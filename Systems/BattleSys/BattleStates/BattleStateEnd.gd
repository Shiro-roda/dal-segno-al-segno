## BattleStateEnd
## Terminal state. Entered by end_battle() immediately after setting battle_ending = true.
## All cleanup work (reticle, resources, exp, signal) remains in end_battle() in the manager.
## This state exists as a clean hook for future post-battle sequencing
## (cutscenes, loot reveals, results screens) that needs an identifiable state to branch on.
## No transitions out — battle_ending = false is cleared by end_battle() before it finishes.
extends BattleState

func enter(m) -> void:
	super.enter(m)
	# end_battle() is already running (it called change_state to get here).
	# Nothing to do — this state is a marker for external systems to query.

func exit() -> void:
	pass
