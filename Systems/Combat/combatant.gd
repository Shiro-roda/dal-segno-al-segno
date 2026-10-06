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


func _init(p_block: StatBlock, p_side: Combatant.Side) -> void:
	block = p_block
	side = p_side


func display_name() -> String:
	return block.display_name


func is_down() -> bool:
	return block.is_down()


func has_order() -> bool:
	return not order.is_empty()
