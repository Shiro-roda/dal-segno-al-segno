extends Node
## Checks the plan screen against a real DayCycle, using tiles built in code so it
## needs no authored data. Run this scene (F6) and look for "ALL PASSED". The screen
## is left open afterwards so you can look at it.

var _failures := 0
var _checks := 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		return
	_failures += 1
	print("[plan] FAIL: ", what)


func _ready() -> void:
	var config := WorldConfig.new()

	var exit := TileDef.new()
	exit.id = &"exit"
	exit.display_name = "Exit"
	exit.is_exit = true
	exit.category = TileDef.Category.VILLAGE

	# Colour 30 20 10 costs 3 red, 2 green and 1 blue notes.
	var hub := TileDef.new()
	hub.id = &"hub_a"
	hub.display_name = "Hub A"
	hub.category = TileDef.Category.VILLAGE
	hub.color = Vector3i(30, 20, 10)
	hub.income = {&"cuts": 2}

	# Colour 50 40 20 costs 5 red, 4 green and 2 blue notes.
	var dungeon := TileDef.new()
	dungeon.id = &"dungeon_a"
	dungeon.display_name = "Dungeon A"
	dungeon.category = TileDef.Category.DUNGEON
	dungeon.color = Vector3i(50, 40, 20)
	dungeon.enemies = [EnemyTemplate.new()]
	dungeon.spawn_count = 2
	dungeon.notes_per_kill = 3

	var day := DayCycle.new(exit, config, WorldPersistent.new(), 7)
	day.blueprint_pool = [dungeon]
	day.begin_run()
	_expect(day.blueprints.size() == config.blueprints_per_day, "a hand of blueprints is drawn")

	var screen := PlanScreen.new()
	add_child(screen)
	screen.open(day, [hub])
	_expect(screen.is_open(), "the screen is open while planning")
	_expect(screen._grid.get_child_count() == 9, "the grid covers the exit and its four slots (got %d)" \
			% screen._grid.get_child_count())

	# --- Hub tile: placed with notes, paid from stock ------------------------------
	screen.choose_def(hub)
	screen.click_cell(Vector2i(1, 0))
	_expect(day.grid.has(Vector2i(1, 0)), "a hub tile is placed on an open slot")
	_expect(int(day.stock[&"red_notes"]) == 7, "the hub's colour is paid in notes (red %d)" \
			% int(day.stock[&"red_notes"]))
	screen.click_cell(Vector2i(1, 0))
	_expect(day.grid.size() == 2, "an occupied cell can't be built on again")
	screen.click_cell(Vector2i(5, 5))
	_expect(day.grid.size() == 2 and screen._status.text == "Must touch a standing tile.",
			"a cell away from the village is refused with a reason")

	# --- Dungeon tile: needs a blueprint, spends one card --------------------------
	screen.choose_def(dungeon)
	_expect(screen._selected == dungeon, "a blueprint can be chosen")
	screen.click_cell(Vector2i(0, 1))
	_expect(day.grid.has(Vector2i(0, 1)), "a dungeon tile is placed from a blueprint")
	_expect(day.blueprints.size() == config.blueprints_per_day - 1, "placing spends one blueprint card")
	_expect(screen._dungeon_count.text.contains("Dungeon tiles: 1")
			and screen._dungeon_count.text.contains("Remnants: 2"), "the dungeon summary counts tiles and remnants")
	screen.click_cell(Vector2i(0, -1))
	_expect(not day.grid.has(Vector2i(0, -1)) and screen._status.text == "Cannot afford it.",
			"a tile that can't be paid for is refused")
	_expect(day.blueprints.size() == config.blueprints_per_day - 1, "a refused placement keeps the card")

	# --- Erasing: only spent rooms unless the config allows more -------------------
	screen.set_erase(true)
	screen.click_cell(Vector2i(0, 1))
	_expect(day.grid.has(Vector2i(0, 1)) and screen._status.text == "Only a spent room can be erased.",
			"a room that isn't spent can't be erased")
	day.config.erase_any_tile = true
	screen.click_cell(Vector2i(0, 1))
	_expect(not day.grid.has(Vector2i(0, 1)), "erase works once the config allows it")
	screen.set_erase(false)

	# --- Tithe -----------------------------------------------------------------------
	_expect(screen._tithe.text.contains("Tithe tonight: 1"), "the tithe for tonight is shown")
	screen.set_notes_first(true)
	_expect(day.tithe_notes_first, "the notes-first switch reaches the day cycle")
	_expect(screen._tithe.text.contains("Pays: "), "the tithe preview shows what would be paid")

	# --- Starting, and coming back ---------------------------------------------------
	var requested := [0]
	screen.expedition_requested.connect(func(): requested[0] += 1)
	screen.request_expedition()
	_expect(requested[0] == 1, "the start button asks for an expedition")
	day.start_expedition()
	_expect(not screen.is_open(), "the screen closes during the expedition")
	var report := day.return_to_exit()
	var next_day := day.begin_next_day()
	_expect(screen.is_open() and screen._title.text == "Day 2", "the screen reopens on the next day")
	screen.show_report(report, next_day)
	_expect(screen._report.visible and screen._report.text.contains("Banked"), "the report is shown")

	print("[plan] %d checks, %d failures." % [_checks, _failures])
	print("[plan] ALL PASSED" if _failures == 0 else "[plan] SOME FAILED")
