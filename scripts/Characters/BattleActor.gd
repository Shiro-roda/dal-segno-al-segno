extends Node3D
class_name BattleActor

signal turn_finished
signal died

enum Team { PLAYER, ENEMY }
@export var team : Team

@export var max_hp : int = 10
@export var attack_power : int = 3
@export var body_parts : Array[BodyPartData]


var hp : int

func _ready():
	hp = max_hp
	
	add_to_group("battle_actor")


func take_turn(target: BattleActor, part: BodyPartData = null) -> void:
	await get_tree().create_timer(0.1).timeout
	if part == null:
		await attack(target)
	else:
		await attack_part(target, part)
	
	


func spend_turn():
	emit_signal("turn_finished")


func attack(target: BattleActor) -> void:
	
	await play_attack_animation(target)
	target.take_damage(attack_power)



	emit_signal("turn_finished")


func attack_part(target: BattleActor, part: BodyPartData) -> void:
	await play_attack_animation(target)
	
	var damage = attack_power * part.damage_multiplier
	target.take_damage(damage)

	emit_signal("turn_finished")



func take_damage(amount: int):
	
	hp -= amount
	print(name, " takes ", amount, " damage, ", hp, " hp remaining.")
	
	if hp <= 0:
		hp = 0
		emit_signal("died", self)
		queue_free()

func is_alive() -> bool:
	return hp > 0

func get_visible_parts(current_mask: int) -> Array[BodyPartData]:
	var visible : Array[BodyPartData] = []

	for part in body_parts:
		if part.base_visible:
			visible.append(part)
			continue

		if (current_mask & part.required_removed_mask) == part.required_removed_mask:
			visible.append(part)

	return visible

func update_shader_visibility(mask: int):
	pass


func use_lens(channel: int):
	# Ask manager to apply lens effect
	var manager = get_tree().get_first_node_in_group("battle_manager")
	print("Lens added: ", channel)
	manager.apply_lens(channel)

	spend_turn()

func play_attack_animation(target: BattleActor) -> void:
	
	var manager = get_tree().get_first_node_in_group("battle_manager")
	manager.active_cam.follow_damping = false
	manager.target_cam.follow_damping = false

	var original_pos = global_position
	var direction = (target.global_position - global_position).normalized()
	
	var windup_pos = original_pos - direction * 0.1
	var lunge_pos = (original_pos + direction * 0.5) - windup_pos
	
	var windup_tween := create_tween()
	windup_tween.set_trans(Tween.TRANS_QUAD)
	windup_tween.set_ease(Tween.EASE_IN_OUT)

	windup_tween.tween_property(self, "global_position", windup_pos, 0.3)
	await windup_tween.finished

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT_IN)
	

	tween.tween_property(self, "global_position", lunge_pos, 0.22)
	await tween.finished
	
	# IMPACT MOMENT
	var impact_dir = (global_position - target.global_position).normalized()
	
	manager.screen_shake_on_actor(target, impact_dir, 2.0, 0.5)
	
	

	

	
	var back_tween = create_tween()
	back_tween.set_trans(Tween.TRANS_QUAD)
	back_tween.set_ease(Tween.EASE_IN_OUT)

	back_tween.tween_property(self, "global_position", original_pos, 0.3)
	await back_tween.finished
	
	manager.active_cam.follow_damping = true
	manager.target_cam.follow_damping = true
	
	await get_tree().create_timer(1.0).timeout
