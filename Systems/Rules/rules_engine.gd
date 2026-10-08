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


func save_dc(caster: StatBlock, stat_id: StringName) -> int:
	return config.save_dc_base + caster.total_mod(stat_id) \
			+ floori(caster.level / float(maxi(1, config.save_dc_level_step)))


# --------------------------------------------------------------- rolls

func _resolve(kind: RollResult.Kind, actor: StatBlock, stat_id: StringName, target: int,
		mode: RollMode, extra_bonus: int, label: String) -> RollResult:
	var r := RollResult.new()
	r.kind = kind
	r.stat = stat_id
	r.target = target
	var adv := actor.advantage_sources(stat_id)
	r.mode = resolve_mode(mode, adv["adv"], adv["dis"])
	var die := roll_die(r.mode)
	r.natural = die["natural"]
	r.rolls.assign(die["rolls"])
	r.parts = actor.breakdown(stat_id)
	if extra_bonus != 0:
		r.parts.append({"source": "Bonus", "value": extra_bonus})
	r.bonus = 0
	for p in r.parts:
		r.bonus += int(p["value"])
	r.total = r.natural + r.bonus
	r.crit = r.natural >= config.crit_min
	r.fumble = r.natural <= config.fumble_max
	r.success = r.total >= target
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
		var def := get_stat(stat_id)
		r.label = say(&"check_label", {"actor": actor.display_name,
				"stat": def.display_name if def != null else String(stat_id)})
	r.text = text
	return r


## Skill or attribute check against a DC.
func check(actor: StatBlock, stat_id: StringName, dc: int, mode: RollMode = RollMode.NORMAL,
		extra_bonus: int = 0, label: String = "") -> RollResult:
	return _resolve(RollResult.Kind.CHECK, actor, stat_id, dc, mode, extra_bonus, label)


## Attack roll against the defender's defense.
func attack(attacker: StatBlock, stat_id: StringName, defender: StatBlock,
		mode: RollMode = RollMode.NORMAL, extra_bonus: int = 0, label: String = "") -> RollResult:
	if label == "":
		label = say(&"attack_label", {"attacker": attacker.display_name, "defender": defender.display_name})
	return _resolve(RollResult.Kind.ATTACK, attacker, stat_id, defender.defense(), mode, extra_bonus, label)


## Saving throw for `target` against a fixed DC.
func save(target: StatBlock, stat_id: StringName, dc: int, mode: RollMode = RollMode.NORMAL,
		extra_bonus: int = 0, label: String = "") -> RollResult:
	return _resolve(RollResult.Kind.SAVE, target, stat_id, dc, mode, extra_bonus, label)


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
## Returns {ok, reason, level, rolls: Array[RollResult], log: Array[String]}.
func use_action(user: StatBlock, action: ActionDef, targets: Array, cast_level: int = 0) -> Dictionary:
	var result := {"ok": false, "reason": "", "level": 0, "rolls": [], "log": []}
	if not user.can_act():
		result["reason"] = say(&"cannot_act", {"actor": user.display_name})
		return result
	if not user.can_cast(action):
		result["reason"] = say(&"canto_locked", {"actor": user.display_name,
				"action": action.display_name, "level": action.canto_level})
		return result
	# An upcast is held at the highest level the caster has unlocked.
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
	var resolved_targets: Array = [user] if action.target == ActionDef.Target.SELF else targets
	for t: StatBlock in resolved_targets:
		_apply_to_target(user, action, t, result, level)
	return result


func _apply_to_target(user: StatBlock, action: ActionDef, target: StatBlock, result: Dictionary,
		level: int = 0) -> void:
	var hit := true
	var crit := false
	var saved := false
	match action.roll:
		ActionDef.Roll.ATTACK:
			var attack_stat := action.attack_stat if action.attack_stat != &"" else user.weapon_attack_stat()
			var r := attack(user, attack_stat, target)
			result["rolls"].append(r)
			var attack_line := r.describe()
			if attack_line != "":
				result["log"].append(attack_line)
			hit = r.success
			crit = r.crit
		ActionDef.Roll.SAVE:
			var dc := save_dc(user, action.dc_stat)
			var r := save(target, action.save_stat, dc)
			result["rolls"].append(r)
			var save_line := r.describe()
			if save_line != "":
				result["log"].append(save_line)
			saved = r.success
	if not hit:
		return
	# How many levels above the Canto's own level this was cast at.
	var levels_up := 0
	if action.is_canto():
		levels_up = maxi(0, level - action.canto_level)
	elif action.is_cantrip():
		levels_up = config.cantrip_tier(user.level)
	for effect in action.effects:
		_apply_effect(user, effect, target, crit, saved, result, levels_up)


func _apply_effect(user: StatBlock, effect: EffectDef, target: StatBlock,
		crit: bool, saved: bool, result: Dictionary, levels_up: int = 0) -> void:
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
			var dealt := target.take_damage(amount)
			_log(result, &"damage", {"target": target.display_name, "amount": dealt,
					"type": damage_type, "corpus": target.corpus, "max_corpus": target.max_corpus()})
		EffectDef.Kind.HEAL:
			var total := int(Dice.roll_expr(effect.dice, rng)["total"]) + _upcast_total(effect, levels_up)
			var healed := target.heal(maxi(0, total + bonus))
			_log(result, &"heal", {"target": target.display_name, "amount": healed})
		EffectDef.Kind.RESTORE_ANIMA:
			var total := int(Dice.roll_expr(effect.dice, rng)["total"]) + _upcast_total(effect, levels_up)
			var restored := target.restore_anima(maxi(0, total + bonus))
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


## Extra dice from casting a Canto above its own level: `upcast_dice` once per level.
func _upcast_total(effect: EffectDef, levels_up: int, mult: int = 1) -> int:
	if levels_up <= 0 or effect.upcast_dice == "":
		return 0
	var total := 0
	for _i in levels_up:
		total += int(Dice.roll_expr(effect.upcast_dice, rng, mult)["total"])
	return total
