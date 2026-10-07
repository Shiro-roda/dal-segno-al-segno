class_name TileDef
extends Resource
## One kind of tile the player can place on the grid, described entirely as data.

enum Category { VILLAGE, DUNGEON }

@export var id: StringName
@export var display_name := ""
@export var category: Category = Category.DUNGEON
## The run's entrance and exit. Placed for free at the origin; cannot be built.
@export var is_exit := false
## Extra resource id -> amount spent to place this tile, on top of its colour cost
## (for example cuts). Leave empty if the colour is all it costs.
@export var cost: Dictionary = {}
## This room's colour, each channel 0-250: x = red, y = green, z = blue. It sets the
## note cost (140, 240, 30 costs 14 red, 24 green and 3 blue notes) and, for dungeon
## tiles, which enemies gather here: the lowest channel(s) are the most likely.
@export var color := Vector3i.ZERO

@export_group("Village")
## Resource id -> amount produced at the start of every day while it stands.
@export var income: Dictionary = {}

@export_group("Dungeon")
## Remnants this tile gathers each day, chosen at random from `enemies`.
@export var enemies: Array[EnemyTemplate] = []
@export var spawn_count := 0
## Notes of the enemy's own colour carried out per remnant laid to rest here, scaled
## up by distance from the exit. They also raise this room's matching colour channel.
@export var notes_per_kill := 0
## Other resource id -> base amount carried out per remnant (for example cuts).
## Scaled up by distance from the exit.
@export var loot_per_kill: Dictionary = {}

@export_group("Blueprint")
## Dungeon tiles are placed from a blueprint drawn fresh each day. Relative draw
## chance: high = common, low = rare, 0 = never offered.
@export_range(0.0, 100.0, 0.1) var blueprint_weight := 1.0
## Not offered before this day of a run.
@export var blueprint_min_day := 1

@export_group("Presentation")
## The walkable chunk or visual for this tile. Optional until you build it.
@export var scene: PackedScene
@export_multiline var description := ""
