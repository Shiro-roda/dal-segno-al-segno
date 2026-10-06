extends Node3D
## "Drone" camera. This body chases an anchor point over the player's shoulder using
## spring physics, so it lags behind, then catches up with a little overshoot, and it
## looks at a point ahead of the player. The child Camera3D adds banking into sideways
## movement and a faint idle sway.
##
## It finds its targets through groups, so no cross-scene wiring is needed:
##   "camera_anchor" - where the drone wants to be   (a Marker3D on the player)
##   "camera_look"   - what the drone looks at       (a Marker3D on the player)
##
## A PhantomCameraHost sits on the Camera3D, so any PhantomCamera3D you make active
## (cutscenes, dialogue framing) will take the view over from the drone.

@export_group("Chase")
## Spring stiffness in rad/s. Higher = snappier, lower = lazier.
@export var chase_frequency: float = 2.2
## Below 1 the drone overshoots and settles (momentum); 1 is critically damped.
@export_range(0.1, 1.5, 0.05) var damping_ratio: float = 0.7
## How quickly the view turns toward the look target.
@export var look_smoothing: float = 2.5
@export_group("Drone feel")
## Radians of roll per m/s of sideways drift.
@export var bank_amount: float = 0.025
@export var max_bank: float = 0.14
@export var bank_smoothing: float = 4.0
## Idle sway, in meters. Set 0 to turn off.
@export var sway_distance: float = 0.05
@export var sway_speed: float = 0.8

@onready var camera: Camera3D = $Camera

var _anchor: Node3D
var _look: Node3D
var _drift := Vector3.ZERO
var _time: float = 0.0


func _process(delta: float) -> void:
	if _anchor == null or _look == null:
		_find_targets()
		return

	var dt := minf(delta, 1.0 / 30.0)

	# Spring-damper toward the anchor: acceleration pulls toward the goal, drag resists motion.
	var goal := _anchor.global_position
	var omega := chase_frequency
	var accel := omega * omega * (goal - global_position) - 2.0 * damping_ratio * omega * _drift
	_drift += accel * dt
	global_position += _drift * dt

	# Ease the view toward the look target.
	var to_look := _look.global_position - global_position
	if to_look.length_squared() > 0.001:
		var wanted := Basis.looking_at(to_look.normalized(), Vector3.UP)
		var blend := 1.0 - exp(-look_smoothing * dt)
		global_basis = Basis(Quaternion(global_basis.orthonormalized()).slerp(Quaternion(wanted), blend))

	# Bank into sideways drift, and sway a little while idle.
	var sideways := _drift.dot(global_basis.x)
	var bank := clampf(-sideways * bank_amount, -max_bank, max_bank)
	camera.rotation.z = lerpf(camera.rotation.z, bank, 1.0 - exp(-bank_smoothing * dt))
	_time += dt
	camera.position = Vector3(sin(_time * sway_speed * 1.3), sin(_time * sway_speed * 1.9) * 0.6, 0.0) * sway_distance


func _find_targets() -> void:
	_anchor = get_tree().get_first_node_in_group("camera_anchor") as Node3D
	_look = get_tree().get_first_node_in_group("camera_look") as Node3D
	if _anchor == null or _look == null:
		return
	# Start already in place instead of flying in from the origin.
	global_position = _anchor.global_position
	_drift = Vector3.ZERO
	var to_look := _look.global_position - global_position
	if to_look.length_squared() > 0.001:
		global_basis = Basis.looking_at(to_look.normalized(), Vector3.UP)
