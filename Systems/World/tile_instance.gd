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


func _init(p_def: TileDef, p_pos: Vector2i, p_ruined := false) -> void:
	def = p_def
	pos = p_pos
	ruined = p_ruined
	if def != null:
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


func is_live() -> bool:
	return not ruined and not is_depleted()
