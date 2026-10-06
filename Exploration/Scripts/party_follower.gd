class_name PartyFollower
extends Node3D
## Party member that trails the player along its breadcrumb path (PlayerLink).
## Built by ExplorationParty from the active roster.

@export var model_scene: PackedScene
@export var follow_distance := 1.4
@export var smoothing := 10.0
@export var turn_smoothing := 12.0
## Animation names to play, if the model has them. Empty = don't animate.
@export var idle_anim: StringName = &""
@export var walk_anim: StringName = &""
@export var run_anim: StringName = &""
@export var run_threshold := 4.5

## Roster id of the character this follower represents.
var character_id: StringName = &""
var model: Node3D
var anim: AnimationPlayer

var _link: PlayerLink


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
	if _link == null or not is_instance_valid(_link) or _link.body == null:
		_link = get_tree().get_first_node_in_group("party_link") as PlayerLink
		if _link != null and _link.body != null:
			global_position = _link.get_trail_point(follow_distance)
			rotation.y = _link.body.rotation.y
		return

	var old := global_position
	var target := _link.get_trail_point(follow_distance)
	global_position = old.lerp(target, 1.0 - exp(-smoothing * delta))

	var step := global_position - old
	step.y = 0.0
	var speed := step.length() / maxf(delta, 0.0001)
	if step.length() > 0.001:
		# Forward is -Z.
		var yaw := atan2(-step.x, -step.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-turn_smoothing * delta))
	_animate(speed)


func _animate(speed: float) -> void:
	if anim == null:
		return
	var want := idle_anim
	if speed > 0.2:
		want = run_anim if speed > run_threshold else walk_anim
	if want != &"" and anim.has_animation(want) and anim.current_animation != String(want):
		anim.play(want)
