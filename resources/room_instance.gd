extends Resource
class_name RoomInstance

var room_data : RoomData
var position : Vector2i

var visited := false
var cleared := false
var rested := false  # REST rooms: consumed once the player actually rests
var rest_options : Array = []  # cached rest choices so they don't re-roll on re-entry

## How many corridors have been built into/out of this room so far.
## Incremented on both sides when build_room() fires.
var built_connections : int = 0

## True when this room cannot accept any more corridors.
func is_connection_full() -> bool:
	if room_data == null:
		return false
	return built_connections >= room_data.max_connections
