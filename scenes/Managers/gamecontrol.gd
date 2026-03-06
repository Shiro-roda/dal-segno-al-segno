extends Node
class_name GameControl

static var current_run : RunState
static var current_dungeon_run : DungeonRunState

var dungeon_layer
var battle_layer
var event_layer

var battle_manager
var dungeon_controller


func _ready():

	await _wait_for_layers()

	dungeon_layer.visible = true
	battle_layer.visible = false
	event_layer.visible = false

	await _wait_for_controllers()

	battle_manager.connect("battle_finished", _on_battle_finished)

func _wait_for_layers():

	while dungeon_layer == null or battle_layer == null or event_layer == null:

		await get_tree().process_frame

		dungeon_layer = get_tree().get_first_node_in_group("dungeon_layer")
		battle_layer = get_tree().get_first_node_in_group("battle_layer")
		event_layer = get_tree().get_first_node_in_group("event_layer")


func _wait_for_controllers():

	while dungeon_controller == null:
		await get_tree().process_frame
		dungeon_controller = get_tree().get_first_node_in_group("dungeon_controller")

	while battle_manager == null:
		await get_tree().process_frame
		battle_manager = get_tree().get_first_node_in_group("battle_manager")

	await battle_manager.battle_manager_ready



func start_new_run(run : RunState):
	current_run = run


func start_battle(encounter):

	clear_layer(battle_layer)

	var battle_scene = preload("res://scenes/Events/battle_scene.tscn").instantiate()

	battle_layer.add_child(battle_scene)

	var manager = battle_scene.get_node("BattleManager")

	var context = BattleContext.new()
	context.encounter = encounter
	context.run_state = current_run

	manager.start_battle_with_context(context)

	manager.battle_finished.connect(_on_battle_finished)




func _on_battle_finished(victory):

	clear_layer(battle_layer)

	var dungeon_controller = get_tree().get_first_node_in_group("dungeon_controller")

	if victory:
		dungeon_controller.on_room_completed()

func clear_layer(layer):

	for child in layer.get_children():
		child.queue_free()




func start_event(event_scene: PackedScene):

	clear_layer(event_layer)

	var event = event_scene.instantiate()

	event_layer.add_child(event)

	event.event_finished.connect(_on_event_finished)



func _on_event_finished():

	clear_layer(event_layer)

	var dungeon_controller = get_tree().get_first_node_in_group("dungeon_controller")

	dungeon_controller.on_room_completed()
