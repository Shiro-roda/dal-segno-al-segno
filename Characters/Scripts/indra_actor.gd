extends BattleActor
# Indra — the android saviour, storm-god lineage.
# Mid will, mid-high damage. His nailed bat opens bleeding wounds.
# Bleed scales off target max HP — he understands bodies as structures to dismantle.
#
# ATTACK  — Crucify:    spends will, bleed application, medium damage
# ATTACK  — Clobber:    struggle (no will), random target, chance to miss/self-hit, no bleed
# SPECIAL — Fulminate:  spends 3 will, AoE lightning hits all enemies for reduced damage
# SUPPORT — Galvanize:  spends 2 will, raises attack+will of both supports slightly,
#                        grants Kendall a free shot.
# SUPPORT — Martyr:     bleed self and store all damage taken to add to next attack

const BLEED_DURATION          = 3
const BLEED_CHANCE_NORMAL     = 0.5
const FULMINATE_WILL_COST     = 3
const FULMINATE_DMG_MULT      = 0.7   # each enemy takes 70% of normal attack
const GALVANIZE_WILL_COST     = 2
const GALVANIZE_ATK_BONUS     = 2
const GALVANIZE_WILL_BONUS    = 1
const MARTYR_HP_COST          = 4
const MARTYR_WILL_RESTORE     = 3
const MARTYR_DURATION = 3
const MARTYR_TEMPO_BONUS = 3

const CHATTER_CRUCIFY = [
	"Hold out your arms.",
	"Bleed with me.",
	"Another nail for your coffin.",
	" ",
	" ",
	" ",
	" ",
]
const CHATTER_CLOBBER = [
	"Get out of my way!",
	"No time for this.",
	" ",
	" ",
]
const CHATTER_FULMINATE = [
	"Kneel.",
	"Only filth, to be washed away.",
	"",
	" ",
	" ",
]
const CHATTER_GALVANIZE = [
	"We need to keep going.",
	"They're only another stepping stone for us.",
	"The skies stand with you.",
	"We've weathered greater storms.",
	"Sharpen yourselves. Turn your head to the howling wind and pierce it."
]
const CHATTER_MARTYR = [
	"It's not my right to falter now.",
	"Not nearly enough...",
	"You . . . will bleed with me.",
	"This thirst . . . but there's no rain.",
	"Let us share this bitter cup.",
	" ",
	" ",
]
const CHATTER_HURT = [
	"It's nothing.",
	"I'll get another arm.",
	"...!",
	"This won't stop me.",
	"It's not nearly enough.",
	" ",
	" ",
]

const CHATTER_KILL = [
	"Forgiveness is beyond you now.",
	"I will be with you soon, in Paradise.",
	"I will not forget your sacrifice.",
	" ",
	" ",
]

const CHATTER_DIE = [
	"I leave the rest to you . . .",
	"Mother . . . ?",
	"Is this enough . . . ?",
	"Is it finished . . . ?",
	". . . they know not . . .",
	" ",
	" ",
]

const CHATTER_TURN_START = [
	"This brother will not falter.",
	"I await your command.",
	"By your will.",
	"Who stands against you?",
	" ",
	" ",
	" ",
]

func get_skills() -> Array:
	var has_will        = party_member != null and party_member.will > 0
	var can_fulminate   = party_member != null and party_member.will >= FULMINATE_WILL_COST
	var can_galvanize   = party_member != null and party_member.will >= GALVANIZE_WILL_COST
	var galv_unlocked   = party_member != null and party_member.is_skill_unlocked("Galvanize")
	var fulm_unlocked   = party_member != null and party_member.is_skill_unlocked("Fulminate")
	var skills = [
		SkillDirectory.get_dict("Crucify" if has_will else "Clobber"),
	]
	if galv_unlocked:
		skills.append(SkillDirectory.get_dict("Galvanize" if can_galvanize else "Martyr"))
	if fulm_unlocked and can_fulminate:
		skills.insert(1, SkillDirectory.get_dict("Fulminate"))
	return skills


func take_turn(target: BattleActor, part: BodyPartData = null) -> void:
	await get_tree().create_timer(0.1).timeout
	tick_status_effects()
	if not is_alive():
		emit_signal("turn_finished")
		return
	if has_status(STATUS_FROZEN):
		print(name, " is frozen and cannot act.")
		spend_turn()
		return
	if party_member.will > 0:
		await _crucify(target, part)
	else:
		var manager = get_tree().get_first_node_in_group("battle_manager")
		await struggle_attack(manager.actors, attack_power)


func use_skill(command_key: String, targets: Array, part: BodyPartData = null) -> void:
	match command_key:
		"special":
			var manager = get_tree().get_first_node_in_group("battle_manager")
			await _fulminate(manager.actors)
		"support":
			if party_member.will >= GALVANIZE_WILL_COST:
				var manager = get_tree().get_first_node_in_group("battle_manager")
				await _galvanize(manager.actors)
			else:
				await _martyr()
		_:
			spend_turn()


# --- Skills ---

func _crucify(target: BattleActor, part: BodyPartData) -> void:
	if not party_member.spend_will(1):
		var manager = get_tree().get_first_node_in_group("battle_manager")
		await struggle_attack(manager.actors, attack_power)
		return
	var damage := int(attack_power * (part.damage_multiplier if part != null else 1.0))
	if part != null and part.is_cognitohazard:
		perishing = true
	if randf() < BLEED_CHANCE_NORMAL:
		target.apply_status(STATUS_BLEEDING, BLEED_DURATION)
		log_msg("%s opens a wound on %s." % [get_log_name(), target.get_log_name()])
	say_random(CHATTER_CRUCIFY)
	log_msg("%s charges at %s." % [name, target.get_log_name()])
	await play_attack_animation(target, attack_power, 2.0, damage)
	if part != null and part.has_part_hp():
		var broke := part.take_part_damage(attack_power)
		if broke:
			target._on_part_broken(part)
	emit_signal("turn_finished")


func _fulminate(all_actors: Array) -> void:
	party_member.spend_will(FULMINATE_WILL_COST)
	say_random(CHATTER_FULMINATE)
	log_msg("The earth is laid waste before him, the world and all who dwell in it.")
	var targets := get_opponents()
	for enemy in targets:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var dmg := int(attack_power * FULMINATE_DMG_MULT) + (randi() % attack_power)
		enemy.take_damage(dmg, self)
	if is_inside_tree():
		emit_signal("turn_finished")


func _galvanize(all_actors: Array) -> void:
	party_member.spend_will(GALVANIZE_WILL_COST)
	var supports = get_allies()
	log_msg("%s rouses his companions." % [name])
	for s in supports:
		s.modify_attack(GALVANIZE_ATK_BONUS)
		s.party_member.restore_will(GALVANIZE_WILL_BONUS)
	# Grant Kendall a free shot: flag on the manager
	var manager = get_tree().get_first_node_in_group("battle_manager")
	manager.grant_free_shot()
	say_random(CHATTER_GALVANIZE)
	spend_turn()




func _martyr() -> void:
	if struggle_restores_will():
		party_member.restore_will(MARTYR_WILL_RESTORE)
		log_msg("%s prepares a cup of wrath. (+%d AP)" % [name, MARTYR_WILL_RESTORE])
	else:
		log_msg("%s prepares a cup of wrath." % name)
	apply_status(STATUS_BLEEDING, BLEED_DURATION)
	apply_status(STATUS_MARTYR, MARTYR_DURATION)
	martyr_tempo_bonus = MARTYR_TEMPO_BONUS
	martyr_bonus_damage = 0
	say_random(CHATTER_MARTYR)
	spend_turn()



func take_damage(amount: int, attacker: BattleActor = null) -> void:
	super.take_damage(amount, attacker)
	if is_alive():
		say_random(CHATTER_HURT)
