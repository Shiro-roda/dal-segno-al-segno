extends Node
class_name DungeonController

const BossBuilder = preload("res://resources/characters/bosses/boss_builder.gd")

var dungeon : DungeonRunState

var dungeon_ui: Control
var map_ui: Node3D  # DungeonMap3D (class_name removed to avoid cache conflicts)



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
#	recruit_instance.position = Vector2i(-4, -3)
#	dungeon.grid[Vector2i(-4, -3)] = recruit_instance
	recruit_instance.position = Vector2i(0, -1)
	dungeon.grid[Vector2i(0, -1)] = recruit_instance

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
	dungeon_ui.clear_room_list()  # clear rest/event UI from previous room

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
			# Already cleared - nothing to do

		RoomData.RoomType.BOSS:
			if not room.cleared:
				_trigger_boss_battle()


func on_room_completed():

	var room : RoomInstance = dungeon.grid[dungeon.current_pos]
	room.cleared = true

	# If the recruit room was just cleared, place the boss room on the map now.
	if room.room_data != null and room.room_data.room_type == RoomData.RoomType.RECRUIT:
		_place_boss_room()

	map_ui.redraw_map()


func _place_boss_room() -> void:
	var boss_room_data := RoomData.new()
	boss_room_data.room_name = "The Threshold"
	boss_room_data.room_type = RoomData.RoomType.BOSS
	boss_room_data.danger_level = 5
	boss_room_data.allows_segno = false
	boss_room_data.connections = [Vector2i(0, 0)]  # no exits
	var boss_instance := RoomInstance.new()
	boss_instance.room_data = boss_room_data
#	boss_instance.position = Vector2i(-9, -8)
#	dungeon.grid[Vector2i(-9, -11)] = boss_instance
	boss_instance.position = Vector2i(-1, -1)
	dungeon.grid[Vector2i(-1, -1)] = boss_instance

func get_available_positions() -> Array:
	var room : RoomInstance = dungeon.grid.get(dungeon.current_pos)
	if room == null:
		return []

	var dirs : Array = room.room_data.get_exit_dirs() if room.room_data != null else []

	var positions : Array = []
	for d in dirs:
		var pos = dungeon.current_pos + d
		if not dungeon.grid.has(pos):
			positions.append(pos)
	return positions


# Returns 3 random room choices for a given grid position (cached per pos).
var _room_choice_cache : Dictionary = {}  # Vector2i -> Array[RoomData]

func get_room_choices(pos: Vector2i) -> Array:
	if not _room_choice_cache.has(pos):
		var choices : Array[RoomData] = []
		var pool : Array = dungeon.dungeon_data.rooms.duplicate()
		pool.shuffle()
		for r in pool:
			if choices.size() >= 3:
				break
			if r not in choices:
				choices.append(r)
		_room_choice_cache[pos] = choices
	return _room_choice_cache.get(pos, [])


func cancel_build():
	# Called when the player dismisses the choice panel without picking
	# Don't erase the cache so re-clicking shows the same choices
	pass


func build_room(pos: Vector2i, room_data: RoomData):
	_room_choice_cache.erase(pos)

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


const BOSS_ENCOUNTERS := {
	"Hue":    preload("res://resources/encounters/boss_battles/boss_hue.tres"),
	"Indra":  preload("res://resources/encounters/boss_battles/boss_indra.tres"),
	"Vritra": preload("res://resources/encounters/boss_battles/boss_vritra.tres"),
}

func _trigger_boss_battle() -> void:
	var run := dungeon.run_state
	if run.boss_target == null:
		if run.available_supports.is_empty():
			on_room_completed()
			return
		run.boss_target = run.available_supports[randi() % run.available_supports.size()]
	var encounter : EncounterData = BOSS_ENCOUNTERS.get(run.boss_target.display_name)
	if encounter == null:
		push_error("No boss encounter found for: " + run.boss_target.display_name)
		on_room_completed()
		return
	# Attach a synthetic PartyMemberData to each enemy CharacterData in the encounter
	# so the support actor scripts have will and skill unlocks available.
	for char_data in encounter.enemies:
		if char_data.boss_party_member == null:
			char_data.boss_party_member = BossBuilder.make_party_member(char_data)
	GameController.start_boss_battle(encounter)


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
	if dungeon.last_segno_pos != Vector2i(-999, -999):
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
