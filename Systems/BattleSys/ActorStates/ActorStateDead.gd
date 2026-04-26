## Actor's hp has reached 0. Removed from all targeting lists immediately.
## The death animation coroutine plays, then the actor is freed by the manager.
## This is a terminal state — no transitions out.
class_name BattleActorStateDead
extends BattleActorState

func enter(a: Node3D) -> void:
	super.enter(a)

func exit() -> void:
	pass
