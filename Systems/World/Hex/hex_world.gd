class_name HexWorld
extends RefCounted
## The shared world plane: terrain on hexes, structures on vertices, roads on edges. Pure
## data and rules, no scenes. Geometry and adjacency live in HexGrid.
##
## Expansion works like Catan's, for a single owner:
##   - the world starts with one structure, the origin, placed freely;
##   - a ROAD may be built on any edge that touches a structure or another road;
##   - a STRUCTURE may be built on any vertex where a road ends (and, with distance_rule
##     on, not next to another structure, so rooms are always at least one road apart).
## `structures` and `roads` store whatever the caller wants to attach (a TileInstance,
## say); this class only cares which keys are present.
##
## Hexes start hidden when `fog` is on. Founding or building reveals the hexes around it.

signal structure_changed(vertex: Vector3i)
signal road_changed(edge: Vector3i)
signal revealed_changed
## A vertex was explored.
signal explored_changed

## What a hex is made of. Meant to bias the colour of rooms built on its corners.
enum Terrain { NEUTRAL, RED, GREEN, BLUE }

## Relative frequency of each terrain when a board is generated.
const DEFAULT_WEIGHTS := {
	Terrain.NEUTRAL: 1,
	Terrain.RED: 2,
	Terrain.GREEN: 2,
	Terrain.BLUE: 2,
}

const NO_VERTEX := HexGrid.NONE

## The dice numbers dealt to hexes, Catan's token set. There is no 7: it is kept free for
## rival raids later, as Catan keeps it for the robber.
const TOKENS: Array[int] = [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12]

var radius := 0
## An endless plane: every hex exists, and its terrain and number come from the seed alone.
## The terrain and numbers dictionaries then only cache the hexes that have been looked at.
var infinite := false
var _seed := 0
var _terrain_cycle: Array[int] = []
## Vector2i -> Terrain. Its keys are the hexes on the board (when infinite, the ones seen).
var terrain: Dictionary = {}
## Vector2i -> int, 2 to 12 and never 7. A hex wakes on the dawn roll that matches it.
var numbers: Dictionary = {}
## Vector3i vertex -> whatever the caller stored.
var structures: Dictionary = {}
## Vector3i edge -> whatever the caller stored.
var roads: Dictionary = {}
## The vertex of the founding structure, or NO_VERTEX before one is placed.
var origin := NO_VERTEX
## No two structures on neighbouring vertices (Catan's distance rule).
var distance_rule := false
## Hide hexes until something built touches them.
var fog := true
## Vector2i -> true. The hexes the player has uncovered.
var revealed: Dictionary = {}
## Per-vertex exploration. On: a vertex must be explored before anything can be built on it
## or a road laid to it, and hexes only reveal as their corners are explored. Off by
## default so the hex-level fog above is all that applies.
var vertex_fog := false
## Vector3i -> true. The vertices that have been explored.
var explored: Dictionary = {}

var _vertices: Array[Vector3i] = []
var _edges: Array[Vector3i] = []
var _vertex_set := {}
var _edge_set := {}


# ---------------------------------------------------------------- generation

## Lays out a hexagonal board of `p_radius` and deals terrain. The same seed always gives
## the same board; a negative seed picks one at random. `weights` is Terrain -> relative
## frequency. Clears anything already built.
func generate(p_radius: int, seed_value := -1, weights: Dictionary = DEFAULT_WEIGHTS) -> void:
	radius = maxi(0, p_radius)
	infinite = false
	terrain.clear()
	numbers.clear()
	structures.clear()
	roads.clear()
	revealed.clear()
	explored.clear()
	origin = NO_VERTEX
	var board := HexGrid.hexes_in_radius(radius)
	_index(board)

	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	var cycle: Array[int] = []
	for kind in weights:
		for _i in maxi(0, int(weights[kind])):
			cycle.append(int(kind))
	if cycle.is_empty():
		cycle.append(Terrain.NEUTRAL)
	# A shuffled bag, so the mix stays close to the weights even on a small board.
	var bag: Array[int] = []
	while bag.size() < board.size():
		bag.append_array(cycle)
	_shuffle(bag, rng)
	for i in board.size():
		terrain[board[i]] = bag[i]

	# Dice numbers come after the terrain, so a seed keeps giving the same terrain.
	var tokens: Array[int] = []
	while tokens.size() < board.size():
		tokens.append_array(TOKENS)
	_shuffle(tokens, rng)
	for i in board.size():
		numbers[board[i]] = tokens[i]


## Makes the world an endless plane. The same seed always gives the same terrain and
## numbers at every hex, however far out, and nothing is generated until it is looked at.
## Clears anything already built.
func generate_infinite(seed_value := -1, weights: Dictionary = DEFAULT_WEIGHTS) -> void:
	infinite = true
	radius = 0
	terrain.clear()
	numbers.clear()
	structures.clear()
	roads.clear()
	revealed.clear()
	explored.clear()
	origin = NO_VERTEX
	_vertex_set.clear()
	_edge_set.clear()
	_vertices.clear()
	_edges.clear()
	if seed_value >= 0:
		_seed = seed_value
	else:
		_seed = randi() & 0x7fffffff
	_terrain_cycle.clear()
	for kind in weights:
		for _i in maxi(0, int(weights[kind])):
			_terrain_cycle.append(int(kind))
	if _terrain_cycle.is_empty():
		_terrain_cycle.append(Terrain.NEUTRAL)


## A repeatable pseudo-random value for a hex, the same on every machine.
func _mix(hex: Vector2i, salt: int) -> int:
	var h := _seed * 668265263 + hex.x * 374761393 + hex.y * 1274126177 + salt * 2246822519
	h = (h ^ (h >> 15)) * 2654435761
	h = (h ^ (h >> 13)) * 1597334677
	h = h ^ (h >> 16)
	return h & 0x7fffffff


## Deals terrain and a number to `hex` the first time an endless world is asked about it.
func _ensure(hex: Vector2i) -> void:
	if terrain.has(hex):
		return
	terrain[hex] = _terrain_cycle[_mix(hex, 1) % _terrain_cycle.size()]
	numbers[hex] = TOKENS[_mix(hex, 2) % TOKENS.size()]


## The dice number on `hex`, or 0 if it is off the board.
func number_at(hex: Vector2i) -> int:
	if infinite:
		_ensure(hex)
	return int(numbers.get(hex, 0))


static func _shuffle(bag: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(bag.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := bag[i]
		bag[i] = bag[j]
		bag[j] = swap


func _index(board: Array[Vector2i]) -> void:
	_vertex_set.clear()
	_edge_set.clear()
	for hex in board:
		for v: Vector3i in HexGrid.hex_corners(hex):
			_vertex_set[v] = true
		for e: Vector3i in HexGrid.hex_edges(hex):
			_edge_set[e] = true
	_vertices.clear()
	_edges.clear()
	for v: Vector3i in _vertex_set:
		_vertices.append(v)
	for e: Vector3i in _edge_set:
		_edges.append(e)
	_vertices.sort_custom(_vec3_less)
	_edges.sort_custom(_vec3_less)


static func _vec3_less(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


# ------------------------------------------------------------------- queries

func hex_count() -> int:
	return terrain.size()


func hexes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for hex: Vector2i in terrain:
		out.append(hex)
	return out


## Every hex carrying `number`, sorted. On an endless plane that means every hex within
## reach of the built world: a window that grows with the roads and rooms.
func hexes_with_number(number: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if infinite:
		for hex in HexGrid.hexes_in_radius(_reach()):
			if number_at(hex) == number:
				out.append(hex)
		out.sort_custom(_vec2_less)
		return out
	for hex: Vector2i in numbers:
		if numbers[hex] == number:
			out.append(hex)
	out.sort_custom(_vec2_less)
	return out


static func _vec2_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


## How far from the middle an endless world has been built, plus a margin, at least 24.
func _reach() -> int:
	var far := 0
	for v: Vector3i in structures:
		far = maxi(far, HexGrid.hex_distance(Vector2i.ZERO, Vector2i(v.x, v.y)))
	for e: Vector3i in roads:
		far = maxi(far, HexGrid.hex_distance(Vector2i.ZERO, Vector2i(e.x, e.y)))
	return maxi(24, far + 12)


## Every vertex on the board (a corner of at least one board hex), sorted.
func vertices() -> Array[Vector3i]:
	return _vertices.duplicate()


## Every edge on the board (a side of at least one board hex), sorted.
func edges() -> Array[Vector3i]:
	return _edges.duplicate()


func has_hex(hex: Vector2i) -> bool:
	return infinite or terrain.has(hex)


func has_vertex(v: Vector3i) -> bool:
	return infinite or _vertex_set.has(v)


func has_edge(e: Vector3i) -> bool:
	return infinite or _edge_set.has(e)


## The terrain of `hex`, or -1 if it is off the board.
func terrain_at(hex: Vector2i) -> int:
	if infinite:
		_ensure(hex)
	return int(terrain.get(hex, -1))


## The board hexes that meet at `v`.
func hexes_at(v: Vector3i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for hex: Vector2i in HexGrid.vertex_hexes(v):
		if infinite:
			_ensure(hex)
		if terrain.has(hex):
			out.append(hex)
	return out


## The terrains of the board hexes that meet at `v`, one entry per hex.
func terrains_at(v: Vector3i) -> Array[int]:
	var out: Array[int] = []
	for hex in hexes_at(v):
		out.append(int(terrain[hex]))
	return out


func has_structure(v: Vector3i) -> bool:
	return structures.has(v)


func structure_at(v: Vector3i) -> Variant:
	return structures.get(v)


func has_road(e: Vector3i) -> bool:
	return roads.has(e)


func road_at(e: Vector3i) -> Variant:
	return roads.get(e)


func is_revealed(hex: Vector2i) -> bool:
	return has_hex(hex) and (not fog or revealed.has(hex))


# ----------------------------------------------------------------- placement

## Founds the world: the first structure, free of the road rule. Only once.
func place_origin(v: Vector3i, data: Variant = true) -> bool:
	if origin != NO_VERTEX or not has_vertex(v):
		return false
	origin = v
	structures[v] = data
	explore(v)
	_reveal(HexGrid.vertex_hexes(v))
	structure_changed.emit(v)
	return true


## {ok: bool, reason: String}. A road runs from a structure or another road.
func can_build_road(e: Vector3i) -> Dictionary:
	if not has_edge(e):
		return _no("Off the board.")
	if roads.has(e):
		return _no("A road already runs there.")
	if origin == NO_VERTEX:
		return _no("Nothing has been founded yet.")
	if vertex_fog:
		for end: Vector3i in HexGrid.edge_ends(e):
			if not explored.has(end):
				return _no("Unexplored: send the party there first.")
	for end: Vector3i in HexGrid.edge_ends(e):
		if _anchors(end):
			return _yes()
	return _no("A road must start from a structure or another road.")


func build_road(e: Vector3i, data: Variant = true) -> bool:
	if not can_build_road(e)["ok"]:
		return false
	roads[e] = data
	_reveal(HexGrid.edge_hexes(e))
	road_changed.emit(e)
	return true


## {ok: bool, reason: String}. A structure stands where a road ends. A structure at
## `ignoring` does not count towards the distance rule, for moving one that is about to go.
func can_build_structure(v: Vector3i, ignoring := NO_VERTEX) -> Dictionary:
	if not has_vertex(v):
		return _no("Off the board.")
	if structures.has(v):
		return _no("Occupied.")
	if vertex_fog and not explored.has(v):
		return _no("Unexplored: send the party there first.")
	if distance_rule:
		for near: Vector3i in HexGrid.vertex_neighbours(v):
			if near != ignoring and structures.has(near):
				return _no("Too close to another structure.")
	for e: Vector3i in HexGrid.vertex_edges(v):
		if roads.has(e):
			return _yes()
	return _no("A structure must stand where a road ends.")


func build_structure(v: Vector3i, data: Variant = true) -> bool:
	if not can_build_structure(v)["ok"]:
		return false
	structures[v] = data
	_reveal(HexGrid.vertex_hexes(v))
	structure_changed.emit(v)
	return true


## Takes a road away. The network is not re-checked: whatever it was holding up is now
## cut off (see is_cut_off).
func remove_road(e: Vector3i) -> bool:
	if not roads.erase(e):
		return false
	road_changed.emit(e)
	return true


## Takes a structure away. The origin cannot be removed.
func remove_structure(v: Vector3i) -> bool:
	if v == origin or not structures.has(v):
		return false
	structures.erase(v)
	structure_changed.emit(v)
	return true


## Edges a road could be built on right now, sorted.
func open_road_spots() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if infinite:
		var seen := {}
		for anchor: Vector3i in _anchor_vertices():
			for e: Vector3i in HexGrid.vertex_edges(anchor):
				if not seen.has(e) and can_build_road(e)["ok"]:
					seen[e] = true
					out.append(e)
		out.sort_custom(_vec3_less)
		return out
	for e in _edges:
		if can_build_road(e)["ok"]:
			out.append(e)
	return out


## Vertices a structure could be built on right now, sorted.
func open_structure_spots() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if infinite:
		for v in _anchor_vertices():
			if can_build_structure(v)["ok"]:
				out.append(v)
		out.sort_custom(_vec3_less)
		return out
	for v in _vertices:
		if can_build_structure(v)["ok"]:
			out.append(v)
	return out


## Vertices that carry a structure or the end of a road: where building can reach from.
func _anchor_vertices() -> Array[Vector3i]:
	var seen := {}
	for v: Vector3i in structures:
		seen[v] = true
	for e: Vector3i in roads:
		for end: Vector3i in HexGrid.edge_ends(e):
			seen[end] = true
	var out: Array[Vector3i] = []
	for v: Vector3i in seen:
		out.append(v)
	return out


## True if a road can start from `v`: a structure stands there or a road already ends there.
func _anchors(v: Vector3i) -> bool:
	if structures.has(v):
		return true
	for e: Vector3i in HexGrid.vertex_edges(v):
		if roads.has(e):
			return true
	return false


# ------------------------------------------------------------- connectivity

## Vertex -> Array of the vertices a road leads to from it. Only vertices a road touches
## appear.
func road_graph() -> Dictionary:
	var graph := {}
	for e: Vector3i in roads:
		var ends := HexGrid.edge_ends(e)
		for i in 2:
			if not graph.has(ends[i]):
				graph[ends[i]] = []
			(graph[ends[i]] as Array).append(ends[1 - i])
	return graph


## Every vertex reachable from `start` along roads, as a set (includes `start`).
func reachable_from(start: Vector3i) -> Dictionary:
	var seen := {}
	if not has_vertex(start):
		return seen
	seen[start] = true
	var graph := road_graph()
	var queue: Array[Vector3i] = [start]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_back()
		var onward: Array = graph.get(cur, [])
		for nxt: Vector3i in onward:
			if not seen.has(nxt):
				seen[nxt] = true
				queue.append(nxt)
	return seen


## Every vertex the origin's road network reaches. Empty before the origin is placed.
func connected_to_origin() -> Dictionary:
	if origin == NO_VERTEX:
		return {}
	return reachable_from(origin)


## True if a structure stands at `v` but no unbroken road leads back to the origin.
func is_cut_off(v: Vector3i) -> bool:
	return structures.has(v) and not connected_to_origin().has(v)


# -------------------------------------------------------------------- doors

## A room's doors are the roads that touch its vertex: at most three, one per edge slot.
## Each entry is {slot: int, edge: Vector3i, to: Vector3i}. `slot` is the edge's index in
## HexGrid.vertex_edges(v), so a door keeps the same place on the room's wall for good.
## Ordered by slot.
func doors_at(v: Vector3i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not has_vertex(v):
		return out
	var slots := HexGrid.vertex_edges(v)
	for slot in slots.size():
		var e: Vector3i = slots[slot]
		if roads.has(e):
			var ends := HexGrid.edge_ends(e)
			out.append({"slot": slot, "edge": e, "to": ends[1] if ends[0] == v else ends[0]})
	return out


func door_count(v: Vector3i) -> int:
	return doors_at(v).size()


## The vertex you reach by going through the door in `slot` of `v`, or NO_VERTEX if no road
## runs from that slot.
func door_destination(v: Vector3i, slot: int) -> Vector3i:
	for door in doors_at(v):
		if door["slot"] == slot:
			return door["to"]
	return NO_VERTEX


## The slot at `to` that leads back to `from`, so a scene swap can put the player at the
## door they came in by. -1 if the two are not joined by a road.
func arrival_slot(from: Vector3i, to: Vector3i) -> int:
	for door in doors_at(to):
		if door["to"] == from:
			return door["slot"]
	return -1


# --------------------------------------------------------------------- fog

## True if `v` has been explored, or vertex_fog is off (then every vertex counts).
func is_explored(v: Vector3i) -> bool:
	return has_vertex(v) and (not vertex_fog or explored.has(v))


## Marks `v` explored and reveals the hexes at its corners. False if it was off the board
## or already explored.
func explore(v: Vector3i) -> bool:
	if not has_vertex(v) or explored.has(v):
		return false
	explored[v] = true
	_reveal(HexGrid.vertex_hexes(v))
	explored_changed.emit()
	return true


## Explores `v` and every vertex within `steps` neighbour-steps of it (not road steps: the
## party walks open ground). Returns how many vertices were newly explored.
func explore_around(v: Vector3i, steps := 0) -> int:
	var count := 0
	var seen := {v: 0}
	var queue: Array[Vector3i] = [v]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_front()
		if explore(cur):
			count += 1
		if int(seen[cur]) >= steps:
			continue
		for nxt: Vector3i in HexGrid.vertex_neighbours(cur):
			if has_vertex(nxt) and not seen.has(nxt):
				seen[nxt] = int(seen[cur]) + 1
				queue.append(nxt)
	return count


func _reveal(to_show: Array[Vector2i]) -> void:
	var changed := false
	for hex in to_show:
		if has_hex(hex) and not revealed.has(hex):
			revealed[hex] = true
			changed = true
	if changed:
		revealed_changed.emit()


# ----------------------------------------------------------------- helpers

func _yes() -> Dictionary:
	return {"ok": true, "reason": ""}


func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
