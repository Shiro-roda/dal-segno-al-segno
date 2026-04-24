extends Node3D
# AmmoStaff — circular staff showing Kendall's battle ammo as 3D notes.
# The staff wraps into a ring; notes sit on the curve.
# Time signature faces the camera at the front of the ring.
#
# Decomposition (ammo → notes):
#   one whole note per bullet

# ── Exports ───────────────────────────────────────────────────────────────────
@export var time_sig_bottom : int   = 8    # denominator — fixed, display only
@export var ring_radius     : float = 0.30
@export var ring_y          : float = 0.0
@export var staff_spread    : float = 0.026  # radial gap between staff lines
@export var note_whole_scene  : PackedScene   ## whole note model
@export var note_half_scene   : PackedScene   ## half note model
@export var note_eighth_scene : PackedScene   ## eighth note model

# ── Colours ───────────────────────────────────────────────────────────────────
const C_STAFF := Color(0.75, 0.68, 0.50, 1.0)
const C_NOTE  := Color(0.90, 0.85, 0.60, 1.0)
const C_SIG   := Color(1.353, 0.94, 0.547, 1.0)

# ── Dimensions ────────────────────────────────────────────────────────────────
const LINE_TUBE_R  := 0.003   # half-height of staff ribbon
const LINE_SEGS    := 48      # segments per arc
const LINE_DEPTH   := 0.018   # Z depth of each ribbon segment (flatness)
const NOTE_R_WHOLE := 0.036
const NOTE_R_HALF  := 0.026
const NOTE_R_EIGHTH:= 0.018
const NOTE_FLAT    := 0.35
const STEM_W       := 0.006
const STEM_H       := 0.062

# ── Internal ──────────────────────────────────────────────────────────────────
var _actor      = null
var _run_state  = null
var _ammo       : int = 0
var _max_ammo   : int = 8

var _ring_root  : Node3D   # contains staff lines; does NOT rotate
var _note_root  : Node3D   # contains notes placed on ring curve
var _sig_label_top : Label3D
var _sig_label_bot : Label3D

var _note_nodes : Array = []  # [{node, angle}]
var _ring_angle : float = 0.0
@export var rotate_speed : float = 0.4
var _spin_speed : float = 0.0

var _camera : Node3D


func setup(actor) -> void:
	_actor     = actor
	_run_state = actor.get("run_state")
	_max_ammo  = _run_state.gun_clip if _run_state else 6
	_ammo      = _run_state.ammo if _run_state else _max_ammo
	_build()
	_refresh()
	if _run_state and _run_state.has_signal("battle_ammo_changed"):
		_run_state.battle_ammo_changed.connect(_on_ammo_changed)


func _process(delta: float) -> void:
	_update_billboard()
	var spd := _spin_speed if _spin_speed > rotate_speed else rotate_speed
	_ring_angle += spd * delta
	if _note_root:
		_note_root.rotation.y = _ring_angle
	if _ring_root:
		_ring_root.rotation.y = _ring_angle


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
	var scene_root := get_tree().get_first_node_in_group("battle_scene")
	if scene_root:
		return scene_root.get_node_or_null("CameraRig/active_cam")
	var node : Node = self
	while node:
		var rig := node.get_node_or_null("CameraRig")
		if rig:
			return rig.get_node_or_null("active_cam")
		node = node.get_parent()
	return null


# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	_ring_root = Node3D.new()
	_ring_root.position = Vector3(0, ring_y, 0)
	add_child(_ring_root)

	_note_root = Node3D.new()
	_note_root.position = Vector3(0, ring_y, 0)
	add_child(_note_root)

	_build_staff_arcs()
	_build_time_sig()


func _build_staff_arcs() -> void:
	# 4 concentric circular arcs approximated with LineSegs segments
	# Each arc is a ring of thin cylinder segments
	for line_i in 4:
		var r := ring_radius + (line_i - 1.5) * staff_spread
		_add_arc(_ring_root, r)


func _add_arc(parent: Node3D, r: float) -> void:
	# Approximate a full circle with LINE_SEGS BoxMesh segments
	for i in LINE_SEGS:
		var a0 := (TAU / LINE_SEGS) * i
		var a1 := (TAU / LINE_SEGS) * (i + 1)
		var mid_a := (a0 + a1) * 0.5
		var chord := 2.0 * r * sin(TAU / LINE_SEGS / 2.0)

		var mi   := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(chord, LINE_TUBE_R * 2.0, LINE_DEPTH)
		var mat  := StandardMaterial3D.new()
		mat.albedo_color = C_STAFF
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = false
		mesh.material = mat
		mi.mesh = mesh
		mi.position = Vector3(sin(mid_a) * r, 0.0, cos(mid_a) * r)
		mi.rotation.y = mid_a
		parent.add_child(mi)


func _build_time_sig() -> void:
	var font_path := "res://UI/Themes/Fonts/TerminalVector.ttf"
	var font : Font = load(font_path) if ResourceLoader.exists(font_path) else null
	var sig_r := ring_radius - staff_spread * 1.5

	# Top number (ammo)
	_sig_label_top = Label3D.new()
	_sig_label_top.text        = str(_ammo)
	_sig_label_top.pixel_size  = 0.002
	_sig_label_top.font_size   = 82
	_sig_label_top.modulate    = C_SIG
	_sig_label_top.outline_size     = 10
	_sig_label_top.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_sig_label_top.no_depth_test    = false
	_sig_label_top.billboard        = BaseMaterial3D.BILLBOARD_DISABLED
	_sig_label_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font: _sig_label_top.font = font
	_sig_label_top.position = Vector3(0.0, 0.0, 0.0)
	_ring_root.add_child(_sig_label_top)

	# Bottom number: gun clip size (updates if clip changes)
	_sig_label_bot = Label3D.new()
	_sig_label_bot.text        = str(_max_ammo)
	_sig_label_bot.pixel_size  = 0.002
	_sig_label_bot.font_size   = 80
	_sig_label_bot.modulate    = C_SIG
	_sig_label_bot.outline_size     = 10
	_sig_label_bot.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_sig_label_bot.no_depth_test    = false
	_sig_label_bot.billboard        = BaseMaterial3D.BILLBOARD_DISABLED
	_sig_label_bot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font: _sig_label_bot.font = font
	_sig_label_bot.position = Vector3(0.0, -0.14, 0.0)
	_ring_root.add_child(_sig_label_bot)


# ── Notes ─────────────────────────────────────────────────────────────────────

func _rebuild_notes(ammo: int) -> void:
	for n in _note_nodes:
		if is_instance_valid(n.node):
			n.node.queue_free()
	_note_nodes.clear()
	if _sig_label_top:
		_sig_label_top.text = str(ammo)

	if ammo <= 0:
		return

	# One whole note per bullet
	var slots : Array = []
	for _i in ammo:
		slots.append("whole")

	# Reserve angle 0 (front) for time signature — spread notes around the rest
	# Notes fill from angle TAU/note_count spacing, starting after the time sig gap
	var count := slots.size()
	if count == 0:
		return

	# Gap at front for time sig: reserve ~TAU * 0.12 either side of angle 0
	var reserved := 0#TAU * 0.15
	var available := TAU - reserved * 2.0
	var angle_start := reserved        # start just past the reserved gap (in +angle direction)
	var angle_step  := available / maxi(count, 1) if count > 1 else 0.0

	for i in count:
		var angle := angle_start + i * angle_step
		var node : Node3D
		match slots[i]:
			"whole":  node = _make_whole_note()
			"half":   node = _make_half_note()
			_:        node = _make_eighth_note()

		# Place on ring, no rotation — billboard on parent keeps everything facing camera
		var r := ring_radius
		node.position = Vector3(sin(angle) * r, 0.0, cos(angle) * r)
		_note_root.add_child(node)
		_note_nodes.append({node = node, angle = angle})


func _make_whole_note() -> Node3D:
	if note_whole_scene:
		return note_whole_scene.instantiate()
	var mi   := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = NOTE_R_WHOLE
	mesh.height = NOTE_R_WHOLE * 2.0
	mi.mesh  = mesh
	mi.scale = Vector3(1.0, NOTE_FLAT, 1.0)
	_apply_mat(mi, C_NOTE)
	return mi


func _make_half_note() -> Node3D:
	if note_half_scene:
		return note_half_scene.instantiate()
	var root := Node3D.new()
	var head := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = NOTE_R_HALF
	mesh.height = NOTE_R_HALF * 2.0
	head.mesh  = mesh
	head.scale = Vector3(1.0, NOTE_FLAT, 1.0)
	_apply_mat(head, C_NOTE)
	root.add_child(head)
	var stem := _make_stem()
	stem.position = Vector3(0.0, STEM_H * 0.5, 0.0)
	root.add_child(stem)
	return root


func _make_eighth_note() -> Node3D:
	if note_eighth_scene:
		return note_eighth_scene.instantiate()
	var root := Node3D.new()
	var head := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = NOTE_R_EIGHTH
	mesh.height = NOTE_R_EIGHTH * 2.0
	head.mesh  = mesh
	head.scale = Vector3(1.0, NOTE_FLAT, 1.0)
	_apply_mat(head, C_NOTE)
	root.add_child(head)
	var stem := _make_stem()
	stem.position = Vector3(0.0, STEM_H * 0.5, 0.0)
	root.add_child(stem)
	# Flag: small angled BoxMesh at stem top
	var flag := MeshInstance3D.new()
	var fm   := BoxMesh.new()
	fm.size  = Vector3(STEM_W * 3.0, STEM_H * 0.35, STEM_W)
	_apply_mat(flag, C_NOTE)
	flag.mesh = fm
	flag.position = Vector3(STEM_W * 1.5, STEM_H - STEM_H * 0.18, 0.0)
	flag.rotation.z = -0.4
	root.add_child(flag)
	return root


func _make_stem() -> MeshInstance3D:
	var mi   := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(STEM_W, STEM_H, STEM_W)
	_apply_mat(mi, C_NOTE)
	mi.mesh = mesh
	return mi


func _apply_mat(mi: MeshInstance3D, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color  = color
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_DISABLED
	mi.set_surface_override_material(0, mat)


# ── Ammo change ───────────────────────────────────────────────────────────────

func _on_ammo_changed(new_ammo: int) -> void:
	_ammo = mini(new_ammo, _max_ammo)
	_spin_burst()
	_rebuild_notes(_ammo)


func _spin_burst() -> void:
	_spin_speed = 18.0
	var tw := create_tween()
	tw.tween_property(self, "_spin_speed", rotate_speed, 0.6)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh(_ignored = null) -> void:
	if _run_state:
		_ammo = mini(_run_state.ammo, _max_ammo)
	_rebuild_notes(_ammo)
