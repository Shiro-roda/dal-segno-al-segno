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

## Reroll charges — spent to regenerate room choices at a ghost slot.
var reroll_charges : int = 0

## Road tiles remaining — free connector rooms placeable anywhere.
## Granted at dungeon start via start_dungeon(); items and rewards add more.
var road_tiles_remaining : int = 0

## Currency for purchasing consumable items (Meat = Corpus, Candy = AP).
var money : int = 0

var run_flags : Dictionary = {}
var run_modifiers : Array = []

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
