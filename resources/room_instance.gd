extends Resource
class_name RoomInstance

var room_data : RoomData
var position : Vector2i

var visited := false
var cleared := false
var rested := false  # REST rooms: consumed once the player actually rests
var rest_options : Array = []  # cached rest choices so they don't re-roll on re-entry
var inverted : bool = false   # true when the chapel has been "Inverted" during AL_SEGNO/fine

## Stores the resource types chosen during Transpose (DAL_SEGNO).
## Each entry is a String: "corpus", "anima", or "bb".
## Rolled into actual rest_options when the chapel is entered during AL_SEGNO/fine.
var transpose_picks : Array = []
## True once the AL_SEGNO/fine benefits have been rolled and are ready.
var transpose_rolled : bool = false

## How many corridors have been built into/out of this room so far.
var built_connections : int = 0

## Explicit list of grid positions this room is connected to.
## This is the authoritative source for navigation and corridor drawing.
var explicit_connections : Array = []  # Array[Vector2i]

## Number of times the player has entered this room during the current AL_SEGNO transit.
## Used to calculate rolling re-encounter chance on subsequent passes.
var al_segno_passes : int = 0

## True when this room cannot accept any more corridors.
func is_connection_full() -> bool:
	if room_data == null:
		return false
	return built_connections >= room_data.max_connections
