extends CharacterBody3D


const SPEED = 5.0
const JUMP_VELOCITY = 8.0
var has_jumped = false
var last_direction = 0
@onready var ken_model: Node3D = $ken_model_test11
@onready var flashlight: SpotLight3D = $ken_model_test11/Kendall_rig_001/Skeleton3D/Head_001/Flashlight


var current_channel := 0 # 0=C, 1=M, 2=Y
const CHANNEL_COLORS = [Color.CYAN, Color.MAGENTA, Color.YELLOW]

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		if last_direction == Vector3(0,0,0):
			ken_model.play_anim("Jump2")
		else:
			velocity.y = JUMP_VELOCITY - 3
	
	if ken_model.anim.current_animation == "Jump2":
		var t = ken_model.anim.current_animation_position
		if t >= 0.6 and is_on_floor() and not has_jumped:
			velocity.y = JUMP_VELOCITY
			has_jumped = true
		if t < 0.6 and not is_on_floor():
			ken_model.anim.stop()

	if (ken_model.anim.current_animation != "Jump2") and is_on_floor():
		has_jumped = false
	
	if is_on_floor() and ken_model.anim.current_animation == "Jump2" and not last_direction == Vector3(0,0,0):
		ken_model.anim.stop()
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		if Input.is_action_pressed("Sprint") and not (ken_model.anim.current_animation == "Jump2" or has_jumped):
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
			ken_model.play_anim("Action_004")
		else:
			velocity.x = direction.x * SPEED / 2.5
			velocity.z = direction.z * SPEED / 2.5
			if is_on_floor() and not ken_model.anim.current_animation == "Jump2":
				ken_model.play_anim("Action_003")
		if direction.length() > 0:
			# atan2 expects (x, z) in 3D space
			var target_rotation = atan2(direction.x, direction.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, 10 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		if (is_on_floor() == true) and not ken_model.anim.current_animation == "Jump2":
			ken_model.play_anim("Idle2")
	
	last_direction = direction
	
	if Input.is_action_just_pressed("eye_sore_input"):
		lens_change(current_channel)
	
	if Input.is_action_just_pressed("close_your_eyes"):
		if flashlight.light_energy == 0.0:
			flashlight.light_energy = 40.0
		else:
			flashlight.light_energy = 0.0

	move_and_slide()

func lens_change(int):
	current_channel = (current_channel + 1) % 3
	
	flashlight.light_color = CHANNEL_COLORS[current_channel]
	print(current_channel)
	RenderingServer.global_shader_parameter_set("vision_mode", current_channel)

func _on_stage_enter_body_entered(body: Node3D) -> void:
	print("Setting Stage!")
	get_tree().change_scene_to_file("res://scenes/main.tscn")
