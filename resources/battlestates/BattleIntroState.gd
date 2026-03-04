extends BattleState


func enter(manager):
	super.enter(manager)
	print("Battle Start")
	battle_manager.start_battle()
