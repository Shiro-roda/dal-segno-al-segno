extends Resource
class_name RoomData

enum RoomType {
	BATTLE,
	ELITE,
	EVENT,
	SHOP,
	REST,
	SEGNO,
	BOSS,
	RECRUIT
}

@export var room_name : String
@export var room_type : RoomType

# Visuals
@export var icon : Texture2D
@export var description : String
## Optional 3D model scene (.tscn or .glb) displayed on the dungeon map for this room.
## Leave blank to use the default colour-coded cube placeholder.
@export var room_model : PackedScene

# Gameplay
@export var encounter : EncounterData
@export var event_scene : PackedScene

# Rewards / risk
#@export var reward_table : RewardTable
@export var danger_level : int = 1

# Dungeon interaction
@export var consumes_room : bool = true
@export var allows_segno : bool = true
## Maximum number of corridors this room will accept. 4 = all four cardinal directions.
## Once a room reaches this limit its remaining empty exit slots stop appearing as buildable.
@export var max_connections : int = 4

# Room effects applied on entry or passthrough.
@export var room_effects : Array[RoomEffect] = []

# Optional fixed rest options for this room (e.g. Chapel).
# If non-empty, these replace the random pool entirely.
# Each RestOption has a name, description, type, and optional fixed value.
@export var rest_options_override : Array[RestOption] = []

# Connection offsets: relative grid positions this room opens exits toward.
# Empty array (default)        = all four cardinal directions.
# [Vector2i(0,0)] (sentinel)   = no exits at all.
# Any other values             = exactly those exit directions.
@export var connections : Array[Vector2i] = []

func get_exit_dirs() -> Array:
	if connections.size() == 1 and connections[0] == Vector2i(0, 0):
		return []  # sentinel: no exits
	if connections.is_empty():
		return [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	return connections
