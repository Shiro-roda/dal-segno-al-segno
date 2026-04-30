## BattleStateTurn
## The main combat loop.  Drives next_turn() and runs until check_victory()
## triggers end_battle(), at which point the manager transitions to BattleStateEnd.
## This state also re-enables the reticle UI at the start of each player turn.
extends BattleState

func enter(m) -> void:
	super.enter(m)
	call_deferred("_start_turn_loop")

func _start_turn_loop() -> void:
	if BattleSettings.battle_mode == BattleSettings.BattleMode.ATB:
		# ATB: _tick_atb() in _process drives all turns.
		# Just park cameras on overview and let the real-time system take over.
		manager._return_camera_to_overview()
	else:
		# CTB: release cameras and run the sequential turn loop.
		manager.focus_idle_orbit()
		manager.next_turn()

func exit() -> void:
	pass
