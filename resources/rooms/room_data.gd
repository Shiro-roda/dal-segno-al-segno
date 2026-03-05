extends Resource
class_name RoomData

enum RoomType {
	BATTLE,
	ELITE,
	EVENT,
	SHOP,
	REST,
	SEGNO,
	BOSS
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
