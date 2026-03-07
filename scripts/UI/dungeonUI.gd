extends Control

@onready var room_list = $RoomList
@onready var controller: DungeonController = $"../DungeonController"

var dungeon : DungeonRunState

func setup(controller_dungeon : DungeonRunState):

	
	print("Setting up UI.")
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

	for child in room_list.get_children():
		child.queue_free()

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



func show_room_choices(dungeon: DungeonRunState, controller: DungeonController):

	clear_room_list()

	var positions = controller.get_available_positions()

	for pos in positions:

		var label = Label.new()
		label.text = "Build at " + str(pos)
		room_list.add_child(label)

		for i in range(3):

			var room_data = dungeon.dungeon_data.rooms.pick_random()
			var data: RoomData = room_data

			var button = Button.new()
			button.text = data.room_name

			button.pressed.connect(func():
				controller.build_room(pos, data)
			)

			room_list.add_child(button)

func clear_room_list():

	if room_list == null:
		push_error("RoomList node missing!")
		return

	for child in room_list.get_children():
		child.queue_free()
