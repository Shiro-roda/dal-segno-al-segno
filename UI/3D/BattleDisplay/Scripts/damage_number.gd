extends Node3D
## DamageNumber — floating 3D damage text.
## Pops in above the target, drifts upward, fades via flicker shader.
## Bills toward the active battle camera each frame.

const FONT_PATH   := "res://UI/Themes/Fonts/SpaceMono-Bold.ttf"
const SHADER_PATH := "res://Shaders/flicker_text.gdshader"

const C_DAMAGE := Color(0.749, 0.0, 0.016, 1.0)
const C_SHADOW := Color(0.0,  0.0,  0.0)
const RISE     := 0.9
const DURATION := 1.2
const POP_SCALE := 1.7
# Spawn this many units above the actor root (roughly head height)
const SPAWN_Y_OFFSET := 2.1

var _camera : Node3D = null
var _mi     : MeshInstance3D = null


func _start(world_pos: Vector3, amount: int, actor_team: int, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	position = world_pos + Vector3(randf_range(-0.15, 0.15), SPAWN_Y_OFFSET, 0.0)

	# Find the appropriate phantom cam for this team
	var scene_root := get_tree().get_first_node_in_group("battle_scene")
	if scene_root:
		var cam_name := "target_cam" if actor_team == 1 else "active_cam"
		_camera = scene_root.get_node_or_null("CameraRig/" + cam_name)

	var font   := load(FONT_PATH)   as Font
	var shader := load(SHADER_PATH) as Shader

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = 10
	mat.set_shader_parameter("text_color",         Vector3(C_DAMAGE.r, C_DAMAGE.g, C_DAMAGE.b))
	mat.set_shader_parameter("flicker_speed",      2.0)
	mat.set_shader_parameter("flicker_intensity",  0.00)
	mat.set_shader_parameter("uv_aspect",          1.0)
	mat.set_shader_parameter("pixel_size",         8.0)
	# No shadow — zero steps means shadow source == self, so use_shadow is always 0
	mat.set_shader_parameter("shadow_color",       Vector3(0.0, 0.0, 0.0))
	mat.set_shader_parameter("shadow_pixel_steps", Vector2(0.0, 0.0))

	var mesh := TextMesh.new()
	if font: mesh.font = font
	mesh.text      = str(amount)
	mesh.font_size = 14
	mesh.depth     = 0.0
	mesh.add_uv2   = true
	mesh.material  = mat

	_mi = MeshInstance3D.new()
	_mi.mesh = mesh
	add_child(_mi)

	# Pop scale spike then settle
	var pop_tw := create_tween()
	pop_tw.tween_property(_mi, "scale",
		Vector3(POP_SCALE, POP_SCALE, POP_SCALE), 0.06)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	pop_tw.tween_property(_mi, "scale",
		Vector3.ONE, 0.12)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	# Drift in camera-relative screen space so numbers stay visible.
	# Use the camera's right vector for lateral spread and world Y for vertical.
	# The sign of lateral drift is biased away from the attacker in screen space.
	var cam_right := Vector3.RIGHT
	if _camera:
		var to_cam_flat := Vector3(
			_camera.global_position.x - world_pos.x,
			0.0,
			_camera.global_position.z - world_pos.z).normalized()
		cam_right = to_cam_flat.cross(Vector3.UP).normalized()
	# Determine which side the attacker is on relative to camera right
	var to_attacker : Vector3 = attacker_pos - world_pos
	var lateral_sign : float = 1.0
	if to_attacker.length_squared() > 0.01:
		var dot : float = to_attacker.dot(cam_right)
		lateral_sign = -1.0 if dot > 0.0 else 1.0
	else:
		lateral_sign = 1.0 if randf() > 0.5 else -1.0
	var drift : Vector3 = cam_right * lateral_sign * randf_range(0.25, 0.55)
	drift.y = randf_range(0.05, 0.35)
	create_tween().tween_property(self, "position",
		position + drift, DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Fade out
	var hold := DURATION * 0.5
	var fall := DURATION - hold
	var fade_tw := create_tween()
	fade_tw.tween_interval(hold)
	fade_tw.tween_method(
		func(v: float): mat.set_shader_parameter("flicker_intensity", v),
		0.0, 1.0, fall)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fade_tw.tween_callback(queue_free)


func _process(_delta: float) -> void:
	if _camera == null or _mi == null:
		return
	# Billboard: rotate the root node to face the camera on Y, then tilt the
	# mesh so it reads clearly from the camera's elevation angle.
	var to_cam := _camera.global_position - global_position
	if to_cam.length_squared() < 0.0001:
		return
	# Yaw to face camera
	var dx := to_cam.x
	var dz := to_cam.z
	rotation.y = atan2(dx, dz)
	# Pitch: tilt face upward to match camera elevation
	var flat_dist := Vector2(dx, dz).length()
	rotation.x   = -atan2(to_cam.y, flat_dist)
