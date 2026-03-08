extends Node
class_name DungeonController

var dungeon : DungeonRunState

var dungeon_ui: Control
var map_ui: DungeonMap3D



func _ready():

	add_to_group("dungeon_controller")


func start_dungeon(run_state: RunState, dungeon_data: DungeonData):

	if dungeon_ui == null:
		dungeon_ui = get_parent().get_node("DungeonUI")

	if map_ui == null:
		map_ui = get_tree().get_first_node_in_group("dungeon_map_3d")

	dungeon = DungeonRunState.new()
	dungeon.run_state = run_state
	dungeon.dungeon_data = dungeon_data

	GameController.current_dungeon_run = dungeon

	var start_room = RoomInstance.new()
	start_room.room_data = dungeon_data.start_room
	start_room.position = Vector2i.ZERO

	dungeon.grid[Vector2i.ZERO] = start_room
	dungeon.current_pos = Vector2i.ZERO

	# Pre-place recruit room south of start.
	# Uses dungeon_data.recruit_room if assigned, otherwise a default one.
	var recruit_data : RoomData = dungeon_data.recruit_room
	if recruit_data == null:
		recruit_data = RoomData.new()
		recruit_data.room_name = "Crossroads"
		recruit_data.room_type = RoomData.RoomType.RECRUIT
		recruit_data.danger_level = 0
		recruit_data.allows_segno = false
	var recruit_instance := RoomInstance.new()
	recruit_instance.room_data = recruit_data
	recruit_instance.position = Vector2i(0, -1)
	dungeon.grid[Vector2i(-3, -5)] = recruit_instance

	map_ui.setup(dungeon, self)

	# Start dungeon ambient music
	if dungeon_data.dungeon_track != null:
		AudioManagerAuto.play_dungeon_track(dungeon_data.dungeon_track)

	enter_current_room()






func move_to_room(pos : Vector2i):

	if not dungeon.grid.has(pos):
		return

	var diff = pos - dungeon.current_pos

	if diff.length() != 1:
		return

	dungeon.current_pos = pos

	map_ui.redraw_map()

	enter_current_room()


const BATTLE_RESPAWN_CHANCE = 0.4

func enter_current_room():

	var room : RoomInstance = dungeon.grid.get(dungeon.current_pos)

	if room == null:
		push_error("Room missing at " + str(dungeon.current_pos))
		return

	var data : RoomData = room.room_data

	if data == null:
		push_error("Room has no RoomData!")
		return

	room.visited = true

	match data.room_type:

		RoomData.RoomType.BATTLE, RoomData.RoomType.ELITE:
			if not room.cleared or randf() < BATTLE_RESPAWN_CHANCE:
				room.cleared = false
				GameController.start_battle(data.encounter)

		RoomData.RoomType.EVENT:
			load_event(data.event_scene)

		RoomData.RoomType.REST:
			if not room.rested:
				open_rest_ui()

		RoomData.RoomType.SEGNO:
			place_segno()

		RoomData.RoomType.RECRUIT:
			if not room.cleared:
				load_recruit_event()
			# If already cleared (recruited), fall through silently


func on_room_completed():

	var room : RoomInstance = dungeon.grid[dungeon.current_pos]
	room.cleared = true
	dungeon_ui.clear_room_list()

	map_ui.redraw_map()


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
	dungeon_ui.clear_room_list()


var pending_build_pos : Vector2i = Vector2i(-999, -999)
var pending_room_choices : Dictionary = {}  # Vector2i -> Array[RoomData]

func build_room(pos: Vector2i, room_data: RoomData):
	if room_data == null:
		# Generate choices once per position, reuse on repeated clicks
		if not pending_room_choices.has(pos):
			var choices : Array[RoomData] = []
			while choices.size() < 3:
				var choice = dungeon.dungeon_data.rooms.pick_random()
				if choice not in choices:
					choices.append(choice)
			pending_room_choices[pos] = choices
		pending_build_pos = pos
		dungeon_ui.show_room_choices(dungeon, self)
		return

	pending_room_choices.erase(pos)
	pending_build_pos = Vector2i(-999, -999)

	var instance = RoomInstance.new()
	instance.room_data = room_data
	instance.position = pos

	dungeon.grid[pos] = instance
	dungeon.current_pos = pos

	map_ui.redraw_map()

	enter_current_room()


func load_recruit_event() -> void:
	var scene := preload("res://scenes/Events/companion_select/recruit_event.tscn")
	GameController.start_event(scene)


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

func on_party_defeated():

	if dungeon.last_segno_pos != null:
		respawn_at_segno()
	else:
		end_run()

func respawn_at_segno():

	dungeon.current_pos = dungeon.last_segno_pos

	for member in dungeon.run_state.party_members:
		member.current_hp = member.character.base_max_hp / 2

	map_ui.redraw_map()

	enter_current_room()

func end_run():

	print("Run ended")

	GameController.start_world(
		preload("res://scenes/Maps/white_test.tscn")
	)
