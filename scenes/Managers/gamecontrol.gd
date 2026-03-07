extends Node
class_name GameControl

<<<<<<< Updated upstream
var current_run : RunState
var current_dungeon : DungeonData
var current_scene : Node


func start_new_run(run: RunState):
	current_run = run

func start_battle(encounter: EncounterData):
	var context = BattleContext.new()
	context.run_state = current_run
	context.encounter = encounter

	current_run = context.run_state

	get_tree().change_scene_to_file("res://scenes/Events/battle_scene.tscn")

	call_deferred("_start_loaded_battle", context)


func change_scene_to_battle(context: BattleContext):
	if current_scene:
		current_scene.queue_free()
=======
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

	var member = PartyMemberData.new()
	member.character = preload("res://resources/characters/kendall.tres")
	member.current_hp = member.character.base_max_hp
	run.party_members.append(member)

	member = PartyMemberData.new()
	member.character = preload("res://resources/characters/kendall.tres")
	member.current_hp = member.character.base_max_hp
	run.party_members.append(member)

	member = PartyMemberData.new()
	member.character = preload("res://resources/characters/kendall.tres")
	member.current_hp = member.character.base_max_hp
	run.party_members.append(member)

	start_new_run(run)

	var dungeon_data = preload("res://resources/dungeons/test_dungeon.tres")

	start_dungeon(dungeon_data)



func start_new_run(run : RunState):
	current_run = run

func start_battle(encounter):

	dungeon_layer.visible = false
	event_layer.visible = false
	battle_layer.visible = true

	clear_layer(battle_layer)
>>>>>>> Stashed changes

	var battle_scene = preload("res://scenes/Events/battle_scene.tscn").instantiate()
	get_tree().root.add_child(battle_scene)
	current_scene = battle_scene

	var manager = battle_scene.get_node("BattleManager")
	manager.connect("battle_finished", _on_battle_finished)
	await manager.battle_manager_ready
	manager.start_battle_with_context(context)



func _on_battle_finished(victory: bool):

<<<<<<< Updated upstream
	current_scene.queue_free()

	if victory:
		var dungeon_scene = preload("res://scenes/Maps/dungeon_scene.tscn").instantiate()
		get_tree().root.add_child(dungeon_scene)
		current_scene = dungeon_scene
	else:
		print("Handle death logic")
=======

func _on_battle_finished(victory):

	clear_layer(battle_layer)

	battle_layer.visible = false
	event_layer.visible = false
	dungeon_layer.visible = true
	
	AudioManagerAuto.fade_out_bgm()
	
	var dungeon_controller = get_tree().get_first_node_in_group("dungeon_controller")

	if victory:
		dungeon_controller.on_room_completed()
	else:
		dungeon_controller.on_party_defeated()



func clear_layer(layer):

	for child in layer.get_children():
		child.queue_free()
>>>>>>> Stashed changes



func _start_loaded_battle(context):
	var bm : Node = null

	while bm == null:
		await get_tree().process_frame
		bm = get_tree().get_first_node_in_group("battle_manager")

<<<<<<< Updated upstream
	bm.start_battle_with_context(context)
=======
	clear_layer(event_layer)

	var event = event_scene.instantiate()

	event_layer.add_child(event)

	event.event_finished.connect(_on_event_finished)



func _on_event_finished():

	clear_layer(event_layer)

	var dungeon_controller = get_tree().get_first_node_in_group("dungeon_controller")

	dungeon_controller.on_room_completed()

func start_world(scene: PackedScene):

	clear_layer(world_layer)

	var world = scene.instantiate()

	world_layer.add_child(world)

	dungeon_layer.visible = false
	battle_layer.visible = false
	event_layer.visible = false
	world_layer.visible = true

func start_dungeon(dungeon_data: DungeonData):

	dungeon_layer.visible = true
	world_layer.visible = false

	dungeon_controller.start_dungeon(current_run, dungeon_data)
>>>>>>> Stashed changes
