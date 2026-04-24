extends Node
## SaveManager — autoload singleton (add as "SaveManager" in Project > AutoLoad).
##
## Responsibilities:
##   • Serialize / deserialize a mid-run RunState + DungeonRunState to disk.
##   • Autosave after every room completion (called by DungeonController).
##   • Expose save / load / delete API to GameControl and the start screen.
##
## Save file layout  (user://saves/):
##   run_save.json        — active mid-run snapshot (deleted on run end)
##   meta_progress.json   — persistent cross-run data (owned by MetaProgress)

const RUN_SAVE_PATH  := "user://saves/run_save.json"
const SAVES_DIR      := "user://saves/"

signal run_save_created
signal run_save_deleted

# ──────────────────────────────────────────────────────────────────────────────
# Lifecycle
# ──────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_ensure_save_dir()


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_recursive_absolute(SAVES_DIR)


# ──────────────────────────────────────────────────────────────────────────────
# Public API
# ──────────────────────────────────────────────────────────────────────────────

## Returns true if a mid-run save file exists.
func has_run_save() -> bool:
	return FileAccess.file_exists(RUN_SAVE_PATH)


## Serialize and write the current run to disk.
## Called automatically by DungeonController on room completion,
## and manually from any pause/quit flow.
func save_run(run: RunState, dungeon: DungeonRunState) -> void:
	var data := _serialize_run(run, dungeon)
	var json_str := JSON.stringify(data, "\t")
	var file := FileAccess.open(RUN_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] Could not open run save for writing: %s" % RUN_SAVE_PATH)
		return
	file.store_string(json_str)
	file.close()
	run_save_created.emit()


## Load the saved run. Returns a Dictionary with keys "run" (RunState)
## and "dungeon" (DungeonRunState), or an empty Dictionary on failure.
func load_run() -> Dictionary:
	if not has_run_save():
		return {}
	var file := FileAccess.open(RUN_SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] Could not open run save for reading.")
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("[SaveManager] Run save JSON is malformed.")
		return {}

	var result := _deserialize_run(parsed)
	return result


## Delete the mid-run save (call on run completion, game-over, or new game).
func delete_run_save() -> void:
	if FileAccess.file_exists(RUN_SAVE_PATH):
		DirAccess.remove_absolute(RUN_SAVE_PATH)
	run_save_deleted.emit()


# ──────────────────────────────────────────────────────────────────────────────
# Serialization helpers
# ──────────────────────────────────────────────────────────────────────────────

func _serialize_run(run: RunState, dungeon: DungeonRunState) -> Dictionary:
	return {
		"version": 1,
		"run":    _serialize_run_state(run),
		"dungeon": _serialize_dungeon_state(dungeon),
	}


func _serialize_run_state(run: RunState) -> Dictionary:
	var party := []
	for pm in run.party_members:
		party.append(_serialize_party_member(pm))

	var inventory := []
	for item in run.inventory:
		inventory.append({
			"item_data_path": item.item_data.resource_path if item.item_data else "",
			"stacks":         item.stacks,
			"durability":     item.durability,
		})

	return {
		"gun_clip":            run.gun_clip,
		"ammo":                run.ammo,
		"excess_ammo":         run.excess_ammo,
		"segno_charges":       run.segno_charges,
		"reroll_charges":      run.reroll_charges,
		"road_tiles_remaining": run.road_tiles_remaining,
		"money":               run.money,
		"run_flags":           run.run_flags.duplicate(),
		"run_modifiers":       run.run_modifiers.duplicate(),
		"active_support_path": run.active_support.resource_path if run.active_support else "",
		"available_supports":  _serialize_char_array(run.available_supports),
		"boss_target_path":    run.boss_target.resource_path if run.boss_target else "",
		"boss_battle_triggered": run.boss_battle_triggered,
		"party":               party,
		"inventory":           inventory,
	}


func _serialize_party_member(pm: PartyMemberData) -> Dictionary:
	return {
		"character_path":    pm.character.resource_path if pm.character else "",
		"current_hp":        pm.current_hp,
		"bonus_attack":      pm.bonus_attack,
		"bonus_max_hp":      pm.bonus_max_hp,
		"bonus_flat_defense": pm.bonus_flat_defense,
		"will":              pm.will,
		"max_will":          pm.max_will,
		"exp":               pm.exp,
		"level":             pm.level,
		"skill_unlocks":     pm.skill_unlocks.duplicate(),
	}


func _serialize_char_array(arr: Array) -> Array:
	var out := []
	for c in arr:
		if c and c is Resource and c.resource_path != "":
			out.append(c.resource_path)
	return out


func _serialize_dungeon_state(dungeon: DungeonRunState) -> Dictionary:
	var grid_data := []
	for pos in dungeon.grid.keys():
		var room : RoomInstance = dungeon.grid[pos]
		var conn_arr := []
		for c in room.explicit_connections:
			conn_arr.append(_vec2i_to_arr(c))
		grid_data.append({
			"pos": _vec2i_to_arr(pos),
			"room_data_path":       room.room_data.resource_path if room.room_data else "",
			"visited":              room.visited,
			"cleared":              room.cleared,
			"rested":               room.rested,
			"inverted":             room.inverted,
			"built_connections":    room.built_connections,
			"explicit_connections": conn_arr,
			"al_segno_passes":      room.al_segno_passes,
			"transpose_picks":      room.transpose_picks.duplicate(),
			"transpose_rolled":     room.transpose_rolled,
		})

	var snap_data = null
	if dungeon.segno_snapshot != null:
		snap_data = _serialize_segno_snapshot(dungeon.segno_snapshot)

	return {
		"dungeon_data_path":   dungeon.dungeon_data.resource_path if dungeon.dungeon_data else "",
		"phase":               dungeon.phase,
		"current_pos":         _vec2i_to_arr(dungeon.current_pos),
		"segno_pos":           _vec2i_to_arr(dungeon.segno_pos),
		"coda_pos":            _vec2i_to_arr(dungeon.coda_pos),
		"next_segno_target":   _vec2i_to_arr(dungeon.next_segno_target),
		"past_segno_positions": dungeon.past_segno_positions.map(func(v): return _vec2i_to_arr(v)),
		"segno_level_ceiling": dungeon.segno_level_ceiling,
		"segno_transit_count": dungeon.segno_transit_count,
		"segno_min_dist":      dungeon.segno_min_dist,
		"grid":                grid_data,
		"segno_snapshot":      snap_data,
	}


func _serialize_segno_snapshot(snap: SegnoSnapshot) -> Dictionary:
	var party_snaps := []
	for ps in snap.party_snapshots:
		party_snaps.append({
			"character_path":    ps["character"].resource_path if ps["character"] else "",
			"current_hp":        ps["current_hp"],
			"bonus_attack":      ps["bonus_attack"],
			"bonus_max_hp":      ps["bonus_max_hp"],
			"bonus_flat_defense": ps.get("bonus_flat_defense", 0),
			"will":              ps["will"],
			"max_will":          ps["max_will"],
			"exp":               ps["exp"],
			"level":             ps["level"],
			"skill_unlocks":     ps["skill_unlocks"].duplicate(),
			"status_effects":    [],
		})
	var inv_snaps := []
	for it in snap.inventory_snapshot:
		inv_snaps.append({
			"item_data_path": it["item_data"].resource_path if it["item_data"] else "",
			"stacks":         it["stacks"],
			"durability":     it["durability"],
		})
	return {
		"placed_at":           _vec2i_to_arr(snap.placed_at),
		"used":                snap.used,
		"phase":               snap.phase,
		"segno_grid_pos":      _vec2i_to_arr(snap.segno_grid_pos),
		"past_segno_positions": snap.past_segno_positions.map(func(v): return _vec2i_to_arr(v)),
		"ammo":                snap.ammo,
		"gun_clip":            snap.gun_clip,
		"excess_ammo":         snap.excess_ammo,
		"segno_charges":       snap.segno_charges,
		"money":               snap.money,
		"reroll_charges":      snap.reroll_charges,
		"road_tiles":          snap.road_tiles,
		"run_flags":           snap.run_flags.duplicate(),
		"run_modifiers":       snap.run_modifiers.duplicate(),
		"active_support_path": snap.active_support.resource_path if snap.active_support else "",
		"party_snapshots":     party_snaps,
		"inventory_snapshot":  inv_snaps,
	}


# ──────────────────────────────────────────────────────────────────────────────
# Deserialization helpers
# ──────────────────────────────────────────────────────────────────────────────

func _deserialize_run(data: Dictionary) -> Dictionary:
	var run_data  : Dictionary = data.get("run",    {})
	var dung_data : Dictionary = data.get("dungeon", {})

	var run    := _deserialize_run_state(run_data)
	var dungeon := _deserialize_dungeon_state(dung_data, run)

	return {"run": run, "dungeon": dungeon}


func _deserialize_run_state(d: Dictionary) -> RunState:
	var run := RunState.new()
	run.gun_clip             = d.get("gun_clip",   6)
	run.ammo                 = d.get("ammo",       6)
	run.excess_ammo          = d.get("excess_ammo", 0)
	run.segno_charges        = d.get("segno_charges", 0)
	run.reroll_charges       = d.get("reroll_charges", 0)
	run.road_tiles_remaining = d.get("road_tiles_remaining", 0)
	run.money                = d.get("money", 0)
	run.run_flags            = d.get("run_flags", {}).duplicate()
	run.run_modifiers        = d.get("run_modifiers", []).duplicate()
	run.boss_battle_triggered = d.get("boss_battle_triggered", false)

	var as_path : String = d.get("active_support_path", "")
	if as_path != "" and ResourceLoader.exists(as_path):
		run.active_support = load(as_path)

	var bt_path : String = d.get("boss_target_path", "")
	if bt_path != "" and ResourceLoader.exists(bt_path):
		run.boss_target = load(bt_path)

	for path in d.get("available_supports", []):
		if ResourceLoader.exists(path):
			run.available_supports.append(load(path))

	for pm_d in d.get("party", []):
		var pm := _deserialize_party_member(pm_d)
		if pm:
			run.party_members.append(pm)

	for item_d in d.get("inventory", []):
		var path : String = item_d.get("item_data_path", "")
		if path != "" and ResourceLoader.exists(path):
			var inst := ItemInstance.new()
			inst.item_data  = load(path)
			inst.stacks     = item_d.get("stacks", 1)
			inst.durability = item_d.get("durability", -1)
			run.inventory.append(inst)

	return run


func _deserialize_party_member(d: Dictionary) -> PartyMemberData:
	var path : String = d.get("character_path", "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	var pm := PartyMemberData.new()
	pm.character        = load(path)
	pm.current_hp       = d.get("current_hp",   pm.character.base_max_hp)
	pm.bonus_attack     = d.get("bonus_attack",  0)
	pm.bonus_max_hp     = d.get("bonus_max_hp",  0)
	pm.bonus_flat_defense = d.get("bonus_flat_defense", 0)
	pm.will             = d.get("will",           0)
	pm.max_will         = d.get("max_will",       pm.character.base_max_will)
	pm.exp              = d.get("exp",            0)
	pm.level            = d.get("level",          1)
	pm.skill_unlocks    = Array(d.get("skill_unlocks", []))
	return pm


func _deserialize_dungeon_state(d: Dictionary, run: RunState) -> DungeonRunState:
	var dungeon := DungeonRunState.new()
	dungeon.run_state = run

	var dpath : String = d.get("dungeon_data_path", "")
	if dpath != "" and ResourceLoader.exists(dpath):
		dungeon.dungeon_data = load(dpath)

	dungeon.phase               = d.get("phase", 0)
	dungeon.current_pos         = _arr_to_vec2i(d.get("current_pos", [0, 0]))
	dungeon.segno_pos           = _arr_to_vec2i(d.get("segno_pos", [-999, -999]))
	dungeon.coda_pos            = _arr_to_vec2i(d.get("coda_pos", [-999, -999]))
	dungeon.next_segno_target   = _arr_to_vec2i(d.get("next_segno_target", [-999, -999]))
	dungeon.segno_level_ceiling = d.get("segno_level_ceiling", 3)
	dungeon.segno_transit_count = d.get("segno_transit_count", 0)
	dungeon.segno_min_dist      = d.get("segno_min_dist", 4)

	for pos_arr in d.get("past_segno_positions", []):
		dungeon.past_segno_positions.append(_arr_to_vec2i(pos_arr))

	for room_d in d.get("grid", []):
		var pos := _arr_to_vec2i(room_d.get("pos", [0, 0]))
		var rpath : String = room_d.get("room_data_path", "")
		var room := RoomInstance.new()
		if rpath != "" and ResourceLoader.exists(rpath):
			room.room_data = load(rpath)
		room.position          = pos
		room.visited           = room_d.get("visited",           false)
		room.cleared           = room_d.get("cleared",           false)
		room.rested            = room_d.get("rested",            false)
		room.inverted          = room_d.get("inverted",          false)
		room.built_connections = room_d.get("built_connections", 0)
		room.al_segno_passes   = room_d.get("al_segno_passes",   0)
		room.transpose_picks   = Array(room_d.get("transpose_picks", []))
		room.transpose_rolled  = room_d.get("transpose_rolled",  false)
		for c_arr in room_d.get("explicit_connections", []):
			room.explicit_connections.append(_arr_to_vec2i(c_arr))
		dungeon.grid[pos] = room

	var snap_d = d.get("segno_snapshot", null)
	if snap_d is Dictionary:
		dungeon.segno_snapshot = _deserialize_segno_snapshot(snap_d, run)

	return dungeon


func _deserialize_segno_snapshot(d: Dictionary, run: RunState) -> SegnoSnapshot:
	var snap := SegnoSnapshot.new()
	snap.placed_at      = _arr_to_vec2i(d.get("placed_at", [-999, -999]))
	snap.used           = d.get("used", false)
	snap.phase          = d.get("phase", 0)
	snap.segno_grid_pos = _arr_to_vec2i(d.get("segno_grid_pos", [-999, -999]))
	for pa in d.get("past_segno_positions", []):
		snap.past_segno_positions.append(_arr_to_vec2i(pa))
	snap.ammo           = d.get("ammo",    6)
	snap.gun_clip       = d.get("gun_clip", 6)
	snap.excess_ammo    = d.get("excess_ammo", 0)
	snap.segno_charges  = d.get("segno_charges", 0)
	snap.money          = d.get("money", 0)
	snap.reroll_charges = d.get("reroll_charges", 0)
	snap.road_tiles     = d.get("road_tiles", 0)
	snap.run_flags      = d.get("run_flags", {}).duplicate()
	snap.run_modifiers  = d.get("run_modifiers", []).duplicate()

	var as_path : String = d.get("active_support_path", "")
	if as_path != "" and ResourceLoader.exists(as_path):
		snap.active_support = load(as_path)

	for ps_d in d.get("party_snapshots", []):
		var cpath : String = ps_d.get("character_path", "")
		if cpath == "" or not ResourceLoader.exists(cpath):
			continue
		snap.party_snapshots.append({
			"character":          load(cpath),
			"current_hp":         ps_d.get("current_hp", 1),
			"bonus_attack":       ps_d.get("bonus_attack", 0),
			"bonus_max_hp":       ps_d.get("bonus_max_hp", 0),
			"bonus_flat_defense": ps_d.get("bonus_flat_defense", 0),
			"will":               ps_d.get("will", 0),
			"max_will":           ps_d.get("max_will", 0),
			"exp":                ps_d.get("exp", 0),
			"level":              ps_d.get("level", 1),
			"skill_unlocks":      Array(ps_d.get("skill_unlocks", [])),
			"status_effects":     [],
		})

	for it_d in d.get("inventory_snapshot", []):
		var ipath : String = it_d.get("item_data_path", "")
		if ipath == "" or not ResourceLoader.exists(ipath):
			continue
		snap.inventory_snapshot.append({
			"item_data":  load(ipath),
			"stacks":     it_d.get("stacks", 1),
			"durability": it_d.get("durability", -1),
		})

	return snap


# ──────────────────────────────────────────────────────────────────────────────
# Vector2i helpers
# ──────────────────────────────────────────────────────────────────────────────

func _vec2i_to_arr(v: Vector2i) -> Array:
	return [v.x, v.y]


func _arr_to_vec2i(a) -> Vector2i:
	if a is Array and a.size() >= 2:
		return Vector2i(int(a[0]), int(a[1]))
	return Vector2i.ZERO
