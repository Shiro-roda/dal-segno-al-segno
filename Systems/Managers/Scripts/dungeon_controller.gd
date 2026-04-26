extends Node
class_name DungeonController

const BossBuilder = preload("res://Characters/Scripts/boss_builder.gd")

## Minimum Manhattan distance a new Segno room must be from the current one.
const SEGNO_MIN_DIST : int = 4
## Minimum number of valid candidate slots required before a transit can begin.
## Kept low so small dungeons aren't blocked; the range growth does the real work.
const SEGNO_MIN_CANDIDATES : int = 1

var dungeon : DungeonRunState

var dungeon_ui: Control
var map_ui: Node3D


func _ready():
	add_to_group("dungeon_controller")


func start_dungeon(run_state: RunState, dungeon_data: DungeonData, map: Node3D = null):
	print("[DC] start_dungeon called - stack: ", get_stack())

	if dungeon_ui == null:
		dungeon_ui = get_parent().get_node("DungeonUI")

	if map != null:
		map_ui = map
	elif map_ui == null:
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

	var recruit_data : RoomData = dungeon_data.recruit_room
	if recruit_data == null:
		recruit_data = RoomData.new()
		recruit_data.room_name = "Crossroads"
		recruit_data.room_type = RoomData.RoomType.RECRUIT
		recruit_data.danger_level = 0
		recruit_data.allows_segno = false
	var recruit_instance := RoomInstance.new()
	recruit_instance.room_data = recruit_data
	recruit_instance.position = Vector2i(4, -5)
	dungeon.grid[Vector2i(4, -5)] = recruit_instance

	map_ui.setup(dungeon, self)

	# Grant starting resources for the first run through.
	run_state.road_tiles_remaining += 2
	run_state.reroll_charges       += 1

	if dungeon_data.dungeon_track != null:
		AudioManagerAuto.play_dungeon_track(dungeon_data.dungeon_track)

	enter_current_room()


func resume_dungeon(loaded: DungeonRunState, map: Node3D = null) -> void:
	if dungeon_ui == null:
		dungeon_ui = get_parent().get_node("DungeonUI")
	if map != null:
		map_ui = map
	elif map_ui == null:
		map_ui = get_tree().get_first_node_in_group("dungeon_map_3d")
	dungeon = loaded
	GameController.current_dungeon_run = dungeon
	_room_choice_cache.clear()
	map_ui.setup(dungeon, self)
	if dungeon.dungeon_data and dungeon.dungeon_data.dungeon_track:
		AudioManagerAuto.play_dungeon_track(dungeon.dungeon_data.dungeon_track)
	map_ui.redraw_map()


func move_to_room(pos : Vector2i):
	if not dungeon.grid.has(pos):
		return
	var diff = pos - dungeon.current_pos
	if diff.length() != 1:
		return
	if not rooms_connected(dungeon.current_pos, pos):
		return
	dungeon.current_pos = pos
	dungeon_ui.clear_room_list()
	enter_current_room()


func rooms_connected(a: Vector2i, b: Vector2i) -> bool:
	var room_a : RoomInstance = dungeon.grid.get(a)
	if room_a == null:
		return false
	return b in room_a.explicit_connections


## Base respawn chance for a cleared battle during AL_SEGNO (2nd+ pass).
const AL_SEGNO_RESPAWN_BASE  : float = 0.25
const AL_SEGNO_RESPAWN_STEP  : float = 0.10
const AL_SEGNO_RESPAWN_MAX   : float = 0.65

func _room_should_battle(room: RoomInstance) -> bool:
	if not room.cleared:
		return true
	if dungeon.is_battle_reprimed_transit():
		# 2nd+ pass through a cleared battle in AL_SEGNO: rolling re-encounter.
		if room.al_segno_passes >= 1:
			var chance := minf(
				AL_SEGNO_RESPAWN_BASE + AL_SEGNO_RESPAWN_STEP * (room.al_segno_passes - 1),
				AL_SEGNO_RESPAWN_MAX)
			if randf() < chance:
				return true
	return false


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
	# Motif discovery: first time entering each room type.
	if data.room_type != RoomData.RoomType.ROAD:
		var rtype_int : int = data.room_type as int
		var rtype_key : String = "room:" + str(rtype_int)
		MetaProgress.notify_encounter(rtype_key, data.room_name if data.room_name != "" else rtype_key)
	# Track AL_SEGNO passes for rolling re-encounter probability.
	if dungeon.is_battle_reprimed_transit() and \
			room.room_data.room_type in [RoomData.RoomType.BATTLE, RoomData.RoomType.ELITE]:
		room.al_segno_passes += 1
	apply_room_effects(room)

	match data.room_type:
		RoomData.RoomType.BATTLE, RoomData.RoomType.ELITE:
			if _room_should_battle(room):
				room.cleared = false
				AudioManagerAuto.reset_ambience()
				await AudioManagerAuto.fade_out_bgm()
				GameController.start_battle(data.encounter, dungeon)
			else:
				map_ui.redraw_map()

		RoomData.RoomType.EVENT:
			load_event(data.event_scene)

		RoomData.RoomType.REST:
			var tense_phase : bool = dungeon.is_battle_reprimed_transit()
			if not room.rested or tense_phase:
				open_rest_ui()
			else:
				map_ui.redraw_map()

		RoomData.RoomType.SEGNO:
			# A cleared Segno room is a past placement — just show the map.
			if room.cleared:
				map_ui.redraw_map()
			else:
				_handle_segno_room()

		RoomData.RoomType.RECRUIT:
			if not room.cleared:
				load_recruit_event()
			else:
				map_ui.redraw_map()

		RoomData.RoomType.BOSS:
			if not room.cleared:
				_trigger_boss_battle()
			else:
				map_ui.redraw_map()

		RoomData.RoomType.ROAD:
			# Roads are pure connectors — auto-clear and show the map.
			if not room.cleared:
				on_room_completed()
			else:
				map_ui.redraw_map()

		RoomData.RoomType.SHOP:
			_open_shop(room)

		RoomData.RoomType.TREASURE:
			if not room.cleared:
				_open_treasure_room(room)
			else:
				map_ui.redraw_map()


func on_room_completed():
	print("[DC] on_room_completed at ", dungeon.current_pos, " grid size=", dungeon.grid.size())
	var room : RoomInstance = dungeon.grid[dungeon.current_pos]
	room.cleared = true

	if room.room_data != null and room.room_data.room_type == RoomData.RoomType.RECRUIT:
		_place_boss_room()

	var dui = get_tree().get_first_node_in_group("dungeon_ui")
	if dui and dui.has_method("_refresh_inventory_bar"):
		dui._refresh_inventory_bar()

	map_ui.redraw_map()

	# Autosave after every room completion.
	SaveManager.save_run(dungeon.run_state, dungeon)


func _place_boss_room() -> void:
	var boss_room_data := RoomData.new()
	boss_room_data.room_name = "The Threshold"
	boss_room_data.room_type = RoomData.RoomType.BOSS
	boss_room_data.danger_level = 5
	boss_room_data.allows_segno = false
	boss_room_data.connections = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	var boss_instance := RoomInstance.new()
	boss_instance.room_data = boss_room_data
	boss_instance.position = Vector2i(-9, -9)
	dungeon.grid[Vector2i(-9, -9)] = boss_instance


func get_available_positions() -> Array:
	return get_buildable_positions()


func get_buildable_positions() -> Array:
	if dungeon.is_building_locked():
		return []
	# TERMINAL rooms have no outgoing exits — nothing can be built from them.
	var cur_room : RoomInstance = dungeon.grid.get(dungeon.current_pos)
	if cur_room != null and cur_room.room_data != null and cur_room.room_data.is_terminal():
		return []
	var room : RoomInstance = dungeon.grid.get(dungeon.current_pos)
	if room == null:
		return []
	if room.is_connection_full():
		return []
	var dirs : Array = room.room_data.get_exit_dirs() if room.room_data != null else []
	var positions : Array = []
	for d in dirs:
		var pos : Vector2i = dungeon.current_pos + (d as Vector2i)
		if not dungeon.grid.has(pos):
			positions.append(pos)
	return positions


func get_navigable_positions() -> Array:
	var room : RoomInstance = dungeon.grid.get(dungeon.current_pos)
	if room == null:
		return []
	# explicit_connections is the authoritative navigation list.
	var positions : Array = []
	for pos in room.explicit_connections:
		if dungeon.grid.has(pos):
			positions.append(pos)
	return positions


func get_all_connected_pairs() -> Array:
	var pairs : Array = []
	var seen  : Dictionary = {}
	for pos_a in dungeon.grid.keys():
		var room_a : RoomInstance = dungeon.grid[pos_a]
		if room_a == null:
			continue
		for pos_b in room_a.explicit_connections:
			var key : Array = [pos_a, pos_b] if _pos_less(pos_a, pos_b) else [pos_b, pos_a]
			var key_str := str(key)
			if not seen.has(key_str):
				seen[key_str] = true
				pairs.append(key)
	return pairs


func _pos_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


## Explicitly connect two adjacent rooms. Updates both sides.
func _make_connection(pos_a: Vector2i, pos_b: Vector2i) -> void:
	var room_a : RoomInstance = dungeon.grid.get(pos_a)
	var room_b : RoomInstance = dungeon.grid.get(pos_b)
	if room_a == null or room_b == null:
		return
	if pos_b not in room_a.explicit_connections:
		room_a.explicit_connections.append(pos_b)
		room_a.built_connections += 1
	if pos_a not in room_b.explicit_connections:
		room_b.explicit_connections.append(pos_a)
		room_b.built_connections += 1


## True if two adjacent rooms could legally form a new connection.
func _can_connect(pos_a: Vector2i, pos_b: Vector2i) -> bool:
	var room_a : RoomInstance = dungeon.grid.get(pos_a)
	var room_b : RoomInstance = dungeon.grid.get(pos_b)
	if room_a == null or room_b == null:
		return false
	if pos_b in room_a.explicit_connections:
		return false  # already connected
	if room_a.is_connection_full() or room_b.is_connection_full():
		return false
	# Terminal rooms cannot accept new connections.
	if room_b.room_data != null and room_b.room_data.is_terminal():
		return false
	if room_a.room_data != null and room_a.room_data.is_terminal():
		return false
	# Both rooms must have exits pointing at each other.
	var diff : Vector2i = pos_b - pos_a
	var exits_a : Array = room_a.room_data.get_exit_dirs() if room_a.room_data else []
	var exits_b : Array = room_b.room_data.get_exit_dirs() if room_b.room_data else []
	return diff in exits_a and -diff in exits_b


var _room_choice_cache : Dictionary = {}

## Spend one reprise charge on a ghost slot, regenerating its choices.
func reroll_room_choices(pos: Vector2i) -> void:
	var run := dungeon.run_state
	if run.reroll_charges <= 0:
		return
	run.reroll_charges -= 1
	_room_choice_cache.erase(pos)


func get_room_choices(pos: Vector2i) -> Array:
	if not _room_choice_cache.has(pos):
		var choices : Array[RoomData] = []
		var pool : Array = dungeon.dungeon_data.rooms.duplicate()
		var current_room : RoomInstance = dungeon.grid.get(dungeon.current_pos)
		var allowed_types : Array = []
		if current_room and current_room.room_data:
			for effect in current_room.room_data.room_effects:
				if effect.effect_type == RoomEffect.EffectType.RESTRICT_BUILD_POOL:
					allowed_types = effect.get_allowed_types()
					break
		if not allowed_types.is_empty():
			pool = pool.filter(func(r): return r.room_type in allowed_types)
		# Depletion weighting: count how many of each RoomData already exist in grid.
		var counts : Dictionary = {}
		for inst in dungeon.grid.values():
			var rd : RoomData = (inst as RoomInstance).room_data
			if rd != null:
				counts[rd] = counts.get(rd, 0) + 1
		# Build a weighted list: weight = 1 / (1 + count). Weighted random draw.
		var weighted : Array = []
		for r in pool:
			var w : float = 1.0 / (1.0 + counts.get(r, 0))
			weighted.append({"room": r, "w": w})
		var picked : Array = []
		for _i in 3:
			if weighted.is_empty():
				break
			var total : float = 0.0
			for entry in weighted: total += entry["w"]
			var roll := randf() * total
			var acc  : float = 0.0
			for entry in weighted:
				acc += entry["w"]
				if roll <= acc:
					picked.append(entry["room"])
					weighted.erase(entry)
					break
		for r in picked:
			choices.append(r)
		_room_choice_cache[pos] = choices
	return _room_choice_cache.get(pos, [])


func cancel_build():
	pass


func build_room(pos: Vector2i, room_data: RoomData):
	_room_choice_cache.erase(pos)
	# Road tiles spend from the player's tile pool, not from the dungeon room pool.
	if room_data.room_type == RoomData.RoomType.ROAD:
		dungeon.run_state.road_tiles_remaining = max(0, dungeon.run_state.road_tiles_remaining - 1)

	var instance = RoomInstance.new()
	instance.room_data = room_data
	instance.position = pos

	var road_tile : bool = room_data.room_type == RoomData.RoomType.ROAD
	dungeon.grid[pos] = instance

	# Connect the new room to the origin room it was built from.
	# For Terminal rooms, only the origin expends a connection slot;
	# the terminal room records the origin for navigation (leaving) but
	# its own built_connections is not counted against max_connections.
	if not road_tile:
		var origin : RoomInstance = dungeon.grid.get(dungeon.current_pos)
		if room_data.is_terminal():
			# Record both sides for navigation, but only charge the origin.
			if origin != null and not origin.is_connection_full():
				if pos not in origin.explicit_connections:
					origin.explicit_connections.append(pos)
					origin.built_connections += 1
			if dungeon.current_pos not in instance.explicit_connections:
				instance.explicit_connections.append(dungeon.current_pos)
				# Don't increment built_connections on Terminal itself.
		else:
			_make_connection(dungeon.current_pos, pos)
	print("[DC] build_room at ", pos, " grid size now=", dungeon.grid.size())

	if room_data.room_type == RoomData.RoomType.ROAD:
		_room_choice_cache.clear()
		map_ui.redraw_map()
	else:
		dungeon.current_pos = pos
		enter_current_room()


## After entering a room, check for adjacent placed rooms that could connect.
## For each eligible pair, show a yes/no prompt in the map UI.
func _propose_side_connections(pos: Vector2i) -> void:
	const CARDINALS := [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	var proposals : Array = []
	for d in CARDINALS:
		var nb_pos : Vector2i = pos + d
		if not dungeon.grid.has(nb_pos):
			continue
		if nb_pos == dungeon.current_pos:
			continue
		if _can_connect(pos, nb_pos):
			proposals.append(nb_pos)
	if proposals.is_empty():
		return
	map_ui.show_connection_proposals(pos, proposals, self)


func accept_connection_proposal(pos_a: Vector2i, pos_b: Vector2i) -> void:
	if _can_connect(pos_a, pos_b):
		_make_connection(pos_a, pos_b)
		map_ui.redraw_map()


func load_recruit_event() -> void:
	var scene := preload("res://Events/Scenes/recruit_event.tscn")
	GameController.start_event(scene)


const BOSS_ENCOUNTERS := {
	"Hue":    preload("res://Encounters/Resources/BossBattles/boss_hue.tres"),
	"Indra":  preload("res://Encounters/Resources/BossBattles/boss_indra.tres"),
	"Vritra": preload("res://Encounters/Resources/BossBattles/boss_vritra.tres"),
}

func _trigger_boss_battle() -> void:
	MetaProgress.notify_encounter("phase:al_fine", "Al Fine")
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
	var scene := preload("res://Events/Scenes/chapel_event.tscn")
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


# ── Segno / Phase logic ───────────────────────────────────────────────────────

## Called when Semiosis at a rest room fills the third charge.
## Converts the Segno pickup room to SEGNO type. Does not reprime or lock building.
## DA_CAPO / GRAND_PAUSE: pickup room = entrance (Vector2i.ZERO)
## DAL_SEGNO:         pickup room = current segno_pos
func on_semiosis_complete() -> void:
	var pickup_pos : Vector2i
	match dungeon.phase:
		DungeonRunState.Phase.DA_CAPO:
			# First Segno always forms at the dungeon entrance.
			pickup_pos = Vector2i.ZERO
		DungeonRunState.Phase.GRAND_PAUSE:
			# Redo Semiosis at the most recently placed Segno position.
			if dungeon.past_segno_positions.is_empty():
				pickup_pos = Vector2i.ZERO
			else:
				pickup_pos = dungeon.past_segno_positions.back() as Vector2i
		_:
			return  # Semiosis only applies before the first Segno or after GRAND_PAUSE

	var room : RoomInstance = dungeon.grid.get(pickup_pos)
	if room != null and room.room_data != null:
		var segno_data := RoomData.new()
		segno_data.room_name       = "Segno"
		segno_data.room_type       = RoomData.RoomType.SEGNO
		segno_data.allows_segno    = false
		segno_data.max_connections = 4
		segno_data.connections     = room.room_data.connections.duplicate()
		segno_data.room_model      = SEGNO_ROOM_SCENE
		room.room_data             = segno_data
		room.cleared               = false

	map_ui.redraw_map()


func _handle_segno_room() -> void:
	var run := dungeon.run_state
	match dungeon.phase:

		DungeonRunState.Phase.DA_CAPO, DungeonRunState.Phase.GRAND_PAUSE:
			if not run.has_full_segno():
				map_ui.redraw_map()
				return
			var candidates := _find_next_segno_candidates()
			if candidates.is_empty():
				_show_segno_blocked_notice()
				return
			_prompt_pickup_segno(false)

		DungeonRunState.Phase.DAL_SEGNO:
			# No charge requirement — the Segno is always available to pick up.
			# Only gate is exploration radius (enough candidates outside min range).
			var candidates := _find_next_segno_candidates()
			if candidates.is_empty():
				_show_segno_blocked_notice()
				return
			_prompt_pickup_segno(true)

		DungeonRunState.Phase.DC_AL_SEGNO, DungeonRunState.Phase.DS_AL_SEGNO:
			_do_place_segno()

		DungeonRunState.Phase.AL_FINE:
			_trigger_boss_battle()

		_:
			map_ui.redraw_map()


func _prompt_pickup_segno(is_ds: bool) -> void:
	_show_segno_pickup_event(is_ds)


func _show_segno_pickup_event(is_ds: bool) -> void:
	var scene := preload("res://Events/Scenes/segno_event.tscn")
	var event := scene.instantiate()
	event.set("is_pickup_prompt", true)
	event.set("is_ds_transit", is_ds)
	var event_layer = get_tree().get_first_node_in_group("event_layer")
	if event_layer:
		var dungeon_layer = get_tree().get_first_node_in_group("dungeon_layer")
		if dungeon_layer: dungeon_layer.visible = false
		for c in event_layer.get_children(): c.queue_free()
		event_layer.add_child(event)
		event_layer.visible = true
		event.pickup_confirmed.connect(func():
			for c in event_layer.get_children(): c.queue_free()
			event_layer.visible = false
			if dungeon_layer: dungeon_layer.visible = true
			_execute_pickup(is_ds)
		, CONNECT_ONE_SHOT)
		event.event_finished.connect(func():
			for c in event_layer.get_children(): c.queue_free()
			event_layer.visible = false
			if dungeon_layer: dungeon_layer.visible = true
			map_ui.redraw_map()
		, CONNECT_ONE_SHOT)
	else:
		_execute_pickup(is_ds)


func _execute_pickup(is_ds: bool) -> void:
	var run := dungeon.run_state
	# Record the pickup position as a permanent Segno anchor before finding
	# candidates, so the exclusion zone around it is respected immediately.
	if dungeon.current_pos not in dungeon.past_segno_positions:
		dungeon.past_segno_positions.append(dungeon.current_pos)
	var candidates := _find_next_segno_candidates()
	var target : Vector2i = candidates[randi() % candidates.size()]
	dungeon.next_segno_target = target
	_place_segno_room_at(target)
	run.consume_segno()
	_revert_room_at(dungeon.current_pos)
	if is_ds:
		for pos in dungeon.grid.keys():
			var room : RoomInstance = dungeon.grid[pos]
			if room.room_data != null and \
					room.room_data.room_type in [RoomData.RoomType.BATTLE, RoomData.RoomType.ELITE]:
				room.cleared = false
				room.al_segno_passes = 0  # reset per-transit pass counter
		_spawn_treasure_rooms()
		dungeon.phase = DungeonRunState.Phase.DS_AL_SEGNO
		# Motif discovery: first time reaching Al Segno (DS variant).
		MetaProgress.notify_encounter("phase:al_segno", "Al Segno")
	else:
		dungeon.phase = DungeonRunState.Phase.DC_AL_SEGNO
		MetaProgress.notify_encounter("phase:dc_al_segno", "Da Capo al Segno")
	on_room_completed()


func _do_place_segno() -> void:
	var run := dungeon.run_state
	var replacing : bool = dungeon.segno_snapshot != null and not dungeon.segno_snapshot.used
	dungeon.segno_snapshot = SegnoSnapshot.capture(
		run,
		dungeon.current_pos,
		DungeonRunState.Phase.DAL_SEGNO,
		dungeon.current_pos,
		dungeon.past_segno_positions,
		dungeon.grid
	)
	# Compute min_dist BEFORE appending so we can measure the gap between
	# the previous Segno (last entry in past_segno_positions) and this one.
	# min_dist = distance from the last pickup to this placement, floored at SEGNO_MIN_DIST.
	# past_segno_positions always contains at least the pickup position by this point.
	if not dungeon.past_segno_positions.is_empty():
		var prev : Vector2i = dungeon.past_segno_positions.back() as Vector2i
		var curr : Vector2i = dungeon.current_pos
		dungeon.segno_min_dist = max(SEGNO_MIN_DIST,
			abs(curr.x - prev.x) + abs(curr.y - prev.y))
	else:
		dungeon.segno_min_dist = SEGNO_MIN_DIST

	if dungeon.current_pos not in dungeon.past_segno_positions:
		dungeon.past_segno_positions.append(dungeon.current_pos)
	dungeon.segno_pos         = dungeon.current_pos
	dungeon.next_segno_target = Vector2i(-999, -999)
	dungeon.phase             = DungeonRunState.Phase.DAL_SEGNO
	# Motif discovery: first time reaching DAL_SEGNO phase.
	MetaProgress.notify_encounter("phase:dal_segno", "Dal Segno")
	# Lock the safe-phase ceiling to max party level + shrinking bonus.
	# The bonus is generous early and ticks down each transit so the player
	# has breathing room at first but must earn more through al Segno grinding.
	var locked_level : int = 1
	for m in dungeon.run_state.party_members:
		if m.level > locked_level:
			locked_level = m.level
	var bonus_arr := DungeonRunState.CEILING_BONUSES
	var bonus : int = bonus_arr[min(dungeon.segno_transit_count, bonus_arr.size() - 1)]
	dungeon.segno_level_ceiling = min(locked_level + bonus, LevelTable.MAX_LEVEL)
	dungeon.segno_transit_count += 1
	_spawn_suggested_elite()
	_show_segno_event(false, replacing)


const SEGNO_ROOM_SCENE = preload("res://Rooms/Models/Scenes/segno_room.tscn")

func _place_segno_room_at(pos: Vector2i) -> void:
	# Never overwrite a room that already exists (e.g. a pre-seeded elite).
	if dungeon.grid.has(pos):
		push_warning("[DC] _place_segno_room_at: pos %s already occupied, skipping" % pos)
		return
	var segno_data := RoomData.new()
	segno_data.room_name       = "Threshold"
	segno_data.room_type       = RoomData.RoomType.SEGNO
	segno_data.allows_segno    = false
	segno_data.max_connections = 4
	segno_data.room_model      = SEGNO_ROOM_SCENE
	var inst := RoomInstance.new()
	inst.room_data = segno_data
	inst.position  = pos
	dungeon.grid[pos] = inst


## Flood-fill from origin through mutually connected rooms.
## Returns a Dictionary of Vector2i positions that are reachable from the player.
func _get_connected_positions() -> Dictionary:
	var visited : Dictionary = {}
	var queue   : Array      = [Vector2i.ZERO]
	visited[Vector2i.ZERO]   = true
	while not queue.is_empty():
		var pos : Vector2i = queue.pop_front()
		var room : RoomInstance = dungeon.grid.get(pos)
		if room == null:
			continue
		for nb in room.explicit_connections:
			if visited.has(nb):
				continue
			if not dungeon.grid.has(nb):
				continue
			visited[nb] = true
			queue.append(nb)
	return visited


## Returns empty grid positions reachable and far enough from all past Segno spots.
## Minimum range is stored on dungeon.segno_min_dist, set at each Segno placement.
func _find_next_segno_candidates() -> Array:
	var candidates : Array = []
	var min_dist : int = dungeon.segno_min_dist
	# Only consider ghost slots adjacent to the connected component from origin.
	var connected : Dictionary = _get_connected_positions()
	for placed_pos in connected.keys():
		var placed_room : RoomInstance = dungeon.grid.get(placed_pos)
		if placed_room == null or placed_room.room_data == null:
			continue
		# A full room can't form a new connection — any ghost slot beyond it
		# would be unreachable, so skip it as a Segno candidate source.
		if placed_room.is_connection_full():
			continue
		for d in placed_room.room_data.get_exit_dirs():
			var candidate : Vector2i = (placed_pos as Vector2i) + d
			if dungeon.grid.has(candidate):
				continue
			if candidate in candidates:
				continue
			# Build the full set of anchors: all past positions + live segno_pos.
			# current_pos is also included so a freshly placed Segno (not yet
			# appended to past_segno_positions) is still respected.
			var too_close := false
			var anchors_check : Array = dungeon.past_segno_positions.duplicate()
			if dungeon.segno_pos != Vector2i(-999, -999) and \
					dungeon.segno_pos not in anchors_check:
				anchors_check.append(dungeon.segno_pos)
			if dungeon.current_pos not in anchors_check:
				anchors_check.append(dungeon.current_pos)
			for anchor in anchors_check:
				var a : Vector2i = anchor as Vector2i
				var dist : int = abs(candidate.x - a.x) + abs(candidate.y - a.y)
				if dist < min_dist:
					too_close = true
					break
			if not too_close:
				candidates.append(candidate)
	return candidates


func _spawn_suggested_elite() -> void:
	# The elite must be:
	#  (a) between min_dist + 1 and min_dist from every Segno anchor — further than the
	#      next Segno target range, so it clearly reads as "explore out here"
	#  (b) NOT adjacent to any room in the player-connected component —
	#      it sits in genuinely unexplored territory, unreachable without
	#      building new rooms toward it.
	var anchors : Array = dungeon.past_segno_positions.duplicate()
	if dungeon.segno_pos != Vector2i(-999, -999) and dungeon.segno_pos not in anchors:
		anchors.append(dungeon.segno_pos)
	var outer_dist : int = dungeon.segno_min_dist + 1
	var connected : Dictionary = _get_connected_positions()
	const CARDINALS := [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]

	# Scan a generous area around the current Segno for valid positions.
	var candidates : Array = []
	var search_range : int = outer_dist
	var origin : Vector2i = dungeon.segno_pos if dungeon.segno_pos != Vector2i(-999,-999) \
		else Vector2i.ZERO
	for dx in range(-search_range, search_range + 1):
		for dy in range(-search_range, search_range + 1):
			var pos : Vector2i = origin + Vector2i(dx, dy)
			# Skip occupied positions.
			if dungeon.grid.has(pos):
				continue
			# Must be outside outer_dist from every anchor.
			var far_enough := true
			for a in anchors:
				var d : int = abs(pos.x - (a as Vector2i).x) + abs(pos.y - (a as Vector2i).y)
				if d < outer_dist:
					far_enough = false
					break
			if not far_enough:
				continue
			# Must NOT be adjacent to any player-connected room.
			var adj_to_connected := false
			for dir in CARDINALS:
				if connected.has(pos + dir):
					adj_to_connected = true
					break
			if adj_to_connected:
				continue
			candidates.append(pos)

	# Fall back to any outer candidate if none are fully disconnected.
	if candidates.is_empty():
		for dx in range(-search_range, search_range + 1):
			for dy in range(-search_range, search_range + 1):
				var pos : Vector2i = origin + Vector2i(dx, dy)
				if dungeon.grid.has(pos):
					continue
				var far_enough := true
				for a in anchors:
					var d : int = abs(pos.x - (a as Vector2i).x) + abs(pos.y - (a as Vector2i).y)
					if d < outer_dist:
						far_enough = false
						break
				if far_enough:
					candidates.append(pos)
	if candidates.is_empty():
		return

	candidates.shuffle()
	var target : Vector2i = candidates[0]
	var elite_data : RoomData = null
	for r in dungeon.dungeon_data.rooms:
		if r.room_type == RoomData.RoomType.ELITE:
			elite_data = r
			break
	if elite_data == null:
		return
	var inst := RoomInstance.new()
	inst.room_data = elite_data
	inst.position  = target
	dungeon.grid[target] = inst
	map_ui.redraw_map()


## Spawn 1-2 treasure rooms in empty ghost slots at AL_SEGNO start.
## Prefers positions adjacent to dead-end rooms (high connectivity dead ends)
## so they reward players who built exploratory side branches.
func _spawn_treasure_rooms() -> void:
	var all_empty : Array = []
	for pos in dungeon.grid.keys():
		var room : RoomInstance = dungeon.grid[pos]
		if room.room_data == null:
			continue
		for d in room.room_data.get_exit_dirs():
			var candidate : Vector2i = (pos as Vector2i) + d
			if dungeon.grid.has(candidate):
				continue
			if candidate in all_empty:
				continue
			all_empty.append(candidate)
	if all_empty.is_empty():
		return
	all_empty.shuffle()
	var count : int = min(2, all_empty.size())
	for i in count:
		var treasure_data := RoomData.new()
		treasure_data.room_name    = "Cache"
		treasure_data.room_type    = RoomData.RoomType.TREASURE
		treasure_data.allows_segno = false
		treasure_data.max_connections = 1
		treasure_data.description  = "Something left behind."
		var inst := RoomInstance.new()
		inst.room_data = treasure_data
		inst.position  = all_empty[i]
		dungeon.grid[all_empty[i]] = inst
	map_ui.redraw_map()


## Open the Sundown Market shop for the current room.
## The shop can be re-entered; stock persists on the RoomInstance.
func _open_shop(room: RoomInstance) -> void:
	var scene := preload("res://Events/Scenes/shop_event.tscn")
	var event := scene.instantiate()
	event.run_state    = dungeon.run_state
	event.room_instance = room
	var event_layer = get_tree().get_first_node_in_group("event_layer")
	if event_layer == null:
		return
	var dungeon_layer = get_tree().get_first_node_in_group("dungeon_layer")
	if dungeon_layer: dungeon_layer.visible = false
	for c in event_layer.get_children(): c.queue_free()
	event_layer.add_child(event)
	event_layer.visible = true
	event.event_finished.connect(func():
		for c in event_layer.get_children(): c.queue_free()
		event_layer.visible = false
		if dungeon_layer: dungeon_layer.visible = true
		map_ui.redraw_map()
	, CONNECT_ONE_SHOT)


## Grant treasure rewards and permanently close the room.
func _open_treasure_room(room: RoomInstance) -> void:
	var run  := dungeon.run_state
	var dr   := dungeon
	# EXP burst — distributed equally among living party members, capped at ceiling.
	var burst_exp  : int = 20
	var ceiling    : int = dr.segno_level_ceiling if dr.segno_level_ceiling > 0 else LevelTable.MAX_LEVEL
	var exp_per_member  : Dictionary = {}
	var level_up_events : Dictionary = {}
	for m in run.party_members:
		if m.current_hp > 0:
			var events := m.add_exp_capped(burst_exp, ceiling)
			exp_per_member[m.character.display_name] = burst_exp
			if not events.is_empty():
				level_up_events[m.character.display_name] = events
	# Excess ammo top-up — refill up to half the gun clip worth of excess.
	var ammo_grant : int = max(1, run.gun_clip / 2)
	run.excess_ammo += ammo_grant
	# One reroll charge.
	run.reroll_charges += 1
	print("[Treasure] +%d EXP, +%d BB, +1 reprise." % [burst_exp, ammo_grant])
	# Show battle-results-style screen so the player sees any level-ups.
	_show_treasure_results(run.party_members, exp_per_member, level_up_events)


func _show_treasure_results(party: Array, exp_per_member: Dictionary, level_up_events: Dictionary) -> void:
	var results_scene := preload("res://UI/2D/Scenes/battle_results.tscn")
	var results := results_scene.instantiate() as Control
	var event_layer = get_tree().get_first_node_in_group("event_layer")
	if event_layer == null:
		on_room_completed()
		return
	var dungeon_layer = get_tree().get_first_node_in_group("dungeon_layer")
	if dungeon_layer: dungeon_layer.visible = false
	for c in event_layer.get_children(): c.queue_free()
	event_layer.add_child(results)  # add_child first so @onready vars resolve
	event_layer.visible = true
	results.setup(true, party, exp_per_member, level_up_events, [])
	results.results_dismissed.connect(func():
		for c in event_layer.get_children(): c.queue_free()
		event_layer.visible = false
		if dungeon_layer: dungeon_layer.visible = true
		on_room_completed()
	, CONNECT_ONE_SHOT)


## Show a UI notice that the dungeon must expand before the Segno can be moved.
## Displayed whenever _find_next_segno_candidates() returns empty.
func _show_segno_blocked_notice() -> void:
	var min_dist : int = SEGNO_MIN_DIST + dungeon.past_segno_positions.size()
	push_warning("[DC] Segno blocked: no candidates at min_dist=%d" % min_dist)
	# Show a brief on-screen notice via the segno event in blocked mode.
	var scene := preload("res://Events/Scenes/segno_event.tscn")
	var event := scene.instantiate()
	event.set("is_blocked_notice", true)
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
			map_ui.redraw_map()
		, CONNECT_ONE_SHOT)
	else:
		map_ui.redraw_map()


func place_segno(from_chapel: bool = false) -> void:
	var run := dungeon.run_state
	if not run.has_full_segno():
		if not from_chapel:
			on_room_completed()
		return
	_do_place_segno()


func _show_segno_event(from_chapel: bool, replacing: bool) -> void:
	var scene := preload("res://Events/Scenes/segno_event.tscn")
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
			if from_chapel:
				dungeon_ui.show_rest_screen()
			else:
				# Do NOT call on_room_completed — the active Segno room must
				# stay uncleared so the player can walk back to pick it up.
				map_ui.redraw_map()
		, CONNECT_ONE_SHOT)
	else:
		on_room_completed()


func on_party_defeated():
	match dungeon.phase:
		DungeonRunState.Phase.DAL_SEGNO:
			var snap := dungeon.segno_snapshot as SegnoSnapshot
			if snap != null and not snap.used:
				respawn_at_segno()
			else:
				end_run()
		_:
			end_run()


func _revert_entrance_to_start_room() -> void:
	_revert_room_at(Vector2i.ZERO)


## Revert a room back to a safe passable state after the Segno leaves it.
## Entrance gets the original start_room data.
## Other positions become a REST room with rested=true (just redraws map on re-entry).
func _revert_room_at(pos: Vector2i) -> void:
	var room : RoomInstance = dungeon.grid.get(pos)
	if room == null:
		return
	# All past Segno positions (including the entrance at origin) keep their
	# SEGNO room_data so the dimmed yellow model persists as a landmark.
	# Marking cleared prevents re-triggering the pickup interaction.
	room.cleared = true
	room.rested  = true


func respawn_at_segno() -> void:
	var snap := dungeon.segno_snapshot as SegnoSnapshot
	dungeon.coda_pos             = dungeon.current_pos
	snap.restore_into(dungeon.run_state)
	var placed_at : Vector2i     = snap.placed_at
	dungeon.current_pos          = placed_at
	dungeon.segno_snapshot       = null
	dungeon.past_segno_positions = snap.past_segno_positions.duplicate(true)

	# Restore the dungeon grid to its state at Segno placement time.
	if not snap.grid_snapshot.is_empty():
		dungeon.grid.clear()
		for gpos in snap.grid_snapshot.keys():
			var d : Dictionary = snap.grid_snapshot[gpos]
			var room := RoomInstance.new()
			room.room_data           = d["room_data"]
			room.position            = d["position"]
			room.visited             = d["visited"]
			room.cleared             = d["cleared"]
			room.rested              = d["rested"]
			room.inverted            = d["inverted"]
			room.built_connections   = d["built_connections"]
			room.al_segno_passes     = d["al_segno_passes"]
			room.transpose_picks     = d["transpose_picks"].duplicate()
			room.transpose_rolled    = d["transpose_rolled"]
			for c in d["explicit_connections"]:
				room.explicit_connections.append(c)
			dungeon.grid[gpos] = room
		_room_choice_cache.clear()

	_revert_room_at(placed_at)
	dungeon.segno_pos  = Vector2i(-999, -999)
	dungeon.phase      = DungeonRunState.Phase.GRAND_PAUSE
	_revert_entrance_to_start_room()
	# Restore layer visibility
	GameController.event_layer.visible   = false
	GameController.battle_layer.visible  = false
	GameController.dungeon_layer.visible = true
	GameController._set_dungeon_map_visible(true)
	map_ui.redraw_map()


func end_run():
	print("Run ended")
	MetaProgress.on_run_ended(false)
	SaveManager.delete_run_save()
	GameController.start_new_game()


# ── Room effect application ───────────────────────────────────────────────────

func apply_room_effects(room: RoomInstance) -> void:
	if room == null or room.room_data == null:
		return
	var run := dungeon.run_state
	for effect in room.room_data.room_effects:
		match effect.effect_type:

			RoomEffect.EffectType.AMMO_RESTORE_ON_PASS:
				if not room.cleared:
					continue
				if randf() < effect.ammo_chance:
					run.restore_ammo(effect.ammo_amount)
					print("[RoomEffect] Restored %d ammo." % effect.ammo_amount)
					if effect.risk_reactivate and randf() < effect.ammo_chance:
						room.cleared = false
						print("[RoomEffect] High Noon reactivated!")

			RoomEffect.EffectType.PARTY_HEAL_ON_ENTER:
				for pm in run.party_members:
					var max_hp : int = pm.character.base_max_hp + pm.bonus_max_hp
					var heal := effect.heal_amount if effect.heal_flat else int(max_hp * effect.heal_amount / 100.0)
					pm.set_hp(min(pm.current_hp + heal, max_hp))

			RoomEffect.EffectType.WILL_RESTORE_ON_ENTER:
				for pm in run.party_members:
					pm.restore_will(effect.will_amount)

			RoomEffect.EffectType.RESTRICT_BUILD_POOL:
				pass

			RoomEffect.EffectType.TEMPO_BONUS_ON_ENTER:
				run.run_flags["tempo_bonus_next_battle"] = effect.tempo_amount

			RoomEffect.EffectType.GRANT_REROLLS:
				run.reroll_charges += effect.grant_amount

			RoomEffect.EffectType.GRANT_ROAD_TILES:
				run.road_tiles_remaining += effect.grant_amount
