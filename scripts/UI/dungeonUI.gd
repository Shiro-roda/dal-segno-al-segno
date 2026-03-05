extends Control

@onready var room_list = $RoomList

func setup(dungeon : DungeonRunState):

	room_list.queue_free_children()

	for i in dungeon.rooms.size():

		var room = dungeon.rooms[i]

		var button = Button.new()
		button.text = room.room_data.room_name

		button.disabled = i != dungeon.current_room_index

		button.pressed.connect(func():
			enter_room()
		)

		room_list.add_child(button)
