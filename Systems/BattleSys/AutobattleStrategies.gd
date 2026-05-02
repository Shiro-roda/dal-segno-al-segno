## AutobattleStrategies
## Concrete autobattle strategy implementations.
##
## This file self-registers all built-in strategies with BattleSettings on
## _ready().  Add it as an autoload named "AutobattleStrategies", OR attach
## it to a Node in the battle scene — either works because strategies are
## stateless Callables.
##
## ── Adding a new strategy ────────────────────────────────────────────────────
##   1.  Add a new enum value to BattleSettings.AutobattleMode.
##   2.  Write a static func _strategy_your_name(actor, manager) -> Dictionary
##       below following the same pattern as _strategy_repeat_last.
##   3.  Register it in _ready():
##         BattleSettings.register_autobattle_strategy(
##             BattleSettings.AutobattleMode.YOUR_NAME,
##             _strategy_your_name
##         )
##
## ── Action dict shape ────────────────────────────────────────────────────────
##   Mirrors the _last_actions entries in BattleManager:
##   {
##     "command":    String,        # "attack" | "special" | "support" | etc.
##     "target":     WeakRef|null,  # use weakref(actor) or null for AoE
##     "body_part":  BodyPartData|null,
##     "is_struggle":bool,
##     "filter":     int,           # -1 if unused
##   }
##   Return {} to fall back to normal player input for this actor.

extends Node

func _ready() -> void:
	BattleSettings.register_autobattle_strategy(
		BattleSettings.AutobattleMode.REPEAT_LAST,
		_strategy_repeat_last
	)
	# Placeholders — replace the bodies when implementing AI_SCRIPT / FULL_AI.
	BattleSettings.register_autobattle_strategy(
		BattleSettings.AutobattleMode.AI_SCRIPT,
		_strategy_ai_script
	)
	BattleSettings.register_autobattle_strategy(
		BattleSettings.AutobattleMode.FULL_AI,
		_strategy_full_ai
	)


# ── REPEAT_LAST ───────────────────────────────────────────────────────────────
## Replay each character's last confirmed action if it is still valid.
## Falls back to {} (player input) when no previous action exists or the
## target has died.

static func _strategy_repeat_last(actor: BattleActor, manager: Node) -> Dictionary:
	if not is_instance_valid(manager):
		return {}
	var available_keys : Array = actor.get_skills().map(func(s): return s["key"])
	var la : Dictionary = manager._last_actions.get(actor.name, {})

	# ── Validate last action ─────────────────────────────────────────────────
	if not la.is_empty():
		var cmd : String = la.get("command", "")
		if cmd in available_keys:
			# Attack/special: target must still be alive.
			if cmd in ["attack", "special"] and not la.get("is_struggle", false):
				var wr = la.get("target")
				if wr != null:
					var tgt = wr.get_ref()
					if is_instance_valid(tgt) and (tgt as BattleActor).is_alive():
						return la
				# Target gone — fall through to auto-pick below.
			else:
				return la

	# ── No valid last action: auto-pick on first turn ────────────────────────
	# Find the first "attack" skill and pick the lowest-HP living enemy.
	var attack_skill : Dictionary = {}
	for s in actor.get_skills():
		if s.get("key", "") == "attack":
			attack_skill = s
			break
	if attack_skill.is_empty():
		return {}  # No attack available — wait for player.

	var enemies : Array = manager.actors.filter(
		func(a: BattleActor): return a.team != actor.team and a.is_alive())
	if enemies.is_empty():
		return {}

	var is_aoe     : bool = attack_skill.get("aoe",     false)
	var is_struggle: bool = attack_skill.get("struggle", false)
	var target : BattleActor = null
	if not is_aoe and not is_struggle:
		# Pick lowest-HP% enemy.
		enemies.sort_custom(func(a, b):
			return float(a.hp) / max(a.max_hp, 1) < float(b.hp) / max(b.max_hp, 1))
		target = enemies[0]

	# Pick highest-mult body part.
	var removed_mask : int = manager.get("removed_channels") if manager.get("removed_channels") != null else 0
	var part : BodyPartData = null
	if target != null:
		part = AutobattleEvaluator.resolve_part_by_mode(
			AutobattleRule.PartMode.HIGHEST_MULT, target, removed_mask)

	return {
		"command":     attack_skill.get("key", "attack"),
		"target":      weakref(target) if target != null else null,
		"body_part":   part,
		"is_struggle": is_struggle,
		"filter":      -1,
	}


# ── AI_SCRIPT (reserved) ─────────────────────────────────────────────────────
## Designer-authored priority list.  Currently falls through to player input.
## Replace this body with a priority-table lookup when implementing.

static func _strategy_ai_script(actor: BattleActor, manager: Node) -> Dictionary:
	var cfg : ActorAutobattleConfig = BattleSettings.get_actor_config(actor)
	if cfg == null:
		return {}

	var removed_mask : int = manager.get("removed_channels") if manager.get("removed_channels") != null else 0

	for rule in cfg.rules:
		if not AutobattleEvaluator.rule_passes(rule, actor, manager):
			continue
		var available_keys : Array = actor.get_skills().map(func(s): return s["key"])
		if rule.command not in available_keys:
			continue
		var sk_data : Array = actor.get_skills().filter(func(s): return s["key"] == rule.command)
		var is_aoe      : bool = not sk_data.is_empty() and sk_data[0].get("aoe", false)
		var is_struggle : bool = not sk_data.is_empty() and sk_data[0].get("struggle", false)
		var needs_target : bool = not is_aoe and not is_struggle
		var target : BattleActor = null
		if needs_target:
			target = AutobattleEvaluator.resolve_target(rule, actor, manager)
			if target == null:
				continue
		var part : BodyPartData = null
		if target != null and not is_aoe:
			part = AutobattleEvaluator.resolve_part(rule, target, removed_mask)
			if part == null and rule.part_mode != AutobattleRule.PartMode.NONE:
				continue
		return {
			"command":     rule.command,
			"target":      weakref(target) if target != null else null,
			"body_part":   part,
			"is_struggle": is_struggle,
			"filter":      -1,
		}
	if cfg.fallback_repeat_last:
		return _strategy_repeat_last(actor, manager)
	return {}


# ── FULL_AI (reserved) ────────────────────────────────────────────────────────
## Heuristic or learned policy.  Currently falls through to player input.

static func _strategy_full_ai(_actor: BattleActor, _manager: Node) -> Dictionary:
	# TODO: implement heuristic AI (threat assessment, target priority, etc.)
	return {}
