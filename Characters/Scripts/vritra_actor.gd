extends BattleActor
# Vritra — the serpent demigod of the ferris wheel carnival.
#
# ATTACK  — Vice:           spends will, leeches target (60% chance).
#                            
# ATTACK  — Strangulate:    struggle (no will). Randomly targets an ally or enemy.
#                            Vritra locks onto first target hit and attacks them every
#                            consecutive turn for a random number of turns (2-4),
#                            locked out of all other moves. Damage escalates each turn.
#                            If constricting an ally, Vritra regains will proportional to damage.
# SPECIAL — Devour:         spends 3 will, high damage. If it kills the target,
#                            permanently increases Vritra's max HP for this run.
# SUPPORT — Wither:         spends 2 will, reduces target's attack and siphons HP to Vritra.
#                            Falls back to Coil when willless.

const LEECH_DURATION            = 4
const LEECH_WILL_RESTORE_RATIO  = 0.5
const WITHER_CHANCE_NORMAL       = 0.6
const DEVOUR_WILL_COST          = 3
const DEVOUR_DMG_MULT           = 1.8
const DEVOUR_MAX_HP_BONUS       = 1    # gained per kill
const VICE_WILL_COST          = 1
const WITHER_WILL_COST        = 2  
const WITHER_ATK_REDUCTION      = 2
const WITHER_SIPHON_HP          = 0.3
const COIL_DMG_MULT   = 0.8
const COIL_HEAL_FLAT  = 3
const MALICE_DURATION = 2
const MALICE_WILL_COST = 2


const UNWILLING_WILL_RESTORE     = 4
const UNWILLING_MAX_WILL_BONUS   = 1

const CHATTER_VICE = [
	"Just one bite . . .",
	" ",
	" ",

]
const CHATTER_MALICE = [
	"You owe me at least this much.",
	"Don't just stand there!",
	"They don't regret it at all . . .",
	"They don't know, they don't know what they're doing . . .",
	"Make yourself useful for once.",
	" ",
	" ",
]
const CHATTER_CONSTRICT = [
	" ",
	" ",
	" ",
	" ",
]
const CHATTER_DEVOUR_KILL = [
	"I'M SORRY",
	"I DIDN'T MEAN TO",
	"[audio expunged from footage]",
	"YOU MADE ME DO THIS",
	" ",
	" ",
	" ",
	" ",
]
const CHATTER_DEVOUR = [
	"YOU LOOK SO GOOD",
	"COME HERE",
	"YOU'RE FUCKING MINE",
	"YOU'RE NOT GETTING AWAY",
	" ",
	" ",
]

const CHATTER_UNWILLING = [
	" ",
]
const CHATTER_WITHER = [
	"Pipe down!",
	"Get out of my sight.",
	" ",
	" ",
]
const CHATTER_COIL = [
	" ",
	" ",
]
const CHATTER_DRAIN = [
	" ",
]
const CHATTER_HURT = [
	"Tch... that fucking stung.",
	"Fuck! I just grew that back!",
	"Alright, you're gonna be a cube by the time I'm done.",
	" ",
	" ",
]

const CHATTER_KILL = [
	"Ugh, it's all stringy and shit.",
	". . . already?",
	" ",
	" ",
]

const CHATTER_DIE = [
	"Sh-Shit... can't... breathe...",
	"God, finally . . .",
	" ",
]

const CHATTER_TURN_START = [
	"Ugh, why aren't these guys dead yet?", 
	"Still listening, KK?",
	"That junk still working for you?",
	"Just hurry up, it's fucking itching! I'm about to start peeling this shit off.",
	" ",
	" ",
	" ",
	" ",
]



# Constrict state
var constrict_target : BattleActor = null
var constrict_turns_remaining : int = 0
var constrict_base_damage : int = 0
var constrict_turn_count : int = 0   # how many constrict turns have elapsed


func get_skills() -> Array:
	var has_will     = party_member != null and party_member.will > 0
	var can_devour   = party_member != null and party_member.will >= DEVOUR_WILL_COST
	var can_wither   = party_member != null and party_member.will >= WITHER_WILL_COST
	var can_vice = party_member != null and party_member.will >= VICE_WILL_COST
	var vice_unlocked = party_member != null and party_member.is_skill_unlocked("Vice")
	var devour_unlocked = party_member != null and party_member.is_skill_unlocked("Devour")
	
	var skills = [
		SkillDirectory.get_dict("Wither" if has_will else "Coil"),
	]
	if vice_unlocked:
		skills.append(SkillDirectory.get_dict("Vice" if can_vice else "Malice"))
	var has_devour_bonus = party_member != null and party_member.bonus_max_hp > 0
	if devour_unlocked:
		if can_devour:
			skills.insert(1, SkillDirectory.get_dict("Devour"))
		elif has_devour_bonus:
			skills.insert(1, SkillDirectory.get_dict("Anthropophagy"))
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

	# Constrict lock: if currently strangling, continue
	"if constrict_target != null:
		if constrict_target.is_alive() and constrict_turns_remaining > 0:
			await _constrict_tick()
			return
		else:
			_end_constrict()"

	if party_member != null and party_member.will >= WITHER_WILL_COST:
		await _wither(target, part)
	else:
		await _coil(target)



func use_skill(command_key: String, targets: Array, part: BodyPartData = null) -> void:
	tick_status_effects()
	if not is_alive():
		emit_signal("turn_finished")
		return
	match command_key:
		"special":
			var t = targets[0] if not targets.is_empty() else null
			if t == null:
				spend_turn()
				return
			if party_member != null and party_member.will >= DEVOUR_WILL_COST:
				await _devour(t, part)
			else:
				await _unwilling_devour(t)
		"support":
			var t = targets[0] if not targets.is_empty() else null
			if t == null:
				spend_turn()
				return
			if party_member != null and party_member.will >= VICE_WILL_COST:
				await _vice(t, part)
			else:
				await _malice(t)
		_:
			spend_turn()


# --- Skills ---

func _vice(target: BattleActor, part: BodyPartData = null) -> void:
	if not party_member.spend_will(VICE_WILL_COST):
		spend_turn()
		return

	say_random(CHATTER_VICE)

	target.apply_status(STATUS_LIFESTEAL, LEECH_DURATION)

	log_msg("%s instills a terrible hunger within %s." % [name, target.name])

	emit_signal("turn_finished")



func _malice(target: BattleActor) -> void:


	say_random(CHATTER_MALICE)

	target.apply_status(STATUS_MALICE, MALICE_DURATION)
	target.malice_source = self

	log_msg("%s fills %s with venomous spite." % [name, target.name])

	emit_signal("turn_finished")


func _constrict_tick() -> void:
	if constrict_target == null or not constrict_target.is_alive():
		_end_constrict()
		spend_turn()
		return

	constrict_turn_count += 1
	# Damage escalates each turn: base * turn_count
	var dmg = constrict_base_damage * constrict_turn_count
	var self_dmg = max(1, dmg / 3)

	if constrict_turn_count % 2 == 0:
		say_random(CHATTER_CONSTRICT)
	constrict_target.take_damage(dmg, self)
	take_damage(self_dmg)
	emit_signal("hp_changed")

	if constrict_target.team == Team.PLAYER and party_member != null:
		var will_gain = max(1, int(dmg * LEECH_WILL_RESTORE_RATIO))
		party_member.restore_will(will_gain)
		log_msg("%s asphyxiates %s — restores %d AP." % [name, constrict_target.name, will_gain])

	constrict_turns_remaining -= 1
	if constrict_turns_remaining <= 0 or not constrict_target.is_alive():
		_end_constrict()

	await get_tree().create_timer(0.4).timeout
	emit_signal("turn_finished")


func _end_constrict() -> void:
	log_msg("%s loosens up." % name)
	constrict_target = null
	constrict_turns_remaining = 0
	constrict_turn_count = 0


func _devour(target: BattleActor, part: BodyPartData = null) -> void:
	party_member.spend_will(DEVOUR_WILL_COST)
	var victim = target.get_log_name()
	var damage := int(attack_power * DEVOUR_DMG_MULT)
	log_msg("The beast grows voracious.")
	await play_attack_animation(target, 3.0, 3.0, damage)
	if part != null and part.has_part_hp() and is_instance_valid(target):
		var broke := part.take_part_damage(attack_power)
		if broke:
			target._on_part_broken(part)
	if not is_instance_valid(target) or not target.is_alive():
		say_random(CHATTER_DEVOUR_KILL)
		max_hp += DEVOUR_MAX_HP_BONUS
		if party_member:
			party_member.bonus_max_hp += DEVOUR_MAX_HP_BONUS
		log_msg("%s was devoured — the beast yet grows voracious." % [victim])
	else:
		var heal      : int = max(1, int(damage * (1.0 - LIFESTEAL_RATIO)))
		say_random(CHATTER_DEVOUR)
		hp = min(hp + heal, max_hp)
		emit_signal("hp_changed")
		log_msg("%s drinks %d CORP from the wound." % [get_log_name(), heal])
	emit_signal("turn_finished")


func _unwilling_devour(ally: BattleActor) -> void:
	if ally == self or not ally.is_alive():
		spend_turn()
		return
	var victim_name = ally.name
	var damage := int(attack_power * DEVOUR_DMG_MULT)
	say_random(CHATTER_UNWILLING)
	log_msg("%s turns on %s." % [name, victim_name])
	await play_attack_animation(ally, 3.0, 3.0, damage)
	# Always restore 1-3 AP regardless of phase
	if party_member:
		var ap_gain := randi_range(1, 3)
		party_member.restore_will(ap_gain)
		log_msg("%s wrings out %d AP from the act." % [name, ap_gain])
	if not ally.is_alive():
		# Convert 1 bonus max corp (from Devour) into 1 max AP
		if party_member and party_member.bonus_max_hp > 0:
			party_member.bonus_max_hp -= 1
			max_hp = max(1, max_hp - 1)
			party_member.max_will += UNWILLING_MAX_WILL_BONUS
			party_member.will = min(party_member.will, party_member.max_will)
			log_msg("%s was consumed." % [victim_name])
		else:
			log_msg("%s was consumed." % [victim_name])
	emit_signal("turn_finished")


func _coil(target: BattleActor) -> void:
	if target == null or not target.is_alive():
		spend_turn()
		return
	var damage := int(attack_power * COIL_DMG_MULT)
	await play_attack_animation(target, 1.0, 1.0, damage)
	if is_instance_valid(target) and not target.is_alive():
		say_kill()
	var heal := COIL_HEAL_FLAT
	hp = min(hp + heal, max_hp)
	emit_signal("hp_changed")
	log_msg("%s wrings out what it can. (+%d CORP)" % [name, heal])
	say_random(CHATTER_COIL)
	spend_turn()


func _wither(target: BattleActor, part: BodyPartData = null) -> void:
	party_member.spend_will(WITHER_WILL_COST)
	
	log_msg("%s sharpens their tongue on %s." % [name, target.name])
	var dmg_dealt : int = attack_power
	if randf() < WITHER_CHANCE_NORMAL:
		if has_status(STATUS_LIFESTEAL):
			var leech_dmg : int = int(dmg_dealt * (1.0 - LIFESTEAL_RATIO))
			var heal      : int = max(1, int(dmg_dealt))
			target.take_damage(leech_dmg, self)
			say_random(CHATTER_DRAIN)
			hp = min(hp + heal, max_hp)
			emit_signal("hp_changed")
			log_msg("%s drinks %d CORP from the wound." % [get_log_name(), heal])
		else:
			target.take_damage(dmg_dealt, self)
			say_random(CHATTER_WITHER)
		target.modify_attack(-WITHER_ATK_REDUCTION)
		log_msg("%s cowers under %s's fangs." % [target.name, name])
	else:
		if has_status(STATUS_LIFESTEAL):
			var leech_dmg : int = int(dmg_dealt * (1.0 - LIFESTEAL_RATIO))
			var heal      : int = max(1, int(dmg_dealt))
			target.take_damage(leech_dmg, self)
			say_random(CHATTER_DRAIN)
			hp = min(hp + heal, max_hp)
			emit_signal("hp_changed")
			log_msg("%s drinks %d CORP from the wound." % [get_log_name(), heal])
		else:
			target.take_damage(dmg_dealt, self)
			say_random(CHATTER_WITHER)
	if part != null and part.has_part_hp():
		var broke := part.take_part_damage(attack_power)
		if broke:
			target._on_part_broken(part)
	spend_turn()








func take_damage(amount: int, attacker: BattleActor = null) -> void:
	super.take_damage(amount, attacker)
	if is_alive():
		say_random(CHATTER_HURT)

func say_kill() -> void:
	say_random(CHATTER_KILL)

func say_die() -> void:
	say_random(CHATTER_DIE)

func say_turn_start() -> void:
	say_random(CHATTER_TURN_START)
