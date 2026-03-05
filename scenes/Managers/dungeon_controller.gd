extends Node
class_name DungeonController

var dungeon : DungeonRunState


func _ready():
	dungeon = GameController.current_dungeon_run
	add_to_group("dungeon_controller")


	if dungeon == null:
		return
	
	var ui = get_parent().get_node("DungeonUI")
	ui.setup(dungeon)
	
	enter_current_room()



func start_dungeon(run_state : RunState, dungeon_data : DungeonData):

	dungeon = DungeonRunState.new()
	dungeon.run_state = run_state
	GameController.current_dungeon_run = dungeon


	generate_rooms(dungeon_data)

	enter_current_room()


func generate_rooms(dungeon_data : DungeonData):

	dungeon.rooms.clear()

	for i in range(10):

		var instance = RoomInstance.new()
		instance.room_data = dungeon_data.rooms.pick_random()
		instance.position_index = i

		dungeon.rooms.append(instance)



func enter_current_room():

	var room : RoomInstance = dungeon.rooms[dungeon.current_room_index]
	var data : RoomData = room.room_data
	
	room.visited = true

	print("Entering room:", data.room_name)

	match data.room_type:

		RoomData.RoomType.BATTLE:
			GameController.start_battle(data.encounter)

		RoomData.RoomType.EVENT:
			load_event(data.event_scene)

		RoomData.RoomType.REST:
			open_rest_ui()

		RoomData.RoomType.SEGNO:
			place_segno()

func advance_room():
	dungeon.current_room_index += 1
	enter_current_room()

func on_room_completed():
	var room = dungeon.rooms[dungeon.current_room_index]
	room.cleared = true

	advance_room()

func open_rest_ui():
	for member in dungeon.run_state.party_members:
		member.current_hp = member.character.base_max_hp

	on_room_completed()

func place_segno():
	dungeon.last_segno_index = dungeon.current_room_index
	on_room_completed()

func load_event(event_scene: PackedScene):

	if event_scene == null:
		push_error("Event room has no scene!")
		on_room_completed()
		return

	GameController.start_event(event_scene)
