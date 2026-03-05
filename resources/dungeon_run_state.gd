extends Resource
class_name DungeonRunState

var dungeon_data : DungeonData
var rooms : Array[RoomInstance] = []
var current_room_index : int = 0
var last_segno_index : int = -1
var run_state : RunState
