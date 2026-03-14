extends Node3D
## RoomCorridor3D — a visual connector drawn between two adjacent rooms on the dungeon map.
## Currently renders as a glowing yellow flat box.
## Swap _build_placeholder() for a real model + animation in the future.

# World-space endpoints (set by dungeon_map_3d before add_child).
var from_world : Vector3
var to_world   : Vector3

# Whether this corridor was just built this frame (for future build animation trigger).
var is_new_build : bool = false

@onready var _mesh_node : MeshInstance3D = $CorridorMesh


func _ready() -> void:
	_build_placeholder()


## Rebuild the visual to span from_world → to_world.
## Call this if endpoints change, or override with your own model logic.
func _build_placeholder() -> void:
	if _mesh_node == null:
		return

	var mid    : Vector3 = (from_world + to_world) * 0.5
	var diff   : Vector3 = to_world - from_world
	var length : float   = diff.length()

	# Position at midpoint, rotate to face the direction, scale to length.
	position = mid
	look_at(to_world, Vector3.UP)
	# After look_at the local +Z faces away from to_world; flip 180° so +Z faces to_world.
	rotate_object_local(Vector3.UP, PI)

	# Scale the unit box: X = corridor width, Y = height, Z = length.
	const WIDTH  := 0.12
	const HEIGHT := 0.06
	_mesh_node.scale = Vector3(WIDTH, HEIGHT, length)

	# Glowing yellow material.
	var mat := StandardMaterial3D.new()
	mat.albedo_color              = Color(1.0, 0.85, 0.15, 1.0)
	mat.emission_enabled          = true
	mat.emission                  = Color(1.0, 0.75, 0.05, 1.0)
	mat.emission_energy_multiplier = 1.2
	_mesh_node.set_surface_override_material(0, mat)


## Hook for future build animation.  Call when spawning a newly-built corridor.
func play_build_animation() -> void:
	# TODO: replace placeholder with proper tween / AnimationPlayer.
	pass
