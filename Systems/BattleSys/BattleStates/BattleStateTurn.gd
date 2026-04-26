## BattleStateTurn
## The main combat loop.  Drives next_turn() and runs until check_victory()
## triggers end_battle(), at which point the manager transitions to BattleStateEnd.
## This state also re-enables the reticle UI at the start of each player turn.
extends BattleState

func enter(m) -> void:
	super.enter(m)
	call_deferred("_start_turn_loop")

func _start_turn_loop() -> void:
	# Release both cameras from the overview anchor so turn-based
	# focus_actor / focus_idle_orbit calls can take over normally.
	manager.focus_idle_orbit()
	manager.next_turn()

func exit() -> void:
	pass
