class_name MapView
extends Control
## A top-down map drawn from live game state, in the party menu's Map tab.
##
##   Mode.ROOM      the room the party is standing in: walls, doors (and where each leads),
##                  the exit, the Segno spawn, enemies waiting to fight, the leader with
##                  the way they face, and the companions.
##   Mode.DUNGEON   the whole Bass Clef grid: every room tinted with its colour, the main
##                  path from the Segno to the exit, enemies left in each room, and a
##                  pulsing marker on the room the party is in.
##
## North is up in both, matching the plan screen (NORTH is -Z). Hover a room, door or
## marker for details. It reads GameController.day_cycle directly and redraws every
## frame while visible, so it never needs feeding.

enum Mode { ROOM, DUNGEON }

const PAD := 18.0
const TOP := 34.0
const LEGEND_H := 30.0
const ROOM_GRID_M := 5.0
const DOOR_WIDTH_M := 3.5

@export var mode: Mode = Mode.DUNGEON

var _t := 0.0

# Dungeon layout of the last draw, kept for tooltips.
var _bounds := Rect2i()
var _grid_origin := Vector2.ZERO
var _cell_px := 0.0

# Room layout of the last draw.
var _world := Rect2()
var _world_origin_px := Vector2.ZERO
var _world_scale := 1.0
var _hits: Array[Dictionary] = []  # {pos: Vector2, radius: float, text: String}


func _ready() -> void:
	custom_minimum_size = Vector2(420.0, 340.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()


## The room scene the party is in, or null in the Town.
static func find_room(tree: SceneTree) -> DungeonRoom:
	for node in tree.get_nodes_in_group("dungeon_room"):
		if node is DungeonRoom and not node.is_queued_for_deletion():
			return node as DungeonRoom
	return null


# ------------------------------------------------------------------- draw

func _draw() -> void:
	var back := _c("bg").lightened(0.03)
	draw_rect(Rect2(Vector2.ZERO, size), back)
	draw_rect(Rect2(Vector2.ZERO, size), MenuStyle.fade(_c("dim"), 0.3), false, 1.0)
	_hits.clear()
	var day := GameController.day_cycle
	if day == null:
		_message("No expedition has been planned yet.")
		return
	_label(Vector2(PAD, 22.0), _caption(day), _c("secondary"), 13)
	_draw_compass()
	if mode == Mode.ROOM:
		_draw_room(day)
	else:
		_draw_dungeon(day)


func _caption(day: DayCycle) -> String:
	if mode == Mode.DUNGEON:
		return "BASS CLEF  -  %d rooms" % day.bass.size()
	var room := find_room(get_tree())
	if room == null:
		return "CURRENT ROOM"
	var tile := day.tile_at(room.cell, TileDef.Clef.BASS)
	return "%s  (%d, %d)" % [_tile_name(tile).to_upper() if tile != null else "ROOM", room.cell.x, room.cell.y]


# ---------------------------------------------------------------- dungeon

func _draw_dungeon(day: DayCycle) -> void:
	if day.bass.size() == 0:
		_message("No rooms have been placed yet.")
		return
	var extra: Array[Vector2i] = [DayCycle.ORIGIN]
	if day.has_segno():
		extra.append(day.segno)
	_bounds = day.bass.bounds(extra)
	var avail := Vector2(maxf(size.x - PAD * 2.0, 1.0), maxf(size.y - TOP - PAD - LEGEND_H, 1.0))
	_cell_px = clampf(minf(avail.x / _bounds.size.x, avail.y / _bounds.size.y), 18.0, 90.0)
	var grid_px := Vector2(_bounds.size) * _cell_px
	_grid_origin = Vector2(PAD, TOP) + (avail - grid_px) * 0.5

	var enemies := {}
	for s: Dictionary in day.spawns:
		if bool(s["alive"]):
			var at: Vector2i = s["pos"]
			enemies[at] = int(enemies.get(at, 0)) + 1
	var info := day.main_path()
	var on_path: Dictionary = info["on_path"]
	var path: Array = info["path"]
	var room := find_room(get_tree())
	var here: Vector2i = room.cell if room != null and day.phase == DayCycle.Phase.EXPEDITION else DayCycle.NO_SEGNO

	for pos: Vector2i in day.bass.cells:
		var tile: TileInstance = day.bass.cells[pos]
		var cell := _cell_rect(pos).grow(-2.0)
		draw_rect(cell, _tile_fill(tile))
		var edge := MenuStyle.fade(_c("dim"), 0.5)
		var edge_w := 1.0
		if on_path.has(pos):
			edge = MenuStyle.fade(_c("secondary"), 0.9)
			edge_w = 2.0
		if tile.ruined:
			draw_line(cell.position, cell.end, MenuStyle.fade(_c("dim"), 0.6), 1.5)
			draw_line(Vector2(cell.end.x, cell.position.y), Vector2(cell.position.x, cell.end.y),
					MenuStyle.fade(_c("dim"), 0.6), 1.5)
		elif tile.is_depleted():
			edge = MenuStyle.fade(_c("alert"), 0.8)
		draw_rect(cell, edge, false, edge_w)
		if _cell_px >= 40.0:
			_label(Vector2(cell.position.x + 4.0, cell.end.y - 5.0),
					_fit(_tile_name(tile), cell.size.x - 8.0, 11), _c("text"), 11)
		if tile.def.is_exit:
			_label(cell.position + Vector2(4.0, 13.0), "EXIT", _c("secondary"), 11)
		if tile.def.is_segno:
			_label(cell.position + Vector2(4.0, 13.0), "SEGNO", _c("secondary"), 11)
		var count := int(enemies.get(pos, 0))
		if count > 0:
			var tag := "x%d" % count
			var tag_w := _font().get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			_label(Vector2(cell.end.x - tag_w - 4.0, cell.position.y + 14.0), tag, _c("alert"), 12)

	if path.size() > 1:
		var points := PackedVector2Array()
		for step: Vector2i in path:
			points.append(_cell_rect(step).get_center())
		draw_polyline(points, MenuStyle.fade(_c("secondary"), 0.55), 3.0, true)

	if here != DayCycle.NO_SEGNO:
		var centre := _cell_rect(here).get_center()
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		draw_rect(_cell_rect(here).grow(-1.0), MenuStyle.fade(_c("primary"), 0.4 + 0.6 * pulse), false, 3.0)
		draw_circle(centre, maxf(_cell_px * 0.12, 5.0), _c("primary"))
		draw_arc(centre, maxf(_cell_px * 0.12, 5.0) + 3.0 + 3.0 * pulse, 0.0, TAU, 24,
				MenuStyle.fade(_c("primary"), 0.6), 1.5)

	_legend([
		[_c("primary"), "You"],
		[_c("secondary"), "Main path"],
		[_c("alert"), "enemies"],
		[_c("dim"), "Ruined"],
	])


func _cell_rect(pos: Vector2i) -> Rect2:
	return Rect2(_grid_origin + Vector2(pos - _bounds.position) * _cell_px, Vector2(_cell_px, _cell_px))


func _tile_fill(tile: TileInstance) -> Color:
	if tile.ruined:
		return Color(0.2, 0.19, 0.19)
	if tile.is_depleted():
		return Color(0.09, 0.09, 0.09)
	var tint := Color(tile.color.x / 250.0, tile.color.y / 250.0, tile.color.z / 250.0)
	return Color(0.1, 0.11, 0.12).lerp(tint, 0.62)


func _tile_tip(pos: Vector2i) -> String:
	var day := GameController.day_cycle
	if day == null:
		return ""
	var tile := day.tile_at(pos, TileDef.Clef.BASS)
	if tile == null:
		return ""
	var lines: Array[String] = ["%s  (%d, %d)" % [_tile_name(tile), pos.x, pos.y]]
	if tile.def.is_exit:
		lines.append("The exit. Reach it to end the expedition.")
	if tile.def.is_segno:
		lines.append("The Segno. The party spawns here.")
	if tile.ruined:
		lines.append("Ruined")
	elif tile.is_depleted():
		lines.append("Spent: erase it to build again")
	lines.append("Colour   R %d   G %d   B %d" % [
			roundi(tile.color.x / 10.0), roundi(tile.color.y / 10.0), roundi(tile.color.z / 10.0)])
	var count := _enemies_at(day, pos)
	if count > 0:
		lines.append("enemies waiting: %d" % count)
	if tile.is_live() and not tile.def.enemies.is_empty():
		lines.append("Loot x%.2f" % day.loot_multiplier(pos))
	if bool(day.main_path()["on_path"].has(pos)):
		lines.append("On the main path")
	return "\n".join(lines)


# ------------------------------------------------------------------- room

func _draw_room(day: DayCycle) -> void:
	var room := find_room(get_tree())
	if room == null:
		_message("You are not inside a dungeon room.\nStart an expedition to see where you are.")
		return
	var expedition := day.phase == DayCycle.Phase.EXPEDITION
	var centre := _xz(room)
	var half := room.room_half_size
	var tile: TileInstance = day.tile_at(room.cell, TileDef.Clef.BASS) if expedition else null

	var doors: Array[RoomDoor] = []
	for node in get_tree().get_nodes_in_group("room_door"):
		if node is RoomDoor and room.is_ancestor_of(node) and not node.is_queued_for_deletion():
			doors.append(node as RoomDoor)
	var exits: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("room_exit"):
		if node is Node3D and room.is_ancestor_of(node) and not node.is_queued_for_deletion():
			exits.append(node as Node3D)
	var leader: Node3D = null
	for node in get_tree().get_nodes_in_group("party_leader"):
		if node is Node3D and not node.is_queued_for_deletion():
			leader = node as Node3D
	var followers: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("party_follower"):
		if node is Node3D and not node.is_queued_for_deletion():
			followers.append(node as Node3D)
	var spawn := room.get_node_or_null("SegnoSpawn") as Node3D
	var encounter := room.get_node_or_null("Encounter") as Node3D
	var waiting := _enemies_at(day, room.cell) if expedition else 0

	# World rectangle: the room's walls, grown to hold anything that sits outside them.
	var world := Rect2(centre - half, half * 2.0)
	for door in doors:
		world = world.expand(_xz(door))
	for spot in exits:
		world = world.expand(_xz(spot))
	if leader != null:
		world = world.expand(_xz(leader))
	world = world.grow(2.0)

	var avail := Vector2(maxf(size.x - PAD * 2.0, 1.0), maxf(size.y - TOP - PAD - LEGEND_H, 1.0))
	_world_scale = minf(avail.x / world.size.x, avail.y / world.size.y)
	_world = world
	_world_origin_px = Vector2(PAD, TOP) + (avail - world.size * _world_scale) * 0.5

	# Floor and a 5 m grid.
	var floor_rect := Rect2(_to_px(centre - half), half * 2.0 * _world_scale)
	draw_rect(floor_rect, _c("bg").lightened(0.08))
	var grid_col := MenuStyle.fade(_c("dim"), 0.12)
	for i in range(ceili(-half.x / ROOM_GRID_M), floori(half.x / ROOM_GRID_M) + 1):
		var gx := _to_px(Vector2(centre.x + i * ROOM_GRID_M, centre.y)).x
		draw_line(Vector2(gx, floor_rect.position.y), Vector2(gx, floor_rect.end.y), grid_col, 1.0)
	for i in range(ceili(-half.y / ROOM_GRID_M), floori(half.y / ROOM_GRID_M) + 1):
		var gy := _to_px(Vector2(centre.x, centre.y + i * ROOM_GRID_M)).y
		draw_line(Vector2(floor_rect.position.x, gy), Vector2(floor_rect.end.x, gy), grid_col, 1.0)
	draw_rect(floor_rect, MenuStyle.fade(_c("dim"), 0.8), false, 2.0)

	# Where the fight happens.
	if encounter != null and waiting > 0:
		var trigger := Vector2(room.encounter_trigger_size.x, room.encounter_trigger_size.z)
		var zone := Rect2(_to_px(_xz(encounter) - trigger * 0.5), trigger * _world_scale)
		draw_rect(zone, MenuStyle.fade(_c("alert"), 0.1))
		draw_rect(zone, MenuStyle.fade(_c("alert"), 0.55), false, 1.5)
		var tag := "%d enemy%s" % [waiting, "" if waiting == 1 else "s"]
		var tag_w := _font().get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var zc := zone.get_center()
		_label(Vector2(zc.x - tag_w * 0.5, zc.y + 4.0), tag, _c("alert"), 12)
		_hits.append({"pos": zc, "radius": 22.0,
				"text": "%d enemy%s wait here.\nWalk into the marked area to start the fight." % [
					waiting, "" if waiting == 1 else "s"]})

	# The Segno spawn.
	if tile != null and tile.def.is_segno:
		var sp := _to_px(_xz(spawn) if spawn != null else centre)
		draw_colored_polygon(PackedVector2Array([sp + Vector2(0.0, -9.0), sp + Vector2(9.0, 0.0),
				sp + Vector2(0.0, 9.0), sp + Vector2(-9.0, 0.0)]), MenuStyle.fade(_c("secondary"), 0.85))
		_label(sp + Vector2(12.0, 4.0), "SEGNO", _c("secondary"), 11)
		_hits.append({"pos": sp, "radius": 14.0, "text": "The Segno. The party appeared here."})

	# The exit.
	for spot in exits:
		var ep := _to_px(_xz(spot))
		draw_rect(Rect2(ep - Vector2(8.0, 8.0), Vector2(16.0, 16.0)), MenuStyle.fade(_c("secondary"), 0.3))
		draw_rect(Rect2(ep - Vector2(8.0, 8.0), Vector2(16.0, 16.0)), _c("secondary"), false, 2.0)
		_label(ep + Vector2(12.0, 4.0), "EXIT", _c("secondary"), 11)
		_hits.append({"pos": ep, "radius": 16.0, "text": "The exit. Step here to leave the dungeon."})

	# Doors, each labelled with the room behind it.
	for door in doors:
		_draw_door(door, room, day, expedition, centre)

	# The party.
	for follower in followers:
		var fp := _to_px(_xz(follower))
		draw_circle(fp, 5.0, MenuStyle.fade(_c("text"), 0.85))
		_hits.append({"pos": fp, "radius": 9.0, "text": "A companion"})
	if leader != null:
		_draw_leader(leader)

	_legend([
		[_c("primary"), "You"],
		[_c("text"), "Companions"],
		[_c("primary"), "Open door"],
		[_c("alert"), "Sealed / enemies"],
		[_c("dim"), "grid %d m" % int(ROOM_GRID_M)],
	])


func _draw_door(door: RoomDoor, room: DungeonRoom, day: DayCycle, expedition: bool, centre: Vector2) -> void:
	var dp := _to_px(_xz(door))
	var sealed := door.sealed
	var colour := _c("alert") if sealed else _c("primary")
	var side := int(door.side)
	var across := Vector2(1.0, 0.0) if side == DayCycle.Side.NORTH or side == DayCycle.Side.SOUTH else Vector2(0.0, 1.0)
	var reach := DOOR_WIDTH_M * 0.5 * _world_scale
	draw_line(dp - across * reach, dp + across * reach, colour, 5.0)

	var side_name := String(DayCycle.Side.keys()[side]).capitalize()
	var leads_to := "Sealed"
	if not sealed:
		leads_to = "Open"
		if expedition:
			var next := day.neighbour_room(room.cell, side)
			if next != null:
				leads_to = _tile_name(next)
	var inward := (_to_px(centre) - dp).normalized()
	var text_w := _font().get_string_size(leads_to, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var at := dp + inward * 18.0
	_label(Vector2(at.x - text_w * 0.5, at.y + 4.0), leads_to, colour, 11)
	_hits.append({"pos": dp, "radius": maxf(reach, 14.0),
			"text": "%s door  -  %s" % [side_name, "sealed, nothing lies that way" if sealed else "leads to %s" % leads_to]})


func _draw_leader(leader: Node3D) -> void:
	var lp := _to_px(_xz(leader))
	var forward3 := -leader.global_transform.basis.z
	var forward := Vector2(forward3.x, forward3.z)
	forward = forward.normalized() if forward.length() > 0.01 else Vector2(0.0, -1.0)
	var sideways := Vector2(-forward.y, forward.x)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	draw_arc(lp, 10.0 + 3.0 * pulse, 0.0, TAU, 24, MenuStyle.fade(_c("primary"), 0.6), 1.5)
	draw_circle(lp, 6.0, _c("primary"))
	draw_colored_polygon(PackedVector2Array([lp + forward * 15.0,
			lp + forward * 4.0 + sideways * 6.0, lp + forward * 4.0 - sideways * 6.0]), _c("primary"))
	_label(lp + Vector2(12.0, -10.0), "YOU", _c("primary"), 11)
	_hits.append({"pos": lp, "radius": 12.0, "text": "You (the party leader)"})


func _to_px(world_pos: Vector2) -> Vector2:
	return _world_origin_px + (world_pos - _world.position) * _world_scale


static func _xz(node: Node3D) -> Vector2:
	return Vector2(node.global_position.x, node.global_position.z)


# ---------------------------------------------------------------- tooltip

func _get_tooltip(at_position: Vector2) -> String:
	if mode == Mode.ROOM:
		for hit: Dictionary in _hits:
			if (hit["pos"] as Vector2).distance_to(at_position) <= float(hit["radius"]):
				return String(hit["text"])
		return ""
	if _cell_px <= 0.0:
		return ""
	var rel := (at_position - _grid_origin) / _cell_px
	return _tile_tip(Vector2i(floori(rel.x), floori(rel.y)) + _bounds.position)


# ---------------------------------------------------------------- helpers

func _c(key: String) -> Color:
	return MenuStyle.pal(key)


func _font() -> Font:
	return get_theme_default_font()


func _label(at: Vector2, text: String, colour: Color, font_size: int) -> void:
	var font := _font()
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 3, MenuStyle.fade(_c("bg"), 0.9))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, colour)


func _message(text: String) -> void:
	draw_multiline_string(_font(), Vector2(PAD, size.y * 0.5 - 8.0), text, HORIZONTAL_ALIGNMENT_CENTER,
			size.x - PAD * 2.0, 14, -1, _c("dim"))


## Shortens `text` with an ellipsis until it fits `max_width`.
func _fit(text: String, max_width: float, font_size: int) -> String:
	var font := _font()
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var cut := text
	while cut.length() > 1 and font.get_string_size(cut + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		cut = cut.substr(0, cut.length() - 1)
	return cut + "..."


func _tile_name(tile: TileInstance) -> String:
	if tile == null or tile.def == null:
		return "Room"
	return tile.def.display_name if tile.def.display_name != "" else String(tile.def.id)


func _enemies_at(day: DayCycle, pos: Vector2i) -> int:
	var count := 0
	for s: Dictionary in day.spawns:
		if bool(s["alive"]) and s["pos"] == pos:
			count += 1
	return count


## "N" with an arrow, top right.
func _draw_compass() -> void:
	var tip := Vector2(size.x - PAD - 8.0, 10.0)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(5.0, 11.0), tip + Vector2(-5.0, 11.0)]),
			MenuStyle.fade(_c("dim"), 0.9))
	_label(tip + Vector2(-4.0, 25.0), "N", _c("dim"), 11)


## A row of coloured swatches and captions along the bottom edge.
func _legend(items: Array) -> void:
	var font := _font()
	var x := PAD
	var y := size.y - 12.0
	for item: Array in items:
		var colour: Color = item[0]
		var text: String = item[1]
		draw_rect(Rect2(Vector2(x, y - 8.0), Vector2(9.0, 9.0)), colour)
		_label(Vector2(x + 14.0, y), text, _c("dim"), 11)
		x += 14.0 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 18.0
