class_name StatBlock
extends RefCounted
## Runtime rules state for one combatant or character: attribute scores, skill ranks,
## Corpus Portions (health), Anima Portions (spell slots), modifiers and conditions.

var display_name: String = ""
var level: int = 1
## This character's Corpus die. 0 uses RulesConfig.default_corpus_die.
var corpus_die: int = 0
## attribute id -> score
var scores: Dictionary = {}
## skill id -> ranks
var skill_ranks: Dictionary = {}
var corpus: int = 0
var anima: int = 0
## Array of StatModifier (equipment, buffs, etc.)
var modifiers: Array = []
## Array of ActiveCondition
var conditions: Array = []
## Abilities the character knows (from the CharacterSheet).
var known_actions: Array[ActionDef] = []
## slot id -> ItemDef currently equipped.
var equipment: Dictionary = {}
## Hit-die rolls for levels 2 and up (index 0 is level 2), stored on the CharacterSheet.
## A level with no stored roll counts as the die's average, so enemies and test blocks
## that were never rolled still have sensible Corpus.
var corpus_rolls: Array[int] = []
## Corpus gained from companions levelling up (the player character's main source;
## see RulesConfig.player_corpus_share).
var bonus_corpus: int = 0
## Feats owned; a repeated entry is a stack.
var feats: Array[FeatDef] = []
var engine: RulesEngine


func _init(p_engine: RulesEngine, p_name: String = "", p_level: int = 1) -> void:
	engine = p_engine
	display_name = p_name
	level = p_level


## Call after setting scores and level to fill Corpus and Anima Portions.
func refill() -> void:
	corpus = max_corpus()
	anima = max_anima()


# ---------------------------------------------------------------- stats

func score(stat_id: StringName) -> int:
	return int(scores.get(stat_id, engine.config.attribute_base))


## Modifier from the stat itself, before modifiers and conditions.
func base_mod(stat_id: StringName) -> int:
	var def := engine.get_stat(stat_id)
	if def != null and not def.governing_stats.is_empty():
		var ranks := int(skill_ranks.get(stat_id, 0)) * engine.config.skill_rank_bonus
		var total := ranks
		for part in _governing_parts(def):
			total += int(part["value"])
		return total
	if scores.has(stat_id):
		return engine.config.ability_mod(score(stat_id))
	return 0


## Each governing attribute's contribution to a skill or save: {source, value}.
func _governing_parts(def: StatDef) -> Array:
	var count := def.governing_stats.size()
	var parts: Array = []
	for gid in def.governing_stats:
		var gdef := engine.get_stat(gid)
		var label := gdef.display_name if gdef != null else String(gid)
		var m := total_mod(gid)
		if count == 1:
			parts.append({"source": label, "value": m})
		else:
			parts.append({"source": "%s (1/%d)" % [label, count], "value": engine.config.split_mod(m, count)})
	return parts


## Sum of modifiers and condition modifiers targeting this stat.
func modifier_bonus(stat_id: StringName) -> int:
	var total := 0
	for m: StatModifier in modifiers:
		if m.stat == stat_id:
			total += m.value
	for c: ActiveCondition in conditions:
		total += int(c.def.modifiers.get(stat_id, 0))
	return total


func total_mod(stat_id: StringName) -> int:
	return base_mod(stat_id) + modifier_bonus(stat_id)


## Array of {source, value} describing total_mod(stat_id).
func breakdown(stat_id: StringName) -> Array:
	var parts: Array = []
	var def := engine.get_stat(stat_id)
	var label := def.display_name if def != null else String(stat_id)
	if def != null and not def.governing_stats.is_empty():
		parts.append_array(_governing_parts(def))
		var ranks := int(skill_ranks.get(stat_id, 0)) * engine.config.skill_rank_bonus
		if ranks != 0:
			parts.append({"source": "%s ranks" % label, "value": ranks})
	else:
		parts.append({"source": label, "value": base_mod(stat_id)})
	for m: StatModifier in modifiers:
		if m.stat == stat_id:
			parts.append({"source": m.source, "value": m.value})
	for c: ActiveCondition in conditions:
		var v := int(c.def.modifiers.get(stat_id, 0))
		if v != 0:
			parts.append({"source": c.source, "value": v})
	return parts


## Returns {adv: int, dis: int}: how many conditions grant each for this stat.
func advantage_sources(stat_id: StringName) -> Dictionary:
	var adv := 0
	var dis := 0
	for c: ActiveCondition in conditions:
		if c.def.advantage_on.has(String(stat_id)) or c.def.advantage_on.has("all"):
			adv += 1
		if c.def.disadvantage_on.has(String(stat_id)) or c.def.disadvantage_on.has("all"):
			dis += 1
	return {"adv": adv, "dis": dis}


# ------------------------------------------------------------- derived

func defense() -> int:
	return engine.config.base_defense + total_mod(engine.config.defense_stat) + modifier_bonus(&"defense")


func initiative_mod() -> int:
	return total_mod(engine.config.initiative_stat) + modifier_bonus(&"initiative")


## The die this character's Corpus is built from.
func effective_corpus_die() -> int:
	return corpus_die if corpus_die > 0 else engine.config.default_corpus_die


## What a level with no stored roll counts as: the die's average (half + 1).
func corpus_average_gain() -> int:
	return floori(effective_corpus_die() / 2.0) + 1


## Level 1 gets a full die. Each later level gets that level's stored hit-die roll (or
## the average if it was never rolled). The corpus_stat modifier applies at every
## level, and a level always gives at least 1. bonus_corpus is added on top.
func max_corpus() -> int:
	var mod := total_mod(engine.config.corpus_stat)
	var total := engine.config.corpus_base + maxi(1, effective_corpus_die() + mod)
	for i in maxi(0, level - 1):
		var gain := corpus_rolls[i] if i < corpus_rolls.size() else corpus_average_gain()
		total += maxi(1, gain + mod)
	return total + bonus_corpus + modifier_bonus(&"corpus_max")


func max_anima() -> int:
	var best := 0
	for stat_id in engine.config.color_stats:
		best = maxi(best, total_mod(stat_id))
	var from_level: int = floori((level - 1) / float(maxi(1, engine.config.anima_level_step)))
	return maxi(0, engine.config.anima_base + from_level + best + modifier_bonus(&"anima_max"))


# --------------------------------------------------- Corpus and Anima

func is_down() -> bool:
	return corpus <= 0


## Returns the damage actually taken.
func take_damage(amount: int) -> int:
	var dealt := clampi(amount, 0, corpus)
	corpus -= dealt
	return dealt


## Returns the amount actually healed.
func heal(amount: int) -> int:
	var healed := clampi(amount, 0, max_corpus() - corpus)
	corpus += healed
	return healed


func spend_anima(amount: int) -> bool:
	if amount > anima:
		return false
	anima -= amount
	return true


func restore_anima(amount: int) -> int:
	var restored := clampi(amount, 0, max_anima() - anima)
	anima += restored
	return restored


# ----------------------------------------------------------- conditions

func add_condition(def: ConditionDef, source: String = "", duration: int = -2) -> ActiveCondition:
	# Reapplying refreshes the duration instead of stacking.
	for c: ActiveCondition in conditions:
		if c.def == def:
			c.remaining = def.duration_rounds if duration == -2 else duration
			return c
	var active := ActiveCondition.make(def, source, duration)
	conditions.append(active)
	return active


func remove_condition(id: StringName) -> void:
	conditions = conditions.filter(func(c: ActiveCondition): return c.def.id != id)


func has_condition(id: StringName) -> bool:
	for c: ActiveCondition in conditions:
		if c.def.id == id:
			return true
	return false


func can_act() -> bool:
	if is_down():
		return false
	for c: ActiveCondition in conditions:
		if c.def.blocks_actions:
			return false
	return true


## Call once per round. Applies tick damage, counts down durations, drops expired
## conditions. Returns log lines.
func tick_round() -> Array[String]:
	var lines: Array[String] = []
	var keep: Array = []
	for c: ActiveCondition in conditions:
		if c.def.tick_damage != "":
			var r := Dice.roll_expr(c.def.tick_damage, engine.rng)
			var dealt := take_damage(int(r["total"]))
			var tick_line := engine.say(&"condition_tick", {"target": display_name,
					"amount": dealt, "condition": c.def.display_name})
			if tick_line != "":
				lines.append(tick_line)
		if c.remaining > 0:
			c.remaining -= 1
		if c.remaining == 0:
			var end_line := engine.say(&"condition_ends", {"target": display_name,
					"condition": c.def.display_name})
			if end_line != "":
				lines.append(end_line)
		else:
			keep.append(c)
	conditions = keep
	return lines


# ------------------------------------------------------------ equipment

func remove_modifiers_by_origin(origin: StringName) -> void:
	modifiers = modifiers.filter(func(m: StatModifier): return m.origin != origin)


## Replaces all equipment modifiers with those from the given gear.
func apply_equipment(p_equipment: Dictionary) -> void:
	remove_modifiers_by_origin(&"equipment")
	equipment = p_equipment.duplicate()
	for slot in equipment:
		var item := equipment[slot] as ItemDef
		if item == null:
			continue
		for stat_id in item.modifiers:
			modifiers.append(StatModifier.make(
					StringName(stat_id), int(item.modifiers[stat_id]), item.display_name, &"equipment"))
	corpus = mini(corpus, max_corpus())
	anima = mini(anima, max_anima())


## Replaces all feat modifiers with those from the given feats (repeats stack).
func apply_feats(p_feats: Array) -> void:
	remove_modifiers_by_origin(&"feat")
	feats.clear()
	for f in p_feats:
		var feat := f as FeatDef
		if feat == null:
			continue
		feats.append(feat)
		for stat_id in feat.modifiers:
			modifiers.append(StatModifier.make(
					StringName(stat_id), int(feat.modifiers[stat_id]), feat.display_name, &"feat"))
	corpus = mini(corpus, max_corpus())
	anima = mini(anima, max_anima())


## The equipped weapon, or the unarmed fallback if there isn't one.
func weapon() -> ItemDef:
	var item := equipment.get(&"weapon") as ItemDef
	if item != null and item.damage_dice != "":
		return item
	return engine.config.unarmed_weapon()


## Attack stat of the equipped weapon.
func weapon_attack_stat() -> StringName:
	var w := weapon()
	return w.attack_stat if w.attack_stat != &"" else engine.config.default_attack_stat


## Damage stat of the equipped weapon.
func weapon_damage_stat() -> StringName:
	var w := weapon()
	return w.damage_stat if w.damage_stat != &"" else engine.config.default_damage_stat


## The highest Canto level this character has unlocked, from their level.
func max_canto_level() -> int:
	return engine.config.max_canto_level_for(level)


## False for a Canto whose own level is above what this character has unlocked.
## Ordinary actions are always castable.
func can_cast(action: ActionDef) -> bool:
	return not action.is_canto() or action.canto_level <= max_canto_level()


## The levels this character can cast `action` at: the Canto's own range, held at
## their unlocked level. Empty for an ordinary action or a locked Canto.
func castable_levels(action: ActionDef) -> Array[int]:
	var out: Array[int] = []
	if can_cast(action):
		for lvl in action.castable_levels():
			if lvl <= max_canto_level():
				out.append(lvl)
	return out


## The basic Attack, then known actions, then any granted by equipped items.
func available_actions() -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	var attack := engine.config.get_basic_attack()
	if attack != null:
		out.append(attack)
	for action in known_actions:
		if not out.has(action):
			out.append(action)
	for slot in equipment:
		var item := equipment[slot] as ItemDef
		if item == null:
			continue
		for action in item.granted_actions:
			if not out.has(action):
				out.append(action)
	for feat in feats:
		for action in feat.granted_actions:
			if not out.has(action):
				out.append(action)
	return out
