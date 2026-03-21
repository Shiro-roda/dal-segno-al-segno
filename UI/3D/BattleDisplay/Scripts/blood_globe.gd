extends Node3D

@export var token_large_scene  : PackedScene = preload("res://UI/3D/BattleDisplay/Scenes/ring nodes/large_flesh_orb.tscn")
@export var token_small_scene  : PackedScene = preload("res://UI/3D/BattleDisplay/Scenes/ring nodes/small_flesh_orb.tscn")
@export var shield_orb_scene   : PackedScene = preload("res://UI/3D/BattleDisplay/Scenes/ring nodes/small_ice_orb.tscn")


@export var ring_radius : float = 0.32
@export var ring_y : float = 0.0
@export var rotate_speed : float = 0.45

@export var spring_strength : float = 52.0
@export var spring_damping : float = 0.95
@export var repel_strength : float = 6.0
@export var repel_distance : float = 0.09


const C_TEXT := Color(0.95,0.9,0.9,1)
const C_TEXT_LO := Color(0.9,0.25,0.25,1)

const SZ_LARGE := 0.06
const SZ_SMALL := 0.035

var _actor
var _ring_root   : Node3D
var _shield_root : Node3D  # separate ring for shield orbs
var _num_label   : Label3D
var _tokens         : Array = []  # [{node, target, vel}] for HP
var _shield_tokens  : Array = []  # [{node}] for temp HP — simple, no spring
var _ring_angle  := 0.0
var _last_shield : int = -1
var _camera      : Node3D


func setup(actor):
	_actor = actor
	_build()
	_refresh()
	actor.hp_changed.connect(_refresh)
	# Enemy WorldSpacePanel starts hidden until Augur reveals their stats.
	if actor.team == actor.Team.ENEMY:
		var panel := get_parent()
		if is_instance_valid(panel):
			panel.visible = false


func _process(delta):

	_update_spring(delta)

	if _ring_root:
		_ring_angle += rotate_speed * delta
		_ring_root.rotation.y = _ring_angle
	if _shield_root and not _shield_tokens.is_empty():
		_shield_root.rotation.y = -_ring_angle * 0.7

	_update_label_billboard()


func _update_label_billboard() -> void:
	if not _num_label:
		return

	if not _camera and _actor != null:
		_camera = _find_phantom_cam()

	if not _camera:
		return

	var dx := _camera.global_position.x - global_position.x
	var dz := _camera.global_position.z - global_position.z

	if dx * dx + dz * dz > 0.0001:
		var is_enemy : bool = _actor != null and _actor.get("team") == 1
		var flip : float = PI if is_enemy else 0.0
		_num_label.rotation.y = atan2(dx, dz) - PI * 0.5 + flip

func _find_phantom_cam() -> Node3D:
	var is_enemy : bool = _actor != null and _actor.get("team") == 1
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

func _update_spring(delta):
	
	_apply_repulsion(delta)

	for t in _tokens:

		var node : Node3D = t.node

		var pos = node.position
		var ttime = Time.get_ticks_msec() * 0.001
		var vel = t.vel
		var target = t.target
		# angular wobble
		var wobble = sin(ttime * 1.6 + t.wobble_seed * 10.0) * 0.25

		var angle = t.base_angle + wobble

		t.target.x = sin(angle) * ring_radius
		t.target.z = cos(angle) * ring_radius
		
		var radial = ring_radius + sin(ttime * 1.1 + t.wobble_seed * 6.0) * 0.015

		t.target.x = sin(angle) * radial
		t.target.z = cos(angle) * radial
	
		var force = (target - pos) * spring_strength

		vel += force * delta
		vel *= pow(spring_damping, delta * 60.0)

		pos += vel * delta

		node.position = pos
		t.vel = vel
		t.target.y = sin(Time.get_ticks_msec() * 0.002 + node.get_instance_id()) * 0.02

func _apply_repulsion(delta):

	var count = _tokens.size()

	for i in count:
		var ti = _tokens[i]
		var ni : Node3D = ti.node
		var pos_i = ni.position

		for j in range(i + 1, count):

			var tj = _tokens[j]
			var nj : Node3D = tj.node
			var pos_j = nj.position

			var diff = pos_i - pos_j
			var dist = diff.length()

			if dist < repel_distance and dist > 0.0001:

				var push = diff.normalized() * (repel_distance - dist) * repel_strength * delta
				
				var size_i = SZ_LARGE if ni.scene_file_path == token_large_scene.resource_path else SZ_SMALL
				var size_j = SZ_LARGE if nj.scene_file_path == token_large_scene.resource_path else SZ_SMALL

				var scale = (size_i + size_j) * 8.0
				push *= scale
				
				ti.vel += push
				tj.vel -= push

func _slosh():

	for t in _tokens:

		var dir = -t.target.normalized()

		t.vel += dir * randf_range(4.0,6.0)
		

# ----------------------------------------------------
# BUILD
# ----------------------------------------------------

func _build():

	_ring_root = Node3D.new()
	_ring_root.position = Vector3(0, ring_y, 0)
	add_child(_ring_root)

	_shield_root = Node3D.new()
	# Slightly above the HP ring so ice orbs are visually distinct
	_shield_root.position = Vector3(0, ring_y + 0.12, 0)
	add_child(_shield_root)

	_num_label = Label3D.new()
	_num_label.pixel_size    = 0.002
	_num_label.font_size     = 82
	_num_label.outline_size  = 10
	_num_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_num_label.position = Vector3(0, ring_y, 0)
	add_child(_num_label)


func _rebuild_tokens(current:int):

	for t in _tokens:
		if is_instance_valid(t.node):
			t.node.queue_free()

	_tokens.clear()

	if current <= 0:
		return

	var large = current / 5
	var small = current % 5

	for i in large:
		var node = _make_token(5)
		_ring_root.add_child(node)
		_tokens.append({
			node = node,
			target = Vector3.ZERO,
			vel = Vector3.ZERO,
			base_angle = 0.0,
			angle_offset = randf_range(-0.3,0.3),
			wobble_seed = randf()
		})

	for i in small:
		var node = _make_token(1)
		_ring_root.add_child(node)
		_tokens.append({
			node = node,
			target = Vector3.ZERO,
			vel = Vector3.ZERO,
			base_angle = 0.0,
			angle_offset = randf_range(-0.3,0.3),
			wobble_seed = randf()
		})
	_reposition_all()


func _reposition_all():

	var count = _tokens.size()
	if count == 0:
		return

	for i in count:
		var angle = (TAU / count) * i

		var target = Vector3(
			sin(angle) * ring_radius,
			0,
			cos(angle) * ring_radius
		)

		_tokens[i].base_angle = angle
		_tokens[i].target = target


# ----------------------------------------------------
# TOKEN CREATION
# ----------------------------------------------------

func _make_token(value:int) -> Node3D:

	var src = token_large_scene if value == 5 else token_small_scene

	if src:
		return src.instantiate()

	# fallback mesh
	var mi = MeshInstance3D.new()

	var mesh = SphereMesh.new()
	var sz = SZ_LARGE if value == 5 else SZ_SMALL
	mesh.radius = sz
	mesh.height = sz*2
	mi.mesh = mesh

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	if value == 5:
		mat.albedo_color = Color(0.75,0.12,0.12)
	else:
		mat.albedo_color = Color(0.95,0.22,0.18)

	mi.set_surface_override_material(0,mat)

	return mi


# ----------------------------------------------------
# SHIELD RING
# ----------------------------------------------------

func _rebuild_shield_tokens(shield: int) -> void:
	for t in _shield_tokens:
		if is_instance_valid(t): t.queue_free()
	_shield_tokens.clear()
	if shield <= 0 or _shield_root == null:
		return
	var count := mini(shield, 20)
	for i in count:
		var node : Node3D
		if shield_orb_scene != null:
			node = shield_orb_scene.instantiate() as Node3D
		else:
			# Fallback: small ice-coloured sphere
			var mi := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.025
			mesh.height = 0.05
			mi.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color           = Color(0.72, 0.94, 1.00, 1.0)
			mat.emission_enabled       = true
			mat.emission               = Color(0.40, 0.75, 0.95, 1.0)
			mat.emission_energy_multiplier = 0.8
			mat.shading_mode           = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override       = mat
			node = mi
		var angle := (TAU / count) * i
		node.position = Vector3(sin(angle) * ring_radius * 0.85,
			0.0,
			cos(angle) * ring_radius * 0.85)
		_shield_root.add_child(node)
		_shield_tokens.append(node)


# ----------------------------------------------------
# REFRESH
# ----------------------------------------------------

func _refresh(_ignored=null):

	if _actor == null:
		return

	var hp     : int = _actor.hp
	var mhp    : int = _actor.max_hp
	var shield : int = _actor.get("shield_hp") if _actor.get("shield_hp") != null else 0

	if _num_label:
		_num_label.text = str(hp)
		_num_label.modulate = C_TEXT_LO if float(hp)/float(mhp) < 0.3 else C_TEXT

	_rebuild_tokens(hp)
	_slosh()

	if shield != _last_shield:
		_last_shield = shield
		_rebuild_shield_tokens(shield)
