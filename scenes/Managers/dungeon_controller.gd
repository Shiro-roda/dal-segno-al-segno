extends Node
class_name DungeonController

var dungeon : DungeonRunState

@onready var dungeon_ui: Control = $"../DungeonUI"
@onready var map_ui: Control = $"../DungeonMapUI"


func _ready():

	add_to_group("dungeon_controller")


func start_dungeon(run_state: RunState, dungeon_data: DungeonData):

	if map_ui == null:
		map_ui = get_parent().get_node("DungeonMapUI")

	if dungeon_ui == null:
		dungeon_ui = get_parent().get_node("DungeonUI")

	dungeon = DungeonRunState.new()
	dungeon.run_state = run_state
	dungeon.dungeon_data = dungeon_data

	GameController.current_dungeon_run = dungeon

	var start_room = RoomInstance.new()
	start_room.room_data = dungeon_data.start_room
	start_room.position = Vector2i.ZERO

	dungeon.grid[Vector2i.ZERO] = start_room
	dungeon.current_pos = Vector2i.ZERO

	map_ui.setup(dungeon, self)

	enter_current_room()




func move_to_room(pos : Vector2i):

	if not dungeon.grid.has(pos):
		return

	var diff = pos - dungeon.current_pos

	if diff.length() != 1:
		return

	dungeon.current_pos = pos

	map_ui.queue_redraw()

	enter_current_room()


func enter_current_room():

	var room : RoomInstance = dungeon.grid.get(dungeon.current_pos)

	if room.visited and room.cleared:
		show_build_choices()
		return


	if room == null:
		push_error("Room missing at " + str(dungeon.current_pos))
		return

	room.visited = true

	var data : RoomData = room.room_data

	if data == null:
		push_error("Room has no RoomData!")
		return

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


func on_room_completed():

	var room : RoomInstance = dungeon.grid[dungeon.current_pos]
	room.cleared = true

	map_ui.queue_redraw()

	show_build_choices()


func get_available_positions():

	var dirs = [
		Vector2i.UP,
		Vector2i.DOWN,
		Vector2i.LEFT,
		Vector2i.RIGHT
	]

	var positions = []

	for d in dirs:

		var pos = dungeon.current_pos + d

		if not dungeon.grid.has(pos):
			positions.append(pos)

	return positions


func show_build_choices():
	dungeon_ui.show_room_choices(dungeon, self)


func build_room(pos: Vector2i, room_data: RoomData):

	var instance = RoomInstance.new()
	instance.room_data = room_data
	instance.position = pos

	dungeon.grid[pos] = instance
	dungeon.current_pos = pos

	map_ui.queue_redraw()

	enter_current_room()


func load_event(event_scene: PackedScene):

	if event_scene == null:
		push_error("Event room has no scene!")
		on_room_completed()
		return

	GameController.start_event(event_scene)


func open_rest_ui():
	dungeon_ui.show_rest_screen()


func place_segno():

	dungeon.last_segno_pos = dungeon.current_pos

	on_room_completed()
