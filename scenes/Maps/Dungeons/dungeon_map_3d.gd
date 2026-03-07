extends Node3D
class_name DungeonMap3D

var dungeon : DungeonRunState
var rotating = false
var last_mouse_pos
@onready var controller: DungeonController = $"../DungeonController"



@onready var map_root = $MapRoot

const ROOM_SCENE = preload("res://scenes/MapRooms/dungeon_room_3d.tscn")

const ROOM_SPACING = 6.0

func _ready():
	set_process_input(true)


func setup(run_state: DungeonRunState, dungeon_controller: DungeonController):
	print("DungeonMap setup called")

	dungeon = run_state
	controller = dungeon_controller

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

	for child in map_root.get_children():
		child.queue_free()
	
	map_root.position = -grid_to_world(dungeon.current_pos)

	
	for pos in dungeon.grid.keys():

		var room : RoomInstance = dungeon.grid[pos]

		var node = ROOM_SCENE.instantiate()

		node.setup(pos, room, controller)

		node.position = grid_to_world(pos)

		map_root.add_child(node)

	draw_available_positions()



func draw_available_positions():

	var positions = controller.get_available_positions()

	for pos in positions:

		var node = ROOM_SCENE.instantiate()

		node.grid_pos = pos
		node.controller = controller
		node.room_instance = null

		node.position = grid_to_world(pos)

		var mesh = node.get_node("MeshInstance3D")

		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.2,0.6,1,0.4)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

		mesh.set_surface_override_material(0, material)

		map_root.add_child(node)




func grid_to_world(pos:Vector2i) -> Vector3:

	return Vector3(
		pos.x * ROOM_SPACING,
		0,
		pos.y * ROOM_SPACING
	)
