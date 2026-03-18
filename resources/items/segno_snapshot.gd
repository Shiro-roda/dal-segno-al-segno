extends Resource
class_name SegnoSnapshot
# A consumable save-point snapshot. Created when the player places a Segno item.
# Stores enough state to fully restore the run to the moment it was placed.
# Consumed (set to null) after one use.

# Position in the dungeon grid where the segno was placed.
var placed_at : Vector2i = Vector2i(-999, -999)

# Whether this snapshot has already been used (consumed on restore).
var used : bool = false

# --- Serialised DungeonRunState fields (phase context) ---
var phase                 : int       # DungeonRunState.Phase enum value at snapshot time
var segno_grid_pos        : Vector2i  # where the segno was placed in the grid
var past_segno_positions  : Array = [] # Array[Vector2i] history at snapshot time

# --- Serialised RunState fields ---
var ammo              : int
var gun_clip          : int   # stored separately so restore doesn't clobber via setter
var excess_ammo       : int
var segno_charges     : int
var run_flags         : Dictionary
var run_modifiers     : Array
var active_support    : CharacterData  # reference, not deep-copied

# Serialised party members. Each dict mirrors PartyMemberData fields.
var party_snapshots   : Array = []

# Serialised inventory (item_data references + stacks).
var inventory_snapshot : Array = []


static func capture(run_state: RunState, pos: Vector2i, dungeon_phase: int = 0, grid_segno_pos: Vector2i = Vector2i(-999,-999), past_positions: Array = []) -> SegnoSnapshot:
	var snap := SegnoSnapshot.new()
	snap.placed_at             = pos
	snap.phase                 = dungeon_phase
	snap.segno_grid_pos        = grid_segno_pos
	snap.past_segno_positions  = past_positions.duplicate(true)
	snap.ammo          = run_state.ammo
	snap.gun_clip      = run_state.gun_clip
	snap.excess_ammo   = run_state.excess_ammo
	snap.segno_charges = run_state.segno_charges
	snap.run_flags     = run_state.run_flags.duplicate(true)
	snap.run_modifiers = run_state.run_modifiers.duplicate(true)
	snap.active_support = run_state.active_support

	snap.party_snapshots.clear()
	for pm in run_state.party_members:
		snap.party_snapshots.append({
			"character":       pm.character,
			"current_hp":      pm.current_hp,
			"bonus_attack":       pm.bonus_attack,
			"bonus_max_hp":       pm.bonus_max_hp,
			"bonus_flat_defense": pm.bonus_flat_defense,
			"will":            pm.will,
			"max_will":        pm.max_will,
			"exp":             pm.exp,
			"level":           pm.level,
			"skill_unlocks":   pm.skill_unlocks.duplicate(),
			"status_effects":  pm.status_effects.duplicate(true),
		})

	snap.inventory_snapshot.clear()
	for item in run_state.inventory:
		snap.inventory_snapshot.append({
			"item_data":  item.item_data,
			"stacks":     item.stacks,
			"durability": item.durability,
		})

	return snap


func restore_into(run_state: RunState) -> void:
	run_state.ammo          = ammo
	run_state.gun_clip      = gun_clip
	run_state.excess_ammo   = excess_ammo
	run_state.segno_charges = segno_charges
	run_state.run_flags     = run_flags.duplicate(true)
	run_state.run_modifiers = run_modifiers.duplicate(true)
	run_state.active_support = active_support

	run_state.party_members.clear()
	for snap_pm in party_snapshots:
		var pm := PartyMemberData.new()
		pm.character      = snap_pm["character"]
		pm.current_hp     = snap_pm["current_hp"]
		pm.bonus_attack       = snap_pm["bonus_attack"]
		pm.bonus_max_hp       = snap_pm["bonus_max_hp"]
		pm.bonus_flat_defense = snap_pm.get("bonus_flat_defense", 0)
		pm.will           = snap_pm["will"]
		pm.max_will       = snap_pm["max_will"]
		pm.exp            = snap_pm["exp"]
		pm.level          = snap_pm["level"]
		pm.skill_unlocks  = snap_pm["skill_unlocks"].duplicate()
		pm.status_effects = snap_pm["status_effects"].duplicate(true)
		run_state.party_members.append(pm)

	run_state.inventory.clear()
	for snap_item in inventory_snapshot:
		var inst := ItemInstance.new()
		inst.item_data  = snap_item["item_data"]
		inst.stacks     = snap_item["stacks"]
		inst.durability = snap_item["durability"]
		run_state.inventory.append(inst)

	used = true
