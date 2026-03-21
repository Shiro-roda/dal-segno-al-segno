extends Resource
class_name RoomEffect
## Describes a single effect a room applies to the dungeon or the party.
## Set effect_type, then fill in only the fields relevant to that type.
## All fields have safe defaults so unused ones are harmless.

enum EffectType {
	RESTRICT_BUILD_POOL,   ## Limit which RoomTypes can appear as build options from this room.
	AMMO_RESTORE_ON_PASS,  ## Chance to restore ammo when walking through a cleared room.
	PARTY_HEAL_ON_ENTER,   ## Restore HP to all party members on entry.
	WILL_RESTORE_ON_ENTER, ## Restore will to all party members on entry.
	TEMPO_BONUS_ON_ENTER,  ## Grant a flat tempo bonus at the start of the next battle.
	GRANT_REROLLS,         ## Give the player N reprise charges on room entry.
	GRANT_ROAD_TILES,      ## Give the player N tie charges on room entry.
	TERMINAL,              ## Room accepts entry from any direction but has no outgoing exits.
						   ## No ghost slots appear from this room; no ties or rooms can attach.
}

@export var effect_type : EffectType = EffectType.RESTRICT_BUILD_POOL

## ── RESTRICT_BUILD_POOL ──────────────────────────────────────────────────────
## Tick the room types that are allowed to be built from this room.
## Unticked types are excluded from the random pool.
@export var allow_battle  : bool = true
@export var allow_elite   : bool = true
@export var allow_event   : bool = true
@export var allow_shop    : bool = true
@export var allow_rest    : bool = true
@export var allow_segno   : bool = true

## ── AMMO_RESTORE_ON_PASS ─────────────────────────────────────────────────────
## How much ammo to restore when the effect fires.
@export var ammo_amount   : int   = 0
## Probability (0–1) that the restore fires at all.
@export var ammo_chance   : float = 0.0
## If true, the same probability roll is used a second time to reactivate
## the room's encounter (e.g. High Noon).
@export var risk_reactivate : bool = false

## ── PARTY_HEAL_ON_ENTER ──────────────────────────────────────────────────────
## Amount of HP to restore. If heal_flat is true, this is a flat value;
## otherwise it is treated as a percentage of each member's max HP.
@export var heal_amount   : int  = 0
@export var heal_flat     : bool = true

## ── WILL_RESTORE_ON_ENTER ────────────────────────────────────────────────────
@export var will_amount   : int  = 0

## ── TEMPO_BONUS_ON_ENTER ─────────────────────────────────────────────────────
## Flat tempo added to all actors at the start of the next battle.
@export var tempo_amount  : float = 0.0

## Number of reprise or tie charges to grant (GRANT_REROLLS / GRANT_ROAD_TILES).
@export var grant_amount  : int = 1


## Helper used by DungeonController.get_room_choices().
## Returns an Array[int] of allowed RoomData.RoomType values for this effect.
func get_allowed_types() -> Array:
	var out : Array = []
	if allow_battle: out.append(RoomData.RoomType.BATTLE)
	if allow_elite:  out.append(RoomData.RoomType.ELITE)
	if allow_event:  out.append(RoomData.RoomType.EVENT)
	if allow_shop:   out.append(RoomData.RoomType.SHOP)
	if allow_rest:   out.append(RoomData.RoomType.REST)
	if allow_segno:  out.append(RoomData.RoomType.SEGNO)
	return out
