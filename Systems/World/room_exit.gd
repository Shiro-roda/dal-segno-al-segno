class_name RoomExit
extends Area3D
## Walk into this volume to leave the dungeon: the day's loot is banked and the party
## wakes in the Town. DungeonRoom adds one automatically to the exit tile's room, so you
## only place one by hand to choose where in the room it sits (or what it looks like).

## If the node has no CollisionShape3D child, a box of this size is added.
@export var auto_shape_size := Vector3(6.0, 3.0, 6.0)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 1  # the player body is on layer 2
	add_to_group("room_exit")
	body_entered.connect(_on_body_entered)
	if find_children("*", "CollisionShape3D", false, false).is_empty():
		var box := BoxShape3D.new()
		box.size = auto_shape_size
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position.y = auto_shape_size.y * 0.5
		add_child(shape)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("party_leader"):
		return
	var room := _find_room()
	if room != null and not room.can_leave():
		return  # no leaving mid-fight
	GameController.return_to_town()


func _find_room() -> DungeonRoom:
	var node := get_parent()
	while node != null:
		if node is DungeonRoom:
			return node
		node = node.get_parent()
	return null
