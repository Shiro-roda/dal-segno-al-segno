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
		if mesh:
			mesh.visible = false
		# Dim the model when this is a spent (cleared) Segno room so it reads
		# as "past" while remaining visually distinct on the map.
		if room_instance.cleared and data.room_type == RoomData.RoomType.SEGNO:
			_tint_model(Color(0.35, 0.22, 0.05, 1.0))  # dark amber
	else:
		# No model — fall back to colour-coded placeholder cube.
		_show_placeholder(_state_color())


## Base colour per room type — readable at a glance on the 3D map.
func _type_color() -> Color:
	if room_instance == null or room_instance.room_data == null:
		return Color(0.5, 0.5, 0.5)  # unknown
	match room_instance.room_data.room_type:
		RoomData.RoomType.BATTLE:  return Color(0.85, 0.22, 0.22)   # red
		RoomData.RoomType.ELITE:   return Color(0.90, 0.45, 0.10)   # orange
		RoomData.RoomType.EVENT:   return Color(0.55, 0.35, 0.75)   # purple
		RoomData.RoomType.SHOP:    return Color(0.90, 0.80, 0.15)   # gold
		RoomData.RoomType.REST:    return Color(0.20, 0.65, 0.45)   # teal
		RoomData.RoomType.SEGNO:   return Color(0.30, 0.55, 0.90)   # blue
		RoomData.RoomType.BOSS:    return Color(0.70, 0.10, 0.10)   # dark red
		RoomData.RoomType.RECRUIT: return Color(0.30, 0.70, 0.70)   # cyan
		RoomData.RoomType.ROAD:     return Color(0.70, 0.70, 0.68)   # light grey
		RoomData.RoomType.TREASURE: return Color(0.95, 0.80, 0.20)   # gold
		_: return Color(0.55, 0.55, 0.55)


## Final display colour: type colour modulated by room state.
func _state_color() -> Color:
	var base := _type_color()
	# Current room: bright white outline tint
	if controller != null and controller.dungeon != null \
			and controller.dungeon.current_pos == grid_pos:
		return base.lightened(0.45)
	# Past (cleared) Segno rooms: heavily dimmed so they read as spent
	# but remain visually distinct from other room types.
	if room_instance.cleared and room_instance.room_data != null \
			and room_instance.room_data.room_type == RoomData.RoomType.SEGNO:
		return base.darkened(0.55)
	# Cleared: slightly dimmed to show it's done
	if room_instance.cleared:
		return base.darkened(0.25)
	# Visited but not cleared: full type colour
	if room_instance.visited:
		return base
	# Unvisited: dark / greyed out
	return base.darkened(0.55)


## Show the placeholder cube in a given colour (used for ghosts and fallback).
func _show_placeholder(color: Color) -> void:
	_clear_model()
	if mesh == null:
		return
	# Ensure the mesh has geometry; assign a BoxMesh if empty.
	if mesh.mesh == null:
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 0.4, 0.9)
		mesh.mesh = box
	mesh.visible = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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


## Override the albedo of the first MeshInstance3D found inside the model.
## Used to tint cleared Segno rooms dark so they read as spent.
func _tint_model(color: Color) -> void:
	if _model_node == null:
		return
	# Find the first MeshInstance3D — works for both flat and nested models.
	var mi : MeshInstance3D = _model_node as MeshInstance3D
	if mi == null:
		for child in _model_node.get_children():
			if child is MeshInstance3D:
				mi = child as MeshInstance3D
				break
	if mi == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.set_surface_override_material(0, mat)


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
			# If adjacent and can connect, propose the connection.
			# Otherwise attempt normal movement.
			var cur := controller.dungeon.current_pos
			var diff := grid_pos - cur
			var is_adjacent : bool = (abs(diff.x) + abs(diff.y)) == 1
			if is_adjacent and not controller.rooms_connected(cur, grid_pos) \
					and controller._can_connect(cur, grid_pos):
				var map_ui : Node3D = get_tree().get_first_node_in_group("dungeon_map_3d")
				if map_ui:
					map_ui.show_connection_proposals(cur, [grid_pos], controller)
			else:
				controller.move_to_room(grid_pos)
		else:
			# Ghost cube clicked — ask map to show choices near click position
			var map_ui : Node3D = get_tree().get_first_node_in_group("dungeon_map_3d")
			if map_ui == null:
				return
			var choices := controller.get_room_choices(grid_pos)
			map_ui.show_choices_at(grid_pos, choices, event.position)
