class_name RoomUpgrade
extends Resource
## One node of a room's upgrade tree. A TileDef lists the upgrades its rooms can take
## (TileDef.upgrades); the tree's shape comes from `requires` (prerequisites) and
## `excludes` (branches that lock each other out, so taking one closes the other for that
## room). Each placed room records the ids it took (TileInstance.upgrades), and
## HexDayCycle adds the modifiers below to the room's base stats. Upgrade ids must be
## unique within one TileDef.

## How an upgrade changes what its room's units do.
enum AllyBehaviorChange { KEEP, GUARD, PATROL }

@export var id: StringName = &""
@export var display_name := ""
@export_multiline var description := ""
## Resource id -> amount paid when the upgrade is taken (like TileDef.cost).
@export var cost: Dictionary = {}
## Segments the upgrade takes to finish once bought. While it is under way the room keeps
## working with its old stats and cannot take another upgrade. 0 = instant.
@export_range(0, 20) var build_segments := 0

@export_group("Tree")
## Upgrade ids the room must already have. All of them are needed.
@export var requires: Array[StringName] = []
## Upgrade ids this one is exclusive with. The lockout works both ways: it is enough for
## either of the two upgrades to list the other.
@export var excludes: Array[StringName] = []

@export_group("Stats")
## Added to the room's spawn count. Raising it also raises the room's size tier.
@export var spawn_count_add := 0
## Added to the safe zone's reach, in road steps, on top of the size tier's radius.
@export var cover_radius_add := 0
## Added to the number of enemies the room can hold, on top of the size tier's capacity.
@export var capacity_add := 0
## Added to the structure's health (a negative value is allowed; health never drops below 1).
@export var max_health_add := 0

@export_group("Defence")
## Replaces the unit the room musters. The latest upgrade taken that sets one wins. Null =
## keep whatever the room already musters.
@export var ally: AllyTemplate
@export var ally_cap_add := 0
@export var ally_per_segment_add := 0
## Change what the room's units do. The latest upgrade taken that changes it wins.
@export var ally_behavior: AllyBehaviorChange = AllyBehaviorChange.KEEP
@export var ally_patrol_range_add := 0
