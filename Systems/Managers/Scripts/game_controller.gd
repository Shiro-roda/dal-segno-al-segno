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


func _ready() -> void:
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
	pending_spawn = &"default"
	load_world_scene(PLACEHOLDER_LEVEL)


## Travel to another level, arriving at the named spawn point.
## Deferred so it is safe to call from physics callbacks (body_entered).
func travel_to(scene_path: String, spawn: StringName = &"default") -> void:
	pending_spawn = spawn
	load_world_scene.call_deferred(scene_path)


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
