class_name TileDef
extends Resource
## One kind of tile the player can place on the grid, described entirely as data.

## VILLAGE tiles live on the Treble Clef (Town), DUNGEON tiles on the Bass Clef.
enum Category { VILLAGE, DUNGEON }
## The two overlapping grids. Each is its own 3D space.
enum Clef { TREBLE, BASS }

enum Role { NORMAL, EXIT, ORIGIN, SEGNO }

@export var id: StringName
@export var display_name := ""
@export var category: Category = Category.DUNGEON

@export var role: Role = Role.NORMAL


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

@export_group("Features")
## Dungeon tile: a short rest room (Anima back, hit dice spent for Corpus).
@export var rest: RestDef
## Dungeon tile: a trap that goes off when the party walks in and earns bonus blueprints.
@export var hazard: HazardDef
## Village tile: sells items, restocked every dawn. Paid for from the run's stock.
@export var shop: ShopDef

@export_group("Blueprint")
## Dungeon tiles are placed from a blueprint drawn fresh each day. Relative draw
## chance: high = common, low = rare, 0 = never offered.
@export_range(0.0, 100.0, 0.1) var blueprint_weight := 1.0
## Not offered before this day of a run.
@export var blueprint_min_day := 1
## Ids of the dungeon tiles this blueprint can come from. It is only drawn while at
## least one of them is standing in the dungeon. Empty = can be drawn anywhere. Ids,
## not TileDef references, so two tiles can name each other without a circular load.
@export var blueprint_source_ids: Array[StringName] = []

@export_group("Unlock")
## Ids of Treble Clef (Town) tiles that must each be standing for this tile (Bass or
## Treble) to be built or drawn as a blueprint. Temporary: a run starts with the Town in
## ruins, so these have to be rebuilt each run, which keeps the early draw pool small. A
## ruined or erased requirement locks the tile again. Rooms already built stay standing.
## Empty = available from the start. Ids, not references, to avoid cycles.
@export var unlock_requires_ids: Array[StringName] = []

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

## Role shortcuts. Kept as properties so `def.is_exit` and `def.is_exit = true` both work.
## Do not turn these into methods: callers use them without parentheses, and a method
## reference is always truthy.
var is_exit: bool:
	get: return role == Role.EXIT
	set(value): _set_role(Role.EXIT, value)

var is_origin: bool:
	get: return role == Role.ORIGIN
	set(value): _set_role(Role.ORIGIN, value)

var is_segno: bool:
	get: return role == Role.SEGNO
	set(value): _set_role(Role.SEGNO, value)


func _set_role(which: Role, on: bool) -> void:
	if on:
		role = which
	elif role == which:
		role = Role.NORMAL
