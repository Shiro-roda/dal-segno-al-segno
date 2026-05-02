## BattleStateTurn
## The main combat loop.  Drives next_turn() and runs until check_victory()
## triggers end_battle(), at which point the manager transitions to BattleStateEnd.
## This state also re-enables the reticle UI at the start of each player turn.
extends BattleState

func enter(m) -> void:
	super.enter(m)
	call_deferred("_start_turn_loop")

func _start_turn_loop() -> void:
	# Both CTB and ATB are now driven by _tick_tempo() in _process.
	# Park cameras on overview and let the real-time system take over.
	manager._return_camera_to_overview()

func exit() -> void:
	pass
