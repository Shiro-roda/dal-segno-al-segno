class_name Combatant
extends RefCounted
## One participant in a CombatSession: a StatBlock plus combat-only state.

enum Side { PARTY, ENEMY }
## What a party member does on their own turn when no order is queued.
enum Behavior { ATTACK, HEAL_WOUNDED }

## Party settings carried from one fight to the next (this session only), by name.
static var _remembered: Dictionary = {}

var block: StatBlock
var side: Combatant.Side = Side.PARTY
## Fills from 0 to 1; at 1 this combatant takes a turn.
var gauge: float = 0.0
## Preferred target: what auto-attacks and single-target orders aim at.
var target: Combatant
## A queued order: {action: ActionDef, level: int, target: Combatant}. Empty = none.
var order: Dictionary = {}

# ── automatic behaviour (party) ──────────────────────────────────────────────
## What they do each turn when nothing is queued. Null = the basic attack.
var default_action: ActionDef
var default_level: int = 0
var behavior: Behavior = Behavior.ATTACK

# ── positioning ──────────────────────────────────────────────────────────────
## The in-world body. Null = no positioning (always in reach).
var body: Node3D
var move_speed: float = 3.5
## Reach of a basic attack, in metres (centre to centre). Raise it for ranged weapons.
var attack_range: float = 2.2
## Party only: don't advance on targets automatically.
var hold_position: bool = false
## An explicit player move order and where it goes.
var move_order: bool = false
var move_goal: Vector3 = Vector3.ZERO
## True on frames where this combatant moved (for animations).
var moving: bool = false

# ── turn state ───────────────────────────────────────────────────────────────
## Gauge is full and the action is waiting to be in reach.
var turn_pending: bool = false
var pending_plan: Dictionary = {}
var approach_target: Combatant
var approach_reach: float = 0.0

## Watchdog: how long a waiting turn has gone without getting closer to reach, and the
## closest it has been (metres beyond reach; 0 or less means in reach).
var stall_time: float = 0.0
var best_gap: float = INF

func _init(p_block: StatBlock, p_side: Combatant.Side) -> void:
	block = p_block
	side = p_side


func display_name() -> String:
	return block.display_name


func is_down() -> bool:
	return block.is_down()


func has_order() -> bool:
	return not order.is_empty()


## Saves the automatic settings so the next fight starts with them.
func remember() -> void:
	if side != Side.PARTY:
		return
	_remembered[block.display_name] = {
		"action": default_action,
		"level": default_level,
		"behavior": int(behavior),
	}


## Restores saved settings, dropping a default action the character can no longer cast.
func recall() -> void:
	if side != Side.PARTY or not _remembered.has(block.display_name):
		return
	var saved: Dictionary = _remembered[block.display_name]
	behavior = int(saved["behavior"]) as Behavior
	var action: ActionDef = saved["action"]
	if action != null and block.can_cast(action):
		default_action = action
		default_level = int(saved["level"])
