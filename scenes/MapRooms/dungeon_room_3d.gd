extends Node3D

var grid_pos : Vector2i
var room_instance : RoomInstance
var controller : DungeonController

@onready var mesh : MeshInstance3D = get_node_or_null("MeshInstance3D")
@onready var area : Area3D = get_node_or_null("Area3D")





func setup(pos:Vector2i, instance:RoomInstance, dungeon_controller):

	grid_pos = pos
	room_instance = instance
	controller = dungeon_controller

	update_visual()


func update_visual():
	if mesh == null:
		push_error("MeshInstance3D missing in DungeonRoom3D scene!")
		return

	if room_instance == null:
		return

	var color = Color.GRAY

	if room_instance.cleared:
		color = Color.GREEN
	elif room_instance.visited:
		color = Color.YELLOW

	if controller.dungeon.current_pos == grid_pos:
		color = Color.RED

	var material = StandardMaterial3D.new()
	material.albedo_color = color

	mesh.set_surface_override_material(0, material)


func _on_area_3d_input_event(camera, event, position, normal, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if room_instance != null:
			controller.move_to_room(grid_pos)
		else:
			# Ghost cube clicked — ask map to show choices near click position
			var map_ui : Node3D = get_tree().get_first_node_in_group("dungeon_map_3d")
			if map_ui == null:
				return
			var choices := controller.get_room_choices(grid_pos)
			map_ui.show_choices_at(grid_pos, choices, event.position)
