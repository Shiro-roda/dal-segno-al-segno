extends Node3D
# HpDisplay — placeholder 3D HP display.
# Currently: a row of small spheres that dim as HP drops.
# Replace _build() contents once you settle on the final aesthetic.

# ── Exports ───────────────────────────────────────────────────────────────────
@export var sphere_radius   : float = 0.025
@export var shield_radius   : float = 0.018
@export var row_spacing     : float = 0.065
@export var max_visible     : int   = 20
@export var max_shield_vis  : int   = 10

# ── Colours ───────────────────────────────────────────────────────────────────
const C_FULL  := Color(0.75, 0.18, 0.14, 1.0)
const C_SPENT := Color(0.22, 0.20, 0.18, 0.45)
const C_ICE   := Color(0.72, 0.94, 1.00, 1.0)  # pale cyan-white ice
const C_ICE_EM:= Color(0.40, 0.75, 0.95, 1.0)  # ice glow emission

# ── Internal ──────────────────────────────────────────────────────────────────
var _actor          = null
var _hp_spheres     : Array = []  # one per max_hp (capped)
var _shield_spheres : Array = []  # rebuilt each refresh
var _max_hp         : int = 1
var _hp             : int = 1
var _shield         : int = 0

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
	for s in _hp_spheres:
		if is_instance_valid(s): s.queue_free()
	_hp_spheres.clear()
	_free_shield_spheres()

	var count := mini(_max_hp, max_visible)
	var total_w := (count - 1) * row_spacing
	for i in count:
		var mi   := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = sphere_radius
		mesh.height = sphere_radius * 2.0
		mi.mesh = mesh
		var mat  := StandardMaterial3D.new()
		mat.albedo_color  = C_FULL
		mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = false
		mat.transparency  = BaseMaterial3D.TRANSPARENCY_DISABLED
		mi.material_override = mat
		mi.position = Vector3(i * row_spacing - total_w * 0.5, 0, 0)
		add_child(mi)
		_hp_spheres.append(mi)


func _free_shield_spheres() -> void:
	for s in _shield_spheres:
		if is_instance_valid(s): s.queue_free()
	_shield_spheres.clear()


func _build_shield_spheres(count: int, right_edge_x: float) -> void:
	for i in count:
		var mi   := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = shield_radius
		mesh.height = shield_radius * 2.0
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color               = C_ICE
		mat.emission_enabled           = true
		mat.emission                   = C_ICE_EM
		mat.emission_energy_multiplier = 0.8
		mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test              = false
		mat.transparency               = BaseMaterial3D.TRANSPARENCY_DISABLED
		mi.material_override           = mat
		mi.position = Vector3(right_edge_x + (i + 0.7) * row_spacing, 0.010, 0)
		add_child(mi)
		_shield_spheres.append(mi)


# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh(_ignored = null) -> void:
	if _actor == null or not is_instance_valid(_actor):
		return
	_hp     = _actor.hp
	_max_hp = _actor.max_hp
	_shield = _actor.get("shield_hp") if _actor.get("shield_hp") != null else 0

	# Rebuild HP ring if max changed.
	if _hp_spheres.size() != mini(_max_hp, max_visible):
		_build()

	# Colour HP orbs.
	for i in _hp_spheres.size():
		var mat := (_hp_spheres[i] as MeshInstance3D).material_override as StandardMaterial3D
		if mat == null: continue
		mat.albedo_color = C_FULL if i < _hp else C_SPENT

	# Rebuild shield orbs whenever the count changes.
	var shield_count := mini(_shield, max_shield_vis)
	if _shield_spheres.size() != shield_count:
		_free_shield_spheres()
		if shield_count > 0:
			# Right edge: last hp sphere's local x, or 0 if ring is empty.
			var right_edge : float = (_hp_spheres.back() as Node3D).position.x \
					if not _hp_spheres.is_empty() else 0.0
			_build_shield_spheres(shield_count, right_edge)
