extends Node3D
# HpDisplay — placeholder 3D HP display.
# Currently: a row of small spheres that dim as HP drops.
# Replace _build() contents once you settle on the final aesthetic.

# ── Exports ───────────────────────────────────────────────────────────────────
@export var sphere_radius  : float = 0.025
@export var row_spacing    : float = 0.065
@export var max_visible    : int   = 20  # cap so huge-HP enemies don't overflow

# ── Colours ───────────────────────────────────────────────────────────────────
const C_FULL    := Color(0.75, 0.18, 0.14, 1.0)
const C_SPENT   := Color(0.22, 0.20, 0.18, 0.45)
const C_SHIELD  := Color(0.49, 0.92, 0.24, 1.0)

# ── Internal ──────────────────────────────────────────────────────────────────
var _actor      = null
var _spheres    : Array = []  # MeshInstance3D nodes
var _max_hp     : int = 1
var _hp         : int = 1
var _shield     : int = 0

# Camera for billboarding
var _camera : Node3D


func setup(actor) -> void:
	_actor    = actor
	_max_hp   = actor.max_hp
	_hp       = actor.hp
	_shield   = actor.get("shield_hp") if actor.get("shield_hp") != null else 0
	_build()
	_refresh()
	actor.hp_changed.connect(_refresh)


func _process(_delta: float) -> void:
	_update_billboard()


func _update_billboard() -> void:
	if not _camera and _actor != null:
		_camera = _find_phantom_cam()
	if not _camera:
		return
	var dx := _camera.global_position.x - global_position.x
	var dz := _camera.global_position.z - global_position.z
	if dx * dx + dz * dz > 0.0001:
		rotation.y = atan2(dx, dz) - PI * 0.5

func _find_phantom_cam() -> Node3D:
	var is_enemy : bool = _actor.get("team") == 1
	var cam_name := "target_cam" if is_enemy else "active_cam"
	var scene_root := get_tree().get_first_node_in_group("battle_scene")
	if scene_root:
		return scene_root.get_node_or_null("CameraRig/" + cam_name)
	var node : Node = self
	while node:
		var rig := node.get_node_or_null("CameraRig")
		if rig:
			return rig.get_node_or_null(cam_name)
		node = node.get_parent()
	return null


# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	for s in _spheres:
		if is_instance_valid(s):
			s.queue_free()
	_spheres.clear()

	var count := mini(_max_hp, max_visible)
	var total_w := (count - 1) * row_spacing
	for i in count:
		var mi   := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = sphere_radius
		mesh.height = sphere_radius * 2.0
		var mat  := StandardMaterial3D.new()
		mat.albedo_color  = C_FULL
		mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = false
		mat.transparency  = BaseMaterial3D.TRANSPARENCY_DISABLED
		mesh.material = mat
		mi.mesh = mesh
		mi.position = Vector3(i * row_spacing - total_w * 0.5, 0, 0)
		add_child(mi)
		_spheres.append(mi)


# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh(_ignored = null) -> void:
	if _actor == null or not is_instance_valid(_actor):
		return
	_hp     = _actor.hp
	_max_hp = _actor.max_hp
	_shield = _actor.get("shield_hp") if _actor.get("shield_hp") != null else 0

	# Rebuild if max changed
	if _spheres.size() != mini(_max_hp, max_visible):
		_build()

	for i in _spheres.size():
		var mat : Material = _spheres[i].get_active_material(0)
		if not mat is StandardMaterial3D:
			continue
		var sm := mat as StandardMaterial3D
		# i is 0-based from left; hp fills from left
		if i < _hp:
			sm.albedo_color = C_FULL
		elif i < _hp + _shield:
			sm.albedo_color = C_SHIELD
		else:
			sm.albedo_color = C_SPENT
