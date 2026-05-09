extends Node3D
# WillRing — orbiting token display for will-based characters.
# Tokens: large (5-pt) and small (1-pt) arranged on a slowly rotating ring.
# A Label3D at the centre shows the current will value.
#
# Assign real models via exports; falls back to SphereMesh placeholders.

# ── Exports ───────────────────────────────────────────────────────────────────
@export var token_large_scene : PackedScene   ## 5-point token model
@export var token_small_scene : PackedScene   ## 1-point token model
@export var ring_radius       : float = 0.28
@export var ring_y            : float = 0.0
@export var rotate_speed      : float = 0.6   # radians/sec

# ── Colours ───────────────────────────────────────────────────────────────────
const C_TEXT    := Color(0.95, 0.90, 0.70, 1.0)
const C_TEXT_LO := Color(0.80, 0.30, 0.22, 1.0)  # red tint when low

# ── Sizes (placeholder meshes) ────────────────────────────────────────────────
const SZ_LARGE := 0.055
const SZ_SMALL := 0.030

# ── Internal ──────────────────────────────────────────────────────────────────
var _actor       = null
var _ring_root   : Node3D      # rotates each frame
var _num_label   : Label3D
var _tokens      : Array = []  # [{node}]
var _ring_angle  : float = 0.0

# Camera for billboarding the number label
var _camera      : Node3D
var _spin_speed  : float = 0.0  # overrides rotate_speed during burst


func setup(actor) -> void:
	_actor = actor
	_build()
	_refresh()
	var pm = actor.party_member
	if pm:
		pm.will_changed.connect(_refresh)



func _process(delta: float) -> void:
	# Rotate the ring
	if _ring_root:
		_ring_angle += rotate_speed * delta
		var spd := _spin_speed if _spin_speed > rotate_speed else rotate_speed
		_ring_angle += spd * delta
		_ring_root.rotation.y = _ring_angle

	# Billboard the centre label to phantom cam
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


# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	var pm = _actor.party_member
	if pm == null:
		return

	# Ring root — this node rotates, tokens are children of it
	_ring_root = Node3D.new()
	_ring_root.position = Vector3(0, ring_y, 0)
	add_child(_ring_root)

	# Centre label
	_num_label = Label3D.new()
	_num_label.pixel_size       = 0.002
	_num_label.font_size        = 82
	_num_label.outline_size     = 10
	_num_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_num_label.no_depth_test    = false
	_num_label.billboard        = BaseMaterial3D.BILLBOARD_DISABLED
	_num_label.extra_cull_margin = 8.0
	_num_label.position    = Vector3(0, ring_y, 0)
	var font_path := "res://UI/Themes/Fonts/TerminalVector.ttf"
	if ResourceLoader.exists(font_path):
		_num_label.font = load(font_path)
	add_child(_num_label)

	_rebuild_tokens(pm.will)


func _rebuild_tokens(current: int) -> void:
	for t in _tokens:
		if is_instance_valid(t.node):
			t.node.queue_free()
	_tokens.clear()

	if current <= 0:
		return

	var large_count : int = current / 5
	var small_count : int = current % 5

	for i in large_count:
		var node := _make_token(5)
		_ring_root.add_child(node)
		_tokens.append({node = node})

	for i in small_count:
		var node := _make_token(1)
		_ring_root.add_child(node)
		_tokens.append({node = node})

	_reposition_all()





func _reposition_all() -> void:
	var count := _tokens.size()
	for i in count:
		var angle := (TAU / count) * i
		_tokens[i].node.position = Vector3(sin(angle) * ring_radius, 0, cos(angle) * ring_radius)



func _make_token(value: int) -> Node3D:
	# Use provided scenes if available, else placeholder sphere
	var src : PackedScene = token_large_scene if value == 5 else token_small_scene
	if src:
		return src.instantiate()

	# Placeholder — each token gets its own material instance so recolouring is independent
	var mi   := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	var sz   := SZ_LARGE if value == 5 else SZ_SMALL
	mesh.radius = sz
	mesh.height = sz * 2.0
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color  = Color(0.85, 0.78, 0.35, 1.0) if value == 5 else Color(0.65, 0.58, 0.25, 1.0)
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_DISABLED
	mi.set_surface_override_material(0, mat)
	mi.extra_cull_margin = 8.0
	return mi


func _spin_burst() -> void:
	_spin_speed = 30.0  # ~3 full rotations per second
	var tw := create_tween()
	tw.tween_property(self, "_spin_speed", rotate_speed, 1.4)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


# ── Refresh ───────────────────────────────────────────────────

func _refresh(_ignored = null) -> void:
	if _actor == null or not is_instance_valid(_actor):
		return
	var pm = _actor.party_member
	if pm == null or pm.max_will == 0:
		return

	var w  : int = pm.will
	var mw : int = pm.max_will

	# Update centre label
	if _num_label:
		_num_label.text = str(w)
		_num_label.modulate = C_TEXT_LO if float(w) / float(mw) < 0.3 else C_TEXT

	_spin_burst()
	_rebuild_tokens(w)
