extends BattleState

func enter(manager):
	super.enter(manager)

	battle_manager.ui.show_player_actions()
