extends Node
## Self-test for the day loop and its economy. Run day_cycle_selftest.tscn and read the output.

const RED := &"red_notes"
const GREEN := &"green_notes"
const BLUE := &"blue_notes"
const CUTS := &"cuts"

var _failures := 0
var _checks := 0


func _ready() -> void:
	_test_loop()
	_test_segno()
	_test_tithe()
	_test_colors()
	_test_blueprints()
	print("[day] %d checks, %d failures." % [_checks, _failures])
	if _failures == 0:
		print("[day] ALL PASSED")


# -------------------------------------------------------------- the loop

func _test_loop() -> void:
	var red := _enemy(&"red", EnemyTemplate.NoteColor.RED)
	var green := _enemy(&"green", EnemyTemplate.NoteColor.GREEN)
	var blue := _enemy(&"blue", EnemyTemplate.NoteColor.BLUE)

	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var hut := _tile(&"hut", TileDef.Category.VILLAGE, {}, {CUTS: 3})
	hut.color = Vector3i(20, 0, 0)
	var shrine := _tile(&"shrine", TileDef.Category.VILLAGE)
	var haunt := _tile(&"haunt", TileDef.Category.DUNGEON)
	haunt.color = Vector3i(30, 10, 50)
	haunt.enemies = [red, green, blue]
	haunt.spawn_count = 2
	haunt.loot_per_kill = {CUTS: 1}

	var config := WorldConfig.new()
	config.require_blueprints = false
	config.starting_resources = {RED: 10, GREEN: 10, BLUE: 10}
	config.tithe_base = 0
	config.tithe_per_day = 1
	config.level_per_day = 0.5
	config.main_path_bonus_per_step = 0.125  # the Segno below sits 2 steps out: +25%
	config.loop_penalty = 0.25
	config.ruin_discount = 0.5
	config.debt_per_level = 4
	config.carried_level_bonus = 1

	var persistent := WorldPersistent.new()
	var cycle := DayCycle.new(gate, config, persistent, 7)

	# ---- run setup
	cycle.begin_run()
	_expect(cycle.phase == DayCycle.Phase.PLAN and cycle.day == 1, "a run begins on day 1 in PLAN")
	_expect(cycle.stock[RED] == 10 and cycle.stock[GREEN] == 10 and cycle.stock[BLUE] == 10, "starting notes are granted")
	_expect(cycle.bass.has_tile(Vector2i.ZERO) and cycle.bass.get_tile(Vector2i.ZERO).def.is_exit, "the exit is placed at the Bass Clef origin")
	_expect(cycle.treble.has_tile(Vector2i.ZERO) and cycle.treble.get_tile(Vector2i.ZERO).def.is_origin, "the Town's origin is placed at the Treble Clef origin")

	# ---- colour costs
	_expect(cycle.cost_of(Vector2i(5, 5), haunt) == {RED: 3, GREEN: 1, BLUE: 5}, "a room's colour is its note cost (30, 10, 50 = 3, 1, 5)")
	_expect(cycle.cost_of(Vector2i(5, 5), hut) == {RED: 2}, "a village tile's colour costs notes too")
	var priced := _tile(&"priced", TileDef.Category.VILLAGE, {CUTS: 4})
	priced.color = Vector3i(140, 240, 30)
	_expect(cycle.cost_of(Vector2i(5, 5), priced) == {RED: 14, GREEN: 24, BLUE: 3, CUTS: 4}, "140, 240, 30 costs 14, 24, 3, plus any extra cost")

	# ---- planning
	_expect(not cycle.can_place(Vector2i(3, 3), haunt)["ok"], "a tile must touch a standing tile")
	_expect(not cycle.can_place(Vector2i(1, 0), gate)["ok"], "the exit cannot be built")
	_expect(cycle.place_tile(Vector2i(1, 0), haunt) and cycle.stock[RED] == 7 and cycle.stock[GREEN] == 9 and cycle.stock[BLUE] == 5,
			"placing a tile spends its colour in notes")
	_expect(not cycle.can_place(Vector2i(1, 0), haunt)["ok"], "an occupied cell is refused")
	_expect(cycle.place_tile(Vector2i(2, 0), haunt) and cycle.stock[BLUE] == 0, "a tile can touch another built tile")
	_expect(cycle.place_tile(Vector2i(0, 1), hut) and cycle.stock[RED] == 2, "village tiles place the same way")
	_expect(not cycle.can_place(Vector2i(3, 0), haunt)["ok"], "an unaffordable tile is refused")
	_expect(cycle.distance_to_exit(Vector2i(2, 0)) == 2 and cycle.distance_to_exit(Vector2i(1, 0)) == 1,
			"distance is measured in steps from the exit")

	# ---- expedition: the party spawns at the Segno, so one must be placed first
	_expect(cycle.start_expedition().is_empty() and cycle.phase == DayCycle.Phase.PLAN, "a day cannot start without a Segno")
	_expect(cycle.set_segno(Vector2i(1, -1)), "the Segno is built in an empty cell beside a standing room")
	var spawns := cycle.start_expedition()
	_expect(cycle.phase == DayCycle.Phase.EXPEDITION, "the expedition starts")
	_expect(spawns.size() == 4, "each dungeon tile gathers its remnants (got %d)" % spawns.size())
	_expect(not cycle.can_place(Vector2i(5, 5), haunt)["ok"], "no building during an expedition")
	var near: Array[Dictionary] = []
	var far: Array[Dictionary] = []
	var loot_ok := true
	for s in spawns:
		(near if s["pos"] == Vector2i(1, 0) else far).append(s)
		var template: EnemyTemplate = s["template"]
		var note_id: StringName = [RED, GREEN, BLUE][int(template.note_color) - 1]
		var is_near: bool = s["pos"] == Vector2i(1, 0)
		var loot: Dictionary = s["loot"]
		if int(loot.get(note_id, 0)) != (5 if is_near else 4) or int(loot.get(CUTS, 0)) != 1 or loot.size() != 2:
			loot_ok = false
	_expect(loot_ok, "a remnant carries notes of its own colour plus the tile's other loot; the room on the main path pays 25% more")
	_expect(near[0]["level"] == 1, "day 1 remnants have their base level")

	var expected := Vector3i(30, 10, 50)
	var expected_notes := {RED: 0, GREEN: 0, BLUE: 0}
	var expected_cuts := 0
	for s in near:
		cycle.record_kill(s["id"])
		var channel := int((s["template"] as EnemyTemplate).note_color) - 1
		expected[channel] = mini(250, expected[channel] + 5)  # 5 notes, 1 colour point each
		expected_notes[[RED, GREEN, BLUE][channel]] += 5
		expected_cuts += 1
	var room: TileInstance = cycle.bass.get_tile(Vector2i(1, 0))
	_expect(room.color == expected, "each note dropped raises the room's matching colour (got %s, want %s)" % [room.color, expected])
	_expect(cycle.record_kill(near[0]["id"]).is_empty(), "a kill counts once")
	_expect(cycle.stock[RED] == 2 and cycle.stock[GREEN] == 8, "loot is carried, not banked, until you return")
	var carried_ok := int(cycle.carried_loot.get(CUTS, 0)) == expected_cuts
	for id in expected_notes:
		carried_ok = carried_ok and int(cycle.carried_loot.get(id, 0)) == int(expected_notes[id])
	_expect(carried_ok, "carried loot adds up")
	_expect(cycle.remaining() == 2, "two remnants are left")

	var before := cycle.stock.duplicate()
	var report := cycle.return_to_exit()
	var banked_ok := true
	for id in [RED, GREEN, BLUE, CUTS]:
		banked_ok = banked_ok and int(cycle.stock.get(id, 0)) == int(before.get(id, 0)) + int(report["banked"].get(id, 0))
	_expect(banked_ok and report["left_alive"] == 2, "returning banks the loot")
	_expect(cycle.phase == DayCycle.Phase.SUMMARY and cycle.carried[Vector2i(2, 0)] == 2, "remnants left alive are remembered")

	# ---- next day: income, then the tithe, paid in cuts first
	var day2 := cycle.begin_next_day()
	_expect(cycle.day == 2 and cycle.phase == DayCycle.Phase.PLAN, "the next day begins in PLAN")
	_expect(int(day2["income"].get(CUTS, 0)) == 3 and day2["tithe_due"] == 1 and day2["shortfall"] == 0, "income arrives, then the tithe")
	_expect(day2["tithe_paid_with"] == {CUTS: 1}, "the tithe is paid in cuts first")
	_expect(cycle.stock[CUTS] == expected_cuts + 3 - 1, "cuts cover the tithe and the notes are untouched")
	_expect(cycle.level_bonus(Vector2i(2, 0)) == 1 and cycle.level_bonus(Vector2i(1, 0)) == 0, "surviving remnants make their tile stronger")
	var day2_spawns := cycle.start_expedition()
	_expect(day2_spawns.size() == 6, "surviving remnants return in addition to the usual ones (got %d)" % day2_spawns.size())
	cycle.return_to_exit()

	# ---- defeat
	cycle.begin_next_day()
	cycle.start_expedition()
	cycle.record_kill(cycle.spawns[0]["id"])
	var day_at_defeat := cycle.day
	cycle.defeat()
	_expect(cycle.phase == DayCycle.Phase.OVER and cycle.carried_loot.is_empty(), "defeat ends the run and loses carried loot")
	_expect(persistent.runs == 1 and persistent.best_day == day_at_defeat, "the run is recorded")
	_expect(persistent.ruins.size() == 1 and persistent.ruins[0]["def"] == hut, "village tiles are remembered as ruins")
	_expect(persistent.built_ids.has(&"hut") and persistent.built_ids.has(&"haunt"), "built tile ids are remembered")

	# ---- the next run
	cycle.begin_run()
	_expect(cycle.day == 1 and cycle.debt == 0 and cycle.stock[RED] == 10, "a new run resets day, debt and stock")
	_expect(not cycle.bass.has_tile(Vector2i(1, 0)) and not cycle.bass.has_tile(Vector2i(2, 0)), "the dungeon is wiped")
	_expect(not cycle.has_segno(), "the Segno is cleared with the dungeon")
	var ruin: TileInstance = cycle.treble.get_tile(Vector2i(0, 1))
	_expect(ruin != null and ruin.ruined, "the town comes back as ruins")
	_expect(cycle.treble.get_tile(Vector2i.ZERO).def.is_origin and not cycle.treble.get_tile(Vector2i.ZERO).ruined, "the Town's origin is never a ruin")
	_expect(not ruin.is_live(), "ruins are not part of the standing network")
	_expect(not cycle.can_place(Vector2i(0, 1), shrine)["ok"], "ruins can only be rebuilt as what they were")
	_expect(cycle.can_erase(Vector2i(0, 1), TileDef.Clef.TREBLE)["ok"], "a ruin can be cleared to build something else")
	_expect(cycle.cost_of(Vector2i(0, 1), hut) == {RED: 1}, "rebuilding ruins is discounted")
	_expect(cycle.place_tile(Vector2i(0, 1), hut) and cycle.stock[RED] == 9, "ruins can be rebuilt")
	_expect(not cycle.treble.get_tile(Vector2i(0, 1)).ruined, "a rebuilt tile stands again")


# ------------------------------------------------------------------ segno

func _test_segno() -> void:
	var red := _enemy(&"red", EnemyTemplate.NoteColor.RED)
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	# A free room whose red enemy drops 4 notes, so multipliers show up as whole numbers.
	var room := _tile(&"room", TileDef.Category.DUNGEON)
	room.enemies = [red]
	room.spawn_count = 1

	var config := WorldConfig.new()
	config.require_blueprints = false
	config.starting_resources = {RED: 100, GREEN: 100, BLUE: 100}
	config.main_path_bonus_per_step = 0.25
	config.loop_penalty = 0.25
	config.erase_any_tile = true

	# ---- a straight corridor: exit - (1,0) - (2,0), and the Segno room at (3,0)
	var cycle := DayCycle.new(gate, config, WorldPersistent.new(), 21)
	cycle.begin_run()
	for x in [1, 2]:
		cycle.place_tile(Vector2i(x, 0), room)
	_expect(not cycle.has_segno() and cycle.spawn_cell() == Vector2i.ZERO, "with no Segno the spawn falls back to the exit")
	_expect(not cycle.can_start_expedition()["ok"], "a day cannot start without a Segno")
	_expect(not cycle.set_segno(Vector2i(9, 9)), "the Segno must touch a standing room")
	_expect(not cycle.set_segno(Vector2i.ZERO), "the Segno cannot go on the exit")
	_expect(not cycle.set_segno(Vector2i(2, 0)), "the Segno is a room of its own, never put on top of another")
	_expect(not cycle.can_place(Vector2i(3, 0), cycle.segno_def)["ok"], "the Segno room is not built like other tiles")
	var stock_before := cycle.stock.duplicate()
	_expect(cycle.set_segno(Vector2i(3, 0)) and cycle.spawn_cell() == Vector2i(3, 0), "the Segno becomes the spawn")
	_expect(cycle.stock == stock_before, "the Segno room costs nothing")
	_expect(cycle.bass.get_tile(Vector2i(3, 0)).def.is_segno and cycle.bass.get_tile(Vector2i(2, 0)).def == room,
			"the Segno is its own room beside the old one")
	var info := cycle.main_path()
	_expect(bool(info["found"]) and int(info["steps"]) == 3 and int(info["loops"]) == 0, "a corridor's main path is its whole length, no loops (steps %d)" % int(info["steps"]))
	_expect(is_equal_approx(float(info["bonus"]), 0.75), "the bonus grows with path length (3 steps x 0.25)")
	_expect(is_equal_approx(cycle.loot_multiplier(Vector2i(2, 0)), 1.75), "rooms on the main path pay the bonus")
	_expect(cycle.can_start_expedition()["ok"], "a day can start once the Segno connects to the exit")
	var start_spawns := cycle.start_expedition()
	_expect(start_spawns.size() == 2, "the Segno room gathers no remnants")
	var loot: Dictionary = start_spawns[0]["loot"]
	_expect(int(loot.get(RED, 0)) == 7, "loot is scaled by the main-path bonus (4 x 1.75 = 7, got %s)" % str(loot))
	cycle.return_to_exit()
	cycle.begin_next_day()

	# ---- moving the Segno takes the old room away; it can't lean on the room it is leaving
	_expect(cycle.set_segno(Vector2i(2, 1)) and cycle.segno == Vector2i(2, 1), "the Segno can be moved")
	_expect(not cycle.bass.has_tile(Vector2i(3, 0)), "the old Segno room is gone")
	_expect(not cycle.set_segno(Vector2i(2, 2)), "the Segno can't move to a cell that touches only its old room")

	# ---- erasing the Segno room picks it up
	_expect(cycle.erase_tile(Vector2i(2, 1)) and not cycle.has_segno() and not cycle.bass.has_tile(Vector2i(2, 1)),
			"erasing the Segno room clears the Segno")
	_expect(cycle.set_segno(Vector2i(3, 0)), "and it can be put down again")
	cycle.clear_segno()
	_expect(not cycle.has_segno() and not cycle.bass.has_tile(Vector2i(3, 0)), "clear_segno removes the room")

	# ---- a 2x2 block gives the main path a loop
	var block := DayCycle.new(gate, config, WorldPersistent.new(), 22)
	block.begin_run()
	for cell in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)]:
		block.place_tile(cell, room)
	block.set_segno(Vector2i(3, 0))
	var loop_info := block.main_path()
	_expect(int(loop_info["steps"]) == 5 and int(loop_info["loops"]) == 1,
			"the longest path winds round the block and the shortcut is a loop (steps %d, loops %d)" % [int(loop_info["steps"]), int(loop_info["loops"])])
	_expect(is_equal_approx(float(loop_info["bonus"]), 1.0), "each loop takes the penalty off the bonus (5 x 0.25 - 0.25)")

	# ---- the rule can be switched off
	config.require_segno = false
	var free := DayCycle.new(gate, config, WorldPersistent.new(), 23)
	free.begin_run()
	_expect(free.can_start_expedition()["ok"] and free.spawn_cell() == Vector2i.ZERO, "require_segno = false spawns the party at the exit")


# ------------------------------------------------------------------ tithe

func _test_tithe() -> void:
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var config := WorldConfig.new()
	config.require_blueprints = false
	config.starting_resources = {}
	config.require_segno = false  # these checks are about the tithe, not the spawn
	config.tithe_base = 0
	config.tithe_per_day = 10
	config.debt_per_level = 4
	var cycle := DayCycle.new(gate, config, WorldPersistent.new(), 5)
	cycle.begin_run()

	# Cuts first, then each note colour in order.
	cycle.start_expedition()
	cycle.return_to_exit()
	cycle.stock = {CUTS: 2, RED: 1, GREEN: 4, BLUE: 100}
	_expect(cycle.tithe_tonight() == 10, "tonight's tithe is the next day's amount")
	var preview := cycle.tithe_preview()
	_expect(preview["paid"] == {CUTS: 2, RED: 1, GREEN: 4, BLUE: 3} and preview["shortfall"] == 0,
			"the tithe is paid in cuts, then red, green and blue notes")
	_expect(cycle.stock[BLUE] == 100, "a preview takes nothing")
	var day2 := cycle.begin_next_day()
	_expect(day2["tithe_paid_with"] == {CUTS: 2, RED: 1, GREEN: 4, BLUE: 3} and cycle.stock[BLUE] == 97 and cycle.stock[CUTS] == 0,
			"paying takes exactly that from stock")

	# Notes first.
	cycle.start_expedition()
	cycle.return_to_exit()
	cycle.stock = {CUTS: 50, RED: 5, GREEN: 5, BLUE: 5}
	_expect(cycle.tithe_preview()["paid"] == {CUTS: 20}, "cuts alone cover the tithe when they can")
	cycle.tithe_notes_first = true
	_expect(cycle.tithe_preview()["paid"] == {RED: 5, GREEN: 5, BLUE: 5, CUTS: 5}, "notes first spends every note colour before cuts")
	var day3 := cycle.begin_next_day()
	_expect(day3["shortfall"] == 0 and cycle.stock[CUTS] == 45 and cycle.stock[RED] == 0, "the chosen order is the one used")

	# Unpaid tithe becomes debt.
	cycle.start_expedition()
	cycle.return_to_exit()
	cycle.stock = {CUTS: 3}
	var day4 := cycle.begin_next_day()
	_expect(day4["tithe_paid"] == 3 and day4["shortfall"] == 27 and cycle.debt == 27, "what can't be paid becomes debt")

	# A config with no cuts in its order never touches them.
	config.tithe_order = [RED, GREEN, BLUE]
	cycle.tithe_notes_first = false
	cycle.stock = {CUTS: 99, RED: 2}
	_expect(cycle.tithe_preview(10)["paid"] == {RED: 2} and cycle.tithe_preview(10)["shortfall"] == 8,
			"a resource left out of tithe_order is never taken")


# ----------------------------------------------------------- room colours

func _test_colors() -> void:
	var red := _enemy(&"red", EnemyTemplate.NoteColor.RED)
	var green := _enemy(&"green", EnemyTemplate.NoteColor.GREEN)
	var blue := _enemy(&"blue", EnemyTemplate.NoteColor.BLUE)
	var neutral := _enemy(&"neutral", EnemyTemplate.NoteColor.NONE)
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true

	var config := WorldConfig.new()
	config.require_blueprints = false
	config.starting_resources = {RED: 10000, GREEN: 10000, BLUE: 10000}
	config.require_segno = false  # these checks are about room colours, not the spawn
	config.affinity_multiplier = 4.0

	# Enemies of the room's lowest colour are the most likely.
	var crowd := _tile(&"crowd", TileDef.Category.DUNGEON)
	crowd.color = Vector3i(200, 20, 200)
	crowd.enemies = [red, green, blue]
	crowd.spawn_count = 300
	var cycle := DayCycle.new(gate, config, WorldPersistent.new(), 3)
	cycle.begin_run()
	cycle.place_tile(Vector2i(1, 0), crowd)
	var counts := _count_colors(cycle.start_expedition())
	_expect(counts[2] > 165 and counts[1] < 90 and counts[3] < 90,
			"a room low in green gathers mostly green enemies (red %d, green %d, blue %d of 300)" % [counts[1], counts[2], counts[3]])

	# Tied lowest channels are all favoured, equally.
	var flat := _tile(&"flat", TileDef.Category.DUNGEON)
	flat.color = Vector3i(50, 50, 50)
	flat.enemies = [red, green, blue]
	flat.spawn_count = 300
	var cycle_flat := DayCycle.new(gate, config, WorldPersistent.new(), 4)
	cycle_flat.begin_run()
	cycle_flat.place_tile(Vector2i(1, 0), flat)
	counts = _count_colors(cycle_flat.start_expedition())
	_expect(counts[1] > 60 and counts[1] < 140 and counts[2] > 60 and counts[2] < 140 and counts[3] > 60 and counts[3] < 140,
			"equal channels give an even mix (red %d, green %d, blue %d of 300)" % [counts[1], counts[2], counts[3]])

	# An uncoloured enemy drops its own quantity of notes, each a random colour. An enemy
	# whose notes_per_kill is 0 drops none.
	var mix := _tile(&"mix", TileDef.Category.DUNGEON)
	mix.color = Vector3i(10, 90, 90)
	mix.enemies = [neutral]
	mix.spawn_count = 1
	var plain := _tile(&"plain", TileDef.Category.DUNGEON)
	plain.enemies = [_enemy(&"dud", EnemyTemplate.NoteColor.RED, 0)]
	plain.spawn_count = 1
	var cycle_mix := DayCycle.new(gate, config, WorldPersistent.new(), 5)
	cycle_mix.begin_run()
	cycle_mix.place_tile(Vector2i(1, 0), mix)
	cycle_mix.place_tile(Vector2i(0, 1), plain)
	var loot_by_pos := {}
	for s in cycle_mix.start_expedition():
		loot_by_pos[s["pos"]] = s["loot"]
	var mixed_loot: Dictionary = loot_by_pos[Vector2i(1, 0)]
	var only_notes := true
	for key in mixed_loot:
		if not [RED, GREEN, BLUE].has(key):
			only_notes = false
	_expect(only_notes and _note_total(mixed_loot) == 4, "an uncoloured enemy drops its own notes_per_kill in notes (got %s)" % str(mixed_loot))
	_expect(loot_by_pos[Vector2i(0, 1)] == {}, "an enemy whose notes_per_kill is 0 drops no notes")

	# Over many kills the notes come out in all three colours, evenly, whatever the room's
	# own colours are (this room is nearly empty of red, which must not bias them).
	var swarm := _tile(&"swarm", TileDef.Category.DUNGEON)
	swarm.color = Vector3i(10, 200, 200)
	swarm.enemies = [neutral]
	swarm.spawn_count = 100
	var cycle_swarm := DayCycle.new(gate, config, WorldPersistent.new(), 8)
	cycle_swarm.begin_run()
	cycle_swarm.place_tile(Vector2i(1, 0), swarm)
	var totals := {RED: 0, GREEN: 0, BLUE: 0}
	for s in cycle_swarm.start_expedition():
		for key in s["loot"]:
			totals[key] += int(s["loot"][key])
	var all_notes := int(totals[RED]) + int(totals[GREEN]) + int(totals[BLUE])
	var even := true
	for id in totals:
		even = even and int(totals[id]) > 80 and int(totals[id]) < 190
	_expect(all_notes == 400 and even, "an uncoloured enemy's notes are an even mix of colours (red %d, green %d, blue %d of 400)" % [totals[RED], totals[GREEN], totals[BLUE]])

	# The enemy sets the quantity; the room only multiplies it.
	var scaled := _tile(&"scaled", TileDef.Category.DUNGEON)
	_expect(cycle_mix.notes_dropped(scaled, neutral) == 4, "a note multiplier of 1 leaves the enemy's quantity alone")
	scaled.note_multiplier = 1.5
	_expect(cycle_mix.notes_dropped(scaled, neutral) == 6, "a multiplier of 1.5 turns 4 notes into 6")
	scaled.note_multiplier = 0.5
	_expect(cycle_mix.notes_dropped(scaled, neutral) == 2, "a multiplier of 0.5 turns 4 notes into 2")
	scaled.note_multiplier = 0.1
	_expect(cycle_mix.notes_dropped(scaled, neutral) == 1, "a small multiplier never rounds a drop down to nothing")
	scaled.note_multiplier = 0.0
	_expect(cycle_mix.notes_dropped(scaled, neutral) == 0, "a multiplier of 0 drops no notes")
	scaled.note_multiplier = 1.0
	_expect(cycle_mix.notes_dropped(scaled, neutral, 1.25) == 5, "the main-path bonus stacks with the room's multiplier")
	_expect(cycle_mix.notes_dropped(scaled, _enemy(&"big", EnemyTemplate.NoteColor.NONE, 10)) == 10, "each enemy sets its own quantity")
	_expect(cycle_mix.notes_dropped(scaled, _enemy(&"dud", EnemyTemplate.NoteColor.NONE, 0)) == 0, "an enemy can drop nothing")
	var rich := _tile(&"rich", TileDef.Category.DUNGEON)
	rich.enemies = [red]
	rich.spawn_count = 1
	rich.note_multiplier = 2.0
	var cycle_rich := DayCycle.new(gate, config, WorldPersistent.new(), 9)
	cycle_rich.begin_run()
	cycle_rich.place_tile(Vector2i(1, 0), rich)
	_expect(cycle_rich.start_expedition()[0]["loot"] == {RED: 8}, "a room with a multiplier of 2 doubles a red enemy's 4 notes")

	# A room whose channels all reach 250 is spent and must be erased.
	var edge := _tile(&"edge", TileDef.Category.DUNGEON)
	edge.color = Vector3i(250, 250, 249)
	edge.enemies = [_enemy(&"blue_one", EnemyTemplate.NoteColor.BLUE, 1)]
	edge.spawn_count = 1
	var cycle_edge := DayCycle.new(gate, config, WorldPersistent.new(), 6)
	cycle_edge.begin_run()
	cycle_edge.place_tile(Vector2i(1, 0), edge)
	var steady := _tile(&"steady", TileDef.Category.DUNGEON)
	steady.color = Vector3i(50, 50, 50)
	cycle_edge.place_tile(Vector2i(0, 1), steady)
	var spent: TileInstance = cycle_edge.bass.get_tile(Vector2i(1, 0))
	var edge_spawns := cycle_edge.start_expedition()
	_expect(not spent.is_depleted() and cycle_edge.distance_to_exit(Vector2i(1, 0)) == 1, "a room one step short of full still works")
	cycle_edge.record_kill(edge_spawns[0]["id"])
	_expect(spent.color == Vector3i(250, 250, 250) and spent.is_depleted(), "a channel stops at 250 and the room is spent")
	_expect(cycle_edge.distance_to_exit(Vector2i(1, 0)) == -1, "a spent room no longer connects anything")
	cycle_edge.return_to_exit()
	cycle_edge.begin_next_day()
	_expect(not cycle_edge.open_slots().has(Vector2i(1, 0)), "a spent room is not an open slot")
	_expect(not cycle_edge.can_place(Vector2i(1, 0), edge)["ok"], "nothing can be built on a spent room")
	_expect(cycle_edge.can_erase(Vector2i(1, 0))["ok"], "a spent room can be erased")
	_expect(not cycle_edge.can_erase(Vector2i(0, 1))["ok"], "a working room can't be erased by default")
	_expect(not cycle_edge.can_erase(Vector2i.ZERO)["ok"], "the exit can't be erased")
	_expect(cycle_edge.start_expedition().is_empty(), "a spent room gathers no remnants")
	cycle_edge.return_to_exit()
	cycle_edge.begin_next_day()
	_expect(cycle_edge.erase_tile(Vector2i(1, 0)) and not cycle_edge.bass.has_tile(Vector2i(1, 0)), "erasing clears the cell")
	_expect(cycle_edge.open_slots().has(Vector2i(1, 0)), "and the cell is open again")
	config.erase_any_tile = true
	_expect(cycle_edge.can_erase(Vector2i(0, 1))["ok"], "erase_any_tile lets any tile be erased")


# -------------------------------------------------------------- blueprints

func _test_blueprints() -> void:
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var hut := _tile(&"hut", TileDef.Category.VILLAGE, {&"notes": 2})
	var common := _tile(&"common", TileDef.Category.DUNGEON, {&"notes": 1})
	var never := _tile(&"never", TileDef.Category.DUNGEON, {&"notes": 1})
	never.blueprint_weight = 0.0
	var late := _tile(&"late", TileDef.Category.DUNGEON, {&"notes": 1})
	late.blueprint_min_day = 3

	var config := WorldConfig.new()
	config.starting_resources = {&"notes": 50}
	config.require_segno = false  # these checks are about blueprints, not the spawn
	config.blueprints_per_day = 3
	var cycle := DayCycle.new(gate, config, WorldPersistent.new(), 11)
	cycle.blueprint_pool = [common, never, late, hut, gate]

	cycle.begin_run()
	_expect(cycle.blueprints.size() == 3, "a hand of blueprints is drawn each day")
	_expect(cycle.blueprints.all(func(d: TileDef) -> bool: return d == common),
			"weight 0, tiles from a later day, village tiles and the exit are never drawn")
	_expect(cycle.stock[&"notes"] == 50, "drawing blueprints costs nothing")

	_expect(cycle.place_tile(Vector2i(0, 1), hut) and cycle.stock[&"notes"] == 48,
			"a village tile needs no blueprint")
	_expect(not cycle.can_place(Vector2i(1, 0), never)["ok"], "a dungeon tile with no blueprint is refused")
	_expect(cycle.place_tile(Vector2i(1, 0), common) and cycle.blueprints.size() == 2
			and cycle.stock[&"notes"] == 47, "placing from a blueprint spends the card and the cost")
	_expect(cycle.place_tile(Vector2i(2, 0), common) and cycle.place_tile(Vector2i(1, -1), common),
			"each copy in the hand is one placement")
	var refusal := cycle.can_place(Vector2i(2, 1), common)
	_expect(not refusal["ok"] and String(refusal["reason"]).contains("blueprint"), "with the hand spent, no more")

	var slots := cycle.open_slots()
	_expect(slots.has(Vector2i(3, 0)) and not slots.has(Vector2i(1, 0)) and not slots.has(Vector2i(3, 3)),
			"open_slots lists empty cells beside standing tiles")

	# Unspent blueprints expire and a fresh hand is drawn.
	cycle.start_expedition()
	cycle.return_to_exit()
	cycle.begin_next_day()
	_expect(cycle.day == 2 and cycle.blueprints.size() == 3, "a new day draws a new hand")

	# Rarity gating by day.
	var seen_late_early := false
	var seen_late_later := false
	for _i in 40:
		cycle.day = 2
		cycle.draw_blueprints()
		seen_late_early = seen_late_early or cycle.blueprints.has(late)
		cycle.day = 3
		cycle.draw_blueprints()
		seen_late_later = seen_late_later or cycle.blueprints.has(late)
	_expect(not seen_late_early, "a tile is never offered before its blueprint_min_day")
	_expect(seen_late_later, "and becomes available on that day")

	# Repeat penalty spreads the hand across different tiles.
	var other := _tile(&"other", TileDef.Category.DUNGEON)
	config.blueprints_per_day = 2
	config.blueprint_repeat_penalty = 1000.0
	cycle.blueprint_pool = [common, other]
	var mixed := 0
	for _i in 30:
		cycle.draw_blueprints()
		if cycle.blueprints.has(common) and cycle.blueprints.has(other):
			mixed += 1
	_expect(mixed >= 28, "copies already drawn make repeats unlikely (%d of 30 hands mixed)" % mixed)

	# With the rule switched off there is no hand and nothing is gated.
	config.require_blueprints = false
	cycle.draw_blueprints()
	_expect(cycle.blueprints.is_empty() and not cycle.needs_blueprint(common),
			"require_blueprints = false turns the whole rule off")


# ---------------------------------------------------------------- helpers

func _count_colors(spawns: Array[Dictionary]) -> Dictionary:
	var counts := {1: 0, 2: 0, 3: 0}
	for s in spawns:
		counts[int((s["template"] as EnemyTemplate).note_color)] += 1
	return counts


func _enemy(id: StringName, note_color: EnemyTemplate.NoteColor, notes := 4) -> EnemyTemplate:
	var template := EnemyTemplate.new()
	template.display_name = String(id)
	template.level = 1
	template.note_color = note_color
	template.notes_per_kill = notes
	return template


## Notes of every colour in a loot dictionary, ignoring cuts and the like.
func _note_total(loot: Dictionary) -> int:
	var total := 0
	for id in [RED, GREEN, BLUE]:
		total += int(loot.get(id, 0))
	return total


func _tile(id: StringName, category: TileDef.Category, cost: Dictionary = {}, income: Dictionary = {}) -> TileDef:
	var def := TileDef.new()
	def.id = id
	def.display_name = String(id)
	def.category = category
	def.cost = cost
	def.income = income
	return def


func _expect(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		return
	_failures += 1
	push_error("[day] FAIL: " + message)
	print("[day] FAIL: ", message)
