extends Node
class_name GameControl

var current_run : RunState
var current_dungeon : DungeonData
var current_scene : Node
var current_dungeon_run : DungeonRunState



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

	var battle_scene = preload("res://scenes/Events/battle_scene.tscn").instantiate()
	get_tree().root.add_child(battle_scene)
	current_scene = battle_scene

	var manager = battle_scene.get_node("BattleManager")
	manager.connect("battle_finished", _on_battle_finished)
	await manager.battle_manager_ready
	manager.start_battle_with_context(context)



func _on_battle_finished(victory: bool):

	if victory:
		return_to_dungeon()
	else:
		print("Handle death logic")



func _start_loaded_battle(context):

	var bm : Node = null

	while bm == null:
		await get_tree().process_frame
		bm = get_tree().get_first_node_in_group("battle_manager")

	bm.connect("battle_finished", _on_battle_finished)

	bm.start_battle_with_context(context)

func start_event(event_scene: PackedScene):

	get_tree().change_scene_to_packed(event_scene)

	call_deferred("_wait_for_event_finish")

func _wait_for_event_finish():

	var event_node : Node = null

	while event_node == null:
		await get_tree().process_frame
		event_node = get_tree().current_scene

	await event_node.event_finished

	return_to_dungeon()

func return_to_dungeon():

	get_tree().change_scene_to_file(
		"res://scenes/Maps/dungeon_scene.tscn"
	)
	call_deferred("_resume_dungeon")

func _resume_dungeon():

	var controller = get_tree().get_first_node_in_group("dungeon_controller")

	if controller:
		controller.on_room_completed()
