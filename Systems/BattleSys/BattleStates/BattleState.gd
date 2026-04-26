## Base class for all BattleManager FSM states.
## Each state receives a reference to the manager on enter() and must
## call manager.change_state("StateName") to transition.
class_name BattleState
extends Node

var manager  # BattleManager — set on enter()

func enter(m) -> void:
	manager = m

func exit() -> void:
	pass
