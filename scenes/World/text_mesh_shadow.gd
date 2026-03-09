@tool
extends MeshInstance3D
class_name TextMeshShadow
# Attach to any MeshInstance3D that uses a TextMesh.
# Automatically creates a dark duplicate offset behind the text to simulate a shadow.
# The shadow inherits the same mesh, so it updates when the TextMesh changes.

@export var shadow_color   : Color = Color(0.0, 0.0, 0.0, 0.7)
@export var shadow_offset  : Vector3 = Vector3(0.05, -0.05, -0.1)
@export var shadow_enabled : bool = true

var _shadow_instance : MeshInstance3D


func _ready() -> void:
	_rebuild_shadow()


func _rebuild_shadow() -> void:
	if _shadow_instance:
		_shadow_instance.queue_free()
		_shadow_instance = null

	if not shadow_enabled or mesh == null:
		return

	_shadow_instance = MeshInstance3D.new()
	_shadow_instance.mesh = mesh  # shared mesh reference — updates automatically

	var mat := StandardMaterial3D.new()
	mat.albedo_color = shadow_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	_shadow_instance.material_override = mat
	_shadow_instance.position = shadow_offset

	# Add as a sibling so it sits behind in the scene without inheriting our transform twice
	get_parent().add_child(_shadow_instance)
	# Move before self so it renders behind
	get_parent().move_child(_shadow_instance, get_index())
