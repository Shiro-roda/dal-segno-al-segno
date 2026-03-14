extends Node
class_name DungeonController

const BossBuilder = preload("res://resources/characters/bosses/boss_builder.gd")

var dungeon : DungeonRunState

var dungeon_ui: Control
@onready var map_ui: Node3D = $"../../DungeonMap3D"





func _ready():

	add_to_group("dungeon_controller")


func start_dungeon(run_state: RunState, dungeon_data: DungeonData):
	print("[DC] start_dungeon called - stack: ", get_stack())

	if dungeon_ui == null:
		dungeon_ui = get_parent().get_node("DungeonUI")

	if map_ui == null:
		map_ui = get_tree().get_first_node_in_group("dungeon_map_3d")

	dungeon = DungeonRunState.new()
	dungeon.run_state = run_state
	dungeon.dungeon_data = dungeon_data
	_room_choice_cache.clear()

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

	# Enforce bidirectional connection check.
	if not rooms_connected(dungeon.current_pos, pos):
		return

	dungeon.current_pos = pos
	dungeon_ui.clear_room_list()
	enter_current_room()


## Returns true when room A has an exit toward B AND room B has an exit back toward A.
## Ghost (unplaced) positions are not checked here — those go through build_room.
func rooms_connected(a: Vector2i, b: Vector2i) -> bool:
	var diff : Vector2i = b - a
	var room_a : RoomInstance = dungeon.grid.get(a)
	var room_b : RoomInstance = dungeon.grid.get(b)
	if room_a == null or room_b == null:
		return false
	var exits_a : Array = room_a.room_data.get_exit_dirs() if room_a.room_data else []
	var exits_b : Array = room_b.room_data.get_exit_dirs() if room_b.room_data else []
	return diff in exits_a and -diff in exits_b


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
	apply_room_effects(room)

	match data.room_type:

		RoomData.RoomType.BATTLE, RoomData.RoomType.ELITE:
			if not room.cleared or randf() < BATTLE_RESPAWN_CHANCE:
				room.cleared = false
				GameController.start_battle(data.encounter)
			else:
				map_ui.redraw_map()  # already cleared, just show the map

		RoomData.RoomType.EVENT:
			load_event(data.event_scene)

		RoomData.RoomType.REST:
			if not room.rested:
				open_rest_ui()
			else:
				map_ui.redraw_map()  # already rested

		RoomData.RoomType.SEGNO:
			place_segno()

		RoomData.RoomType.RECRUIT:
			if not room.cleared:
				load_recruit_event()
			else:
				map_ui.redraw_map()  # already cleared

		RoomData.RoomType.BOSS:
			if not room.cleared:
				_trigger_boss_battle()
			else:
				map_ui.redraw_map()


func on_room_completed():
	print("[DC] on_room_completed at ", dungeon.current_pos, " grid size=", dungeon.grid.size())
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
	boss_room_data.connections = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1)]  # no exits
	var boss_instance := RoomInstance.new()
	boss_instance.room_data = boss_room_data
#	boss_instance.position = Vector2i(-9, -11)
#	dungeon.grid[Vector2i(-9, -11)] = boss_instance
	boss_instance.position = Vector2i(-1, -1)
	dungeon.grid[Vector2i(-1, -1)] = boss_instance

## Returns positions the player can move to or build on from the current room.
## Splits into two arrays for the map: [navigable_existing, buildable_empty]
func get_available_positions() -> Array:
	return get_buildable_positions()


## Empty neighbour slots reachable from the current room (can be built on).
## Only blocked when the current room itself is at its connection limit.
## Neighbour limit checks happen at build_room time, once we know both rooms.
func get_buildable_positions() -> Array:
	var room : RoomInstance = dungeon.grid.get(dungeon.current_pos)
	if room == null:
		return []
	# If this room is full, nowhere new can be built from it.
	if room.is_connection_full():
		return []
	var dirs : Array = room.room_data.get_exit_dirs() if room.room_data != null else []
	var positions : Array = []
	for d in dirs:
		var pos : Vector2i = dungeon.current_pos + (d as Vector2i)
		if not dungeon.grid.has(pos):
			positions.append(pos)
	return positions


## Existing placed rooms that are mutually connected to the current room.
func get_navigable_positions() -> Array:
	var room : RoomInstance = dungeon.grid.get(dungeon.current_pos)
	if room == null:
		return []
	var dirs : Array = room.room_data.get_exit_dirs() if room.room_data != null else []
	var positions : Array = []
	for d in dirs:
		var pos : Vector2i = dungeon.current_pos + (d as Vector2i)
		if dungeon.grid.has(pos) and rooms_connected(dungeon.current_pos, pos):
			positions.append(pos)
	return positions


## All pairs of mutually-connected placed rooms in the entire dungeon.
## Returns Array of [Vector2i, Vector2i] with a < b to avoid duplicates.
func get_all_connected_pairs() -> Array:
	var pairs : Array = []
	var seen  : Dictionary = {}
	for pos_a in dungeon.grid.keys():
		var room_a : RoomInstance = dungeon.grid[pos_a]
		if room_a == null or room_a.room_data == null:
			continue
		for d in room_a.room_data.get_exit_dirs():
			var pos_b : Vector2i = (pos_a as Vector2i) + (d as Vector2i)
			if not dungeon.grid.has(pos_b):
				continue
			if not rooms_connected(pos_a, pos_b):
				continue
			# Deduplicate: store with the lexicographically-smaller pos first.
			var key : Array = [pos_a, pos_b] if _pos_less(pos_a, pos_b) else [pos_b, pos_a]
			var key_str := str(key)
			if not seen.has(key_str):
				seen[key_str] = true
				pairs.append(key)
	return pairs


func _pos_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


# Returns 3 random room choices for a given grid position (cached per pos).
var _room_choice_cache : Dictionary = {}  # Vector2i -> Array[RoomData]

func get_room_choices(pos: Vector2i) -> Array:
	if not _room_choice_cache.has(pos):
		var choices : Array[RoomData] = []
		var pool : Array = dungeon.dungeon_data.rooms.duplicate()
		# Check if current room restricts which types can be built from here
		var current_room : RoomInstance = dungeon.grid.get(dungeon.current_pos)
		var allowed_types : Array = []
		if current_room and current_room.room_data:
			for effect in current_room.room_data.room_effects:
				if effect.effect_type == RoomEffect.EffectType.RESTRICT_BUILD_POOL:
					allowed_types = effect.get_allowed_types()
					break
		if not allowed_types.is_empty():
			pool = pool.filter(func(r): return r.room_type in allowed_types)
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

	# Count corridors formed by placing this room.
	# The origin room (where we built from) always gets +1, unless it's already full.
	var origin_room : RoomInstance = dungeon.grid.get(dungeon.current_pos)
	if origin_room != null and not origin_room.is_connection_full():
		origin_room.built_connections += 1

	# The new room starts with 1 (back to origin), then gains one more for every
	# other already-placed neighbour it mutually connects to — only if that
	# neighbour still has capacity.
	var new_corridors : int = 1
	const CARDINALS := [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	var new_exits : Array = room_data.get_exit_dirs()
	for d in CARDINALS:
		var nb_pos : Vector2i = pos + d
		if nb_pos == dungeon.current_pos:
			continue  # already counted as origin
		var nb : RoomInstance = dungeon.grid.get(nb_pos)
		if nb == null or nb.room_data == null:
			continue
		if nb.is_connection_full():
			continue  # neighbour is full — corridor doesn't form
		var nb_exits : Array = nb.room_data.get_exit_dirs()
		if d in new_exits and -d in nb_exits:
			new_corridors += 1
			nb.built_connections += 1
	instance.built_connections = new_corridors

	dungeon.grid[pos] = instance
	dungeon.current_pos = pos
	print("[DC] build_room at ", pos, " grid size now=", dungeon.grid.size())

	# Do NOT call redraw_map() here — enter_current_room will trigger a battle/event
	# which hides the dungeon layer anyway. redraw_map() is called by on_room_completed()
	# once the room is actually finished. Calling it here first causes two overlapping
	# async redraws (both await process_frame) that stomp each other.
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


func open_rest_ui() -> void:
	var scene := preload("res://scenes/Events/chapel_event.tscn")
	var event := scene.instantiate() as ChapelEvent
	event.setup(
		dungeon.grid.get(dungeon.current_pos),
		dungeon.run_state
	)
	var event_layer = get_tree().get_first_node_in_group("event_layer")
	var dungeon_layer_node = get_tree().get_first_node_in_group("dungeon_layer")
	if event_layer:
		for c in event_layer.get_children(): c.queue_free()
		event_layer.add_child(event)
		if dungeon_layer_node: dungeon_layer_node.visible = false
		event_layer.visible = true
		event.event_finished.connect(func():
			for c in event_layer.get_children(): c.queue_free()
			event_layer.visible = false
			if dungeon_layer_node: dungeon_layer_node.visible = true
			on_room_completed()
		, CONNECT_ONE_SHOT)


func place_segno(from_chapel: bool = false) -> void:
	# Consume one Segno item from inventory
	var segno_item_idx := _find_segno_in_inventory()
	if segno_item_idx < 0:
		# No Segno item — fall back to legacy position-only behaviour
		dungeon.last_segno_pos = dungeon.current_pos
		_show_segno_event(from_chapel, false)
		return
	_consume_inventory_item(segno_item_idx)
	var replacing : bool = dungeon.segno_snapshot != null and not dungeon.segno_snapshot.used
	dungeon.segno_snapshot = SegnoSnapshot.capture(dungeon.run_state, dungeon.current_pos)
	dungeon.last_segno_pos = dungeon.current_pos  # keep in sync for UI checks
	_show_segno_event(from_chapel, replacing)


func _show_segno_event(from_chapel: bool, replacing: bool) -> void:
	var scene := preload("res://scenes/Events/segno_event.tscn")
	var event := scene.instantiate()
	event.is_replacing = replacing
	var event_layer = get_tree().get_first_node_in_group("event_layer")
	if event_layer:
		var dungeon_layer = get_tree().get_first_node_in_group("dungeon_layer")
		if dungeon_layer: dungeon_layer.visible = false
		for c in event_layer.get_children(): c.queue_free()
		event_layer.add_child(event)
		event_layer.visible = true
		event.event_finished.connect(func():
			for c in event_layer.get_children(): c.queue_free()
			event_layer.visible = false
			if dungeon_layer: dungeon_layer.visible = true
			if not from_chapel:
				on_room_completed()
			else:
				dungeon_ui.show_rest_screen()
		, CONNECT_ONE_SHOT)
	else:
		on_room_completed()

func on_party_defeated():
	var _snap := dungeon.segno_snapshot as SegnoSnapshot
	var has_snapshot : bool = _snap != null and not _snap.used
	var has_legacy   : bool = dungeon.last_segno_pos != Vector2i(-999, -999)
	if has_snapshot:
		respawn_at_segno()
	elif has_legacy:
		_legacy_respawn()
	else:
		end_run()


func respawn_at_segno() -> void:
	# Full snapshot restore — returns party to exact state when Segno was placed.
	var snap := dungeon.segno_snapshot as SegnoSnapshot
	snap.restore_into(dungeon.run_state)
	dungeon.current_pos = snap.placed_at
	# Snapshot is now consumed (used = true set inside restore_into)
	dungeon.last_segno_pos = Vector2i(-999, -999)
	dungeon.segno_snapshot = null
	map_ui.redraw_map()
	enter_current_room()


func _legacy_respawn() -> void:
	# Old behaviour: just move back to segno position, restore half HP.
	dungeon.current_pos = dungeon.last_segno_pos
	for member in dungeon.run_state.party_members:
		member.current_hp = member.character.base_max_hp / 2
	map_ui.redraw_map()
	enter_current_room()

func end_run():
	print("Run ended")
	GameController.start_new_game()


# --- Inventory helpers ---

func _find_segno_in_inventory() -> int:
	var inv : Array = dungeon.run_state.inventory
	for i in inv.size():
		if inv[i].item_data is SegnoItem:
			return i
	return -1


func _consume_inventory_item(idx: int) -> void:
	var inv : Array = dungeon.run_state.inventory
	if idx < 0 or idx >= inv.size():
		return
	var item : ItemInstance = inv[idx]
	item.stacks -= 1
	if item.stacks <= 0:
		inv.remove_at(idx)


# --- Room effect application ---

func apply_room_effects(room: RoomInstance) -> void:
	if room == null or room.room_data == null:
		return
	var run := dungeon.run_state
	for effect in room.room_data.room_effects:
		match effect.effect_type:

			RoomEffect.EffectType.AMMO_RESTORE_ON_PASS:
				# Only fires when room is already cleared (passing through)
				if not room.cleared:
					continue
				if randf() < effect.ammo_chance:
					run.restore_ammo(effect.ammo_amount)
					print("[RoomEffect] Restored %d ammo." % effect.ammo_amount)
					# Risk: reactivate the encounter
					if effect.risk_reactivate and randf() < effect.ammo_chance:
						room.cleared = false
						print("[RoomEffect] High Noon reactivated!")

			RoomEffect.EffectType.PARTY_HEAL_ON_ENTER:
				for pm in run.party_members:
					var max_hp : int = pm.character.base_max_hp + pm.bonus_max_hp
					var heal := effect.heal_amount if effect.heal_flat else int(max_hp * effect.heal_amount / 100.0)
					pm.current_hp = min(pm.current_hp + heal, max_hp)

			RoomEffect.EffectType.WILL_RESTORE_ON_ENTER:
				for pm in run.party_members:
					pm.restore_will(effect.will_amount)

			RoomEffect.EffectType.RESTRICT_BUILD_POOL:
				# Handled at build time in get_room_choices; stored on the room for reference.
				pass

			RoomEffect.EffectType.TEMPO_BONUS_ON_ENTER:
				# Stored in run_flags so the battle manager can read it at battle start.
				run.run_flags["tempo_bonus_next_battle"] = effect.tempo_amount
