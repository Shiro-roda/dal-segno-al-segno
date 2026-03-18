extends Node3D
class_name BattleActor

signal turn_finished
signal died
signal hp_changed
signal status_applied(effect_id: String)
signal battle_log(message: String)  # general battle narration
signal chatter(message: String, speaker: String)  # character voice line

# --- Status effect IDs ---
const STATUS_FROZEN   = "frozen"   # tempo stops accumulating
const STATUS_SLOW     = "slow"     # tempo accumulates at reduced rate
const STATUS_BLEEDING = "bleeding" # takes damage each turn
const STATUS_LEECHED  = "leeched"  # heals attacker on hit
const STATUS_DODGING  = "dodging"  # chance to dodge incoming attacks
const STATUS_SHIELD   = "shield"   # has temporary HP buffer
const STATUS_COVERED  = "covered"  # damage redirected to another actor
const STATUS_LIFESTEAL = "lifesteal"
const STATUS_MALICE = "malice"
const STATUS_MARTYR = "martyr"




const DODGE_CHANCE          = 0.5
const STRUGGLE_MISS_CHANCE  = 0.35
const STRUGGLE_SELF_CHANCE  = 0.25
const SLOW_TEMPO_MULT       = 0.4  # slowed actors gain 40% of normal tempo
const LIFESTEAL_RATIO = 0.5
const WITHER_DRAIN_CHANCE = 0.6


# Active effects: Array of {id, duration} dictionaries
var active_effects : Array = []

enum Team { PLAYER, ENEMY }
@export var team : Team

@export var max_hp : int = 10
@export var attack_power : int = 3
## Locked at battle-start value — never modified directly.
## All buffs/debuffs go through attack_modifier instead.
var base_attack_power : int = 0
## Flat modifier applied on top of base. Capped to [-base+1, +base].
var attack_modifier : int = 0

@export var flat_defense : int = 0
var base_flat_defense : int = 0
var flat_modifier : int = 0

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
var malice_source : BattleActor = null
var martyr_bonus_damage : int = 0
var martyr_tempo_bonus : float = 0.0



## Effective Sharp value used for all damage calculations.
## Always at least 1.
func effective_attack() -> int:
	return max(1, base_attack_power + attack_modifier)


## Apply a Sharp buff (positive) or debuff (negative).
## Caps so the actor can't exceed double base or drop below 1.
func modify_attack(delta: int) -> void:
	var cap_high : int =  base_attack_power
	var cap_low  : int = -(base_attack_power - 1)
	attack_modifier = clampi(attack_modifier + delta, cap_low, cap_high)
	attack_power = effective_attack()


## Effective Flat defense value. Always >= 0.
func effective_flat() -> int:
	return max(0, base_flat_defense + flat_modifier)


## Apply a Flat buff (positive) or debuff (negative).
## Capped at +100% of base; cannot go below 0.
func modify_flat(delta: int) -> void:
	var cap_high : int = base_flat_defense
	var cap_low  : int = -base_flat_defense
	flat_modifier = clampi(flat_modifier + delta, cap_low, cap_high)
	flat_defense  = effective_flat()


func _ready():
	print(hp)
	base_attack_power = attack_power
	base_flat_defense = flat_defense
	add_to_group("battle_actor")
	var panel = find_child("WorldSpacePanel", true, false)
	if panel and panel.has_method("setup"):
		panel.setup(self)


func take_turn(target: BattleActor, part: BodyPartData = null) -> void:
	await get_tree().create_timer(0.1).timeout
	if not is_inside_tree():
		return
	tick_status_effects()
	# Encasement breaks the moment the actor takes a turn.
	active_effects = active_effects.filter(func(e): return e["id"] != "encased")
	if not is_alive() or not is_inside_tree():
		emit_signal("turn_finished")
		return
	if not is_instance_valid(target) or not target.is_alive():
		# Target already dead; skip attack, still end turn
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
	if has_status("encased"):
		amount = int(amount * 0.6)
	if has_status(STATUS_DODGING) and randf() < DODGE_CHANCE:
		log_msg("%s dodges!" % name)
		return
	# Cover redirect: another actor is absorbing damage for us
	if cover_source != null and cover_source.is_alive() and cover_source != attacker:
		amount *= 0.65
		if cover_source != self:
			cover_source.take_damage(int(amount), attacker)  # 15% reduction
			cover_source.party_member.will += int(amount)
			log_msg("Hue takes the blow for %s." % [name])
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
	# Flat defense: damage = Sharp² / (Sharp + Flat). Always at least 1.
	var flat : int = effective_flat()
	if flat > 0:
		amount = max(1, int(float(amount * amount) / float(amount + flat)))
	hp -= amount
	emit_signal("hp_changed")
	log_msg("%s takes %d damage. (%d CORP)" % [name, amount, max(0, hp)])
		# Martyr pain conversion
	if has_status(STATUS_MARTYR):

		var stored = int(amount * 0.5)

		martyr_bonus_damage += stored

		log_msg("%s drinks deeply from the cup of wrath. (+%d stored damage)" % [name, stored])

		# Malice counter
	if has_status(STATUS_MALICE) and attacker != null and is_alive():
		var counter_damage = max(1, attack_power)

		log_msg("%s returns the blow." % name)
		
		await get_tree().create_timer(0.15).timeout
		await play_attack_animation(attacker, 1.0, 1.0, counter_damage)

		# Reward Vritra
		if malice_source != null and malice_source.party_member:
			var will_gain = max(1, int(counter_damage * 0.5))
			malice_source.party_member.restore_will(will_gain)

			malice_source.log_msg(
				"%s feeds on the spite — restores %d AP."
				% [malice_source.name, will_gain]
			)


	# Leech: any attacker hitting a leeched target regains HP.
	# on_leech_proc also fires so characters like Vritra can restore will on top.
	if attacker and has_status(STATUS_LEECHED):
		var heal = max(1, amount / 2)
		attacker.hp = min(attacker.hp + heal, attacker.max_hp)
		attacker.emit_signal("hp_changed")
		log_msg("%s leeches %d CORP from %s." % [attacker.name, heal, name])
		attacker.on_leech_proc(heal)

	if hp <= 0:
		hp = 0
		log_msg("%s has fallen." % name)
		emit_signal("died", self)
		# Do NOT queue_free here — manager handles cleanup in _on_actor_died
		# so that any in-progress coroutines don't access freed nodes

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
	emit_signal("chatter", msg, self.name)

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
		# "encased" has no duration -- it persists until cleared by take_turn.
		if effect["id"] == "encased":
			continue
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
	if not has_status(STATUS_MALICE):
		malice_source = null


# Called each round by battle_manager before picking the next actor.
# Adds tempo based on stat, modified by slow/freeze.
func tick_tempo() -> void:
	if has_status(STATUS_FROZEN):
		return  # no tempo gain while frozen
	var gain : float = float(tempo_stat)
	if has_status(STATUS_SLOW):
		gain *= SLOW_TEMPO_MULT
	# Small jitter breaks ties between equal-stat actors without distorting the scale.
	# Full gain is deterministic; randf_range adds at most +/-5% of one stat point.
	var martyr_bonus := 0.0

	if has_status(STATUS_MARTYR):
		martyr_bonus = martyr_tempo_bonus

	tempo_pool += gain + randf_range(-0.5, 0.5) + tempo_bonus + martyr_bonus


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
func use_skill(command_key: String, targets: Array, part: BodyPartData = null) -> void:
	spend_turn()

# AI turn entry point for enemies that have skills (e.g. boss enemies).
# Consults get_skills(), picks an action, and executes it.
# Falls back to take_turn(target) if no skills are available.
func enemy_take_turn(target: BattleActor) -> void:
	var skills := get_skills()
	if skills.is_empty():
		await take_turn(target)
		return

	var opponents : Array = get_opponents()
	var allies    : Array = get_allies()

	var attacks  : Array = skills.filter(func(s): return s.get("key") == "attack")
	var specials : Array = skills.filter(func(s): return s.get("key") == "special")
	# Only include ally-support skills when there are living allies to use them on
	var supports : Array = skills.filter(func(s):
		if s.get("key") != "support": return false
		if s.get("ally_target", false): return not allies.is_empty()
		return true
	)

	# Build a weighted pool: specials 30%, supports 20%, attacks fill the rest
	var pool := []
	for s in attacks:  pool.append({"skill": s, "weight": 3})
	for s in specials: pool.append({"skill": s, "weight": 1})
	for s in supports: pool.append({"skill": s, "weight": 2})

	if pool.is_empty():
		await take_turn(target)
		return

	# Weighted random pick
	var total := 0
	for entry in pool: total += entry["weight"]
	var roll := randi() % total
	var chosen_skill : Dictionary = pool[0]["skill"]
	var acc := 0
	for entry in pool:
		acc += entry["weight"]
		if roll < acc:
			chosen_skill = entry["skill"]
			break

	var key        : String = chosen_skill.get("key", "attack")
	var is_aoe     : bool   = chosen_skill.get("aoe", false)
	var is_ally_t  : bool   = chosen_skill.get("ally_target", false)
	var is_enemy_t : bool   = chosen_skill.get("enemy_target", false)
	var is_struggle: bool   = chosen_skill.get("struggle", false)

	# "attack" key on non-data-driven enemies falls back to the base attack.
	# EnemyActor overrides use_skill and handles attack keys via execute_effects.
	if key == "attack" or is_struggle:
		if not (self is EnemyActor):
			await take_turn(target)
			return

	# Determine targets for the chosen skill
	var skill_targets : Array = []
	if is_ally_t:
		# Support skill targeting an ally — pick the ally with the lowest HP ratio
		if allies.is_empty():
			await take_turn(target)
			return
		var neediest : BattleActor = allies[0]
		for a in allies:
			if float(a.hp) / float(a.max_hp) < float(neediest.hp) / float(neediest.max_hp):
				neediest = a
		skill_targets = [neediest]
	elif is_aoe:
		skill_targets = opponents
	elif is_enemy_t:
		if not opponents.is_empty():
			skill_targets = [opponents[randi() % opponents.size()]]
		else:
			await take_turn(target)
			return
	else:
		if not opponents.is_empty():
			skill_targets = [opponents[randi() % opponents.size()]]
		else:
			await take_turn(target)
			return

	await use_skill(key, skill_targets)

# Returns all living actors on the opposing team.
func get_opponents() -> Array:
	var manager = get_tree().get_first_node_in_group("battle_manager")
	if manager == null: return []
	return manager.actors.filter(func(a): return a.team != team and a.is_alive())

# Returns all living actors on the same team (excluding self).
func get_allies() -> Array:
	var manager = get_tree().get_first_node_in_group("battle_manager")
	if manager == null: return []
	return manager.actors.filter(func(a): return a.team == team and a.is_alive() and a != self)

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
		log_msg("%s lacked the will to strike true." % name)
		spend_turn()
		return
	# Randomly hit a visible body part if one exists, otherwise hit the actor directly
	var manager = get_tree().get_first_node_in_group("battle_manager")
	var visible_parts = target.get_visible_parts(manager.removed_channels if manager else 0)
	var hit_part: bool = not visible_parts.is_empty()
	if hit_part:
		var part = visible_parts[randi() % visible_parts.size()]
		log_msg("%s found the will to strike %s's %s." % [name, target.name, part.part_name])
		await play_attack_animation(target, 1.0, 1.0, int((base_damage * 0.5) * part.damage_multiplier))
		if part.is_cognitohazard:
			perishing = true
	else:
		await play_attack_animation(target, 1.0, 1.0, base_damage)
	if randf() < STRUGGLE_SELF_CHANCE:
		var self_dmg = max(1, base_damage / 2)
		log_msg("%s struggles in vain." % name)
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


	if is_instance_valid(target) and is_inside_tree():
		if target.is_alive():
			
			var final_damage = damage

			if has_status(STATUS_MARTYR) and martyr_bonus_damage > 0:

				

				final_damage += martyr_bonus_damage

				martyr_bonus_damage = 0

			# Lifesteal buff (Vice)
			if has_status(STATUS_LIFESTEAL):
				target.take_damage(damage * (1 - LIFESTEAL_RATIO), self)
				var heal = max(1, int(damage * LIFESTEAL_RATIO))
				hp = min(hp + heal, max_hp)
				log_msg("%s drinks %d CORP from the wound." % [name, heal])
				if has_status(STATUS_MARTYR):
					martyr_bonus_damage = max(0, martyr_bonus_damage - heal)
					log_msg("The cup passes from Indra. (-%d damage)" % [heal])
				emit_signal("hp_changed")

				
			else:
				if has_status(STATUS_MARTYR) and martyr_bonus_damage > 0:
					log_msg("%s pours out the cup of wrath. (+%d damage)" % [name, martyr_bonus_damage])
				target.take_damage(final_damage, self)


	

	
	var back_tween = create_tween()
	back_tween.set_trans(Tween.TRANS_QUAD)
	back_tween.set_ease(Tween.EASE_IN_OUT)

	back_tween.tween_property(self, "global_position", original_pos, 0.3)
	await back_tween.finished

	# Guard: target or self may have been freed if battle ended mid-animation
	if not is_instance_valid(target) or not is_inside_tree():
		return
	if perishing and is_inside_tree():
		print("You saw something you shouldn't have.")
		emit_signal("turn_finished")
		if damage >= hp:
			log_msg("%s understood the price all too well." % [name])
		else:
			log_msg("%s underestimated the price of understanding." % [name])
		take_damage(damage)
		perishing = false

	if is_inside_tree():
		await get_tree().create_timer(1.0).timeout
