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

# Gameplay
@export var encounter : EncounterData
@export var event_scene : PackedScene

# Rewards / risk
#@export var reward_table : RewardTable
@export var danger_level : int = 1

# Dungeon interaction
@export var consumes_room : bool = true
@export var allows_segno : bool = true

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
