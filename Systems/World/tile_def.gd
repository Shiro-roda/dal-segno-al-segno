class_name TileDef
extends Resource
## One kind of tile the player can place on the grid, described entirely as data.

## VILLAGE tiles live on the Treble Clef (Town), DUNGEON tiles on the Bass Clef.
enum Category { VILLAGE, DUNGEON }
## The two overlapping grids. Each is its own 3D space.
enum Clef { TREBLE, BASS }

@export var id: StringName
@export var display_name := ""
@export var category: Category = Category.DUNGEON
## The dungeon's exit, on the Bass Clef. Placed for free at the origin; cannot be built
## or erased. Reaching it ends the expedition.
@export var is_exit := false
## The Town's origin tile, on the Treble Clef. The party starts each day here and plans
## from it. Placed for free at the origin; cannot be built or erased.
@export var is_origin := false
## The Segno room, on the Bass Clef. Placed for free in an empty cell next to a standing
## room (it is its own room, never put on top of one) and the party spawns in it. Can be
## moved or erased during planning. Never offered as a blueprint.
@export var is_segno := false
## Extra resource id -> amount spent to place this tile, on top of its colour cost
## (for example cuts). Leave empty if the colour is all it costs.
@export var cost: Dictionary = {}

@export_group("Village")
## Resource id -> amount produced at the start of every day while it stands.
@export var income: Dictionary = {}

@export_group("Dungeon")
## Remnants this tile gathers each day, chosen at random from `enemies`.
@export var enemies: Array[EnemyTemplate] = []
@export var spawn_count := 0
## Multiplies how many notes the enemies gathered here drop. Each enemy sets its own
## quantity (EnemyTemplate.notes_per_kill); this scales it for the room, and then the
## main-path bonus applies. 1.0 = as the enemy says, 0 = this room's enemies drop no
## notes. Dropped notes also raise this room's matching colour channel.
@export_range(0.0, 10.0, 0.05) var note_multiplier := 1.0
## Other resource id -> base amount carried out per remnant (for example cuts).
## Scaled by the main-path bonus; note_multiplier does not affect it.
@export var loot_per_kill: Dictionary = {}

@export_group("Blueprint")
## Dungeon tiles are placed from a blueprint drawn fresh each day. Relative draw
## chance: high = common, low = rare, 0 = never offered.
@export_range(0.0, 100.0, 0.1) var blueprint_weight := 1.0
## Not offered before this day of a run.
@export var blueprint_min_day := 1

@export_group("Color")
## The room's color, each channel 0-250 in steps of 10 (red, green, blue). Cost is
## color / 10 notes per channel, so (140, 240, 30) costs 14 red, 24 green, 3 blue.
## It also decides which enemies spawn here. Placed rooms keep their own copy.
@export var color := Vector3i.ZERO

@export_group("Presentation")
## The walkable chunk or visual for this tile. Optional until you build it.
@export var scene: PackedScene
@export_multiline var description := ""


## Which grid this tile belongs on. The exit is always Bass and the origin always
## Treble; everything else follows its category.
func clef() -> Clef:
	if is_exit:
		return Clef.BASS
	if is_origin:
		return Clef.TREBLE
	return Clef.TREBLE if category == Category.VILLAGE else Clef.BASS
