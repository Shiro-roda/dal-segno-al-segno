extends BattleActor
# Hue — the boy in the yellow raincoat.
# Umbrella-wielding, defensive, cold.
#
# ATTACK  — Rebuke:          spends will. AoE frost hits all enemies for reduced damage,
#                             each with a 45% chance to be slowed. Body-part targeted:
#                             single enemy, full damage, guaranteed freeze.
# ATTACK  — Cling:           struggle (no will). Latches onto a single random enemy,
#                             slowing them. Chance to miss, chance to self-harm, no freeze.
# SPECIAL — Calcify:         spends 3 will. Encases one enemy in ice for 2-4 turns —
#                             their tempo pool is heavily drained each turn (can't act soon),
#                             and they take 50% reduced damage while encased.
# SPECIAL — Desperate Grasp: sacrifice HP for will (no will for Calcify).
# SUPPORT — Shelter:         spends 2 will. Gives an ally temporary HP (shield_hp buffer).
# SUPPORT — Embrace:         free (no will). Hue covers an ally — redirects incoming
#                             damage to himself with a 15% reduction for 2 turns.

const REBUKE_WILL_COST       = 1
const REBUKE_DMG_MULT        = 1
const REBUKE_SLOW_CHANCE     = 0.45
const CALCIFY_WILL_COST      = 3
const CALCIFY_MIN_TURNS      = 1
const CALCIFY_MAX_TURNS      = 3
const CALCIFY_DMG_REDUCTION  = 0.5
const SHELTER_WILL_COST      = 2
const SHELTER_HP_AMOUNT      = 8
const SELF_HARM_HP_COST      = 3
const SELF_HARM_WILL_RESTORE = 2
const EMBRACE_DURATION       = 2

const CHATTER_REBUKE = [
	"Stay back.",
	"Go away!",
	"Don't come any closer!",
	"I think that got 'em!",
	"Stop fighting and listen!",
	" ",
	" ",
	" ",
]
const CHATTER_CLING = [
	"I'm not gonna let go!",
	"W-Wait! Please, you don't have to be angry!",
	"Stop! Stop it!",
	" ",
	" ",
	" ",
]
const CHATTER_CALCIFY = [
	"Hold still!",
	"Bbbrrrr...",
	"They shouldn't bother us now.",
	" ",
	" ",
	" ",
	" ",
	" ",
]
const CHATTER_SHELTER = [
	"I won't let them hurt you.",
	"Are you alright?",
	" ",
	" ",
	" ",
	" ",
]
const CHATTER_EMBRACE = [
	"I won't. . .let them hurt you!",
	" ",
	" ",
	" ",
]
const CHATTER_HURT = [
	"Ow!!",
	"Leave us alone!",
	"Please, stop!",
	" ",
	" ",
	" ",
	" ",
	" ",
]


func get_skills() -> Array:
	var has_will  = party_member != null and party_member.will > 0
	var can_calc  = party_member != null and party_member.will >= CALCIFY_WILL_COST
	var can_shelt = party_member != null and party_member.will >= SHELTER_WILL_COST
	var skills = [
		{"name": "Rebuke" if has_will else "Cling", "key": "attack", "aoe": has_will, "struggle": not has_will},
		{"name": "Shelter" if can_shelt else "Embrace", "key": "support", "ally_target": true},
	]
	# Calcify needs a single enemy target
	if can_calc:
		skills.insert(1, {"name": "Calcify", "key": "special", "targeted": true})
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
	if party_member != null and party_member.will > 0:
		await _rebuke(target, part)
	else:
		await _cling()


func use_skill(command_key: String, targets: Array) -> void:
	match command_key:
		"special":
			var t = targets[0] if not targets.is_empty() else null
			if t == null:
				spend_turn()
				return
			await _calcify(t)
		"support":
			var ally = targets[0] if not targets.is_empty() else self
			if party_member != null and party_member.will >= SHELTER_WILL_COST:
				await _shelter(ally)
			else:
				await _embrace(ally)
		_:
			spend_turn()


# --- Skills ---

func _rebuke(target: BattleActor, part: BodyPartData) -> void:
	if not party_member.spend_will(REBUKE_WILL_COST):
		await _cling()
		return
	var manager = get_tree().get_first_node_in_group("battle_manager")
	var enemies = manager.actors.filter(func(a): return a.team == Team.ENEMY and a.is_alive())
	say_random(CHATTER_REBUKE)
	for enemy in enemies:
		var dmg = int(attack_power * REBUKE_DMG_MULT)
		enemy.take_damage(dmg, self)
		if randf() < REBUKE_SLOW_CHANCE:
			enemy.apply_status(STATUS_SLOW, 2)
			log_msg("%s is slowed." % enemy.name)
	await get_tree().create_timer(0.5).timeout
	emit_signal("turn_finished")


func _cling() -> void:
	var manager = get_tree().get_first_node_in_group("battle_manager")
	var enemies = manager.actors.filter(func(a): return a.team == Team.ENEMY and a.is_alive())
	if enemies.is_empty():
		spend_turn()
		return
	var target = enemies[randi() % enemies.size()]
	if randf() < STRUGGLE_MISS_CHANCE:
		log_msg("%s flails and misses." % name)
		spend_turn()
		return
	var dmg = max(1, attack_power / 2)
	target.apply_status(STATUS_SLOW, 1)
	say_random(CHATTER_CLING)
	await play_attack_animation(target, 1.0, 1.0, dmg)
	if randf() < STRUGGLE_SELF_CHANCE:
		var self_dmg = max(1, dmg / 2)
		take_damage(self_dmg)
	emit_signal("turn_finished")


func _calcify(target: BattleActor) -> void:
	party_member.spend_will(CALCIFY_WILL_COST)
	var turns = randi_range(CALCIFY_MIN_TURNS, CALCIFY_MAX_TURNS)
	target.apply_status(STATUS_FROZEN, turns)
	target.apply_status("encased", turns)
	say_random(CHATTER_CALCIFY)
	log_msg("%s is encased in ice for %d turns." % [target.name, turns])
	# Drain tempo heavily each turn of encasement via the manager
	var manager = get_tree().get_first_node_in_group("battle_manager")
	for i in range(turns):
		manager.delay_actor_turn(target)
	await get_tree().create_timer(0.5).timeout
	emit_signal("turn_finished")


func _shelter(ally: BattleActor) -> void:
	party_member.spend_will(SHELTER_WILL_COST)
	ally.shield_hp += SHELTER_HP_AMOUNT
	ally.apply_status(STATUS_SHIELD, 999)
	say_random(CHATTER_SHELTER)
	log_msg("%s shields %s (+%d temp HP)." % [name, ally.name, SHELTER_HP_AMOUNT])
	spend_turn()


func _embrace(ally: BattleActor) -> void:
	# Hue covers the ally — damage to them redirects to Hue with 15% reduction
	ally.cover_source = self
	ally.apply_status(STATUS_COVERED, EMBRACE_DURATION)
	say_random(CHATTER_EMBRACE)
	log_msg("%s covers %s for %d turns." % [name, ally.name, EMBRACE_DURATION])
	spend_turn()


func _desperate_grasp() -> void:
	if hp <= SELF_HARM_HP_COST:
		log_msg("%s is too weak to grasp." % name)
		spend_turn()
		return
	take_damage(SELF_HARM_HP_COST)
	party_member.restore_will(SELF_HARM_WILL_RESTORE)
	log_msg("%s trades %d HP for %d will." % [name, SELF_HARM_HP_COST, SELF_HARM_WILL_RESTORE])
	spend_turn()


# Encased enemies take reduced damage; Hue reacts when hit
func take_damage(amount: int, attacker: BattleActor = null) -> void:
	if has_status("encased"):
		amount = int(amount * CALCIFY_DMG_REDUCTION)
	super.take_damage(amount, attacker)
	if is_alive():
		say_random(CHATTER_HURT)
