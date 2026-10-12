extends Node
## Self-test for the hex day loop. Run hex_day_cycle_selftest.tscn and read the output.

const RED := &"red_notes"
const GREEN := &"green_notes"
const BLUE := &"blue_notes"
const CUTS := &"cuts"
const GREY := &"grey_notes"

var _failures := 0
var _checks := 0


func _ready() -> void:
	_test_loop()
	_test_roads_and_segno()
	_test_spent_rooms()
	_test_dawn()
	_test_segments()
	_test_blueprints()
	_test_grey_notes()
	_test_neutral_drops()
	_test_spawn_tokens()
	_test_raids()
	_test_allies()
	_test_upgrades()
	_test_construction()
	_test_exploration_and_wild()
	print("[hexday] %d checks, %d failures." % [_checks, _failures])
	if _failures == 0:
		print("[hexday] ALL PASSED")


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
	config.board_radius = 3
	config.starting_resources = {RED: 10, GREEN: 10, BLUE: 10}
	config.road_cost = {}
	config.level_per_day = 0.5
	config.main_path_bonus_per_step = 0.125  # the Segno below is 6 roads out: +75%
	config.loop_penalty = 0.25
	config.ruin_discount = 0.5
	config.carried_level_bonus = 1

	var persistent := WorldPersistent.new()
	var c := HexDayCycle.new(gate, config, persistent, 7)

	# ---- run setup
	c.begin_run()
	var o := c.origin_vertex()
	_expect(c.phase == HexDayCycle.Phase.PLAN and c.day == 1, "a run begins on day 1 in PLAN")
	_expect(c.stock[RED] == 10 and c.stock[GREEN] == 10 and c.stock[BLUE] == 10, "starting notes are granted")
	_expect(c.world.origin == o and c.world.has_structure(o) and c.tile_at(o).def.is_origin, "the Town Square stands on the origin vertex, which is also the exit")
	_expect(persistent.board_seed >= 0 and c.world.hex_count() == 37, "the board is dealt from a seed that is remembered")

	# ---- colour costs
	_expect(c.cost_of(o, haunt) == {RED: 3, GREEN: 1, BLUE: 5}, "a room's colour is its note cost (30, 10, 50 = 3, 1, 5)")
	_expect(c.cost_of(o, hut) == {RED: 2}, "a village tile's colour costs notes too")
	var priced := _tile(&"priced", TileDef.Category.VILLAGE, {CUTS: 4})
	priced.color = Vector3i(140, 240, 30)
	_expect(c.cost_of(o, priced) == {RED: 14, GREEN: 24, BLUE: 3, CUTS: 4}, "140, 240, 30 costs 14, 24, 3, plus any extra cost")

	# ---- planning: a main chain of six roads and a short side chain
	var visited := {}
	var main := _chain(c, o, 6, visited)
	var side := _chain(c, o, 2, visited)
	_expect(main.size() == 7 and side.size() == 3, "roads can be laid in two chains from the origin (got %d and %d)" % [main.size(), side.size()])
	if main.size() < 7 or side.size() < 3:
		return
	var a: Vector3i = main[1]
	var b: Vector3i = main[2]
	var d: Vector3i = main[4]
	var f: Vector3i = main[6]
	var b2: Vector3i = side[2]

	_expect(c.can_place(a, haunt)["ok"], "a room may stand right next to the origin, since there is no distance rule")
	_expect(not c.can_place(HexGrid.corner(Vector2i(3, 0), 1), haunt)["ok"], "a room needs a road to its vertex")
	_expect(not c.can_place(a, gate)["ok"], "the exit cannot be built")
	_expect(c.place_tile(b, haunt) and c.stock[RED] == 7 and c.stock[GREEN] == 9 and c.stock[BLUE] == 5,
			"placing a room spends its colour in notes")
	_expect(not c.can_place(b, haunt)["ok"], "an occupied vertex is refused")
	_expect(c.place_tile(d, haunt) and c.stock[BLUE] == 0, "a second room can stand further along the road")
	_expect(c.place_tile(b2, hut) and c.stock[RED] == 2, "village tiles place the same way")
	_expect(c.can_place(f, haunt)["reason"] == "Cannot afford it.", "an unaffordable room is refused")
	_expect(c.distance_to_exit(b) == 2 and c.distance_to_exit(d) == 4, "distance is measured in roads from the exit")

	# ---- expedition: the party spawns at the Segno, so one must be placed first
	_expect(c.start_expedition().is_empty() and c.phase == HexDayCycle.Phase.PLAN, "a day cannot start without a Segno")
	_expect(c.set_segno(f) and c.has_segno() and c.world.has_structure(f), "the Segno is built where a road ends")
	var info := c.main_path()
	_expect(bool(info["found"]) and bool(info["connected"]) and int(info["steps"]) == 6 and int(info["loops"]) == 0
			and (info["path"] as Array).size() == 7, "the main path runs the whole chain with no loops")
	_expect(is_equal_approx(float(info["bonus"]), 0.75), "six roads at 0.125 each is a 75% bonus")
	_wake(c, [b, d])
	var want := 2 * (c.awake_borders(b).size() + c.awake_borders(d).size())
	var spawns := c.start_expedition()
	_expect(c.phase == HexDayCycle.Phase.EXPEDITION, "the expedition starts")
	_expect(want >= 4 and spawns.size() == want, "each room gathers 2 enemies per awake hex beside it (got %d, want %d)" % [spawns.size(), want])
	_expect(c.open_road_spots().is_empty() and c.open_structure_spots().is_empty(), "no building during an expedition")
	_expect(is_equal_approx(c.loot_multiplier(b), 1.75) and c.loot_multiplier(b2) == 1.0, "rooms on the main path pay more; others pay normally")
	var loot_ok := true
	for s in spawns:
		var template: EnemyTemplate = s["template"]
		var note_id: StringName = [RED, GREEN, BLUE][int(template.note_color) - 1]
		var loot: Dictionary = s["loot"]
		if int(loot.get(note_id, 0)) != 7 or int(loot.get(CUTS, 0)) != 2 or loot.size() != 2:
			loot_ok = false
	_expect(loot_ok, "an enemy carries notes of its own colour plus the room's other loot, both scaled by the bonus")
	_expect(spawns[0]["level"] == 1, "day 1 enemies have their base level")

	var at_b: Array[Dictionary] = []
	for s in spawns:
		if s["vertex"] == b:
			at_b.append(s)
	var at_d := spawns.size() - at_b.size()
	var expected := Vector3i(30, 10, 50)
	var expected_notes := {RED: 0, GREEN: 0, BLUE: 0}
	var expected_cuts := 0
	for s in at_b:
		c.record_kill(s["id"])
		var channel := int((s["template"] as EnemyTemplate).note_color) - 1
		expected[channel] = mini(250, expected[channel] + 7)  # 7 notes, 1 colour point each
		expected_notes[[RED, GREEN, BLUE][channel]] += 7
		expected_cuts += 2
	var room: TileInstance = c.world.structure_at(b)
	_expect(room.color == expected, "each note dropped raises the room's matching colour (got %s, want %s)" % [room.color, expected])
	_expect(c.record_kill(at_b[0]["id"]).is_empty(), "a kill counts once")
	_expect(c.stock[RED] == 2 and c.stock[GREEN] == 8, "loot is carried, not banked, until you return")
	var carried_ok := int(c.carried_loot.get(CUTS, 0)) == expected_cuts
	for id in expected_notes:
		carried_ok = carried_ok and int(c.carried_loot.get(id, 0)) == int(expected_notes[id])
	_expect(carried_ok, "carried loot adds up")
	_expect(c.remaining() == at_d, "the rest of the enemies are left")

	var before := c.stock.duplicate()
	var report := c.return_to_exit()
	var banked_ok := true
	for id in [RED, GREEN, BLUE, CUTS]:
		banked_ok = banked_ok and int(c.stock.get(id, 0)) == int(before.get(id, 0)) + int(report["banked"].get(id, 0))
	_expect(banked_ok and report["left_alive"] == at_d, "returning banks the loot")
	_expect(c.phase == HexDayCycle.Phase.SUMMARY and c.carried[d] == at_d, "enemies left alive are remembered")

	# ---- next day: income arrives (and nothing is taken back)
	var day2 := c.begin_next_day()
	_expect(c.day == 2 and c.phase == HexDayCycle.Phase.PLAN, "the next day begins in PLAN")
	_expect(int(day2["income"].get(CUTS, 0)) == 3 and not day2.has("tithe_due"), "income arrives and there is no tithe")
	_expect(c.stock[CUTS] == expected_cuts + 3, "all the income is kept")
	_expect(c.level_bonus(d) == 1 and c.level_bonus(b) == 0, "surviving enemies make their room stronger")
	_wake(c, [b, d])
	_expect(c.start_expedition().size() == want + at_d, "surviving enemies return in addition to the usual ones")
	c.return_to_exit()

	# ---- defeat
	c.begin_next_day()
	c.start_expedition()
	c.record_kill(c.spawns[0]["id"])
	var terrain_before := c.world.terrain.duplicate()
	var day_at_defeat := c.day
	c.defeat()
	_expect(c.phase == HexDayCycle.Phase.OVER and c.carried_loot.is_empty(), "defeat ends the run and loses carried loot")
	_expect(persistent.runs == 1 and persistent.best_day == day_at_defeat, "the run is recorded")
	_expect(persistent.ruins.size() == 1 and persistent.ruins[0]["def"] == hut and persistent.ruins[0]["vertex"] == b2,
			"town tiles are remembered as ruins, with their vertex")
	_expect(persistent.built_ids.has(&"hut") and persistent.built_ids.has(&"haunt"), "built tile ids are remembered")
	_expect(c.world.roads.is_empty() and c.world.structures.is_empty(), "defeat wipes every road and room")

	# ---- the next run
	c.begin_run()
	_expect(c.day == 1 and c.stock[RED] == 10, "a new run resets day and stock")
	_expect(c.world.terrain == terrain_before, "the board is the same one, so ruins sit where they were")
	_expect(not c.world.has_structure(b) and not c.world.has_structure(d) and c.world.roads.is_empty(), "the dungeon and its roads are wiped")
	_expect(not c.has_segno(), "the Segno is cleared with the dungeon")
	var ruin := c.tile_at(b2)
	_expect(ruin != null and ruin.ruined and not ruin.is_live(), "the town comes back as ruins")
	_expect(not c.tile_at(o).ruined and c.tile_at(o).def.is_origin, "the origin is never a ruin")
	_expect(not c.world.has_structure(b2), "a ruin is not a standing structure, so it anchors nothing")
	c.build_road(_road_between(side[0], side[1]))
	c.build_road(_road_between(side[1], side[2]))
	_expect(c.can_place(b2, shrine)["reason"] == "Ruins of something else stand here.", "ruins can only be rebuilt as what they were")
	_expect(c.can_erase(b2)["ok"], "a ruin can be cleared to build something else")
	_expect(c.cost_of(b2, hut) == {RED: 1}, "rebuilding ruins is discounted")
	_expect(c.place_tile(b2, hut) and c.stock[RED] == 9, "ruins can be rebuilt once a road reaches them")
	_expect(not c.tile_at(b2).ruined and not c.ruins.has(b2), "a rebuilt tile stands again")


# --------------------------------------------------- roads and the Segno

func _test_roads_and_segno() -> void:
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var config := WorldConfig.new()
	config.require_blueprints = false
	config.board_radius = 3
	config.starting_resources = {CUTS: 20}
	config.road_cost = {CUTS: 1}
	var c := HexDayCycle.new(gate, config, WorldPersistent.new(), 3)
	c.begin_run()
	var o := c.origin_vertex()
	_expect(c.road_price() == {CUTS: 1}, "road cost is read from the config")

	var chain := _chain(c, o, 4, {})
	_expect(chain.size() == 5 and c.stock[CUTS] == 16, "each road costs one cut (got %d roads, %d cuts)" % [chain.size() - 1, int(c.stock.get(CUTS, 0))])
	if chain.size() < 5:
		return
	c.stock[CUTS] = 0
	var spots := c.open_road_spots()
	_expect(not spots.is_empty() and c.can_build_road(spots[0])["reason"] == "Cannot afford it." and not c.build_road(spots[0]),
			"a road you cannot pay for is refused")
	c.stock[CUTS] = 10
	var middle := _road_between(chain[1], chain[2])
	_expect(c.erase_road(middle) and not c.world.has_road(middle) and c.stock[CUTS] == 10, "a road can be torn up, with no refund")
	_expect(c.build_road(middle) and c.stock[CUTS] == 9, "and laid again")

	# ---- the Segno
	_expect(c.can_set_segno(chain[1])["ok"], "the Segno may stand right next to the origin")
	_expect(not c.can_set_segno(HexGrid.corner(Vector2i(3, 0), 1))["ok"], "the Segno needs a road to its vertex")
	_expect(c.spawn_vertex() == o, "with no Segno the party would spawn at the exit")
	_expect(c.set_segno(chain[3]) and c.segno == chain[3] and c.world.has_structure(chain[3]) and c.spawn_vertex() == chain[3], "the Segno is placed free where a road ends")
	_expect(c.set_segno(chain[4]) and not c.world.has_structure(chain[3]) and c.world.has_structure(chain[4]),
			"moving the Segno leaves nothing behind at its old place")
	_expect(not c.can_set_segno(chain[4])["ok"], "the Segno is already there")
	_expect(c.can_start_expedition()["ok"], "a Segno joined to the exit can start the day")

	c.erase_road(middle)
	_expect(not bool(c.main_path()["connected"]) and c.distance_to_exit(chain[4]) == -1, "cutting the road cuts the Segno off")
	_expect(c.can_start_expedition()["reason"] == "The Segno must connect to the exit.", "a cut-off Segno cannot start the day")
	c.build_road(middle)
	_expect(bool(c.main_path()["connected"]) and c.can_start_expedition()["ok"], "mending the road reconnects it")

	c.clear_segno()
	_expect(not c.has_segno() and not c.world.has_structure(chain[4]), "the Segno can be picked up again")


# -------------------------------------------------------------- spent rooms

func _test_spent_rooms() -> void:
	var big := _enemy(&"big", EnemyTemplate.NoteColor.RED, 250)
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	# One kill takes the red channel to 250, and green and blue start there: spent.
	var husk := _tile(&"husk", TileDef.Category.DUNGEON)
	husk.color = Vector3i(0, 250, 250)
	husk.enemies = [big]
	husk.spawn_count = 1

	var config := WorldConfig.new()
	config.require_blueprints = false
	config.board_radius = 3
	config.starting_resources = {RED: 100, GREEN: 100, BLUE: 100}
	config.road_cost = {}
	config.erase_any_tile = false
	var c := HexDayCycle.new(gate, config, WorldPersistent.new(), 5)
	c.begin_run()
	var o := c.origin_vertex()
	var chain := _chain(c, o, 4, {})
	if chain.size() < 5:
		_expect(false, "a chain of four roads can be laid")
		return
	var middle: Vector3i = chain[2]
	_expect(c.place_tile(middle, husk) and c.set_segno(chain[4]), "a room and the Segno stand either side of the exit's road")
	_expect(bool(c.main_path()["connected"]) and c.distance_to_exit(chain[4]) == 4, "the layout is connected at first")
	_expect(not c.can_erase(middle)["ok"], "a room that isn't spent cannot be erased")
	_expect(not c.can_erase(o)["ok"], "the origin cannot be erased")

	_wake(c, [middle])
	var spawns := c.start_expedition()
	_expect(spawns.size() == c.awake_borders(middle).size() and spawns.size() >= 1, "the husk gathers its enemy")
	c.record_kill(spawns[0]["id"])
	_expect((c.world.structure_at(middle) as TileInstance).is_depleted(), "a kill that fills every channel spends the room")
	_expect(not bool(c.main_path()["connected"]) and c.distance_to_exit(chain[4]) == -1, "a spent room no longer connects the road")
	_expect(c.distance_to_exit(chain[1]) == 1, "the road up to it still does")

	c.return_to_exit()
	c.begin_next_day()
	_expect(c.can_erase(middle)["ok"] and c.erase_tile(middle) and not c.world.has_structure(middle), "a spent room can be erased")
	_expect(c.world.has_road(_road_between(chain[1], chain[2])), "its roads stay")
	_expect(c.can_place(middle, husk)["ok"], "the vertex can be built on again")


# -------------------------------------------------------------- blueprints

func _test_blueprints() -> void:
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var room := _tile(&"room", TileDef.Category.DUNGEON)
	var stall := _tile(&"stall", TileDef.Category.VILLAGE)
	var config := WorldConfig.new()
	config.require_blueprints = true
	config.blueprints_per_day = 1
	config.road_cost = {}
	config.board_radius = 3
	config.starting_resources = {RED: 10, GREEN: 10, BLUE: 10}
	var c := HexDayCycle.new(gate, config, WorldPersistent.new(), 9)
	var pool: Array[TileDef] = [room]
	c.blueprint_pool = pool
	c.begin_run()
	_expect(c.blueprints.size() == 1 and c.blueprints[0] == room, "a day's hand is drawn at dawn")

	var visited := {}
	var chain := _chain(c, c.origin_vertex(), 2, visited)
	if chain.size() < 3:
		_expect(false, "a chain of two roads can be laid")
		return
	_expect(c.place_tile(chain[2], room) and c.blueprints.is_empty(), "placing a dungeon room spends its blueprint")
	var more := _chain(c, chain[2], 2, visited)
	if more.size() < 3:
		_expect(false, "the chain can be extended")
		return
	_expect(c.can_place(more[2], room)["reason"] == "No blueprint for that today.", "with no card left, another room is refused")
	_expect(c.can_place(more[2], stall)["ok"], "town tiles never need a blueprint")


# --------------------------------------------------------------------- dawn

func _test_dawn() -> void:
	var red := _enemy(&"red", EnemyTemplate.NoteColor.RED)
	var green := _enemy(&"green", EnemyTemplate.NoteColor.GREEN)
	var blue := _enemy(&"blue", EnemyTemplate.NoteColor.BLUE)
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var den := _tile(&"den", TileDef.Category.DUNGEON)
	den.enemies = [red, green, blue]
	den.spawn_count = 3

	var config := WorldConfig.new()
	config.require_blueprints = false
	config.require_segno = false
	config.board_radius = 3
	config.starting_resources = {RED: 100, GREEN: 100, BLUE: 100}
	config.road_cost = {}
	config.wake_rolls_per_segment = 2
	config.terrain_affinity_multiplier = 100000.0
	var c := HexDayCycle.new(gate, config, WorldPersistent.new(), 11)

	# ---- the roll
	var sevens := 0
	var consistent := true
	var two_rolls := true
	for _i in 60:
		c.begin_run()
		two_rolls = two_rolls and c.rolls.size() == 2
		sevens += c.rolls.count(7)
		for hex in c.world.hexes():
			consistent = consistent and c.awake.has(hex) == c.rolls.has(int(c.world.numbers[hex]))
	_expect(two_rolls, "the dice are rolled as many times as the config says")
	_expect(sevens == 0, "a 7 is rolled again while reroll_sevens is on")
	_expect(consistent, "a hex is awake exactly when its number was rolled")
	config.reroll_sevens = false
	for _i in 100:
		c.begin_run()
		sevens += c.rolls.count(7)
		for hex in c.world.hexes():
			consistent = consistent and c.awake.has(hex) == c.rolls.has(int(c.world.numbers[hex]))
	_expect(sevens > 0, "with rerolls off a 7 can come up")
	_expect(consistent, "a rolled 7 wakes nothing, since no hex carries one")
	config.reroll_sevens = true

	# ---- a den on a corner of three hexes
	c.begin_run()
	var chain := _chain(c, c.origin_vertex(), 2, {})
	if chain.size() < 3:
		_expect(false, "a chain of two roads can be laid")
		return
	var v: Vector3i = chain[2]
	var ring := c.world.hexes_at(v)
	if ring.size() < 3:
		_expect(false, "the den's corner touches three hexes")
		return
	_expect(c.place_tile(v, den), "the den is placed")
	var none: Array[Vector2i] = []
	var one: Array[Vector2i] = [ring[0]]
	var two: Array[Vector2i] = [ring[0], ring[1]]
	var three: Array[Vector2i] = [ring[0], ring[1], ring[2]]
	var green_blue: Array[Vector2i] = [ring[1], ring[2]]

	c.set_awake(none)
	_expect(c.awake_borders(v).is_empty() and c.spawn_count_at(v) == 0, "a den with nothing awake beside it is quiet")
	c.set_awake(three)
	_expect(c.awake_borders(v).size() == 3 and c.spawn_count_at(v) == 9, "a den gathers its spawn count for each awake hex beside it")
	_expect(c.spawn_count_at(chain[1]) == 0, "a bare vertex gathers nothing")
	_expect(_run_day(c, none).is_empty(), "a quiet day gathers nothing")
	_expect(_run_day(c, one).size() == 3, "one awake hex fills the den with its spawn count")
	_expect(_run_day(c, two).size() == 6, "two awake hexes double that")
	_expect(_run_day(c, three).size() == 9, "three triple it")

	# ---- the awake hexes' colours steer who turns up
	c.world.terrain[ring[0]] = HexWorld.Terrain.RED
	c.world.terrain[ring[1]] = HexWorld.Terrain.GREEN
	c.world.terrain[ring[2]] = HexWorld.Terrain.BLUE
	var from_red := _run_day(c, one)
	var all_red := true
	for s in from_red:
		all_red = all_red and (s["template"] as EnemyTemplate).note_color == EnemyTemplate.NoteColor.RED
	_expect(from_red.size() == 3 and all_red, "a red hex waking fills the den with red enemies")
	var from_pair := _run_day(c, green_blue)
	var no_red := true
	for s in from_pair:
		no_red = no_red and (s["template"] as EnemyTemplate).note_color != EnemyTemplate.NoteColor.RED
	_expect(from_pair.size() == 6 and no_red, "green and blue hexes waking leave the red enemies out")

	# ---- a den nothing woke beside can still gather a few
	config.idle_spawn_count = 2
	_expect(_run_day(c, none).size() == 2, "a quiet den gathers its idle few")
	config.idle_spawn_count = 0


# ----------------------------------------------------------------- segments

func _test_segments() -> void:
	var red := _enemy(&"red", EnemyTemplate.NoteColor.RED)
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var den := _tile(&"den", TileDef.Category.DUNGEON)
	den.enemies = [red]
	den.spawn_count = 2

	var config := WorldConfig.new()
	config.require_blueprints = false
	config.require_segno = false
	config.board_radius = 3
	config.starting_resources = {RED: 100, GREEN: 100, BLUE: 100}
	config.road_cost = {}
	var c := HexDayCycle.new(gate, config, WorldPersistent.new(), 21)
	var segments_seen: Array[int] = []
	c.segment_changed.connect(func(s: int) -> void: segments_seen.append(s))
	var rests: Array[bool] = []
	c.party_rested.connect(func(long_rest: bool) -> void: rests.append(long_rest))

	c.begin_run()
	_expect(c.segment == HexDayCycle.Segment.DAWN and c.day == 1, "a run begins at dawn on day 1")
	_expect(c.rolls.size() == 1, "each segment makes one roll by default")
	var chain := _chain(c, c.origin_vertex(), 2, {})
	if chain.size() < 3:
		_expect(false, "a chain of two roads can be laid")
		return
	var v: Vector3i = chain[2]
	var ring := c.world.hexes_at(v)
	if ring.size() < 3:
		_expect(false, "the den's corner touches three hexes")
		return
	_expect(c.place_tile(v, den), "the den is placed")
	var one: Array[Vector2i] = [ring[0]]
	var other: Array[Vector2i] = [ring[1]]
	var none: Array[Vector2i] = []

	# ---- dawn: nobody delves, so the den still fills
	c.set_awake(one)
	var step := c.begin_next_segment()
	_expect(c.segment == HexDayCycle.Segment.MIDDAY and int(step["segment"]) == int(HexDayCycle.Segment.MIDDAY), "the next segment is midday")
	_expect(c.day == 1 and c.phase == HexDayCycle.Phase.PLAN, "a new segment is not a new day")
	_expect(c.gathered_at(v) == 2, "a segment nobody delved in still fills the den")
	var consistent := c.rolls.size() == 1
	for hex in c.world.hexes():
		consistent = consistent and c.awake.has(hex) == c.rolls.has(int(c.world.numbers[hex]))
	_expect(consistent, "the new segment's awake hexes come from its own roll")

	# ---- midday: delve; the dawn's enemies are still waiting and join midday's
	c.set_awake(other)
	var spawns := c.start_expedition()
	_expect(spawns.size() == 4, "midday's den holds dawn's 2 waiting enemies and its own 2 (got %d)" % spawns.size())
	_expect(c.gathered_at(v) == 0, "the waiting enemies were drawn into the expedition")
	_expect(c.begin_next_segment().is_empty() and c.segment == HexDayCycle.Segment.MIDDAY, "a segment cannot be ended while delving")
	for i in spawns.size() - 1:
		c.record_kill(spawns[i]["id"])
	c.return_to_exit()
	_expect(int(c.carried.get(v, 0)) == 1, "the enemy left alive waits")

	# ---- dusk: nobody delves again
	c.begin_next_segment()
	_expect(c.segment == HexDayCycle.Segment.DUSK and c.day == 1, "the third segment is dusk")
	_expect(c.gathered_at(v) == 0, "midday's gathering was already used, so nothing is gathered twice")
	c.set_awake(one)
	var report := c.begin_next_segment()
	_expect(c.day == 2 and c.segment == HexDayCycle.Segment.DAWN, "after dusk the day turns over")
	_expect(report.has("income") and not report.has("tithe_due"), "the day's end reports income and no tithe")
	_expect(c.gathered_at(v) == 2, "dusk's unvisited gathering is kept past the night")
	_expect(rests.size() == 3 and not rests[0] and not rests[1] and rests[2], "segments end with a short rest and the day with a long one")
	_expect(segments_seen.size() == 4 and segments_seen[1] == int(HexDayCycle.Segment.MIDDAY) and segments_seen[3] == int(HexDayCycle.Segment.DAWN), "every segment change is announced")

	# ---- the next day: waiting enemies and the leftover enemy all turn up
	c.set_awake(none)
	var third := c.start_expedition()
	_expect(third.size() == 3, "a quiet dawn still meets the 2 waiting enemies and the 1 leftover (got %d)" % third.size())


# --------------------------------------------------------------- grey notes

func _test_grey_notes() -> void:
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var config := WorldConfig.new()  # the defaults: a road costs one grey note
	config.require_blueprints = false
	config.require_segno = false
	config.board_radius = 3
	config.starting_resources = {GREY: 2, RED: 3, GREEN: 3, BLUE: 3}
	var c := HexDayCycle.new(gate, config, WorldPersistent.new(), 4)
	c.begin_run()
	var o := c.origin_vertex()

	_expect(c.road_price() == {GREY: 1}, "a road costs one grey note by default")
	_expect(WorldConfig.new().starting_resources.has(GREY), "a run starts with grey notes in hand")
	var chain := _chain(c, o, 2, {})
	_expect(chain.size() == 3 and c.stock[GREY] == 0, "two roads spend two grey notes (got %d roads, %d grey)" % [chain.size() - 1, int(c.stock.get(GREY, 0))])
	var spots := c.open_road_spots()
	_expect(not spots.is_empty() and c.can_build_road(spots[0])["reason"] == "Cannot afford it." and not c.build_road(spots[0]),
			"with no grey notes left, no road")

	_expect(c.exchange_to_grey() and c.stock[GREY] == 1 and c.stock[RED] == 2 and c.stock[GREEN] == 2 and c.stock[BLUE] == 2,
			"one note of each colour makes one grey note")
	_expect(c.build_road(spots[0]) and c.stock[GREY] == 0, "and the grey note pays for a road")
	_expect(c.can_exchange_to_colors()["reason"] == "Not enough grey notes." and not c.exchange_to_colors(), "you cannot convert grey notes you do not have")
	c.stock[GREY] = 2
	_expect(c.exchange_to_colors(2) and c.stock[GREY] == 0 and c.stock[RED] == 4 and c.stock[GREEN] == 4 and c.stock[BLUE] == 4,
			"a grey note makes one note of each colour, and conversions can be batched")
	c.stock[GREEN] = 0
	_expect(c.can_exchange_to_grey()["reason"] == "Not enough of every colour." and not c.exchange_to_grey(), "making grey needs every colour")
	_expect(c.stock[RED] == 4 and c.stock[BLUE] == 4, "a refused conversion takes nothing")

	config.grey_exchange_rate = 2
	c.stock = {GREY: 1, RED: 0, GREEN: 0, BLUE: 0}
	_expect(c.exchange_amount() == 2 and c.exchange_to_colors() and c.stock[RED] == 2 and c.stock[GREEN] == 2 and c.stock[BLUE] == 2 and c.stock[GREY] == 0,
			"at rate 2, one grey note is worth two of each colour")
	_expect(c.exchange_to_grey() and c.stock[GREY] == 1 and c.stock[RED] == 0 and c.stock[GREEN] == 0 and c.stock[BLUE] == 0,
			"and two of each colour make one grey note")

	c.start_expedition()
	_expect(c.phase == HexDayCycle.Phase.EXPEDITION and not c.can_exchange_to_grey()["ok"] and not c.can_exchange_to_colors()["ok"],
			"notes are only converted while planning")


# ------------------------------------------------------------ neutral drops

func _test_neutral_drops() -> void:
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var config := WorldConfig.new()
	config.require_blueprints = false
	config.require_segno = false
	config.board_radius = 3
	var c := HexDayCycle.new(gate, config, WorldPersistent.new(), 4)
	c.begin_run()

	var room := _tile(&"crypt", TileDef.Category.DUNGEON)
	room.note_multiplier = 1.0
	var tile := TileInstance.new(room, Vector2i.ZERO)

	var grey_loot := c._loot_for(tile, _enemy(&"wisp", EnemyTemplate.NoteColor.NONE, 3), 1.0)
	_expect(int(grey_loot.get(GREY, 0)) == 3 and not grey_loot.has(RED) and not grey_loot.has(GREEN) and not grey_loot.has(BLUE),
			"a neutral enemy drops only grey notes (got %s)" % str(grey_loot))

	var red_loot := c._loot_for(tile, _enemy(&"imp", EnemyTemplate.NoteColor.RED, 3), 1.0)
	_expect(int(red_loot.get(RED, 0)) == 3 and not red_loot.has(GREY),
			"a coloured enemy still drops its own colour, not grey (got %s)" % str(red_loot))

	var none_loot := c._loot_for(tile, _enemy(&"dud", EnemyTemplate.NoteColor.NONE, 0), 1.0)
	_expect(none_loot.is_empty(), "a neutral enemy that drops nothing drops no grey either")

	# Grey notes do not stain the room they were looted from.
	var before := tile.color
	c.world.build_structure(c.origin_vertex(), tile)
	c._stain_room(c.origin_vertex(), grey_loot)
	_expect(tile.color == before, "grey loot leaves the room's colour unchanged")


# ------------------------------------------------------------ spawn tokens

func _tokens(spawns: Array[Dictionary]) -> int:
	var total := 0
	for s in spawns:
		total += (s["template"] as EnemyTemplate).spawn_cost
	return total


func _test_spawn_tokens() -> void:
	var runt := _enemy(&"runt", EnemyTemplate.NoteColor.NONE)
	var brute := _enemy(&"brute", EnemyTemplate.NoteColor.NONE)
	brute.spawn_cost = 5
	_expect(runt.spawn_cost == 1, "an enemy costs one spawn token unless it says otherwise")

	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var den := _tile(&"den", TileDef.Category.DUNGEON)
	den.enemies = [runt, brute]
	den.spawn_count = 6
	var config := WorldConfig.new()
	config.require_blueprints = false
	config.require_segno = false
	config.board_radius = 3
	config.starting_resources = {RED: 100, GREEN: 100, BLUE: 100}
	config.road_cost = {}
	var c := HexDayCycle.new(gate, config, WorldPersistent.new(), 41)
	c.begin_run()
	var chain := _chain(c, c.origin_vertex(), 2, {})
	if chain.size() < 3:
		_expect(false, "a chain of two roads can be laid")
		return
	var v: Vector3i = chain[2]
	var ring := c.world.hexes_at(v)
	_expect(c.place_tile(v, den), "the den is placed")
	var one: Array[Vector2i] = [ring[0]]
	var two: Array[Vector2i] = [ring[0], ring[1]]

	# A mixed pool always spends the whole budget, since a runt can pay for any remainder.
	var exact := true
	var saw_brute := false
	var saw_only_runts := false
	for _i in 60:
		var day := _run_day(c, one)
		exact = exact and _tokens(day) == 6
		var brutes := day.filter(func(s: Dictionary) -> bool: return (s["template"] as EnemyTemplate).spawn_cost == 5)
		saw_brute = saw_brute or not brutes.is_empty()
		saw_only_runts = saw_only_runts or brutes.is_empty()
		exact = exact and brutes.size() <= 1  # two brutes would cost 10
	_expect(exact, "a room spends exactly its tokens, and never overspends")
	_expect(saw_brute and saw_only_runts, "a costly enemy turns up in lower numbers beside cheap ones")
	_expect(_tokens(_run_day(c, two)) == 12, "each awake hex adds another full budget of tokens")

	# Only costly enemies: the leftover token buys nothing and is lost.
	den.enemies = [brute]
	var only := _run_day(c, one)
	_expect(only.size() == 1 and _tokens(only) == 5, "a budget of 6 buys one 5-token enemy and loses the spare token")

	# Too costly for the budget: the room stays empty rather than overspending.
	brute.spawn_cost = 7
	_expect(_run_day(c, one).is_empty(), "an enemy costing more than the budget is never gathered")


# ------------------------------------------------------------------ raids

## A StatBlock for an off-screen fight. `corpus` above 0 overrides its health.
func _fighter(engine: RulesEngine, display_name: String, level: int, corpus := 0, volume := 12) -> StatBlock:
	var b := StatBlock.new(engine, display_name, level)
	b.scores = {&"volume": volume, &"tempo": 10, &"tone": 12, &"attachment": 14}
	b.refill()
	if corpus > 0:
		b.corpus = corpus
	return b


func _test_raids() -> void:
	_expect(not WorldConfig.new().raids_enabled, "raids are off unless the config turns them on")
	var runt := _enemy(&"runt", EnemyTemplate.NoteColor.NONE)
	var raider := _enemy(&"raider", EnemyTemplate.NoteColor.NONE)
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var den := _tile(&"den", TileDef.Category.DUNGEON)
	den.enemies = [runt]
	den.spawn_count = 3
	var stall := _tile(&"stall", TileDef.Category.VILLAGE)
	stall.max_health = 3

	var config := WorldConfig.new()
	config.require_blueprints = false
	config.require_segno = false
	config.board_radius = 3
	config.starting_resources = {RED: 100, GREEN: 100, BLUE: 100}
	config.road_cost = {}
	config.raids_enabled = true
	var raider_list: Array[EnemyTemplate] = [raider]
	config.raider_templates = raider_list
	config.raid_repair_per_day = 0
	var c := HexDayCycle.new(gate, config, WorldPersistent.new(), 57)
	var engine := RulesEngine.new(null, 4242)
	engine.load_stat_defs("res://Systems/Rules/Data/Stats")
	c.combat_engine = engine
	c.begin_run()

	# stall two roads from the Town Square, den two roads beyond it
	var visited := {}
	var first := _chain(c, c.origin_vertex(), 2, visited)
	if first.size() < 3:
		_expect(false, "a chain of two roads can be laid")
		return
	var s: Vector3i = first[2]
	_expect(c.place_tile(s, stall), "the stall is placed")
	var second := _chain(c, s, 2, visited)
	if second.size() < 3:
		_expect(false, "two more roads can be laid beyond the stall")
		return
	var d: Vector3i = second[2]
	_expect(c.place_tile(d, den), "the den is placed")
	var ring := c.world.hexes_at(s)
	if ring.size() < 2:
		_expect(false, "the stall's corner touches two hexes")
		return
	var none: Array[Vector2i] = []
	var one: Array[Vector2i] = [ring[0]]
	var two: Array[Vector2i] = [ring[0], ring[1]]
	var den_tile: TileInstance = c.world.structures[d]
	var stall_tile: TileInstance = c.world.structures[s]
	_expect(stall_tile.health == 3, "a structure starts at its max health")

	# ---- room size comes from spawn count
	den.spawn_count = 2
	_expect(c.room_size(den_tile) == 0, "a low spawn count makes a small room")
	den.spawn_count = 3
	_expect(c.room_size(den_tile) == 1, "the first threshold makes it medium")
	den.spawn_count = 6
	_expect(c.room_size(den_tile) == 2, "the second threshold makes it large")
	_expect(c.cover_radius(den_tile) == 3 and c.room_capacity(den_tile) == 14, "size sets radius and capacity")

	# ---- a small room's zone does not reach, so the stall draws raiders
	den.spawn_count = 2
	_expect(not c.is_covered(s), "a small room does not reach two roads away")
	c.set_awake(one)
	c.spawn_raids()
	_expect(c.raiders_at(s) == 1, "an uncovered structure draws a raider when its hex wakes")
	c.raiders.clear()
	c.set_awake(two)
	c.spawn_raids()
	_expect(c.raiders_at(s) == 2, "each awake hex beside it draws another")
	c.raiders.clear()
	c.set_awake(none)
	c.spawn_raids()
	_expect(c.raiders.is_empty(), "nothing awake, no raiders")

	# ---- a medium room covers it: the raiders gather in the room instead
	den.spawn_count = 3
	_expect(c.is_covered(s), "a medium room reaches two roads away")
	c.gathered.clear()
	c.set_awake(one)
	c.spawn_raids()
	_expect(c.raiders_at(s) == 0 and c.gathered_at(d) >= 1, "raiders gather in the room that covers their structure")
	c.raiders.clear()
	c.gathered.clear()

	# ---- a full room covers nothing, and leaks what it cannot hold
	var full: Array = []
	for _i in c.room_capacity(den_tile):
		full.append(runt)
	c.gathered[d] = full.duplicate()
	_expect(c.room_spare(d) == 0 and not c.is_covered(s), "a full room no longer covers")
	c.set_awake(one)
	c.spawn_raids()
	_expect(c.raiders_at(s) == 1, "so the stall's raider roams")
	c.raiders.clear()
	var over: Array = full.duplicate()
	over.append(runt)
	over.append(runt)
	c.gathered[d] = over
	c._leak_overflow()
	_expect(c.gathered_at(d) == c.room_capacity(den_tile), "an overflowing room keeps only its capacity")
	_expect(c.raiders_at(s) == 2, "the surplus leaks toward the nearest structure")
	c.raiders.clear()
	c.gathered.clear()

	# ---- unopposed raiders hurt the structure; repair; allies cancel raiders
	c._add_raider(s, raider)
	c._resolve_raids()
	_expect(stall_tile.health == 2, "an unopposed raider wears the structure down at segment end")
	config.raid_repair_per_day = 5
	c._repair_structures()
	_expect(stall_tile.health == 3, "a new day repairs damage, up to max health")
	config.raid_repair_per_day = 0

	# ---- allies fight raiders through the real CombatSession
	c.raiders.clear()
	c._add_raider(s, raider)
	c.raiders[0]["block"] = _fighter(engine, "Weakling", 1, 1)
	var ally_t := AllyTemplate.new()
	var hero := _fighter(engine, "Guard", 5, 0, 20)
	c.add_ally(s, ally_t, TileDef.AllyBehavior.GUARD, 0, hero)
	c._resolve_raids()
	_expect(c.raiders_at(s) == 0, "allies defeat a raider in a real fight")
	_expect(c.allies_at(s).size() == 1 and not hero.is_down() and stall_tile.health == 3,
			"the standing ally keeps the tile safe")
	c.allies.clear()
	c._add_raider(s, raider)
	c.raiders[0]["block"] = _fighter(engine, "Ogre", 3, 200, 20)
	var recruit := _fighter(engine, "Recruit", 1, 1)
	c.add_ally(s, ally_t, TileDef.AllyBehavior.GUARD, 0, recruit)
	c._resolve_raids()
	_expect(recruit.is_down() and c.allies_at(s).is_empty(), "a beaten ally falls")
	_expect(c.raiders_at(s) == 1 and stall_tile.health == 2, "the surviving raider then hurts the tile")
	c.allies.clear()

	# ---- a structure that runs out of health falls
	c.raiders.clear()
	c._add_raider(s, raider)
	c._add_raider(s, raider)
	c._resolve_raids()
	_expect(not c.world.has_structure(s), "a structure with no health left falls")
	_expect(c.ruins.has(s) and (c.ruins[s] as TileInstance).ruined, "a fallen town tile is left as a ruin")
	c.raiders.clear()

	# ---- dungeon rooms are never raided
	_expect(not c._can_be_raided(d), "a dungeon room is never a raid target")
	var around_den := c.world.hexes_at(d)
	var den_hexes: Array[Vector2i] = [around_den[0]]
	c.set_awake(den_hexes)
	c.spawn_raids()
	_expect(c.raiders_at(d) == 0, "nothing raids the den, even with its hex awake")
	c.raiders.clear()
	c.gathered.clear()

	# ---- raiders are fought in person
	_expect(c.place_tile(s, stall), "the ruined stall can be rebuilt")
	c._add_raider(s, raider)
	c._add_raider(s, raider)
	c.set_awake(none)
	var day_spawns := c.start_expedition()
	var roaming := day_spawns.filter(func(sp: Dictionary) -> bool: return sp.has("raider_id"))
	_expect(roaming.size() == 2, "raiders join the expedition's spawns")
	if roaming.size() == 2:
		c.record_kill(roaming[0]["id"])
		_expect(c.raiders_at(s) == 1, "a raider you kill is gone from the map")
		c.return_to_exit()
		_expect(c.raiders_at(s) == 1 and int(c.carried.get(s, 0)) == 0,
				"a raider left alive stays on the map rather than joining the room")


# ----------------------------------------------------------------- upgrades

func _upgrade(id: StringName, label: String, price := 5) -> RoomUpgrade:
	var up := RoomUpgrade.new()
	up.id = id
	up.display_name = label
	up.cost = {RED: price}
	return up


func _test_upgrades() -> void:
	var runt := _enemy(&"runt", EnemyTemplate.NoteColor.NONE)
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var den := _tile(&"den", TileDef.Category.DUNGEON)
	den.enemies = [runt]
	den.spawn_count = 2
	den.max_health = 10
	var stall := _tile(&"stall", TileDef.Category.VILLAGE)

	var recruit_t := AllyTemplate.new()
	var reach := _upgrade(&"reach", "Long Reach")
	reach.cover_radius_add = 1
	var deep := _upgrade(&"deep", "Deep Lair")
	deep.spawn_count_add = 3
	deep.max_health_add = 5
	var ranger := _upgrade(&"ranger", "Rangers")
	ranger.requires = [&"deep"]
	ranger.excludes = [&"warden"]
	ranger.ally = recruit_t
	ranger.ally_cap_add = 2
	ranger.ally_behavior = RoomUpgrade.AllyBehaviorChange.PATROL
	ranger.ally_patrol_range_add = 4
	var warden := _upgrade(&"warden", "Wardens")
	warden.requires = [&"deep"]
	warden.ally = recruit_t
	warden.ally_cap_add = 1
	warden.capacity_add = 3
	warden.ally_behavior = RoomUpgrade.AllyBehaviorChange.GUARD
	den.upgrades = [reach, deep, ranger, warden]

	var config := WorldConfig.new()
	config.require_blueprints = false
	config.require_segno = false
	config.board_radius = 3
	config.starting_resources = {RED: 100, GREEN: 100, BLUE: 100}
	config.road_cost = {}
	config.raids_enabled = true
	var c := HexDayCycle.new(gate, config, WorldPersistent.new(), 77)
	var engine := RulesEngine.new(null, 4242)
	engine.load_stat_defs("res://Systems/Rules/Data/Stats")
	c.combat_engine = engine
	c.begin_run()

	var visited := {}
	var first := _chain(c, c.origin_vertex(), 2, visited)
	if first.size() < 3:
		_expect(false, "a chain of two roads can be laid")
		return
	var x: Vector3i = first[2]
	_expect(c.place_tile(x, den), "the den is placed")
	var second := _chain(c, x, 2, visited)
	if second.size() < 3:
		_expect(false, "two more roads can be laid beyond the den")
		return
	var y: Vector3i = second[2]
	_expect(c.place_tile(y, stall), "the stall is placed")
	var room: TileInstance = c.world.structures[x]

	# ---- a room with no upgrades is just its def
	_expect(c.effective_spawn_count(room) == 2 and c.room_size(room) == 0, "a bare den is small")
	_expect(c.cover_radius(room) == 1 and c.room_capacity(room) == 4, "a small room covers one step and holds four")
	_expect(not c.is_covered(y), "the stall two steps off is outside a small den's zone")
	_expect(c.cover_zone(x).has(x) and not c.cover_zone(x).has(y) and c.cover_zone(y).is_empty(),
			"a safe room's zone holds its own vertex and what it reaches, and only safe rooms have one")
	_expect(c.available_upgrades(x).size() == 2, "only the roots of the tree are open at first")
	_expect(c.available_upgrades(y).is_empty(), "a tile with no tree has nothing to take")

	# ---- buying: prerequisites, cost, and stat changes
	_expect(not c.can_upgrade(x, &"ranger")["ok"] and String(c.can_upgrade(x, &"ranger")["reason"]).begins_with("Needs"),
			"a branch needs its prerequisite first")
	_expect(not c.can_upgrade(x, &"nope")["ok"], "an upgrade the room does not have is refused")
	var red_before := int(c.stock.get(RED, 0))
	_expect(c.upgrade_tile(x, &"reach"), "the room takes Long Reach")
	_expect(int(c.stock.get(RED, 0)) == red_before - 5, "an upgrade is paid for")
	_expect(c.cover_radius(room) == 2 and c.is_covered(y), "a wider zone now covers the stall")
	_expect(c.cover_zone(x).has(y), "and the zone includes it")
	_expect(not c.upgrade_tile(x, &"reach"), "an upgrade cannot be taken twice")

	c.stock[RED] = 0
	_expect(String(c.can_upgrade(x, &"deep")["reason"]) == "Cannot afford it.", "an upgrade needs its price in stock")
	c.stock[RED] = 100

	var hp_before := room.health
	_expect(c.upgrade_tile(x, &"deep"), "the room takes Deep Lair")
	_expect(c.effective_spawn_count(room) == 5 and c.room_size(room) == 1, "more spawn count raises the room's size tier")
	_expect(c.cover_radius(room) == 3 and c.room_capacity(room) == 8, "a medium room covers further and holds more")
	_expect(c.effective_max_health(room) == 15 and room.health == hp_before + 5, "health upgrades add to current health too")

	# the bigger spawn count feeds the day's gathering
	var ring := c.world.hexes_at(x)
	var one: Array[Vector2i] = [ring[0]]
	c.set_awake(one)
	_expect(c.spawn_count_at(x) == 5, "the upgraded spawn count is gathered for each awake hex")

	# ---- branches lock each other out
	_expect(c.available_upgrades(x).size() == 2, "both branches are open once the prerequisite is taken")
	_expect(c.upgrade_tile(x, &"ranger"), "the room takes the Rangers branch")
	var blocked := c.can_upgrade(x, &"warden")
	_expect(not blocked["ok"] and String(blocked["reason"]).begins_with("Locked out"), "the sibling branch is locked out")
	_expect(c.available_upgrades(x).is_empty(), "nothing else is open")
	_expect(room.upgrades == [&"reach", &"deep", &"ranger"], "the room remembers its choices in order")

	# ---- the branch decides what the garrison does
	_expect(c.effective_ally(room) == recruit_t and c.ally_cap_of(room) == 2, "an upgrade can give a room a garrison")
	c.muster_allies()
	c.muster_allies()
	c.muster_allies()
	_expect(c.allies_of(x) == 2, "the garrison fills to the upgraded cap")
	_expect(int(c.allies[0]["behavior"]) == TileDef.AllyBehavior.PATROL and int(c.allies[0]["range"]) == 4,
			"the Rangers patrol the roads")

	# ---- the lockout works from either side
	var twin := TileInstance.new(den, Vector2i.ZERO)
	twin.upgrades = [&"deep", &"warden"]
	_expect(String(c._upgrade_block(twin, ranger)).begins_with("Locked out"), "the lockout holds whichever way round it is listed")

	# ---- a different branch gives a different room
	var guard_room := TileInstance.new(den, Vector2i.ZERO)
	guard_room.upgrades = [&"deep", &"warden"]
	_expect(c.room_capacity(guard_room) == 11 and c.ally_cap_of(guard_room) == 1, "the Wardens branch trades patrols for capacity")
	_expect(c.ally_behavior_of(guard_room) == TileDef.AllyBehavior.GUARD, "and its units guard")

	# ---- not while the day is under way, and not for rooms that fell
	c.set_awake([])
	c.start_expedition()
	_expect(String(c.can_upgrade(x, &"warden")["reason"]) != "" and not c.can_upgrade(x, &"warden")["ok"],
			"upgrades are only bought while planning")


# ------------------------------------------------------------------ allies

func _test_allies() -> void:
	var raider := _enemy(&"raider", EnemyTemplate.NoteColor.NONE)
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var recruit_t := AllyTemplate.new()
	recruit_t.display_name = "Recruit"
	recruit_t.level = 3
	recruit_t.scores[&"volume"] = 18
	var post := _tile(&"post", TileDef.Category.VILLAGE)  # guards its own vertex
	post.ally = recruit_t
	post.ally_cap = 2
	post.ally_per_segment = 1
	post.ally_behavior = TileDef.AllyBehavior.GUARD
	var stall := _tile(&"stall", TileDef.Category.VILLAGE)  # has no defenders of its own
	stall.max_health = 3
	var watch := _tile(&"watch", TileDef.Category.VILLAGE)  # sends a patrol out
	watch.ally = recruit_t
	watch.ally_cap = 1
	watch.ally_per_segment = 1
	watch.ally_behavior = TileDef.AllyBehavior.PATROL

	var config := WorldConfig.new()
	config.require_blueprints = false
	config.require_segno = false
	config.board_radius = 3
	config.starting_resources = {RED: 100, GREEN: 100, BLUE: 100}
	config.road_cost = {}
	config.raids_enabled = true
	config.raid_repair_per_day = 0
	var c := HexDayCycle.new(gate, config, WorldPersistent.new(), 63)
	var engine := RulesEngine.new(null, 4242)
	engine.load_stat_defs("res://Systems/Rules/Data/Stats")
	c.combat_engine = engine
	c.begin_run()

	# post, then the stall two roads on, then the watch two roads further
	var visited := {}
	var first := _chain(c, c.origin_vertex(), 2, visited)
	if first.size() < 3:
		_expect(false, "a chain of two roads can be laid")
		return
	var x: Vector3i = first[2]
	_expect(c.place_tile(x, post), "the post is placed")
	var second := _chain(c, x, 2, visited)
	if second.size() < 3:
		_expect(false, "two more roads can be laid beyond the post")
		return
	var y: Vector3i = second[2]
	_expect(c.place_tile(y, stall), "the stall is placed")
	var third := _chain(c, y, 2, visited)
	if third.size() < 3:
		_expect(false, "two more roads can be laid beyond the stall")
		return
	var z: Vector3i = third[2]
	_expect(c.place_tile(z, watch), "the watch is placed")
	var stall_tile: TileInstance = c.world.structures[y]
	var post_tile: TileInstance = c.world.structures[x]

	# ---- rooms muster units, a few a segment, up to their cap
	_expect(c.allies.is_empty(), "no units until a segment's muster")
	c.muster_allies()
	_expect(c.allies_of(x) == 1 and c.allies_of(z) == 1, "each defensive room musters its units")
	c.muster_allies()
	_expect(c.allies_of(x) == 2 and c.allies_of(z) == 1, "the next segment adds more, up to each room's cap")
	c.muster_allies()
	_expect(c.allies_of(x) == 2 and c.allies_of(y) == 0, "a full room musters no more; a room with no ally musters none")
	_expect(c.allies_at(x).size() == 2 and c.allies_at(z).size() == 1, "units start at their room")

	# ---- a guard holds its own vertex
	c._add_raider(x, raider)
	c.raiders[0]["block"] = _fighter(engine, "Weakling", 1, 1)
	c._resolve_raids()
	_expect(c.raiders_at(x) == 0 and post_tile.health == post.max_health, "guards beat the raider at their room")
	_expect(c.allies_at(z).size() == 1, "the patrol stays home when its own roads are quiet")

	# ---- a patrol walks the roads to raiders elsewhere
	c._add_raider(y, raider)
	c.raiders[0]["block"] = _fighter(engine, "Weakling", 1, 1)
	c._resolve_raids()
	_expect(c.raiders_at(y) == 0 and stall_tile.health == 3, "a patrol defends a tile that has no guards")
	_expect(c.allies_at(y).size() == 1 and c.allies_at(z).is_empty(), "the patrol went to the raided vertex")

	# ---- but only as far as its range
	for a in c.allies:
		if int(a["behavior"]) == TileDef.AllyBehavior.PATROL:
			a["range"] = 1
	c._add_raider(y, raider)
	c.raiders[0]["block"] = _fighter(engine, "Weakling", 1, 1)
	c._resolve_raids()
	_expect(c.raiders_at(y) == 1 and stall_tile.health == 2, "a patrol with too short a range cannot reach the raid")
	_expect(c.allies_at(z).size() == 1, "it stays at its room")
	c.raiders.clear()

	# ---- the garrison rests, and is replenished
	var guard: Dictionary = c.allies_at(x)[0]
	var block: StatBlock = guard["block"]
	block.corpus = 1
	c._rest_allies()
	_expect(block.corpus == block.max_corpus(), "a new day heals the garrison")
	block.corpus = 0
	c.muster_allies()
	_expect(not c.allies.has(guard) and c.allies_of(x) == 2, "a fallen unit is replaced at the next muster")

	# ---- units are lost with their room
	c._damage_structure(z, 99)
	c.muster_allies()
	_expect(not c.world.has_structure(z) and c.allies_of(z) == 0, "when the room falls its units are lost")


# ------------------------------------------------------------ construction

func _test_construction() -> void:
	var red := _enemy(&"red", EnemyTemplate.NoteColor.RED)
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	gate.build_segments = 5  # the exit is never built, whatever it says
	var shed := _tile(&"shed", TileDef.Category.VILLAGE, {}, {CUTS: 2})
	shed.build_segments = 2
	var slow := _tile(&"slow", TileDef.Category.VILLAGE, {}, {CUTS: 5})
	slow.build_segments = 4
	var den := _tile(&"den", TileDef.Category.DUNGEON)
	den.enemies = [red]
	den.spawn_count = 2
	den.build_segments = 1
	var tent := _tile(&"tent", TileDef.Category.VILLAGE)
	tent.build_segments = 3

	var config := WorldConfig.new()
	config.require_blueprints = false
	config.require_segno = false
	config.board_radius = 3
	config.road_cost = {}
	config.starting_resources = {RED: 100, GREEN: 100, BLUE: 100}
	var c := HexDayCycle.new(gate, config, WorldPersistent.new(), 31)
	c.begin_run()
	var o := c.origin_vertex()
	var visited := {}
	var chain := _chain(c, o, 3, visited)
	var side := _chain(c, o, 1, visited)
	if chain.size() < 4 or side.size() < 2:
		_expect(false, "a chain of three roads and a spur can be laid")
		return

	_expect(c.build_time_of(shed) == 2 and c.build_time_of(gate) == 0 and c.build_time_of(c.origin_def) == 0, "a tile's build time is its own, except for the exit and origin")
	_expect(c.place_tile(chain[1], shed) and c.place_tile(chain[2], slow) and c.place_tile(chain[3], den), "rooms with a build time can be placed")
	var site := c.tile_at(chain[1])
	_expect(c.world.has_structure(chain[1]) and not site.is_built() and not site.is_live() and c.construction_left(chain[1]) == 2,
			"a placed room holds its vertex as a building site")
	_expect(c.distance_to_exit(chain[3]) == 3, "a building site still carries the road through it")
	_wake(c, [chain[3]])
	_expect(c.spawn_count_at(chain[3]) == 0, "a site gathers no enemies")

	# ---- a site can be abandoned
	_expect(c.place_tile(side[1], tent) and c.can_erase(side[1])["ok"] and c.erase_tile(side[1]) and not c.world.has_structure(side[1]),
			"a building site can be abandoned")

	# ---- dawn -> midday: the den's one segment is up, but it missed the dawn gathering
	c.begin_next_segment()
	_expect(c.segment == HexDayCycle.Segment.MIDDAY and c.tile_at(chain[3]).is_built() and c.tile_at(chain[3]).is_live(), "a site with one segment to build is finished by midday")
	_expect(c.gathered_at(chain[3]) == 0, "it finished too late to gather the dawn's enemies")
	_expect(c.construction_left(chain[1]) == 1 and c.construction_left(chain[2]) == 3, "other sites count down a segment at a time")
	_wake(c, [chain[3]])
	_expect(c.awake_borders(chain[3]).size() == 1 and c.spawn_count_at(chain[3]) == 2, "once built, the den gathers for the awake hex beside it")

	# ---- midday -> dusk
	c.begin_next_segment()
	_expect(c.gathered_at(chain[3]) == 2, "midday's enemies were gathered")
	_expect(c.tile_at(chain[1]).is_live() and c.construction_left(chain[2]) == 2, "the shed finishes at dusk")
	_expect(not c.can_erase(chain[1])["ok"], "a finished room can no longer be abandoned")

	# ---- dusk -> the next day: only the shed pays
	var report := c.begin_next_segment()
	_expect(c.day == 2 and int((report["income"] as Dictionary).get(CUTS, 0)) == 2, "only finished rooms earn income (got %s)" % str(report.get("income")))
	_expect(c.construction_left(chain[2]) == 1 and not c.tile_at(chain[2]).is_live(), "the slow site is still a site on day 2")
	c.begin_next_segment()
	_expect(c.construction_left(chain[2]) == 0 and c.tile_at(chain[2]).is_live(), "and is finished by midday of day 2")


# ------------------------------------------ exploration, wild enemies, the party

func _wild_config(templates: Array[EnemyTemplate]) -> WorldConfig:
	var config := WorldConfig.new()
	config.require_blueprints = false
	config.require_segno = false
	config.board_radius = 4
	config.road_cost = {}
	config.starting_resources = {}
	config.explore_vertices = true
	config.start_explored_radius = 0
	config.wild_enemies_enabled = true
	config.wild_density = 1.0
	config.wild_group_min = 1
	config.wild_group_max = 1
	config.wild_safe_radius = 1
	config.wild_templates = templates
	return config


func _test_exploration_and_wild() -> void:
	var gate := _tile(&"gate", TileDef.Category.DUNGEON)
	gate.is_exit = true
	var shed := _tile(&"shed", TileDef.Category.VILLAGE)
	var grunt := _enemy(&"grunt", EnemyTemplate.NoteColor.NONE)
	var grunts: Array[EnemyTemplate] = [grunt]
	var engine := RulesEngine.new(null, 4242)
	engine.load_stat_defs("res://Systems/Rules/Data/Stats")

	var c := HexDayCycle.new(gate, _wild_config(grunts), WorldPersistent.new(), 77)
	c.combat_engine = engine
	c.begin_run()
	var wild_keys: Array = c.wild.keys()
	var o := c.origin_vertex()
	var ring: Array[Vector3i] = HexGrid.vertex_neighbours(o)
	var n: Vector3i = ring[0]
	var onward: Array[Vector3i] = []
	for x: Vector3i in HexGrid.vertex_neighbours(n):
		if x != o and c.world.has_vertex(x):
			onward.append(x)
	if onward.size() < 2:
		_expect(false, "two vertices lie beyond the first step")
		return
	var w: Vector3i = onward[0]
	var w2: Vector3i = onward[1]
	var e1 := _road_between(o, n)
	var e2 := _road_between(n, w)

	# ---- exploration
	_expect(c.world.vertex_fog and c.world.is_explored(o) and c.world.explored.size() == 1, "only the origin is explored at the start")
	_expect(not c.world.is_explored(n) and not c.world.is_explored(w), "everything else starts unexplored")
	_expect(c.is_frontier_edge(e1) and c.unexplored_end(e1) == n, "an edge from the explored to the unexplored is a frontier edge")
	_expect(not c.is_frontier_edge(e2), "an edge between two unexplored vertices is not")
	_expect(c.frontier_edges().size() == 3, "the origin has three frontier edges (got %d)" % c.frontier_edges().size())
	_expect(not c.can_build_road(e1)["ok"], "no road runs to a vertex nobody has explored")
	_expect(c.world.explore(n) and not c.world.explore(n), "a vertex is explored once")
	_expect(c.world.is_revealed(c.world.hexes_at(n)[0]), "exploring a vertex reveals the hexes at its corners")
	_expect(not c.is_frontier_edge(e1) and c.is_frontier_edge(e2), "the frontier moves outward as vertices are explored")
	_expect(c.known_edges().size() == 1 and c.known_edges()[0] == e1, "an edge with both ends explored is a known edge")
	_expect(c.can_build_road(e1)["ok"] and c.build_road(e1), "a road to an explored vertex can be built")

	# ---- wild enemies hold ground
	_expect(not c.has_wild(o) and not c.has_wild(n) and c.has_wild(w), "wild enemies keep clear of the origin's surroundings and fill the rest")
	c.world.explore(w)
	var wild_road := c.can_build_road(e2)
	_expect(not wild_road["ok"] and String(wild_road["reason"]).contains("Wild"), "a road cannot end on wild enemies")
	_expect(c.world.build_road(e2), "(the road is laid directly, to test the room rule)")
	var blocked := c.can_place(w, shed)
	_expect(not blocked["ok"] and String(blocked["reason"]).contains("Wild"), "a room cannot be built on wild enemies")

	# ---- the party walks and fights
	var hero := _fighter(engine, "Hero", 5, 500, 18)
	c.set_party([hero])
	_expect(c.party_vertex == o and c.party_moves_left == 6, "the party starts on the origin with a segment's moves")
	_expect(c.move_party(w).is_empty(), "the party cannot jump two vertices")
	var r1 := c.move_party(n)
	_expect(not r1.is_empty() and not bool(r1["fought"]) and c.party_vertex == n and c.party_moves_left == 5, "the party steps to a neighbouring vertex")
	var r2 := c.move_party(w)
	_expect(not r2.is_empty() and bool(r2["fought"]) and r2["result"] == HexDayCycle.FightResult.WON, "walking into wild enemies is a fight, and the hero wins it")
	_expect(not c.has_wild(w) and c.party_vertex == w, "the cleared vertex is open and the party stands on it")
	_expect(int(c.party_loot.get(GREY, 0)) == 4 and int(c.stock.get(GREY, 0)) == 0, "loot is carried, not banked, away from the origin")
	_expect(c.can_place(w, shed)["ok"] and c.place_tile(w, shed), "a cleared vertex can be built on")
	c.move_party(n)
	c.move_party(o)
	_expect(int(c.stock.get(GREY, 0)) == 4 and c.party_loot.is_empty(), "the loot is banked when the party reaches the origin")
	_expect(c.party_moves_left == 2, "each step cost a move (got %d left)" % c.party_moves_left)

	# ---- travel through the dark, by way of a frontier edge
	_expect(c.is_frontier_edge(_road_between(n, w2)) and c.unexplored_end(_road_between(n, w2)) == w2, "the edge to the other unexplored neighbour is a frontier edge")
	var trip := c.can_travel_to(w2)
	_expect(trip["ok"] and int(trip["steps"]) == 2, "the party can walk two explored steps into the dark")
	var r3 := c.travel_party(w2)
	_expect(c.world.is_explored(w2) and not c.has_wild(w2) and c.party_vertex == w2, "travelling explores the far vertex and clears what was there")
	_expect(c.party_moves_left == 0 and not c.can_travel_to(n)["ok"], "with no moves left, the party stays put")
	_expect(not r3.is_empty() and bool(r3["fought"]), "travel stops at a fight")
	c.begin_next_segment()
	_expect(c.party_moves_left == 6, "moves refill as a new segment begins")

	# ---- the same board every time for one seed
	var twin := HexDayCycle.new(gate, _wild_config(grunts), WorldPersistent.new(), 77)
	twin.begin_run()
	var same := twin.wild.size() == wild_keys.size()
	for k in wild_keys:
		same = same and twin.wild.has(k)
	_expect(same, "one seed scatters wild enemies the same way")

	# ---- a party that loses is sent home with nothing
	var ogre := _enemy(&"ogre", EnemyTemplate.NoteColor.NONE)
	ogre.level = 6
	ogre.corpus_die = 20
	var ogres: Array[EnemyTemplate] = [ogre]
	var d := HexDayCycle.new(gate, _wild_config(ogres), WorldPersistent.new(), 77)
	d.combat_engine = engine
	d.begin_run()
	d.set_party([_fighter(engine, "Weak", 1, 1, 3)])
	d.move_party(n)
	var lost := d.move_party(w)
	_expect(not lost.is_empty() and lost["result"] == HexDayCycle.FightResult.WIPED, "a party that cannot win is wiped out")
	_expect(d.party_vertex == o and d.party_loot.is_empty() and d.party_moves_left == 0 and d.has_wild(w), "and wakes at the origin, empty-handed, with the enemies still there")

	# ---- the options that turn all of this off
	var endless_config := _wild_config(grunts)
	endless_config.infinite_board = true
	var endless := HexDayCycle.new(gate, endless_config, WorldPersistent.new(), 77)
	endless.begin_run()
	_expect(endless.wild.is_empty(), "an endless board gets no wild enemies")
	var plain_config := WorldConfig.new()
	plain_config.require_segno = false
	var plain := HexDayCycle.new(gate, plain_config, WorldPersistent.new(), 77)
	plain.begin_run()
	_expect(not plain.world.vertex_fog and plain.frontier_edges().is_empty() and plain.wild.is_empty(), "with the options off there is no fog and no wild enemies")


# ----------------------------------------------------------------- helpers

## Wakes the first hex beside each of the vertices in `rooms`.
func _wake(c: HexDayCycle, rooms: Array) -> void:
	var woken: Array[Vector2i] = []
	for room: Vector3i in rooms:
		woken.append(c.world.hexes_at(room)[0])
	c.set_awake(woken)


## Wakes exactly `woken`, runs a whole expedition that lays every enemy to rest, and
## begins the next day. Returns the day's enemies.
func _run_day(c: HexDayCycle, woken: Array[Vector2i]) -> Array[Dictionary]:
	c.set_awake(woken)
	var spawns := c.start_expedition()
	for s in spawns:
		c.record_kill(s["id"])
	c.return_to_exit()
	c.begin_next_day()
	return spawns

## Builds up to `steps` roads in a chain from `start`, never touching a vertex already in
## `visited` and never running next to one other than the one it just left, so chains
## neither loop nor crowd each other. Returns the vertices walked, `start` first.
func _chain(c: HexDayCycle, start: Vector3i, steps: int, visited: Dictionary) -> Array[Vector3i]:
	var walked: Array[Vector3i] = [start]
	visited[start] = true
	var cur := start
	for _i in steps:
		var moved := false
		for e in HexGrid.vertex_edges(cur):
			if not c.world.has_edge(e) or c.world.has_road(e):
				continue
			var nxt := _other_end(e, cur)
			if visited.has(nxt) or _crowded(nxt, cur, visited):
				continue
			if not c.build_road(e):
				continue
			visited[nxt] = true
			walked.append(nxt)
			cur = nxt
			moved = true
			break
		if not moved:
			break
	return walked


func _crowded(v: Vector3i, came_from: Vector3i, visited: Dictionary) -> bool:
	for near in HexGrid.vertex_neighbours(v):
		if near != came_from and visited.has(near):
			return true
	return false


func _other_end(e: Vector3i, v: Vector3i) -> Vector3i:
	var ends := HexGrid.edge_ends(e)
	return ends[1] if ends[0] == v else ends[0]


## The edge joining two neighbouring vertices.
func _road_between(u: Vector3i, v: Vector3i) -> Vector3i:
	for e in HexGrid.vertex_edges(u):
		if HexGrid.edge_ends(e).has(v):
			return e
	return HexGrid.NONE


func _enemy(id: StringName, note_color: EnemyTemplate.NoteColor, notes := 4) -> EnemyTemplate:
	var template := EnemyTemplate.new()
	template.display_name = String(id)
	template.level = 1
	template.note_color = note_color
	template.notes_per_kill = notes
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
	push_error("[hexday] FAIL: " + message)
	print("[hexday] FAIL: ", message)
