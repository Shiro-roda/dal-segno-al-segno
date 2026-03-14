extends Node3D

var grid_pos : Vector2i
var room_instance : RoomInstance
var controller : DungeonController

@onready var mesh : MeshInstance3D = get_node_or_null("MeshInstance3D")
@onready var area : Area3D = get_node_or_null("Area3D")

# Spawned custom model node, if any.
var _model_node : Node3D = null


func setup(pos: Vector2i, instance: RoomInstance, dungeon_controller) -> void:
	grid_pos      = pos
	room_instance = instance
	controller    = dungeon_controller
	update_visual()


func update_visual() -> void:
	if room_instance == null:
		# Ghost / unbuilt slot — always show plain cube, no model
		_show_placeholder(Color(0.20, 0.60, 1.00))
		return

	var data : RoomData = room_instance.room_data
	var model_scene : PackedScene = data.room_model if data != null else null

	if model_scene != null:
		_spawn_model(model_scene)
		# Tint the model node to reflect state, or leave neutral if you prefer.
		# The placeholder cube is hidden when a model is present.
		if mesh:
			mesh.visible = false
	else:
		# No model — fall back to colour-coded placeholder cube.
		_clear_model()
		if mesh == null:
			push_error("MeshInstance3D missing in DungeonRoom3D scene at " + str(grid_pos))
			return
		mesh.visible = true
		var color := _state_color()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mesh.set_surface_override_material(0, mat)


## Returns the tint colour that represents this room's current state.
func _state_color() -> Color:
	if controller != null and controller.dungeon.current_pos == grid_pos:
		return Color.RED
	if room_instance.cleared:
		return Color.GREEN
	if room_instance.visited:
		return Color.YELLOW
	return Color.GRAY


## Show the placeholder cube in a given colour (used for ghosts and fallback).
func _show_placeholder(color: Color) -> void:
	_clear_model()
	if mesh == null:
		return
	mesh.visible = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.set_surface_override_material(0, mat)


## Spawn (or replace) the custom model. The model root is added as a child
## and positioned at the origin so it sits where the placeholder cube would be.
func _spawn_model(scene: PackedScene) -> void:
	_clear_model()
	_model_node = scene.instantiate() as Node3D
	if _model_node == null:
		push_error("room_model for " + str(grid_pos) + " is not a Node3D scene.")
		return
	add_child(_model_node)


## Remove any previously spawned model node.
func _clear_model() -> void:
	if _model_node != null and is_instance_valid(_model_node):
		_model_node.queue_free()
	_model_node = null


## Called by dungeon_map_3d for ghost / unbuilt-slot nodes.
## Must be called after add_child() so @onready vars are resolved.
func setup_ghost(pos: Vector2i, dungeon_controller, color: Color, interactive: bool) -> void:
	grid_pos      = pos
	controller    = dungeon_controller
	room_instance = null
	if not interactive and area != null:
		area.monitoring   = false
		area.monitorable  = false
		area.process_mode = Node.PROCESS_MODE_DISABLED
	# Ghost always uses the emissive placeholder cube, never a model.
	_clear_model()
	if mesh == null:
		return
	mesh.visible = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color              = color
	mat.emission_enabled          = true
	mat.emission                  = color
	mat.emission_energy_multiplier = 0.6
	mesh.set_surface_override_material(0, mat)


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
