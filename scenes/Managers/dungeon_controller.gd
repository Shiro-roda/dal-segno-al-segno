extends Node
class_name DungeonController

var dungeon : DungeonRunState

var dungeon_ui : Control


func _ready():
	add_to_group("dungeon_controller")

	dungeon = GameController.current_dungeon_run

	dungeon_ui = get_parent().get_node("DungeonUI")



func start_dungeon(run_state : RunState, dungeon_data : DungeonData):

	dungeon = DungeonRunState.new()
	dungeon.run_state = run_state
	dungeon.dungeon_data = dungeon_data
	
	GameController.current_dungeon_run = dungeon
	GameController.current_dungeon = dungeon_data

	

	dungeon_ui.setup(dungeon, self)
	
	dungeon_ui.show_room_choices(dungeon, self)


	





func enter_current_room():

	var room : RoomInstance = dungeon.rooms[dungeon.current_room_index]

	if room == null or room.room_data == null:
		push_error("Invalid room!")
		return

	var data : RoomData = room.room_data
	room.visited = true

	print("Entering room:", data.room_name)

	match data.room_type:

		RoomData.RoomType.BATTLE:
			GameController.start_battle(data.encounter)
		
		RoomData.RoomType.ELITE:
			GameController.start_battle(data.encounter)
			
		RoomData.RoomType.EVENT:
			load_event(data.event_scene)

		RoomData.RoomType.REST:
			open_rest_ui()

		RoomData.RoomType.SEGNO:
			place_segno()


func advance_room():
	dungeon.current_room_index += 1

	#if dungeon.current_room_index >= dungeon.rooms.size():
	#	print("Dungeon complete!")
	#	return

	dungeon_ui.show_room_choices(dungeon, self)





func on_room_completed():
	var room = dungeon.rooms[dungeon.current_room_index]
	room.cleared = true

	advance_room()



func open_rest_ui():
	dungeon_ui.show_rest_screen()




func place_segno():
	dungeon.last_segno_index = dungeon.current_room_index
	on_room_completed()


func load_event(event_scene: PackedScene):

	if event_scene == null:
		push_error("Event room has no scene!")
		on_room_completed()
		return

	GameController.start_event(event_scene)
