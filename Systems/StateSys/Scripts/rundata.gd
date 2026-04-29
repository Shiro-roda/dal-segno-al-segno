extends Resource
class_name RunState

signal battle_ammo_changed(new_ammo: int)

@export var party_members : Array[PartyMemberData] = []
@export var inventory : Array[ItemInstance] = []

# The one support currently active in the party.
# Set during the companion-select event at dungeon start.
var active_support : CharacterData = null

# Supports not yet recruited. Populated by gamecontrol before dungeon start.
# Each entry is a CharacterData resource.
var available_supports : Array = []

# The support who was NOT chosen and will appear as the boss after the recruit room.
# Picked randomly from available_supports when the recruit event completes.
var boss_target : CharacterData = null

# Set true once the boss battle has been triggered so it only fires once.
var boss_battle_triggered : bool = false

## The gun's native clip size. Shown in the time-signature bottom number.
## This never changes unless a gun upgrade specifically increases it.
var gun_clip : int = 6

## Current ammo loaded in the gun. Capped at gun_clip during battle.
var ammo : int = 6

## Excess ammo pool accumulated from Chapel Transpose upgrades.
## Used to refill the gun after battle during AL_SEGNO / AL_FINE
## (when the free post-battle reload does not apply).
var excess_ammo : int = 0

## Total ammo capacity (gun + excess). Kept for legacy API compatibility.
var max_ammo : int :
	get: return gun_clip + excess_ammo
	set(v): gun_clip = v  # legacy fallback; prefer gun_clip directly

# Semiosis / Segno charge system.
# The player performs Semiosis at rest rooms to accumulate charges (max 3).
# At 3 charges the Segno is "complete" and can be placed in a Segno room.
# Placing the Segno resets charges to 0.
const MAX_SEGNO_CHARGES : int = 3
var segno_charges : int = 0

func add_semiosis_charge() -> void:
	segno_charges = min(segno_charges + 1, MAX_SEGNO_CHARGES)

func has_full_segno() -> bool:
	return segno_charges >= MAX_SEGNO_CHARGES

func consume_segno() -> void:
	segno_charges = 0

## Reprise charges — spent to regenerate room choices at a ghost slot.
var reroll_charges : int = 0

## Ties remaining — free connector rooms placeable anywhere.
## Granted at dungeon start via start_dungeon(); items and rewards add more.
var road_tiles_remaining : int = 0

## Cuts — currency for purchasing consumable items at shops.
var money : int = 0

var run_flags : Dictionary = {}
var run_modifiers : Array = []

## All enemies encountered during this run, keyed by display_name.
## Values are CharacterData resources (preserved even after enemies die).
## Used by the Bestiary tab in the party menu.
var defeated_enemies : Dictionary = {}  # display_name -> CharacterData

## Kendall's equipped guns. Up to two slots: "gun_primary" and "gun_secondary".
## Values are GunData resources, or null if the slot is empty.
var gun_primary   : GunData = null
var gun_secondary : GunData = null

## Return whichever gun is currently active (primary first, then secondary).
## Returns null if no gun is equipped.
func get_active_gun() -> GunData:
	if gun_primary != null:
		return gun_primary
	return gun_secondary

## Equip a gun into the next available slot.
## Returns true if equipped, false if both slots are full.
func equip_gun(gun: GunData) -> bool:
	if gun_primary == null:
		gun_primary = gun
		_sync_clip_to_gun()
		return true
	if gun_secondary == null:
		gun_secondary = gun
		return true
	return false

## Swap primary ↔ secondary (cycles active gun).
func swap_guns() -> void:
	var tmp := gun_primary
	gun_primary   = gun_secondary
	gun_secondary = tmp
	_sync_clip_to_gun()

## Unequip from a slot by name ("gun_primary" | "gun_secondary").
func unequip_gun(slot: String) -> void:
	if slot == "gun_primary":
		gun_primary = null
	elif slot == "gun_secondary":
		gun_secondary = null
	_sync_clip_to_gun()

## Sync gun_clip to the active gun's clip_size, preserving relative ammo.
func _sync_clip_to_gun() -> void:
	var gun := get_active_gun()
	var new_clip : int = gun.clip_size if gun != null else 6
	if new_clip != gun_clip:
		var ratio : float = float(ammo) / float(max(gun_clip, 1))
		gun_clip = new_clip
		ammo = clamp(int(round(ratio * gun_clip)), 0, gun_clip)

func spend_ammo(amount: int) -> bool:
	if ammo < amount:
		return false
	ammo -= amount
	battle_ammo_changed.emit(ammo)
	return true

## Restore ammo into the gun (capped at gun_clip, no excess tap).
func restore_ammo(amount: int) -> void:
	ammo = min(ammo + amount, gun_clip)

## Reload the gun from the excess pool. Returns how many rounds were loaded.
func reload_from_excess() -> int:
	var needed : int = gun_clip - ammo
	var drawn  : int = min(needed, excess_ammo)
	ammo        += drawn
	excess_ammo -= drawn
	return drawn

## Add to the excess ammo pool (Chapel Transpose upgrade).
func increase_max_ammo(amount: int) -> void:
	excess_ammo += amount
