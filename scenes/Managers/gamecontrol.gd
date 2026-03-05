extends Node
class_name GameControl

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

	var battle_scene = preload("res://scenes/Events/battle_scene.tscn").instantiate()
	get_tree().root.add_child(battle_scene)
	current_scene = battle_scene

	var manager = battle_scene.get_node("BattleManager")
	manager.connect("battle_finished", _on_battle_finished)
	await manager.battle_manager_ready
	manager.start_battle_with_context(context)



func _on_battle_finished(victory: bool):

	current_scene.queue_free()

	if victory:
		var dungeon_scene = preload("res://scenes/Maps/dungeon_scene.tscn").instantiate()
		get_tree().root.add_child(dungeon_scene)
		current_scene = dungeon_scene
	else:
		print("Handle death logic")



func _start_loaded_battle(context):
	var bm : Node = null

	while bm == null:
		await get_tree().process_frame
		bm = get_tree().get_first_node_in_group("battle_manager")

	bm.start_battle_with_context(context)
