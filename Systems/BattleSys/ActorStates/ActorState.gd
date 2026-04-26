## Base class for all BattleActor FSM states.
class_name BattleActorState
extends RefCounted

var actor: Node3D

func enter(a: Node3D) -> void:
	actor = a

func exit() -> void:
	pass

func on_status_changed() -> void:
	pass
