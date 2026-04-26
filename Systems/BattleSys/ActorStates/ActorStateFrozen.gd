## Actor has the frozen status effect. Tempo does not accumulate.
## The actor can still be targeted and takes damage normally.
## When its turn would come up the battle manager skips it and logs the message.
## Transitions back to Idle when the frozen status expires.
class_name BattleActorStateFrozen
extends BattleActorState

func enter(a: Node3D) -> void:
	super.enter(a)

func exit() -> void:
	pass

func on_status_changed() -> void:
	if not actor.has_status("frozen"):
		actor.set_actor_state("Idle")
