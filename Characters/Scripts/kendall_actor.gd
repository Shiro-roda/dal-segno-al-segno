extends BattleActor
# Kendall — the investigator with the pistol.
# High tempo, high single-target damage. Ammo for basic attacks only.
# Basic:   Shoot (costs 1 ammo) / Pistol Whip (no ammo, struggle)
# Special: Change Lens (costs ally will, not ammo — bends perception itself)
# Support: Augur (costs ally will, whole team dodge+tempo) / Evade (free, personal)

const AUGUR_WILL_COST    = 0
const AUGUR_DODGE_TURNS  = 4
const AUGUR_TEMPO_BONUS  = 5.0  # flat tempo bonus to allies
const EVADE_DODGE_TURNS  = 2
const EVADE_TEMPO_BONUS  = 10.0  # larger personal tempo bonus
const PISTOL_WHIP_MULT   = 0.5



func get_skills() -> Array:
	var has_ammo        = run_state != null and run_state.ammo > 0
	var supports_have_will = _supports_have_will()
	var lens_unlocked   = party_member != null and party_member.is_skill_unlocked("Unveil")

	# Use the equipped gun's shoot dict if a gun is equipped.
	var active_gun : GunData = run_state.get_active_gun() if run_state != null else null
	var shoot_dict : Dictionary
	if active_gun != null:
		shoot_dict = active_gun.get_shoot_dict(not has_ammo)
	else:
		shoot_dict = SkillDirectory.get_dict("Shoot" if has_ammo else "Pistol Whip")

	var skills = [shoot_dict]

	skills.append(SkillDirectory.get_dict("Augur" if party_member != null else "Evade"))
	skills.append(SkillDirectory.get_dict("Unveil"))
	return skills


# Change Lens draws on ally will instead of ammo.
# Each support with will contributes AUGUR_WILL_COST; at least one must afford it.
const CHATTER_SHOOT = [
	"...",
]
const CHATTER_WHIP = [
	"...",
]
const CHATTER_LENS = [
	"...",
]
const CHATTER_AUGUR = [
	"...",
]
const CHATTER_EVADE = [
	"...",
]

const CHATTER_KILL = [
	" ",
	" ",
]

const CHATTER_DIE = [
	" ",
	" ",
]


func use_lens(channel: int) -> void:
	var manager = get_tree().get_first_node_in_group("battle_manager")
	var supports = manager.actors.filter(func(a):
		return a.team == Team.PLAYER and a != self and a.party_member != null \
			and a.party_member.will >= AUGUR_WILL_COST
	)
	if supports.is_empty():
		log_msg("None have the will to keep looking.")
		spend_turn()
		return
	for s in supports:
		s.party_member.spend_will(AUGUR_WILL_COST)
	manager.apply_lens(channel)
	say_random(CHATTER_LENS)
	spend_turn()


func use_skill(command_key: String, targets: Array, part: BodyPartData = null) -> void:
	tick_status_effects()
	if not is_alive():
		emit_signal("turn_finished")
		return
	match command_key:
		"special":
			# routing handled by battle_manager (lens filter UI)
			pass
		"support":
			if _supports_have_will():
				await augur(targets)
			else:
				await evade()
		_:
			spend_turn()


# Augur: spend will from each support, grant whole team dodge + tempo bonus
func augur(all_actors: Array) -> void:
	var supports = all_actors.filter(func(a):
		return a.team == Team.PLAYER and a != self and a.party_member != null and a.party_member.has_will()
	)
	var any_will = supports.any(func(a): return a.party_member.will >= AUGUR_WILL_COST)
	if not any_will:
		log_msg("None have the will to keep looking.")
		spend_turn()
		return
	for support in supports:
		support.party_member.spend_will(AUGUR_WILL_COST)
	var allies = all_actors.filter(func(a): return a.team == Team.PLAYER and a.is_alive())
	for ally in allies:
		ally.apply_status(STATUS_DODGING, AUGUR_DODGE_TURNS)
		ally.tempo_bonus += AUGUR_TEMPO_BONUS
	say_random(CHATTER_AUGUR)
	# Reveal enemy stats panel
	var manager = get_tree().get_first_node_in_group("battle_manager")
	if manager:
		var enemies = manager.actors.filter(func(a): return a.team == Team.ENEMY and a.is_alive())
		for enemy in enemies:
			enemy.reveal_stats()
		manager.battle_hud.show_augur_panel(enemies)
	spend_turn()


# Evade: free, Kendall only, dodge + personal tempo burst
func evade() -> void:
	apply_status(STATUS_DODGING, EVADE_DODGE_TURNS)
	tempo_bonus += EVADE_TEMPO_BONUS
	tempo_pool += EVADE_TEMPO_BONUS
	say_random(CHATTER_EVADE)
	spend_turn()


func _supports_have_will() -> bool:
	var manager = get_tree().get_first_node_in_group("battle_manager")
	if manager == null: return false
	for actor in manager.actors:
		if actor.team == Team.PLAYER and actor != self:
			if actor.party_member != null and actor.party_member.will >= AUGUR_WILL_COST:
				return true
	return false


func _make_skill(label: String, key: String, _slot: String) -> Dictionary:
	return {"name": label, "key": key}
