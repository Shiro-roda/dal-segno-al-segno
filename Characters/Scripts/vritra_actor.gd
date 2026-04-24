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
# SPECIAL — Waste:          no will for Devour. Reduces Vritra's max HP bonus (from Devour)
#                            in exchange for restoring will and some HP.
# SUPPORT — Wither:         spends 2 will, reduces target's attack and siphons HP to Vritra.

const LEECH_DURATION            = 2
const LEECH_WILL_RESTORE_RATIO  = 0.5
const WITHER_CHANCE_NORMAL       = 0.6
const DEVOUR_WILL_COST          = 3
const DEVOUR_DMG_MULT           = 1.8
const DEVOUR_MAX_HP_BONUS       = 1    # gained per kill
const VICE_WILL_COST          = 2
const WITHER_WILL_COST        = 1  
const WITHER_ATK_REDUCTION      = 2
const WITHER_SIPHON_HP          = 0.3
const WASTE_HP_RESTORE          = 3
const WASTE_WILL_RESTORE        = 2
const WASTE_MAX_HP_REDUCTION    = 2    # reduces devour bonus pool
const MALICE_DURATION = 2
const MALICE_WILL_COST = 2


const UNWILLING_WILL_RESTORE     = 4
const UNWILLING_MAX_WILL_BONUS   = 1

const CHATTER_VICE = [
	"Hey tasty~",
	"C'mere... just want a hug, is all...",
	"Don't they look soooo good?",
	" ",
	" ",

]
const CHATTER_MALICE = [
	"You owe me at least this much.",
	"Don't just stand there!",
	" ",
	" ",
	" ",
]
const CHATTER_CONSTRICT = [
	"Sh-Shiiittt... can't... breathe... I guess I got too excited~",
	" ",
	" ",
	" ",
	" ",
]
const CHATTER_DEVOUR = [
	"I'M SORRY",
	"I DIDN'T MEAN TO",
	"[audio expunged from footage]",
	"YOU LOOK SO GOOD",
	" ",
	" ",
	" ",
	" ",
	" ",
]
const CHATTER_UNWILLING = [
	" ",
]
const CHATTER_WITHER = [
	"Pipe down!",
]
const CHATTER_WASTE = [
	"Fuuuuck, I'm hungry...",
	" ",
	" ",
	" ",
	" ",
	" ",
]
const CHATTER_DRAIN = [
	"*SLUUURRPP*",
	"Ugh, it's all stringy and shit.",
	"Just a bite ~<3",
	" ",
	" ",
	" ",
	" ",
]
const CHATTER_HURT = [
	"Aww, play nice!",
	"Tch... that fucking stung.",
	"*Cough* Shit, that felt good...",
	"I'm fucking you up for that!",
	"Fuck! I just grew that back!",
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
		SkillDirectory.get_dict("Wither" if has_will else "Waste"),
	]
	if vice_unlocked:
		skills.append(SkillDirectory.get_dict("Vice" if can_vice else "Malice"))
	var has_devour_bonus = party_member != null and party_member.bonus_max_hp > 0
	if devour_unlocked:
		if can_devour:
			skills.insert(1, SkillDirectory.get_dict("Devour"))
		elif has_devour_bonus:
			skills.insert(1, SkillDirectory.get_dict("Unwilling"))
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
		await _waste()



func use_skill(command_key: String, targets: Array, part: BodyPartData = null) -> void:
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

	if not party_member.spend_will(MALICE_WILL_COST):
		spend_turn()
		return

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
	say_random(CHATTER_DEVOUR)
	log_msg("The beast grows voracious.")
	await play_attack_animation(target, 3.0, 3.0, damage)
	if part != null and part.has_part_hp():
		var broke := part.take_part_damage(attack_power)
		if broke:
			target._on_part_broken(part)
	if not target.is_alive():
		max_hp += DEVOUR_MAX_HP_BONUS
		if party_member:
			party_member.bonus_max_hp += DEVOUR_MAX_HP_BONUS
		log_msg("%s was devoured — the beast yet grows voracious." % [victim])
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


func _waste() -> void:
	# Reduce any stored Devour bonus in exchange for will and HP.
	# If no bonus HP remains, spend real HP instead.
	var current_bonus = party_member.bonus_max_hp if party_member else 0
	if current_bonus >= WASTE_MAX_HP_REDUCTION:
		party_member.bonus_max_hp -= WASTE_MAX_HP_REDUCTION
		max_hp = max(1, max_hp - WASTE_MAX_HP_REDUCTION)
		log_msg("The serpent sheds another skin — Vritra is looking thin.")
	else:
		# No bonus to shed — pay with actual HP
		var hp_cost = WASTE_MAX_HP_REDUCTION
		if hp <= hp_cost:
			hp_cost = hp - 1  # leave 1 HP
		if hp_cost > 0:
			hp -= hp_cost
			emit_signal("hp_changed")
			log_msg("Vritra tears something out of itself — %d HP lost." % hp_cost)
		else:
			log_msg("Vritra is too starved to shed anything.")
	if party_member and struggle_restores_will():
		party_member.restore_will(WASTE_WILL_RESTORE)
		log_msg("%s wrings out what little it has. (+%d AP)" % [name, WASTE_WILL_RESTORE])
	hp = min(hp + WASTE_HP_RESTORE, max_hp)
	emit_signal("hp_changed")
	say_random(CHATTER_WASTE)
	spend_turn()


func _wither(target: BattleActor, part: BodyPartData = null) -> void:
	party_member.spend_will(WITHER_WILL_COST)
	say_random(CHATTER_WITHER)
	log_msg("%s sharpens their tongue on %s." % [name, target.name])
	if randf() < WITHER_CHANCE_NORMAL:
		#var siphon = int(attack_power * WITHER_SIPHON_HP)
		target.take_damage(attack_power, self)
		target.modify_attack(-WITHER_ATK_REDUCTION)
		#hp = min(hp + siphon, max_hp)
		#emit_signal("hp_changed")
		log_msg("%s cowers under %s's fangs." % [target.name, name])
	else:
		target.take_damage(attack_power, self)
	if part != null and part.has_part_hp():
		var broke := part.take_part_damage(attack_power)
		if broke:
			target._on_part_broken(part)
	spend_turn()








func take_damage(amount: int, attacker: BattleActor = null) -> void:
	super.take_damage(amount, attacker)
	if is_alive():
		say_random(CHATTER_HURT)
