extends Control

@onready var room_list = $RoomList
var controller : DungeonController
var dungeon : DungeonRunState

func setup(controller_dungeon : DungeonRunState, dungeon_controller : DungeonController):

	
	print("Setting up UI.")
	controller = dungeon_controller
	dungeon = controller_dungeon

	if controller == null:
		push_error("DungeonController not found!")


	for child in room_list.get_children():
		child.queue_free()


	for i in range(dungeon.rooms.size()):

		var room = dungeon.rooms[i]

		if room.room_data == null:
			continue

		var button = Button.new()
		button.text = room.room_data.room_name

		button.disabled = i != dungeon.current_room_index

		var index := i

		button.pressed.connect(func():
			controller.dungeon.current_room_index = index
			controller.enter_current_room()
		)


		room_list.add_child(button)

func show_rest_screen():

	var rest_button = Button.new()
	rest_button.text = "Rest (+20 HP)"

	rest_button.pressed.connect(func():

		for member in controller.dungeon.run_state.party_members:

			member.current_hp = min(
				member.current_hp + 20,
				member.character.base_max_hp
			)

		controller.on_room_completed()

	)

	room_list.add_child(rest_button)


func show_room_choices(controller_dungeon : DungeonRunState, dungeon_controller : DungeonController):

	for child in room_list.get_children():
		child.queue_free()
	controller = dungeon_controller
	dungeon = controller_dungeon
	var all_rooms = dungeon.dungeon_data.rooms

	var choices = []

	while choices.size() < 3:
		var choice = all_rooms.pick_random()
		if choice not in choices:
			choices.append(choice)

	for room_data in choices:

		var button = Button.new()
		button.text = room_data.room_name

		button.pressed.connect(func():

			var instance = RoomInstance.new()
			instance.room_data = room_data
			instance.position_index = dungeon.current_room_index

			dungeon.rooms.append(instance)

			controller.enter_current_room()

		)

		room_list.add_child(button)
