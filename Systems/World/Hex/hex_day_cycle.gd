class_name HexDayCycle
extends RefCounted
## The plan -> expedition -> bank loop on the hex world. The counterpart of DayCycle: the
## same economy, but over one shared plane instead of two square grids.
##
##   Terrain  hexes, dealt from a seed (HexWorld).
##   Rooms    structures on vertices. A TileDef's clef() is now only a tag: TREBLE
##            structures are the town (income, services, ruins after a defeat), BASS
##            structures are the dungeon (blueprints, enemies, wiped on defeat).
##   Roads    edges. The origin grows them itself: at the end of each segment it turns a share
##            of the banked notes into Hyle, and each time enough Hyle has built up a road is
##            laid, into the fog if need be (see _grow_network). A vertex a road reaches must
##            be cleared of wild enemies before it can be built on.
##   Building A room with build_segments above 0 is a building site for that many segments
##            after it is placed. It anchors roads but is not live until finished.
##
## The exit and the Town Square are one structure on the origin vertex.
##
## PLAN        spend stock on rooms and place the Segno (the day's spawn).
## EXPEDITION  the party appears at the Segno, works the dungeon, then walks to the exit.
## SUMMARY     you made it back; loot is banked. begin_next_day() starts the next plan.
## OVER        defeated. Loot carried is lost, the dungeon and every road are wiped, the
##             town is left as ruins. begin_run() starts a fresh run.
##
## A DAY has three SEGMENTS (DAWN, MIDDAY, DUSK). Each segment begins with a roll
## (config.wake_rolls_per_segment times, 2d6): every hex carrying a rolled number is AWAKE,
## but only for that segment. A dungeon room gathers its spawn_count enemies for each awake
## hex it borders, favouring enemies of those hexes' colours; a room with nothing awake
## beside it stays quiet. The roll is known at the start of the segment.
##
## GATHERING ACCUMULATES. A segment's enemies are gathered when its expedition starts, or,
## if nobody went in, when the segment ends. Whatever is not cleared waits in the room, and
## enemies left alive come back too, so rooms fill with more and different enemies the
## longer they are left alone.
##
## begin_next_segment() ends a segment (the party rests briefly) and begins the next; after
## DUSK it rolls over to the next day (income, a long rest). The day stays the unit
## for larger-scale state and projects.
##
## Not here yet: the walk between rooms (a door leads to the next vertex along a road,
## which may be a bare junction rather than a room), and rival dungeons.

signal phase_changed(phase: Phase)
signal log_line(text: String)
signal blueprints_changed
## A room was placed, erased, stained or changed.
signal tile_changed(vertex: Vector3i)
signal road_changed(edge: Vector3i)
## The origin's Hyle changed: notes were turned into it, or a road was paid for with it.
signal hyle_changed
signal revealed_changed
## The Segno was placed, moved or cleared.
signal segno_changed
## A shop's shelves were restocked or something was bought. `vertex` is where it stands.
signal shop_changed(vertex: Vector3i)
## The dawn roll was made, or the awake hexes were set by hand.
signal awake_changed
## A new segment of the day began (its roll is already made).
signal segment_changed(segment: Segment)
## A segment or a day ended. The party gets a short rest, or a long one when `long_rest`.
signal party_rested(long_rest: bool)
## The party moved, fought, banked loot or was knocked back to the origin.
signal party_changed
## Wild enemies were cleared, or the board was seeded with them.
signal wild_changed
## A vertex was explored.
signal explored_changed

enum Phase { PLAN, EXPEDITION, SUMMARY, OVER }
## The parts of a day, each opened by its own roll.
enum Segment { DAWN, MIDDAY, DUSK }

## Stands for "no Segno placed".
const NO_SEGNO := HexGrid.NONE

## Switches the origin's growth off: no starting roads, no Hyle, no new roads. For the
## self-test, whose older checks lay out their own roads and count their own notes.
static var growth_disabled := false

var config: WorldConfig
var persistent: WorldPersistent
var exit_def: TileDef
var origin_def: TileDef
## The room the Segno is made of. Free, never a blueprint.
var segno_def: TileDef
var rng := RandomNumberGenerator.new()

var phase: Phase = Phase.OVER
var day := 0
## Which part of the day it is. Each segment has its own roll and its own awake hexes.
var segment: Segment = Segment.DAWN
## Enemies already gathered in rooms by earlier segments and not yet met:
## Vector3i -> Array of EnemyTemplate. Drawn on when the next expedition starts.
var gathered: Dictionary = {}
## True once this segment's enemies have been gathered (an expedition started in it).
var _gathered_this_segment := false
var stock: Dictionary = {}                # resource id -> int
## Hyle the origin has produced and not yet spent on a road. At the end of each segment a
## share of the banked notes becomes Hyle; every road grown takes hyle_cost_of_next_road().
var hyle := 0
## Roads the origin has grown since the run began, not counting the starting ones. Sets the
## Hyle price of the next road and how much of the banked notes a segment turns into Hyle.
var roads_grown := 0
var world := HexWorld.new()               # structures hold TileInstances, roads hold true
## Town tiles left as ruins: Vector3i -> TileInstance (ruined). Kept out of
## world.structures so a ruin anchors no road and blocks no neighbour.
var ruins: Dictionary = {}
## The vertex the party spawns on this day. NO_SEGNO until placed.
var segno := NO_SEGNO
var carried: Dictionary = {}              # Vector3i -> enemies left alive yesterday
var carried_loot: Dictionary = {}         # picked up this expedition, banked on return
var spawns: Array[Dictionary] = []        # {id, vertex, template, level, loot, alive}
## Every dungeon tile that may be drawn as a blueprint. Set by whoever loads the tiles.
var blueprint_pool: Array[TileDef] = []
## Today's blueprints, one card each. A card is spent when its tile is placed, and
## whatever is left expires when the day turns over.
var blueprints: Array[TileDef] = []
## Today's extra copy of the standing blueprint, or null. Kept apart from `blueprints`
## because placing it costs more notes. Spent when its tile is placed.
var extra_blueprint: TileDef = null

## Times each room's feature (rest, hazard) was used today. Key: the room's vertex.
var feature_uses: Dictionary = {}
## Hit dice each character has spent today (character id -> int).
var hit_dice_spent: Dictionary = {}
## Bonus blueprints earned from hazards today, added to the next day's hand.
var bonus_blueprints_pending := 0
## Shop shelves, per vertex: Vector3i -> Array of {offer: ShopOffer, left: int}.
var shop_stock: Dictionary = {}

## Today's dawn rolls (each a 2d6 total), made when the day begins and known all through
## planning, so rooms can be placed to use what woke.
var rolls: Array[int] = []
## Vector2i -> true. The hexes whose number was rolled today. A room gathers enemies
## for each awake hex it borders.
var awake: Dictionary = {}

## Wild enemies scattered over the board: Vector3i -> Array of {template, block}. A vertex
## holding any cannot be built on or roaded to until they are cleared.
var wild: Dictionary = {}
## The party's StatBlocks (set_party). Empty until a caller provides them.
var party: Array[StatBlock] = []
## Where the party stands on the map. Starts on the origin.
var party_vertex: Vector3i = HexGrid.NONE
## Vertices the party can still walk this segment.
var party_moves_left := 0
## Notes the party has picked up and not yet brought home. Banked on reaching the origin,
## lost if the party is wiped out.
var party_loot: Dictionary = {}
var _origin := HexGrid.NONE
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
		segno_def.role = TileDef.Role.SEGNO
		segno_def.blueprint_weight = 0.0
	if p_origin != null:
		origin_def = p_origin
	else:
		origin_def = TileDef.new()
		origin_def.id = &"origin"
		origin_def.display_name = "Town Square"
		origin_def.category = TileDef.Category.VILLAGE
		origin_def.role = TileDef.Role.ORIGIN
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	world.road_changed.connect(func(e: Vector3i) -> void:
		_path_dirty = true
		road_changed.emit(e))
	world.revealed_changed.connect(func() -> void: revealed_changed.emit())
	world.explored_changed.connect(func() -> void: explored_changed.emit())


## The vertex of the Town Square and the exit.
func origin_vertex() -> Vector3i:
	return _origin


## The room at `v` (standing or spent), or the ruin there, or null.
func tile_at(v: Vector3i) -> TileInstance:
	var built: TileInstance = world.structures.get(v)
	if built != null:
		return built
	var ruin: TileInstance = ruins.get(v)
	return ruin


# ------------------------------------------------------------- run setup

func begin_run() -> void:
	day = 1
	segment = Segment.DAWN
	gathered.clear()
	_gathered_this_segment = false
	stock = _normalised(config.starting_resources)
	hyle = maxi(0, config.starting_hyle)
	roads_grown = 0
	segno = NO_SEGNO
	carried.clear()
	carried_loot.clear()
	spawns.clear()
	raiders.clear()
	allies.clear()
	wild.clear()
	party_loot.clear()
	_reset_daily_features()
	shop_stock.clear()
	bonus_blueprints_pending = 0
	if persistent.board_seed < 0:
		persistent.board_seed = rng.randi() & 0x7fffffff
	_new_board()
	world.place_origin(_origin, TileInstance.new(origin_def, Vector2i.ZERO))
	world.explore_around(_origin, config.start_explored_radius)
	party_vertex = _origin
	party_moves_left = config.party_moves_per_segment
	_scatter_wild()
	for _i in (0 if growth_disabled else config.start_roads):
		if not _grow_one_road():
			break
	for ruin in persistent.ruins:
		if not ruin.has("vertex"):
			continue
		var v: Vector3i = ruin["vertex"]
		if v != _origin and world.has_vertex(v) and not ruins.has(v):
			ruins[v] = TileInstance.new(ruin["def"], Vector2i.ZERO, true)
	_path_dirty = true
	_restock_shops()
	draw_blueprints()
	_roll_wake()
	_set_phase(Phase.PLAN)
	segment_changed.emit(segment)
	segno_changed.emit()
	log_line.emit("Day %d begins." % day)


## A fresh, empty board: same terrain every time for one board_seed.
func _new_board() -> void:
	if config.infinite_board:
		world.generate_infinite(persistent.board_seed)
	else:
		world.generate(config.board_radius, persistent.board_seed)
	world.vertex_fog = config.explore_vertices
	_origin = HexGrid.corner(Vector2i.ZERO, 0)
	ruins.clear()


# ------------------------------------------------------------ unlocks

## Ids of the tiles that currently count as built: every standing Town tile (ruins do
## not count), plus the dungeon exit. A tile also counts as every building it was upgraded
## from. Unlocks last only while these stand.
func _built_ids() -> Dictionary:
	var ids := {exit_def.id: true, origin_def.id: true}
	for v: Vector3i in world.structures:
		var tile: TileInstance = world.structures[v]
		if tile.def.clef() == TileDef.Clef.TREBLE and tile.is_live():
			_mark_ids(ids, tile)
	return ids


## Marks `tile`'s building, and the ones it was upgraded from, in `ids`.
func _mark_ids(ids: Dictionary, tile: TileInstance) -> void:
	ids[tile.def.id] = true
	for earlier in tile.lineage:
		ids[earlier] = true


## Ids `def` needs that have not been built yet.
func missing_unlocks(def: TileDef) -> Array[StringName]:
	var out: Array[StringName] = []
	if def == null or def.unlock_requires_ids.is_empty():
		return out
	var built := _built_ids()
	for id in def.unlock_requires_ids:
		if not built.has(id):
			out.append(id)
	return out


## True while every Town tile `def` requires is standing.
func is_unlocked(def: TileDef) -> bool:
	return missing_unlocks(def).is_empty()


# --------------------------------------------------------------- planning

## Cost of placing `def` at `v`: its colour in notes (140, 240, 30 = 14 red, 24 green,
## 3 blue) plus any extra `cost`, after any ruin discount.
func cost_of(v: Vector3i, def: TileDef) -> Dictionary:
	var out := _normalised(def.cost)
	for i in 3:
		var points := clampi(def.color[i], 0, TileInstance.MAX_COLOR)
		var notes := floori(points / float(maxi(1, config.color_per_note)))
		if notes > 0:
			out[_note_id(i)] = int(out.get(_note_id(i), 0)) + notes
	if uses_extra_blueprint(def):
		for i in 3:
			if out.has(_note_id(i)):
				out[_note_id(i)] = int(out[_note_id(i)]) * maxi(1, config.extra_blueprint_cost_multiplier)
	var ruin: TileInstance = ruins.get(v)
	if ruin != null and ruin.def == def:
		for key in out:
			out[key] = int(ceil(out[key] * config.ruin_discount))
	return out


## {ok: bool, reason: String}. A room goes on a vertex where a road ends, one road apart
## from any other room, so the world grows outward along its roads.
func can_place(v: Vector3i, def: TileDef) -> Dictionary:
	if phase != Phase.PLAN:
		return _no("Not planning.")
	if def.is_exit:
		return _no("The exit cannot be built.")
	if def.is_origin:
		return _no("The origin cannot be built.")
	if def.is_segno:
		return _no("Use Place Segno for the Segno room.")
	if not is_unlocked(def):
		return _no("Locked: needs %s standing." % ", ".join(missing_unlocks(def)))
	if needs_blueprint(def) and not has_blueprint_for(def):
		return _no("No blueprint for that today.")
	var ruin: TileInstance = ruins.get(v)
	if ruin != null and ruin.def != def:
		return _no("Ruins of something else stand here.")
	var spot := world.can_build_structure(v)
	if not spot["ok"]:
		return spot
	if has_wild(v):
		return _no("Wild enemies hold this spot: clear them first.")
	var price := cost_of(v, def)
	for key in price:
		if int(stock.get(key, 0)) < int(price[key]):
			return _no("Cannot afford it.")
	return _yes()


func place_tile(v: Vector3i, def: TileDef) -> bool:
	var check := can_place(v, def)
	if not check["ok"]:
		log_line.emit(String(check["reason"]))
		return false
	var price := cost_of(v, def)
	for key in price:
		stock[key] = int(stock.get(key, 0)) - int(price[key])
	ruins.erase(v)
	var site := TileInstance.new(def, Vector2i.ZERO)
	site.build_left = build_time_of(def)
	world.build_structure(v, site)
	if site.build_left > 0:
		log_line.emit("Building %s: %d segments." % [def.display_name, site.build_left])
	if needs_blueprint(def):
		if blueprints.has(def):
			blueprints.erase(def)  # spends one card
		else:
			extra_blueprint = null  # spends the standing copy
		blueprints_changed.emit()
	if not persistent.built_ids.has(def.id):
		persistent.built_ids.append(def.id)
	_path_dirty = true
	if def.shop != null:
		_stock_shop(v)
	tile_changed.emit(v)
	return true


# --------------------------------------------------------------- growth

## Hyle the next road costs: the base, plus a step for every road the origin has already
## grown (the starting roads do not count), so a larger network is slower to extend.
func hyle_cost_of_next_road() -> int:
	return maxi(1, config.road_hyle_base + config.road_hyle_per_road * roads_grown)


## The share of the lowest banked colour turned into Hyle at the end of a segment. High at
## first, it falls with every road grown until it reaches config.hyle_ratio_floor.
func hyle_ratio_now() -> float:
	var ratio := config.hyle_ratio_start - config.hyle_ratio_step * roads_grown
	return clampf(ratio, config.hyle_ratio_floor, 1.0)


## Notes the origin would take from EACH colour if the segment ended now. Zero unless every
## colour is banked. That many are drawn from the lowest colour's stock, rounded up, so the
## draw is the same for all three.
func hyle_draw() -> int:
	if growth_disabled or hyle_ratio_now() <= 0.0:
		return 0
	var lowest := -1
	for i in 3:
		var banked := int(stock.get(_note_id(i), 0))
		lowest = banked if lowest < 0 else mini(lowest, banked)
	if lowest <= 0:
		return 0
	return mini(lowest, maxi(1, ceili(lowest * hyle_ratio_now())))


## Turns the segment's share of the banked notes into Hyle. Returns the Hyle made.
func _convert_to_hyle() -> int:
	var each := hyle_draw()
	if each <= 0:
		return 0
	for i in 3:
		stock[_note_id(i)] = int(stock.get(_note_id(i), 0)) - each
	var made := each * 3 * maxi(1, config.hyle_per_note)
	hyle += made
	hyle_changed.emit()
	log_line.emit("The origin takes %d of each note and makes %d Hyle (%d banked)." % [each, made, hyle])
	return made


## Roads laid as the segment ends, as many as the Hyle pays for (at most
## config.max_roads_per_segment). Returns how many.
func _grow_network() -> int:
	var laid := 0
	while laid < config.max_roads_per_segment and hyle >= hyle_cost_of_next_road():
		var cost := hyle_cost_of_next_road()
		if not _grow_one_road():
			break  # nowhere left to grow
		hyle -= cost
		roads_grown += 1
		laid += 1
	if laid > 0:
		hyle_changed.emit()
		log_line.emit("The roads grow by %d." % laid)
	return laid


## The end of a segment for the origin: banked notes become Hyle, and Hyle becomes roads.
## Returns {"hyle": made, "roads": laid}.
func _grow_at_segment_end() -> Dictionary:
	if growth_disabled:
		return {"hyle": 0, "roads": 0}
	var made := _convert_to_hyle()
	return {"hyle": made, "roads": _grow_network()}


## Lays the road with the lowest score and returns true, or false if the network cannot
## grow. Wild enemies on the vertex it reaches stay where they are: the vertex must be
## cleared before it can be built on (see can_place).
func _grow_one_road() -> bool:
	var pick := _pick_growth()
	if pick.is_empty():
		return false
	if not world.grow_road(pick["edge"]):
		return false
	_path_dirty = true
	return true


## The best growth candidate, {edge, from, to, score}, or {} if there is none. A candidate
## scores growth_distance_penalty for each road step its far end is from the origin, plus
## growth_crowd_penalty for each vertex of another branch within growth_crowd_radius steps
## of it, plus a little jitter. The lowest score wins, so the network spreads outward
## evenly (the distance term) without clumping (the crowd term).
func _pick_growth() -> Dictionary:
	var candidates := world.growth_candidates()
	if candidates.is_empty():
		return {}
	var graph := world.road_graph()
	var depth := _road_depths(graph)
	var held := {_origin: true}  # every vertex the network holds
	for v: Vector3i in world.structures:
		held[v] = true
	for v: Vector3i in graph:
		held[v] = true
	var best := {}
	for c in candidates:
		var from: Vector3i = c["from"]
		var to: Vector3i = c["to"]
		# The candidate's own branch: what is within two road steps back along it. It is not
		# "another branch", however close.
		var own := _within_steps(graph, from, 2)
		var crowd := 0
		var near := _vertices_within(to, config.growth_crowd_radius)
		for v: Vector3i in near:
			if held.has(v) and not own.has(v):
				crowd += 1
		var score := config.growth_distance_penalty * float(int(depth.get(from, 0)) + 1)
		score += config.growth_crowd_penalty * float(crowd)
		score += rng.randf() * maxf(0.0, config.growth_jitter)
		if best.is_empty() or score < float(best["score"]):
			best = {"edge": c["edge"], "from": from, "to": to, "score": score}
	return best


## Road steps from the origin to each vertex the network reaches.
func _road_depths(graph: Dictionary) -> Dictionary:
	var depth := {_origin: 0}
	var queue: Array[Vector3i] = [_origin]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_front()
		for nxt: Vector3i in graph.get(cur, []):
			if not depth.has(nxt):
				depth[nxt] = int(depth[cur]) + 1
				queue.append(nxt)
	return depth


## The vertices within `steps` road steps of `v` (including `v`), as a set.
func _within_steps(graph: Dictionary, v: Vector3i, steps: int) -> Dictionary:
	var seen := {v: 0}
	var queue: Array[Vector3i] = [v]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_front()
		if int(seen[cur]) >= steps:
			continue
		for nxt: Vector3i in graph.get(cur, []):
			if not seen.has(nxt):
				seen[nxt] = int(seen[cur]) + 1
				queue.append(nxt)
	return seen


## The vertices within `steps` neighbour steps of `v` (not road steps), excluding `v`.
func _vertices_within(v: Vector3i, steps: int) -> Array[Vector3i]:
	var seen := {v: 0}
	var queue: Array[Vector3i] = [v]
	var out: Array[Vector3i] = []
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_front()
		if int(seen[cur]) >= steps:
			continue
		for nxt: Vector3i in HexGrid.vertex_neighbours(cur):
			if world.has_vertex(nxt) and not seen.has(nxt):
				seen[nxt] = int(seen[cur]) + 1
				queue.append(nxt)
				out.append(nxt)
	return out


## {ok: bool, reason: String}. A spent room (every colour channel at 250) must be erased
## before anything else can be built there, and so must a ruin you want to replace with a
## different tile. Other tiles only if erase_any_tile is on.
func can_erase(v: Vector3i) -> Dictionary:
	if phase != Phase.PLAN:
		return _no("Not planning.")
	var tile := tile_at(v)
	if tile == null:
		return _no("Nothing there.")
	if v == _origin:
		return _no("The origin and the exit cannot be erased.")
	if tile.def.is_segno:
		return _yes()  # free to pick up and put down again
	if tile.ruined:
		return _yes()
	if not tile.is_built():
		return _yes()  # a building site can be abandoned, with no refund
	if not tile.is_depleted() and not config.erase_any_tile:
		return _no("Only a spent room can be erased.")
	return _yes()


func erase_tile(v: Vector3i) -> bool:
	var check := can_erase(v)
	if not check["ok"]:
		log_line.emit(String(check["reason"]))
		return false
	if world.has_structure(v):
		world.remove_structure(v)
	else:
		ruins.erase(v)
	if shop_stock.erase(v):
		shop_changed.emit(v)
	carried.erase(v)
	gathered.erase(v)
	_path_dirty = true
	if v == segno:
		segno = NO_SEGNO
		segno_changed.emit()
	log_line.emit("Erased (%d, %d, %d)." % [v.x, v.y, v.z])
	tile_changed.emit(v)
	return true


## Vertices a room could be built on right now, plus ruins that can be rebuilt. Sorted.
func open_structure_spots() -> Array[Vector3i]:
	if phase != Phase.PLAN:
		return []
	return world.open_structure_spots()


# ------------------------------------------------------------ construction

## Segments `def` takes to build once placed. The exit, origin and Segno are never built.
func build_time_of(def: TileDef) -> int:
	if def.is_exit or def.is_origin or def.is_segno:
		return 0
	return maxi(0, def.build_segments)


## Segments left before the room at `v` is finished: 0 if it stands, or there is none.
func construction_left(v: Vector3i) -> int:
	var tile: TileInstance = world.structures.get(v)
	return tile.build_left if tile != null else 0


## Every building site works one segment closer to done. Called as each segment ends, so
## a site never finishes in time to gather that segment's enemies.
func _advance_construction() -> void:
	var vertices: Array = world.structures.keys()
	vertices.sort_custom(_vertex_less)
	for v: Vector3i in vertices:
		var tile: TileInstance = world.structures[v]
		if tile.is_built():
			if tile.upgrading != &"":
				tile.upgrade_left -= 1
				var up := _upgrade_def(tile.def, tile.upgrading)
				if tile.upgrade_left <= 0 or up == null:
					if up != null:
						_finish_upgrade(v, tile, up)
					else:
						tile.upgrading = &""
				else:
					tile_changed.emit(v)
			continue
		tile.build_left -= 1
		if tile.is_built():
			_path_dirty = true
			if tile.def.shop != null:
				_stock_shop(v)
			log_line.emit("%s finished at (%d, %d, %d)." % [tile.def.display_name, v.x, v.y, v.z])
		tile_changed.emit(v)


# ------------------------------------------------------------ wild enemies

## True if living wild enemies stand at `v`.
func has_wild(v: Vector3i) -> bool:
	return not (wild.get(v, []) as Array).is_empty()


## How many wild enemies stand at `v`.
func wild_count_at(v: Vector3i) -> int:
	return (wild.get(v, []) as Array).size()


## Scatters wild groups over the board, the same way for one board seed. Nothing lands
## within config.wild_safe_radius of the origin. An infinite board has no vertex list to
## deal from, so it gets none.
func _scatter_wild() -> void:
	wild.clear()
	if not config.wild_enemies_enabled or config.wild_templates.is_empty():
		wild_changed.emit()
		return
	var dice := RandomNumberGenerator.new()
	dice.seed = persistent.board_seed ^ 0x5bd1e995
	var lo := mini(config.wild_group_min, config.wild_group_max)
	var hi := maxi(config.wild_group_min, config.wild_group_max)
	if not world.infinite:
		_scatter_wild_ground(dice, lo, hi)
	_guard_start(dice, lo, hi)
	wild_changed.emit()


## The scatter proper: a group on each vertex outside the safe radius, by chance.
func _scatter_wild_ground(dice: RandomNumberGenerator, lo: int, hi: int) -> void:
	var safe := {_origin: 0}
	var queue: Array[Vector3i] = [_origin]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_front()
		if int(safe[cur]) >= config.wild_safe_radius:
			continue
		for nxt: Vector3i in HexGrid.vertex_neighbours(cur):
			if not safe.has(nxt):
				safe[nxt] = int(safe[cur]) + 1
				queue.append(nxt)
	for v: Vector3i in world.vertices():
		if safe.has(v) or dice.randf() >= config.wild_density:
			continue
		var group: Array = []
		for _i in dice.randi_range(lo, hi):
			group.append({"template": config.wild_templates[dice.randi_range(0, config.wild_templates.size() - 1)]})
		wild[v] = group


## A wild group on each of the three vertices around the origin, whatever the safe radius,
## so a run opens with something to clear on every side. Dealt from the same seeded dice,
## after the scatter, so it does not change where the rest of the board's groups fall.
func _guard_start(dice: RandomNumberGenerator, lo: int, hi: int) -> void:
	if not config.start_guards:
		return
	for v: Vector3i in HexGrid.vertex_neighbours(_origin):
		if not world.has_vertex(v):
			continue
		var group: Array = []
		for _i in maxi(1, dice.randi_range(lo, hi)):
			group.append({"template": config.wild_templates[dice.randi_range(0, config.wild_templates.size() - 1)]})
		wild[v] = group


# ------------------------------------------------------------------- party

enum FightResult { WON, WIPED, STALEMATE }

## Set by whatever shows the map (the board) to watch fights as they happen. A fight is then
## not played out at once: move_party() returns {fought: true, pending: true} and the fight
## waits in `fight` until the presenter calls finish_fight().
var present_fights := false
## The fight under way, or {}: {vertex, from, group, session}.
var fight: Dictionary = {}
## A watched fight's session exists but has not begun: add it to the scene tree here.
signal fight_starting(session: CombatSession)
## A watched fight has begun: bind a HUD to the session.
signal fight_started(session: CombatSession)
## The party won a fight and earned `amount` XP each. `ready` lists the companions who can
## now level up (see Leveling.award_xp).
signal xp_awarded(amount: int, ready: Array)
## The roster XP is awarded to. Null = Rules.roster.
var roster: PartyRoster = null

## Gives the map a party to walk. The blocks are used as given, so wounds carry over.
func set_party(blocks: Array) -> void:
	party.clear()
	for b in blocks:
		party.append(b as StatBlock)
	party_changed.emit()


## True while at least one party member is standing.
func party_alive() -> bool:
	for b in party:
		if not b.is_down():
			return true
	return false


## {ok: bool, reason: String}. The party walks open ground one vertex at a time, a limited
## number each segment.
func can_move_party(to: Vector3i) -> Dictionary:
	if fighting():
		return _no("A fight is under way.")
	if phase != Phase.PLAN:
		return _no("Not planning.")
	if party.is_empty():
		return _no("There is no party to send.")
	if not party_alive():
		return _no("The party is down. They recover when the day turns.")
	if party_moves_left <= 0:
		return _no("The party is out of moves this segment.")
	if not world.has_vertex(to):
		return _no("Off the board.")
	if not HexGrid.vertex_neighbours(party_vertex).has(to):
		return _no("The party can only step to a neighbouring vertex.")
	if has_foes(to) and _combat_engine() == null:
		return _no("No rules engine, so there is nothing to fight with.")
	return _yes()


## Walks the party onto `to` and explores around it. Wild enemies there are fought at once,
## off-screen, in a real CombatSession. Returns {} if the move was refused; otherwise
## {fought: bool, result: FightResult}. A fight that is not settled in time sends the
## party back where it came from.
func move_party(to: Vector3i) -> Dictionary:
	var check := can_move_party(to)
	if not check["ok"]:
		log_line.emit(String(check["reason"]))
		return {}
	var from := party_vertex
	party_moves_left -= 1
	party_vertex = to
	world.explore_around(to, config.sight_radius)
	var report := {"fought": false, "result": FightResult.WON, "pending": false}
	if has_foes(to):
		report["fought"] = true
		var session := _start_wild_fight(to, from)
		if present_fights:
			report["pending"] = true
			party_changed.emit()
			return report
		_run_fight_now(session)
		report["result"] = _settle_fight()
	_bank_party_loot()
	party_changed.emit()
	return report


## True while a fight is under way and waiting to be settled.
func fighting() -> bool:
	return not fight.is_empty()


## True if wild enemies, roaming raiders or enemies held in a dungeon room stand on `v`.
func has_foes(v: Vector3i) -> bool:
	return has_wild(v) or raiders_at(v) > 0 or room_held(v) > 0


## Everyone the party would fight at `v`: the wild group's entries, the raiders' own entries
## (the same dictionaries held in `wild` and `raiders`, so their blocks persist), and the
## enemies a dungeon room holds. Raider entries have an "id" and room entries a "room"
## flag; wild ones have neither. Room entries are made fresh here from `gathered` and
## `carried`, and written back by _settle_fight().
func _foes_at(v: Vector3i) -> Array:
	var out: Array = []
	if wild.has(v):
		out.append_array(wild[v])
	for r in raiders:
		if r["vertex"] == v:
			out.append(r)
	for template: EnemyTemplate in (gathered.get(v, []) as Array):
		out.append({"template": template, "room": true})
	var tile: TileInstance = world.structures.get(v)
	if tile != null:
		for _i in int(carried.get(v, 0)):
			var extra: EnemyTemplate = _pick_enemy(tile, awake_borders(v))
			if extra != null:
				out.append({"template": extra, "room": true})
	return out


## Builds the session for the wild group at `v`, records it as the fight under way and begins
## it. A watched fight starts paused, so the player can give orders first.
func _start_wild_fight(v: Vector3i, from: Vector3i) -> CombatSession:
	var engine := _combat_engine()
	var group: Array = _foes_at(v)
	var foes: Array = []
	for entry in group:
		if not entry.has("block"):
			entry["block"] = (entry["template"] as EnemyTemplate).build_block(engine)
		foes.append(entry["block"])
	var friends: Array = []
	for b in party:
		if not b.is_down():
			friends.append(b)
	var session := CombatSession.new()
	session.start_paused = present_fights
	fight = {"vertex": v, "from": from, "group": group, "session": session}
	if present_fights:
		fight_starting.emit(session)
	session.begin(friends, foes, engine)
	if present_fights:
		fight_started.emit(session)
	return session


## Plays a fight out at once, with nobody watching.
func _run_fight_now(session: CombatSession) -> void:
	var step := 0.05
	var steps := int(config.raid_fight_seconds / step)
	while session.active and steps > 0:
		session.advance(step)
		steps -= 1
	session.free()


## The presenter calls this when the fight it was showing is over. Settles it, banks loot if
## the party is home, and tells listeners. Returns {} if no fight was waiting.
func finish_fight() -> Dictionary:
	if fight.is_empty():
		return {}
	var result := _settle_fight()
	_bank_party_loot()
	party_changed.emit()
	return {"fought": true, "result": result}


## Works out what the fight under way came to: loot from the fallen, the wild group cleared
## or whittled down, and a wipe or stalemate sending the party back. Survivors keep their
## wounds. Clears `fight`.
func _settle_fight() -> FightResult:
	var v: Vector3i = fight["vertex"]
	var from: Vector3i = fight["from"]
	var group: Array = fight["group"]
	fight = {}
	var left: Array = []
	var downed := 0
	var raiders_hit := false
	var had_room := false
	var xp_earned := 0
	var room_tile: TileInstance = world.structures.get(v)
	for entry in group:
		var is_room = entry.has("room")
		had_room = had_room or is_room
		if (entry["block"] as StatBlock).is_down():
			downed += 1
			xp_earned += maxi(0, (entry["template"] as EnemyTemplate).xp_value)
			var loot: Dictionary
			if is_room and room_tile != null:
				loot = _loot_for(room_tile, entry["template"], loot_multiplier(v))
			else:
				loot = _raider_loot(entry["template"])
			for id in loot:
				party_loot[id] = int(party_loot.get(id, 0)) + int(loot[id])
			if entry.has("id"):
				raiders.erase(entry)
				raiders_hit = true
		else:
			left.append(entry)
	var wild_left: Array = left.filter(
			func(e: Dictionary) -> bool: return not e.has("id") and not e.has("room"))
	if wild_left.is_empty():
		wild.erase(v)
	else:
		wild[v] = wild_left
	wild_changed.emit()
	if raiders_hit:
		raids_changed.emit()
	if had_room:
		# The room keeps whoever survived, as waiting enemies; the left-alive count is spent.
		var room_left: Array = []
		for e in left:
			if e.has("room"):
				room_left.append(e["template"])
		if room_left.is_empty():
			gathered.erase(v)
		else:
			gathered[v] = room_left
		carried.erase(v)
		tile_changed.emit(v)
	if left.is_empty():
		log_line.emit("Cleared %d enemies at (%d, %d, %d)." % [downed, v.x, v.y, v.z])
		_award_xp(xp_earned)
		return FightResult.WON
	if not party_alive():
		party_loot.clear()
		for b in party:
			b.refill()
		party_vertex = _origin
		party_moves_left = 0
		log_line.emit("The party was wiped out and wakes at the origin, empty-handed.")
		return FightResult.WIPED
	party_vertex = from
	log_line.emit("The fight dragged on. The party fell back.")
	return FightResult.STALEMATE


## Gives every active companion `amount` XP for a won fight (the player character earns
## none). Nothing happens for 0 or with no roster.
func _award_xp(amount: int) -> void:
	if amount <= 0:
		return
	var target: PartyRoster = roster if roster != null else Rules.roster
	if target == null:
		return
	var ready := Leveling.award_xp(target, amount)
	log_line.emit("The party gains %d XP." % amount)
	xp_awarded.emit(amount, ready)


## Brings what the party carries into stock when it stands on the origin.
func _bank_party_loot() -> void:
	if party_vertex != _origin or party_loot.is_empty():
		return
	var parts: PackedStringArray = []
	for id in party_loot:
		stock[id] = int(stock.get(id, 0)) + int(party_loot[id])
		parts.append("%s +%d" % [String(id).replace("_notes", ""), int(party_loot[id])])
	party_loot.clear()
	log_line.emit("Banked %s." % ", ".join(parts))


# ----------------------------------------------------------------- frontier

## The end of `e` that has not been explored, if the other end has: the way into the dark.
## HexGrid.NONE for any other edge, and always when vertex fog is off.
func unexplored_end(e: Vector3i) -> Vector3i:
	if not world.vertex_fog or not world.has_edge(e):
		return HexGrid.NONE
	var ends := HexGrid.edge_ends(e)
	var a_known := world.explored.has(ends[0])
	var b_known := world.explored.has(ends[1])
	if a_known and not b_known and world.has_vertex(ends[1]):
		return ends[1]
	if b_known and not a_known and world.has_vertex(ends[0]):
		return ends[0]
	return HexGrid.NONE


## Every edge whose two ends are both explored: the part of the grid the player can see
## in full. Empty when vertex fog is off.
func known_edges() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if not world.vertex_fog:
		return out
	for v: Vector3i in world.explored:
		for e: Vector3i in HexGrid.vertex_edges(v):
			if not world.has_edge(e):
				continue
			var ends := HexGrid.edge_ends(e)
			if ends[0] == v and world.explored.has(ends[1]):
				out.append(e)
	return out


## True if `e` joins an explored vertex to an unexplored one.
func is_frontier_edge(e: Vector3i) -> bool:
	return unexplored_end(e) != HexGrid.NONE


## Every edge between an explored vertex and an unexplored one. Walks the explored set, so
## it costs as much as what has been uncovered, not as much as the board.
func frontier_edges() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if not world.vertex_fog:
		return out
	for v: Vector3i in world.explored:
		for e: Vector3i in HexGrid.vertex_edges(v):
			if is_frontier_edge(e):
				out.append(e)
	return out


## The vertices the party would step through to reach `to`, from where it stands (not
## counting its own vertex; `to` last). Only open ground is crossed: explored vertices free
## of wild enemies, apart from `to` itself. Empty if there is no way.
func party_path(to: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	if party_vertex == HexGrid.NONE or to == party_vertex or not world.has_vertex(to):
		return path
	var came := {party_vertex: party_vertex}
	var queue: Array[Vector3i] = [party_vertex]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_front()
		for nxt: Vector3i in HexGrid.vertex_neighbours(cur):
			if came.has(nxt) or not world.has_vertex(nxt):
				continue
			if nxt != to and (not world.is_explored(nxt) or has_foes(nxt)):
				continue
			came[nxt] = cur
			if nxt == to:
				var step := to
				while step != party_vertex:
					path.push_front(step)
					step = came[step]
				return path
			queue.append(nxt)
	return path


## {ok: bool, reason: String, steps: int}. The party can walk to `to` if explored open ground
## leads there and it has the moves left for every step.
func can_travel_to(to: Vector3i) -> Dictionary:
	if fighting():
		return _no("A fight is under way.")
	if phase != Phase.PLAN:
		return _no("Not planning.")
	if party.is_empty():
		return _no("There is no party to send.")
	if not party_alive():
		return _no("The party is down. They recover when the day turns.")
	var path := party_path(to)
	if path.is_empty():
		return _no("No explored way there.")
	if path.size() > party_moves_left:
		return _no("Needs %d moves; the party has %d." % [path.size(), party_moves_left])
	if has_foes(to) and _combat_engine() == null:
		return _no("No rules engine, so there is nothing to fight with.")
	var ok := _yes()
	ok["steps"] = path.size()
	return ok


## Walks the party along party_path(to), a step at a time. Stops early if a fight happens
## or the party is thrown back. Returns the last step's report, or {} if it was refused.
func travel_party(to: Vector3i) -> Dictionary:
	var check := can_travel_to(to)
	if not check["ok"]:
		log_line.emit(String(check["reason"]))
		return {}
	var report := {}
	for step: Vector3i in party_path(to):
		report = move_party(step)
		if report.is_empty() or bool(report["fought"]) or party_vertex != step:
			break
	return report


# ------------------------------------------------------------ blueprints

## True if `def` can only be built from a blueprint drawn today: dungeon (Bass Clef) tiles.
func needs_blueprint(def: TileDef) -> bool:
	return config.require_blueprints and def.clef() == TileDef.Clef.BASS \
			and not def.is_exit and not def.is_segno


## Throws away unspent blueprints and draws a fresh hand. Rarer tiles have lower
## weights, and every copy already in the hand makes another less likely. Bonus
## blueprints earned from hazards are added to this hand and then used up.
func draw_blueprints() -> void:
	blueprints.clear()
	extra_blueprint = null
	if config.require_blueprints:
		var standing := _standing_bass_ids()
		var copies := {}
		for _i in config.blueprints_per_day + bonus_blueprints_pending:
			var candidates: Array[TileDef] = []
			var weights: Array[float] = []
			for def in blueprint_pool:
				if def == null or def.clef() != TileDef.Clef.BASS or def.is_exit or def.is_segno:
					continue
				if def.blueprint_weight <= 0.0 or def.blueprint_min_day > day:
					continue
				if not _sources_standing(def, standing) or not is_unlocked(def):
					continue
				candidates.append(def)
				weights.append(def.blueprint_weight
						/ (1.0 + config.blueprint_repeat_penalty * int(copies.get(def, 0))))
			var index := _weighted_index(weights)
			if index < 0:
				break
			blueprints.append(candidates[index])
			copies[candidates[index]] = int(copies.get(candidates[index], 0)) + 1
			if not persistent.seen_blueprints.has(candidates[index].id):
				persistent.seen_blueprints.append(candidates[index].id)
		extra_blueprint = _standing_pick(standing)
	bonus_blueprints_pending = 0
	blueprints_changed.emit()


## Ids of every standing dungeon room, plus the exit (which always stands). A room also
## counts as every building it was upgraded from. Blueprint sources are checked against these.
func _standing_bass_ids() -> Dictionary:
	var ids := {exit_def.id: true}
	for v: Vector3i in world.structures:
		var tile: TileInstance = world.structures[v]
		if tile.def.clef() == TileDef.Clef.BASS and tile.is_live():
			_mark_ids(ids, tile)
	return ids


## True if `def` has no source rooms, or one of them is in `standing` (see
## _standing_bass_ids).
func _sources_standing(def: TileDef, standing: Dictionary) -> bool:
	if def.blueprint_source_ids.is_empty():
		return true
	for source_id in def.blueprint_source_ids:
		if standing.has(source_id):
			return true
	return false


## True if `def` could be drawn today as far as its source rooms go.
func blueprint_sources_met(def: TileDef) -> bool:
	return _sources_standing(def, _standing_bass_ids())


## The standing pick as a TileDef, if it can be offered today: it must be in the pool,
## a dungeon tile, and have a source room standing. Null otherwise.
func _standing_pick(standing: Dictionary) -> TileDef:
	if persistent.standing_blueprint == &"":
		return null
	for def in blueprint_pool:
		if def == null or def.id != persistent.standing_blueprint:
			continue
		if def.clef() != TileDef.Clef.BASS or def.is_exit or def.is_segno:
			return null
		return def if _sources_standing(def, standing) and is_unlocked(def) else null
	return null


# ---- standing blueprint

## True if a card for `def` is in hand, either a normal one or today's extra copy.
func has_blueprint_for(def: TileDef) -> bool:
	return blueprints.has(def) or extra_blueprint == def


## True if placing `def` right now would spend the extra copy (so it costs more): there
## is no normal card for it, only the standing one.
func uses_extra_blueprint(def: TileDef) -> bool:
	return extra_blueprint != null and extra_blueprint == def and not blueprints.has(def) \
			and needs_blueprint(def)


## Blueprints from the pool the player has seen before: the ones the standing pick can
## be changed to.
func seen_blueprint_defs() -> Array[TileDef]:
	var out: Array[TileDef] = []
	for def in blueprint_pool:
		if def != null and persistent.seen_blueprints.has(def.id) \
				and def.clef() == TileDef.Clef.BASS and not def.is_exit and not def.is_segno:
			out.append(def)
	return out


## {ok: bool, reason: String}. Only a blueprint seen before can be made the standing pick.
func can_set_standing_blueprint(def: TileDef) -> Dictionary:
	if def == null:
		return _yes()  # clears the pick
	if def.clef() != TileDef.Clef.BASS or def.is_exit or def.is_segno:
		return _no("Not a dungeon blueprint.")
	if not persistent.seen_blueprints.has(def.id):
		return _no("You haven't seen that blueprint yet.")
	return _yes()


## Sets (or with null clears) the blueprint that gets an extra copy in every day's hand.
## It takes effect at the next dawn; today's hand is left as it is.
func set_standing_blueprint(def: TileDef) -> bool:
	var check := can_set_standing_blueprint(def)
	if not check["ok"]:
		log_line.emit(String(check["reason"]))
		return false
	persistent.standing_blueprint = def.id if def != null else &""
	blueprints_changed.emit()
	return true


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


## {ok: bool, reason: String}. The Segno is a room of its own, placed free of charge on an
## empty vertex where a road ends, like any other room. Moving it doesn't count the old
## Segno as a neighbour. Whether it connects to the exit is checked when the day starts,
## so you can place it before the route is finished.
func can_set_segno(v: Vector3i) -> Dictionary:
	if phase != Phase.PLAN:
		return _no("Not planning.")
	if has_segno() and v == segno:
		return _no("The Segno is already there.")
	if ruins.has(v):
		return _no("A ruin stands there.")
	return world.can_build_structure(v, segno)


## Builds the Segno room at `v`, taking the previous one away. Free.
func set_segno(v: Vector3i) -> bool:
	var check := can_set_segno(v)
	if not check["ok"]:
		log_line.emit(String(check["reason"]))
		return false
	var old := segno
	if has_segno():
		world.remove_structure(old)
		tile_changed.emit(old)
	world.build_structure(v, TileInstance.new(segno_def, Vector2i.ZERO))
	segno = v
	_path_dirty = true
	tile_changed.emit(v)
	segno_changed.emit()
	log_line.emit("Segno set at (%d, %d, %d)." % [v.x, v.y, v.z])
	return true


## Picks the Segno room up again.
func clear_segno() -> void:
	if not has_segno():
		return
	var old := segno
	world.remove_structure(old)
	segno = NO_SEGNO
	_path_dirty = true
	tile_changed.emit(old)
	segno_changed.emit()


## The vertex the party appears on.
func spawn_vertex() -> Vector3i:
	return segno if config.require_segno and has_segno() else _origin


## {ok: bool, reason: String}.
func can_start_expedition() -> Dictionary:
	if phase != Phase.PLAN:
		return _no("Not planning.")
	if config.require_segno:
		if not has_segno():
			return _no("Place the Segno first.")
		var room := tile_at(segno)
		if room == null or not room.def.is_segno or not room.is_live():
			return _no("The Segno room is missing.")
		if not bool(main_path()["connected"]):
			return _no("The Segno must connect to the exit.")
	return _yes()


# -------------------------------------------------------------- main path

## Roads between the vertices that still carry anything: a spent room no longer connects
## its neighbours, so its vertex drops out (the Segno and the exit never do). A building
## site is not a room yet but still carries the road through it.
func _live_graph() -> Dictionary:
	var graph := world.road_graph()
	var dead := {}
	for v: Vector3i in graph:
		var tile: TileInstance = world.structures.get(v)
		if tile != null and tile.is_depleted() and v != _origin and v != segno:
			dead[v] = true
	if dead.is_empty():
		return graph
	var out := {}
	for v: Vector3i in graph:
		if dead.has(v):
			continue
		var onward: Array = []
		for nxt: Vector3i in graph[v]:
			if not dead.has(nxt):
				onward.append(nxt)
		out[v] = onward
	return out


## The scored layout, cached until something changes:
## {found, connected, path (Segno first, exit last), steps, loops, bonus, capped,
##  on_path (set), reach (set of vertices reachable from the spawn)}.
func main_path() -> Dictionary:
	if not _path_dirty:
		return _path_cache
	_path_dirty = false
	var graph := _live_graph()
	var reach := HexMainPath.reachable(graph, spawn_vertex())
	var info := {
		"found": false, "connected": reach.has(_origin), "path": [], "steps": 0, "loops": 0,
		"bonus": 0.0, "capped": false, "on_path": {}, "reach": reach,
	}
	if config.require_segno and has_segno() and graph.has(segno) and graph.has(_origin):
		var result := HexMainPath.find(graph, segno, _origin, config.main_path_search_limit)
		if bool(result["found"]):
			info["found"] = true
			info["path"] = result["path"]
			info["steps"] = int(result["steps"])
			info["loops"] = int(result["loops"])
			info["capped"] = bool(result["capped"])
			info["on_path"] = result["on_path"]
			info["bonus"] = HexMainPath.bonus(int(result["steps"]), int(result["loops"]),
					config.main_path_bonus_per_step, config.loop_penalty)
	_path_cache = info
	return info


## Loot multiplier for an encounter room: rooms on the main path gain its bonus, rooms
## with no road to the spawn are cut.
func loot_multiplier(v: Vector3i) -> float:
	var info := main_path()
	var mult := 1.0
	if bool(info["found"]) and (info["on_path"] as Dictionary).has(v):
		mult += float(info["bonus"])
	if not (info["reach"] as Dictionary).has(v):
		mult *= config.disconnected_loot_multiplier
	return mult


# ----------------------------------------------------------- pressure

## Levels added to every enemy spawned at `v` today.
func level_bonus(v: Vector3i) -> int:
	var bonus := int(floor((day - 1) * config.level_per_day))
	if int(carried.get(v, 0)) > 0:
		bonus += config.carried_level_bonus
	return bonus


## Roads from the exit to `v` along the shortest route that avoids spent rooms, or -1 if
## `v` is cut off.
func distance_to_exit(v: Vector3i) -> int:
	if v == _origin:
		return 0
	var graph := _live_graph()
	if not graph.has(_origin):
		return -1
	var seen := {_origin: 0}
	var queue: Array[Vector3i] = [_origin]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_front()
		if cur == v:
			return seen[cur]
		for nxt: Vector3i in graph.get(cur, []):
			if not seen.has(nxt):
				seen[nxt] = int(seen[cur]) + 1
				queue.append(nxt)
	return -1


# ------------------------------------------------------------------- dawn

## Rolls the dice and wakes every hex carrying a rolled number, replacing the previous
## segment's awake hexes. Called when a segment begins.
func _roll_wake() -> void:
	rolls.clear()
	awake.clear()
	for _i in maxi(1, config.wake_rolls_per_segment):
		var total := _roll_2d6()
		rolls.append(total)
		for hex in world.hexes_with_number(total):
			awake[hex] = true
	awake_changed.emit()
	muster_allies()
	spawn_raids()
	spawn_frontier_raids()


func _roll_2d6() -> int:
	var total := rng.randi_range(1, 6) + rng.randi_range(1, 6)
	while total == 7 and config.reroll_sevens:
		total = rng.randi_range(1, 6) + rng.randi_range(1, 6)
	return total


## Wakes exactly these hexes, replacing the roll's result. For tests, debugging and
## scripted scenarios: normally the dice decide.
func set_awake(woken: Array[Vector2i]) -> void:
	awake.clear()
	for hex in woken:
		if world.has_hex(hex):
			awake[hex] = true
	awake_changed.emit()


## The awake hexes beside the vertex `v`.
func awake_borders(v: Vector3i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for hex in world.hexes_at(v):
		if awake.has(hex):
			out.append(hex)
	return out


## How many spawn tokens the dungeon room at `v` gathers this segment, not counting
## enemies carried over from yesterday: its spawn_count for each awake hex beside it, or
## config.idle_spawn_count when none is awake. 0 if there is no such room. Each enemy
## spends its spawn_cost of these tokens, so this is a budget, not a head count.
func spawn_count_at(v: Vector3i) -> int:
	var tile := _live_bass_tile(v)
	if tile == null or tile.def.is_exit or tile.def.enemies.is_empty():
		return 0
	var woke := awake_borders(v).size()
	return effective_spawn_count(tile) * woke if woke > 0 else config.idle_spawn_count


## Banks this segment's enemies in every dungeon room. The room spends spawn_count_at(v)
## tokens on enemies picked by the awake hexes' colours, each costing its spawn_cost, and
## adds them to whatever the room already holds. Unspent tokens (too few left for any
## enemy the room can field) are lost. Once per segment.
func _gather_segment() -> void:
	if _gathered_this_segment:
		return
	_gathered_this_segment = true
	var vertices: Array = world.structures.keys()
	vertices.sort_custom(_vertex_less)
	for v: Vector3i in vertices:
		var budget := spawn_count_at(v)
		if budget <= 0:
			continue
		var tile := _live_bass_tile(v)
		var borders := awake_borders(v)
		var held: Array = gathered.get(v, [])
		while budget > 0:
			var template := _pick_enemy(tile, borders, budget)
			if template == null:
				break  # nothing left that the remaining tokens can pay for
			held.append(template)
			budget -= template.spawn_cost
		gathered[v] = held
	_leak_overflow()


## Enemies waiting in the room at `v` from earlier segments, not counting this segment's.
func gathered_at(v: Vector3i) -> int:
	return (gathered.get(v, []) as Array).size()


# ------------------------------------------------------------------ raids

## Enemies roaming the map, each attacking the structure at its vertex: {id, vertex,
## template}. They spawn when a hex wakes beside a structure that no dungeon room covers,
## and when a room overflows. You fight them in person (they join the expedition's spawns);
## the ones you leave are dealt with when the segment ends.
var raiders: Array[Dictionary] = []
## Friendly units: {id, home, vertex, behavior, range, template, block}. A defensive room (a
## TileDef with an `ally`) musters them each segment. A guard holds its room's vertex; a
## patrol walks the roads to the nearest unopposed raiders (see _send_patrols). They fight
## raiders with the same CombatSession the party uses, and are lost with their room.
var allies: Array[Dictionary] = []
var _next_ally_id := 0
## The rules engine off-screen fights run on. Null = Rules.engine.
var combat_engine: RulesEngine = null
var _next_raider_id := 0

## Raiders were added, fought, or a structure was hurt or fell.
signal raids_changed
## The run is over (the party was defeated, or the origin fell to raiders). `reason` says why.
signal run_ended(reason: String)


func raids_enabled() -> bool:
	return config.raids_enabled


## The spawn count that decides a room's size: its building's own.
func effective_spawn_count(tile: TileInstance) -> int:
	return maxi(0, tile.def.spawn_count)


## 0 small, 1 medium, 2 large: how many of the size thresholds the room's spawn count meets.
func room_size(tile: TileInstance) -> int:
	var count := effective_spawn_count(tile)
	var size := 0
	for threshold in config.room_size_thresholds:
		if count >= threshold:
			size += 1
	return mini(size, 2)


func _by_size(table: Array[int], tile: TileInstance) -> int:
	if table.is_empty():
		return 0
	return table[clampi(room_size(tile), 0, table.size() - 1)]


## Road steps the room's safe zone reaches: its size tier's radius.
func cover_radius(tile: TileInstance) -> int:
	return maxi(0, _by_size(config.cover_radius_by_size, tile))


## Enemies the room can hold before it is full: its size tier's capacity.
func room_capacity(tile: TileInstance) -> int:
	return maxi(0, _by_size(config.capacity_by_size, tile))


## A finished dungeon room that gathers enemies, so it can act as a safe zone.
func is_safe_room(tile: TileInstance) -> bool:
	return tile != null and tile.is_live() and tile.def.clef() == TileDef.Clef.BASS \
			and not tile.def.is_exit and not tile.def.is_segno \
			and not tile.def.enemies.is_empty() and effective_spawn_count(tile) > 0


## Enemies the room at `v` holds right now (waiting from earlier segments, or left alive).
func room_held(v: Vector3i) -> int:
	return gathered_at(v) + int(carried.get(v, 0))


## Room left in the safe room at `v`, 0 if it is not one.
func room_spare(v: Vector3i) -> int:
	var tile: TileInstance = world.structures.get(v)
	if not is_safe_room(tile):
		return 0
	return maxi(0, room_capacity(tile) - room_held(v))


## Only town tiles are raided (never the Town Square). Dungeon rooms are safe zones, not
## targets.
func _can_be_raided(v: Vector3i) -> bool:
	var tile: TileInstance = world.structures.get(v)
	return tile != null and tile.def.clef() == TileDef.Clef.TREBLE \
			and not tile.def.is_origin and v != _origin


## True if raiders standing at `v` can hurt what is there: any structure, a town tile, a
## dungeon room or the origin itself (its fall ends the run). Only the Segno, a marker
## rather than a building, is left alone. Raiders walking the roads stop at the first one.
func _can_be_attacked(v: Vector3i) -> bool:
	var tile: TileInstance = world.structures.get(v)
	return tile != null and not tile.def.is_segno


## The nearest safe room (by road steps) whose zone reaches `v` and that has room left in
## `spare` (vertex -> room left, filled in as rooms are first met). NONE if there is none.
func _covering_room(v: Vector3i, graph: Dictionary, spare: Dictionary) -> Vector3i:
	var max_radius := 0
	for r in config.cover_radius_by_size:
		max_radius = maxi(max_radius, r)
	var seen := {v: 0}
	var queue: Array[Vector3i] = [v]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_front()
		var dist: int = seen[cur]
		var tile: TileInstance = world.structures.get(cur)
		if is_safe_room(tile):
			if not spare.has(cur):
				spare[cur] = room_spare(cur)
			if int(spare[cur]) > 0 and dist <= cover_radius(tile):
				return cur
		if dist >= max_radius:
			continue
		for nxt: Vector3i in graph.get(cur, []):
			if not seen.has(nxt):
				seen[nxt] = dist + 1
				queue.append(nxt)
	return HexGrid.NONE


## True if a safe room with space to spare covers the structure at `v`.
func is_covered(v: Vector3i) -> bool:
	return _covering_room(v, _live_graph(), {}) != HexGrid.NONE


## The vertices the safe room at `v` reaches, by road steps within its cover radius (the
## room's own vertex included). Empty if `v` is not a safe room.
func cover_zone(v: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var tile: TileInstance = world.structures.get(v)
	if not is_safe_room(tile):
		return out
	var graph := _live_graph()
	var radius := cover_radius(tile)
	var seen := {v: 0}
	var queue: Array[Vector3i] = [v]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_front()
		out.append(cur)
		if int(seen[cur]) >= radius:
			continue
		for nxt: Vector3i in graph.get(cur, []):
			if not seen.has(nxt):
				seen[nxt] = int(seen[cur]) + 1
				queue.append(nxt)
	return out


## The nearest town tile raiders can attack, by road steps from `v` (`v` itself if it is
## one). NONE if none is reachable.
func _raid_target(v: Vector3i, graph: Dictionary) -> Vector3i:
	var seen := {v: true}
	var queue: Array[Vector3i] = [v]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_front()
		if _can_be_raided(cur):
			return cur
		for nxt: Vector3i in graph.get(cur, []):
			if not seen.has(nxt):
				seen[nxt] = true
				queue.append(nxt)
	return HexGrid.NONE


func raiders_at(v: Vector3i) -> int:
	var n := 0
	for r in raiders:
		if r["vertex"] == v:
			n += 1
	return n


func _add_raider(v: Vector3i, template: EnemyTemplate, frontier := false) -> void:
	var entry := {"id": _next_raider_id, "vertex": v, "template": template}
	if frontier:
		entry["frontier"] = true  # counts toward frontier_raider_cap; walks the roads like any raider
	raiders.append(entry)
	_next_raider_id += 1


## Called as a segment's roll is made: every town tile beside an awake hex draws raiders.
## Ones a safe room covers gather in it (taking up its space); the rest roam and attack
## the structure they were born on.
func spawn_raids() -> void:
	if not config.raids_enabled or config.raider_templates.is_empty():
		return
	var graph := _live_graph()
	var spare := {}
	var vertices: Array = world.structures.keys()
	vertices.sort_custom(_vertex_less)
	var roaming := 0
	for v: Vector3i in vertices:
		if not _can_be_raided(v):
			continue
		for _i in awake_borders(v).size() * config.raiders_per_wake:
			var template: EnemyTemplate = config.raider_templates[
					rng.randi_range(0, config.raider_templates.size() - 1)]
			var room := _covering_room(v, graph, spare)
			if room != HexGrid.NONE:
				var held: Array = gathered.get(room, [])
				held.append(template)
				gathered[room] = held
				spare[room] = int(spare[room]) - 1
			else:
				_add_raider(v, template)
				roaming += 1
	if roaming > 0:
		log_line.emit("%d raiders roam." % roaming)
		raids_changed.emit()


## A room holding more than its capacity leaks the surplus: those enemies go to attack the
## nearest town tile. With none to attack, the surplus stays crowded in the room.
func _leak_overflow() -> void:
	if not config.raids_enabled:
		return
	var graph := _live_graph()
	var vertices: Array = world.structures.keys()
	vertices.sort_custom(_vertex_less)
	var leaked := 0
	for v: Vector3i in vertices:
		var tile: TileInstance = world.structures[v]
		if not is_safe_room(tile):
			continue
		var held: Array = gathered.get(v, [])
		var over := room_held(v) - room_capacity(tile)
		var target := _raid_target(v, graph)
		while over > 0 and not held.is_empty() and target != HexGrid.NONE:
			var template: EnemyTemplate = held.pop_back()
			_add_raider(target, template)
			over -= 1
			leaked += 1
		gathered[v] = held
	if leaked > 0:
		log_line.emit("%d enemies leak from full rooms." % leaked)
		raids_changed.emit()


# ---- frontier raids

## True when explored ground outside the dungeons draws raiders of its own.
func frontier_raids_active() -> bool:
	return config.frontier_raids_enabled and config.raids_enabled and world.vertex_fog \
			and not config.raider_templates.is_empty()


## How many frontier raiders are alive on the map.
func frontier_raider_count() -> int:
	var n := 0
	for r in raiders:
		if r.get("frontier", false):
			n += 1
	return n


## Every vertex some dungeon room's safe zone reaches (road steps within its cover radius,
## the room's own vertex included). Capacity is ignored: this is the room's territory.
func _covered_vertices() -> Dictionary:
	var covered := {}
	var graph := _live_graph()
	for sv: Vector3i in world.structures:
		var tile: TileInstance = world.structures[sv]
		if not is_safe_room(tile):
			continue
		var radius := cover_radius(tile)
		var seen := {sv: 0}
		var queue: Array[Vector3i] = [sv]
		while not queue.is_empty():
			var cur: Vector3i = queue.pop_front()
			covered[cur] = true
			if int(seen[cur]) >= radius:
				continue
			for nxt: Vector3i in graph.get(cur, []):
				if not seen.has(nxt):
					seen[nxt] = int(seen[cur]) + 1
					queue.append(nxt)
	return covered


## Called as a segment's roll is made. Every explored vertex a road reaches (the origin's
## own aside) draws
## `frontier_raiders_per_wake` enemies for each awake hex beside it.
##   - Outside every dungeon room's reach they roam as frontier raiders.
##   - Inside a room's reach they gather in that room instead, taking up its space, exactly
##     as a town tile's raiders do (see spawn_raids). This covers every explored vertex the
##     room reaches, built on or not. Vertices with a structure are left to spawn_raids (town
##     tiles) and to the room's own gathering (dungeon rooms), so nothing is drawn twice.
##   - If the covering room is full, they roam like the rest.
## Roaming ones are shuffled so that, under the cap, no corner of the map is favoured; the
## cap counts only the roamers, since enemies gathered in a room are limited by its capacity.
func spawn_frontier_raids() -> void:
	if not frontier_raids_active() or config.frontier_raiders_per_wake <= 0:
		return
	var cap := config.frontier_raider_cap
	var alive := frontier_raider_count()
	var graph := _live_graph()
	var covered := _covered_vertices()
	var spare := {}
	var candidates: Array[Vector3i] = []
	var network := world.road_graph()  # raiders only rise where a road reaches
	for v: Vector3i in world.explored:
		if v == _origin or not network.has(v) or awake_borders(v).is_empty():
			continue
		if covered.has(v) and world.structures.has(v):
			continue  # town tiles and dungeon rooms have their own rules
		candidates.append(v)
	candidates.sort_custom(_vertex_less)
	for i in range(candidates.size() - 1, 0, -1):  # Fisher-Yates, on the cycle's own rng
		var j := rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	var spawned := 0
	var collected := 0
	for v: Vector3i in candidates:
		for _i in awake_borders(v).size() * config.frontier_raiders_per_wake:
			var room := _covering_room(v, graph, spare) if covered.has(v) else HexGrid.NONE
			if room != HexGrid.NONE:
				var held: Array = gathered.get(room, [])
				held.append(config.raider_templates[
						rng.randi_range(0, config.raider_templates.size() - 1)])
				gathered[room] = held
				spare[room] = int(spare[room]) - 1
				collected += 1
				continue
			if cap > 0 and alive >= cap:
				break
			_add_raider(v, config.raider_templates[
					rng.randi_range(0, config.raider_templates.size() - 1)], true)
			alive += 1
			spawned += 1
	if collected > 0:
		log_line.emit("%d enemies gather in the rooms from the ground they reach." % collected)
		raids_changed.emit()
	if spawned > 0:
		log_line.emit("%d raiders rise from the unguarded dark." % spawned)
		raids_changed.emit()


## Every raider not standing on something it can attack walks up to config.raider_steps
## vertices along the roads toward the origin (the road step that is nearer the origin; ties
## go to the lowest vertex), and stops at the first structure it can attack, so whatever
## stands in the way is hit before the raider goes on. Raiders never leave the roads.
func _march_raiders() -> void:
	if config.raider_steps <= 0 or raiders.is_empty():
		return
	var graph := world.road_graph()
	var depth := _road_depths(graph)
	for r in raiders:
		for _s in config.raider_steps:
			var here: Vector3i = r["vertex"]
			if _can_be_attacked(here) or not depth.has(here) or int(depth[here]) == 0:
				break
			var best := HexGrid.NONE
			for nxt: Vector3i in graph.get(here, []):
				if depth.has(nxt) and int(depth[nxt]) < int(depth[here]) \
						and (best == HexGrid.NONE or _vertex_less(nxt, best)):
					best = nxt
			if best == HexGrid.NONE:
				break
			r["vertex"] = best


## What a raider carries: the enemy's own notes (a random colour if it is uncoloured).
func _raider_loot(template: EnemyTemplate) -> Dictionary:
	var out := {}
	if template.notes_per_kill > 0:
		out[_drop_note_id(template)] = int(template.notes_per_kill)
	return out


## The note colour `template` drops: its own, or one picked at random if it has none.
func _drop_note_id(template: EnemyTemplate) -> StringName:
	var channel := int(template.note_color) - 1
	if channel < 0:
		channel = rng.randi_range(0, 2)
	return _note_id(channel)


## The end of a segment for raiders nobody fought in person. Where allies stand guard they
## fight the raiders in a real CombatSession, stepped without any presentation. Raiders
## still standing with no ally left hurt the structure they are on (any kind, the origin
## included); one that falls becomes a ruin. Then every raider not on a structure walks
## `raider_steps` along the roads toward the origin, stopping at the first thing in its way.
func _resolve_raids() -> void:
	_prune_allies()
	if raiders.is_empty():
		return
	_send_patrols(_live_graph())
	var by_vertex := {}
	for r in raiders:
		var group: Array = by_vertex.get(r["vertex"], [])
		group.append(r)
		by_vertex[r["vertex"]] = group
	var vertices: Array = by_vertex.keys()
	vertices.sort_custom(_vertex_less)
	for v: Vector3i in vertices:
		var group: Array = by_vertex[v]
		if not allies_at(v).is_empty():
			_fight_raiders(group, allies_at(v))
		if group.is_empty() or not allies_at(v).is_empty() or not _can_be_attacked(v):
			continue
		_damage_structure(v, group.size() * config.raid_damage_per_raider)
		if phase == Phase.OVER:  # the origin fell: the run, and this resolution, are done
			return
	_march_raiders()
	raids_changed.emit()


func _combat_engine() -> RulesEngine:
	return combat_engine if combat_engine != null else Rules.engine


## Runs one fight between allies (`guards`, entries of `allies`) and a group of raiders
## through the same CombatSession the player's fights use, with no bodies, no HUD and no
## camera: everyone counts as in reach, and time is stepped here instead of by the engine's
## frames. Raiders and allies keep their StatBlock between segments, so wounds carry over.
## Whoever is downed is removed from `group` and `raiders`, or from `allies`.
func _fight_raiders(group: Array, guards: Array) -> void:
	var engine := _combat_engine()
	if engine == null:
		push_warning("HexDayCycle: no rules engine, so the fight at a raided tile is skipped.")
		return
	var foes: Array = []
	for r in group:
		if not r.has("block"):
			r["block"] = (r["template"] as EnemyTemplate).build_block(engine)
		foes.append(r["block"])
	var session := CombatSession.new()
	session.start_paused = false
	var friends: Array = []
	for a in guards:
		friends.append(a["block"])
	session.begin(friends, foes, engine)
	var step := 0.05
	var steps := int(config.raid_fight_seconds / step)
	while session.active and steps > 0:
		session.advance(step)
		steps -= 1
	session.free()
	for r in group.duplicate():
		if (r["block"] as StatBlock).is_down():
			group.erase(r)
			raiders.erase(r)
	for a in guards:
		if (a["block"] as StatBlock).is_down():
			allies.erase(a)


# ----------------------------------------------------------------- upgrades
#
# An upgrade turns a finished room into a different building (RoomUpgrade.into). The
# steps a room can take are the ones listed on the TileDef it is right now, so each
# building offers its own next steps and the tree is simply buildings pointing at buildings.

## The step on `def` that leads to the building `id`, or null.
func _upgrade_def(def: TileDef, id: StringName) -> RoomUpgrade:
	if def == null:
		return null
	for up in def.upgrades:
		if up != null and up.into != null and up.id == id:
			return up
	return null


func effective_max_health(tile: TileInstance) -> int:
	return maxi(1, tile.def.max_health)


## The unit the room musters: its building's.
func effective_ally(tile: TileInstance) -> AllyTemplate:
	return tile.def.ally


func ally_cap_of(tile: TileInstance) -> int:
	return maxi(0, tile.def.ally_cap)


func ally_per_segment_of(tile: TileInstance) -> int:
	return maxi(0, tile.def.ally_per_segment)


func ally_patrol_range_of(tile: TileInstance) -> int:
	return maxi(0, tile.def.ally_patrol_range)


## What the room's units do: its building's behaviour.
func ally_behavior_of(tile: TileInstance) -> int:
	return int(tile.def.ally_behavior)


## Why `up` cannot be taken by `tile` right now, ignoring cost. "" if nothing stops it.
func _upgrade_block(tile: TileInstance, up: RoomUpgrade) -> String:
	if up == null or up.into == null:
		return "That upgrade leads nowhere."
	if tile.upgrading != &"":
		var busy := _upgrade_def(tile.def, tile.upgrading)
		return "Busy: becoming %s in %d segment(s)." % [
				busy.label() if busy != null else String(tile.upgrading),
				tile.upgrade_left]
	return ""


func upgrade_cost(up: RoomUpgrade) -> Dictionary:
	return _normalised(up.cost)


## The steps the room at `v` could take next, ignoring cost: the buildings its current
## building can be upgraded into, unless it is already busy becoming one.
func available_upgrades(v: Vector3i) -> Array[RoomUpgrade]:
	var out: Array[RoomUpgrade] = []
	var tile: TileInstance = world.structures.get(v)
	if tile == null or not tile.is_live():
		return out
	for up in tile.def.upgrades:
		if up != null and _upgrade_block(tile, up) == "":
			out.append(up)
	return out


## {ok: bool, reason: String}. Upgrades are bought while planning, for a finished room.
func can_upgrade(v: Vector3i, id: StringName) -> Dictionary:
	if phase != Phase.PLAN:
		return _no("Not planning.")
	var tile: TileInstance = world.structures.get(v)
	if tile == null or not tile.is_live():
		return _no("Nothing finished to upgrade there.")
	var up := _upgrade_def(tile.def, id)
	if up == null:
		return _no("That room has no such upgrade.")
	var block := _upgrade_block(tile, up)
	if block != "":
		return _no(block)
	var price := upgrade_cost(up)
	for key in price:
		if int(stock.get(key, 0)) < int(price[key]):
			return _no("Cannot afford it.")
	return _yes()


func upgrade_tile(v: Vector3i, id: StringName) -> bool:
	var check := can_upgrade(v, id)
	if not check["ok"]:
		log_line.emit(String(check["reason"]))
		return false
	var tile: TileInstance = world.structures[v]
	var up := _upgrade_def(tile.def, id)
	var price := upgrade_cost(up)
	for key in price:
		stock[key] = int(stock.get(key, 0)) - int(price[key])
	if up.build_segments > 0:
		tile.upgrading = id
		tile.upgrade_left = up.build_segments
		log_line.emit("Upgrading %s into %s: %d segments." % [tile.def.display_name,
				up.label(), up.build_segments])
		tile_changed.emit(v)
		return true
	_finish_upgrade(v, tile, up)
	return true


## The upgrade takes effect: the room becomes the new building, its health follows, and its
## standing units take the new building's orders (or stand down if it musters none).
func _finish_upgrade(v: Vector3i, tile: TileInstance, up: RoomUpgrade) -> void:
	tile.upgrading = &""
	tile.upgrade_left = 0
	var old_name := tile.def.display_name
	tile.become(up.into)
	var musters := effective_ally(tile) != null and ally_cap_of(tile) > 0
	for a in allies.duplicate():  # units already standing take on the new orders
		if a["home"] != v:
			continue
		if not musters:
			allies.erase(a)
		else:
			a["behavior"] = ally_behavior_of(tile)
			a["range"] = ally_patrol_range_of(tile)
	log_line.emit("%s upgraded into %s." % [old_name, up.label()])
	tile_changed.emit(v)
	raids_changed.emit()


# ------------------------------------------------------------------ allies

## Adds a friendly unit to the room at `home`. Its StatBlock is built from `template`, or
## `block` is used as given (tests, scripted scenarios). Returns the unit, or {} if it cannot
## be built (no template and no block, or no rules engine).
func add_ally(home: Vector3i, template: AllyTemplate,
		behavior: int = TileDef.AllyBehavior.GUARD, patrol_range := 0,
		block: StatBlock = null) -> Dictionary:
	if block == null:
		var engine := _combat_engine()
		if engine == null or template == null:
			return {}
		block = template.build_block(engine)
	var unit := {
		"id": _next_ally_id, "home": home, "vertex": home, "behavior": behavior,
		"range": patrol_range, "template": template, "block": block,
	}
	_next_ally_id += 1
	allies.append(unit)
	return unit


## The friendly units standing at the vertex `v` right now.
func allies_at(v: Vector3i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in allies:
		if a["vertex"] == v:
			out.append(a)
	return out


## How many units belong to the room at `home`, wherever they are.
func allies_of(home: Vector3i) -> int:
	var n := 0
	for a in allies:
		if a["home"] == home:
			n += 1
	return n


## Units are lost with their room (fallen, erased, spent or ruined), and when downed.
func _prune_allies() -> void:
	for a in allies.duplicate():
		var tile: TileInstance = world.structures.get(a["home"])
		if tile == null or not tile.is_live() or (a["block"] as StatBlock).is_down():
			allies.erase(a)


## Called as a segment's roll is made: every finished defensive room musters up to its
## ally_per_segment new units, never beyond its ally_cap.
func muster_allies() -> void:
	_prune_allies()
	var vertices: Array = world.structures.keys()
	vertices.sort_custom(_vertex_less)
	var mustered := 0
	for v: Vector3i in vertices:
		var tile: TileInstance = world.structures[v]
		var unit := effective_ally(tile)
		var cap := ally_cap_of(tile)
		if not tile.is_live() or unit == null or cap <= 0:
			continue
		var room := mini(ally_per_segment_of(tile), cap - allies_of(v))
		for _i in room:
			if not add_ally(v, unit, ally_behavior_of(tile), ally_patrol_range_of(tile)).is_empty():
				mustered += 1
	if mustered > 0:
		log_line.emit("%d defenders muster." % mustered)
		raids_changed.emit()


## A new day is a long rest for the garrison.
func _rest_allies() -> void:
	for a in allies:
		(a["block"] as StatBlock).refill()


## Before a segment's fights: every unit returns to its room, then each patrol heads for the
## nearest raiders that no guard is already holding off. A raid is covered once as many
## units are headed there as there are raiders.
func _send_patrols(graph: Dictionary) -> void:
	var need := {}  # vertex -> raiders still without a unit to face them
	for r in raiders:
		need[r["vertex"]] = int(need.get(r["vertex"], 0)) + 1
	for a in allies:
		a["vertex"] = a["home"]
		if int(a["behavior"]) == TileDef.AllyBehavior.GUARD:
			need[a["home"]] = int(need.get(a["home"], 0)) - 1
	for a in allies:
		if int(a["behavior"]) != TileDef.AllyBehavior.PATROL:
			continue
		var goal := _patrol_goal(a, graph, need)
		if goal != HexGrid.NONE:
			a["vertex"] = goal
			need[goal] = int(need[goal]) - 1


## The nearest vertex (road steps from the patrol's room, within its range) that still has
## raiders to face; ties go to the lowest vertex. NONE if there is none.
func _patrol_goal(a: Dictionary, graph: Dictionary, need: Dictionary) -> Vector3i:
	var home: Vector3i = a["home"]
	var limit := int(a["range"])
	var seen := {home: true}
	var layer: Array[Vector3i] = [home]
	var steps := 0
	while not layer.is_empty():
		var hits: Array[Vector3i] = []
		for cur: Vector3i in layer:
			if int(need.get(cur, 0)) > 0:
				hits.append(cur)
		if not hits.is_empty():
			hits.sort_custom(_vertex_less)
			return hits[0]
		if limit > 0 and steps >= limit:
			break
		var following: Array[Vector3i] = []
		for cur: Vector3i in layer:
			for nxt: Vector3i in graph.get(cur, []):
				if not seen.has(nxt):
					seen[nxt] = true
					following.append(nxt)
		layer = following
		steps += 1
	return HexGrid.NONE


func _damage_structure(v: Vector3i, amount: int) -> void:
	var tile: TileInstance = world.structures.get(v)
	if tile == null or amount <= 0 or not _can_be_attacked(v):
		return
	tile.health -= amount
	tile_changed.emit(v)
	if tile.health > 0:
		log_line.emit("%s at (%d, %d, %d) is raided (%d left)." % [
				tile.def.display_name, v.x, v.y, v.z, tile.health])
		return
	if v == _origin:
		log_line.emit("%s falls to raiders." % tile.def.display_name)
		_end_run("The origin fell to raiders on day %d." % day)
		return
	world.remove_structure(v)
	ruins[v] = TileInstance.new(tile.def, Vector2i.ZERO, true)
	if shop_stock.erase(v):
		shop_changed.emit(v)
	_path_dirty = true
	log_line.emit("%s at (%d, %d, %d) falls to raiders." % [tile.def.display_name, v.x, v.y, v.z])
	tile_changed.emit(v)


## Damaged structures regain `raid_repair_per_day` health when a day begins.
func _repair_structures() -> void:
	if config.raid_repair_per_day <= 0:
		return
	for v: Vector3i in world.structures:
		var tile: TileInstance = world.structures[v]
		var top := effective_max_health(tile)
		if tile.health < top:
			tile.health = mini(top, tile.health + config.raid_repair_per_day)
			tile_changed.emit(v)


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
	_gather_segment()  # this segment's enemies join those left waiting by earlier ones
	var vertices: Array = world.structures.keys()
	vertices.sort_custom(_vertex_less)
	for v: Vector3i in vertices:
		var tile: TileInstance = world.structures[v]
		if not tile.is_live() or tile.def.clef() != TileDef.Clef.BASS \
				or tile.def.is_exit or tile.def.enemies.is_empty():
			continue
		var mult := loot_multiplier(v)
		var borders := awake_borders(v)
		var templates: Array = (gathered.get(v, []) as Array).duplicate()
		for _i in int(carried.get(v, 0)):
			templates.append(_pick_enemy(tile, borders))
		for template: EnemyTemplate in templates:
			spawns.append({
				"id": _next_spawn_id,
				"vertex": v,
				"template": template,
				"level": template.level + level_bonus(v),
				"loot": _loot_for(tile, template, mult),
				"alive": true,
			})
			_next_spawn_id += 1
	for r in raiders:
		var raider: EnemyTemplate = r["template"]
		spawns.append({
			"id": _next_spawn_id,
			"vertex": r["vertex"],
			"template": raider,
			"level": raider.level + level_bonus(r["vertex"]),
			"loot": _raider_loot(raider),
			"alive": true,
			"raider_id": r["id"],
		})
		_next_spawn_id += 1
	carried.clear()
	gathered.clear()
	_set_phase(Phase.EXPEDITION)
	log_line.emit("Expedition: %d enemies gather." % spawns.size())
	return spawns.duplicate()


func remaining() -> int:
	var n := 0
	for s in spawns:
		if s["alive"]:
			n += 1
	return n


## Lays one enemy to rest. Its loot is carried, not banked, until you return. Every
## note of a colour it drops also raises the room's matching colour channel.
func record_kill(spawn_id: int) -> Dictionary:
	if phase != Phase.EXPEDITION:
		return {}
	for s in spawns:
		if s["id"] == spawn_id and s["alive"]:
			s["alive"] = false
			for key in s["loot"]:
				carried_loot[key] = int(carried_loot.get(key, 0)) + int(s["loot"][key])
			if s.has("raider_id"):
				# A raider is not of the room it stands in, so it leaves no stain.
				for r in raiders:
					if r["id"] == s["raider_id"]:
						raiders.erase(r)
						break
				raids_changed.emit()
			else:
				_stain_room(s["vertex"], s["loot"])
			return s["loot"]
	return {}


func _stain_room(v: Vector3i, loot: Dictionary) -> void:
	var tile: TileInstance = world.structures.get(v)
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
	tile_changed.emit(v)
	if tile.is_depleted():
		_path_dirty = true  # a spent room no longer connects anything
		log_line.emit("Spent (%d, %d, %d)." % [v.x, v.y, v.z])


## Back at the exit: loot is banked and enemies still alive wait for tomorrow.
func return_to_exit() -> Dictionary:
	if phase != Phase.EXPEDITION:
		return {}
	var banked := carried_loot.duplicate()
	for key in banked:
		stock[key] = int(stock.get(key, 0)) + int(banked[key])
	var left_alive := 0
	for s in spawns:
		if s["alive"]:
			if not s.has("raider_id"):  # raiders stay on the map, not in a room
				carried[s["vertex"]] = int(carried.get(s["vertex"], 0)) + 1
			left_alive += 1
	carried_loot.clear()
	spawns.clear()
	_set_phase(Phase.SUMMARY)
	log_line.emit("Returned. %d enemies left alive." % left_alive)
	return {"banked": banked, "left_alive": left_alive}


## The party fell before reaching the exit. Carried loot is lost and the run ends. The
## dungeon and every road are wiped; every town tile but the origin is left as a ruin.
func defeat() -> void:
	if phase != Phase.EXPEDITION:
		return
	_end_run("The run ends on day %d." % day)


## Ends the run from any phase: the party fell, or the origin did. Same fallout either way.
func _end_run(reason: String) -> void:
	persistent.runs += 1
	persistent.best_day = maxi(persistent.best_day, day)
	var left_standing: Array[Dictionary] = []
	for v: Vector3i in world.structures:
		var tile: TileInstance = world.structures[v]
		if tile.def.clef() == TileDef.Clef.TREBLE and not tile.def.is_origin:
			left_standing.append({"vertex": v, "def": tile.def})
	for v: Vector3i in ruins:
		var ruin: TileInstance = ruins[v]
		left_standing.append({"vertex": v, "def": ruin.def})
	persistent.ruins.assign(left_standing)
	carried_loot.clear()
	spawns.clear()
	_new_board()
	segno = NO_SEGNO
	_path_dirty = true
	blueprints.clear()
	extra_blueprint = null
	bonus_blueprints_pending = 0
	shop_stock.clear()
	_reset_daily_features()
	rolls.clear()
	awake.clear()
	gathered.clear()
	raiders.clear()
	allies.clear()
	segment = Segment.DAWN
	_gathered_this_segment = false
	awake_changed.emit()
	_set_phase(Phase.OVER)
	log_line.emit(reason)
	run_ended.emit(reason)


# ------------------------------------------------------- next segment, next day

## Ends the current segment and begins the next one, whether or not anyone delved in it:
## this segment's enemies are gathered if nobody did, the party rests briefly, and the new
## segment's roll is made. After
## DUSK this is the same as begin_next_day() (income, a long rest) and returns its
## report; otherwise it returns {"segment": the new segment, "rolls": [...]}.
func begin_next_segment() -> Dictionary:
	if phase != Phase.SUMMARY and phase != Phase.PLAN:
		return {}  # not while delving: return to the exit first
	if segment >= Segment.DUSK:
		if phase == Phase.PLAN:
			_set_phase(Phase.SUMMARY)  # the day closes without a delve in this segment
		return begin_next_day()
	_gather_segment()
	_resolve_raids()
	if phase == Phase.OVER:  # raiders took the origin
		return {}
	_advance_construction()
	_grow_at_segment_end()
	segment = (int(segment) + 1) as Segment
	_gathered_this_segment = false
	_roll_wake()
	_set_phase(Phase.PLAN)
	party_rested.emit(false)
	party_moves_left = config.party_moves_per_segment
	party_changed.emit()
	segment_changed.emit(segment)
	log_line.emit("%s begins." % Segment.keys()[segment].capitalize())
	return {"segment": segment, "rolls": rolls.duplicate()}


# ---------------------------------------------------------------- next day

## Town income arrives, and the origin makes Hyle and grows the roads. Returns a report:
## {"income": {resource id: amount}, "hyle": Hyle made, "roads": roads laid}.
func begin_next_day() -> Dictionary:
	if phase != Phase.SUMMARY:
		return {}
	_gather_segment()  # a segment nobody delved in still fills its rooms
	_resolve_raids()
	if phase == Phase.OVER:  # raiders took the origin
		return {}
	_advance_construction()
	# Dusk is a segment's end too: the origin works on what was banked before income arrives.
	var grown := _grow_at_segment_end()
	_repair_structures()
	_rest_allies()
	day += 1
	var income := {}
	for v: Vector3i in world.structures:
		var tile: TileInstance = world.structures[v]
		if tile.def.clef() == TileDef.Clef.TREBLE and tile.is_live():
			for key in tile.def.income:
				var amount := int(tile.def.income[key])
				stock[StringName(key)] = int(stock.get(StringName(key), 0)) + amount
				income[StringName(key)] = int(income.get(StringName(key), 0)) + amount
	_reset_daily_features()
	_restock_shops()
	draw_blueprints()
	segment = Segment.DAWN
	_gathered_this_segment = false
	_roll_wake()
	_set_phase(Phase.PLAN)
	party_rested.emit(true)
	party_moves_left = config.party_moves_per_segment
	for b in party:  # the long rest: the party is whole again
		b.refill()
	party_changed.emit()
	segment_changed.emit(segment)
	log_line.emit("Day %d begins." % day)
	return {"income": income, "hyle": grown["hyle"], "roads": grown["roads"]}


# ------------------------------------------------------- room features

func feature_uses_today(v: Vector3i) -> int:
	return int(feature_uses.get(v, 0))


## Day boundary: rooms can be used again and every character's hit dice come back.
func _reset_daily_features() -> void:
	feature_uses.clear()
	hit_dice_spent.clear()


## The standing dungeon room at `v`, or null if there is none.
func _live_bass_tile(v: Vector3i) -> TileInstance:
	var tile: TileInstance = world.structures.get(v)
	if tile != null and tile.is_live() and tile.def.clef() == TileDef.Clef.BASS:
		return tile
	return null


## True if a enemy is still alive in the room at `v`.
func has_living_enemies(v: Vector3i) -> bool:
	for s in spawns:
		if bool(s["alive"]) and s["vertex"] == v:
			return true
	return false


# ---- short rest rooms

## {ok: bool, reason: String}. A rest room works on an expedition, up to its uses per
## day, and only once nothing is left alive in it.
func can_short_rest(v: Vector3i) -> Dictionary:
	if phase != Phase.EXPEDITION:
		return _no("Not on an expedition.")
	var tile := _live_bass_tile(v)
	if tile == null or tile.def.rest == null:
		return _no("No rest room here.")
	if has_living_enemies(v):
		return _no("enemies still hold this room.")
	if feature_uses_today(v) >= tile.def.rest.uses_per_day:
		return _no("Already used today.")
	return _yes()


## Uses the rest room at `v` once and returns its RestDef, or null if it can't be used
## (the reason is logged). What the rest does to the party is RoomFeatures.short_rest.
func use_short_rest(v: Vector3i) -> RestDef:
	var check := can_short_rest(v)
	if not check["ok"]:
		log_line.emit(String(check["reason"]))
		return null
	feature_uses[v] = feature_uses_today(v) + 1
	log_line.emit("Short rest at (%d, %d, %d)." % [v.x, v.y, v.z])
	return _live_bass_tile(v).def.rest


## Hit dice character `char_id` (at `level`) still has today.
func hit_dice_left(char_id: StringName, level: int) -> int:
	var pool := maxi(0, level) * config.hit_dice_per_level
	return maxi(0, pool - int(hit_dice_spent.get(char_id, 0)))


## Spends up to `count` of the character's hit dice. Returns how many were spent.
func spend_hit_dice(char_id: StringName, level: int, count: int) -> int:
	var spent := clampi(count, 0, hit_dice_left(char_id, level))
	if spent > 0:
		hit_dice_spent[char_id] = int(hit_dice_spent.get(char_id, 0)) + spent
	return spent


# ---- hazard rooms

## {ok: bool, reason: String}. A hazard goes off once per room per day, on an expedition.
func can_trigger_hazard(v: Vector3i) -> Dictionary:
	if phase != Phase.EXPEDITION:
		return _no("Not on an expedition.")
	var tile := _live_bass_tile(v)
	if tile == null or tile.def.hazard == null:
		return _no("No hazard here.")
	if feature_uses_today(v) > 0:
		return _no("Already sprung today.")
	return _yes()


## Sets the hazard at `v` off: marks it used and queues its bonus blueprints for the
## next dawn (up to WorldConfig.hazard_bonus_cap in total). Returns its HazardDef, or
## null if it can't go off. The saves and damage are RoomFeatures.resolve_hazard.
func trigger_hazard(v: Vector3i) -> HazardDef:
	if not can_trigger_hazard(v)["ok"]:
		return null
	var def := _live_bass_tile(v).def.hazard
	feature_uses[v] = 1
	bonus_blueprints_pending = mini(bonus_blueprints_pending + def.bonus_blueprints,
			maxi(config.hazard_bonus_cap, bonus_blueprints_pending))
	log_line.emit("Hazard at (%d, %d, %d)." % [v.x, v.y, v.z])
	blueprints_changed.emit()
	return def


# ---- shops

## The shop on the standing town tile at `v`, or null.
func shop_def_at(v: Vector3i) -> ShopDef:
	var tile: TileInstance = world.structures.get(v)
	if tile == null or not tile.is_live():
		return null
	return tile.def.shop


## What the shop at `v` has on its shelves: Array of {offer: ShopOffer, left: int}.
## Empty if there is no shop. Shelf order is stable until the next restock.
func shop_offers(v: Vector3i) -> Array:
	return (shop_stock.get(v, []) as Array).duplicate()


## Rolls the shop at `v` afresh.
func _stock_shop(v: Vector3i) -> void:
	shop_stock.erase(v)
	var shop := shop_def_at(v)
	if shop == null:
		shop_changed.emit(v)
		return
	var pool: Array[ShopOffer] = []
	for offer in shop.offers:
		if offer != null and offer.item != null and offer.weight > 0.0 and offer.copies > 0 \
				and offer.min_day <= day and not offer.price.is_empty():
			pool.append(offer)
	var shelves: Array = []
	for _i in shop.slots:
		var weights: Array[float] = []
		for offer in pool:
			weights.append(offer.weight)
		var index := _weighted_index(weights)
		if index < 0:
			break
		var picked: ShopOffer = pool.pop_at(index)
		shelves.append({"offer": picked, "left": picked.copies})
	shop_stock[v] = shelves
	shop_changed.emit(v)


## Restocks every shop that stands. Called at dawn.
func _restock_shops() -> void:
	shop_stock.clear()
	var vertices: Array = world.structures.keys()
	vertices.sort_custom(_vertex_less)
	for v: Vector3i in vertices:
		if shop_def_at(v) != null:
			_stock_shop(v)


## What shelf `index` of the shop at `v` costs, normalised to StringName keys.
func shop_price(v: Vector3i, index: int) -> Dictionary:
	var shelves: Array = shop_stock.get(v, [])
	if index < 0 or index >= shelves.size():
		return {}
	return _normalised((shelves[index]["offer"] as ShopOffer).price)


## {ok: bool, reason: String}. Shopping happens while planning, in the Town.
func can_buy(v: Vector3i, index: int) -> Dictionary:
	if phase != Phase.PLAN:
		return _no("Not planning.")
	if shop_def_at(v) == null:
		return _no("No shop there.")
	var shelves: Array = shop_stock.get(v, [])
	if index < 0 or index >= shelves.size():
		return _no("Nothing on that shelf.")
	if int(shelves[index]["left"]) <= 0:
		return _no("Sold out.")
	var price := shop_price(v, index)
	for key in price:
		if int(stock.get(key, 0)) < int(price[key]):
			return _no("Cannot afford it.")
	return _yes()


## Pays for one of shelf `index` and returns the ItemDef, or null if the purchase is
## refused (the reason is logged). Putting the item in the bag is RoomFeatures.buy.
func buy(v: Vector3i, index: int) -> ItemDef:
	var check := can_buy(v, index)
	if not check["ok"]:
		log_line.emit(String(check["reason"]))
		return null
	var price := shop_price(v, index)
	for key in price:
		stock[key] = int(stock.get(key, 0)) - int(price[key])
	var entry: Dictionary = (shop_stock[v] as Array)[index]
	entry["left"] = int(entry["left"]) - 1
	shop_changed.emit(v)
	return (entry["offer"] as ShopOffer).item


# ----------------------------------------------------------------- helpers

static func _vertex_less(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


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


## A room picks its enemies at random. Enemies of the room's lowest colour(s) are more
## likely, and so are enemies matching the colour of each awake hex around it: the dawn
## decides what the room fills with. Terrain and enemy colours share their numbering
## (neutral, red, green, blue). With a `budget` (spawn tokens left) only enemies whose
## spawn_cost fits it can be picked, and the result is null if none does; without one
## (budget < 0) every enemy is eligible.
func _pick_enemy(tile: TileInstance, borders: Array[Vector2i] = [], budget := -1) -> EnemyTemplate:
	var lowest := tile.lowest_channels()
	var weights: Array[float] = []
	var any_affordable := false
	for template in tile.def.enemies:
		if budget >= 0 and template.spawn_cost > budget:
			weights.append(0.0)
			continue
		any_affordable = true
		var channel := int(template.note_color) - 1  # -1 = neutral
		var weight := config.affinity_multiplier if lowest.has(channel) else 1.0
		for hex in borders:
			if world.terrain_at(hex) == int(template.note_color):
				weight *= config.terrain_affinity_multiplier
		weights.append(weight)
	if not any_affordable:
		return null
	return tile.def.enemies[maxi(0, _weighted_index(weights))]


## Notes one enemy drops: the enemy's own notes_per_kill, times the room's
## note_multiplier, times `mult` (the main-path bonus), rounded. At least one, unless the
## enemy or the room drops none at all.
func notes_dropped(def: TileDef, template: EnemyTemplate, mult := 1.0) -> int:
	if template.notes_per_kill <= 0 or def.note_multiplier <= 0.0:
		return 0
	return maxi(1, roundi(template.notes_per_kill * def.note_multiplier * mult))


## What one enemy carries: its notes (all of the enemy's own colour, or all of one randomly
## picked colour if the enemy is uncoloured) plus the tile's other loot, scaled by the
## main-path bonus.
func _loot_for(tile: TileInstance, template: EnemyTemplate, mult: float) -> Dictionary:
	var out := _scaled_loot(tile.def.loot_per_kill, mult)
	var dropped := notes_dropped(tile.def, template, mult)
	if dropped > 0:
		var note := _drop_note_id(template)
		out[note] = int(out.get(note, 0)) + dropped
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


func _yes() -> Dictionary:
	return {"ok": true, "reason": ""}


func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
