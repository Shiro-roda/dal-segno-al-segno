extends CharacterBody3D
## Tank controls (Resident Evil 4 style): left/right turn the body, forward/back move
## along its facing. Tap back while sprinting to quick-turn 180 degrees.
## The camera is separate (drone_camera.tscn); the model, collision and the camera
## anchor markers all live in player.tscn.

@export_group("Movement")
@export var walk_speed: float = 3.5
@export var sprint_speed: float = 6.0
@export var backward_speed: float = 2.0
@export var acceleration: float = 20.0
@export var gravity: float = 24.0
@export_group("Turning")
@export var turn_speed_deg: float = 140.0
@export var sprint_turn_speed_deg: float = 100.0
@export var quick_turn_speed_deg: float = 540.0
## Switch off while dialogue or combat has the controls.
@export var controls_enabled: bool = true

var _quick_turn_left: float = 0.0


func _physics_process(delta: float) -> void:
	var drive := 0.0   # +1 forward, -1 backward
	var steer := 0.0   # +1 turn left, -1 turn right
	var sprinting := false
	if controls_enabled:
		drive = Input.get_axis("move_back", "move_forward")
		steer = Input.get_axis("move_right", "move_left")
		sprinting = Input.is_action_pressed("Sprint")
		if _quick_turn_left <= 0.0 and sprinting and Input.is_action_just_pressed("move_back"):
			_quick_turn_left = PI

	var turn_step := 0.0
	if _quick_turn_left > 0.0:
		turn_step = minf(_quick_turn_left, deg_to_rad(quick_turn_speed_deg) * delta)
		_quick_turn_left -= turn_step
		drive = 0.0
	else:
		var rate := sprint_turn_speed_deg if sprinting else turn_speed_deg
		turn_step = steer * deg_to_rad(rate) * delta
	rotate_y(turn_step)

	var facing := -global_transform.basis.z
	var speed := backward_speed
	if drive > 0.0:
		speed = sprint_speed if sprinting else walk_speed
	var target := facing * drive * speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()
