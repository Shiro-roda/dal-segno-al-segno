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
	# BattleManager exposes can_repeat_action() and _last_actions.
	# We call the public helper; if valid, we return the stored action dict.
	if not is_instance_valid(manager):
		return {}
	var la : Dictionary = manager._last_actions.get(actor.name, {})
	if la.is_empty():
		return {}
	# Validate that the command is still available on this actor.
	var available_keys : Array = actor.get_skills().map(func(s): return s["key"])
	var cmd : String = la.get("command", "")
	if cmd not in available_keys:
		return {}
	# Validate that a required target is still alive.
	if cmd in ["attack", "special"] and not la.get("is_struggle", false):
		var wr = la.get("target")
		if wr == null:
			return {}
		var tgt = wr.get_ref()
		if not is_instance_valid(tgt) or not (tgt as BattleActor).is_alive():
			return {}
	return la


# ── AI_SCRIPT (reserved) ─────────────────────────────────────────────────────
## Designer-authored priority list.  Currently falls through to player input.
## Replace this body with a priority-table lookup when implementing.

static func _strategy_ai_script(_actor: BattleActor, _manager: Node) -> Dictionary:
	# TODO: implement priority-action-script strategy.
	# Read a resource (e.g. an Array of {condition, action} dicts) attached
	# to the actor or the encounter and evaluate conditions top-down.
	return {}


# ── FULL_AI (reserved) ────────────────────────────────────────────────────────
## Heuristic or learned policy.  Currently falls through to player input.

static func _strategy_full_ai(_actor: BattleActor, _manager: Node) -> Dictionary:
	# TODO: implement heuristic AI (threat assessment, target priority, etc.)
	return {}
