extends Resource
class_name RoomInstance

var room_data : RoomData
var position : Vector2i

var visited := false
var cleared := false
var rested := false  # REST rooms: consumed once the player actually rests
var rest_options : Array = []  # cached rest choices so they don't re-roll on re-entry
