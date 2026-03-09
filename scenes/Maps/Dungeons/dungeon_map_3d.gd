extends Node3D
# DungeonMap3D — 3D grid map renderer and in-world build UI.

var dungeon : DungeonRunState
var rotating = false
var last_mouse_pos

var controller : DungeonController = null
@onready var map_root = $MapRoot

const ROOM_SCENE    = preload("res://scenes/MapRooms/dungeon_room_3d.tscn")
const ROOM_SPACING  = 2.0

# 2D overlay choice panel
var _choice_panel      : CanvasLayer = null
var _preview_ghosts    : Array  = []      # yellow ghost cubes (non-interactive)
var _pending_choices   : Array  = []      # Array[RoomData] currently being previewed
var _pending_pos       : Vector2i = Vector2i(-999, -999)
var _selected_data     : RoomData = null  # first-click selection waiting for confirm
var _choice_buttons    : Array  = []      # Button nodes for highlight updates


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
	dungeon = run_state
	controller = dungeon_controller
	redraw_map()

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			rotating = event.pressed
			last_mouse_pos = event.position
		# Right-click or Escape cancels current choice
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			dismiss_choice_panel()

	if event is InputEventMouseMotion and rotating:
		var delta = event.position - last_mouse_pos
		last_mouse_pos = event.position
		$CameraPivot.rotate_y(-delta.x * 0.01)


# ── Map drawing ────────────────────────────────────────────────────────────────

func redraw_map():
	if dungeon == null:
		return

	dismiss_choice_panel()

	var old_pos = map_root.position
	var new_pos = -grid_to_world(dungeon.current_pos)

	for child in map_root.get_children():
		child.queue_free()

	map_root.position = old_pos

	for pos in dungeon.grid.keys():
		var room : RoomInstance = dungeon.grid[pos]
		var node = ROOM_SCENE.instantiate()
		node.setup(pos, room, controller)
		node.position = grid_to_world(pos)
		map_root.add_child(node)

	draw_available_positions()

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(map_root, "position", new_pos, 0.35)


func draw_available_positions():
	if controller == null:
		push_error("DungeonMap3D: controller is null in draw_available_positions")
		return
	var positions = controller.get_available_positions()
	for pos in positions:
		_spawn_ghost(pos)


func _spawn_ghost(pos: Vector2i, color: Color = Color(0.2, 0.6, 1.0, 1.0), interactive: bool = true) -> Node3D:
	var node = ROOM_SCENE.instantiate()
	node.grid_pos      = pos
	node.controller    = controller
	node.room_instance = null
	node.position      = grid_to_world(pos)
	map_root.add_child(node)  # add_child first so @onready vars resolve
	if not interactive:
		# Disable the Area3D so yellow preview ghosts can't be clicked
		var area = node.get_node_or_null("Area3D")
		if area:
			area.monitoring   = false
			area.monitorable  = false
			area.process_mode = Node.PROCESS_MODE_DISABLED

	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.6
	node.mesh.set_surface_override_material(0, material)
	return node


# ── Choice panel ───────────────────────────────────────────────────────────────

# Called by DungeonRoom3D when a ghost cube is clicked.
# screen_pos: the 2D viewport position of the click, for panel placement.
func show_choices_at(grid_pos: Vector2i, choices: Array, screen_pos: Vector2 = Vector2(200, 200)):
	if choices.is_empty():
		return
	# Toggle off if same position re-clicked with nothing selected
	if _pending_pos == grid_pos and _choice_panel != null and _selected_data == null:
		dismiss_choice_panel()
		return

	dismiss_choice_panel()
	_pending_pos     = grid_pos
	_pending_choices = choices
	_selected_data   = null
	_choice_buttons.clear()

	# --- 2D CanvasLayer, positioned near the clicked cube ---
	_choice_panel = CanvasLayer.new()
	_choice_panel.layer = 10
	add_child(_choice_panel)

	var panel := PanelContainer.new()
	# Offset the panel to the right of the click so it doesn't cover the cube
	var vp_size  = get_viewport().get_visible_rect().size
	var px = clamp(screen_pos.x + 24, 4, vp_size.x - 280)
	var py = clamp(screen_pos.y - 40, 4, vp_size.y - 200)
	panel.position = Vector2(px, py)
	_choice_panel.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	for i in choices.size():
		var data : RoomData = choices[i]
		var btn := Button.new()
		btn.text = data.room_name
		btn.custom_minimum_size = Vector2(220, 34)
		btn.toggle_mode = true
		var captured_data := data
		var captured_pos  := grid_pos
		btn.pressed.connect(func():
			_on_choice_pressed(captured_pos, captured_data, btn)
		)
		vbox.add_child(btn)
		_choice_buttons.append(btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(220, 28)
	cancel_btn.pressed.connect(dismiss_choice_panel)
	vbox.add_child(cancel_btn)

	# --- Connection preview ghosts for first choice by default ---
	_show_connection_ghosts(grid_pos, choices[0])


func _show_connection_ghosts(origin: Vector2i, data: RoomData):
	# Clear old preview ghosts
	for g in _preview_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_preview_ghosts.clear()

	var dirs : Array = data.get_exit_dirs()

	for offset in dirs:
		var target : Vector2i = origin + offset
		# Don't ghost positions that are already occupied
		if dungeon.grid.has(target):
			continue
		# Don't double-ghost the build position itself
		if target == origin:
			continue
		var ghost = _spawn_ghost(target, Color(1.0, 0.85, 0.2, 1.0), false)
		_preview_ghosts.append(ghost)


func dismiss_choice_panel():
	if is_instance_valid(_choice_panel):
		_choice_panel.queue_free()
	_choice_panel = null

	for g in _preview_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_preview_ghosts.clear()

	_pending_pos     = Vector2i(-999, -999)
	_pending_choices = []
	_selected_data   = null
	_choice_buttons.clear()

	# Also clear the controller's pending state
	if controller != null:
		controller.cancel_build()


# First click: select and preview. Second click on same: confirm and build.
func _on_choice_pressed(pos: Vector2i, data: RoomData, btn: Button):
	if _selected_data == data:
		# Second click on the same choice → build it
		dismiss_choice_panel()
		controller.build_room(pos, data)
		return

	# First click → mark as selected, update previews
	_selected_data = data
	for b in _choice_buttons:
		b.button_pressed = (b == btn)
	_show_connection_ghosts(pos, data)


# ── Helpers ────────────────────────────────────────────────────────────────────

func grid_to_world(pos: Vector2i) -> Vector3:
	return Vector3(pos.x * ROOM_SPACING, 0, pos.y * ROOM_SPACING)
