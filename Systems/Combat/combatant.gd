class_name Combatant
extends RefCounted
## One participant in a CombatSession: a StatBlock plus combat-only state.

enum Side { PARTY, ENEMY }

var block: StatBlock
var side: Combatant.Side = Side.PARTY
## Fills from 0 to 1; at 1 this combatant takes a turn.
var gauge: float = 0.0
## Preferred target: what auto-attacks and single-target orders aim at.
var target: Combatant
## A queued order: {action: ActionDef, level: int, target: Combatant}. Empty = none.
var order: Dictionary = {}

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


func _init(p_block: StatBlock, p_side: Combatant.Side) -> void:
	block = p_block
	side = p_side


func display_name() -> String:
	return block.display_name


func is_down() -> bool:
	return block.is_down()


func has_order() -> bool:
	return not order.is_empty()
