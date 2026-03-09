extends BattleActor
# Vritra — the serpent demigod of the ferris wheel carnival.
#
# ATTACK  — Vice:           spends will, leeches target (60% chance normal, guaranteed on body part).
#                            Leech heals grant Vritra will back at 50% ratio.
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
# SUPPORT — Drain Ally:     no will for Wither. Takes HP from an ally to restore will to Vritra.

const LEECH_DURATION            = 2
const LEECH_WILL_RESTORE_RATIO  = 0.5
const LEECH_CHANCE_NORMAL       = 0.6
const DEVOUR_WILL_COST          = 3
const DEVOUR_DMG_MULT           = 1.8
const DEVOUR_MAX_HP_BONUS       = 1    # gained per kill
const WITHER_WILL_COST          = 2
const WITHER_ATK_REDUCTION      = 2
const WITHER_SIPHON_HP          = 3
const WASTE_HP_RESTORE          = 3
const WASTE_WILL_RESTORE        = 2
const WASTE_MAX_HP_REDUCTION    = 2    # reduces devour bonus pool
const DRAIN_ALLY_HP_COST        = 5
const DRAIN_ALLY_WILL_RESTORE   = 4

const CHATTER_VICE = [
	"Hey tasty~",
	" ",
	" ",
	" ",
	" ",
]
const CHATTER_STRANGULATE = [
	"C'mere... just want a hug, is all...",
	" ",
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
const CHATTER_WITHER = [
	" ",
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
	var wither_unlocked = party_member != null and party_member.is_skill_unlocked("Wither")
	var devour_unlocked = party_member != null and party_member.is_skill_unlocked("Devour")
	var skills = [
		{"name": "Vice" if has_will else "Strangulate", "key": "attack", "struggle": not has_will},
	]
	# Support: Wither (unlocked + affordable) > Waste (unlocked) > nothing shown
	if wither_unlocked:
		skills.append({"name": "Wither" if can_wither else "Waste", "key": "support", "enemy_target": can_wither, "aoe": not can_wither})
	# Special: Devour only when unlocked and affordable
	if devour_unlocked and can_devour:
		skills.insert(1, {"name": "Devour", "key": "special"})
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
	if constrict_target != null:
		if constrict_target.is_alive() and constrict_turns_remaining > 0:
			await _constrict_tick()
			return
		else:
			_end_constrict()

	if party_member != null and party_member.will > 0:
		await _vice(target, part)
	else:
		await _strangulate_start()


func use_skill(command_key: String, targets: Array, part: BodyPartData = null) -> void:
	match command_key:
		"special":
			var t = targets[0] if not targets.is_empty() else null
			if t == null:
				spend_turn()
				return
			await _devour(t)
		"support":
			if party_member != null and party_member.will >= WITHER_WILL_COST:
				var t = targets[0] if not targets.is_empty() else null
				if t == null:
					spend_turn()
					return
				await _wither(t)
			else:
				await _waste()
		_:
			spend_turn()


# --- Skills ---

func _vice(target: BattleActor, part: BodyPartData) -> void:
	if not party_member.spend_will(1):
		await _strangulate_start()
		return
	var damage := int(attack_power * (part.damage_multiplier if part != null else 1.0))
	if part != null and part.is_cognitohazard:
		perishing = true
	say_random(CHATTER_VICE)
	log_msg("%s sinks their teeth into %s." % [name, target.name])
	await play_attack_animation(target, attack_power, 2.0, damage)
	# Apply leech AFTER the hit so it takes effect on future attacks, not this one
	if randf() < LEECH_CHANCE_NORMAL:
		if target:
			target.apply_status(STATUS_LEECHED, LEECH_DURATION)
			log_msg("%s is leeched." % target.name)
	emit_signal("turn_finished")


func _strangulate_start() -> void:
	var manager = get_tree().get_first_node_in_group("battle_manager")
	var all_alive = manager.actors.filter(func(a): return a.is_alive() and a != self)
	if all_alive.is_empty():
		spend_turn()
		return
	var target = all_alive[randi() % all_alive.size()]
	constrict_target = target
	constrict_turns_remaining = randi_range(2, 4)
	constrict_base_damage = max(1, attack_power / 2)
	constrict_turn_count = 0
	say_random(CHATTER_STRANGULATE)
	log_msg("%s begins to constrict %s!" % [name, target.name])
	await _constrict_tick()


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
		log_msg("%s asphyxiates %s — restores %d will." % [name, constrict_target.name, will_gain])

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


func _devour(target: BattleActor) -> void:
	party_member.spend_will(DEVOUR_WILL_COST)
	var victim = target.name
	var damage := int(attack_power * DEVOUR_DMG_MULT)
	say_random(CHATTER_DEVOUR)
	log_msg("The beast grows voracious." % [name, target.name])
	await play_attack_animation(target, 3.0, 3.0, damage)
	if not target:
		max_hp += DEVOUR_MAX_HP_BONUS
		if party_member:
			party_member.bonus_max_hp += DEVOUR_MAX_HP_BONUS
		log_msg("%s was devoured — the beast yet grows voracious." % [victim])
	emit_signal("turn_finished")


func _waste() -> void:
	# Reduce any stored Devour bonus in exchange for will and HP
	var current_bonus = party_member.bonus_max_hp if party_member else 0
	if current_bonus >= WASTE_MAX_HP_REDUCTION:
		party_member.bonus_max_hp -= WASTE_MAX_HP_REDUCTION
		max_hp = max(1, max_hp - WASTE_MAX_HP_REDUCTION)
		log_msg("The serpent sheds another skin — Vritra is looking thin.")
	else:
		log_msg("Vritra is emaciated.")
	if party_member:
		party_member.restore_will(WASTE_WILL_RESTORE)
	hp = min(hp + WASTE_HP_RESTORE, max_hp)
	emit_signal("hp_changed")
	say_random(CHATTER_WASTE)
	spend_turn()


func _wither(target: BattleActor) -> void:
	party_member.spend_will(WITHER_WILL_COST)
	target.attack_power = max(0, target.attack_power - WITHER_ATK_REDUCTION)
	var siphon = WITHER_SIPHON_HP
	target.take_damage(siphon, self)
	hp = min(hp + siphon, max_hp)
	emit_signal("hp_changed")
	say_random(CHATTER_WITHER)
	log_msg("%s withers %s — arms grow heavy, and %d vitality is siphoned." % [name, target.name, siphon])
	spend_turn()


func _drain_ally(ally: BattleActor) -> void:
	if ally == self or not ally.is_alive():
		spend_turn()
		return
	if ally.hp <= DRAIN_ALLY_HP_COST:
		log_msg("Not enough left in %s to take." % ally.name)
		spend_turn()
		return
	ally.take_damage(DRAIN_ALLY_HP_COST, self)
	if party_member:
		party_member.restore_will(DRAIN_ALLY_WILL_RESTORE)
	say_random(CHATTER_DRAIN)
	log_msg("%s drains %d from %s, restoring %d will." % [name, DRAIN_ALLY_HP_COST, ally.name, DRAIN_ALLY_WILL_RESTORE])
	emit_signal("turn_finished")





func take_damage(amount: int, attacker: BattleActor = null) -> void:
	super.take_damage(amount, attacker)
	if is_alive():
		say_random(CHATTER_HURT)
