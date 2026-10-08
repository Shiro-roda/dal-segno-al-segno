class_name RoomDoor
extends Area3D
## A doorway between two dungeon rooms. Put one in the gap of each wall you want to be
## able to open, and set `side` to the wall it is in (NORTH is -Z).
##
## When the room loads, DungeonRoom checks the grid: a door with a standing room behind
## it stays open, any other is sealed. Walking into an open door carries the party to
## that room, where they appear at the matching door on the opposite side.
##
## Optional children:
##   Seal     a Node3D (usually a StaticBody3D wall) shown, and made solid, only while
##            the door is sealed. Without one, a sealed door is just inert.
##   Arrival  a Marker3D marking where the party stands after coming in through this
##            door. Without one they appear `arrival_distance` metres towards the
##            room's origin, so centre the room on its origin or add the marker.

@export var side: DayCycle.Side = DayCycle.Side.NORTH
## If the node has no CollisionShape3D child, a box of this size is added.
@export var auto_shape_size := Vector3(3.5, 3.0, 2.0)
@export var arrival_distance := 3.0

## Set by DungeonRoom. Doors refuse to open mid-fight.
var room: DungeonRoom
var sealed := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 1  # the player body is on layer 2
	add_to_group("room_door")
	body_entered.connect(_on_body_entered)
	if find_children("*", "CollisionShape3D", false, false).is_empty():
		var box := BoxShape3D.new()
		box.size = auto_shape_size
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position.y = auto_shape_size.y * 0.5
		add_child(shape)


func set_sealed(on: bool) -> void:
	sealed = on
	set_deferred("monitoring", not on)
	var seal := get_node_or_null("Seal") as Node3D
	if seal == null and on:
		seal = _make_default_seal()  # the scene didn't author one: still close the gap
	if seal != null:
		_toggle(seal, on)


## A plain wall plugging the doorway, for rooms whose doors have no Seal of their own.
func _make_default_seal() -> Node3D:
	var wall := CSGBox3D.new()
	wall.name = "Seal"
	wall.size = Vector3(maxf(auto_shape_size.x + 0.5, 1.0), 4.0, 1.0)
	wall.position.y = 2.0
	wall.use_collision = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.14)
	wall.material = mat
	add_child(wall)
	return wall


## Where the party stands after arriving through this door, in world space.
func arrival_point() -> Vector3:
	var marker := get_node_or_null("Arrival") as Node3D
	if marker != null:
		return marker.global_position
	var origin := room.global_position if room != null else Vector3.ZERO
	var inward := origin - global_position
	inward.y = 0.0
	if inward.length_squared() < 0.01:
		inward = -global_basis.z
	var spot := global_position + inward.normalized() * arrival_distance
	spot.y = origin.y + 0.1
	return spot


func _on_body_entered(body: Node3D) -> void:
	if sealed or not body.is_in_group("party_leader"):
		return
	if room != null and not room.can_leave():
		return
	GameController.go_through_door(side)


## Shows or hides a node and, for anything solid inside it, turns collision on or off.
func _toggle(node: Node3D, on: bool) -> void:
	node.visible = on
	var solids := node.find_children("*", "CollisionObject3D", true, false)
	if node is CollisionObject3D:
		solids.append(node)
	for solid: CollisionObject3D in solids:
		if not solid.has_meta(&"door_layer"):
			solid.set_meta(&"door_layer", solid.collision_layer)
		solid.collision_layer = int(solid.get_meta(&"door_layer")) if on else 0
	# CSG walls make their own collision body, so switch that on and off too.
	var csgs := node.find_children("*", "CSGShape3D", true, false)
	if node is CSGShape3D:
		csgs.append(node)
	for csg: CSGShape3D in csgs:
		csg.use_collision = on
