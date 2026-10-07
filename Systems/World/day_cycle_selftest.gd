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
	var haunt := _tile(&"haunt", TileDef.Category.DUNGEON)
	haunt.color = Vector3i(30, 10, 50)
	haunt.enemies = [red, green, blue]
	haunt.spawn_count = 2
	haunt.notes_per_kill = 4
	haunt.loot_per_kill = {CUTS: 1}

	var config := WorldConfig.new()
	config.require_blueprints = false
	config.starting_resources = {RED: 10, GREEN: 10, BLUE: 10}
	config.tithe_base = 0
	config.tithe_per_day = 1
	config.level_per_day = 0.5
	config.loot_distance_bonus = 0.25
	config.ruin_discount = 0.5
	config.debt_per_level = 4
	config.carried_level_bonus = 1

	var persistent := WorldPersistent.new()
	var cycle := DayCycle.new(gate, config, persistent, 7)

	# ---- run setup
	cycle.begin_run()
	_expect(cycle.phase == DayCycle.Phase.PLAN and cycle.day == 1, "a run begins on day 1 in PLAN")
	_expect(cycle.stock[RED] == 10 and cycle.stock[GREEN] == 10 and cycle.stock[BLUE] == 10, "starting notes are granted")
	_expect(cycle.grid.has(Vector2i.ZERO) and cycle.grid[Vector2i.ZERO].def.is_exit, "the exit is placed at the origin")

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

	# ---- expedition
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
		if int(loot.get(note_id, 0)) != (5 if is_near else 6) or int(loot.get(CUTS, 0)) != (1 if is_near else 2) or loot.size() != 2:
			loot_ok = false
	_expect(loot_ok, "a remnant carries notes of its own colour, scaled by distance, plus the tile's other loot")
	_expect(near[0]["level"] == 1, "day 1 remnants have their base level")

	var expected := Vector3i(30, 10, 50)
	var expected_notes := {RED: 0, GREEN: 0, BLUE: 0}
	var expected_cuts := 0
	for s in near:
		cycle.record_kill(s["id"])
		var channel := int((s["template"] as EnemyTemplate).note_color) - 1
		expected[channel] = mini(250, expected[channel] + 50)
		expected_notes[[RED, GREEN, BLUE][channel]] += 5
		expected_cuts += 1
	var room: TileInstance = cycle.grid[Vector2i(1, 0)]
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
	_expect(not cycle.grid.has(Vector2i(1, 0)) and not cycle.grid.has(Vector2i(2, 0)), "the dungeon is wiped")
	var ruin: TileInstance = cycle.grid.get(Vector2i(0, 1))
	_expect(ruin != null and ruin.ruined, "the village comes back as ruins")
	_expect(cycle.distance_to_exit(Vector2i(0, 1)) == -1, "ruins are not part of the standing network")
	_expect(not cycle.can_place(Vector2i(0, 1), haunt)["ok"], "ruins can only be rebuilt as what they were")
	_expect(cycle.cost_of(Vector2i(0, 1), hut) == {RED: 1}, "rebuilding ruins is discounted")
	_expect(cycle.place_tile(Vector2i(0, 1), hut) and cycle.stock[RED] == 9, "ruins can be rebuilt")
	_expect(not (cycle.grid[Vector2i(0, 1)] as TileInstance).ruined, "a rebuilt tile stands again")


# ------------------------------------------------------------------ tithe

func _test_tithe() -> void:
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var config := WorldConfig.new()
	config.require_blueprints = false
	config.starting_resources = {}
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

	# A neutral enemy drops the room's lowest colour; no notes_per_kill drops no notes.
	var mix := _tile(&"mix", TileDef.Category.DUNGEON)
	mix.color = Vector3i(10, 90, 90)
	mix.enemies = [neutral]
	mix.spawn_count = 1
	mix.notes_per_kill = 4
	var plain := _tile(&"plain", TileDef.Category.DUNGEON)
	plain.enemies = [red]
	plain.spawn_count = 1
	var cycle_mix := DayCycle.new(gate, config, WorldPersistent.new(), 5)
	cycle_mix.begin_run()
	cycle_mix.place_tile(Vector2i(1, 0), mix)
	cycle_mix.place_tile(Vector2i(0, 1), plain)
	var loot_by_pos := {}
	for s in cycle_mix.start_expedition():
		loot_by_pos[s["pos"]] = s["loot"]
	_expect(loot_by_pos[Vector2i(1, 0)] == {RED: 5}, "a neutral enemy drops the room's lowest colour")
	_expect(loot_by_pos[Vector2i(0, 1)] == {}, "a tile with no notes_per_kill drops no notes")

	# A room whose channels all reach 250 is spent and must be erased.
	var edge := _tile(&"edge", TileDef.Category.DUNGEON)
	edge.color = Vector3i(250, 250, 245)
	edge.enemies = [blue]
	edge.spawn_count = 1
	edge.notes_per_kill = 1
	var cycle_edge := DayCycle.new(gate, config, WorldPersistent.new(), 6)
	cycle_edge.begin_run()
	cycle_edge.place_tile(Vector2i(1, 0), edge)
	var steady := _tile(&"steady", TileDef.Category.DUNGEON)
	steady.color = Vector3i(50, 50, 50)
	cycle_edge.place_tile(Vector2i(0, 1), steady)
	var spent: TileInstance = cycle_edge.grid[Vector2i(1, 0)]
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
	_expect(cycle_edge.erase_tile(Vector2i(1, 0)) and not cycle_edge.grid.has(Vector2i(1, 0)), "erasing clears the cell")
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


func _enemy(id: StringName, note_color: EnemyTemplate.NoteColor) -> EnemyTemplate:
	var template := EnemyTemplate.new()
	template.display_name = String(id)
	template.level = 1
	template.note_color = note_color
	return template


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
