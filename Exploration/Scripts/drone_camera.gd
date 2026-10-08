extends Node3D
## "Drone" camera. This body chases a goal point using spring physics, so it lags behind,
## then catches up with a little overshoot, and it looks at a focus point. The child
## Camera3D adds banking into sideways movement and a faint idle sway.
##
## It has several perspectives (Mode). Press the cycle action (C by default) to step
## through them, or call set_mode() from anywhere. When the perspective changes the
## camera swings around the party leader to its new position instead of flying through them.
##   DRONE     the original: over the player's shoulder, loose and floaty.
##   CLOSE     close behind the leader and much tighter; follows turns closely.
##   FRONT     in front of the leader, looking back at their face.
##   OVERHEAD  high above, not turning with the leader.
##
## It finds its targets through groups, so no cross-scene wiring is needed:
##   "camera_anchor" - where the drone wants to be   (a Marker3D on the player)
##   "camera_look"   - what the drone looks at       (a Marker3D on the player)
##   "party_leader"  - the leader's body, which the other perspectives are built around
##   (this node joins "drone_camera", so get_tree().call_group() can reach it)
##
## A PhantomCameraHost sits on the Camera3D, so any PhantomCamera3D you make active
## (cutscenes, dialogue framing) will take the view over from the drone.

## Emitted after the perspective changes, so a HUD can show its name.
signal mode_changed(new_mode: Mode)

enum Mode { DRONE, CLOSE, FRONT, OVERHEAD }

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

@export_group("Perspective")
## Which perspective the camera uses right now.
@export var mode: Mode = Mode.DRONE:
	set = set_mode
## Input action that steps to the next perspective. Ignored if the action doesn't exist.
@export var cycle_action: StringName = &"camera_cycle"
## How quickly the camera swings around the leader when the perspective changes.
@export var swing_smoothing: float = 4.0

@export_group("Close follow")
## Camera position in the leader's own space. Forward is -Z, so +Z is behind them.
@export var close_offset := Vector3(0.0, 2.2, 3.2)
## What it looks at, in the same space.
@export var close_look := Vector3(0.0, 1.3, -2.0)
@export var close_chase_frequency: float = 7.0
@export_range(0.1, 1.5, 0.05) var close_damping_ratio: float = 0.95
@export var close_look_smoothing: float = 9.0
## How quickly the camera's offset turns with the leader. Higher keeps it glued behind.
@export var close_turn_smoothing: float = 6.0

@export_group("Front")
## Camera position in the leader's own space: -Z is in front of them.
@export var front_offset := Vector3(0.0, 1.8, -3.6)
## What it looks at, in the same space: their chest and face.
@export var front_look := Vector3(0.0, 1.35, 0.0)
@export var front_chase_frequency: float = 5.0
@export_range(0.1, 1.5, 0.05) var front_damping_ratio: float = 0.9
@export var front_look_smoothing: float = 8.0
@export var front_turn_smoothing: float = 4.0

@export_group("Overhead")
## Offset from the leader in world space. It does not turn with them.
@export var overhead_offset := Vector3(0.0, 14.0, 5.0)
## What it looks at, relative to the leader.
@export var overhead_look := Vector3(0.0, 0.5, 0.0)
@export var overhead_chase_frequency: float = 3.0
@export_range(0.1, 1.5, 0.05) var overhead_damping_ratio: float = 1.0
@export var overhead_look_smoothing: float = 5.0

@export_group("Manual control")
## While a fight is running the party's controls are locked, so the turn and move keys
## steer the camera instead: left/right orbit the party, forward/back zoom. Works while
## the fight is paused too, since fights start paused.
@export var combat_orbit_speed_deg: float = 100.0
@export var combat_zoom_speed: float = 1.2
## Closest and furthest zoom, as a multiple of the perspective's normal distance.
@export var zoom_range := Vector2(0.45, 2.2)
## How quickly an orbit or zoom eases back to normal once the fight ends.
@export var control_release_smoothing: float = 3.0

## Banking and idle sway are scaled per perspective (indexed by Mode).
const BANK_SCALE: Array[float] = [1.0, 0.5, 0.5, 0.0]
const SWAY_SCALE: Array[float] = [1.0, 0.3, 0.5, 0.2]

@onready var camera: Camera3D = $Camera

var _anchor: Node3D
var _look: Node3D
var _leader: Node3D
var _drift := Vector3.ZERO
var _time: float = 0.0
## The leader's heading, smoothed. The close perspectives are built around this.
var _facing_yaw := 0.0
## How far round the leader the camera still is from where its perspective wants it.
## Set when the perspective changes, then eases back to zero.
var _swing_yaw := 0.0
# The current perspective's spring settings (see _load_params).
var _chase_frequency := 2.2
var _damping := 0.7
var _look_smoothing := 2.5
var _turn_smooth := 6.0
## The perspective lives here, not on the node, so a camera in a newly loaded scene
## starts in whichever one the player chose last instead of its scene's default.
static var _remembered_mode := -1
## Player-steered orbit round the party and zoom, active during fights.
var _orbit_yaw := 0.0
var _zoom := 1.0


func _ready() -> void:
	add_to_group(&"drone_camera")
	# Properties from the scene are applied before this runs, so this overrides the
	# scene's default with the remembered perspective.
	if _remembered_mode >= 0 and _remembered_mode != int(mode):
		mode = _remembered_mode as Mode


func _unhandled_input(event: InputEvent) -> void:
	if cycle_action != &"" and InputMap.has_action(cycle_action) and event.is_action_pressed(cycle_action):
		cycle_mode()
		get_viewport().set_input_as_handled()


# ── Perspectives ─────────────────────────────────────────────────────────────
## Switches perspective. The camera swings round the leader to the new view.
func set_mode(value: Mode) -> void:
	if value == mode:
		return
	mode = value
	# Only remember changes made once in the tree: the scene file's own value is applied
	# while loading and must not overwrite what the player picked.
	if is_inside_tree():
		_remembered_mode = int(value)
	_begin_swing()
	if is_inside_tree():
		mode_changed.emit(mode)


## Steps to the next perspective, wrapping round.
func cycle_mode() -> void:
	set_mode(((int(mode) + 1) % Mode.size()) as Mode)


func mode_name() -> String:
	return String(Mode.keys()[mode]).capitalize()


## Jumps straight to the current perspective, with no swing or flight. Call it after
## the party is teleported (PlayerLink.teleport_to does).
func snap_to_target() -> void:
	if _anchor == null or _look == null:
		return
	if _leader != null and is_instance_valid(_leader):
		_facing_yaw = _leader.global_rotation.y
	_swing_yaw = 0.0
	_drift = Vector3.ZERO
	var active := _effective_mode()
	var leader_pos := _leader_position()
	global_position = leader_pos + _base_offset(active, leader_pos)
	var to_look := _look_point(active, leader_pos) - global_position
	if to_look.length_squared() > 0.001:
		global_basis = Basis.looking_at(to_look.normalized(), Vector3.UP)


## Without a leader to build around, every perspective falls back to the drone's markers.
func _effective_mode() -> Mode:
	return mode if _leader != null and is_instance_valid(_leader) else Mode.DRONE


func _leader_position() -> Vector3:
	if _leader != null and is_instance_valid(_leader):
		return _leader.global_position
	return _anchor.global_position


## Where the camera wants to be, as an offset from the leader (before any swing).
func _base_offset(active: Mode, leader_pos: Vector3) -> Vector3:
	match active:
		Mode.CLOSE:
			return Basis(Vector3.UP, _facing_yaw) * close_offset
		Mode.FRONT:
			return Basis(Vector3.UP, _facing_yaw) * front_offset
		Mode.OVERHEAD:
			return overhead_offset
	return _anchor.global_position - leader_pos


## What the camera looks at.
func _look_point(active: Mode, leader_pos: Vector3) -> Vector3:
	match active:
		Mode.CLOSE:
			return leader_pos + Basis(Vector3.UP, _facing_yaw) * close_look
		Mode.FRONT:
			return leader_pos + Basis(Vector3.UP, _facing_yaw) * front_look
		Mode.OVERHEAD:
			return leader_pos + overhead_look
	return _look.global_position


func _load_params(active: Mode) -> void:
	match active:
		Mode.CLOSE:
			_chase_frequency = close_chase_frequency
			_damping = close_damping_ratio
			_look_smoothing = close_look_smoothing
			_turn_smooth = close_turn_smoothing
		Mode.FRONT:
			_chase_frequency = front_chase_frequency
			_damping = front_damping_ratio
			_look_smoothing = front_look_smoothing
			_turn_smooth = front_turn_smoothing
		Mode.OVERHEAD:
			_chase_frequency = overhead_chase_frequency
			_damping = overhead_damping_ratio
			_look_smoothing = overhead_look_smoothing
			_turn_smooth = 6.0
		_:
			_chase_frequency = chase_frequency
			_damping = damping_ratio
			_look_smoothing = look_smoothing
			_turn_smooth = 6.0


## Remembers which side of the leader the camera is on, relative to where the new
## perspective wants it, so it can swing round them instead of cutting through.
func _begin_swing() -> void:
	if _anchor == null or _leader == null or not is_instance_valid(_leader) or not is_inside_tree():
		return
	var leader_pos := _leader.global_position
	var base := _base_offset(_effective_mode(), leader_pos)
	var here := global_position - leader_pos
	here.y = 0.0
	base.y = 0.0
	if here.length_squared() > 0.01 and base.length_squared() > 0.01:
		_swing_yaw = wrapf(atan2(here.x, here.z) - atan2(base.x, base.z), -PI, PI)


func _process(delta: float) -> void:
	# A paused game freezes the camera outright: no chase, sway or banking.
	if get_tree().paused:
		return
	if _anchor == null or _look == null:
		_find_targets()
		return

	if _leader == null or not is_instance_valid(_leader):
		_leader = get_tree().get_first_node_in_group("party_leader") as Node3D

	var dt := minf(delta, 1.0 / 30.0)
	var active := _effective_mode()
	_load_params(active)

	# During a fight the party is locked, so the player steers the camera. Idle sway and
	# banking hold still while the fight is paused.
	var fight := _active_fight()
	var fight_paused: bool = fight != null and bool(fight.get("paused"))
	_update_manual_control(dt, fight != null)

	# Where the leader is and which way they face. The heading is smoothed so the close
	# perspectives trail a turn instead of snapping with it.
	var leader_pos := _leader_position()
	if _leader != null and is_instance_valid(_leader):
		_facing_yaw = lerp_angle(_facing_yaw, _leader.global_rotation.y, 1.0 - exp(-_turn_smooth * dt))
	# After a perspective change the camera starts on the side of the leader it was on and
	# swings round to the new one.
	_swing_yaw = lerp_angle(_swing_yaw, 0.0, 1.0 - exp(-swing_smoothing * dt))

	# Spring-damper toward the goal: acceleration pulls toward it, drag resists motion.
	var goal := leader_pos + Basis(Vector3.UP, _swing_yaw + _orbit_yaw) * (_base_offset(active, leader_pos) * _zoom)
	var omega := _chase_frequency
	var accel := omega * omega * (goal - global_position) - 2.0 * _damping * omega * _drift
	_drift += accel * dt
	global_position += _drift * dt

	# Ease the view toward the look target.
	var to_look := _look_point(active, leader_pos) - global_position
	if to_look.length_squared() > 0.001:
		var wanted := Basis.looking_at(to_look.normalized(), Vector3.UP)
		var blend := 1.0 - exp(-_look_smoothing * dt)
		global_basis = Basis(Quaternion(global_basis.orthonormalized()).slerp(Quaternion(wanted), blend))

	# Bank into sideways drift, and sway a little while idle. Both hold still while a
	# fight is paused.
	if not fight_paused:
		var sideways := _drift.dot(global_basis.x)
		var bank := clampf(-sideways * bank_amount * BANK_SCALE[active], -max_bank, max_bank)
		camera.rotation.z = lerpf(camera.rotation.z, bank, 1.0 - exp(-bank_smoothing * dt))
		_time += dt
	camera.position = Vector3(sin(_time * sway_speed * 1.3), sin(_time * sway_speed * 1.9) * 0.6, 0.0) * sway_distance * SWAY_SCALE[active]


## The CombatSession that is running a fight right now, or null.
func _active_fight() -> Node:
	for session in get_tree().get_nodes_in_group(&"combat_session"):
		if bool(session.get("active")):
			return session
	return null


## Left/right orbit the party and forward/back zoom while a fight is on (the same keys
## that walk the party when it is free). Outside a fight the view eases back to normal.
func _update_manual_control(dt: float, in_fight: bool) -> void:
	if in_fight:
		var orbit_input := Input.get_axis(&"move_left", &"move_right")
		var zoom_input := Input.get_axis(&"move_forward", &"move_back")  # forward = closer
		_orbit_yaw = wrapf(_orbit_yaw + orbit_input * deg_to_rad(combat_orbit_speed_deg) * dt, -PI, PI)
		_zoom = clampf(_zoom + zoom_input * combat_zoom_speed * dt, zoom_range.x, zoom_range.y)
	else:
		var release := 1.0 - exp(-control_release_smoothing * dt)
		_orbit_yaw = lerp_angle(_orbit_yaw, 0.0, release)
		_zoom = lerpf(_zoom, 1.0, release)


func _find_targets() -> void:
	_anchor = get_tree().get_first_node_in_group("camera_anchor") as Node3D
	_look = get_tree().get_first_node_in_group("camera_look") as Node3D
	if _anchor == null or _look == null:
		return
	_leader = get_tree().get_first_node_in_group("party_leader") as Node3D
	# Start already in place instead of flying in from the origin.
	snap_to_target()
