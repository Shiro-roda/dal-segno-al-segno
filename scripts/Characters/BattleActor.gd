extends Node3D
class_name BattleActor

signal turn_finished
signal died
signal hp_changed
signal status_applied(effect_id: String)
signal battle_log(message: String)  # general battle narration
signal chatter(message: String)      # character voice line

# --- Status effect IDs ---
const STATUS_FROZEN   = "frozen"   # tempo stops accumulating
const STATUS_SLOW     = "slow"     # tempo accumulates at reduced rate
const STATUS_BLEEDING = "bleeding" # takes damage each turn
const STATUS_LEECHED  = "leeched"  # heals attacker on hit
const STATUS_DODGING  = "dodging"  # chance to dodge incoming attacks
const STATUS_SHIELD   = "shield"   # has temporary HP buffer
const STATUS_COVERED  = "covered"  # damage redirected to another actor

const DODGE_CHANCE          = 0.5
const STRUGGLE_MISS_CHANCE  = 0.35
const STRUGGLE_SELF_CHANCE  = 0.25
const SLOW_TEMPO_MULT       = 0.4  # slowed actors gain 40% of normal tempo

# Active effects: Array of {id, duration} dictionaries
var active_effects : Array = []

enum Team { PLAYER, ENEMY }
@export var team : Team

@export var max_hp : int = 10
@export var attack_power : int = 3
@export var tempo_stat : int = 10    # base tempo gained per turn
@export var body_parts : Array[BodyPartData]
var party_member : PartyMemberData
var run_state : RunState
@onready var camera_anchor: Node3D = $CameraAnchor

var perishing := false
var hp : int
var tempo_pool : float = 0.0          # accumulated tempo
var tempo_bonus : float = 0.0         # temporary flat bonus (e.g. from Evade/Augur)
var cover_source : BattleActor = null # actor absorbing damage on our behalf
var shield_hp : int = 0               # temporary HP from Shelter

func _ready():
	print(hp)
	add_to_group("battle_actor")


func take_turn(target: BattleActor, part: BodyPartData = null) -> void:
	await get_tree().create_timer(0.1).timeout
	tick_status_effects()
	if not is_alive():
		emit_signal("turn_finished")
		return
	if has_status(STATUS_FROZEN):
		log_msg("%s is frozen and cannot act." % name)
		spend_turn()
		return
	# All player attacks target a body part; enemies call with part = null
	if part != null:
		await attack_part(target, part)
	else:
		await attack(target)
	
	


func spend_turn():
	emit_signal("turn_finished")


func attack(target: BattleActor) -> void:
	await play_attack_animation(target, attack_power, 2.0, attack_power)



	emit_signal("turn_finished")


func attack_part(target: BattleActor, part: BodyPartData) -> void:
	var damage = attack_power * part.damage_multiplier
	if part.is_cognitohazard:
		perishing = true
	await play_attack_animation(target, 2.0, damage, damage)
	

	emit_signal("turn_finished")



func take_damage(amount: int, attacker: BattleActor = null) -> void:
	if has_status(STATUS_DODGING) and randf() < DODGE_CHANCE:
		log_msg("%s dodges!" % name)
		return
	# Cover redirect: another actor is absorbing damage for us
	if cover_source != null and cover_source.is_alive() and cover_source != attacker:
		cover_source.take_damage(int(amount * 0.85), attacker)  # 15% reduction
		return
	# Shield: absorb with temporary HP first
	if shield_hp > 0:
		if amount <= shield_hp:
			shield_hp -= amount
			if shield_hp == 0:
				active_effects = active_effects.filter(func(e): return e["id"] != STATUS_SHIELD)
			emit_signal("hp_changed")
			return
		else:
			amount -= shield_hp
			shield_hp = 0
			active_effects = active_effects.filter(func(e): return e["id"] != STATUS_SHIELD)
	hp -= amount
	emit_signal("hp_changed")
	log_msg("%s takes %d damage. (%d HP)" % [name, amount, max(0, hp)])

	# Leech: any attacker hitting a leeched target regains HP.
	# on_leech_proc also fires so characters like Vritra can restore will on top.
	if attacker and has_status(STATUS_LEECHED):
		var heal = max(1, amount / 2)
		attacker.hp = min(attacker.hp + heal, attacker.max_hp)
		attacker.emit_signal("hp_changed")
		log_msg("%s leeches %d HP from %s." % [attacker.name, heal, name])
		attacker.on_leech_proc(heal)

	if hp <= 0:
		hp = 0
		log_msg("%s has fallen." % name)
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


# --- Log / chatter helpers ---

func log_msg(msg: String) -> void:
	emit_signal("battle_log", msg)

func say(msg: String) -> void:
	emit_signal("chatter", msg)

func say_random(lines: Array) -> void:
	if lines.is_empty(): return
	say(lines[randi() % lines.size()])


# --- Status effect helpers ---

func apply_status(effect_id: String, duration: int) -> void:
	# Refresh duration if already present, otherwise add
	for effect in active_effects:
		if effect["id"] == effect_id:
			effect["duration"] = max(effect["duration"], duration)
			return
	active_effects.append({"id": effect_id, "duration": duration})
	emit_signal("status_applied", effect_id)

func has_status(effect_id: String) -> bool:
	return active_effects.any(func(e): return e["id"] == effect_id)

func tick_status_effects() -> void:
	var to_remove := []
	for effect in active_effects:
		match effect["id"]:
			STATUS_BLEEDING:
				var bleed_dmg = max(1, max_hp / 10)
				take_damage(bleed_dmg)
		effect["duration"] -= 1
		if effect["duration"] <= 0:
			to_remove.append(effect)
	for e in to_remove:
		active_effects.erase(e)
	# Clear cover reference if STATUS_COVERED expired
	if not has_status(STATUS_COVERED):
		cover_source = null

# Called each round by battle_manager before picking the next actor.
# Adds tempo based on stat, modified by slow/freeze.
func tick_tempo() -> void:
	if has_status(STATUS_FROZEN):
		return  # no tempo gain while frozen
	var gain = tempo_stat
	if has_status(STATUS_SLOW):
		gain *= SLOW_TEMPO_MULT
	tempo_pool += randf_range(0, gain) + randf_range(0, tempo_bonus) 

func reset_tempo_bonus() -> void:
	tempo_bonus = 0.0

# Called when this actor strikes a leeched target. Override for character-specific behaviour.
func on_leech_proc(_heal_amount: int) -> void:
	pass

# --- Skill system ---

# Override in subclasses to return this character's available skills.
# Returns Array of SkillData. battle_manager calls this to build UI buttons.
func get_skills() -> Array:
	return []

# Dispatch a skill by command key. Override or extend in subclasses.
func use_skill(command_key: String, targets: Array) -> void:
	spend_turn()

# Convenience: pick a random living enemy/ally from a list
func random_living(actors: Array) -> BattleActor:
	var alive = actors.filter(func(a): return a.is_alive() and a != self)
	if alive.is_empty(): return null
	return alive[randi() % alive.size()]

# Struggle attack: random target, chance to miss, no status, chance of self-damage
func struggle_attack(all_actors: Array, base_damage: int) -> void:
	var enemies = all_actors.filter(func(a): return a.team != team and a.is_alive())
	if enemies.is_empty():
		spend_turn()
		return
	var target = enemies[randi() % enemies.size()]
	if randf() < STRUGGLE_MISS_CHANCE:
		print(name, " swings wildly and misses!")
		spend_turn()
		return
	await play_attack_animation(target, 1.0, 1.0, base_damage)
	if randf() < STRUGGLE_SELF_CHANCE:
		var self_dmg = max(1, base_damage / 2)
		print(name, " hurts themselves for ", self_dmg, " in the struggle!")
		take_damage(self_dmg)
	emit_signal("turn_finished")

func use_lens(channel: int):
	# Ask manager to apply lens effect
	var manager = get_tree().get_first_node_in_group("battle_manager")
	print("Lens added: ", channel)
	manager.apply_lens(channel)
	spend_turn()

func play_attack_animation(target: BattleActor, player_mult, enemy_mult, damage : int = 0) -> void:
	
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
	
	
	
	
	manager.screen_shake(self, target, impact_dir, player_mult, enemy_mult)

	

	

	
	var back_tween = create_tween()
	back_tween.set_trans(Tween.TRANS_QUAD)
	back_tween.set_ease(Tween.EASE_IN_OUT)

	back_tween.tween_property(self, "global_position", original_pos, 0.3)
	await back_tween.finished
	
	target.take_damage(damage, self)
	if perishing:
		print("You saw something you shouldn't have.")
		emit_signal("turn_finished")
		take_damage(damage)
		perishing = false

	
	await get_tree().create_timer(1.0).timeout
