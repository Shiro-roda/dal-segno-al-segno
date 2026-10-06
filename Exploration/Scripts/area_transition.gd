class_name AreaTransition
extends Area3D
## Walk into this volume to travel to another level.
## `target_spawn` is the name of a Marker3D in group "spawn_point" in the
## target level; PlayerLink places the player there on load.

@export_file("*.tscn") var target_scene := ""
@export var target_spawn: StringName = &"default"
## If the node has no CollisionShape3D child, a box of this size is added.
@export var auto_shape_size := Vector3(4.0, 2.0, 1.0)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 1  # the player body is on layer 2
	body_entered.connect(_on_body_entered)
	if find_children("*", "CollisionShape3D", false, false).is_empty():
		var box := BoxShape3D.new()
		box.size = auto_shape_size
		var shape := CollisionShape3D.new()
		shape.shape = box
		add_child(shape)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("party_leader"):
		return
	if target_scene == "":
		push_warning("AreaTransition '%s' has no target_scene." % name)
		return
	GameController.travel_to(target_scene, target_spawn)
