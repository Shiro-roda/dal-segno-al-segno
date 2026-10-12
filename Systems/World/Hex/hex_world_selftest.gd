extends Node
## Self-test for the hex board. Run hex_world_selftest.tscn and read the output.

var _failures := 0
var _checks := 0


func _ready() -> void:
	_test_counts()
	_test_consistency()
	_test_geometry()
	_test_terrain()
	_test_roads_and_structures()
	_test_doors()
	_test_main_path()
	_test_numbers()
	_test_open_spots()
	_test_single_hex()
	_test_fog_and_signals()
	print("[hex] %d checks, %d failures." % [_checks, _failures])
	if _failures == 0:
		print("[hex] ALL PASSED")


# ------------------------------------------------------------------- counts

func _test_counts() -> void:
	for r: int in [0, 1, 2, 3]:
		var w := HexWorld.new()
		w.generate(r, 1)
		_expect(w.hex_count() == 3 * r * r + 3 * r + 1, "radius %d has 3r^2+3r+1 hexes (got %d)" % [r, w.hex_count()])
		_expect(w.vertices().size() == 6 * (r + 1) * (r + 1), "radius %d has 6(r+1)^2 vertices (got %d)" % [r, w.vertices().size()])
		_expect(w.edges().size() == 9 * r * r + 15 * r + 6, "radius %d has 9r^2+15r+6 edges (got %d)" % [r, w.edges().size()])
	var catan := HexWorld.new()
	catan.generate(2, 1)
	_expect(catan.hex_count() == 19 and catan.vertices().size() == 54 and catan.edges().size() == 72,
			"radius 2 is the standard Catan board: 19 hexes, 54 vertices, 72 edges")
	_expect(not catan.has_vertex(Vector3i(50, 50, 0)) and not catan.has_edge(Vector3i(50, 50, 0)) and not catan.has_hex(Vector2i(50, 50)),
			"keys far from the board are not on it")


# -------------------------------------------------------------- consistency

## Every adjacency question must give the same answer from both directions.
func _test_consistency() -> void:
	var w := HexWorld.new()
	w.generate(3, 1)
	var hexes := HexGrid.hexes_in_radius(3)

	var bad_edge_count := 0
	var bad_vertex_end := 0
	var bad_symmetry := 0
	var bad_vertex_hex := 0
	var degree_sum := 0
	for v in w.vertices():
		var es := HexGrid.vertex_edges(v)
		if _distinct(es) != 3:
			bad_edge_count += 1
		for e in es:
			if not HexGrid.edge_ends(e).has(v):
				bad_vertex_end += 1
			if w.has_edge(e):
				degree_sum += 1
		var near := HexGrid.vertex_neighbours(v)
		if _distinct(near) != 3:
			bad_edge_count += 1
		for n in near:
			if not HexGrid.vertex_neighbours(n).has(v):
				bad_symmetry += 1
		var around := HexGrid.vertex_hexes(v)
		if _distinct(around) != 3:
			bad_vertex_hex += 1
		for h in around:
			if not HexGrid.hex_corners(h).has(v):
				bad_vertex_hex += 1
	_expect(bad_edge_count == 0, "every vertex has three distinct edges and three distinct neighbours (%d bad)" % bad_edge_count)
	_expect(bad_vertex_end == 0, "every edge at a vertex has that vertex as an end (%d bad)" % bad_vertex_end)
	_expect(bad_symmetry == 0, "vertex adjacency is symmetric (%d bad)" % bad_symmetry)
	_expect(bad_vertex_hex == 0, "every hex at a vertex has it as a corner (%d bad)" % bad_vertex_hex)
	_expect(degree_sum == 2 * w.edges().size(), "each board edge is counted by exactly two vertices (%d vs %d)" % [degree_sum, 2 * w.edges().size()])

	var bad_ends := 0
	var bad_edge_hex := 0
	var bad_neighbours := 0
	for e in w.edges():
		var ends := HexGrid.edge_ends(e)
		if ends[0] == ends[1]:
			bad_ends += 1
		for end in ends:
			if not HexGrid.vertex_edges(end).has(e):
				bad_ends += 1
		for h in HexGrid.edge_hexes(e):
			if not HexGrid.hex_edges(h).has(e):
				bad_edge_hex += 1
			for end in ends:
				if not HexGrid.hex_corners(h).has(end):
					bad_edge_hex += 1
		if _distinct(HexGrid.edge_neighbours(e)) != 4:
			bad_neighbours += 1
	_expect(bad_ends == 0, "every edge has two distinct ends that list it back (%d bad)" % bad_ends)
	_expect(bad_edge_hex == 0, "an edge's hexes both own it and both have its ends as corners (%d bad)" % bad_edge_hex)
	_expect(bad_neighbours == 0, "every edge has four distinct neighbouring edges (%d bad)" % bad_neighbours)

	var bad_hex := 0
	for h in hexes:
		var corners := HexGrid.hex_corners(h)
		var sides := HexGrid.hex_edges(h)
		if _distinct(corners) != 6 or _distinct(sides) != 6:
			bad_hex += 1
		# Consecutive corners are joined by one of the hex's own edges.
		for k in 6:
			var a := corners[k]
			var b := corners[(k + 1) % 6]
			var joined := false
			for e in sides:
				var ends := HexGrid.edge_ends(e)
				if ends.has(a) and ends.has(b):
					joined = true
			if not joined:
				bad_hex += 1
		# So each corner lies on exactly two of its sides.
		for c in corners:
			var touching := 0
			for e in sides:
				if HexGrid.edge_ends(e).has(c):
					touching += 1
			if touching != 2:
				bad_hex += 1
	_expect(bad_hex == 0, "each hex is a closed ring of six corners and six sides (%d bad)" % bad_hex)

	var bad_step := 0
	for h in hexes:
		for side in 6:
			var n := HexGrid.hex_neighbour(h, side)
			if HexGrid.hex_neighbour(n, HexGrid.opposite_side(side)) != h or HexGrid.hex_distance(h, n) != 1:
				bad_step += 1
			if not HexGrid.edge_hexes(HexGrid.edge(h, side)).has(n):
				bad_step += 1
	_expect(bad_step == 0, "the other side of a side is the neighbouring hex (%d bad)" % bad_step)


# ----------------------------------------------------------------- geometry

func _test_geometry() -> void:
	var size := 10.0
	var w := HexWorld.new()
	w.generate(2, 1)

	# The corner table must put each vertex where the hex's own corner really is.
	var bad_corner := 0
	for h in HexGrid.hexes_in_radius(2):
		var c := HexGrid.hex_center(h, size)
		for k in 6:
			var a := deg_to_rad(60.0 * k - 90.0)
			var want := c + Vector2(cos(a), sin(a)) * size
			if HexGrid.vertex_pos(HexGrid.corner(h, k), size).distance_to(want) > 0.001:
				bad_corner += 1
	_expect(bad_corner == 0, "corners sit at 60 degree steps from north (%d bad)" % bad_corner)

	var bad_length := 0
	for v in w.vertices():
		for n in HexGrid.vertex_neighbours(v):
			if absf(HexGrid.vertex_pos(v, size).distance_to(HexGrid.vertex_pos(n, size)) - size) > 0.001:
				bad_length += 1
	_expect(bad_length == 0, "every road is one hex-side long (%d bad)" % bad_length)

	var bad_mid := 0
	for e in w.edges():
		var hs := HexGrid.edge_hexes(e)
		var between := (HexGrid.hex_center(hs[0], size) + HexGrid.hex_center(hs[1], size)) * 0.5
		if HexGrid.edge_pos(e, size).distance_to(between) > 0.001:
			bad_mid += 1
	_expect(bad_mid == 0, "an edge's midpoint is halfway between its two hexes (%d bad)" % bad_mid)

	var bad_pick := 0
	for h in HexGrid.hexes_in_radius(2):
		if HexGrid.pixel_to_hex(HexGrid.hex_center(h, size) + Vector2(3.0, 2.0), size) != h:
			bad_pick += 1
	for v in w.vertices():
		if HexGrid.nearest_vertex(HexGrid.vertex_pos(v, size) + Vector2(1.5, -1.0), size) != v:
			bad_pick += 1
	for e in w.edges():
		if HexGrid.nearest_edge(HexGrid.edge_pos(e, size) + Vector2(1.0, 0.5), size) != e:
			bad_pick += 1
	_expect(bad_pick == 0, "points near a hex, vertex or edge pick it (%d bad)" % bad_pick)


# ------------------------------------------------------------------ terrain

func _test_terrain() -> void:
	var a := HexWorld.new()
	var b := HexWorld.new()
	var c := HexWorld.new()
	a.generate(2, 11)
	b.generate(2, 11)
	c.generate(2, 12)
	_expect(a.terrain == b.terrain, "the same seed deals the same board")
	_expect(a.terrain != c.terrain, "another seed deals another board")

	var counts := {}
	for hex in a.hexes():
		var kind := a.terrain_at(hex)
		counts[kind] = int(counts.get(kind, 0)) + 1
	_expect(counts.size() == 4, "all four terrains appear on a radius 2 board")
	_expect(a.terrain_at(Vector2i(9, 9)) == -1, "an off-board hex has no terrain")

	var origin := HexGrid.corner(Vector2i.ZERO, 0)
	_expect(a.terrains_at(origin).size() == 3 and a.hexes_at(origin).size() == 3, "an inner vertex touches three hexes")
	var rim := HexGrid.corner(Vector2i(2, 0), 1)
	_expect(a.has_vertex(rim) and a.hexes_at(rim).size() < 3, "a vertex on the coast touches fewer than three")


# ------------------------------------------------- roads and structures

func _test_roads_and_structures() -> void:
	var w := HexWorld.new()
	w.generate(2, 3)
	var origin := HexGrid.corner(Vector2i.ZERO, 0)
	var first := HexGrid.vertex_edges(origin)[0]

	_expect(not w.can_build_road(first)["ok"], "no road before the world is founded")
	_expect(not w.place_origin(Vector3i(50, 50, 0)), "the origin must be on the board")
	_expect(w.place_origin(origin) and w.origin == origin and w.has_structure(origin), "the origin is placed freely")
	_expect(not w.place_origin(HexGrid.corner(Vector2i.ZERO, 3)), "there is only one origin")

	var far_edge: Vector3i = w.edges().back()
	_expect(not w.can_build_road(far_edge)["ok"], "a road away from the network is refused")
	_expect(not w.can_build_road(Vector3i(50, 50, 0))["ok"], "a road off the board is refused")
	_expect(not w.can_build_structure(HexGrid.vertex_neighbours(origin)[0])["ok"], "a structure needs a road leading to it")

	_expect(w.build_road(first) and w.has_road(first), "a road can leave the origin")
	_expect(not w.build_road(first), "a road cannot be built twice")

	var a := _other_end(first, origin)
	w.distance_rule = true
	_expect(not w.can_build_structure(a)["ok"], "the distance rule keeps structures a road apart")
	var second := _edge_from(w, a, first)
	_expect(w.build_road(second), "a road can extend from another road")
	var b := _other_end(second, a)
	_expect(w.can_build_structure(b)["ok"], "two roads out, a structure may stand")
	_expect(w.build_structure(b, "room") and w.structure_at(b) == "room", "a structure keeps what it was given")
	_expect(not w.build_structure(b), "a vertex holds one structure")

	w.distance_rule = false
	_expect(w.can_build_structure(a)["ok"], "without the distance rule a structure may stand where one road ends")
	w.distance_rule = true

	var reach := w.reachable_from(origin)
	_expect(reach.has(origin) and reach.has(a) and reach.has(b) and reach.size() == 3, "roads connect exactly the vertices they touch")
	_expect(not w.is_cut_off(b), "a structure on the network is not cut off")
	_expect(w.road_graph().size() == 3, "the road graph lists the three vertices roads touch")

	_expect(w.remove_road(first) and not w.has_road(first), "a road can be removed")
	_expect(w.is_cut_off(b) and not w.connected_to_origin().has(b), "a structure behind a removed road is cut off")
	_expect(not w.is_cut_off(origin), "the origin is never cut off")
	_expect(not w.remove_structure(origin), "the origin cannot be removed")
	_expect(w.remove_structure(b) and not w.has_structure(b), "other structures can be removed")


# --------------------------------------------------------------------- doors

func _test_doors() -> void:
	var w := HexWorld.new()
	w.generate(2, 3)
	var origin := HexGrid.corner(Vector2i.ZERO, 0)
	w.place_origin(origin)
	_expect(w.door_count(origin) == 0 and w.doors_at(origin).is_empty(), "a room with no road has no doors")
	_expect(w.doors_at(Vector3i(50, 50, 0)).is_empty(), "an off-board vertex has no doors")

	var first := HexGrid.vertex_edges(origin)[0]
	w.build_road(first)
	var a := _other_end(first, origin)
	_expect(w.door_count(origin) == 1 and w.door_count(a) == 1, "a road is a door at each of its ends")
	var door := w.doors_at(origin)[0]
	_expect(door["edge"] == first and door["to"] == a and door["slot"] == 0, "the door names its road, its far end and its slot")
	_expect(w.door_destination(origin, 0) == a, "going through a door leads to the far end of the road")
	_expect(w.door_destination(origin, 1) == HexWorld.NO_VERTEX, "a slot with no road has no destination")

	var back := w.arrival_slot(origin, a)
	_expect(back >= 0 and w.door_destination(a, back) == origin, "the arrival door leads back where you came from")
	_expect(w.arrival_slot(origin, HexGrid.corner(Vector2i(2, 0), 1)) == -1, "unjoined vertices have no arrival door")

	# Fill every road at the origin: three doors is the most a room can have.
	for e in HexGrid.vertex_edges(origin):
		if w.has_edge(e):
			w.build_road(e)
	_expect(w.door_count(origin) == 3, "an inner room can have three doors (got %d)" % w.door_count(origin))
	var slots_ok := true
	var destinations := {}
	var last_slot := -1
	for d in w.doors_at(origin):
		slots_ok = slots_ok and d["slot"] > last_slot and HexGrid.vertex_edges(origin)[d["slot"]] == d["edge"]
		last_slot = d["slot"]
		destinations[d["to"]] = true
	_expect(slots_ok, "doors are ordered by slot and each slot is the edge's place at the vertex")
	_expect(destinations.size() == 3, "the three doors lead to three different rooms")

	w.remove_road(first)
	_expect(w.door_count(origin) == 2 and w.door_destination(origin, 0) == HexWorld.NO_VERTEX, "removing a road closes its door")


# ---------------------------------------------------------------- main path

func _test_main_path() -> void:
	var w := HexWorld.new()
	w.generate(2, 3)
	var origin := HexGrid.corner(Vector2i.ZERO, 0)
	w.place_origin(origin)
	var first := HexGrid.vertex_edges(origin)[0]
	w.build_road(first)
	var a := _other_end(first, origin)
	var second := _edge_from(w, a, first)
	w.build_road(second)
	var b := _other_end(second, a)
	# A spur off the middle vertex that never rejoins.
	var spur := HexGrid.NONE
	for e in HexGrid.vertex_edges(a):
		if e != first and e != second and w.has_edge(e):
			spur = e
	_expect(spur != HexGrid.NONE and w.build_road(spur), "a side road can leave the middle of the chain")
	var spur_end := _other_end(spur, a)
	var graph := w.road_graph()

	var chain := HexMainPath.find(graph, b, origin)
	_expect(bool(chain["found"]) and int(chain["steps"]) == 2 and int(chain["loops"]) == 0, "a chain's main path runs its whole length with no loops")
	_expect((chain["path"] as Array)[0] == b and (chain["path"] as Array).back() == origin, "the path runs from the Segno to the exit")
	_expect((chain["on_path"] as Dictionary).size() == 3 and not (chain["on_path"] as Dictionary).has(spur_end), "a side road is off the path and costs no loop")
	_expect(not bool(chain["capped"]), "a small network is searched in full")
	_expect(HexMainPath.reachable(graph, origin).size() == 4, "all four road vertices are reachable from the exit")

	var rim := HexGrid.corner(Vector2i(2, 0), 1)
	_expect(not bool(HexMainPath.find(graph, rim, origin)["found"]), "no path from a vertex no road touches")
	_expect(HexMainPath.reachable(graph, rim).is_empty(), "nothing is reachable from a vertex no road touches")
	_expect((HexMainPath.find(graph, origin, origin)["path"] as Array).size() == 1, "a start that is the exit is a path of one vertex")
	_expect(bool(HexMainPath.find(graph, b, origin, 1)["capped"]), "a tiny step budget reports that it ran out")

	# A ring of roads round one hex has two ways between any pair of corners.
	var ring_world := HexWorld.new()
	ring_world.generate(2, 3)
	ring_world.place_origin(origin)
	for _pass in 6:
		for e in HexGrid.hex_edges(Vector2i.ZERO):
			ring_world.build_road(e)
	_expect(ring_world.roads.size() == 6, "the ring has six roads (got %d)" % ring_world.roads.size())
	var ring := ring_world.road_graph()
	var corners := HexGrid.hex_corners(Vector2i.ZERO)

	var near := HexMainPath.find(ring, corners[1], corners[0])
	_expect(int(near["steps"]) == 5 and (near["path"] as Array).size() == 6, "the longest way round beats the one-road shortcut")
	_expect(int(near["loops"]) == 1, "the shortcut road is a chord, so one loop (got %d)" % int(near["loops"]))

	var far := HexMainPath.find(ring, corners[0], corners[3])
	_expect(int(far["steps"]) == 3, "between opposite corners either way is three roads (got %d)" % int(far["steps"]))
	_expect(int(far["loops"]) == 1, "the unused arc meets the path twice, so one loop (got %d)" % int(far["loops"]))

	_expect(is_equal_approx(HexMainPath.bonus(5, 1, 0.1, 0.25), 0.25), "the bonus is per step minus per loop")
	_expect(HexMainPath.bonus(1, 10, 0.1, 0.5) == 0.0, "the bonus never goes below zero")


# ------------------------------------------------------------------ numbers

func _test_numbers() -> void:
	var w := HexWorld.new()
	w.generate(3, 5)
	_expect(w.numbers.size() == w.hex_count(), "every hex carries a number")
	var valid := true
	for hex in w.numbers:
		var n: int = w.numbers[hex]
		valid = valid and n >= 2 and n <= 12 and n != 7
	_expect(valid, "numbers run from 2 to 12 and are never 7")

	var again := HexWorld.new()
	again.generate(3, 5)
	_expect(again.numbers == w.numbers and again.terrain == w.terrain, "a seed always gives the same numbers and terrain")
	var other := HexWorld.new()
	other.generate(3, 6)
	_expect(other.numbers != w.numbers, "another seed deals other numbers")

	var found := 0
	for n in range(2, 13):
		found += w.hexes_with_number(n).size()
	_expect(found == w.hex_count() and w.hexes_with_number(7).is_empty(), "every hex is found under its own number, and none under 7")

	var single := HexWorld.new()
	single.generate(0, 1)
	_expect(single.numbers.size() == 1, "even a lone hex carries a number")
	w.generate(3, 5)
	_expect(w.numbers == again.numbers, "generating again with the same seed deals the same numbers")

	# ---- which hexes a vertex touches
	var around_ok := true
	var counts_ok := true
	var coast := false
	for hex in w.hexes():
		for corner in HexGrid.hex_corners(hex):
			around_ok = around_ok and w.hexes_at(corner).has(hex)
	for v in w.vertices():
		var touching := w.hexes_at(v).size()
		counts_ok = counts_ok and touching >= 1 and touching <= 3
		coast = coast or touching < 3
	_expect(around_ok, "each hex is among the hexes at each of its corners")
	_expect(counts_ok and coast, "a vertex touches one to three board hexes, fewer on the coast")
	_expect(w.hexes_at(HexGrid.corner(Vector2i.ZERO, 0)).size() == 3, "a corner of the middle hex touches three hexes")
	_expect(w.hexes_at(Vector3i(50, 50, 0)).is_empty(), "a vertex off the board touches no hexes")


# -------------------------------------------------------------- open spots

func _test_open_spots() -> void:
	var w := HexWorld.new()
	_expect(not w.distance_rule, "structures may stand next to each other unless the distance rule is switched on")
	w.generate(2, 3)
	w.distance_rule = true
	var origin := HexGrid.corner(Vector2i.ZERO, 0)
	_expect(w.open_road_spots().is_empty() and w.open_structure_spots().is_empty(), "nothing can be built before the world is founded")
	w.place_origin(origin)
	_expect(w.open_road_spots().size() == 3, "from the origin alone, three roads can start (got %d)" % w.open_road_spots().size())
	_expect(w.open_structure_spots().is_empty(), "with no road, no structure can be built")
	w.build_road(HexGrid.vertex_edges(origin)[0])
	_expect(w.open_road_spots().size() == 4, "one road leaves four places to build another (got %d)" % w.open_road_spots().size())
	_expect(w.open_structure_spots().is_empty(), "the road's end is too close to the origin")
	w.distance_rule = false
	_expect(w.open_structure_spots().size() == 1, "without the distance rule the road's end is open")


## One hex has a coast all round: roads can run out along the rim of the board.
func _test_single_hex() -> void:
	var w := HexWorld.new()
	w.generate(0, 1)
	var origin := HexGrid.corner(Vector2i.ZERO, 0)
	w.place_origin(origin)
	var built := 0
	while true:
		var spots := w.open_road_spots()
		if spots.is_empty():
			break
		w.build_road(spots[0])
		built += 1
	_expect(built == 6 and w.roads.size() == 6, "roads can ring a lone hex, six in all (got %d)" % built)
	_expect(w.open_structure_spots().size() == 5, "with no distance rule, every corner but the origin is open (got %d)" % w.open_structure_spots().size())
	w.distance_rule = true
	_expect(w.open_structure_spots().size() == 3, "with the distance rule, three corners stay open around a ring (got %d)" % w.open_structure_spots().size())


# --------------------------------------------------------- fog and signals

func _test_fog_and_signals() -> void:
	var w := HexWorld.new()
	w.generate(2, 3)
	var origin := HexGrid.corner(Vector2i.ZERO, 0)
	var first := HexGrid.vertex_edges(origin)[0]
	_expect(not w.is_revealed(Vector2i.ZERO), "fog hides every hex at first")

	var hits := [0, 0, 0]
	w.structure_changed.connect(func(_v: Vector3i) -> void: hits[0] += 1)
	w.road_changed.connect(func(_e: Vector3i) -> void: hits[1] += 1)
	w.revealed_changed.connect(func() -> void: hits[2] += 1)

	w.place_origin(origin)
	_expect(w.revealed.size() == 3 and w.is_revealed(Vector2i.ZERO), "founding reveals the three hexes around it")
	w.build_road(first)
	_expect(w.revealed.size() == 3, "a road between hexes already seen reveals nothing new")
	var a := _other_end(first, origin)
	var second := _edge_from(w, a, first)
	w.build_road(second)
	_expect(w.revealed.size() == 4, "a road that borders a new hex reveals it (got %d)" % w.revealed.size())
	_expect(not w.is_revealed(Vector2i(9, 9)), "off-board hexes are never revealed")
	_expect(hits[0] == 1 and hits[1] == 2 and hits[2] == 2, "signals fire once per change (got %s)" % str(hits))
	w.fog = false
	_expect(w.is_revealed(Vector2i(-2, 2)) and not w.is_revealed(Vector2i(9, 9)), "with fog off every board hex shows")


# ----------------------------------------------------------------- helpers

func _other_end(e: Vector3i, v: Vector3i) -> Vector3i:
	var ends := HexGrid.edge_ends(e)
	return ends[1] if ends[0] == v else ends[0]


## A board edge at `v` other than `skip`.
func _edge_from(w: HexWorld, v: Vector3i, skip: Vector3i) -> Vector3i:
	for e in HexGrid.vertex_edges(v):
		if e != skip and w.has_edge(e):
			return e
	return HexGrid.NONE


func _distinct(items: Array) -> int:
	var seen := {}
	for item in items:
		seen[item] = true
	return seen.size()


func _expect(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("[hex] FAIL: ", message)
