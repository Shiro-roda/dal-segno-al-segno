class_name RoomUpgrade
extends Resource
## One step up a building's upgrade tree: a building can be turned into `into`, a different
## building with its own TileDef (its own income, units, spawn count, health, scene...).
## A TileDef lists the steps it can take in TileDef.upgrades, so the tree is simply
## buildings pointing at the buildings they can become. Taking a step swaps the placed
## room's def for `into`; the room keeps its place, colour and (proportionally) its health.
## Each branch of the tree is a different path, and a room that has taken one can only
## continue along what that building offers. The tree must not loop back on itself.

## The step's id is the target building's id, so one def's steps must lead to different
## buildings.
var id: StringName:
	get: return into.id if into != null else &""

## The building this step turns the room into.
@export var into: TileDef
## Name shown for the step. Empty = the target building's own name.
@export var display_name := ""
@export_multiline var description := ""
## Resource id -> amount paid to take the step (like TileDef.cost).
@export var cost: Dictionary = {}
## Segments the step takes to finish once bought. While it is under way the room keeps
## working as the old building and cannot be upgraded again. 0 = instant.
@export_range(0, 20) var build_segments := 0


## What to call this step in the log and the panel.
func label() -> String:
	if display_name != "":
		return display_name
	if into != null and into.display_name != "":
		return into.display_name
	return String(id)
