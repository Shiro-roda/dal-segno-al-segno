extends BattleActor
class_name EnemyActor
## Base actor for data-driven enemies.
##
## Assign SkillData resources (with SkillEffect chains) to the `skills` export.
## The AI loop inherited from BattleActor.enemy_take_turn() will pick skills
## automatically.  Skills with empty `effects` arrays are silently skipped in
## execute_effects() — override use_skill() in a subclass for bespoke behaviour.
##
## Custom enemy scripts should extend EnemyActor (not BattleActor directly)
## so they inherit execute_effects() and the helper methods here.

## Assign SkillData resources in the Inspector (or via CharacterData.skills).
@export var skills : Array[SkillData] = []

# Optional flavour lines per skill key.  Override in subclass.
var chatter_attack  : Array = []
var chatter_special : Array = []
var chatter_support : Array = []
var chatter_hurt    : Array = []
var chatter_kill    : Array = []
var chatter_die     : Array = []


func _ready() -> void:
	super._ready()


# ── Skill API ─────────────────────────────────────────────────────────────────

func get_skills() -> Array:
	# Return Dictionary form so BattleActor.enemy_take_turn() can read keys.
	var out : Array = []
	for sd in skills:
		if sd != null:
			out.append(sd.to_dict())
	return out


func use_skill(skill_name: String, targets: Array, _part: BodyPartData = null) -> void:
	# Try to find the skill by exact name first, then fall back to command_key match.
	var sd : SkillData = _find_skill_by_name(skill_name)
	if sd == null:
		sd = _find_skill_by_key(skill_name)  # skill_name may actually be a key when called directly
	if sd == null or sd.effects.is_empty():
		if not targets.is_empty():
			await take_turn(targets[0])
		else:
			spend_turn()
		return
	# Spend will cost if the skill has one and this enemy has a party_member.
	if sd.will_cost > 0 and party_member != null:
		if not party_member.spend_will(sd.will_cost):
			# Can't afford it — fall back to plain attack.
			if not targets.is_empty():
				await take_turn(targets[0])
			else:
				spend_turn()
			return

	# Chatter
	match sd.command_key:
		"attack":  say_random(chatter_attack)
		"special": say_random(chatter_special)
		"support": say_random(chatter_support)

	await execute_effects(sd, targets)
	emit_signal("turn_finished")


## Execute the SkillEffect chain of a SkillData against a list of targets.
## Can be called from custom subclasses for reuse.
func execute_effects(sd: SkillData, targets: Array) -> void:
	for effect in sd.effects:
		if not is_inside_tree():
			return

		# Pre-delay
		if effect.pre_delay > 0.0:
			await get_tree().create_timer(effect.pre_delay).timeout

		# Universal chance roll — status_chance gates all effect types.
		if effect.status_chance < 1.0 and randf() > effect.status_chance:
			continue

		match effect.effect_type:

			SkillEffect.EffectType.DAMAGE:
				var dmg : int = int(attack_power * effect.damage_mult) + effect.damage_bonus
				for t in targets:
					if is_instance_valid(t) and t.is_alive():
						await play_attack_animation(t, 1.0, 1.0, dmg)

			SkillEffect.EffectType.AOE_DAMAGE:
				var dmg : int = int(attack_power * effect.damage_mult) + effect.damage_bonus
				for t in get_opponents():
					if is_instance_valid(t) and t.is_alive():
						t.take_damage(dmg, self)

			SkillEffect.EffectType.STATUS:
				for t in targets:
					if is_instance_valid(t) and t.is_alive():
						t.apply_status(effect.status_id, effect.status_duration)
						log_msg("%s afflicts %s with %s." % [get_log_name(), t.get_log_name(), effect.status_id])

			SkillEffect.EffectType.SELF_STATUS:
				apply_status(effect.status_id, effect.status_duration)
				log_msg("%s enters %s stance." % [get_log_name(), effect.status_id])

			SkillEffect.EffectType.HEAL:
				for t in targets:
					if is_instance_valid(t) and t.is_alive():
						var amt : int = effect.heal_amount if effect.heal_flat \
							else int(t.max_hp * effect.heal_amount / 100.0)
						t.hp = min(t.hp + amt, t.max_hp)
						t.emit_signal("hp_changed")
						log_msg("%s restores %d CORP to %s." % [get_log_name(), amt, t.get_log_name()])

			SkillEffect.EffectType.SELF_HEAL:
				var amt : int = effect.heal_amount if effect.heal_flat \
					else int(max_hp * effect.heal_amount / 100.0)
				hp = min(hp + amt, max_hp)
				emit_signal("hp_changed")
				log_msg("%s recovers %d CORP." % [get_log_name(), amt])

			SkillEffect.EffectType.DRAIN:
				var dmg : int = int(attack_power * effect.damage_mult) + effect.damage_bonus
				for t in targets:
					if is_instance_valid(t) and t.is_alive():
						var hp_before : int = t.hp
						var t_name : String = t.get_log_name()
						await play_attack_animation(t, 1.0, 1.0, dmg)
						# Drain based on damage actually dealt (hp delta), not raw dmg.
						
						if is_alive() and t != null:
							var dealt : int = hp_before - t.hp
							if dealt > 0:
								var heal : int = max(1, int(dealt * effect.drain_ratio))
								hp = min(hp + heal, max_hp)
								emit_signal("hp_changed")
								log_msg("%s drains %d CORP from %s." % [get_log_name(), heal, t_name])
						else:
							var heal : int = max(1, int(hp_before * effect.drain_ratio))
							hp = min(hp + heal, max_hp)
							emit_signal("hp_changed")
							log_msg("%s drains %d CORP from %s." % [get_log_name(), heal, t_name])

			SkillEffect.EffectType.SELF_DAMAGE:
				take_damage(effect.self_damage_amount)

			SkillEffect.EffectType.FLAT_DEBUFF:
				for t in targets:
					if is_instance_valid(t) and t.is_alive():
						t.apply_stat_change("flat", -effect.stat_delta, effect.stat_duration)

			SkillEffect.EffectType.SHARP_DEBUFF:
				for t in targets:
					if is_instance_valid(t) and t.is_alive():
						t.apply_stat_change("sharp", -effect.stat_delta, effect.stat_duration)

			SkillEffect.EffectType.FLAT_BUFF:
				for t in targets:
					if is_instance_valid(t) and t.is_alive():
						t.apply_stat_change("flat", effect.stat_delta, effect.stat_duration)

			SkillEffect.EffectType.SHARP_BUFF:
				for t in targets:
					if is_instance_valid(t) and t.is_alive():
						t.apply_stat_change("sharp", effect.stat_delta, effect.stat_duration)

		# Post-delay
		if effect.post_delay > 0.0:
			await get_tree().create_timer(effect.post_delay).timeout


# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_skill_by_key(command_key: String) -> SkillData:
	for sd in skills:
		if sd != null and sd.command_key == command_key:
			return sd
	return null

func _find_skill_by_name(sname: String) -> SkillData:
	for sd in skills:
		if sd != null and sd.skill_name == sname:
			return sd
	return null


func take_damage(amount: int, attacker: BattleActor = null) -> void:
	super.take_damage(amount, attacker)
	if is_alive():
		say_random(chatter_hurt)

func say_kill() -> void:
	say_random(chatter_kill)

func say_die() -> void:
	say_random(chatter_die)
