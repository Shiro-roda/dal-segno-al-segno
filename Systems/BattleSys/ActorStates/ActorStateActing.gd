## Actor is currently executing its action (animation coroutine is in flight).
## Input is locked, the actor cannot be interrupted, and damage is applied
## at the appropriate moment inside the coroutine.
## Transitions to Idle via the turn_finished signal, or to Dead if hp reaches 0
## during the action (e.g. a Martyr self-damage proc or cognitohazard recoil).
class_name BattleActorStateActing
extends BattleActorState

func enter(a: Node3D) -> void:
	super.enter(a)

func exit() -> void:
	pass
