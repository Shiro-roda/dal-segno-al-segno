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

const REBUKE_WILL_COST       = 2
const REBUKE_DMG_MULT        = 1
const REBUKE_SLOW_CHANCE     = 0.45
const CALCIFY_WILL_COST      = 3
const CALCIFY_MIN_TURNS      = 3
const CALCIFY_MAX_TURNS      = 6
const CALCIFY_DMG_REDUCTION  = 0.5
const SHELTER_WILL_COST      = 1
const SHELTER_HP_AMOUNT      = 10   
const SHELTER_FLAT_BONUS     = 4   
const SELF_HARM_HP_COST       = 3
const SELF_HARM_WILL_RESTORE  = 2
const EMBRACE_DURATION        = 2
const EMBRACE_WILL_RATIO      = 0.5  # will restored = damage * ratio (outside transit phases)

var _embrace_active : bool = false

const CHATTER_REBUKE = [
	"Stay back!!",
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
	"They can't hurt you now!",
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

const CHATTER_KILL = [
	"I . . . I'm sorry . . .",
	" ",
]

const CHATTER_DIE = [
	"W-Wait, what are you—?!",
	". . . Hedone . . . ? Wait, don't go . . . !",
	" ",
	" ",
	" ",
]

const CHATTER_TURN_START = [
	"I'm ready!",
	"Just stay right behind me! . . . please?",
	"I'll find a way!",
	"Is it over yet . . . ?",
	" ",
	" ",
	" ",
	" ",
]


func get_skills() -> Array:
	var has_will      = party_member != null and party_member.will > 0
	var can_calc      = party_member != null and party_member.will >= CALCIFY_WILL_COST
	var can_shelt     = party_member != null and party_member.will >= SHELTER_WILL_COST
	var shelt_unlocked = party_member != null and party_member.is_skill_unlocked("Shelter")
	var calc_unlocked  = party_member != null and party_member.is_skill_unlocked("Calcify")
	var skills = [
		SkillDirectory.get_dict("Rebuke" if has_will else "Cling"),
	]
	if shelt_unlocked:
		skills.append(SkillDirectory.get_dict("Shelter" if can_shelt else "Embrace"))
	if calc_unlocked and can_calc:
		skills.insert(1, SkillDirectory.get_dict("Calcify"))
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
			await _calcify(t, part)
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
	say_random(CHATTER_REBUKE)
	log_msg("%s wards off your foes." % [get_log_name()])
	# Snapshot before damage loop — enemies may die and be freed mid-loop
	var targets := get_opponents()
	for enemy in targets:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var dmg := int(attack_power * REBUKE_DMG_MULT)
		enemy.take_damage(dmg, self)
		if is_instance_valid(enemy) and enemy.is_alive() and randf() < REBUKE_SLOW_CHANCE:
			enemy.apply_status(STATUS_SLOW, 2)
			log_msg("%s is slowed." % enemy.get_log_name())
		# Tick part HP: only applies when targeting a specific part on a single enemy
		if part != null and enemy == target and part.has_part_hp():
			var broke := part.take_part_damage(attack_power)
			if broke:
				enemy._on_part_broken(part)
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.5).timeout
	if is_inside_tree():
		emit_signal("turn_finished")


func _cling() -> void:
	var enemies = get_opponents()
	if enemies.is_empty():
		spend_turn()
		return
	var target = enemies[randi() % enemies.size()]
	log_msg("Hue throws himself at %s." % [target.get_log_name()])
	if randf() < 0.75:
		target.apply_status(STATUS_SLOW, 1)
		log_msg("%s can't shake Hue off. (slowed)" % [target.get_log_name()])
	say_random(CHATTER_CLING)
	
	var dmg = max(1, randi() % attack_power)
	await play_attack_animation(target, 1.0, 1.0, dmg)
	if randf() < STRUGGLE_SELF_CHANCE:
		var self_dmg = max(1, dmg / 2)
		take_damage(self_dmg)
	emit_signal("turn_finished")


func _calcify(target: BattleActor, part: BodyPartData = null) -> void:
	party_member.spend_will(CALCIFY_WILL_COST)
	var turns = randi_range(CALCIFY_MIN_TURNS, CALCIFY_MAX_TURNS)
	var manager = get_tree().get_first_node_in_group("battle_manager")
	var tempo_penalty : float = turns * manager.TEMPO_COST_ATTACK
	target.tempo_pool -= tempo_penalty
	target.apply_status("encased", 0)
	if part != null:
		part.apply_status("encased", 0)
		log_msg("Hue entombs %s's %s in ice, guarding them from harm until it melts. (-%s TEMPO)" % [target.get_log_name(), part.part_name, tempo_penalty])
	else:
		log_msg("Hue entombs %s in ice, guarding them from harm until it melts. (-%s TEMPO)" % [target.get_log_name(), tempo_penalty])
	say_random(CHATTER_CALCIFY)
	await get_tree().create_timer(0.5).timeout
	emit_signal("turn_finished")


func _shelter(ally: BattleActor) -> void:
	party_member.spend_will(SHELTER_WILL_COST)
	ally.shield_hp += SHELTER_HP_AMOUNT
	ally.modify_flat(SHELTER_FLAT_BONUS)
	ally.emit_signal("hp_changed")
	ally.apply_status(STATUS_SHIELD, 999)
	say_random(CHATTER_SHELTER)
	log_msg("%s fortifies %s (+%d temp CORP, +%d FLAT while it holds)." \
		% [name, ally.name, SHELTER_HP_AMOUNT, SHELTER_FLAT_BONUS])
	# Reverse the Flat buff once the shield is consumed.
	# hp_changed fires whenever shield or hp changes; watch for shield drop.
	var _conn : Callable
	_conn = func():
		if ally.shield_hp <= 0:
			ally.modify_flat(-SHELTER_FLAT_BONUS)
			if ally.hp_changed.is_connected(_conn):
				ally.hp_changed.disconnect(_conn)
	ally.hp_changed.connect(_conn)
	spend_turn()


func _embrace(ally: BattleActor) -> void:
	ally.cover_source = self
	ally.apply_status(STATUS_COVERED, EMBRACE_DURATION)
	_embrace_active = true
	# Clear flag when the covered status expires on the ally
	var _watch : Callable
	_watch = func():
		if not ally.has_status(STATUS_COVERED):
			_embrace_active = false
			if ally.hp_changed.is_connected(_watch):
				ally.hp_changed.disconnect(_watch)
	ally.hp_changed.connect(_watch)
	say_random(CHATTER_EMBRACE)
	log_msg("%s holds %s tight for %d turns." % [name, ally.name, EMBRACE_DURATION])
	spend_turn()



func take_damage(amount: int, attacker: BattleActor = null) -> void:
	super.take_damage(amount, attacker)
	if is_alive():
		say_random(CHATTER_HURT)
		if _embrace_active and struggle_restores_will() and party_member != null:
			var will_gain: Variant = max(1, int(amount * EMBRACE_WILL_RATIO))
			party_member.restore_will(will_gain)
			log_msg("%s endures (+%d AP)" % [name, will_gain])

func say_kill() -> void:
	say_random(CHATTER_KILL)

func say_die() -> void:
	say_random(CHATTER_DIE)

func say_turn_start() -> void:
	say_random(CHATTER_TURN_START)
