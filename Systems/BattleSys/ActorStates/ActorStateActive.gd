## Actor is the current player-controlled actor and is awaiting input.
## The reticle/UI should be open and responding to this actor.
## Transitions to Acting once the player confirms an action,
## or back to Idle if the turn is somehow cancelled (e.g. actor dies mid-turn).
class_name BattleActorStateActive
extends BattleActorState

func enter(a: Node3D) -> void:
	super.enter(a)

func exit() -> void:
	pass
