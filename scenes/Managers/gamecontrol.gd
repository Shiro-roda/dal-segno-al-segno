extends Node
class_name GameControl

static var current_run : RunState
static var current_dungeon_run : DungeonRunState

var dungeon_layer
var battle_layer
var event_layer
var world_layer

var battle_manager
var dungeon_controller



func _ready():

	await _wait_for_layers()

	dungeon_layer.visible = true
	battle_layer.visible = false
	event_layer.visible = false

	await _wait_for_controllers()

	start_new_game()


func _wait_for_layers():

	while dungeon_layer == null or battle_layer == null or event_layer == null or world_layer == null:

		await get_tree().process_frame

		dungeon_layer = get_tree().get_first_node_in_group("dungeon_layer")
		battle_layer = get_tree().get_first_node_in_group("battle_layer")
		event_layer = get_tree().get_first_node_in_group("event_layer")
		world_layer = get_tree().get_first_node_in_group("world_layer")


func _wait_for_controllers():

	while dungeon_controller == null:
		await get_tree().process_frame
		dungeon_controller = get_tree().get_first_node_in_group("dungeon_controller")


func start_new_game():

	var run = RunState.new()

	# Kendall is always in the party
	var member = PartyMemberData.new()
	member.init_from_character(preload("res://resources/characters/kendall.tres"))
	run.party_members.append(member)

	# All three supports available; player picks one via companion-select event
	run.available_supports = [
		preload("res://resources/characters/supports/hue.tres"),
		preload("res://resources/characters/supports/indra.tres"),
		preload("res://resources/characters/supports/vritra.tres"),
	]

	start_new_run(run)

	# Show companion select before entering the dungeon
	var select_scene := preload("res://scenes/Events/companion_select/companion_select.tscn")
	var dungeon_data := preload("res://resources/dungeons/test_dungeon.tres")

	_start_companion_select(select_scene, dungeon_data)


func _start_companion_select(select_scene: PackedScene, dungeon_data: DungeonData) -> void:
	clear_layer(event_layer)
	var select := select_scene.instantiate()
	event_layer.add_child(select)
	dungeon_layer.visible = false
	battle_layer.visible = false
	world_layer.visible = false
	event_layer.visible = true
	select.event_finished.connect(func():
		clear_layer(event_layer)
		event_layer.visible = false
		start_dungeon(dungeon_data)
	)


func start_new_run(run : RunState):
	current_run = run


func _set_dungeon_map_visible(visible: bool):
	var map_3d = get_tree().get_first_node_in_group("dungeon_map_3d")
	if map_3d:
		map_3d.visible = visible
		var host = map_3d.get_node_or_null("CameraPivot/Camera3D/PhantomCameraHost")
		if host:
			host.set_process(visible)
			host.set_physics_process(visible)
		var cam = map_3d.get_node_or_null("CameraPivot/Camera3D")
		if cam:
			cam.current = visible


func start_battle(encounter):

	dungeon_layer.visible = false
	event_layer.visible = false
	battle_layer.visible = true
	_set_dungeon_map_visible(false)

	clear_layer(battle_layer)

	var battle_scene = preload("res://scenes/Events/battle_scene.tscn").instantiate()

	battle_layer.add_child(battle_scene)

	var manager = battle_scene.get_node("BattleManager")

	var context = BattleContext.new()
	context.encounter = encounter
	context.run_state = current_run

	manager.start_battle_with_context(context)

	manager.battle_finished.connect(_on_battle_finished)


func _on_battle_finished(victory, exp_per_member: Dictionary = {}, level_up_events: Dictionary = {}):

	clear_layer(battle_layer)
	battle_layer.visible = false

	AudioManagerAuto.reset_ambience()
	AudioManagerAuto.fade_out_bgm()

	var results_scene := preload("res://scenes/UI/menu/battle_results.tscn")
	var results := results_scene.instantiate()
	clear_layer(event_layer)
	event_layer.visible = true
	dungeon_layer.visible = false
	event_layer.add_child(results)
	results.setup(victory, current_run.party_members, exp_per_member, level_up_events)

	var _vic: bool = victory
	results.results_dismissed.connect(func():
		clear_layer(event_layer)
		if not _vic:
			# Defeat: reset the entire run and return to companion select
			start_new_game()
			return
		# Victory: return to dungeon
		event_layer.visible = false
		dungeon_layer.visible = true
		_set_dungeon_map_visible(true)
		var resume_tween = create_tween()
		resume_tween.tween_callback(AudioManagerAuto.resume_dungeon_track).set_delay(0.7)
		var dc = get_tree().get_first_node_in_group("dungeon_controller")
		dc.on_room_completed()
	)


func clear_layer(layer):
	for child in layer.get_children():
		child.queue_free()


func start_event(event_scene: PackedScene):

	clear_layer(event_layer)

	var event = event_scene.instantiate()

	event_layer.add_child(event)

	dungeon_layer.visible = false
	battle_layer.visible = false
	event_layer.visible = true

	event.event_finished.connect(_on_event_finished)


func _on_event_finished():

	clear_layer(event_layer)
	event_layer.visible = false
	dungeon_layer.visible = true
	_set_dungeon_map_visible(true)

	var dc = get_tree().get_first_node_in_group("dungeon_controller")
	dc.on_room_completed()


func start_world(scene: PackedScene):

	clear_layer(world_layer)

	var world = scene.instantiate()

	world_layer.add_child(world)

	dungeon_layer.visible = false
	battle_layer.visible = false
	event_layer.visible = false
	world_layer.visible = true
	_set_dungeon_map_visible(false)


func start_dungeon(dungeon_data: DungeonData):

	dungeon_layer.visible = true
	world_layer.visible = false
	_set_dungeon_map_visible(true)

	dungeon_controller.start_dungeon(current_run, dungeon_data)


func start_boss_battle(encounter: EncounterData) -> void:
	dungeon_layer.visible = false
	event_layer.visible = false
	battle_layer.visible = true
	_set_dungeon_map_visible(false)

	clear_layer(battle_layer)
	var battle_scene = preload("res://scenes/Events/battle_scene.tscn").instantiate()
	battle_layer.add_child(battle_scene)

	var manager = battle_scene.get_node("BattleManager")
	var context = BattleContext.new()
	context.encounter = encounter
	context.run_state = current_run
	manager.start_battle_with_context(context)
	manager.battle_finished.connect(_on_boss_battle_finished)


func _on_boss_battle_finished(victory: bool, exp_per_member: Dictionary = {}, level_up_events: Dictionary = {}):
	clear_layer(battle_layer)
	battle_layer.visible = false
	AudioManagerAuto.reset_ambience()
	AudioManagerAuto.fade_out_bgm()

	var results_scene := preload("res://scenes/UI/menu/battle_results.tscn")
	var results := results_scene.instantiate()
	clear_layer(event_layer)
	event_layer.visible = true
	dungeon_layer.visible = false
	event_layer.add_child(results)
	results.setup(victory, current_run.party_members, exp_per_member, level_up_events)

	if victory:
		results.results_dismissed.connect(func():
			clear_layer(event_layer)
			start_win_screen()
		)
	else:
		results.results_dismissed.connect(func():
			clear_layer(event_layer)
			start_new_game()
		)


func start_win_screen() -> void:
	clear_layer(event_layer)
	event_layer.visible = true
	dungeon_layer.visible = false
	battle_layer.visible = false
	_set_dungeon_map_visible(false)
	var win_scene := preload("res://scenes/Events/win_screen.tscn")
	var win := win_scene.instantiate()
	event_layer.add_child(win)
