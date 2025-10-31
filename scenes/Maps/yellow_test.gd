extends Node3D

@onready var camera: Camera3D = $RunnerCam

var player: Node3D
var skeleton: Skeleton3D
var flashlight: SpotLight3D

var head_bone_name := "Head_001"
var head_bone_index: int = -1

var is_mouse_aiming := false
var aim_point: Vector3 = Vector3.ZERO
var aim_speed := 5.0

# Neutral (default) rotation
var neutral_yaw := 0.0
var neutral_pitch := 0.0


func _ready():
	await get_tree().process_frame
	
	# --- Find the player ---
	player = get_tree().get_root().find_child("Player", true, false)
	if not player:
		push_error("⚠️ Player not found in scene tree!")
		return

	# --- Find the skeleton ---
	skeleton = player.find_child("Skeleton3D", true, false)
	if not skeleton:
		push_error("⚠️ Skeleton3D not found under Player!")
		return

	# --- Get head bone index ---
	head_bone_index = skeleton.find_bone(head_bone_name)
	if head_bone_index == -1:
		push_error("⚠️ Bone '%s' not found in Skeleton3D!" % head_bone_name)
		return

	# --- Find flashlight ---
	flashlight = player.find_child("Flashlight", true, false)
	if not flashlight:
		push_error("⚠️ Flashlight not found in scene tree!")
		return

	# --- Store neutral pose for smooth return ---
	var head_pose: Transform3D = skeleton.get_bone_global_pose(head_bone_index)
	neutral_yaw = head_pose.basis.get_euler().y
	neutral_pitch = head_pose.basis.get_euler().x


func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_mouse_aiming = event.pressed

	if event is InputEventMouseMotion and is_mouse_aiming:
		_update_aim_target(event.position)


func _physics_process(delta: float) -> void:
	if player and skeleton and head_bone_index != -1:
		if is_mouse_aiming:
			_rotate_head_toward_aim(delta)
		else:
			_reset_head_to_neutral(delta)


# ---------------------------------------------------------------------
# Calculates a world-space aim point from the camera and mouse position
# ---------------------------------------------------------------------
func _update_aim_target(mouse_pos: Vector2) -> void:
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 500.0
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		aim_point = result.position
	else:
		aim_point = to


# ---------------------------------------------------------------------
# Rotates the head bone smoothly toward the aim target
# ---------------------------------------------------------------------
func _rotate_head_toward_aim(delta: float) -> void:
	var head_global := skeleton.get_bone_global_pose(head_bone_index)
	var head_pos := head_global.origin
	var dir := (aim_point - head_pos).normalized()

	# Convert aim direction into local space of skeleton
	var local_dir := skeleton.to_local(head_pos + dir) - skeleton.to_local(head_pos)
	local_dir = local_dir.normalized()

	# Compute yaw and pitch relative to skeleton forward (-Z)
	var yaw := atan2(local_dir.x, -local_dir.z)
	var pitch := asin(clamp(local_dir.y, -1.0, 1.0))

	# Clamp angles
	var yaw_limit := deg_to_rad(70.0)
	var pitch_limit := deg_to_rad(40.0)
	yaw = clamp(yaw, -yaw_limit, yaw_limit)
	pitch = clamp(pitch, -pitch_limit, pitch_limit)

	# Smoothly interpolate from current bone rotation
	var current_basis := head_global.basis
	var current_euler := current_basis.get_euler()
	current_euler.x = lerp_angle(current_euler.x, -pitch, delta * aim_speed)
	current_euler.y = lerp_angle(current_euler.y, yaw, delta * aim_speed)
	current_euler.z = 0.0

	# Build new bone transform
	var new_basis := Basis().from_euler(current_euler)
	var new_transform := Transform3D(new_basis, head_pos)

	# Apply rotation override
	skeleton.set_bone_global_pose_override(head_bone_index, new_transform, 1.0, true)

	# Make flashlight match head
	if flashlight:
		flashlight.global_transform.basis = new_basis * Basis(Vector3.UP, deg_to_rad(180))


# ---------------------------------------------------------------------
# Smoothly returns the head bone to neutral pose
# ---------------------------------------------------------------------
func _reset_head_to_neutral(delta: float) -> void:
	var head_global := skeleton.get_bone_global_pose(head_bone_index)
	var current_euler := head_global.basis.get_euler()
	current_euler.x = lerp_angle(current_euler.x, neutral_pitch, delta * aim_speed)
	current_euler.y = lerp_angle(current_euler.y, neutral_yaw, delta * aim_speed)
	current_euler.z = 0.0

	var new_basis := Basis().from_euler(current_euler)
	var new_transform := Transform3D(new_basis, head_global.origin)
	skeleton.set_bone_global_pose_override(head_bone_index, new_transform, 0.8, true)

	if flashlight:
		flashlight.global_transform.basis = new_basis * Basis(Vector3.UP, deg_to_rad(180))
