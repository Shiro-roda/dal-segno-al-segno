## BattleStateIntro
## Plays the encounter's intro splash and intro dialogue, then hands off
## to BattleStateTurn.  All pre-battle sequencing lives here so that
## BattleStateTurn can assume actors are spawned and the field is ready.
extends BattleState

func enter(m) -> void:
	super.enter(m)
	# Use call_deferred so enter() returns before the coroutine starts,
	# preventing re-entrant change_state calls.
	call_deferred("_run_intro")

func _run_intro() -> void:
	var ctx = manager.context

	var has_splash : bool = ctx.encounter.intro_splash != null \
		and not ctx.encounter.intro_splash.is_empty()
	var has_dialogue : bool = ctx.encounter.intro_dialogue != null

	if has_splash or has_dialogue:
		var bui = manager.get_node_or_null("../BattleUI")
		if bui:
			bui.hide()

		if has_splash:
			var splash := BattleIntroSplash.new()
			manager.add_child(splash)
			await splash.play(ctx.encounter.intro_splash, ctx.run_state)
			splash.queue_free()

		if has_dialogue:
			await manager.dialogue_box.play_lines(
				ctx.encounter.intro_dialogue, ctx.run_state)

		if bui:
			bui.show()

	manager.change_state("BattleTurn")
