extends Node3D
class_name DungeonMap3D

var dungeon : DungeonRunState
var rotating = false
var last_mouse_pos
@onready var controller: DungeonController = get_tree().get_first_node_in_group("dungeon_controller")



@onready var map_root = $MapRoot

const ROOM_SCENE = preload("res://scenes/MapRooms/dungeon_room_3d.tscn")

const ROOM_SPACING = 2.0

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
	print("DungeonMap setup called, run_state=", run_state, " controller=", dungeon_controller)

	dungeon = run_state
	controller = dungeon_controller

	print("Grid keys: ", dungeon.grid.keys())
	redraw_map()

func _input(event):

	if event is InputEventMouseButton:

		if event.button_index == MOUSE_BUTTON_MIDDLE:
			rotating = event.pressed
			last_mouse_pos = event.position

	if event is InputEventMouseMotion and rotating:

		var delta = event.position - last_mouse_pos
		last_mouse_pos = event.position

		$CameraPivot.rotate_y(-delta.x * 0.01)


func redraw_map():
	if dungeon == null:
		return

	var old_pos = map_root.position
	var new_pos = -grid_to_world(dungeon.current_pos)

	for child in map_root.get_children():
		child.queue_free()

	map_root.position = old_pos  # start from old position before tween

	
	for pos in dungeon.grid.keys():

		var room : RoomInstance = dungeon.grid[pos]

		var node = ROOM_SCENE.instantiate()

		node.setup(pos, room, controller)

		node.position = grid_to_world(pos)

		map_root.add_child(node)
		print("Room added at local pos: ", node.position)

	draw_available_positions()

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(map_root, "position", new_pos, 0.35)



func draw_available_positions():

	var positions = controller.get_available_positions()

	for pos in positions:

		var node = ROOM_SCENE.instantiate()

		node.grid_pos = pos
		node.controller = controller
		node.room_instance = null

		node.position = grid_to_world(pos)

		map_root.add_child(node)  # add first so @onready vars resolve

		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.2, 0.6, 1, 0.4)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		node.mesh.set_surface_override_material(0, material)




func grid_to_world(pos:Vector2i) -> Vector3:

	return Vector3(
		pos.x * ROOM_SPACING,
		0,
		pos.y * ROOM_SPACING
	)
