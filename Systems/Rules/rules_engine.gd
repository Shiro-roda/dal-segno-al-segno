class_name RulesEngine
extends RefCounted
## Pure-logic d20 resolver. Knows nothing about specific stats: every attribute,
## skill and derived stat comes from StatDef resources registered at runtime.

enum RollMode { NORMAL, ADVANTAGE, DISADVANTAGE }

var config: RulesConfig
var rng := RandomNumberGenerator.new()
## Every line the log can print. Rules loads Data/log_text.tres into this.
var text: LogText = LogText.new()
## stat id -> StatDef
var stats: Dictionary = {}


func _init(p_config: RulesConfig = null, p_seed: int = -1) -> void:
	config = p_config if p_config != null else RulesConfig.new()
	if p_seed >= 0:
		rng.seed = p_seed
	else:
		rng.randomize()


# ------------------------------------------------------------- registry

## One line of log text for `event`, from the LogText resource.
func say(event: StringName, vars: Dictionary = {}) -> String:
	return text.line(event, vars, rng)


## Adds a line to an action result's log, unless that text was left blank.
func _log(result: Dictionary, event: StringName, vars: Dictionary = {}) -> void:
	var line := say(event, vars)
	if line != "":
		result["log"].append(line)

func register_stat(def: StatDef) -> void:
	stats[def.id] = def


func get_stat(id: StringName) -> StatDef:
	return stats.get(id) as StatDef

## How a stat is named in log text: attributes use their abbreviation, everything else its full name.
func stat_label(stat_id: StringName) -> String:
	var def := get_stat(stat_id)
	if def == null:
		return String(stat_id)
	if text.abbreviate_attributes and def.category == StatDef.Category.ATTRIBUTE:
		return def.short_name()
	return def.display_name

## Loads every StatDef .tres found in `dir` and its subfolders.
func load_stat_defs(dir: String) -> int:
	var count := 0
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tres") or file.ends_with(".res"):
			var def := load(dir.path_join(file)) as StatDef
			if def != null:
				register_stat(def)
				count += 1
	for sub in DirAccess.get_directories_at(dir):
		count += load_stat_defs(dir.path_join(sub))
	return count


func stats_in_category(category: StatDef.Category) -> Array[StatDef]:
	var out: Array[StatDef] = []
	for def: StatDef in stats.values():
		if def.category == category:
			out.append(def)
	return out


# ------------------------------------------------------------ primitives

func ability_mod(score: int) -> int:
	return config.ability_mod(score)


## Combines an explicit mode with sources of advantage/disadvantage.
func resolve_mode(mode: RollMode, adv_sources: int = 0, dis_sources: int = 0) -> int:
	var adv := adv_sources + (1 if mode == RollMode.ADVANTAGE else 0)
	var dis := dis_sources + (1 if mode == RollMode.DISADVANTAGE else 0)
	if config.advantage_cancels:
		if adv > 0 and dis > 0:
			return 0
		return 1 if adv > 0 else (-1 if dis > 0 else 0)
	return clampi(adv - dis, -1, 1)


## Rolls the die. `mode` is 1 (advantage), -1 (disadvantage) or 0.
## Returns {natural, rolls}.
func roll_die(mode: int) -> Dictionary:
	var first := Dice.roll(config.die_sides, rng)
	if mode == 0:
		return {"natural": first, "rolls": [first]}
	var second := Dice.roll(config.die_sides, rng)
	var chosen := maxi(first, second) if mode > 0 else mini(first, second)
	return {"natural": chosen, "rolls": [first, second]}


## DC of a spell save: base + the casting attribute's modifier + level scaling + the
## caster's spellcasting discipline for that attribute.
func save_dc(caster: StatBlock, stat_id: StringName) -> int:
	return config.save_dc_base + caster.total_mod(stat_id) \
			+ floori(caster.level / float(maxi(1, config.save_dc_level_step))) \
			+ caster.spell_discipline(stat_id)


# --------------------------------------------------------------- rolls

## `roll_under` is for -saves: the roll must come in strictly under `target`, and advantage
## keeps the lower die. Modifiers are NOT inverted: a negative modifier stays negative, so on
## a -save it lowers the total and helps. That is intentional.
## `discipline` is the roller's discipline bonus for this roll (the level-based bonus times
## their multiplier, positive or negative); it appears as its own "Discipline" line.
func _resolve(kind: RollResult.Kind, actor: StatBlock, stat_id: StringName, target: int,
		mode: RollMode, extra_bonus: int, label: String, roll_under := false,
		discipline := 0) -> RollResult:
	var r := RollResult.new()
	r.kind = kind
	r.stat = stat_id
	r.target = target
	r.roll_under = roll_under
	var roll_key := &""
	if kind == RollResult.Kind.ATTACK:
		roll_key = &"attack"
	elif kind == RollResult.Kind.SAVE:
		roll_key = &"save"
	var adv := actor.advantage_sources(stat_id, roll_key)
	r.mode = resolve_mode(mode, adv["adv"], adv["dis"])
	# Advantage means "better outcome": the higher die normally, the lower die for a -save.
	var die := roll_die(-r.mode if roll_under else r.mode)
	r.natural = die["natural"]
	r.rolls.assign(die["rolls"])
	r.parts = actor.breakdown(stat_id)
	if extra_bonus != 0:
		r.parts.append({"source": "Bonus", "value": extra_bonus})
	if discipline != 0:
		r.parts.append({"source": "Discipline", "value": discipline})
	r.bonus = 0
	for p in r.parts:
		r.bonus += int(p["value"])
	r.total = r.natural + r.bonus
	r.crit = r.natural >= config.crit_min
	r.fumble = r.natural <= config.fumble_max
	r.success = r.total < target if roll_under else r.total >= target
	# Natural crit / fumble overrides apply to attacks only.
	if kind == RollResult.Kind.ATTACK:
		if r.crit and config.natural_crit_auto_hit:
			r.success = true
		elif r.fumble and config.natural_fumble_auto_miss:
			r.success = false
		if not r.success:
			r.crit = false
	else:
		r.crit = false
		r.fumble = false
	if label != "":
		r.label = label
	else:
		r.label = say(&"check_label", {"actor": actor.display_name,
				"stat": stat_label(stat_id)})
	r.text = text
	return r


## Skill or attribute check against a DC. The actor's skill discipline for `stat_id` applies.
func check(actor: StatBlock, stat_id: StringName, dc: int, mode: RollMode = RollMode.NORMAL,
		extra_bonus: int = 0, label: String = "") -> RollResult:
	return _resolve(RollResult.Kind.CHECK, actor, stat_id, dc, mode, extra_bonus, label,
			false, actor.skill_discipline(stat_id))


## Attack roll against the defender's defense. `discipline` is the weapon or spellcasting
## discipline to add; use_action works it out from the action being used.
func attack(attacker: StatBlock, stat_id: StringName, defender: StatBlock,
		mode: RollMode = RollMode.NORMAL, extra_bonus: int = 0, label: String = "",
		discipline: int = 0) -> RollResult:
	if label == "":
		label = say(&"attack_label", {"attacker": attacker.display_name, "defender": defender.display_name})
	var flat := attacker.modifier_bonus(&"attack")
	return _resolve(RollResult.Kind.ATTACK, attacker, stat_id, defender.defense(), mode,
			extra_bonus + flat, label, false, discipline)

## Saving throw for `target` against a fixed DC. A PLUS save (+save) succeeds on a total
## at or over the DC; a MINUS save (-save) succeeds on a total strictly under it.
func save(target: StatBlock, stat_id: StringName, dc: int, mode: RollMode = RollMode.NORMAL,
		extra_bonus: int = 0, label: String = "",
		save_type: RollResult.SaveType = RollResult.SaveType.PLUS) -> RollResult:
	return _resolve(RollResult.Kind.SAVE, target, stat_id, dc, mode, extra_bonus, label,
			save_type == RollResult.SaveType.MINUS, target.save_discipline(stat_id))


## Initiative roll. Returns the total.
func roll_initiative(actor: StatBlock) -> int:
	return Dice.roll(config.die_sides, rng) + actor.initiative_mod()


# -------------------------------------------------------------- actions

## Anima Portions `action` costs when used at `level`. A Canto costs its level's
## price from RulesConfig.canto_costs; anything else costs its own anima_cost.
func anima_cost_for(action: ActionDef, level: int = 0) -> int:
	if action.is_canto():
		return config.canto_cost(action.resolve_level(level))
	if action.is_cantrip():
		return 0
	return action.anima_cost


## Uses an action. For a Canto, `cast_level` picks the level to cast it at (0 means
## its own level; anything else is limited to what the Canto allows).
## `targets` is either a flat Array of StatBlocks (used for every effect not
## aimed at SELF) or a Dictionary {EffectDef.Target: Array[StatBlock]}. SELF always means
## the user. Returns {ok, reason, level, rolls: Array[RollResult], log: Array[String],
## action: String, readout: Array[Dictionary]}. `readout` lists every number rolled, in
## order, for the combat roll display (see _readout).
func use_action(user: StatBlock, action: ActionDef, targets: Variant, cast_level: int = 0) -> Dictionary:
	var result := {"ok": false, "reason": "", "level": 0, "rolls": [], "log": [],
			"readout": [], "action": action.display_name}
	if not user.can_act():
		result["reason"] = say(&"cannot_act", {"actor": user.display_name})
		return result
	if not user.can_cast(action):
		result["reason"] = say(&"canto_locked", {"actor": user.display_name,
				"action": action.display_name, "level": action.canto_level})
		return result
	var level := action.resolve_level(cast_level)
	if action.is_canto():
		level = mini(level, user.max_canto_level())
	if not user.spend_anima(anima_cost_for(action, level)):
		result["reason"] = say(&"no_anima")
		return result
	result["ok"] = true
	result["level"] = level
	if action.is_canto():
		_log(result, &"canto_used", {"actor": user.display_name, "action": action.display_name,
			"level": level})
	elif action.is_cantrip():
		_log(result, &"cantrip_used", {"actor": user.display_name, "action": action.display_name})
	else:
		_log(result, &"action_used", {"actor": user.display_name, "action": action.display_name})

	var by_kind := _targets_by_kind(user, action, targets)
	var levels_up := 0
	if action.is_canto():
		levels_up = maxi(0, level - action.canto_level)
	elif action.is_cantrip():
		levels_up = config.cantrip_tier(user.level)
	# Everyone hit, in the order the effects first name them, so the log reads target by
	# target: that target's roll, then its effects.
	var hit_order: Array = []
	for effect in action.effects:
		if effect == null:
			continue
		for t in by_kind.get(effect.target, []):
			if not hit_order.has(t):
				hit_order.append(t)
	var passes := _attack_passes(user, action)
	for i in passes.size():
		user.weapon_override = passes[i]
		for t in hit_order:
			var foe := t as StatBlock
			if i > 0 and foe != user and foe.corpus <= 0:
				continue  # already down: skip the remaining attacks on it
			_apply_to_target(user, action, foe, by_kind, result, levels_up)
	user.weapon_override = null
	return result


## Adds one rolled number to an action result's readout, which the combat roll display
## plays back. kind: attack, save, damage, heal or anima. `who` made the roll, `against`
## is who it was made against or aimed at. outcome: hit, miss, saved, failed, or empty.
func _readout(result: Dictionary, kind: StringName, value: int, who: String, against: String,
		detail := "", outcome: StringName = &"", crit := false, fumble := false) -> void:
	(result["readout"] as Array).append({"kind": kind, "value": value, "who": who,
			"against": against, "detail": detail, "outcome": outcome,
			"crit": crit, "fumble": fumble})


func _targets_by_kind(user: StatBlock, action: ActionDef, targets: Variant) -> Dictionary:
	var out := {}
	if targets is Dictionary:
		out = (targets as Dictionary).duplicate()
	else:
		for kind in action.target_kinds():
			out[kind] = targets
	out[EffectDef.Target.SELF] = [user]
	return out


func _apply_to_target(user: StatBlock, action: ActionDef, target: StatBlock, by_kind: Dictionary,
		result: Dictionary, levels_up: int = 0) -> void:
	var hit := true
	var crit := false
	var saved := false
	# Only enemy-aimed effects are rolled for; self and ally effects always land.
	var rolled := false
	if target != user:
		for effect in action.effects:
			if effect != null and effect.is_hostile() \
					and (by_kind.get(effect.target, []) as Array).has(target):
				rolled = true
				break
	if rolled:
		match action.roll:
			ActionDef.Roll.ATTACK:
				var attack_stat := action.attack_stat if action.attack_stat != &"" else user.weapon_attack_stat()
				var r := attack(user, attack_stat, target, RollMode.NORMAL, 0, "",
						_attack_discipline(user, action, attack_stat))
				for m in _mechanics_for(user, action):
					m.on_attack_rolled(user, action, r, target)
				result["rolls"].append(r)
				var attack_line := r.describe()
				if attack_line != "":
					result["log"].append(attack_line)
				_readout(result, &"attack", r.total, user.display_name, target.display_name,
						"d20 %d %+d  vs %d" % [r.natural, r.bonus, r.target],
						&"hit" if r.success else &"miss", r.crit, r.fumble)
				hit = r.success
				crit = r.crit
			ActionDef.Roll.SAVE:
				var dc := save_dc(user, action.dc_stat)
				var r := save(target, action.save_stat, dc, RollMode.NORMAL, 0, "", action.save_type)
				result["rolls"].append(r)
				var save_line := r.describe()
				if save_line != "":
					result["log"].append(save_line)
				_readout(result, &"save", r.total, target.display_name, user.display_name,
						"d20 %d %+d  vs DC %s%d" % [r.natural, r.bonus, "<" if r.roll_under else "", r.target],
						&"saved" if r.success else &"failed")
				saved = r.success
	for effect in action.effects:
		if effect == null or not (by_kind.get(effect.target, []) as Array).has(target):
			continue
		if effect.is_hostile():
			if hit:
				_apply_effect(user, effect, target, action, crit, saved, result, levels_up)
		else:
			_apply_effect(user, effect, target, action, false, false, result, levels_up)


func _apply_effect(user: StatBlock, effect: EffectDef, target: StatBlock, action: ActionDef,
		crit: bool, saved: bool, result: Dictionary, levels_up: int = 0,) -> void:
	if saved and effect.on_save == EffectDef.OnSave.NEGATES:
		_log(result, &"resisted", {"target": target.display_name})
		return
	var bonus := user.total_mod(effect.bonus_stat) if effect.bonus_stat != &"" else 0
	match effect.kind:
		EffectDef.Kind.DAMAGE, EffectDef.Kind.WEAPON_DAMAGE:
			var mult := config.crit_dice_multiplier if crit else 1
			var amount := 0
			var damage_type := effect.damage_type
			if effect.kind == EffectDef.Kind.WEAPON_DAMAGE:
				# The dice belong to the equipped weapon, not to the action.
				var weapon := user.weapon()
				damage_type = weapon.damage_type
				amount += int(Dice.roll_expr(weapon.damage_dice, rng, mult)["total"])
				amount += user.total_mod(user.weapon_damage_stat())
			amount += int(Dice.roll_expr(effect.dice, rng, mult)["total"])
			amount += _upcast_total(effect, levels_up, mult)
			amount += bonus + user.modifier_bonus(&"damage")
			if saved and effect.on_save == EffectDef.OnSave.HALF:
				amount = floori(amount / 2.0)
			amount = maxi(0, amount)
			var note := String(damage_type)
			if saved and effect.on_save == EffectDef.OnSave.HALF:
				note += ", halved"
			var event := DamageEvent.new()
			event.source = user
			event.target = target
			event.action = action
			event.amount = amount
			event.damage_type = damage_type
			event.crit = crit
			var dealt := target.receive_damage(event)
			for n in event.notes:
				note += ", " + n
			_readout(result, &"damage", event.amount, user.display_name, target.display_name, note, &"", crit)
			for m in _mechanics_for(user, action):
				m.on_damage_dealt(user, event)
			_log(result, &"damage", {"target": target.display_name, "amount": dealt,
					"type": damage_type, "corpus": target.corpus, "max_corpus": target.max_corpus()})
		EffectDef.Kind.HEAL:
			var total := int(Dice.roll_expr(effect.dice, rng)["total"]) + _upcast_total(effect, levels_up)
			var healing := maxi(0, total + bonus)
			_readout(result, &"heal", healing, user.display_name, target.display_name, "healing")
			var healed := target.heal(healing)
			_log(result, &"heal", {"target": target.display_name, "amount": healed})
		EffectDef.Kind.RESTORE_ANIMA:
			var total := int(Dice.roll_expr(effect.dice, rng)["total"]) + _upcast_total(effect, levels_up)
			var refill := maxi(0, total + bonus)
			_readout(result, &"anima", refill, user.display_name, target.display_name, "anima")
			var restored := target.restore_anima(refill)
			_log(result, &"anima_restored", {"target": target.display_name, "amount": restored})
		EffectDef.Kind.APPLY_CONDITION:
			if effect.condition != null:
				var dur := -2 if effect.condition_duration < 0 else effect.condition_duration
				if levels_up > 0 and effect.upcast_duration > 0:
					var base_rounds := effect.condition.duration_rounds if effect.condition_duration < 0 \
							else effect.condition_duration
					dur = base_rounds + effect.upcast_duration * levels_up
				target.add_condition(effect.condition, user.display_name, dur)
				_log(result, &"condition_applied", {"target": target.display_name,
						"condition": effect.condition.display_name})
		EffectDef.Kind.CUSTOM:
			effect.apply_custom(self, user, target, {"crit": crit, "saved": saved,
					"levels_up": levels_up, "result": result})


## Extra dice from casting a Canto above its own level: `upcast_dice` once per level.
func _upcast_total(effect: EffectDef, levels_up: int, mult: int = 1) -> int:
	if levels_up <= 0 or effect.upcast_dice == "":
		return 0
	var total := 0
	for _i in levels_up:
		total += int(Dice.roll_expr(effect.upcast_dice, rng, mult)["total"])
	return total

## The discipline bonus an attack roll gets. A weapon action uses the discipline for the
## weapon in hand (the secondary weapon on its own passes). A Canto or cantrip uses the
## caster's spellcasting discipline for its attack stat. Anything else gets none.
func _attack_discipline(user: StatBlock, action: ActionDef, attack_stat: StringName) -> int:
	if action.is_weapon_action():
		return user.weapon_discipline()
	if action.is_canto() or action.is_cantrip():
		return user.spell_discipline(attack_stat)
	return 0


func _mechanics_for(user: StatBlock, action: ActionDef) -> Array[Mechanic]:
	var out = user.active_mechanics()
	for m in action.mechanics:
		if m != null:
			out.append(m)
	return out

## One entry per attack the action makes: null = the equipped weapon, else the weapon to
## swap in. Only weapon actions (those with a weapon-damage step) get extra attacks.
func _attack_passes(user: StatBlock, action: ActionDef) -> Array:
	if not action.is_weapon_action():
		return [null]
	var out: Array = []
	for _i in maxi(1, user.attacks_with(false)):
		out.append(null)
	var secondary := user.secondary_weapon()
	if secondary != null:
		for _i in user.attacks_with(true):
			out.append(secondary)
	return out
