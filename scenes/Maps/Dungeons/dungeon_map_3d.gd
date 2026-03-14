extends Node3D
# DungeonMap3D — 3D grid map renderer and radial room-choice UI.

var dungeon    : DungeonRunState
var controller : DungeonController = null
var rotating   = false
var last_mouse_pos

@onready var map_root = $MapRoot

const ROOM_SCENE     = preload("res://scenes/MapRooms/dungeon_room_3d.tscn")
const CORRIDOR_SCENE = preload("res://scenes/MapRooms/room_corridor_3d.tscn")
const ROOM_SPACING   = 2.0

# ── Radial choice state ────────────────────────────────────────────────────────
var _choice_layer    : CanvasLayer = null   # single CanvasLayer for all choice UI
var _pending_pos     : Vector2i = Vector2i(-999, -999)
var _pending_choices : Array    = []        # Array[RoomData]
var _selected_data   : RoomData = null
var _radial_nodes    : Array    = []        # the 3 ring Button nodes
var _detail_node     : Control  = null      # expanded detail card (or null)
var _popped_positions : Dictionary = {}     # Vector2i -> Array[int] of already-popped indices
var _preview_ghosts  : Array    = []        # yellow ghost cubes

# How far the ring buttons orbit from the click point
const RADIAL_RADIUS      = 110.0
# Final resting angles (degrees): top, bottom-left, bottom-right
const RADIAL_ANGLES      = [-90.0, -90.0 + 120.0, -90.0 + 240.0]
# All buttons start spinning from this angle
const RADIAL_START_ANGLE = -90.0
const RING_BTN_W         = 130.0  # expanded oval width
const RING_BTN_H         = 80.0   # circle diameter (height always stays this)
const RING_ROLL_TIME     = 0.38   # wheel roll-out duration
const RING_POP_TIME      = 0.18   # circle→oval pop duration

# Direction vectors for compass (grid space: Y+ = south/down)
const DIR_N = Vector2i( 0, -1)
const DIR_S = Vector2i( 0,  1)
const DIR_W = Vector2i(-1,  0)
const DIR_E = Vector2i( 1,  0)

# Style constants
const C_BG      = Color(0.08, 0.07, 0.06, 0.96)
const C_BORDER  = Color(0.35, 0.28, 0.22, 1.0)
const C_ACCENT  = Color(0.52, 0.42, 0.28, 1.0)
const C_TEXT    = Color(0.88, 0.83, 0.74, 1.0)
const C_DIM     = Color(0.45, 0.40, 0.35, 1.0)
const C_SEL     = Color(0.52, 0.42, 0.28, 0.28)
const C_GHOST   = Color(0.20, 0.60, 1.00, 1.0)
const C_PREVIEW = Color(1.00, 0.85, 0.20, 1.0)
const C_DIR_ON  = Color(0.88, 0.83, 0.74, 1.0)
const C_DIR_OFF = Color(0.30, 0.27, 0.24, 1.0)


func _ready():
	add_to_group("dungeon_map_3d")
	set_process_input(true)
	_setup_environment()
	get_viewport().physics_object_picking = true

var _dungeon_env : Environment = null

func _setup_environment():
	_dungeon_env = Environment.new()
	_dungeon_env.background_mode = Environment.BG_COLOR
	_dungeon_env.background_color = Color(0.08, 0.08, 0.12)
	_dungeon_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_dungeon_env.ambient_light_color = Color(0.6, 0.65, 0.8)
	_dungeon_env.ambient_light_energy = 2.0
	$WorldEnvironment.environment = _dungeon_env

func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_node_ready() and $WorldEnvironment:
			$WorldEnvironment.environment = _dungeon_env if visible else null


func setup(run_state: DungeonRunState, dungeon_controller: DungeonController):
	dungeon    = run_state
	controller = dungeon_controller
	redraw_map()

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			rotating       = event.pressed
			last_mouse_pos = event.position

	if event is InputEventMouseMotion and rotating:
		var delta = event.position - last_mouse_pos
		last_mouse_pos = event.position
		$CameraPivot.rotate_y(-delta.x * 0.01)

func _unhandled_input(event):
	# Any mouse press not consumed by a UI Control (button or card) dismisses the panel.
	if _choice_layer == null:
		return
	if event is InputEventMouseButton and event.pressed:
		dismiss_choice_panel()


# ── Map drawing ────────────────────────────────────────────────────────────────

func redraw_map():
	if dungeon == null:
		return
	print("[MAP] redraw_map grid size=", dungeon.grid.size(), " current_pos=", dungeon.current_pos)

	dismiss_choice_panel()

	var old_pos = map_root.position
	var new_pos = -grid_to_world(dungeon.current_pos)

	for child in map_root.get_children():
		child.queue_free()

	map_root.position = old_pos

	# Wait one frame so queue_free'd nodes are fully removed before re-populating.
	# Without this, old room nodes co-exist with the new ones for one frame,
	# which can cause duplicate click targets and a broken pan tween after battles.
	await get_tree().process_frame

	# Guard: dungeon may have been torn down while we awaited
	if dungeon == null or not is_instance_valid(map_root):
		return

	for pos in dungeon.grid.keys():
		var room : RoomInstance = dungeon.grid[pos]
		var node = ROOM_SCENE.instantiate()
		node.setup(pos, room, controller)
		node.position = grid_to_world(pos)
		map_root.add_child(node)

	_draw_corridors()
	draw_available_positions()

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(map_root, "position", new_pos, 0.35)


func draw_available_positions():
	if controller == null:
		push_error("DungeonMap3D: controller is null in draw_available_positions")
		return
	# Buildable empty slots — blue ghost cubes
	for pos in controller.get_buildable_positions():
		_spawn_ghost(pos, C_GHOST, true)
	# Navigable placed rooms — highlight their existing node with a pulsing outline
	# by setting a distinct emissive tint on the already-spawned room node.
	for pos in controller.get_navigable_positions():
		_highlight_navigable(pos)


func _highlight_navigable(pos: Vector2i) -> void:
	# Find the room node that was already spawned for this position and apply a
	# green emissive tint so the player knows they can walk there.
	for child in map_root.get_children():
		if child.get("grid_pos") == pos and child.get("room_instance") != null:
			var m : MeshInstance3D = child.get_node_or_null("MeshInstance3D")
			if m == null or not m.visible:
				return  # room has a custom model — skip tinting for now
			var mat := StandardMaterial3D.new()
			mat.albedo_color              = Color(0.20, 0.90, 0.40)
			mat.emission_enabled          = true
			mat.emission                  = Color(0.10, 0.60, 0.25)
			mat.emission_energy_multiplier = 0.5
			m.set_surface_override_material(0, mat)
			break


func _spawn_ghost(pos: Vector2i, color: Color = C_GHOST, interactive: bool = true) -> Node3D:
	var node = ROOM_SCENE.instantiate()
	node.position = grid_to_world(pos)
	map_root.add_child(node)
	# setup_ghost must be called after add_child so @onready vars are ready.
	node.setup_ghost(pos, controller, color, interactive)
	return node


# ── Radial choice entry point ─────────────────────────────────────────────────

# Called by DungeonRoom3D when a ghost cube is clicked.
func show_choices_at(grid_pos: Vector2i, choices: Array, screen_pos: Vector2 = Vector2(200, 200)):
	if choices.is_empty():
		return

	# Toggle off if same ghost re-clicked with no selection yet
	if _pending_pos == grid_pos and _choice_layer != null and _selected_data == null:
		dismiss_choice_panel()
		return

	dismiss_choice_panel()
	_pending_pos     = grid_pos
	_pending_choices = choices
	_selected_data   = null

	_choice_layer       = CanvasLayer.new()
	_choice_layer.layer = 10
	add_child(_choice_layer)

	_build_radial_ring(screen_pos, choices)


# ── Phase 1: radial ring ───────────────────────────────────────────────────────

func _build_radial_ring(origin: Vector2, choices: Array):
	_radial_nodes.clear()
	var snap_layer  := _choice_layer
	var prev_popped : Array = _popped_positions.get(_pending_pos, [])

	for i in choices.size():
		var final_angle_deg : float = RADIAL_ANGLES[i % RADIAL_ANGLES.size()]
		var data            : RoomData = choices[i]
		var was_popped      : bool = i in prev_popped

		var wrapper := Control.new()
		wrapper.clip_contents       = true
		wrapper.custom_minimum_size = Vector2(RING_BTN_H, RING_BTN_H)
		wrapper.size                = Vector2(RING_BTN_H, RING_BTN_H)
		wrapper.position            = origin - Vector2(RING_BTN_H * 0.5, RING_BTN_H * 0.5)
		_choice_layer.add_child(wrapper)

		var btn := _make_ring_button("")
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(btn)
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
		_radial_nodes.append(btn)

		var captured_data := data
		btn.pressed.connect(func(): _on_ring_pressed(captured_data, origin))
		_animate_ring_btn(wrapper, btn, origin, RADIAL_START_ANGLE, final_angle_deg, snap_layer, was_popped, data.room_name)


# Phase 1 tween: arc roll-out as a plain circle, springy overshoot.
# If was_popped is true, immediately snaps to oval form once the arc finishes.
func _animate_ring_btn(wrapper: Control, btn: Button, origin: Vector2,
		start_deg: float, final_deg: float, snap_layer: CanvasLayer,
		was_popped: bool = false, room_name: String = "") -> void:
	if not is_instance_valid(snap_layer):
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var arc_cb := _ring_arc_cb.bind(wrapper, origin, start_deg, final_deg)
	tw.tween_method(arc_cb, 0.0, 1.0, RING_ROLL_TIME)
	await tw.finished
	if not is_instance_valid(btn):
		return
	if was_popped:
		# Auto-pop with the same tween as a manual press
		btn.text = room_name
		var final_center := wrapper.position + Vector2(RING_BTN_H * 0.5, RING_BTN_H * 0.5)
		_pop_ring_button(wrapper, btn, final_center)
		return  # _pop_ring_button re-enables mouse_filter on finish
	btn.mouse_filter = Control.MOUSE_FILTER_STOP


# Arc callback: moves wrapper along swept arc, radius 0→RADIAL_RADIUS.
# Width stays RING_BTN_H throughout (circle only, no oval yet).
func _ring_arc_cb(t: float, wrapper: Control, origin: Vector2,
		start_deg: float, final_deg: float) -> void:
	if not is_instance_valid(wrapper):
		return
	var angle_rad : float = deg_to_rad(lerpf(start_deg, final_deg, t))
	var radius    : float = RADIAL_RADIUS * t
	var center    : Vector2 = origin + Vector2(cos(angle_rad), sin(angle_rad)) * radius
	var sz        : Vector2 = Vector2(RING_BTN_H, RING_BTN_H)
	wrapper.custom_minimum_size = sz
	wrapper.size                = sz
	wrapper.position            = center - sz * 0.5


# Phase 1b: pop tween — circle expands to oval and text fades in on first click.
func _pop_ring_button(wrapper: Control, btn: Button, final_center: Vector2) -> void:
	if not is_instance_valid(wrapper):
		return
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(true)
	var pop_cb := _ring_pop_cb.bind(wrapper, btn, final_center)
	tw.tween_method(pop_cb, 0.0, 1.0, RING_POP_TIME)
	await tw.finished
	if is_instance_valid(btn):
		btn.mouse_filter = Control.MOUSE_FILTER_STOP


# Pop callback: width RING_BTN_H→RING_BTN_W, corner radius pill→oval, text fades in.
func _ring_pop_cb(t: float, wrapper: Control, btn: Button, center: Vector2) -> void:
	if not is_instance_valid(wrapper):
		return
	var w      : float = lerpf(RING_BTN_H, RING_BTN_W, t)
	var radius : float = lerpf(RING_BTN_H * 0.5, 14.0, t)
	wrapper.custom_minimum_size = Vector2(w, RING_BTN_H)
	wrapper.size                = Vector2(w, RING_BTN_H)
	wrapper.position            = center - Vector2(w * 0.5, RING_BTN_H * 0.5)
	btn.size                    = Vector2(w, RING_BTN_H)
	for key in ["normal", "hover", "pressed", "focus"]:
		var s : StyleBoxFlat = btn.get_theme_stylebox(key)
		if s is StyleBoxFlat:
			s.set_corner_radius_all(int(radius))


func _make_ring_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text          = label_text
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_theme_font_size_override("font_size", 11)

	var sbox := StyleBoxFlat.new()
	sbox.bg_color     = C_BG
	sbox.border_color = C_BORDER
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(int(RING_BTN_H * 0.5))
	sbox.set_content_margin_all(8)
	var sbox_h := StyleBoxFlat.new()
	sbox_h.bg_color     = C_SEL
	sbox_h.border_color = C_ACCENT
	sbox_h.set_border_width_all(2)
	sbox_h.set_corner_radius_all(int(RING_BTN_H * 0.5))
	sbox_h.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal",  sbox)
	btn.add_theme_stylebox_override("hover",   sbox_h)
	btn.add_theme_stylebox_override("pressed", sbox_h)
	btn.add_theme_stylebox_override("focus",   sbox)
	return btn


# ── Phase 2: detail card ───────────────────────────────────────────────────────

func _on_ring_pressed(data: RoomData, ring_origin: Vector2):
	# Second press on the already-selected bubble = confirm build
	if _selected_data == data:
		var pos := _pending_pos
		_popped_positions.erase(pos)  # choices consumed, reset for this pos
		dismiss_choice_panel()
		controller.build_room(pos, data)
		return
	_selected_data = data
	_show_connection_ghosts(_pending_pos, data)

	# Remove old detail card if any
	if is_instance_valid(_detail_node):
		_detail_node.queue_free()
		_detail_node = null

	# Pop open the pressed button; re-highlight siblings.
	for i in _radial_nodes.size():
		var btn     : Button  = _radial_nodes[i]
		var wrapper : Control = btn.get_parent()
		var is_sel  : bool    = (i < _pending_choices.size() and _pending_choices[i] == data)
		if is_sel:
			btn.text = data.room_name
			var final_center := wrapper.position + wrapper.size * 0.5
			_pop_ring_button(wrapper, btn, final_center)
			# Record that index i has been popped for this position
			if not _popped_positions.has(_pending_pos):
				_popped_positions[_pending_pos] = []
			if i not in _popped_positions[_pending_pos]:
				_popped_positions[_pending_pos].append(i)
		else:
			var sbox := StyleBoxFlat.new()
			sbox.bg_color     = C_BG
			sbox.border_color = C_BORDER
			sbox.set_border_width_all(2)
			sbox.set_corner_radius_all(int(wrapper.size.x * 0.5))
			sbox.set_content_margin_all(8)
			btn.add_theme_stylebox_override("normal", sbox)

	_detail_node = _build_detail_card(data, ring_origin)
	_choice_layer.add_child(_detail_node)


func _build_detail_card(data: RoomData, origin: Vector2) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(260, 0)

	var sbox := StyleBoxFlat.new()
	sbox.bg_color     = C_BG
	sbox.border_color = C_ACCENT
	sbox.set_border_width_all(2)
	sbox.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", sbox)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	# Room name
	var name_lbl := Label.new()
	name_lbl.text                  = data.room_name.to_upper()
	name_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	vbox.add_child(name_lbl)

	# Room type badge
	var type_names : Array = ["Battle", "Elite", "Event", "Shop", "Rest", "Segno", "Boss", "Recruit"]
	var type_lbl := Label.new()
	type_lbl.text               = type_names[data.room_type] if data.room_type < type_names.size() else ""
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_lbl.add_theme_font_size_override("font_size", 10)
	type_lbl.add_theme_color_override("font_color", C_DIM)
	vbox.add_child(type_lbl)

	var div := ColorRect.new()
	div.color                  = C_ACCENT
	div.custom_minimum_size    = Vector2(0, 1)
	vbox.add_child(div)

	# Description
	if data.description != "":
		var desc := Label.new()
		desc.text             = data.description
		desc.autowrap_mode    = TextServer.AUTOWRAP_WORD_SMART
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", C_DIM)
		vbox.add_child(desc)

	# Compass pane
	vbox.add_child(_build_compass(data))

	var div2 := ColorRect.new()
	div2.color               = C_BORDER
	div2.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div2)

	# Confirm / Cancel row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	var confirm := Button.new()
	confirm.text = "BUILD"
	confirm.custom_minimum_size = Vector2(90, 32)
	confirm.add_theme_font_size_override("font_size", 12)
	confirm.add_theme_color_override("font_color", C_TEXT)
	confirm.add_theme_color_override("font_hover_color", C_TEXT)
	var csbox := StyleBoxFlat.new()
	csbox.bg_color     = C_ACCENT
	csbox.border_color = C_BORDER
	csbox.set_border_width_all(1)
	csbox.set_content_margin_all(6)
	confirm.add_theme_stylebox_override("normal",  csbox)
	confirm.add_theme_stylebox_override("hover",   csbox)
	confirm.add_theme_stylebox_override("pressed", csbox)
	confirm.add_theme_stylebox_override("focus",   csbox)
	var captured_data := data
	var captured_pos  := _pending_pos
	confirm.pressed.connect(func():
		_popped_positions.erase(captured_pos)
		dismiss_choice_panel()
		controller.build_room(captured_pos, captured_data)
	)
	btn_row.add_child(confirm)

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.custom_minimum_size = Vector2(80, 32)
	cancel.add_theme_font_size_override("font_size", 11)
	cancel.add_theme_color_override("font_color", C_DIM)
	cancel.add_theme_color_override("font_hover_color", C_TEXT)
	var xsbox := StyleBoxFlat.new()
	xsbox.bg_color     = Color(0, 0, 0, 0)
	xsbox.border_color = C_BORDER
	xsbox.set_border_width_all(1)
	xsbox.set_content_margin_all(6)
	cancel.add_theme_stylebox_override("normal",  xsbox)
	cancel.add_theme_stylebox_override("hover",   xsbox)
	cancel.add_theme_stylebox_override("pressed", xsbox)
	cancel.add_theme_stylebox_override("focus",   xsbox)
	cancel.pressed.connect(dismiss_choice_panel)
	btn_row.add_child(cancel)

	# Position the card: below the ring origin, clamped to viewport
	# We do it after a frame so the card has measured its size
	var vp_size = get_viewport().get_visible_rect().size
	card.position = Vector2(
		clamp(origin.x - 130, 8, vp_size.x - 268),
		clamp(origin.y + RADIAL_RADIUS + 12, 8, vp_size.y - 260)
	)

	return card


func _build_compass(data: RoomData) -> Control:
	# Draws compass on a fixed 100x100 Control using absolute positions.
	# All coordinates are relative to that canvas; centre is (50, 50).
	const W    := 100       # canvas size
	const CX   := 50.0     # centre X
	const CY   := 50.0     # centre Y
	const BAR  := 2.0      # bar thickness
	const BRAD := 16.0     # bar half-length (bar runs from centre ± BRAD)
	const LBL_OFFSET := 30.0  # how far the label centre is from canvas centre
	const FONT_SIZE  := 12

	var exit_dirs : Array = data.get_exit_dirs()
	var n_on : bool = DIR_N in exit_dirs
	var s_on : bool = DIR_S in exit_dirs
	var w_on : bool = DIR_W in exit_dirs
	var e_on : bool = DIR_E in exit_dirs

	var canvas := Control.new()
	canvas.custom_minimum_size = Vector2(W, W)

	# Place a label centred on a point
	var _place_lbl = func(txt: String, cx: float, cy: float, on: bool) -> void:
		var l := Label.new()
		l.text = txt
		l.add_theme_font_size_override("font_size", FONT_SIZE)
		l.add_theme_color_override("font_color", C_DIR_ON if on else C_DIR_OFF)
		# Size the label to a fixed box so we can centre it
		l.custom_minimum_size = Vector2(20, 18)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		l.position = Vector2(cx - 10.0, cy - 9.0)
		canvas.add_child(l)

	# Place a bar (ColorRect) centred on a point
	var _place_bar = func(cx: float, cy: float, bw: float, bh: float, on: bool) -> void:
		var r := ColorRect.new()
		r.color = C_DIR_ON if on else C_DIR_OFF
		r.custom_minimum_size = Vector2(bw, bh)
		r.position = Vector2(cx - bw * 0.5, cy - bh * 0.5)
		canvas.add_child(r)

	# N  — label at top, bar from label down to centre
	_place_lbl.call("N", CX, CY - LBL_OFFSET, n_on)
	_place_bar.call(CX, CY - BRAD * 0.5, BAR, BRAD, n_on)

	# S  — bar from centre down to label
	_place_bar.call(CX, CY + BRAD * 0.5, BAR, BRAD, s_on)
	_place_lbl.call("S", CX + 1, CY + LBL_OFFSET, s_on)

	# W  — label at left, bar from label right to centre
	_place_lbl.call("W", CX - LBL_OFFSET, CY, w_on)
	_place_bar.call(CX - BRAD * 0.5, CY, BRAD, BAR, w_on)

	# E  — bar from centre right to label
	_place_bar.call(CX + BRAD * 0.5, CY, BRAD, BAR, e_on)
	_place_lbl.call("E", CX + LBL_OFFSET, CY, e_on)

	# Centre dot
	var dot := ColorRect.new()
	dot.color = C_DIM
	dot.custom_minimum_size = Vector2(4, 4)
	dot.position = Vector2(CX - 2.0, CY - 2.0)
	canvas.add_child(dot)

	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(0, 108)
	wrap.add_child(canvas)
	return wrap


# ── Corridors ─────────────────────────────────────────────────────────────────

func _draw_corridors(is_new_build_pair: Array = []) -> void:
	# Draw a corridor between every mutually-connected pair of placed rooms.
	for pair in controller.get_all_connected_pairs():
		var pos_a : Vector2i = pair[0]
		var pos_b : Vector2i = pair[1]
		var node := CORRIDOR_SCENE.instantiate() as Node3D
		# Set endpoints BEFORE add_child so _ready() can read them.
		node.from_world = grid_to_world(pos_a)
		node.to_world   = grid_to_world(pos_b)
		node.is_new_build = (pair in is_new_build_pair)
		map_root.add_child(node)
		if node.is_new_build:
			node.play_build_animation()


# ── Connection preview ghosts ──────────────────────────────────────────────────

func _show_connection_ghosts(origin: Vector2i, data: RoomData):
	for g in _preview_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_preview_ghosts.clear()

	var dirs : Array = data.get_exit_dirs()
	for offset in dirs:
		var target : Vector2i = origin + offset
		if dungeon.grid.has(target):
			continue
		if target == origin:
			continue
		var ghost = _spawn_ghost(target, C_PREVIEW, false)
		_preview_ghosts.append(ghost)


# ── Dismiss ────────────────────────────────────────────────────────────────────

func dismiss_choice_panel():
	if is_instance_valid(_choice_layer):
		_choice_layer.queue_free()
	_choice_layer  = null
	_detail_node   = null
	_radial_nodes.clear()

	for g in _preview_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_preview_ghosts.clear()

	_pending_pos     = Vector2i(-999, -999)
	_pending_choices = []
	_selected_data   = null

	if controller != null:
		controller.cancel_build()


# ── Helpers ────────────────────────────────────────────────────────────────────

func grid_to_world(pos: Vector2i) -> Vector3:
	return Vector3(pos.x * ROOM_SPACING, 0, pos.y * ROOM_SPACING)
