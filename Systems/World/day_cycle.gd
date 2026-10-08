class_name DayCycle
extends RefCounted
## The plan -> expedition -> bank loop. Pure logic: no scenes, no UI, no rules engine.
##
## Two grids share coordinates but are separate spaces:
##   TREBLE (Town)    where the day starts. Income, services, ruins after a defeat.
##   BASS (Dungeon)   explored each day, wiped on defeat. Holds the exit and the Segno.
##
## PLAN        spend stock on tiles on either clef and place the Segno (the day's spawn).
## EXPEDITION  the party appears at the Segno, works the dungeon, then walks to the exit.
## SUMMARY     you made it back; loot is banked. begin_next_day() starts the next plan.
## OVER        defeated. Loot carried is lost, the dungeon is wiped, the town is left as
##             ruins. begin_run() starts a fresh run.

signal phase_changed(phase: Phase)
signal log_line(text: String)
signal blueprints_changed
## A tile was placed, erased or changed colour.
signal tile_changed(pos: Vector2i, clef: TileDef.Clef)
## The Segno was placed, moved or cleared.
signal segno_changed

enum Phase { PLAN, EXPEDITION, SUMMARY, OVER }
## The four sides of a dungeon room. NORTH is -Z, matching the Town, where a cell's y
## is laid out along Z. A door on a side leads to the neighbouring cell on that side.
enum Side { NORTH, EAST, SOUTH, WEST }

## Stands for "no Segno placed".
const NO_SEGNO := Vector2i(1 << 30, 1 << 30)
## Both clefs have a fixed tile here: the Town's origin and the dungeon's exit.
const ORIGIN := Vector2i.ZERO
const NEIGHBOURS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

var config: WorldConfig
var persistent: WorldPersistent
var exit_def: TileDef
var origin_def: TileDef
## The room the Segno is made of. Free, never a blueprint, never on top of another room.
var segno_def: TileDef
var rng := RandomNumberGenerator.new()

var phase: Phase = Phase.OVER
var day := 0
var stock: Dictionary = {}                # resource id -> int
var treble := ClefGrid.new(TileDef.Clef.TREBLE)
var bass := ClefGrid.new(TileDef.Clef.BASS)
## The Bass Clef cell the party spawns on this day. NO_SEGNO until placed.
var segno := NO_SEGNO
var carried: Dictionary = {}              # Vector2i -> remnants left alive yesterday
var debt := 0
var carried_loot: Dictionary = {}         # picked up this expedition, banked on return
var spawns: Array[Dictionary] = []        # {id, pos, template, level, loot, alive}
## Every dungeon tile that may be drawn as a blueprint. Set by whoever loads the tiles.
var blueprint_pool: Array[TileDef] = []
## Today's blueprints, one card each. A card is spent when its tile is placed, and
## whatever is left expires when the day turns over.
var blueprints: Array[TileDef] = []
## Pay the tithe from notes before cuts. The plan screen toggles this.
var tithe_notes_first := false

var _next_spawn_id := 0
var _path_cache: Dictionary = {}
var _path_dirty := true


func _init(p_exit: TileDef, p_config: WorldConfig = null, p_persistent: WorldPersistent = null,
		seed_value := -1, p_origin: TileDef = null, p_segno: TileDef = null) -> void:
	exit_def = p_exit
	config = p_config if p_config != null else WorldConfig.new()
	persistent = p_persistent if p_persistent != null else WorldPersistent.new()
	if p_segno != null:
		segno_def = p_segno
	else:
		segno_def = TileDef.new()
		segno_def.id = &"segno"
		segno_def.display_name = "Segno Room"
		segno_def.category = TileDef.Category.DUNGEON
		segno_def.is_segno = true
		segno_def.blueprint_weight = 0.0
	if p_origin != null:
		origin_def = p_origin
	else:
		origin_def = TileDef.new()
		origin_def.id = &"origin"
		origin_def.display_name = "Town Square"
		origin_def.category = TileDef.Category.VILLAGE
		origin_def.is_origin = true
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


## The grid for one clef.
func grid_for(clef: TileDef.Clef) -> ClefGrid:
	return treble if clef == TileDef.Clef.TREBLE else bass


func tile_at(pos: Vector2i, clef: TileDef.Clef) -> TileInstance:
	return grid_for(clef).get_tile(pos)


# ------------------------------------------------------------ room links

## The grid step through a door on `side`.
static func side_offset(side: int) -> Vector2i:
	match side:
		Side.NORTH:
			return Vector2i(0, -1)
		Side.EAST:
			return Vector2i(1, 0)
		Side.SOUTH:
			return Vector2i(0, 1)
		Side.WEST:
			return Vector2i(-1, 0)
	return Vector2i.ZERO


## The side of the next room you arrive through: walk out the north door, come in by
## the south one.
static func opposite_side(side: int) -> int:
	return (side + 2) % 4


## The Bass Clef room one door over, or null if that cell is empty or a ruin.
func neighbour_room(cell: Vector2i, side: int) -> TileInstance:
	var tile := bass.get_tile(cell + side_offset(side))
	if tile != null and tile.is_live():
		return tile
	return null


## Every side of `cell` that has a standing room behind it. Those doors are open; the
## rest are sealed.
func open_sides(cell: Vector2i) -> Array[int]:
	var out: Array[int] = []
	for side in 4:
		if neighbour_room(cell, side) != null:
			out.append(side)
	return out


# ------------------------------------------------------------- run setup

func begin_run() -> void:
	day = 1
	stock = _normalised(config.starting_resources)
	treble.clear()
	bass.clear()
	segno = NO_SEGNO
	carried.clear()
	carried_loot.clear()
	spawns.clear()
	debt = 0
	tithe_notes_first = false
	bass.set_tile(ORIGIN, TileInstance.new(exit_def, ORIGIN))
	treble.set_tile(ORIGIN, TileInstance.new(origin_def, ORIGIN))
	for ruin in persistent.ruins:
		var pos: Vector2i = ruin["pos"]
		if not treble.has_tile(pos):
			treble.set_tile(pos, TileInstance.new(ruin["def"], pos, true))
	_path_dirty = true
	draw_blueprints()
	_set_phase(Phase.PLAN)
	segno_changed.emit()
	log_line.emit("Day %d begins." % day)


# --------------------------------------------------------------- planning

## Cost of placing `def` at `pos`: its colour in notes (140, 240, 30 = 14 red, 24 green,
## 3 blue) plus any extra `cost`, after any ruin discount.
func cost_of(pos: Vector2i, def: TileDef) -> Dictionary:
	var out := _normalised(def.cost)
	for i in 3:
		var points := clampi(def.color[i], 0, TileInstance.MAX_COLOR)
		var notes := floori(points / float(maxi(1, config.color_per_note)))
		if notes > 0:
			out[_note_id(i)] = int(out.get(_note_id(i), 0)) + notes
	var existing := grid_for(def.clef()).get_tile(pos)
	if existing != null and existing.ruined and existing.def == def:
		for key in out:
			out[key] = int(ceil(out[key] * config.ruin_discount))
	return out


## {ok: bool, reason: String}. A tile goes on its own clef and must touch a standing
## tile on that same clef, so each grid grows outward from its own origin.
func can_place(pos: Vector2i, def: TileDef) -> Dictionary:
	if phase != Phase.PLAN:
		return {"ok": false, "reason": "Not planning."}
	if def.is_exit:
		return {"ok": false, "reason": "The exit cannot be built."}
	if def.is_origin:
		return {"ok": false, "reason": "The origin cannot be built."}
	if def.is_segno:
		return {"ok": false, "reason": "Use Place Segno for the Segno room."}
	if needs_blueprint(def) and not blueprints.has(def):
		return {"ok": false, "reason": "No blueprint for that today."}
	var grid := grid_for(def.clef())
	var existing := grid.get_tile(pos)
	if existing != null:
		if not existing.ruined:
			return {"ok": false, "reason": "Occupied."}
		if existing.def != def:
			return {"ok": false, "reason": "Ruins of something else stand here."}
	if not grid.touches_live(pos, _anchor_ignore(grid.clef)):
		if grid.clef == TileDef.Clef.BASS and has_segno() and grid.touches_live(pos):
			return {"ok": false, "reason": "The Segno's room can't anchor new rooms."}
		return {"ok": false, "reason": "Must touch a standing tile."}
	var price := cost_of(pos, def)
	for key in price:
		if int(stock.get(key, 0)) < int(price[key]):
			return {"ok": false, "reason": "Cannot afford it."}
	return {"ok": true, "reason": ""}


func place_tile(pos: Vector2i, def: TileDef) -> bool:
	var check := can_place(pos, def)
	if not check["ok"]:
		log_line.emit(String(check["reason"]))
		return false
	var price := cost_of(pos, def)
	for key in price:
		stock[key] = int(stock.get(key, 0)) - int(price[key])
	var clef := def.clef()
	grid_for(clef).set_tile(pos, TileInstance.new(def, pos))
	if needs_blueprint(def):
		blueprints.erase(def)  # spends one card
		blueprints_changed.emit()
	if not persistent.built_ids.has(def.id):
		persistent.built_ids.append(def.id)
	if clef == TileDef.Clef.BASS:
		_path_dirty = true
	tile_changed.emit(pos, clef)
	return true


## {ok: bool, reason: String}. A spent room (every colour channel at 250) must be erased
## before anything else can be built there, and so must a ruin you want to replace with a
## different tile. Other tiles only if erase_any_tile is on.
func can_erase(pos: Vector2i, clef: TileDef.Clef = TileDef.Clef.BASS) -> Dictionary:
	if phase != Phase.PLAN:
		return {"ok": false, "reason": "Not planning."}
	var tile := grid_for(clef).get_tile(pos)
	if tile == null:
		return {"ok": false, "reason": "Nothing there."}
	if tile.def.is_exit:
		return {"ok": false, "reason": "The exit cannot be erased."}
	if tile.def.is_origin:
		return {"ok": false, "reason": "The origin cannot be erased."}
	if tile.def.is_segno:
		return {"ok": true, "reason": ""}  # free to pick up and put down again
	if tile.ruined:
		return {"ok": true, "reason": ""}
	if not tile.is_depleted() and not config.erase_any_tile:
		return {"ok": false, "reason": "Only a spent room can be erased."}
	return {"ok": true, "reason": ""}


func erase_tile(pos: Vector2i, clef: TileDef.Clef = TileDef.Clef.BASS) -> bool:
	var check := can_erase(pos, clef)
	if not check["ok"]:
		log_line.emit(String(check["reason"]))
		return false
	grid_for(clef).remove_tile(pos)
	if clef == TileDef.Clef.BASS:
		carried.erase(pos)
		_path_dirty = true
		if pos == segno:
			segno = NO_SEGNO
			segno_changed.emit()
	log_line.emit("Erased (%d, %d)." % [pos.x, pos.y])
	tile_changed.emit(pos, clef)
	return true


# ------------------------------------------------------------ blueprints

## True if `def` can only be built from a blueprint drawn today: dungeon (Bass Clef) tiles.
func needs_blueprint(def: TileDef) -> bool:
	return config.require_blueprints and def.clef() == TileDef.Clef.BASS \
			and not def.is_exit and not def.is_segno


## Throws away unspent blueprints and draws a fresh hand. Rarer tiles have lower
## weights, and every copy already in the hand makes another less likely.
func draw_blueprints() -> void:
	blueprints.clear()
	if config.require_blueprints:
		var copies := {}
		for _i in config.blueprints_per_day:
			var candidates: Array[TileDef] = []
			var weights: Array[float] = []
			for def in blueprint_pool:
				if def == null or def.clef() != TileDef.Clef.BASS or def.is_exit or def.is_segno:
					continue
				if def.blueprint_weight <= 0.0 or def.blueprint_min_day > day:
					continue
				candidates.append(def)
				weights.append(def.blueprint_weight
						/ (1.0 + config.blueprint_repeat_penalty * int(copies.get(def, 0))))
			var index := _weighted_index(weights)
			if index < 0:
				break
			blueprints.append(candidates[index])
			copies[candidates[index]] = int(copies.get(candidates[index], 0)) + 1
	blueprints_changed.emit()


## Empty cells on `clef` a tile could be placed on right now: next to a standing tile,
## plus ruins that can be rebuilt. Sorted so it is stable.
func open_slots(clef: TileDef.Clef = TileDef.Clef.BASS) -> Array[Vector2i]:
	return grid_for(clef).open_slots(_anchor_ignore(clef))


## The one tile that can't anchor new ones: the Segno's room on the Bass Clef. A space
## touching only the Segno stays closed; touching any other standing tile opens it.
func _anchor_ignore(clef: TileDef.Clef) -> Vector2i:
	if clef == TileDef.Clef.BASS and has_segno():
		return segno
	return ClefGrid.NO_CELL


func _weighted_index(weights: Array[float]) -> int:
	var total := 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return weights.size() - 1


# ------------------------------------------------------------------ segno

func has_segno() -> bool:
	return segno != NO_SEGNO


## {ok: bool, reason: String}. The Segno is a room of its own, placed free of charge in an
## empty Bass Clef cell next to a standing room (never on top of one). Moving it doesn't
## count the old Segno room as something to touch. Whether it connects to the exit is
## checked when the day starts, so you can place it before the route is finished.
func can_set_segno(pos: Vector2i) -> Dictionary:
	if phase != Phase.PLAN:
		return {"ok": false, "reason": "Not planning."}
	if has_segno() and pos == segno:
		return {"ok": false, "reason": "The Segno is already there."}
	if bass.has_tile(pos):
		return {"ok": false, "reason": "The Segno needs an empty cell."}
	for step in NEIGHBOURS:
		var next := pos + step
		if has_segno() and next == segno:
			continue
		var tile := bass.get_tile(next)
		if tile != null and tile.is_live():
			return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "The Segno must touch a standing room."}


## Builds the Segno room at `pos`, taking the previous one away. Free.
func set_segno(pos: Vector2i) -> bool:
	var check := can_set_segno(pos)
	if not check["ok"]:
		log_line.emit(String(check["reason"]))
		return false
	var old := segno
	if has_segno():
		bass.remove_tile(old)
		tile_changed.emit(old, TileDef.Clef.BASS)
	bass.set_tile(pos, TileInstance.new(segno_def, pos))
	segno = pos
	_path_dirty = true
	tile_changed.emit(pos, TileDef.Clef.BASS)
	segno_changed.emit()
	log_line.emit("Segno set at (%d, %d)." % [pos.x, pos.y])
	return true


## Picks the Segno room up again.
func clear_segno() -> void:
	if not has_segno():
		return
	var old := segno
	bass.remove_tile(old)
	segno = NO_SEGNO
	_path_dirty = true
	tile_changed.emit(old, TileDef.Clef.BASS)
	segno_changed.emit()


## The Bass Clef cell the party appears on.
func spawn_cell() -> Vector2i:
	return segno if config.require_segno and has_segno() else ORIGIN


## {ok: bool, reason: String}.
func can_start_expedition() -> Dictionary:
	if phase != Phase.PLAN:
		return {"ok": false, "reason": "Not planning."}
	if config.require_segno:
		if not has_segno():
			return {"ok": false, "reason": "Place the Segno first."}
		var room := bass.get_tile(segno)
		if room == null or not room.def.is_segno or not room.is_live():
			return {"ok": false, "reason": "The Segno room is missing."}
		if not bool(main_path()["connected"]):
			return {"ok": false, "reason": "The Segno must connect to the exit."}
	return {"ok": true, "reason": ""}


# -------------------------------------------------------------- main path

## The scored layout, cached until something changes:
## {found, connected, path (Segno first, exit last), steps, loops, bonus, capped,
##  on_path (set), reach (set of standing tiles reachable from the spawn)}.
func main_path() -> Dictionary:
	if not _path_dirty:
		return _path_cache
	_path_dirty = false
	var live := bass.live_cells()
	var reach := MainPath.reachable(live, spawn_cell())
	var info := {
		"found": false, "connected": reach.has(ORIGIN), "path": [], "steps": 0, "loops": 0,
		"bonus": 0.0, "capped": false, "on_path": {}, "reach": reach,
	}
	if config.require_segno and has_segno() and live.has(segno) and live.has(ORIGIN):
		var result := MainPath.find(live, segno, ORIGIN, config.main_path_search_limit)
		if bool(result["found"]):
			info["found"] = true
			info["path"] = result["path"]
			info["steps"] = int(result["steps"])
			info["loops"] = int(result["loops"])
			info["capped"] = bool(result["capped"])
			info["on_path"] = result["on_path"]
			info["bonus"] = MainPath.bonus(int(result["steps"]), int(result["loops"]),
					config.main_path_bonus_per_step, config.loop_penalty)
	_path_cache = info
	return info


## Loot multiplier for an encounter room: rooms on the main path gain its bonus, rooms
## with no walking route to the spawn are cut.
func loot_multiplier(pos: Vector2i) -> float:
	var info := main_path()
	var mult := 1.0
	if bool(info["found"]) and (info["on_path"] as Dictionary).has(pos):
		mult += float(info["bonus"])
	if not (info["reach"] as Dictionary).has(pos):
		mult *= config.disconnected_loot_multiplier
	return mult


# ----------------------------------------------------------- pressure

## Levels added to every remnant spawned on `pos` today.
func level_bonus(pos: Vector2i) -> int:
	var bonus := int(floor((day - 1) * config.level_per_day))
	if config.debt_per_level > 0:
		bonus += int(debt / float(config.debt_per_level))
	if int(carried.get(pos, 0)) > 0:
		bonus += config.carried_level_bonus
	return bonus


## Tithe taken at the start of day `for_day`.
func tithe_for_day(for_day: int) -> int:
	return config.tithe_base + config.tithe_per_day * (for_day - 1)


func tithe_due() -> int:
	return tithe_for_day(day)


## What will be taken when the next day begins.
func tithe_tonight() -> int:
	return tithe_for_day(day + 1)


## The order the tithe is paid in: config.tithe_order, with every note colour moved
## ahead of cuts when tithe_notes_first is on.
func tithe_order_now() -> Array[StringName]:
	var out: Array[StringName] = []
	if tithe_notes_first:
		for id in config.tithe_order:
			if config.note_ids.has(id):
				out.append(id)
		for id in config.tithe_order:
			if not config.note_ids.has(id):
				out.append(id)
	else:
		out.assign(config.tithe_order)
	return out


## What paying `due` (default: tonight's tithe) would take from stock right now:
## {paid: {resource id: amount}, shortfall: int}. Takes nothing.
func tithe_preview(due := -1) -> Dictionary:
	var left := tithe_tonight() if due < 0 else due
	var paid := {}
	for id in tithe_order_now():
		if left <= 0:
			break
		var take := mini(int(stock.get(id, 0)), left)
		if take > 0:
			paid[id] = take
			left -= take
	return {"paid": paid, "shortfall": left}


## Steps from the exit across standing Bass Clef tiles, or -1 if the tile is cut off.
func distance_to_exit(pos: Vector2i) -> int:
	var seen := {ORIGIN: 0}
	var queue: Array[Vector2i] = [ORIGIN]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == pos:
			return seen[cur]
		for step in NEIGHBOURS:
			var nxt := cur + step
			var tile := bass.get_tile(nxt)
			if tile != null and tile.is_live() and not seen.has(nxt):
				seen[nxt] = seen[cur] + 1
				queue.append(nxt)
	return -1


# -------------------------------------------------------------- expedition

## Populates every standing encounter room and starts the expedition. The party appears
## at the Segno. Returns the spawns, or nothing if the day cannot start (the reason is
## logged).
func start_expedition() -> Array[Dictionary]:
	var check := can_start_expedition()
	if not check["ok"]:
		if phase == Phase.PLAN:
			log_line.emit(String(check["reason"]))
		return []
	spawns.clear()
	carried_loot.clear()
	var positions: Array = bass.cells.keys()
	positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	for pos: Vector2i in positions:
		var tile: TileInstance = bass.cells[pos]
		if not tile.is_live() or tile.def.is_exit or tile.def.enemies.is_empty():
			continue
		var mult := loot_multiplier(pos)
		var count := tile.def.spawn_count + int(carried.get(pos, 0))
		for _i in count:
			var template := _pick_enemy(tile)
			spawns.append({
				"id": _next_spawn_id,
				"pos": pos,
				"template": template,
				"level": template.level + level_bonus(pos),
				"loot": _loot_for(tile, template, mult),
				"alive": true,
			})
			_next_spawn_id += 1
	carried.clear()
	_set_phase(Phase.EXPEDITION)
	log_line.emit("Expedition: %d remnants gather." % spawns.size())
	return spawns.duplicate()


func remaining() -> int:
	var n := 0
	for s in spawns:
		if s["alive"]:
			n += 1
	return n


## Lays one remnant to rest. Its loot is carried, not banked, until you return. Every
## note of a colour it drops also raises the room's matching colour channel.
func record_kill(spawn_id: int) -> Dictionary:
	if phase != Phase.EXPEDITION:
		return {}
	for s in spawns:
		if s["id"] == spawn_id and s["alive"]:
			s["alive"] = false
			for key in s["loot"]:
				carried_loot[key] = int(carried_loot.get(key, 0)) + int(s["loot"][key])
			_stain_room(s["pos"], s["loot"])
			return s["loot"]
	return {}


func _stain_room(pos: Vector2i, loot: Dictionary) -> void:
	var tile := bass.get_tile(pos)
	if tile == null:
		return
	var changed := false
	for i in 3:
		var notes := int(loot.get(_note_id(i), 0))
		if notes > 0:
			tile.raise_color(i, notes * config.color_gain_per_note)
			changed = true
	if not changed:
		return
	tile_changed.emit(pos, TileDef.Clef.BASS)
	if tile.is_depleted():
		_path_dirty = true  # a spent room no longer connects anything
		log_line.emit("Spent (%d, %d)." % [pos.x, pos.y])


## Back at the exit: loot is banked and remnants still alive wait for tomorrow.
func return_to_exit() -> Dictionary:
	if phase != Phase.EXPEDITION:
		return {}
	var banked := carried_loot.duplicate()
	for key in banked:
		stock[key] = int(stock.get(key, 0)) + int(banked[key])
	var left_alive := 0
	for s in spawns:
		if s["alive"]:
			carried[s["pos"]] = int(carried.get(s["pos"], 0)) + 1
			left_alive += 1
	carried_loot.clear()
	spawns.clear()
	_set_phase(Phase.SUMMARY)
	log_line.emit("Returned. %d remnants left alive." % left_alive)
	return {"banked": banked, "left_alive": left_alive}


## The party fell before reaching the exit. Carried loot is lost and the run ends. The
## dungeon is wiped; every Treble Clef tile but the origin is left as a ruin.
func defeat() -> void:
	if phase != Phase.EXPEDITION:
		return
	persistent.runs += 1
	persistent.best_day = maxi(persistent.best_day, day)
	persistent.ruins.clear()
	for pos: Vector2i in treble.cells:
		var tile: TileInstance = treble.cells[pos]
		if not tile.def.is_origin:
			persistent.ruins.append({"pos": pos, "def": tile.def})
	carried_loot.clear()
	spawns.clear()
	treble.clear()
	bass.clear()
	segno = NO_SEGNO
	_path_dirty = true
	blueprints.clear()
	_set_phase(Phase.OVER)
	log_line.emit("The run ends on day %d." % day)


# ---------------------------------------------------------------- next day

## Town income arrives, then the tithe is taken. Returns a report.
func begin_next_day() -> Dictionary:
	if phase != Phase.SUMMARY:
		return {}
	day += 1
	var income := {}
	for pos: Vector2i in treble.cells:
		var tile: TileInstance = treble.cells[pos]
		if tile.is_live():
			for key in tile.def.income:
				var amount := int(tile.def.income[key])
				stock[StringName(key)] = int(stock.get(StringName(key), 0)) + amount
				income[StringName(key)] = int(income.get(StringName(key), 0)) + amount
	var due := tithe_due()
	var payment := tithe_preview(due)
	var paid_with: Dictionary = payment["paid"]
	for id in paid_with:
		stock[id] = int(stock.get(id, 0)) - int(paid_with[id])
	var shortfall := int(payment["shortfall"])
	debt += shortfall
	draw_blueprints()
	_set_phase(Phase.PLAN)
	log_line.emit("Day %d begins." % day)
	return {"income": income, "tithe_due": due, "tithe_paid": due - shortfall,
			"tithe_paid_with": paid_with, "shortfall": shortfall}


# ----------------------------------------------------------------- helpers

func _scaled_loot(base: Dictionary, mult: float) -> Dictionary:
	var out := {}
	for key in base:
		out[StringName(key)] = maxi(1, roundi(float(base[key]) * mult))
	return out


## Resource id of note colour `channel` (0 red, 1 green, 2 blue).
func _note_id(channel: int) -> StringName:
	if channel < config.note_ids.size():
		return config.note_ids[channel]
	return StringName("notes_%d" % channel)


## A room picks its enemies at random; those of its lowest colour(s) are more likely.
func _pick_enemy(tile: TileInstance) -> EnemyTemplate:
	var lowest := tile.lowest_channels()
	var weights: Array[float] = []
	for template in tile.def.enemies:
		var channel := int(template.note_color) - 1  # -1 = neutral
		weights.append(config.affinity_multiplier if lowest.has(channel) else 1.0)
	return tile.def.enemies[maxi(0, _weighted_index(weights))]


## Notes one remnant drops: the enemy's own notes_per_kill, times the room's
## note_multiplier, times `mult` (the main-path bonus), rounded. At least one, unless the
## enemy or the room drops none at all.
func notes_dropped(def: TileDef, template: EnemyTemplate, mult := 1.0) -> int:
	if template.notes_per_kill <= 0 or def.note_multiplier <= 0.0:
		return 0
	return maxi(1, roundi(template.notes_per_kill * def.note_multiplier * mult))


## What one remnant carries: its notes (all of the enemy's own colour, or a random colour
## for each note if the enemy is uncoloured) plus the tile's other loot, scaled by the
## main-path bonus.
func _loot_for(tile: TileInstance, template: EnemyTemplate, mult: float) -> Dictionary:
	var out := _scaled_loot(tile.def.loot_per_kill, mult)
	var channel := int(template.note_color) - 1  # -1 = uncoloured
	for _i in notes_dropped(tile.def, template, mult):
		var note := _note_id(channel if channel >= 0 else rng.randi_range(0, 2))
		out[note] = int(out.get(note, 0)) + 1
	return out


## Editor dictionaries may use String keys; the rest of the code uses StringNames.
func _normalised(source: Dictionary) -> Dictionary:
	var out := {}
	for key in source:
		out[StringName(key)] = int(source[key])
	return out


func _set_phase(value: Phase) -> void:
	phase = value
	phase_changed.emit(value)
