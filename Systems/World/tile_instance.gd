class_name TileInstance
extends RefCounted
## A tile standing (or lying in ruins) at a grid position.

var def: TileDef
var pos: Vector2i
## Ruined tiles remain visible after a defeat but do nothing until rebuilt.
var ruined := false
## This room's color, each channel 0-250 (140 = 14 notes of that color). Starts as
## the def's color; encounters here raise it. Cost and enemy affinity read from it.
var color := Vector3i.ZERO

const MAX_COLOR := 250

## Segments of construction left. While above 0 this is a building site: it holds its vertex
## and anchors roads, but is not live, so it earns nothing, gathers no enemies and unlocks
## nothing until it is finished. Only HexDayCycle counts it down.
var build_left := 0

## The upgrade being built right now (&"" = none) and the segments it still needs. The
## room works with its old stats until it finishes. Only HexDayCycle counts it down.
var upgrading: StringName = &""
var upgrade_left := 0

## Damage left before raiders bring this structure down. Starts at the def's max_health.
var health := 1

## Ids of the buildings this structure used to be, oldest first, one per upgrade step it has
## taken (so the length is the number of upgrades). Lost with the structure: a ruin starts
## again from whatever it was when it fell, but its history is gone.
var lineage: Array[StringName] = []


## True if this structure is, or ever was, the building with `id`. Unlocks and blueprint
## sources count a building's earlier forms, so a Den upgraded into a Warren still counts
## as a Den.
func is_or_was(id: StringName) -> bool:
	return (def != null and def.id == id) or lineage.has(id)


## Turns this structure into `new_def` (an upgrade step finished). Position and colour stay;
## health moves by the difference between the two buildings' maximums, never below 1 and
## never above the new maximum.
func become(new_def: TileDef) -> void:
	if new_def == null or new_def == def:
		return
	var old_max := def.max_health if def != null else 1
	if def != null:
		lineage.append(def.id)
	def = new_def
	health = clampi(health + new_def.max_health - old_max, 1, maxi(1, new_def.max_health))


func _init(p_def: TileDef, p_pos: Vector2i, p_ruined := false) -> void:
	def = p_def
	pos = p_pos
	ruined = p_ruined
	if def != null:
		health = def.max_health
		color = Vector3i(
				clampi(def.color.x, 0, MAX_COLOR),
				clampi(def.color.y, 0, MAX_COLOR),
				clampi(def.color.z, 0, MAX_COLOR))


## Channel indices (0 red, 1 green, 2 blue) holding the lowest value. Ties all count.
func lowest_channels() -> Array[int]:
	var lowest := mini(color.x, mini(color.y, color.z))
	var out: Array[int] = []
	for i in 3:
		if color[i] == lowest:
			out.append(i)
	return out


## Raises one channel by `amount` colour points, up to the maximum.
func raise_color(channel: int, amount: int) -> void:
	if channel >= 0 and channel < 3:
		color[channel] = mini(MAX_COLOR, color[channel] + amount)


## Every channel at the maximum: the room is spent and must be erased.
func is_depleted() -> bool:
	return color.x >= MAX_COLOR and color.y >= MAX_COLOR and color.z >= MAX_COLOR


## True once construction is finished (always true for tiles with no build time).
func is_built() -> bool:
	return build_left <= 0


func is_live() -> bool:
	return not ruined and not is_depleted() and is_built()
