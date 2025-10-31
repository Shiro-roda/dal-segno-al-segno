extends Node3D

@onready var camera: Camera3D = $RunnerCam

var player: Node3D
var head_ken: Node3D
var flashlight: SpotLight3D

var is_mouse_aiming := false
var aim_point: Vector3 = Vector3.ZERO
var aim_speed := 5.0

func _ready():
	# Wait one frame to let instanced scenes load
	await get_tree().process_frame
	
	# Find the player and head nodes by name anywhere in the scene tree
	player = get_tree().get_root().find_child("Player", true, false)
	if not player:
		push_error("⚠️ Player not found in scene tree!")
		return

	head_ken = player.find_child("Head_001", true, false)
	if not head_ken:
		push_error("⚠️ Head_001 not found under player!")
		return

	flashlight = head_ken.find_child("Flashlight", true, false)
	if not flashlight:
		push_error("⚠️ Flashlight not found under Head_001!")
		return



func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_mouse_aiming = event.pressed

	if event is InputEventMouseMotion and is_mouse_aiming:
		_update_aim_target(event.position)

func _physics_process(delta):
	if player:
		if is_mouse_aiming:
			_rotate_toward_aim(delta)
		else:
			_align_to_movement(delta)


func _update_aim_target(mouse_pos: Vector2) -> void:
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 200.0
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)

	if result:
		aim_point = result.position
	else:
		aim_point = to

func _rotate_toward_aim(delta: float) -> void:
	if not head_ken:
		return

	# Get the head's global position
	var head_pos = head_ken.global_position
	var dir_to_target = (aim_point - head_pos).normalized()

	# Convert direction into the player’s local space
	var local_dir = player.to_local(head_pos + dir_to_target) - player.to_local(head_pos)
	local_dir = local_dir.normalized()

	# Compute yaw (rotation around Y axis)
	var target_yaw = atan2(local_dir.x, local_dir.z)

	# Compute pitch (rotation around X axis)
	var target_pitch = -asin(clamp(local_dir.y, -1.0, 1.0))

	# Clamp angles
	var yaw_limit = deg_to_rad(70.0)
	var pitch_limit = deg_to_rad(40.0)
	target_yaw = clamp(target_yaw, -yaw_limit, yaw_limit)
	target_pitch = clamp(target_pitch, -pitch_limit, pitch_limit)

	# Smoothly interpolate the local rotation
	var current_rot = head_ken.rotation_degrees
	current_rot.y = lerp_angle(current_rot.y, rad_to_deg(target_yaw), delta * aim_speed)
	current_rot.x = lerp_angle(current_rot.x, rad_to_deg(target_pitch), delta * aim_speed)
	head_ken.rotation_degrees = current_rot

	# Flashlight inherits rotation
	if flashlight:
		flashlight.rotation = head_ken.rotation


func _align_to_movement(delta: float) -> void:
	# Get the player's current facing direction
	if not player.has_method("get_last_direction"):
		return
	var move_dir = player.call("get_last_direction")
	if move_dir.length() < 0.1:
		return

	var target_yaw = atan2(move_dir.x, move_dir.z)
	var target_basis = Basis(Vector3.UP, target_yaw)
	head_ken.basis = head_ken.basis.slerp(target_basis, delta * aim_speed)
