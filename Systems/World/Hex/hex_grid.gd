class_name HexGrid
extends RefCounted
## Pure geometry and adjacency for a pointy-top hex board where terrain lives on hexes,
## structures on vertices (corners) and roads on edges (sides). No state, no scenes.
##
## Three kinds of key, all plain integer vectors so they work as Dictionary keys:
##   hex     Vector2i(q, r)     axial coordinates
##   vertex  Vector3i(q, r, t)  t = 0: the TOP corner of hex (q, r); t = 1: its BOTTOM corner
##   edge    Vector3i(q, r, d)  d = 0, 1 or 2: the E, NE or NW side of hex (q, r)
## Every corner on the board is the top or the bottom of exactly one hex, and every side is
## the E, NE or NW side of exactly one hex, so each vertex and edge has a single canonical
## key however you arrive at it.
##
## Space: +x is east, +z is south (NORTH is -Z, as everywhere else in the project). The 2D
## positions here are (x, z). Numbering inside one hex:
##   sides    0 E, 1 NE, 2 NW, 3 W, 4 SW, 5 SE   (counter-clockwise from east)
##   corners  0 N, 1 NE, 2 SE, 3 S, 4 SW, 5 NW   (clockwise from north)
## Side d (for d = 0..2) runs between the corners listed in EDGE_CORNERS.

const SQRT3 := 1.7320508075688772

## Axial step to the neighbouring hex across each side.
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## Where corner k of hex (q, r) lives as a canonical vertex: (dq, dr, t), added to (q, r).
## Corners on the sides of a hex belong to a neighbour as that neighbour's top or bottom.
const CORNER_OFFSETS: Array[Vector3i] = [
	Vector3i(0, 0, 0),   # 0 N : the top of this hex
	Vector3i(1, -1, 1),  # 1 NE: the bottom of the NE neighbour
	Vector3i(0, 1, 0),   # 2 SE: the top of the SE neighbour
	Vector3i(0, 0, 1),   # 3 S : the bottom of this hex
	Vector3i(-1, 1, 0),  # 4 SW: the top of the SW neighbour
	Vector3i(0, -1, 1),  # 5 NW: the bottom of the NW neighbour
]

## The two corners at the ends of side d, for the three canonical sides (E, NE, NW).
const EDGE_CORNERS: Array[Vector2i] = [Vector2i(1, 2), Vector2i(0, 1), Vector2i(5, 0)]

## Stands for "no vertex" / "no edge".
const NONE := Vector3i(1 << 30, 1 << 30, 1 << 30)


# --------------------------------------------------------------------- hexes

static func hex_neighbour(hex: Vector2i, side: int) -> Vector2i:
	return hex + DIRS[posmod(side, 6)]


static func opposite_side(side: int) -> int:
	return posmod(side + 3, 6)


static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	# The sum is never negative, so a shift is an exact halving.
	return (absi(dq) + absi(dr) + absi(dq + dr)) >> 1


## Every hex within `radius` steps of (0, 0): 3r^2 + 3r + 1 of them.
static func hexes_in_radius(radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			out.append(Vector2i(q, r))
	return out


## The six corners of `hex` as canonical vertices, clockwise from the north corner.
static func hex_corners(hex: Vector2i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for k in 6:
		out.append(corner(hex, k))
	return out


## The six sides of `hex` as canonical edges, counter-clockwise from the east side.
static func hex_edges(hex: Vector2i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for d in 6:
		out.append(edge(hex, d))
	return out


# ------------------------------------------------------------------ vertices

## Corner `k` (0..5) of `hex`, as a canonical vertex.
static func corner(hex: Vector2i, k: int) -> Vector3i:
	var o := CORNER_OFFSETS[posmod(k, 6)]
	return Vector3i(hex.x + o.x, hex.y + o.y, o.z)


## The three hexes that meet at `v` (some may lie off the board).
static func vertex_hexes(v: Vector3i) -> Array[Vector2i]:
	var h := Vector2i(v.x, v.y)
	var out: Array[Vector2i] = [h]
	if v.z == 0:
		out.append(h + DIRS[2])  # NW
		out.append(h + DIRS[1])  # NE
	else:
		out.append(h + DIRS[4])  # SW
		out.append(h + DIRS[5])  # SE
	return out


## The three edges that meet at `v` (some may lie off the board).
static func vertex_edges(v: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if v.z == 0:
		out.append(Vector3i(v.x, v.y, 1))
		out.append(Vector3i(v.x, v.y, 2))
		out.append(Vector3i(v.x, v.y - 1, 0))
	else:
		out.append(Vector3i(v.x - 1, v.y + 1, 1))
		out.append(Vector3i(v.x, v.y + 1, 2))
		out.append(Vector3i(v.x - 1, v.y + 1, 0))
	return out


## The three vertices one road away from `v`.
static func vertex_neighbours(v: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for e: Vector3i in vertex_edges(v):
		for end: Vector3i in edge_ends(e):
			if end != v:
				out.append(end)
	return out


# --------------------------------------------------------------------- edges

## Side `side` (0..5) of `hex`, as a canonical edge. Sides 3..5 belong to the neighbour.
static func edge(hex: Vector2i, side: int) -> Vector3i:
	var s := posmod(side, 6)
	if s < 3:
		return Vector3i(hex.x, hex.y, s)
	var n := hex + DIRS[s]
	return Vector3i(n.x, n.y, s - 3)


## The two hexes an edge lies between (one may be off the board).
static func edge_hexes(e: Vector3i) -> Array[Vector2i]:
	var a := Vector2i(e.x, e.y)
	var out: Array[Vector2i] = [a, a + DIRS[e.z]]
	return out


## The two vertices at the ends of an edge.
static func edge_ends(e: Vector3i) -> Array[Vector3i]:
	var pair := EDGE_CORNERS[e.z]
	var hex := Vector2i(e.x, e.y)
	var out: Array[Vector3i] = [corner(hex, pair.x), corner(hex, pair.y)]
	return out


## The four edges that share an end with `e`.
static func edge_neighbours(e: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for end: Vector3i in edge_ends(e):
		for other: Vector3i in vertex_edges(end):
			if other != e:
				out.append(other)
	return out


# ------------------------------------------------------------------ geometry

## Centre of `hex` for hexes whose corners are `size` from the centre.
static func hex_center(hex: Vector2i, size: float) -> Vector2:
	return Vector2(size * SQRT3 * (hex.x + hex.y * 0.5), size * 1.5 * hex.y)


static func vertex_pos(v: Vector3i, size: float) -> Vector2:
	var c := hex_center(Vector2i(v.x, v.y), size)
	return c + Vector2(0.0, -size if v.z == 0 else size)


static func edge_pos(e: Vector3i, size: float) -> Vector2:
	var ends := edge_ends(e)
	return (vertex_pos(ends[0], size) + vertex_pos(ends[1], size)) * 0.5


## The hex under a point.
static func pixel_to_hex(p: Vector2, size: float) -> Vector2i:
	var qf := (SQRT3 / 3.0 * p.x - p.y / 3.0) / size
	var rf := (2.0 / 3.0 * p.y) / size
	var sf := -qf - rf
	var q := roundf(qf)
	var r := roundf(rf)
	var s := roundf(sf)
	var dq := absf(q - qf)
	var dr := absf(r - rf)
	var ds := absf(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))


## The vertex closest to a point. The closest vertex is always a corner of the hex the
## point is in, so only six candidates are checked. For mouse picking.
static func nearest_vertex(p: Vector2, size: float) -> Vector3i:
	var best := NONE
	var best_d := INF
	for v: Vector3i in hex_corners(pixel_to_hex(p, size)):
		var d := vertex_pos(v, size).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = v
	return best


## The edge whose midpoint is closest to a point. For mouse picking.
static func nearest_edge(p: Vector2, size: float) -> Vector3i:
	var best := NONE
	var best_d := INF
	for e: Vector3i in hex_edges(pixel_to_hex(p, size)):
		var d := edge_pos(e, size).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = e
	return best
