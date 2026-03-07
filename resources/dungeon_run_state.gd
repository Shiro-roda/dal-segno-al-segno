extends Resource
class_name DungeonRunState

var dungeon_data : DungeonData
var run_state : RunState

var grid : Dictionary = {} # Vector2i -> RoomInstance

var current_pos : Vector2i = Vector2i.ZERO
var last_segno_pos : Vector2i = Vector2i(-999, -999)
