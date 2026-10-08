class_name WorldController
extends Node3D
## The Town (Treble Clef) controller. Put one in the Town level next to the player; it
## needs the usual Player, drone camera and spawn point.
##
##   - loads every TileDef under tile_dir (exit and origin tiles are picked by flag)
##   - draws the Treble grid in this one scene: a tile's own scene if it has one, else
##     a placeholder slab
##   - a console on the origin tile opens the plan screen, where both clefs are planned
##     and the Segno is placed
##   - starting the expedition hands off to GameController, which loads the Segno's room.
##     Each dungeon room is its own scene (see DungeonRoom); none of them live here
##   - coming back from the dungeon reloads this scene; the return report is shown then
##
## The run itself (DayCycle) lives on GameController so it survives scene changes.

## Emitted when the party returns: the return report, then the next day's report.
signal summary(report: Dictionary, next_day: Dictionary)
## Anything the plan screen should redraw for.
signal state_changed

@export_dir var tile_dir := "res://Systems/World/Resources"
## Leave empty to use whichever TileDef under tile_dir sets is_exit (or a bare placeholder).
@export var exit_def: TileDef
## Leave empty to use whichever TileDef under tile_dir sets is_origin (or a bare placeholder).
@export var origin_def: TileDef
## Leave empty to use whichever TileDef under tile_dir sets is_segno (or a bare placeholder).
@export var segno_def: TileDef
## Balance numbers. Empty = defaults.
@export var config: WorldConfig
## Metres per tile edge in the Town.
@export var tile_size := 12.0

## Show the plan screen from the console on the Town's origin tile.
@export var use_plan_screen := true

@export_group("Testing")
## Skips the plan screen: places one of each village tile and every blueprint in
## hand each day, sets a Segno, then goes. Only for testing without the screen.
@export var autoplan := false
@export var autoplan_delay := 1.5
## One debug label with day, stock and blueprints.
@export var debug_overlay := true

var day: DayCycle
var village_defs: Array[TileDef] = []
var dungeon_defs: Array[TileDef] = []

var _treble_root: Node3D
var _treble_nodes: Dictionary = {}  # Vector2i -> Node3D
var _console: Interactable
var _label: Label
var _plan: PlanScreen
var _plan_locked := false  # lock_controls() is a counter, so keep our calls balanced
var _rebuild_queued := false


func _ready() -> void:
	add_to_group("world_controller")
	_remember_town_scene()
	_load_defs()
	_ensure_cycle()
	_build_root()
	_build_console()
	_build_overlay()
	if use_plan_screen and not autoplan:
		_build_plan_screen()
	rebuild_tiles()
	_update_overlay()
	_place_party.call_deferred()
	_show_pending_report.call_deferred()
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
	if day.segno_changed.is_connected(_on_segno_changed):
		day.segno_changed.disconnect(_on_segno_changed)


# ----------------------------------------------------------------- setup

## The dungeon sends the party back to whichever scene this controller is in.
func _remember_town_scene() -> void:
	var root := owner if owner != null else get_parent()
	if root != null and root.scene_file_path != "":
		GameController.town_scene = root.scene_file_path


func _load_defs() -> void:
	village_defs.clear()
	dungeon_defs.clear()
	var found: Array[TileDef] = []
	_collect(tile_dir, found)
	for def in found:
		if def.is_exit:
			if exit_def == null:
				exit_def = def
		elif def.is_origin:
			if origin_def == null:
				origin_def = def
		elif def.is_segno:
			if segno_def == null:
				segno_def = def
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
			exit.category = TileDef.Category.DUNGEON
			exit.is_exit = true
		GameController.day_cycle = DayCycle.new(exit, config, GameController.world_persistent, -1, origin_def, segno_def)
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
	if not day.segno_changed.is_connected(_on_segno_changed):
		day.segno_changed.connect(_on_segno_changed)


func _build_root() -> void:
	_treble_root = Node3D.new()
	_treble_root.name = "TrebleClef"
	add_child(_treble_root)


## The planning console: stand next to it on the Town's origin tile and interact.
func _build_console() -> void:
	_console = Interactable.new()
	_console.name = "PlanConsole"
	_console.prompt = "Plan the day"
	_console.auto_shape_radius = 1.6
	var post := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.45
	cylinder.bottom_radius = 0.6
	cylinder.height = 1.2
	post.mesh = cylinder
	post.position.y = 0.6
	_console.add_child(post)
	var console_label := Label3D.new()
	console_label.text = "Plan the day"
	console_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	console_label.position.y = 1.8
	_console.add_child(console_label)
	_console.interacted.connect(_on_console_interacted)
	_treble_root.add_child(_console)


# ------------------------------------------------------------------ tiles

## Where a Town cell sits, in this node's space.
func world_pos(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * tile_size, 0.0, cell.y * tile_size)


## Where the party wakes in the Town: on the origin tile, just beside the console.
func town_spawn() -> Vector3:
	return world_pos(DayCycle.ORIGIN) + Vector3(0.0, 0.5, tile_size * 0.25)


func rebuild_tiles() -> void:
	_rebuild_treble()
	state_changed.emit()


func _rebuild_treble() -> void:
	for node: Node3D in _treble_nodes.values():
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	_treble_nodes.clear()
	var grid := day.grid_for(TileDef.Clef.TREBLE)
	for cell: Vector2i in grid.cells:
		var node := _make_tile_node(grid.cells[cell] as TileInstance)
		node.position = world_pos(cell)
		node.name = "Tile_%d_%d" % [cell.x, cell.y]
		_treble_root.add_child(node)
		_treble_nodes[cell] = node


func _make_tile_node(tile: TileInstance) -> Node3D:
	if tile.def.scene != null and not tile.ruined:
		var inst := tile.def.scene.instantiate() as Node3D
		if inst != null:
			return inst
	return _placeholder_tile(tile)


## A flat coloured slab so the Town is walkable before real tiles exist.
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
	elif tile.def.is_origin:
		mat.albedo_color = Color(0.8, 0.75, 0.45)
	else:
		mat.albedo_color = Color(0.35, 0.6, 0.35)
	bm.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = bm
	mesh.position.y = -0.23
	body.add_child(mesh)
	return body


# ----------------------------------------------------------- party movement

## Puts the party where the phase says it belongs. Runs once the level's own spawn
## has happened. An expedition still running when the Town loads (for example after a
## reload) sends the party straight back down.
func _place_party() -> void:
	if day.phase == DayCycle.Phase.EXPEDITION:
		GameController.begin_expedition()
		return
	var link := _party_link()
	if link != null:
		link.teleport_to(global_transform * town_spawn())


## The PlayerLink in this level. The previous scene may still be queued for deletion,
## so asking the group for "the first" one could return its ghost.
func _party_link() -> PlayerLink:
	var root := owner if owner != null else get_parent()
	for node in get_tree().get_nodes_in_group("party_link"):
		if root != null and root.is_ancestor_of(node):
			return node as PlayerLink
	return null


## The party came back from the dungeon: show how the day went.
func _show_pending_report() -> void:
	var pending := GameController.pending_report
	if pending.is_empty():
		return
	GameController.pending_report = {}
	var report: Dictionary = pending["report"]
	var next_day: Dictionary = pending["next_day"]
	if _plan != null:
		_plan.show_report(report, next_day)
	summary.emit(report, next_day)


# ---------------------------------------------------------------- planning

func _on_console_interacted(_who: Node3D) -> void:
	if _plan != null:
		_plan.show_screen()


## Tries every open slot in order; places `def` in the first that accepts it.
func try_place_anywhere(def: TileDef) -> bool:
	for cell in day.open_slots(def.clef()):
		if day.can_place(cell, def)["ok"]:
			return day.place_tile(cell, def)
	return false


## Testing stand-in for a plan screen: one of each village tile, then every
## blueprint in today's hand, wherever they fit, a Segno at the far end. Then off on
## the expedition.
func _run_autoplan() -> void:
	for def in village_defs:
		try_place_anywhere(def)
	for def in day.blueprints.duplicate():
		try_place_anywhere(def)
	_autoplan_segno()
	rebuild_tiles()
	_update_overlay()
	await get_tree().create_timer(autoplan_delay).timeout
	if is_inside_tree():
		start_expedition()


## Builds the Segno room in the empty cell next to the standing dungeon tile furthest
## from the exit.
func _autoplan_segno() -> void:
	if day.has_segno():
		return
	var best := DayCycle.NO_SEGNO
	var best_steps := -1
	for pos in day.open_slots(TileDef.Clef.BASS):
		if not day.can_set_segno(pos)["ok"]:
			continue
		var steps := -1
		for step in DayCycle.NEIGHBOURS:
			steps = maxi(steps, day.distance_to_exit(pos + step))
		if steps > best_steps:
			best = pos
			best_steps = steps
	if best != DayCycle.NO_SEGNO:
		day.set_segno(best)


# -------------------------------------------------------------- expedition

## Locks in the plan and carries the party down to the Segno's room.
func start_expedition() -> void:
	if day.phase != DayCycle.Phase.PLAN:
		return
	if not Rules.roster.party_ready():
		day.log_line.emit("Choose your companions first (TAB opens the party menu).")
		return
	day.start_expedition()
	if day.phase != DayCycle.Phase.EXPEDITION:
		return  # refused, e.g. no Segno yet; the reason was logged
	_release_player_lock()
	GameController.begin_expedition()


## This scene is about to be replaced; make sure nothing keeps the controls frozen.
## (The party link is freed with the scene, so this only matters if the load fails.)
func _release_player_lock() -> void:
	if _plan_locked:
		var link := _party_link()
		if link != null:
			link.unlock_controls()
		_plan_locked = false


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


func _on_segno_changed() -> void:
	_update_overlay()


# ------------------------------------------------------------ plan screen

func _build_plan_screen() -> void:
	_plan = PlanScreen.new()
	_plan.auto_show = false  # opened from the console, not forced on the player
	add_child(_plan)
	_plan.open(day, village_defs)
	_plan.expedition_requested.connect(start_expedition)
	_plan.opened.connect(_sync_plan_lock)
	_plan.closed.connect(_sync_plan_lock)
	# The player may not exist yet, so lock once everything is ready.
	_sync_plan_lock.call_deferred()


## Freezes the player while the plan screen is open. lock_controls() is a counter,
## so only call it when the state actually changes.
func _sync_plan_lock() -> void:
	var want := _plan != null and _plan.is_open()
	if _label != null:
		_label.visible = not want  # the plan screen shows all of this itself
	if want == _plan_locked:
		return
	var link := _party_link()
	if link == null:
		return
	if want:
		link.lock_controls()
	else:
		link.unlock_controls()
	_plan_locked = want


## Placing or erasing a Town tile changes the 3D scene; several can land in one frame.
## Dungeon tiles are only rooms in the grid until the expedition loads them.
func _on_tile_changed(_pos: Vector2i, clef: TileDef.Clef) -> void:
	if day.phase != DayCycle.Phase.PLAN or clef != TileDef.Clef.TREBLE:
		return
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild_after_changes.call_deferred()


func _rebuild_after_changes() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	_rebuild_treble()
	state_changed.emit()


func _on_log(text: String) -> void:
	print("[world] ", text)


func _update_overlay() -> void:
	if _label == null or day == null:
		return
	var lines: Array[String] = []
	lines.append("Day %d  %s" % [day.day, DayCycle.Phase.keys()[day.phase]])
	lines.append("Stock: " + _format_amounts(day.stock))
	lines.append("Tithe tonight: %d  Debt: %d" % [day.tithe_tonight(), day.debt])
	if day.phase == DayCycle.Phase.PLAN:
		var counts := {}
		for def in day.blueprints:
			counts[def.display_name] = int(counts.get(def.display_name, 0)) + 1
		lines.append("Blueprints: " + _format_amounts(counts))
		if day.has_segno():
			var info := day.main_path()
			lines.append("Segno (%d, %d)  main path %d steps, %d loops" % [
					day.segno.x, day.segno.y, int(info["steps"]), int(info["loops"])])
		else:
			lines.append("Segno: not placed")
	_label.text = "\n".join(lines)


func _format_amounts(amounts: Dictionary) -> String:
	if amounts.is_empty():
		return "-"
	var parts: Array[String] = []
	for key in amounts:
		parts.append("%s %d" % [key, int(amounts[key])])
	return ", ".join(parts)
