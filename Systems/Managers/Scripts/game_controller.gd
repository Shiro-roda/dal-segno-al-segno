extends Node
## Minimal entry-point controller (autoload "GameController").
## Plays the boot sequence, shows the start screen, and hosts a placeholder
## "new game" that loads a level into the world layer's SubViewport.
## Everything else (game state, exploration, combat, dialogue) is to be rebuilt.

const START_SCREEN := preload("res://UI/2D/Scenes/start_screen.tscn")
const PLACEHOLDER_LEVEL := "res://Environments/Levels/Scenes/explore_test.tscn"

var world_layer: CanvasLayer
var event_layer: CanvasLayer

## Name of the spawn_point marker the next loaded level should place the
## player at. Read and cleared by PlayerLink on load.
var pending_spawn: StringName = &""

## The current run's day loop. Lives here, not in a level, so it survives scene
## changes. WorldController creates it; New Game clears it.
var day_cycle: DayCycle
## What survives a defeat (ruins, built tile ids, best day). Never cleared in play.
var world_persistent: WorldPersistent = WorldPersistent.new()

## Used for a dungeon room whose TileDef has no scene of its own yet.
const FALLBACK_ROOM := "res://Systems/World/Rooms/room_base.tscn"

## The Town scene the party returns to after an expedition. WorldController fills this
## in from the level it sits in; New Game resets it.
var town_scene := PLACEHOLDER_LEVEL
## The Bass Clef cell whose room is loaded (or about to be) during an expedition.
var bass_cell := DayCycle.ORIGIN
## Which side's door the party came in through (DayCycle.Side), or -1 when they
## appeared at the Segno. Read by DungeonRoom on load.
var arrival_side := -1
## {report, next_day} handed to the Town when the party returns; the plan screen
## shows it once and WorldController clears it.
var pending_report: Dictionary = {}


func _ready() -> void:
	# TAB opens it from anywhere in a running game; it lives here so it survives scene changes.
	add_child(PartyMenu.new())
	await _wait_for_layers()
	world_layer.visible = false
	event_layer.visible = false

	# Boot sequence on first launch, then hand off to the start screen.
	var boot := get_tree().get_first_node_in_group("boot_sequence") as Node
	if boot != null and boot.has_method("show_boot"):
		boot.show_boot()
		await boot.finished
	show_start_screen()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()


func _wait_for_layers() -> void:
	while world_layer == null or event_layer == null:
		await get_tree().process_frame
		var root := get_tree().current_scene
		if root == null:
			continue
		world_layer = root.get_node_or_null("WorldLayer") as CanvasLayer
		event_layer = root.get_node_or_null("EventLayer") as CanvasLayer


func show_start_screen() -> void:
	AudioManagerAuto.fade_out_bgm()
	clear_layer(event_layer)
	clear_world()
	var screen := START_SCREEN.instantiate()
	event_layer.add_child(screen)
	world_layer.visible = false
	event_layer.visible = true
	screen.new_game.connect(func():
		clear_layer(event_layer)
		event_layer.visible = false
		start_new_game())
	screen.quit_game.connect(func(): get_tree().quit())


## Placeholder: drops the player into the exploration test level.
func start_new_game() -> void:
	# Testing: every sheet in Characters/Resources is recruited. Replace with real
	# recruitment once the dungeon run decides who is available.
	PartySetup.recruit_all()
	day_cycle = null  # WorldController starts a fresh run
	bass_cell = DayCycle.ORIGIN
	arrival_side = -1
	pending_report = {}
	town_scene = PLACEHOLDER_LEVEL
	pending_spawn = &"default"
	load_world_scene(PLACEHOLDER_LEVEL)


## Travel to another level, arriving at the named spawn point.
## Deferred so it is safe to call from physics callbacks (body_entered).
func travel_to(scene_path: String, spawn: StringName = &"default") -> void:
	pending_spawn = spawn
	load_world_scene.call_deferred(scene_path)


# ── Dungeon: one scene per room ──────────────────────────────────────────────
## The plan is locked in and the day's expedition has begun: load the room the party
## spawns in (the Segno's).
func begin_expedition() -> void:
	if day_cycle == null or day_cycle.phase != DayCycle.Phase.EXPEDITION:
		return
	enter_room(day_cycle.spawn_cell(), -1)


## Loads the scene for the Bass Clef tile at `cell`. `side` is the DayCycle.Side of the
## door the party arrives through, or -1 to appear at the room's SegnoSpawn.
func enter_room(cell: Vector2i, side := -1) -> void:
	if day_cycle == null:
		return
	var tile := day_cycle.tile_at(cell, TileDef.Clef.BASS)
	if tile == null or not tile.is_live():
		push_error("GameController: no standing room at (%d, %d)." % [cell.x, cell.y])
		return
	bass_cell = cell
	arrival_side = side
	var path := FALLBACK_ROOM
	if tile.def.scene != null and tile.def.scene.resource_path != "":
		path = tile.def.scene.resource_path
	load_world_scene.call_deferred(path)


## The party walked through the door on `side` of the current room.
func go_through_door(side: int) -> void:
	if day_cycle == null or day_cycle.phase != DayCycle.Phase.EXPEDITION:
		return
	var next := bass_cell + DayCycle.side_offset(side)
	enter_room(next, DayCycle.opposite_side(side))


## The party reached the exit room's RoomExit: bank the loot, start the next day, and
## wake up in the Town, which shows the report.
func return_to_town() -> void:
	if day_cycle == null:
		return
	var report := day_cycle.return_to_exit()
	if report.is_empty():
		return
	if day_cycle.config.rest_on_return:
		Rules.roster.rest_all()
	var next_day := day_cycle.begin_next_day()
	pending_report = {"report": report, "next_day": next_day}
	arrival_side = -1
	bass_cell = DayCycle.ORIGIN
	travel_to(town_scene, &"default")


## Returns the SubViewport inside WorldLayer.
func _get_world_viewport() -> SubViewport:
	return world_layer.get_node("SubViewportContainer/SubViewport") as SubViewport


func clear_world() -> void:
	var vp := _get_world_viewport()
	for c in vp.get_children():
		c.queue_free()


## Load a level scene into the world layer's SubViewport.
func load_world_scene(scene_path: String) -> void:
	clear_world()
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("GameController: could not load %s" % scene_path)
		return
	_get_world_viewport().add_child(packed.instantiate())
	event_layer.visible = false
	world_layer.visible = true


func clear_layer(layer: Node) -> void:
	for child in layer.get_children():
		child.queue_free()
