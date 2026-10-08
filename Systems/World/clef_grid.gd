class_name ClefGrid
extends RefCounted
## One of the two grids. The Treble Clef (Town) and the Bass Clef (Dungeon) share
## coordinates but each has its own ClefGrid, and a tile may only grow outward from
## a standing tile on the same clef. Pure data, no scenes.

const NEIGHBOURS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
## Stands for "no cell" (same value as DayCycle.NO_SEGNO).
const NO_CELL := Vector2i(1 << 30, 1 << 30)

var clef: TileDef.Clef
## Vector2i -> TileInstance
var cells: Dictionary = {}


func _init(p_clef: TileDef.Clef = TileDef.Clef.BASS) -> void:
	clef = p_clef


func clear() -> void:
	cells.clear()


func has_tile(pos: Vector2i) -> bool:
	return cells.has(pos)


func get_tile(pos: Vector2i) -> TileInstance:
	var tile: TileInstance = cells.get(pos)
	return tile


func set_tile(pos: Vector2i, tile: TileInstance) -> void:
	cells[pos] = tile


func remove_tile(pos: Vector2i) -> void:
	cells.erase(pos)


func size() -> int:
	return cells.size()


## True if a standing (not ruined, not spent) tile sits next to `pos`. A tile at
## `ignore` doesn't count: the Segno's room can't be what a new room hangs off.
func touches_live(pos: Vector2i, ignore := NO_CELL) -> bool:
	for step in NEIGHBOURS:
		var at := pos + step
		if at == ignore:
			continue
		var tile := get_tile(at)
		if tile != null and tile.is_live():
			return true
	return false


## Every standing tile's position, as a set: {Vector2i: true}.
func live_cells() -> Dictionary:
	var out := {}
	for pos: Vector2i in cells:
		var tile: TileInstance = cells[pos]
		if tile.is_live():
			out[pos] = true
	return out


## Empty cells a tile could be placed on right now: next to a standing tile, plus
## ruins that can be rebuilt. Sorted so it is stable. A tile at `ignore` (the Segno)
## doesn't open up the cells around it.
func open_slots(ignore := NO_CELL) -> Array[Vector2i]:
	var found := {}
	for pos: Vector2i in cells:
		var here: TileInstance = cells[pos]
		if here.ruined and touches_live(pos, ignore):
			found[pos] = true
		if not here.is_live() or pos == ignore:
			continue
		for step in NEIGHBOURS:
			var nxt := pos + step
			if not cells.has(nxt):
				found[nxt] = true
	var out: Array[Vector2i] = []
	for pos: Vector2i in found:
		out.append(pos)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out


## The smallest rectangle holding every tile and every position in `extra`.
func bounds(extra: Array[Vector2i] = []) -> Rect2i:
	var lo := Vector2i.ZERO
	var hi := Vector2i.ZERO
	for pos: Vector2i in cells:
		lo = Vector2i(mini(lo.x, pos.x), mini(lo.y, pos.y))
		hi = Vector2i(maxi(hi.x, pos.x), maxi(hi.y, pos.y))
	for pos in extra:
		lo = Vector2i(mini(lo.x, pos.x), mini(lo.y, pos.y))
		hi = Vector2i(maxi(hi.x, pos.x), maxi(hi.y, pos.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)
