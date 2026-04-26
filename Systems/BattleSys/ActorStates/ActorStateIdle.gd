## Actor is alive and waiting for its turn.
## Can be targeted, can receive status effects, takes damage normally.
## Transitions to Active when the battle manager grants this actor its turn,
## or to Frozen when the frozen status is applied.
class_name BattleActorStateIdle
extends BattleActorState

func enter(a: Node3D) -> void:
	super.enter(a)

func exit() -> void:
	pass

func on_status_changed() -> void:
	if actor.has_status("frozen"):
		actor.set_actor_state("Frozen")
