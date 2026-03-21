extends Control

var dungeon : DungeonRunState
var controller : DungeonController

const TILE_SIZE = 64
const MAP_OFFSET = Vector2(200,200)

func setup(run_state, dungeon_controller):

	dungeon = run_state
	controller = dungeon_controller

	queue_redraw()


func _draw():

	if dungeon == null:
		return

	for pos in dungeon.grid.keys():

		var room : RoomInstance = dungeon.grid[pos]

		var draw_pos = Vector2(pos) * TILE_SIZE + MAP_OFFSET

		var color = Color.GRAY

		if room.cleared:
			color = Color.GREEN
		elif room.visited:
			color = Color.YELLOW

		draw_rect(Rect2(draw_pos, Vector2(TILE_SIZE, TILE_SIZE)), color)

		var label = "?"

		if room.room_data:
			label = room.room_data.room_name.substr(0,1)

		draw_string(
			get_theme_default_font(),
			draw_pos + Vector2(20,40),
			label
		)

		if pos == dungeon.current_pos:
			draw_rect(
				Rect2(draw_pos, Vector2(TILE_SIZE, TILE_SIZE)),
				Color.RED,
				false,
				3
			)


func _gui_input(event):

	if event is InputEventMouseButton and event.pressed:

		var click_pos = event.position - MAP_OFFSET
		var grid_pos = Vector2i(click_pos / TILE_SIZE)

		if dungeon.grid.has(grid_pos):

			controller.move_to_room(grid_pos)
