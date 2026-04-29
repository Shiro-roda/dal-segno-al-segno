

extends Node3D
# DungeonMap3D — 3D grid map renderer and radial room-choice UI.

var dungeon    : DungeonRunState
var controller : DungeonController = null
var rotating   = false    # middle-mouse rotate
var _panning   = false    # left-click pan (active)
var _pan_armed = false    # press seen, waiting for drag threshold
var _pan_press_pos : Vector2 = Vector2.ZERO
const PAN_DRAG_THRESHOLD := 6.0
var _room_mesh_hovered := false  # true whenever the cursor is over any room mesh

var _hop_path : Array = []  # pending hop positions; non-empty = hop in progress

# ── Player position marker ─────────────────────────────────────────────────────
var _player_marker     : MeshInstance3D = null
var _marker_tween      : Tween          = null
var _marker_bounce_t   : float          = 0.0   # drives the idle bounce sine wave
var _pending_marker_target : Vector2i   = Vector2i(-999, -999)  # set before redraw; marker will animate to this on arrival
var _prev_marker_world_pos : Vector3    = Vector3.ZERO  # saved before queue_free so the new marker knows where to arc from
const MARKER_COLOR     := Color(0.718, 0.718, 0.353, 1.0)  # beige
const MARKER_HOVER_Y   := 1.4   # resting height above room surface
const MARKER_BOUNCE_AMP := 0.22  # idle bounce amplitude
const MARKER_BOUNCE_SPD := 2.2   # idle bounce frequency (rad/s)
const MARKER_JUMP_H    := 1.6   # arc peak height when travelling between rooms
const MARKER_TRAVEL_T  := 0.25   # travel tween duration in seconds
var last_mouse_pos : Vector2 = Vector2.ZERO

# ── Camera orbit ──────────────────────────────────────────────────────────────
const CAM_STEPS      := 8                        # 8 snap positions around Y
const CAM_STEP_DEG   := 360.0 / CAM_STEPS        # 45° each
const CAM_SNAP_TIME  := 0.22                     # tween duration in seconds
var   _cam_step      : int   = 0                 # current step (0–7)
var   _cam_tween     : Tween = null              # active snap tween

@onready var map_root = $MapRoot

const ROOM_SCENE     = preload("res://Rooms/Models/Scenes/dungeon_room_3d.tscn")
const CORRIDOR_SCENE = preload("res://Rooms/Models/Scenes/room_corridor_3d.tscn")
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
var _reroll_btn      : Button   = null      # center reroll button
var _road_btn_wrap   : Control  = null      # wrapper for the downward road-tile button
var _room_info_layer : CanvasLayer = null   # popup for right-click room info

# RGB channel mask: bit 0=R, bit 1=G, bit 2=B. All on by default.
# Removing a channel reveals its complementary overlay.
# One channel left = single-channel text mode.
var dungeon_channel_mask : int = 0b111
const CHAN_R := 1  # bit 0
const CHAN_G := 2  # bit 1
const CHAN_B := 4  # bit 2

# Legacy alias so toggle_segno_overlay still works via HUD § button.
var _segno_overlay_visible : bool  = false
var _segno_overlay_nodes   : Array = []  # overlay mesh nodes
# Per-channel persistent text pools. Built once on first toggle, then shown/hidden.
var _chan_text_r     : Array = []  # MeshInstance3D nodes for red-only mode
var _chan_text_g     : Array = []  # MeshInstance3D nodes for green-only mode
var _chan_text_b     : Array = []  # MeshInstance3D nodes for blue-only mode
var _chan_text_built : bool  = false  # true once the pools have been spawned
var _chan_text_timers : Dictionary = {}  # node -> float seconds until relocate

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
const REROLL_BTN_SIZE    = 50.0   # center reroll button diameter
const ROAD_BTN_ANGLE     = 90.0   # straight down (degrees)

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


func _process(delta: float) -> void:
	_tick_channel_text(delta)
	_tick_marker_bounce(delta)


func _tick_marker_bounce(delta: float) -> void:
	if not is_instance_valid(_player_marker):
		return
	if is_instance_valid(_marker_tween) and _marker_tween.is_running():
		return  # don't fight the travel tween
	_marker_bounce_t += delta * MARKER_BOUNCE_SPD
	var base_pos := grid_to_world(dungeon.current_pos)
	_player_marker.position = base_pos + Vector3(0.0,
		MARKER_HOVER_Y + sin(_marker_bounce_t) * MARKER_BOUNCE_AMP, 0.0)


func _tick_channel_text(delta: float) -> void:
	if not _chan_text_built:
		return
	var active_pool : Array
	var bits_on := 0
	var active_chan := 0
	for bit in [CHAN_R, CHAN_G, CHAN_B]:
		if dungeon_channel_mask & bit:
			bits_on += 1; active_chan = bit
	if bits_on != 1: return
	match active_chan:
		CHAN_R: active_pool = _chan_text_r
		CHAN_G: return  # green is self-managing
		CHAN_B: active_pool = _chan_text_b
	for node in active_pool:
		if not is_instance_valid(node): continue
		var t : float = _chan_text_timers.get(node, randf_range(1.0, 5.0))
		t -= delta
		if t <= 0.0:
			# Relocate to a new random position and reset timer
			(node as Node3D).position = Vector3(
				randf_range(-28.0, 28.0),
				randf_range(-4.0, 8.0),
				randf_range(-30.0, 18.0))
			t = randf_range(1.5, 6.0)
		_chan_text_timers[node] = t
	_update_green_visibility()

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
	# Middle-mouse drag — rotate the camera pivot (free rotation, always available)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		rotating       = event.pressed
		last_mouse_pos = event.position

	if event is InputEventMouseMotion and (rotating or _panning or _pan_armed):
		var mouse_delta : Vector2 = event.position - last_mouse_pos
		last_mouse_pos = event.position
		if rotating:
			$CameraPivot.rotate_y(-mouse_delta.x * 0.01)
		if _pan_armed and not _panning:
			if event.position.distance_to(_pan_press_pos) >= PAN_DRAG_THRESHOLD:
				_panning   = true
				_pan_armed = false
		if _panning:
			# Use the pivot's own basis so pan is always aligned to screen axes
			var basis : Basis = $CameraPivot.global_transform.basis
			$CameraPivot.position -= basis.x * mouse_delta.x * 0.05
			$CameraPivot.position -= basis.z * mouse_delta.y * 0.05
			$CameraPivot.position.y = 0.0
			get_viewport().set_input_as_handled()

	# A / D — snap camera 45° left / right, always available in dungeon
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_A:
			_rotate_cam_step(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_D:
			_rotate_cam_step(1)
			get_viewport().set_input_as_handled()



## Snap the camera to the next/previous 45° step around the Y axis.
func _rotate_cam_step(dir: int) -> void:
	_cam_step = (_cam_step + dir + CAM_STEPS) % CAM_STEPS
	var target_y := deg_to_rad(_cam_step * CAM_STEP_DEG)
	if is_instance_valid(_cam_tween):
		_cam_tween.kill()
	# Find the shortest angular path by offsetting target until within +-PI of current.
	var current_y : float = $CameraPivot.rotation.y
	var delta_y : float = fmod(target_y - current_y + PI, TAU) - PI
	var snap_y : float = current_y + delta_y
	_cam_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_cam_tween.tween_property($CameraPivot, "rotation:y", snap_y, CAM_SNAP_TIME)


## Move the player one step in the given grid direction if the target room is
## connected and the controller is available. Arrow keys map to absolute grid
## directions (Up = North / -Y, Down = South / +Y, Left = West / -X, Right = East / +X).
func _try_move_player(dir: Vector2i) -> void:
	if controller == null or dungeon == null:
		return
	var target : Vector2i = dungeon.current_pos + dir
	_pending_marker_target = target
	controller.move_to_room(target)


## Walk the player along a pre-computed path one room at a time, waiting for
## redraw_map() to finish animating before each hop.
## The first element of `path` is the player's current position; it is skipped.
func _hop_along_path(path: Array) -> void:
	_hop_path = path.duplicate()
	if _hop_path.size() <= 1:
		_hop_path.clear()
		return
	_hop_path.pop_front()  # discard current position
	_advance_hop()


func _advance_hop() -> void:
	if _hop_path.is_empty() or controller == null or dungeon == null:
		_hop_path.clear()
		return
	var next_pos : Vector2i = _hop_path.pop_front()
	_pending_marker_target = next_pos
	controller.move_to_room(next_pos)
	# redraw_map() is called inside move_to_room -> enter_current_room.
	# We wait one animation frame (MARKER_TRAVEL_T) before advancing further.
	if not _hop_path.is_empty():
		await get_tree().create_timer(MARKER_TRAVEL_T + 0.05).timeout
		_advance_hop()


## Called by DungeonRoom3D on mouse_entered/mouse_exited to track hover state.
## Pan is blocked whenever the cursor is over any room mesh.
func notify_room_hovered(hovered: bool) -> void:
	_room_mesh_hovered = hovered


## Spawn the player marker sphere and optionally animate it from a prior position.
## Pass a valid grid pos in animate_from to trigger the jump arc;
## pass Vector2i(-999,-999) to just place it at current_pos with no animation.
func _spawn_player_marker_at(animate_to: Vector2i) -> void:
	if is_instance_valid(_player_marker):
		_player_marker.queue_free()
	if is_instance_valid(_marker_tween):
		_marker_tween.kill()
	_player_marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	_player_marker.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color               = MARKER_COLOR
	mat.emission_enabled           = true
	mat.emission                   = MARKER_COLOR
	mat.emission_energy_multiplier = 5.0
	_player_marker.set_surface_override_material(0, mat)
	map_root.add_child(_player_marker)

	var dest_pos : Vector2i = dungeon.current_pos  # where the player actually is now
	var dest_world : Vector3 = grid_to_world(dest_pos) + Vector3(0, MARKER_HOVER_Y, 0)

	# If a pending target was set, a real move happened.
	# Spawn the marker at the saved old world position and arc to the new one.
	if animate_to != Vector2i(-999, -999) and _prev_marker_world_pos != Vector3.ZERO:
		_player_marker.position = _prev_marker_world_pos
		move_marker_to_world(_prev_marker_world_pos, dest_world)
	else:
		_player_marker.position = dest_world
	_prev_marker_world_pos = Vector3.ZERO


## Animate the marker jumping between two world-space positions.
func move_marker_to_world(from: Vector3, to: Vector3) -> void:
	if is_instance_valid(_marker_tween):
		_marker_tween.kill()
	# Quadratic Bézier arc: control point is directly above the midpoint.
	# tween_method evaluates the curve every frame, giving a smooth parabola
	# instead of the sharp angle you get from two straight-line segments.
	var ctrl : Vector3 = (from + to) * 0.5 + Vector3(0, MARKER_JUMP_H, 0)
	_marker_tween = create_tween()
	_marker_tween.tween_method(
		func(t: float) -> void:
			var p : Vector3 = (1.0 - t) * (1.0 - t) * from \
							+ 2.0 * (1.0 - t) * t * ctrl \
							+ t * t * to
			_player_marker.position = p,
		0.0, 1.0, MARKER_TRAVEL_T
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)





func _unhandled_input(event):
	# Any click dismisses the room info popup if open.
	if event is InputEventMouseButton and event.pressed and is_instance_valid(_room_info_layer):
		_dismiss_room_info()

	# Left-click drag — pan the camera. Only fires if no UI Control consumed the click.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var can_pan := dungeon == null or not dungeon.is_building_locked()
		if event.pressed and can_pan:
			if not _room_mesh_hovered:
				_pan_armed     = true
				_pan_press_pos = event.position
				last_mouse_pos = event.position
		elif not event.pressed:
			_pan_armed = false
			_panning   = false

	# Q/W/E toggle R/G/B channels — only while the dungeon layer is active.
	# During battle the dungeon layer is hidden; Change Lens owns the shader there.
	if event is InputEventKey and event.pressed and not event.echo:
		var dl := get_tree().get_first_node_in_group("dungeon_layer")
		var in_dungeon : bool = dl != null and (dl as CanvasLayer).visible
		if in_dungeon:
			match event.keycode:
				KEY_Q:
					toggle_channel(CHAN_R)
					get_viewport().set_input_as_handled()
				KEY_W:
					toggle_channel(CHAN_G)
					get_viewport().set_input_as_handled()
				KEY_E:
					toggle_channel(CHAN_B)
					get_viewport().set_input_as_handled()
				KEY_UP:
					_try_move_player(DIR_N)
					get_viewport().set_input_as_handled()
				KEY_DOWN:
					_try_move_player(DIR_S)
					get_viewport().set_input_as_handled()
				KEY_LEFT:
					_try_move_player(DIR_W)
					get_viewport().set_input_as_handled()
				KEY_RIGHT:
					_try_move_player(DIR_E)
					get_viewport().set_input_as_handled()
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

	# Save marker world position before destroying it so the new one can arc from there.
	if is_instance_valid(_player_marker):
		_prev_marker_world_pos = _player_marker.position

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
	if _hop_path.is_empty():
		draw_available_positions()
	# Capture the pending target before _spawn_player_marker clears state,
	# then animate the marker from the old room to the new one.
	var _animate_to := _pending_marker_target
	_pending_marker_target = Vector2i(-999, -999)
	_spawn_player_marker_at(_animate_to)
	_segno_overlay_nodes.clear()   # freed with map_root children above
	# channel_overlay_nodes are freed by group membership — no separate list needed
	# channel text pools are persistent — visibility managed by _apply_channel_state
	_apply_channel_state()

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(map_root, "position", new_pos, 0.75)


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
	for child in map_root.get_children():
		if child.get("grid_pos") != pos or child.get("room_instance") == null:
			continue
		# Try the placeholder cube first; fall back to any MeshInstance3D in a model.
		var m : MeshInstance3D = child.get_node_or_null("MeshInstance3D")
		if m == null or not m.visible:
			# Room has a custom model — tint its first MeshInstance3D child.
			for sub in child.get_children():
				var mi := sub.find_child("*", true, false)
				if mi is MeshInstance3D:
					m = mi as MeshInstance3D
					break
				if sub is MeshInstance3D:
					m = sub as MeshInstance3D
					break
		if m == null:
			break
		var mat := StandardMaterial3D.new()
		mat.albedo_color              = Color(0.20, 0.90, 0.40)
		mat.emission_enabled          = true
		mat.emission                  = Color(0.10, 0.60, 0.25)
		mat.emission_energy_multiplier = 0.5
		mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.set_surface_override_material(0, mat)
		break


## -----------------------------------------------------------------------
## CHANNEL TEXT TABLE
## -----------------------------------------------------------------------
## Add entries here. Each entry:
##   text      — string to display
##   channel   — "red", "green", or "blue"
##   condition — string key (see _check_condition). "" = always eligible.
## -----------------------------------------------------------------------
const CHANNEL_TEXT_TABLE : Array = [
	# ── RED —──────────────────────────────────────
	{"text": "they are fragile under their skin", "channel": "red", "condition": ""},
	{"text": "", "channel": "red", "condition": ""},
	{"text": "", "channel": "red", "condition": "has_segno"},
	{"text": "", "channel": "red", "condition": "has_segno"},
	{"text": "", "channel": "red", "condition": ""},
	{"text": "", "channel": "red", "condition": "g.p."},
	{"text": "", "channel": "red", "condition": "low_hp"},
	{"text": "", "channel": "red", "condition": "al_segno"},
	{"text": "", "channel": "red", "condition": ""},
	{"text": "", "channel": "red", "condition": "high_transit"},
	{"text": "be wise", "channel": "red", "condition": "da_capo"},
	{"text": "you are still frail", "channel": "red", "condition": "da_capo"},
	{"text": "feed from the weaker ones", "channel": "red", "condition": "da_capo"},
	{"text": "", "channel": "red", "condition": "dal_segno"},
	{"text": "", "channel": "red", "condition": "dal_segno"},
	{"text": "safe now", "channel": "red", "condition": "dc_al_segno"},
	{"text": "it is safe now", "channel": "red", "condition": "dc_al_segno"},
	{"text": "the prey wakes again", "channel": "red", "condition": "ds_al_segno"},
	{"text": "they hear your song", "channel": "red", "condition": "ds_al_segno"},
	{"text": "", "channel": "red", "condition": "al_fine"},
	{"text": "", "channel": "red", "condition": "al_fine"},
	{"text": "", "channel": "red", "condition": "al_fine"},
	{"text": "the hunt will begin again", "channel": "red", "condition": "g.p."},
	{"text": "take your time", "channel": "red", "condition": "g.p."},
	# ── GREEN —───────────────────────────────────
	{"text": "Child of Priam...", "channel": "green", "condition": ""},
	{"text": "", "channel": "green", "condition": ""},
	{"text": "", "channel": "green", "condition": "has_segno"},
	{"text": "", "channel": "green", "condition": ""},
	{"text": "", "channel": "green", "condition": "cleared_room"},
	{"text": "", "channel": "green", "condition": "party_size_2"},
	{"text": "", "channel": "green", "condition": "has_segno"},
	{"text": "You should rest", "channel": "green", "condition": "low_hp"},
	{"text": "", "channel": "green", "condition": "g.p."},
	{"text": "", "channel": "green", "condition": ""},
	{"text": "I fear for my child.", "channel": "green", "condition": "da_capo"},
	{"text": "Please take care of it...", "channel": "green", "condition": "da_capo"},
	{"text": "I fear for my child.", "channel": "green", "condition": "dc_al_segno"},
	{"text": "Please take care of it...", "channel": "green", "condition": "dc_al_segno"},
	{"text": "were you the price He paid?", "channel": "green", "condition": "dal_segno"},
	{"text": "Was He yours?", "channel": "green", "condition": "dal_segno"},
	{"text": "", "channel": "green", "condition": "dc_al_segno"},
	{"text": "", "channel": "green", "condition": "ds_al_segno"},
	{"text": "", "channel": "green", "condition": "g.p."},
	{"text": "", "channel": "green", "condition": "al_fine"},
	# ── BLUE —─────────────────────────────────────
	{"text": "", "channel": "blue", "condition": ""},
	{"text": "", "channel": "blue", "condition": ""},
	{"text": "", "channel": "blue", "condition": "has_segno"},
	{"text": "", "channel": "blue", "condition": ""},
	{"text": "", "channel": "blue", "condition": "high_transit"},
	{"text": "", "channel": "blue", "condition": ""},
	{"text": "", "channel": "blue", "condition": "g.p."},
	{"text": "", "channel": "blue", "condition": "al_segno"},
	{"text": "", "channel": "blue", "condition": "has_segno"},
	{"text": "", "channel": "blue", "condition": ""},
	{"text": "MAKE YOUR MARK IN THE HOUSE OF WORSHIP", "channel": "blue", "condition": "da_capo"},
	{"text": "FORWARD", "channel": "blue", "condition": "da_capo"},
	{"text": "", "channel": "blue", "condition": "dal_segno"},
	{"text": "", "channel": "blue", "condition": "dal_segno"},
	{"text": "", "channel": "blue", "condition": "dc_al_segno"},
	{"text": "THE SUN IS GONE", "channel": "blue", "condition": "ds_al_segno"},
	{"text": "", "channel": "blue", "condition": "al_fine"},
	{"text": "", "channel": "blue", "condition": "al_fine"},
	{"text": "", "channel": "blue", "condition": "al_fine"},
	{"text": "", "channel": "blue", "condition": "g.p."},
]


## Evaluate a condition key against live run state.
## Returns true if the entry is eligible to spawn.
func _check_condition(cond: String) -> bool:
	if cond == "":
		return true
	var dr : DungeonRunState = dungeon
	var rs : RunState = dungeon.run_state if dungeon else null
	if dr == null:
		return cond == ""
	match cond:
		"has_segno":
			return dr.segno_pos != Vector2i(-999, -999) \
				or not dr.past_segno_positions.is_empty()
		"g.p.":
			return dr.phase == DungeonRunState.Phase.GRAND_PAUSE
		"al_segno":
			return dr.phase == DungeonRunState.Phase.DS_AL_SEGNO \
				or dr.phase == DungeonRunState.Phase.DC_AL_SEGNO \
				or dr.phase == DungeonRunState.Phase.AL_FINE
		"cleared_room":
			for pos in dr.grid:
				var room : RoomInstance = dr.grid[pos]
				if room != null and room.cleared:
					return true
			return false
		"party_size_2":
			return rs != null and rs.party_members.size() >= 2
		"party_size_3":
			return rs != null and rs.party_members.size() >= 3
		"low_hp":
			if rs == null: return false
			for m in rs.party_members:
				var pm := m as PartyMemberData
				var max_hp : int = pm.character.base_max_hp + pm.bonus_max_hp
				if max_hp > 0 and float(pm.current_hp) / float(max_hp) < 0.30:
					return true
			return false
		"high_transit":
			return dr.segno_transit_count >= 2
		"da_capo":
			return dr.phase == DungeonRunState.Phase.DA_CAPO
		"dal_segno":
			return dr.phase == DungeonRunState.Phase.DAL_SEGNO
		"dc_al_segno":
			return dr.phase == DungeonRunState.Phase.DC_AL_SEGNO
		"ds_al_segno":
			return dr.phase == DungeonRunState.Phase.DS_AL_SEGNO
		"al_fine":
			return dr.phase == DungeonRunState.Phase.AL_FINE
	return false


## Filter CHANNEL_TEXT_TABLE to eligible entries for one channel,
## shuffle, and return up to `limit` text strings.
func _get_channel_texts(channel: String, limit: int) -> Array:
	var pool : Array = []
	for entry in CHANNEL_TEXT_TABLE:
		if entry["channel"] != channel:
			continue
		if _check_condition(entry["condition"]):
			pool.append(entry["text"])
	return pool


## Draw faint radius markers showing the minimum exploration distance around
## the current Segno position. Only visible during DAL_SEGNO phase.
## Tiles cover every cell strictly inside dungeon.segno_min_dist of any anchor.
## from any past or current Segno position.
## Toggle one RGB channel bit and rebuild all overlays.
func toggle_channel(chan: int) -> void:
	# Blocked during battle — Change Lens owns the shader there.
	var bl := get_tree().get_first_node_in_group("battle_layer")
	if bl != null and (bl as CanvasLayer).visible:
		return
	dungeon_channel_mask ^= chan
	# Drive the global TV shader channel_strength directly.
	var mesh := get_tree().root.get_node_or_null("GameRoot/TVOverlay/MeshInstance2D")
	if mesh:
		var mat := mesh.material as ShaderMaterial
		if mat:
			var r : float = 1.0 if dungeon_channel_mask & CHAN_R else 0.0
			var g : float = 1.0 if dungeon_channel_mask & CHAN_G else 0.0
			var b : float = 1.0 if dungeon_channel_mask & CHAN_B else 0.0
			mat.set_shader_parameter("channel_strength", Vector3(r, g, b))
	# Segno exclusion overlay: only visible when R+G are on and B is off
	# (mask == 0b011). Yellow = R+G, which is the overlay's colour.
	_segno_overlay_visible = (dungeon_channel_mask == (CHAN_R | CHAN_G))
	# Drive audio: removed_mask is the inverse of the channel mask.
	var removed_mask : int = (~dungeon_channel_mask) & 0b111
	AudioManagerAuto.update_dungeon_color_layers(removed_mask)
	_apply_channel_state()


## Reset all channels to full RGB (called when leaving the dungeon).
func reset_channels() -> void:
	dungeon_channel_mask = 0b111
	_segno_overlay_visible = false
	# Clear persistent text pools so they rebuild on next dungeon session.
	for pool in [_chan_text_r, _chan_text_g, _chan_text_b]:
		for n in pool:
			if is_instance_valid(n): n.queue_free()
	_chan_text_r.clear()
	_chan_text_g.clear()
	_chan_text_b.clear()
	_chan_text_built = false
	# Reset stem volumes instantly — no tween — so the battle track
	# can take ownership of volume immediately without a fade fighting it.
	AudioManagerAuto.reset_dungeon_stem_volumes()
	for node in get_tree().get_nodes_in_group("phase_hud"):
		if node.has_method("set_channel_mask"):
			node.set_channel_mask(dungeon_channel_mask)


## Legacy entry point kept for the HUD § button.
func toggle_segno_overlay() -> void:
	toggle_channel(CHAN_B)


## Rebuild all channel-driven visuals and notify HUD.
func _apply_channel_state() -> void:
	_rebuild_segno_overlay()      # Yellow overlay when B is off
	_rebuild_channel_overlays()   # Cyan / Magenta overlays
	_rebuild_channel_text()       # Floating text when only one channel active
	for node in get_tree().get_nodes_in_group("phase_hud"):
		if node.has_method("set_channel_mask"):
			node.set_channel_mask(dungeon_channel_mask)


## Rebuild the Segno exclusion overlay. Called on redraw and on toggle.
## When overlay is hidden, clears all overlay nodes silently.
## When visible, fills each grid cell inside the min-dist exclusion zone
## around every past and current Segno anchor with a flat coloured quad.
func _rebuild_segno_overlay() -> void:
	# Clear previous overlay nodes (safe to call even when list is already empty).
	for n in _segno_overlay_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_segno_overlay_nodes.clear()

	if not _segno_overlay_visible:
		return
	if dungeon == null:
		return

	# Anchors: all past positions + live segno_pos.
	# If no segno has been placed yet (DA_CAPO), use current_pos as the anchor
	# since that is what _find_next_segno_candidates excludes around.
	var anchors : Array = dungeon.past_segno_positions.duplicate()
	if dungeon.segno_pos != Vector2i(-999, -999) and dungeon.segno_pos not in anchors:
		anchors.append(dungeon.segno_pos)
	if anchors.is_empty():
		anchors.append(dungeon.current_pos)

	var min_dist : int = dungeon.segno_min_dist

	# Build the exclusion set: every cell whose Manhattan distance from
	# ANY anchor is strictly less than min_dist.
	var excluded : Dictionary = {}
	for anchor in anchors:
		var a : Vector2i = anchor as Vector2i
		for dx in range(-min_dist + 1, min_dist):
			for dy in range(-min_dist + 1, min_dist):
				if abs(dx) + abs(dy) < min_dist:
					excluded[a + Vector2i(dx, dy)] = true

	# Spawn a flat quad at each excluded cell.
	for cell in excluded.keys():
		var node := _spawn_exclusion_tile(cell as Vector2i, anchors, min_dist)
		_segno_overlay_nodes.append(node)


## Spawn one flat exclusion tile. Tint varies: Segno anchor cells are brighter.
func _spawn_exclusion_tile(pos: Vector2i, anchors: Array, min_dist: int) -> Node3D:
	var node := Node3D.new()
	node.position = grid_to_world(pos)
	map_root.add_child(node)

	var mi   := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(ROOM_SPACING * 0.92, 0.04, ROOM_SPACING * 0.92)
	mi.mesh = mesh
	mi.position = Vector3(0.0, 0.06, 0.0)

	# Colour: anchor cell = gold, inner zone = red-orange, ring edge = amber.
	var is_anchor : bool = pos in anchors
	var min_anchor_dist : int = min_dist
	for a in anchors:
		var d : int = abs(pos.x - (a as Vector2i).x) + abs(pos.y - (a as Vector2i).y)
		if d < min_anchor_dist:
			min_anchor_dist = d
	var t : float = float(min_anchor_dist) / float(min_dist)  # 0 at anchor, 1 at edge
	var col : Color
	if is_anchor:
		col = Color(0.95, 0.80, 0.10, 1.0)  # gold — anchor
	else:
		# Red-orange close to anchor, fading to amber near the edge.
		col = Color(0.85 + t * 0.05, 0.20 + t * 0.45, 0.05, 1.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color              = col
	mat.emission_enabled          = true
	mat.emission                  = Color(col.r * 0.7, col.g * 0.4, 0.02)
	mat.emission_energy_multiplier = 1.0
	mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency              = BaseMaterial3D.TRANSPARENCY_DISABLED
	mi.set_surface_override_material(0, mat)
	node.add_child(mi)
	return node


## Cyan overlay (R off) and Magenta overlay (G off).
## Content is stubbed — fill in what each channel reveals.
func _rebuild_channel_overlays() -> void:
	# Clear existing CMY overlay nodes (reuse _segno_overlay_nodes pool would mix
	# concerns, so channel overlays manage their own list via tags).
	for n in get_tree().get_nodes_in_group("channel_overlay_node"):
		if is_instance_valid(n) and n.get_parent() == map_root:
			n.queue_free()

	# —— Cyan (R removed) ——
	if not (dungeon_channel_mask & CHAN_R):
		_build_cyan_overlay()

	# —— Magenta (G removed) ——
	if not (dungeon_channel_mask & CHAN_G):
		_build_magenta_overlay()


## Stub: build the Cyan overlay (R channel removed).
## Replace the pass with room-tile or label spawning logic.
func _build_cyan_overlay() -> void:
	pass  # TODO: cyan overlay content


## Stub: build the Magenta overlay (G channel removed).
func _build_magenta_overlay() -> void:
	pass  # TODO: magenta overlay content


## Show or hide the persistent channel text pools based on current mask.
## Builds all three pools on first call.
func _rebuild_channel_text() -> void:
	if not _chan_text_built:
		_spawn_red_channel_text()
		_spawn_green_channel_text()
		_spawn_blue_channel_text()
		_chan_text_built = true

	var bits_on : int = 0
	var active_chan : int = 0
	for bit in [CHAN_R, CHAN_G, CHAN_B]:
		if dungeon_channel_mask & bit:
			bits_on += 1
			active_chan = bit

	var show_r : bool = bits_on == 1 and active_chan == CHAN_R
	var show_b : bool = bits_on == 1 and active_chan == CHAN_B
	var show_g : bool = bits_on == 1 and active_chan == CHAN_G


	for n in _chan_text_r:
		if is_instance_valid(n): n.visible = show_r
	for n in _chan_text_b:
		if is_instance_valid(n): n.visible = show_b
	for n in _chan_text_g:
		if is_instance_valid(n): n.visible = show_g

func _update_green_visibility() -> void:
	var show_g := dungeon_channel_mask == CHAN_G
	for n in _chan_text_g:
		if is_instance_valid(n):
			n.visible = show_g

## ── Channel text helpers ────────────────────────────────────────────────────

## Collect room world positions and names for text spawning.
func _get_room_label_data() -> Array:
	var out : Array = []
	if dungeon == null:
		return out
	for pos in dungeon.grid.keys():
		var room : RoomInstance = dungeon.grid[pos]
		if room == null or room.room_data == null:
			continue
		out.append({
			"world": grid_to_world(pos as Vector2i),
			"name":  room.room_data.room_name,
			"pos":   pos
		})
	return out


## Shared helper: spawn a TextMesh on a MeshInstance3D with the flicker shader.
## Appends to `pool`, starts hidden. Rotation points face toward camera (downward tilt).
func _spawn_text_mesh(txt: String, col: Color,
		flicker_speed: float, flicker_intensity: float,
		world_pos: Vector3, pool: Array) -> MeshInstance3D:
	var font   := load("res://UI/Themes/Fonts/SpaceMono-Bold.ttf") as Font
	var shader := load("res://Shaders/flicker_text.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = 1
	mat.set_shader_parameter("text_color",    Vector3(col.r, col.g, col.b))
	mat.set_shader_parameter("flicker_speed",     flicker_speed)
	mat.set_shader_parameter("flicker_intensity", flicker_intensity)
	mat.set_shader_parameter("uv_aspect",         10.0)
	mat.set_shader_parameter("pixel_size",        5.0)
	mat.set_shader_parameter("shadow_color",      Vector3(0.0, 0.0, 0.0))
	mat.set_shader_parameter("shadow_pixel_steps",Vector2(0.0, 0.0))
	var mesh := TextMesh.new()
	if font: mesh.font = font
	mesh.text      = txt
	mesh.font_size = 128
	mesh.depth     = 0.0
	mesh.add_uv2   = true   # required for UV-based shader effects
	mesh.material  = mat
	var mi := MeshInstance3D.new()
	mi.mesh     = mesh
	mi.position = world_pos
	# Tilt to face roughly toward the dungeon camera (looking down ~50 degrees)
	# Camera is at y=18,z=15 looking toward (0,-0.766,-0.643) — 50deg below -Z.
	# Text default normal points +Z. Rotate -50 deg X so top tilts toward +Z,
	# making the face point upward toward the camera.
	mi.rotation_degrees = Vector3(-50.0, 0.0, 0.0)
	mi.visible  = false
	# Parent to CameraPivot so the text inherits Y rotation and moves with the camera.
	$CameraPivot.add_child(mi)
	pool.append(mi)
	return mi


## RED channel — stark strobe. Large uppercase text high in the dungeon sky.
func _spawn_red_channel_text() -> void:
	var texts := _get_channel_texts("red", 6)
	if texts.is_empty(): return
	texts.shuffle()
	for txt in texts:
		var pos := Vector3(
			randf_range(-28.0, 28.0),
			randf_range(-4.0, 8.0),
			randf_range(-30.0, 18.0))
		_spawn_text_mesh((txt as String),
			Color(1.0, 0.12, 0.08),
			randf_range(2.0, 6.0), 0.40,
			pos, _chan_text_r)


## GREEN channel — organic drift. Small text, scattered offsets.
## Effect: slow breath rise then collapse; position drifts gently.
func _spawn_green_channel_text() -> void:
	# Green uses a fire-and-forget spawner: each call launches one label
	# that fades in, holds, fades out, frees itself, then reschedules.
	var texts := _get_channel_texts("green", 99)
	if texts.is_empty(): return
	# Launch N independent ghosts, each staggered so they don't all appear at once.
	const CONCURRENT := 8
	for _i in CONCURRENT:
		var delay := randf() * 8.0
		get_tree().create_timer(delay).timeout.connect(
			_launch_green_ghost.bind(texts), CONNECT_ONE_SHOT)


func _launch_green_ghost(texts: Array) -> void:
	var is_active := (dungeon_channel_mask == CHAN_G)
	var txt : String = texts[randi() % texts.size()]
	var pos := Vector3(
		randf_range(-28.0, 28.0),
		randf_range(-4.0, 8.0),
		randf_range(-30.0, 18.0))
	var mi := _spawn_text_mesh(txt, Color(0.10, 0.88, 0.24),
		randf_range(0.5, 1.2), 1.0, pos, _chan_text_g)
	mi.visible = is_active
	var smat := (mi.mesh as TextMesh).material as ShaderMaterial
	var pre_wait  := randf_range(0.3, 1.2)   # silent before any pixels appear
	var rise      := randf_range(2.0, 4.0)   # gradual flicker-in
	var hold      := randf_range(2.0, 5.0)   # fully visible dwell
	var fall      := randf_range(2.5, 5.0)   # gradual flicker-out
	var post_wait := randf_range(0.5, 1.5)   # silent after pixels gone before free
	var tw := mi.create_tween()
	# Slow upward drift for full lifetime
	var lifetime := pre_wait + rise + hold + fall + post_wait
	mi.create_tween().tween_property(mi, "position",
		pos + Vector3(0, 1.5, 0), lifetime).set_trans(Tween.TRANS_SINE)
	# 1. Silent wait — all pixels discarded, node exists but invisible
	tw.tween_interval(pre_wait)
	# 2. Flicker in — intensity falls from 0.99 toward 0.28 (more pixels appear)
	tw.tween_method(func(v: float): smat.set_shader_parameter("flicker_intensity", v),
		1.0, 0.28, rise).set_trans(Tween.TRANS_SINE)
	# 3. Hold at peak visibility
	tw.tween_interval(hold)
	# 4. Flicker out — intensity rises back to 0.99 (pixels disappear)
	tw.tween_method(func(v: float): smat.set_shader_parameter("flicker_intensity", v),
		0.28, 1.0, fall).set_trans(Tween.TRANS_SINE)
	# 5. Silent wait — all pixels gone, clean pause before node is freed
	tw.tween_interval(post_wait)
	# 6. Free and reschedule this ghost independently
	tw.tween_callback(func():
		_chan_text_g.erase(mi)
		if is_instance_valid(mi): mi.queue_free()

		var delay := randf_range(0.1, 1.5)
		get_tree().create_timer(delay).timeout.connect(
			_launch_green_ghost.bind(texts), CONNECT_ONE_SHOT))


## BLUE channel — spectral double ghost. Two offset copies per text.
func _spawn_blue_channel_text() -> void:
	var texts := _get_channel_texts("blue", 6)
	if texts.is_empty(): return
	texts.shuffle()
	for txt in texts:
		var base_pos := Vector3(
			randf_range(-28.0, 28.0),
			randf_range(-4.0, 8.0),
			randf_range(-30.0, 18.0))
		# Upper ghost — bright, slightly higher
		_spawn_text_mesh(txt as String, Color(0.55, 0.78, 1.00),
			randf_range(0.3, 0.8), 0.22,
			base_pos + Vector3(0.0, 0.15, 0.0), _chan_text_b)
		# Lower echo — dim, offset right
		_spawn_text_mesh(txt as String, Color(0.28, 0.45, 0.75),
			randf_range(0.3, 0.8), 0.22,
			base_pos + Vector3(1.0, -0.15, 0.0), _chan_text_b)


func _spawn_ghost(pos: Vector2i, color: Color = C_GHOST, interactive: bool = true) -> Node3D:
	var node = ROOM_SCENE.instantiate()
	node.position = grid_to_world(pos)
	map_root.add_child(node)
	# setup_ghost must be called after add_child so @onready vars are ready.
	node.setup_ghost(pos, controller, color, interactive)
	return node


# ── Radial choice entry point ─────────────────────────────────────────────────

# Called by DungeonRoom3D when a ghost cube is clicked.
## Show a sequential prompt for each proposed side connection.
## Processes one proposal at a time; moves to the next on accept or skip.
func show_connection_proposals(from_pos: Vector2i, proposals: Array,
		dc: DungeonController) -> void:
	if proposals.is_empty():
		return
	var remaining := proposals.duplicate()
	_show_next_connection_proposal(from_pos, remaining, dc)


func _show_next_connection_proposal(from_pos: Vector2i, remaining: Array,
		dc: DungeonController) -> void:
	if remaining.is_empty():
		return
	var nb_pos : Vector2i = remaining[0]
	remaining = remaining.slice(1)
	var nb_room : RoomInstance = dungeon.grid.get(nb_pos)
	var nb_name : String = nb_room.room_data.room_name if nb_room and nb_room.room_data \
		else str(nb_pos)

	# Build a small 2D overlay panel anchored to screen centre-top.
	var overlay := CanvasLayer.new()
	overlay.layer = 60
	get_tree().root.add_child(overlay)

	var panel := PanelContainer.new()
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.0
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.0
	panel.offset_left   = -180.0
	panel.offset_top    =  20.0
	panel.offset_right  =  180.0
	panel.offset_bottom =  100.0
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.08, 0.07, 0.06, 0.97)
	sbox.border_color = Color(0.35, 0.28, 0.22, 1.0)
	sbox.set_border_width_all(2)
	sbox.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sbox)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var lbl := Label.new()
	lbl.text = "Connect to %s?\n(costs 1 connection each)" % nb_name
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.88, 0.83, 0.74, 1.0))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var connect_btn := Button.new()
	connect_btn.text = "Connect"
	connect_btn.add_theme_font_size_override("font_size", 13)
	connect_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(connect_btn)

	var skip_btn := Button.new()
	skip_btn.text = "Skip"
	skip_btn.add_theme_font_size_override("font_size", 13)
	skip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(skip_btn)

	var close_and_next := func():
		overlay.queue_free()
		_show_next_connection_proposal(from_pos, remaining, dc)

	connect_btn.pressed.connect(func():
		dc.accept_connection_proposal(from_pos, nb_pos)
		close_and_next.call())
	skip_btn.pressed.connect(func():
		close_and_next.call())


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

	# ── Center reroll button (always present, dims when no charges) ──
	_reroll_btn = null
	var run : RunState = GameController.current_run
	var rerolls : int = run.reroll_charges if run != null else 0
	var reroll_wrapper := Control.new()
	reroll_wrapper.custom_minimum_size = Vector2(REROLL_BTN_SIZE, REROLL_BTN_SIZE)
	reroll_wrapper.size                = Vector2(REROLL_BTN_SIZE, REROLL_BTN_SIZE)
	reroll_wrapper.position            = origin - Vector2(REROLL_BTN_SIZE * 0.5, REROLL_BTN_SIZE * 0.5)
	_choice_layer.add_child(reroll_wrapper)
	var reroll_btn := _make_reroll_button(rerolls)
	reroll_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
	reroll_wrapper.add_child(reroll_btn)
	_reroll_btn = reroll_btn
	var captured_origin := origin
	reroll_btn.pressed.connect(func(): _on_reroll_pressed(captured_origin))

	# ── Tie button (downward arc, only when tiles remain) ──
	_road_btn_wrap = null
	var road_count : int = run.road_tiles_remaining if run != null else 0
	if road_count > 0:
		var road_wrapper := Control.new()
		road_wrapper.clip_contents       = true
		road_wrapper.custom_minimum_size = Vector2(RING_BTN_H, RING_BTN_H)
		road_wrapper.size                = Vector2(RING_BTN_H, RING_BTN_H)
		road_wrapper.position            = origin - Vector2(RING_BTN_H * 0.5, RING_BTN_H * 0.5)
		_choice_layer.add_child(road_wrapper)
		_road_btn_wrap = road_wrapper
		var road_btn := _make_ring_button("⌒ %d" % road_count)
		road_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		road_wrapper.add_child(road_btn)
		road_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
		road_btn.pressed.connect(func(): _on_road_pressed(captured_origin))
		_animate_ring_btn(road_wrapper, road_btn, origin, RADIAL_START_ANGLE,
			ROAD_BTN_ANGLE, snap_layer, false, "⌒ %d" % road_count)


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


func _make_reroll_button(charges: int) -> Button:
	var btn := Button.new()
	btn.text = "↺ %d" % charges
	btn.add_theme_font_size_override("font_size", 14)
	var active : bool = charges > 0
	var bg_col   : Color = C_BG
	var bdr_col  : Color = C_ACCENT if active else C_BORDER
	var txt_col  : Color = C_TEXT   if active else C_DIM
	btn.add_theme_color_override("font_color",       txt_col)
	btn.add_theme_color_override("font_hover_color", txt_col)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color     = bg_col
	sbox.border_color = bdr_col
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(int(REROLL_BTN_SIZE * 0.5))
	sbox.set_content_margin_all(4)
	var sbox_h := sbox.duplicate() as StyleBoxFlat
	sbox_h.bg_color     = C_SEL if active else bg_col
	sbox_h.border_color = bdr_col
	btn.add_theme_stylebox_override("normal",  sbox)
	btn.add_theme_stylebox_override("hover",   sbox_h if active else sbox)
	btn.add_theme_stylebox_override("pressed", sbox_h)
	btn.add_theme_stylebox_override("focus",   sbox)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.disabled     = not active
	return btn


func _on_reroll_pressed(origin: Vector2) -> void:
	var run : RunState = GameController.current_run
	if run == null or run.reroll_charges <= 0:
		return
	controller.reroll_room_choices(_pending_pos)
	# Rebuild the ring with fresh choices.
	var new_choices := controller.get_room_choices(_pending_pos)
	_pending_choices = new_choices
	_selected_data   = null
	# Clear old ring nodes (leave CanvasLayer intact).
	for child in _choice_layer.get_children():
		child.queue_free()
	_radial_nodes.clear()
	_reroll_btn   = null
	_road_btn_wrap = null
	if is_instance_valid(_detail_node):
		_detail_node = null
	await get_tree().process_frame
	if not is_instance_valid(_choice_layer):
		return
	_build_radial_ring(origin, new_choices)


func _on_road_pressed(_origin: Vector2) -> void:
	var run : RunState = GameController.current_run
	if run == null or run.road_tiles_remaining <= 0:
		return
	# Capture pos before dismiss clears _pending_pos.
	var build_pos : Vector2i = _pending_pos
	var road_data := RoomData.new()
	road_data.room_name       = "Tie"
	road_data.room_type       = RoomData.RoomType.ROAD
	road_data.allows_segno    = false
	road_data.max_connections = 4
	_popped_positions.erase(build_pos)
	dismiss_choice_panel()
	controller.build_room(build_pos, road_data)


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
	var type_names : Array = ["Battle", "Elite", "Event", "Shop", "Rest", "Segno", "Boss", "Recruit", "Road", "Treasure"]
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

	# Compass pane — TERMINAL rooms show all directions as inactive (no exits).
	vbox.add_child(_build_compass(data, data.is_terminal()))

	var div2 := ColorRect.new()
	div2.color               = C_BORDER
	div2.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div2)

	# Enemies — shown for battle/elite rooms whose encounter enemies the player
	# has already faced (keyed in RunState.defeated_enemies by display_name).
	var is_battle_room : bool = data.room_type == RoomData.RoomType.BATTLE \
		or data.room_type == RoomData.RoomType.ELITE
	if is_battle_room and data.encounter != null:
		var run : RunState = GameController.current_run
		var known_names : Array = []
		for char_data in data.encounter.enemies:
			if char_data != null and char_data.display_name != "" \
					and run != null and run.defeated_enemies.has(char_data.display_name):
				known_names.append(char_data.display_name)
		if not known_names.is_empty():
			var enemy_hdr := Label.new()
			enemy_hdr.text = "ENEMIES"
			enemy_hdr.add_theme_font_size_override("font_size", 10)
			enemy_hdr.add_theme_color_override("font_color", C_ACCENT)
			vbox.add_child(enemy_hdr)
			var enemy_lbl := Label.new()
			enemy_lbl.text = ", ".join(known_names)
			enemy_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			enemy_lbl.add_theme_font_size_override("font_size", 11)
			enemy_lbl.add_theme_color_override("font_color", C_TEXT)
			vbox.add_child(enemy_lbl)
			var enemy_div := ColorRect.new()
			enemy_div.color = C_BORDER
			enemy_div.custom_minimum_size = Vector2(0, 1)
			vbox.add_child(enemy_div)

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


func _build_compass(data: RoomData, force_all_off: bool = false) -> Control:
	# Draws compass on a fixed 100x100 Control using absolute positions.
	# All coordinates are relative to that canvas; centre is (50, 50).
	const W    := 100       # canvas size
	const CX   := 50.0     # centre X
	const CY   := 50.0     # centre Y
	const BAR  := 2.0      # bar thickness
	const BRAD := 16.0     # bar half-length (bar runs from centre ± BRAD)
	const LBL_OFFSET := 30.0  # how far the label centre is from canvas centre
	const FONT_SIZE  := 12

	var exit_dirs : Array = [] if force_all_off else data.get_exit_dirs()
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

	# TERMINAL rooms have no outgoing exits — no preview ghosts.
	if data.is_terminal():
		return

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


func _dismiss_room_info() -> void:
	if is_instance_valid(_room_info_layer):
		_room_info_layer.queue_free()
	_room_info_layer = null


func show_room_info(grid_pos: Vector2i, instance: RoomInstance, screen_pos: Vector2) -> void:
	_dismiss_room_info()

	var data : RoomData = instance.room_data
	if data == null:
		return

	_room_info_layer = CanvasLayer.new()
	_room_info_layer.layer = 12
	add_child(_room_info_layer)

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_BG
	ps.border_color = C_BORDER
	ps.set_border_width_all(2)
	ps.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", ps)
	panel.custom_minimum_size = Vector2(220, 0)
	_room_info_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = data.room_name.to_upper()
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	vbox.add_child(name_lbl)

	# Type
	const TYPE_NAMES := ["Battle", "Elite", "Event", "Shop", "Rest",
		"Segno", "Boss", "Recruit", "Tie", "Treasure"]
	var type_str : String = TYPE_NAMES[data.room_type] if data.room_type < TYPE_NAMES.size() else ""
	var type_lbl := Label.new()
	type_lbl.text = type_str
	type_lbl.add_theme_font_size_override("font_size", 11)
	type_lbl.add_theme_color_override("font_color", C_DIM)
	vbox.add_child(type_lbl)

	# Divider
	var div := ColorRect.new()
	div.color = C_BORDER
	div.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div)

	# Status
	var dr : DungeonRunState = dungeon
	var is_current : bool = dr != null and dr.current_pos == grid_pos
	var status_str : String
	if is_current:
		status_str = "current"
	elif instance.cleared:
		status_str = "cleared"
	elif instance.visited:
		status_str = "visited"
	else:
		status_str = "unvisited"
	var status_lbl := Label.new()
	status_lbl.text = status_str
	status_lbl.add_theme_font_size_override("font_size", 11)
	status_lbl.add_theme_color_override("font_color", C_ACCENT if is_current else C_DIM)
	vbox.add_child(status_lbl)

	# Connections
	var conns_remaining : int = data.max_connections - instance.built_connections
	if conns_remaining > 0:
		var conn_lbl := Label.new()
		conn_lbl.text = "%d connection%s remaining" % [
			conns_remaining, "s" if conns_remaining != 1 else ""]
		conn_lbl.add_theme_font_size_override("font_size", 11)
		conn_lbl.add_theme_color_override("font_color", C_DIM)
		vbox.add_child(conn_lbl)

	# Description
	if data.description != "":
		var desc_div := ColorRect.new()
		desc_div.color = C_BORDER
		desc_div.custom_minimum_size = Vector2(0, 1)
		vbox.add_child(desc_div)
		var desc_lbl := Label.new()
		desc_lbl.text = data.description
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", C_DIM)
		vbox.add_child(desc_lbl)

	# Enemies (battle rooms cleared at least once)
	if not instance.defeated_enemy_names.is_empty():
		var enemy_div := ColorRect.new()
		enemy_div.color = C_BORDER
		enemy_div.custom_minimum_size = Vector2(0, 1)
		vbox.add_child(enemy_div)
		var enemy_hdr := Label.new()
		enemy_hdr.text = "Enemies"
		enemy_hdr.add_theme_font_size_override("font_size", 10)
		enemy_hdr.add_theme_color_override("font_color", C_ACCENT)
		vbox.add_child(enemy_hdr)
		var enemy_lbl := Label.new()
		enemy_lbl.text = ", ".join(instance.defeated_enemy_names)
		enemy_lbl.add_theme_font_size_override("font_size", 11)
		enemy_lbl.add_theme_color_override("font_color", C_TEXT)
		enemy_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(enemy_lbl)

	# Position: clamp to viewport
	var vp := get_viewport().get_visible_rect().size
	panel.position = Vector2(
		clamp(screen_pos.x + 12, 4, vp.x - 228),
		clamp(screen_pos.y - 20, 4, vp.y - 200)
	)
