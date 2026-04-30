extends Node3D
## TempoCentrifuge — 3D world-space tempo display.
##
## A ring of green orbs orbits the character.  Each orb represents 10 tempo.
## As more orbs are added the ring spins faster and expands outward,
## like a centrifuge spinning up under load.
##
## Integration: identical to WillRing / BloodGlobe.
##   actor_panel_3d.gd calls setup(actor) automatically.

# ── Scenes ────────────────────────────────────────────────────────────────────

const ORB_SCENE := preload("res://UI/3D/BattleDisplay/Scenes/ring nodes/small_orb.tscn")

# ── Tuning ────────────────────────────────────────────────────────────────────

## Radius at 1 orb.
const RADIUS_MIN  : float = 0.18
## Radius at 10 orbs (full pool).
const RADIUS_MAX  : float = 0.38

## Spin speed (rad/s) at 1 orb.
const SPEED_MIN   : float = 1.2
## Spin speed (rad/s) at 10 orbs.
const SPEED_MAX   : float = 9.0

## Orb size scale (applied to each instance).
const ORB_SCALE   : float = 1.5

## Y position relative to WorldSpacePanel — above blood globe (+0.355) and will ring.
const PANEL_Y_OFFSET : float = 0.65

## Orb colour at low count — dim green.
const C_DIM   := Color(0.15, 0.55, 0.20, 1.0)
## Orb colour at full (10 orbs) — bright lime.
const C_FULL  := Color(0.40, 1.00, 0.45, 1.0)
## Flash colour when pool hits 100 and resets.
const C_FLASH := Color(0.75, 1.00, 0.60, 1.0)

# ── Internal state ────────────────────────────────────────────────────────────

var _actor        = null
var _camera       : Node3D = null

var _ring_root    : Node3D = null   # all orbs are children; this node rotates
var _ring_angle   : float  = 0.0

var _orbs         : Array  = []     # Array[MeshInstance3D]
var _orb_mats     : Array  = []     # Array[StandardMaterial3D] — one per orb

var _last_count   : int    = -1
var _was_ready    : bool   = false


# ── Setup ─────────────────────────────────────────────────────────────────────

func setup(actor) -> void:
	_actor = actor
	position.y = PANEL_Y_OFFSET

	_ring_root = Node3D.new()
	_ring_root.name = "RingRoot"
	add_child(_ring_root)


# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _actor == null or not is_instance_valid(_actor):
		return

	var pool  : float = clampf(_actor.tempo_pool, 0.0, 100.0)
	var t     : float = pool / 100.0
	# Each orb = 10 tempo, so max 10 orbs.  Always show at least 0.
	var count : int   = int(pool / 10.0)   # 0..10 (truncate, not round)

	_tick_orbs(count, t)
	_tick_spin(delta, count)
	_tick_ready(t)
	_update_billboard()


# ── Orb management ────────────────────────────────────────────────────────────

func _tick_orbs(count: int, t: float) -> void:
	if count == _last_count:
		return
	_last_count = count
	_rebuild_orbs(count, t)


func _rebuild_orbs(count: int, t: float) -> void:
	# Free all existing orbs.
	for orb in _orbs:
		if is_instance_valid(orb):
			orb.queue_free()
	_orbs.clear()
	_orb_mats.clear()

	if count <= 0:
		return

	var radius : float = _radius_for(count)
	var col    : Color = C_DIM.lerp(C_FULL, t)

	for i in count:
		var angle : float = (TAU / count) * i

		var node  : Node3D
		var mat   : StandardMaterial3D

		if ORB_SCENE:
			node = ORB_SCENE.instantiate()
			# The scene's MeshInstance3D holds the material — grab and override it.
			var mi : MeshInstance3D = node.get_child(0) if node.get_child_count() > 0 else null
			if mi and mi is MeshInstance3D:
				mat = StandardMaterial3D.new()
				mat.shading_mode       = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.emission_enabled   = true
				mat.albedo_color       = col
				mat.emission           = col * 0.4
				mi.set_surface_override_material(0, mat)
		else:
			# Fallback: build a sphere inline.
			var mi := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.03
			mesh.height = 0.06
			mi.mesh = mesh
			mat = StandardMaterial3D.new()
			mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.emission_enabled = true
			mat.albedo_color     = col
			mat.emission         = col * 0.4
			mi.set_surface_override_material(0, mat)
			node = mi

		node.scale    = Vector3.ONE * ORB_SCALE
		node.position = Vector3(sin(angle) * radius, 0.0, cos(angle) * radius)
		_ring_root.add_child(node)
		_orbs.append(node)
		_orb_mats.append(mat)


# ── Spin & radius ─────────────────────────────────────────────────────────────

func _tick_spin(delta: float, count: int) -> void:
	if not _ring_root or count <= 0:
		return
	var speed : float = lerpf(SPEED_MIN, SPEED_MAX, float(count - 1) / 9.0)
	_ring_angle      += speed * delta
	_ring_root.rotation.y = _ring_angle


func _radius_for(count: int) -> float:
	if count <= 1:
		return RADIUS_MIN
	return lerpf(RADIUS_MIN, RADIUS_MAX, float(count - 1) / 9.0)


# ── Ready flash ───────────────────────────────────────────────────────────────

func _tick_ready(t: float) -> void:
	var ready : bool = t >= 0.999

	if ready and not _was_ready:
		# Flash all orbs bright then tween back.
		_set_orb_colour(C_FLASH)
		var tw := create_tween()
		tw.tween_method(_set_orb_colour, C_FLASH, C_FULL, 0.4)

	_was_ready = ready


func _set_orb_colour(col: Color) -> void:
	for mat in _orb_mats:
		if mat is StandardMaterial3D:
			mat.albedo_color = col
			mat.emission     = col * 0.4


# ── Billboard ─────────────────────────────────────────────────────────────────

func _update_billboard() -> void:
	if not _camera and _actor != null:
		_camera = _find_phantom_cam()
	if not _camera:
		return
	var dx : float = _camera.global_position.x - global_position.x
	var dz : float = _camera.global_position.z - global_position.z
	if dx * dx + dz * dz > 0.0001:
		var is_enemy : bool = _actor != null and _actor.get("team") == 1
		var flip     : float = PI if is_enemy else 0.0
		rotation.y = atan2(dx, dz) - PI * 0.5 + flip


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
