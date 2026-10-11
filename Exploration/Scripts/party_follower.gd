class_name PartyFollower
extends Node3D
## Party member that moves on its own while exploring. It doesn't walk the leader's
## trail: it keeps a formation slot beside and behind the leader, and only starts
## walking (and turning) when the leader gets further than `leave_distance` from where
## they stood the last time this follower settled. It goes around walls (see Steering),
## keeps clear of the leader and the other followers, and sprints to catch up if left
## behind.
## Built by ExplorationParty from the active roster. During a fight the
## CombatSession moves it instead (combat_controlled).

@export var model_scene: PackedScene
@export_group("Formation")
## Metres behind the leader for the first row of slots.
@export var follow_distance := 2.0
## Metres to the left/right of the leader.
@export var side_spacing := 1.1
## Extra metres back for each further row (two followers per row).
@export var row_spacing := 1.0
## The leader must walk this far from where they stood when this follower last settled
## before it starts moving or turning. Until then it stays put, however the slot has
## shifted.
@export var leave_distance := 3.0
## Safety net: if the leader ends up this far from the follower, it moves anyway.
@export var max_leader_distance := 9.0
## It stops once this close to its slot.
@export var settle_radius := 0.35
@export_group("Movement")
@export var walk_speed := 3.6
## Top speed when far behind.
@export var run_speed := 6.5
## Once the leader is this much further away than leave_distance, it runs flat out.
@export var catch_up_distance := 4.5
## Further than this from the slot (stuck, or the leader teleported): snap to it.
@export var teleport_distance := 25.0
## Followers and the leader push each other apart inside this distance.
@export var separation_radius := 1.0
## How quickly velocity follows what it wants (higher = snappier).
@export var smoothing := 8.0
@export var turn_smoothing := 6.0
@export_group("Animation")
## Animation names to play, if the model has them. Empty = don't animate.
@export var idle_anim: StringName = &""
@export var walk_anim: StringName = &""
@export var run_anim: StringName = &""
@export var run_threshold := 4.5

## Roster id of the character this follower represents.
var character_id: StringName = &""
## 1, 2, 3... picks the slot: odd on the right, even on the left, one row back per pair.
var slot_index := 1
## Set by ExplorationParty; found through the party_link group if left empty.
var link: PlayerLink
var model: Node3D
var anim: AnimationPlayer
var combat_controlled := false

var _heading := Vector3(0.0, 0.0, -1.0)  # which way the leader is travelling
var _velocity := Vector3.ZERO
var _walking := false
var _placed := false
## Where the leader stood when this follower last settled; the trigger to move is the
## leader getting `leave_distance` away from here.
var _anchor := Vector3.ZERO
var _anchored := false


func _ready() -> void:
	add_to_group("party_follower")
	if model_scene != null:
		model = model_scene.instantiate() as Node3D
		if model != null:
			add_child(model)
			var players := model.find_children("*", "AnimationPlayer", true, false)
			if not players.is_empty():
				anim = players[0] as AnimationPlayer


func _physics_process(delta: float) -> void:
	if combat_controlled:
		_velocity = Vector3.ZERO
		_walking = false
		_anchored = false  # after the fight, wait for the leader to move off before following
		return
	var leader := _leader()
	if leader == null:
		return
	_update_heading(leader, delta)
	var slot := slot_position(leader)
	if not _placed:
		_placed = true
		global_position = slot
		_anchor = leader.global_position
		_anchored = true
		rotation.y = atan2(-_heading.x, -_heading.z)
		return
	if not _anchored:
		_anchor = leader.global_position
		_anchored = true

	var to_slot := slot - global_position
	to_slot.y = 0.0
	var dist := to_slot.length()
	if dist > teleport_distance:
		global_position = slot
		_velocity = Vector3.ZERO
		_walking = false
		_anchor = leader.global_position
		return

	var from_anchor := leader.global_position - _anchor
	from_anchor.y = 0.0
	var to_leader := leader.global_position - global_position
	to_leader.y = 0.0

	# Start walking once the leader has moved `leave_distance` away from where they were
	# when we last settled; stop when settled (no jitter), and note where they stand now.
	if _walking:
		if dist <= settle_radius:
			_walking = false
			_anchor = leader.global_position
	elif from_anchor.length() > leave_distance or to_leader.length() > max_leader_distance:
		_walking = true

	var want := Vector3.ZERO
	var walk_dir := Vector3.ZERO
	if _walking:
		walk_dir = Steering.direction(self, slot)
		var urgency := clampf((to_leader.length() - leave_distance) / maxf(catch_up_distance, 0.1), 0.0, 1.0)
		want = walk_dir * lerpf(walk_speed, run_speed, urgency)
	want += _separation(leader) * walk_speed
	_velocity = _velocity.lerp(want, 1.0 - exp(-smoothing * delta))
	global_position += _velocity * delta
	global_position.y = lerpf(global_position.y, leader.global_position.y,
			1.0 - exp(-8.0 * delta))

	# Turn only while walking, towards the way it is heading. Standing still, it keeps
	# whatever facing it had, even if the leader turns or something nudges it.
	if _walking and walk_dir != Vector3.ZERO:
		var yaw := atan2(-walk_dir.x, -walk_dir.z)  # forward is -Z
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-turn_smoothing * delta))
	_animate(_velocity.length())


## Where this follower wants to stand, given the leader.
func slot_position(leader: Node3D) -> Vector3:
	var back := -_heading
	var right := _heading.cross(Vector3.UP)
	var row := floori((slot_index - 1) / 2.0)
	var side := 1.0 if slot_index % 2 == 1 else -1.0
	var spot := leader.global_position + back * (follow_distance + row * row_spacing) \
			+ right * side * side_spacing
	spot.y = leader.global_position.y
	return spot


func _leader() -> CharacterBody3D:
	if link == null or not is_instance_valid(link) or link.body == null:
		link = get_tree().get_first_node_in_group("party_link") as PlayerLink
	if link == null or link.body == null:
		return null
	return link.body


## The heading only changes while the leader is actually walking forward, so turning
## on the spot (or backing up) doesn't make everyone shuffle round to a new side.
func _update_heading(leader: CharacterBody3D, delta: float) -> void:
	var facing := -leader.global_basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return
	facing = facing.normalized()
	var flat := Vector3(leader.velocity.x, 0.0, leader.velocity.z)
	if not _placed or (flat.length() > 0.5 and flat.dot(facing) > 0.0):
		var blend := 1.0 if not _placed else 1.0 - exp(-6.0 * delta)
		_heading = _heading.lerp(facing, blend).normalized()


## A push away from the leader and the other followers when too close.
func _separation(leader: Node3D) -> Vector3:
	var push := Vector3.ZERO
	var others: Array[Node3D] = [leader]
	for node in get_tree().get_nodes_in_group("party_follower"):
		if node != self and node is Node3D:
			others.append(node)
	for other in others:
		var away := global_position - other.global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.001 and d < separation_radius:
			push += away / d * ((separation_radius - d) / separation_radius)
	return push


func _animate(speed: float) -> void:
	if anim == null:
		return
	var want := idle_anim
	if speed > 0.2:
		want = run_anim if speed > run_threshold else walk_anim
	if want != &"" and anim.has_animation(want) and anim.current_animation != String(want):
		anim.play(want)
