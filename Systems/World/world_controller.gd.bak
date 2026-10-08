class_name WorldController
extends Node3D
## Runs the plan -> expedition -> bank loop inside a level. Put one in the level
## next to the player; it needs the usual Player, drone camera and spawn point.
##
##   - loads every TileDef under tile_dir (the exit tile is whichever sets is_exit)
##   - draws the grid as tiles: a tile's own scene if it has one, else a placeholder
##   - on start_expedition(), turns the day's remnants into CombatEncounters
##   - wins record kills, a defeat ends the run, and walking back onto the exit
##     tile banks the carried loot, rests the party and starts the next day
##   - XP from a win opens the level-up screen for whoever earned a level
##
## The run itself (DayCycle) lives on GameController so it survives scene reloads.

## Emitted when the party returns: the return report, then the next day's report.
signal summary(report: Dictionary, next_day: Dictionary)
## Anything the plan screen should redraw for.
signal state_changed

@export_dir var tile_dir := "res://Systems/World/Data"
## Leave empty to use whichever TileDef under tile_dir sets is_exit (or a bare placeholder).
@export var exit_def: TileDef
## Balance numbers. Empty = defaults.
@export var config: WorldConfig
## Metres per tile edge.
@export var tile_size := 12.0

## Show the plan screen at the start of every day.
@export var use_plan_screen := true

@export_group("Testing")
## Skips the plan screen: places one of each village tile and every blueprint in
## hand each day, then goes. Only for testing without the screen.
@export var autoplan := false
@export var autoplan_delay := 1.5
## One debug label with day, stock and blueprints.
@export var debug_overlay := true

var day: DayCycle
var village_defs: Array[TileDef] = []
var dungeon_defs: Array[TileDef] = []

var _tile_nodes: Dictionary = {}  # Vector2i -> Node3D
var _encounters: Array[CombatEncounter] = []
var _exit_zone: Area3D
var _label: Label
var _busy := false  # a level-up screen is open
var _plan: PlanScreen
var _plan_locked := false  # lock_controls() is a counter, so keep our calls balanced
var _rebuild_queued := false


func _ready() -> void:
	add_to_group("world_controller")
	_load_defs()
	_ensure_cycle()
	_build_exit_zone()
	_build_overlay()
	if use_plan_screen and not autoplan:
		_build_plan_screen()
	rebuild_tiles()
	_update_overlay()
	if autoplan and day.phase == DayCycle.Phase.PLAN:
		_run_autoplan.call_deferred()


func _exit_tree() -> void:
	if day == null:
		return
	if day.phase_changed.is_connected(_on_phase_changed):
		day.phase_changed.disconnect(_on_phase_changed)
	if day.blueprints_changed.is_connected(_update_overlay):
		day.blueprints_changed.disconnect(_update_overlay)
	if day.log_line.is_connected(_on_log):
		day.log_line.disconnect(_on_log)
	if day.tile_changed.is_connected(_on_tile_changed):
		day.tile_changed.disconnect(_on_tile_changed)


# ----------------------------------------------------------------- setup

func _load_defs() -> void:
	village_defs.clear()
	dungeon_defs.clear()
	var found: Array[TileDef] = []
	_collect(tile_dir, found)
	for def in found:
		if def.is_exit:
			if exit_def == null:
				exit_def = def
		elif def.category == TileDef.Category.VILLAGE:
			village_defs.append(def)
		else:
			dungeon_defs.append(def)
	if found.is_empty():
		push_warning("WorldController: no TileDefs found in %s." % tile_dir)


func _collect(path: String, out: Array[TileDef]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	var folders := Array(dir.get_directories())
	folders.sort()
	for sub: String in folders:
		_collect(path.path_join(sub), out)
	var files := Array(dir.get_files())
	files.sort()
	for f: String in files:
		var file := f.trim_suffix(".remap")  # exported builds
		if file.ends_with(".tres"):
			var def := load(path.path_join(file)) as TileDef
			if def != null:
				out.append(def)


func _ensure_cycle() -> void:
	if GameController.day_cycle == null:
		var exit := exit_def
		if exit == null:
			exit = TileDef.new()
			exit.id = &"exit"
			exit.display_name = "Exit"
			exit.category = TileDef.Category.VILLAGE
			exit.is_exit = true
		GameController.day_cycle = DayCycle.new(exit, config, GameController.world_persistent)
		GameController.day_cycle.blueprint_pool = dungeon_defs
		GameController.day_cycle.begin_run()
	day = GameController.day_cycle
	day.blueprint_pool = dungeon_defs
	if not day.phase_changed.is_connected(_on_phase_changed):
		day.phase_changed.connect(_on_phase_changed)
	if not day.blueprints_changed.is_connected(_update_overlay):
		day.blueprints_changed.connect(_update_overlay)
	if not day.log_line.is_connected(_on_log):
		day.log_line.connect(_on_log)
	if not day.tile_changed.is_connected(_on_tile_changed):
		day.tile_changed.connect(_on_tile_changed)


func _build_exit_zone() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(tile_size * 0.5, 3.0, tile_size * 0.5)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position.y = 1.0
	_exit_zone = Area3D.new()
	_exit_zone.name = "ExitZone"
	_exit_zone.collision_layer = 0
	_exit_zone.collision_mask = 1 << 1  # the player body is on layer 2
	_exit_zone.add_child(shape)
	add_child(_exit_zone)
	_exit_zone.body_entered.connect(_on_exit_entered)


# ------------------------------------------------------------------ tiles

func world_pos(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * tile_size, 0.0, cell.y * tile_size)


func rebuild_tiles() -> void:
	for node: Node3D in _tile_nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	_tile_nodes.clear()
	for cell: Vector2i in day.grid:
		var node := _make_tile_node(day.grid[cell] as TileInstance)
		node.position = world_pos(cell)
		node.name = "Tile_%d_%d" % [cell.x, cell.y]
		add_child(node)
		_tile_nodes[cell] = node
	state_changed.emit()


func _make_tile_node(tile: TileInstance) -> Node3D:
	if tile.def.scene != null and not tile.ruined:
		var inst := tile.def.scene.instantiate() as Node3D
		if inst != null:
			return inst
	return _placeholder_tile(tile)


## A flat coloured slab so the grid is walkable before real tiles exist.
func _placeholder_tile(tile: TileInstance) -> Node3D:
	var size := Vector3(tile_size - 0.3, 0.5, tile_size - 0.3)
	var body := StaticBody3D.new()
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position.y = -0.23
	body.add_child(shape)
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	if tile.ruined:
		mat.albedo_color = Color(0.4, 0.4, 0.4)
	elif tile.def.is_exit:
		mat.albedo_color = Color(0.9, 0.9, 0.9)
	elif tile.def.category == TileDef.Category.VILLAGE:
		mat.albedo_color = Color(0.35, 0.6, 0.35)
	else:
		mat.albedo_color = Color(0.6, 0.3, 0.3)
	bm.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = bm
	mesh.position.y = -0.23
	body.add_child(mesh)
	return body


# ---------------------------------------------------------------- planning

## Tries every open slot in order; places `def` in the first that accepts it.
func try_place_anywhere(def: TileDef) -> bool:
	for cell in day.open_slots():
		if day.can_place(cell, def)["ok"]:
			return day.place_tile(cell, def)
	return false


## Testing stand-in for a plan screen: one of each village tile, then every
## blueprint in today's hand, wherever they fit. Then off on the expedition.
func _run_autoplan() -> void:
	for def in village_defs:
		try_place_anywhere(def)
	for def in day.blueprints.duplicate():
		try_place_anywhere(def)
	rebuild_tiles()
	_update_overlay()
	await get_tree().create_timer(autoplan_delay).timeout
	if is_inside_tree():
		start_expedition()


# -------------------------------------------------------------- expedition

func start_expedition() -> void:
	if day.phase != DayCycle.Phase.PLAN:
		return
	var spawns := day.start_expedition()
	_clear_encounters()
	var by_cell := {}
	for s in spawns:
		if not by_cell.has(s["pos"]):
			by_cell[s["pos"]] = []
		(by_cell[s["pos"]] as Array).append(s)
	# One fight per tile: everything gathered there is fought together.
	for cell: Vector2i in by_cell:
		var list: Array[EnemyTemplate] = []
		var ids: Array[int] = []
		for s: Dictionary in by_cell[cell]:
			var scaled := (s["template"] as EnemyTemplate).duplicate() as EnemyTemplate
			scaled.level = int(s["level"])
			list.append(scaled)
			ids.append(int(s["id"]))
		var encounter := CombatEncounter.new()
		encounter.enemies = list
		encounter.position = world_pos(cell)
		encounter.auto_shape_size = Vector3(tile_size * 0.5, 3.0, tile_size * 0.5)
		encounter.finished.connect(_on_encounter_finished.bind(ids))
		encounter.xp_awarded.connect(_on_xp_awarded)
		add_child(encounter)
		_encounters.append(encounter)
	_update_overlay()


func _on_encounter_finished(victory: bool, ids: Array) -> void:
	if victory:
		for id in ids:
			day.record_kill(int(id))
	else:
		# CombatEncounter already sends the game back to the start screen.
		day.defeat()
	_update_overlay()


func _on_exit_entered(body: Node3D) -> void:
	if not body.is_in_group("party_leader") or day.phase != DayCycle.Phase.EXPEDITION or _busy:
		return
	for e in _encounters:
		if is_instance_valid(e) and e.session != null and e.session.active:
			return  # no leaving mid-fight
	return_to_exit()


func return_to_exit() -> void:
	var report := day.return_to_exit()
	if report.is_empty():
		return
	_clear_encounters()
	if day.config.rest_on_return:
		Rules.roster.rest_all()
	var next_day := day.begin_next_day()
	rebuild_tiles()
	_update_overlay()
	if _plan != null:
		_plan.show_report(report, next_day)
	summary.emit(report, next_day)
	if autoplan:
		_run_autoplan.call_deferred()


func _clear_encounters() -> void:
	for e in _encounters:
		if is_instance_valid(e):
			e.queue_free()
	_encounters.clear()


# ---------------------------------------------------------------- level-up

## One level-up screen per companion who earned a level, one after another.
func _on_xp_awarded(_amount: int, ready: Array) -> void:
	_busy = true
	var link := get_tree().get_first_node_in_group("party_link") as PlayerLink
	if link != null:
		link.lock_controls()
	for id in ready:
		var offer := Leveling.build_offer(Rules.roster, id)
		if offer == null:
			continue
		var screen := LevelUpScreen.new()
		add_child(screen)
		screen.open(offer)
		await screen.finished
	if link != null:
		link.unlock_controls()
	_busy = false


# ------------------------------------------------------------ debug overlay

func _build_overlay() -> void:
	if not debug_overlay:
		return
	var layer := CanvasLayer.new()
	layer.layer = 10
	_label = Label.new()
	_label.position = Vector2(12, 12)
	layer.add_child(_label)
	add_child(layer)


func _on_phase_changed(_phase: DayCycle.Phase) -> void:
	_sync_plan_lock()
	_update_overlay()


# ------------------------------------------------------------ plan screen

func _build_plan_screen() -> void:
	_plan = PlanScreen.new()
	add_child(_plan)
	_plan.open(day, village_defs)
	_plan.expedition_requested.connect(start_expedition)
	# The player may not exist yet, so lock once everything is ready.
	_sync_plan_lock.call_deferred()


## Freezes the player while the plan screen is open. lock_controls() is a counter,
## so only call it when the state actually changes.
func _sync_plan_lock() -> void:
	var want := _plan != null and day != null and day.phase == DayCycle.Phase.PLAN
	if want == _plan_locked:
		return
	var link := get_tree().get_first_node_in_group("party_link") as PlayerLink
	if link == null:
		return
	if want:
		link.lock_controls()
	else:
		link.unlock_controls()
	_plan_locked = want


## Placing or erasing a tile changes the 3D grid; several can land in one frame.
func _on_tile_changed(_pos: Vector2i) -> void:
	# Colour changes during an expedition don't alter the 3D tiles, so only rebuild
	# when something was placed or erased.
	if day.phase != DayCycle.Phase.PLAN or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild_after_changes.call_deferred()


func _rebuild_after_changes() -> void:
	_rebuild_queued = false
	if is_inside_tree():
		rebuild_tiles()


func _on_log(text: String) -> void:
	print("[world] ", text)


func _update_overlay() -> void:
	if _label == null or day == null:
		return
	var lines: Array[String] = []
	lines.append("Day %d  %s" % [day.day, DayCycle.Phase.keys()[day.phase]])
	lines.append("Stock: " + _format_amounts(day.stock))
	if day.phase == DayCycle.Phase.EXPEDITION:
		lines.append("Carried: " + _format_amounts(day.carried_loot))
		lines.append("Remnants left: %d" % day.remaining())
	var tonight := day.config.tithe_base + day.config.tithe_per_day * day.day
	lines.append("Tithe tonight: %d  Debt: %d" % [tonight, day.debt])
	if day.phase == DayCycle.Phase.PLAN:
		var counts := {}
		for def in day.blueprints:
			counts[def.display_name] = int(counts.get(def.display_name, 0)) + 1
		lines.append("Blueprints: " + _format_amounts(counts))
	_label.text = "\n".join(lines)


func _format_amounts(amounts: Dictionary) -> String:
	if amounts.is_empty():
		return "-"
	var parts: Array[String] = []
	for key in amounts:
		parts.append("%s %d" % [key, int(amounts[key])])
	return ", ".join(parts)
