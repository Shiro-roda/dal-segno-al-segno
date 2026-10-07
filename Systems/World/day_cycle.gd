class_name DayCycle
extends RefCounted
## The plan -> expedition -> bank loop. Pure logic: no scenes, no UI, no rules engine.
##
## PLAN        spend stock on tiles.
## EXPEDITION  the dungeon you built is populated; kill remnants, then return or die.
## SUMMARY     you made it back; loot is banked. begin_next_day() starts the next plan.
## OVER        defeated. Loot carried is lost, the dungeon is wiped, the village is
##             left as ruins. begin_run() starts a fresh run.

signal phase_changed(phase: Phase)
signal log_line(text: String)
signal blueprints_changed
## A tile was placed, erased or changed colour.
signal tile_changed(pos: Vector2i)

enum Phase { PLAN, EXPEDITION, SUMMARY, OVER }

const ORIGIN := Vector2i.ZERO
const NEIGHBOURS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

var config: WorldConfig
var persistent: WorldPersistent
var exit_def: TileDef
var rng := RandomNumberGenerator.new()

var phase: Phase = Phase.OVER
var day := 0
var stock: Dictionary = {}                # resource id -> int
var grid: Dictionary = {}                 # Vector2i -> TileInstance
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


func _init(p_exit: TileDef, p_config: WorldConfig = null, p_persistent: WorldPersistent = null,
		seed_value := -1) -> void:
	exit_def = p_exit
	config = p_config if p_config != null else WorldConfig.new()
	persistent = p_persistent if p_persistent != null else WorldPersistent.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


# ------------------------------------------------------------- run setup

func begin_run() -> void:
	day = 1
	stock = _normalised(config.starting_resources)
	grid.clear()
	carried.clear()
	carried_loot.clear()
	spawns.clear()
	debt = 0
	tithe_notes_first = false
	grid[ORIGIN] = TileInstance.new(exit_def, ORIGIN)
	for ruin in persistent.ruins:
		var pos: Vector2i = ruin["pos"]
		if not grid.has(pos):
			grid[pos] = TileInstance.new(ruin["def"], pos, true)
	draw_blueprints()
	_set_phase(Phase.PLAN)
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
	var existing: TileInstance = grid.get(pos)
	if existing != null and existing.ruined and existing.def == def:
		for key in out:
			out[key] = int(ceil(out[key] * config.ruin_discount))
	return out


## {ok: bool, reason: String}. A tile must touch a standing tile, so the dungeon
## and village grow outward from the exit.
func can_place(pos: Vector2i, def: TileDef) -> Dictionary:
	if phase != Phase.PLAN:
		return {"ok": false, "reason": "Not planning."}
	if def.is_exit:
		return {"ok": false, "reason": "The exit cannot be built."}
	if needs_blueprint(def) and not blueprints.has(def):
		return {"ok": false, "reason": "No blueprint for that today."}
	var existing: TileInstance = grid.get(pos)
	if existing != null:
		if not existing.ruined:
			return {"ok": false, "reason": "Occupied."}
		if existing.def != def:
			return {"ok": false, "reason": "Ruins of something else stand here."}
	if not _touches_live_tile(pos):
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
	grid[pos] = TileInstance.new(def, pos)
	if needs_blueprint(def):
		blueprints.erase(def)  # spends one card
		blueprints_changed.emit()
	if not persistent.built_ids.has(def.id):
		persistent.built_ids.append(def.id)
	tile_changed.emit(pos)
	return true


## {ok: bool, reason: String}. A spent room (every colour channel at 250) must be erased
## before anything else can be built there. Other tiles only if erase_any_tile is on.
func can_erase(pos: Vector2i) -> Dictionary:
	if phase != Phase.PLAN:
		return {"ok": false, "reason": "Not planning."}
	var tile: TileInstance = grid.get(pos)
	if tile == null:
		return {"ok": false, "reason": "Nothing there."}
	if tile.def.is_exit:
		return {"ok": false, "reason": "The exit cannot be erased."}
	if not tile.is_depleted() and not config.erase_any_tile:
		return {"ok": false, "reason": "Only a spent room can be erased."}
	return {"ok": true, "reason": ""}


func erase_tile(pos: Vector2i) -> bool:
	var check := can_erase(pos)
	if not check["ok"]:
		log_line.emit(String(check["reason"]))
		return false
	grid.erase(pos)
	carried.erase(pos)
	log_line.emit("Erased (%d, %d)." % [pos.x, pos.y])
	tile_changed.emit(pos)
	return true


# ------------------------------------------------------------ blueprints

## True if `def` can only be built from a blueprint drawn today.
func needs_blueprint(def: TileDef) -> bool:
	return config.require_blueprints and def.category == TileDef.Category.DUNGEON and not def.is_exit


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
				if def == null or def.category != TileDef.Category.DUNGEON or def.is_exit:
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


## Empty cells a tile could be placed on right now: next to a standing tile, plus
## ruins that can be rebuilt. Sorted so it is stable.
func open_slots() -> Array[Vector2i]:
	var found := {}
	for pos: Vector2i in grid:
		var here: TileInstance = grid[pos]
		if here.ruined and _touches_live_tile(pos):
			found[pos] = true
		if not here.is_live():
			continue
		for step in NEIGHBOURS:
			var nxt := pos + step
			if not grid.has(nxt):
				found[nxt] = true
	var out: Array[Vector2i] = []
	for pos: Vector2i in found:
		out.append(pos)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out


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
	var remaining := tithe_tonight() if due < 0 else due
	var paid := {}
	for id in tithe_order_now():
		if remaining <= 0:
			break
		var take := mini(int(stock.get(id, 0)), remaining)
		if take > 0:
			paid[id] = take
			remaining -= take
	return {"paid": paid, "shortfall": remaining}


## Steps from the exit across standing tiles, or -1 if the tile is cut off.
func distance_to_exit(pos: Vector2i) -> int:
	var seen := {ORIGIN: 0}
	var queue: Array[Vector2i] = [ORIGIN]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == pos:
			return seen[cur]
		for step in NEIGHBOURS:
			var nxt := cur + step
			var tile: TileInstance = grid.get(nxt)
			if tile != null and tile.is_live() and not seen.has(nxt):
				seen[nxt] = seen[cur] + 1
				queue.append(nxt)
	return -1


# -------------------------------------------------------------- expedition

## Populates every standing dungeon tile and starts the expedition. Returns the spawns.
func start_expedition() -> Array[Dictionary]:
	if phase != Phase.PLAN:
		return []
	spawns.clear()
	carried_loot.clear()
	var positions: Array = grid.keys()
	positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	for pos: Vector2i in positions:
		var tile: TileInstance = grid[pos]
		if not tile.is_live() or tile.def.category != TileDef.Category.DUNGEON \
				or tile.def.is_exit or tile.def.enemies.is_empty():
			continue
		var dist := distance_to_exit(pos)
		if dist < 0:
			continue
		var count := tile.def.spawn_count + int(carried.get(pos, 0))
		for _i in count:
			var template := _pick_enemy(tile)
			spawns.append({
				"id": _next_spawn_id,
				"pos": pos,
				"template": template,
				"level": template.level + level_bonus(pos),
				"loot": _loot_for(tile, template, dist),
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
	var tile: TileInstance = grid.get(pos)
	if tile == null:
		return
	var changed := false
	for i in 3:
		var notes := int(loot.get(_note_id(i), 0))
		if notes > 0:
			tile.raise_color(i, notes * config.color_per_note)
			changed = true
	if not changed:
		return
	tile_changed.emit(pos)
	if tile.is_depleted():
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


## The party fell before reaching the exit. Carried loot is lost and the run ends.
func defeat() -> void:
	if phase != Phase.EXPEDITION:
		return
	persistent.runs += 1
	persistent.best_day = maxi(persistent.best_day, day)
	persistent.ruins.clear()
	for pos in grid:
		var tile: TileInstance = grid[pos]
		if tile.def.category == TileDef.Category.VILLAGE and not tile.def.is_exit:
			persistent.ruins.append({"pos": pos, "def": tile.def})
	carried_loot.clear()
	spawns.clear()
	grid.clear()
	blueprints.clear()
	_set_phase(Phase.OVER)
	log_line.emit("The run ends on day %d." % day)


# ---------------------------------------------------------------- next day

## Village income arrives, then the tithe is taken. Returns a report.
func begin_next_day() -> Dictionary:
	if phase != Phase.SUMMARY:
		return {}
	day += 1
	var income := {}
	for pos in grid:
		var tile: TileInstance = grid[pos]
		if tile.is_live() and tile.def.category == TileDef.Category.VILLAGE:
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

func _touches_live_tile(pos: Vector2i) -> bool:
	for step in NEIGHBOURS:
		var tile: TileInstance = grid.get(pos + step)
		if tile != null and tile.is_live():
			return true
	return false


func _scaled_loot(base: Dictionary, distance: int) -> Dictionary:
	var out := {}
	var factor := 1.0 + config.loot_distance_bonus * distance
	for key in base:
		out[StringName(key)] = maxi(1, roundi(float(base[key]) * factor))
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


## What one remnant carries: notes of its own colour (a neutral one carries the room's
## lowest colour), plus the tile's other loot, all scaled by distance from the exit.
func _loot_for(tile: TileInstance, template: EnemyTemplate, distance: int) -> Dictionary:
	var out := _scaled_loot(tile.def.loot_per_kill, distance)
	if tile.def.notes_per_kill > 0:
		var channel := int(template.note_color) - 1
		if channel < 0:
			channel = tile.lowest_channels()[0]
		var notes := maxi(1, roundi(tile.def.notes_per_kill * (1.0 + config.loot_distance_bonus * distance)))
		out[_note_id(channel)] = int(out.get(_note_id(channel), 0)) + notes
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
