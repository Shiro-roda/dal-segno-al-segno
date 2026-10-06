class_name Interactable
extends Area3D
## Anything the player can interact with (NPCs, doors, objects).
## Lives on physics layer 3 so the player's interact area can see it.
## Set `dialogic_timeline` to start a Dialogic timeline, or connect to
## `interacted` for custom behaviour.

signal interacted(who: Node3D)

@export var prompt := "Interact"
## Timeline name or res:// path passed to Dialogic.start(). Empty = none.
@export var dialogic_timeline := ""
@export var one_shot := false
## If the node has no CollisionShape3D child, a sphere of this radius is added.
@export var auto_shape_radius := 1.0

var _used := false


func _ready() -> void:
	collision_layer = 1 << 2
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group("interactable")
	if find_children("*", "CollisionShape3D", false, false).is_empty():
		var sphere := SphereShape3D.new()
		sphere.radius = auto_shape_radius
		var shape := CollisionShape3D.new()
		shape.shape = sphere
		shape.position.y = 1.0
		add_child(shape)


func interact(who: Node3D) -> void:
	if one_shot and _used:
		return
	_used = true
	interacted.emit(who)
	if dialogic_timeline != "":
		var dialogic := get_node_or_null("/root/Dialogic")
		if dialogic != null and dialogic.has_method("start"):
			dialogic.call("start", dialogic_timeline)
		else:
			push_warning("Interactable '%s': Dialogic is not available." % name)
