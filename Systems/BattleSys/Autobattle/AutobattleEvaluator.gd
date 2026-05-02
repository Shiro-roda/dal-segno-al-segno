extends RefCounted
class_name AutobattleEvaluator
## Static helpers that evaluate AutobattleConditions and AutobattleRules
## against live battle state, and resolve targets / body parts.
##
## All public methods are static so they can be called from any strategy
## callable without needing an instance.

# ── Condition evaluation ──────────────────────────────────────────────────────

## Returns true if ALL conditions in `rule` pass given the live state.
## `actor`   — the actor whose turn it is
## `manager` — the BattleManager node (duck-typed for loose coupling)
static func rule_passes(rule: AutobattleRule, actor: BattleActor, manager: Node) -> bool:
	if rule.disabled:
		return false
	# Empty condition list = unconditional (always passes)
	if rule.conditions.is_empty():
		return true
	for cond in rule.conditions:
		if not condition_passes(cond, actor, manager):
			return false
	return true


## Evaluate a single AutobattleCondition against live state.
static func condition_passes(cond: AutobattleCondition, actor: BattleActor, manager: Node) -> bool:
	var subject := cond.subject
	match subject:
		AutobattleCondition.Subject.SELF:
			var val := _read_property(cond, actor, manager)
			return _compare(val, cond.op, cond.value)

		AutobattleCondition.Subject.ANY_ENEMY:
			var enemies := _get_enemies(actor, manager)
			for e in enemies:
				if _compare(_read_property(cond, e, manager), cond.op, cond.value):
					return true
			return false

		AutobattleCondition.Subject.ALL_ENEMY:
			var enemies := _get_enemies(actor, manager)
			if enemies.is_empty(): return false
			for e in enemies:
				if not _compare(_read_property(cond, e, manager), cond.op, cond.value):
					return false
			return true

		AutobattleCondition.Subject.ANY_ALLY:
			var allies := _get_allies(actor, manager)
			for a in allies:
				if _compare(_read_property(cond, a, manager), cond.op, cond.value):
					return true
			return false

		AutobattleCondition.Subject.ALL_ALLY:
			var allies := _get_allies(actor, manager)
			if allies.is_empty(): return false
			for a in allies:
				if not _compare(_read_property(cond, a, manager), cond.op, cond.value):
					return false
			return true

	return false


## Read the numeric value of cond.property from a BattleActor.
static func _read_property(cond: AutobattleCondition, target: BattleActor, manager: Node) -> float:
	match cond.property:
		AutobattleCondition.Property.HP_PCT:
			return float(target.hp) / float(max(target.max_hp, 1))
		AutobattleCondition.Property.HP_ABS:
			return float(target.hp)
		AutobattleCondition.Property.HAS_STATUS:
			return 1.0 if target.has_status(cond.status_id) else 0.0
		AutobattleCondition.Property.MISSING_STATUS:
			return 0.0 if target.has_status(cond.status_id) else 1.0
		AutobattleCondition.Property.ATTACK_MOD:
			return float(target.attack_modifier)
		AutobattleCondition.Property.FLAT_MOD:
			return float(target.flat_modifier)
		AutobattleCondition.Property.TEMPO_PCT:
			return target.tempo_pool / 100.0
		AutobattleCondition.Property.ALLY_COUNT:
			return float(_get_allies(target, manager).size())
		AutobattleCondition.Property.ENEMY_COUNT:
			return float(_get_enemies(target, manager).size())
		AutobattleCondition.Property.TURN_NUMBER:
			return float(manager.get("turn_number") if manager.get("turn_number") != null else 0)
	return 0.0


static func _compare(a: float, op: int, b: float) -> bool:
	match op:
		AutobattleCondition.Operator.LT:  return a <  b
		AutobattleCondition.Operator.LTE: return a <= b
		AutobattleCondition.Operator.EQ:  return is_equal_approx(a, b)
		AutobattleCondition.Operator.GTE: return a >= b
		AutobattleCondition.Operator.GT:  return a >  b
	return false


# ── Target resolution ─────────────────────────────────────────────────────────

## Resolve the best BattleActor target for a rule given the current battle state.
## Returns null if no valid target exists.
static func resolve_target(
		rule: AutobattleRule,
		actor: BattleActor,
		manager: Node) -> BattleActor:

	var is_support : bool = rule.command in ["support"]
	var pool : Array
	if is_support or rule.target_mode == AutobattleRule.TargetMode.SELF:
		pool = _get_allies(actor, manager)
	else:
		pool = _get_enemies(actor, manager)

	if pool.is_empty():
		return null

	match rule.target_mode:
		AutobattleRule.TargetMode.SELF:
			return actor

		AutobattleRule.TargetMode.LOWEST_HP_PCT:
			return pool.reduce(func(best, a):
				return a if (float(a.hp) / max(a.max_hp,1)) < (float(best.hp) / max(best.max_hp,1)) else best)

		AutobattleRule.TargetMode.HIGHEST_HP_PCT:
			return pool.reduce(func(best, a):
				return a if (float(a.hp) / max(a.max_hp,1)) > (float(best.hp) / max(best.max_hp,1)) else best)

		AutobattleRule.TargetMode.RANDOM:
			return pool[randi() % pool.size()]

		AutobattleRule.TargetMode.FIRST:
			return pool[0]

		AutobattleRule.TargetMode.HAS_STATUS:
			for t in pool:
				if t.has_status(rule.target_status_id):
					return t
			return pool[0]  # fallback to first if none match

		AutobattleRule.TargetMode.MISSING_STATUS:
			for t in pool:
				if not t.has_status(rule.target_status_id):
					return t
			return pool[0]

	return pool[0]


## Resolve a BodyPartData for a rule given the selected target.
## Returns null when part selection should be skipped (AoE, struggle, etc.)
static func resolve_part(
		rule: AutobattleRule,
		target: BattleActor,
		removed_mask: int) -> BodyPartData:

	if rule.part_mode == AutobattleRule.PartMode.NONE:
		return null

	var parts : Array = target.get_visible_parts(removed_mask) \
		if target.has_method("get_visible_parts") else []
	# Filter out broken parts
	var available : Array = parts.filter(func(p): return not p.is_broken)
	if available.is_empty():
		return null

	match rule.part_mode:
		AutobattleRule.PartMode.FIRST:
			return available[0]
		AutobattleRule.PartMode.HIGHEST_MULT:
			return available.reduce(func(best, p):
				return p if p.damage_multiplier > best.damage_multiplier else best)
		AutobattleRule.PartMode.RANDOM:
			return available[randi() % available.size()]

	return available[0]


# ── Convenience helpers ───────────────────────────────────────────────────────

static func _get_enemies(actor: BattleActor, manager: Node) -> Array:
	var all : Array = manager.get("actors") if manager.get("actors") != null else []
	return all.filter(func(a): return a.team != actor.team and a.is_alive() and a.can_be_targeted())


static func _get_allies(actor: BattleActor, manager: Node) -> Array:
	var all : Array = manager.get("actors") if manager.get("actors") != null else []
	return all.filter(func(a): return a.team == actor.team and a != actor and a.is_alive())


## Resolve a part using an explicit PartMode (without needing a full AutobattleRule).
static func resolve_part_by_mode(
		part_mode: AutobattleRule.PartMode,
		target: BattleActor,
		removed_mask: int) -> BodyPartData:
	var dummy := AutobattleRule.new()
	dummy.part_mode = part_mode
	return resolve_part(dummy, target, removed_mask)
