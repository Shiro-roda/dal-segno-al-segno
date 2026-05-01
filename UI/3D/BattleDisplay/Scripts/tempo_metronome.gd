extends Node3D
## TempoCentrifuge — 3D world-space tempo display.
##
## Behaviour:
##   < 20 tempo  : one large, dim, inert central orb.
##   20–39 tempo : 2 orbs spin slowly.
##   40–79 tempo : 4 orbs spin at medium speed.
##   80–99 tempo : 8 orbs spin faster.
##   100 tempo   : all orbs converge to the centre, forming one large bright orb
##                 ("ready" state).  Dims back out after the actor's turn.
##
## Integration: actor_panel_3d.gd calls setup(actor) automatically.

const ORB_SCENE := preload("res://UI/3D/BattleDisplay/Scenes/ring nodes/small_orb.tscn")

# ── Tuning ────────────────────────────────────────────────────────────────────

## Ring radius for the orbiting configurations.
const RING_RADIUS   : float = 0.26
## Scale of each individual spinning orb.
const ORB_SCALE     : float = 1.2
## Scale of the single central orb (idle / ready state).
const CENTER_SCALE  : float = 2.4

## Spin speeds (rad/s) per tier — the ring accelerates as tempo fills.
## These are the speeds at the entry threshold; actual speed is interpolated
## continuously within each tier proportional to how far through it the pool is.
const SPEED_2   : float = 0.6   # 2-orb tier (20–39 tempo)
const SPEED_4   : float = 1.4   # 4-orb tier (40–59 tempo)
const SPEED_6   : float = 2.8   # 6-orb tier (60–79 tempo)
const SPEED_8   : float = 5.2   # 8-orb tier (80–99 tempo)

## Y offset above the WorldSpacePanel origin.
const PANEL_Y_OFFSET : float = 0.65

## Central idle orb — dim, no emission.
const C_IDLE        := Color(0.12, 0.40, 0.16, 1.0)
## Orbiting orbs — mid-green.
const C_ORB         := Color(0.25, 0.80, 0.35, 1.0)
## Ready orb — bright lime.
const C_READY       := Color(0.60, 1.00, 0.65, 1.0)
## Emission multiplier for orbiting orbs.
const EMIT_ORB      : float = 0.55
## Emission multiplier for the ready orb.
const EMIT_READY    : float = 1.4

## How quickly the ready orb dims after the turn is spent (alpha decay per second).
const READY_DIM_SPEED : float = 2.5

# ── Internal state ────────────────────────────────────────────────────────────

var _actor       = null
var _camera      : Node3D = null

var _ring_root   : Node3D = null
var _ring_angle  : float  = 0.0

var _orbs        : Array  = []
var _orb_mats    : Array  = []

## Which tier we are currently displaying.
## 0 = idle centre, 2 = 2-orb, 4 = 4-orb, 8 = 8-orb, 100 = ready.
var _current_tier : int   = 0

## True while we are in the "ready" converged state.
var _was_ready    : bool  = false
## Tracks when the actor last took a turn so we can dim the ready orb.
var _last_tempo   : float = -1.0
## Dim alpha for the ready orb (fades from 1 → 0 after the turn is spent).
var _ready_alpha  : float = 1.0


# ── Setup ─────────────────────────────────────────────────────────────────────

func setup(actor) -> void:
	_actor = actor
	position.y = PANEL_Y_OFFSET
	_ring_root = Node3D.new()
	_ring_root.name = "RingRoot"
	add_child(_ring_root)
	_rebuild_tier(0)


# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _actor == null or not is_instance_valid(_actor):
		return

	var pool : float = clampf(_actor.tempo_pool, 0.0, 100.0)
	var tier : int   = _pool_to_tier(pool)

	if tier != _current_tier:
		_current_tier = tier
		_rebuild_tier(tier)

	_tick_spin(delta, tier)
	_tick_ready_dim(delta, pool)
	_update_billboard()


# ── Tier logic ────────────────────────────────────────────────────────────────

func _pool_to_tier(pool: float) -> int:
	if pool >= 100.0:
		return 100
	elif pool >= 80.0:
		return 8
	elif pool >= 60.0:
		return 6
	elif pool >= 40.0:
		return 4
	elif pool >= 20.0:
		return 2
	else:
		return 0


func _rebuild_tier(tier: int) -> void:
	# Free existing orbs.
	for orb in _orbs:
		if is_instance_valid(orb):
			orb.queue_free()
	_orbs.clear()
	_orb_mats.clear()

	match tier:
		0:
			# Single large dim centre orb, no orbit.
			_spawn_orb(Vector3.ZERO, CENTER_SCALE, C_IDLE, 0.0)
		2, 4, 6, 8:
			# Evenly spaced orbiting orbs.
			for i in tier:
				var angle : float = (TAU / tier) * i
				var pos := Vector3(sin(angle) * RING_RADIUS, 0.0, cos(angle) * RING_RADIUS)
				_spawn_orb(pos, ORB_SCALE, C_ORB, EMIT_ORB)
		100:
			# Single large bright centre orb.
			_ready_alpha = 1.0
			_was_ready   = true
			_spawn_orb(Vector3.ZERO, CENTER_SCALE, C_READY, EMIT_READY)
		_:
			pass


## Instantiate one orb, add to the ring root, track it.
func _spawn_orb(local_pos: Vector3, scale_f: float, col: Color, emit_mult: float) -> void:
	var node  : Node3D
	var mat   : StandardMaterial3D

	if ORB_SCENE:
		node = ORB_SCENE.instantiate()
		var mi : MeshInstance3D = node.get_child(0) if node.get_child_count() > 0 else null
		if mi and mi is MeshInstance3D:
			mat = StandardMaterial3D.new()
			mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.emission_enabled = emit_mult > 0.0
			mat.albedo_color     = col
			mat.emission         = col * emit_mult
			mi.set_surface_override_material(0, mat)
	else:
		var mi2 := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.03
		mesh.height = 0.06
		mi2.mesh = mesh
		mat = StandardMaterial3D.new()
		mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = emit_mult > 0.0
		mat.albedo_color     = col
		mat.emission         = col * emit_mult
		mi2.set_surface_override_material(0, mat)
		node = mi2

	node.scale    = Vector3.ONE * scale_f
	node.position = local_pos
	_ring_root.add_child(node)
	_orbs.append(node)
	_orb_mats.append(mat)


# ── Spin ──────────────────────────────────────────────────────────────────────

func _tick_spin(delta: float, tier: int) -> void:
	if not _ring_root:
		return
	var pool : float = clampf(_actor.tempo_pool, 0.0, 100.0)
	# Compute speed continuously proportional to pool within each tier band.
	# This gives smooth acceleration rather than discrete jumps.
	var speed : float = 0.0
	match tier:
		2:
			# 20–39: interpolate from SPEED_2 entry up to SPEED_4 entry
			var t := (pool - 20.0) / 20.0
			speed = lerpf(SPEED_2, SPEED_4, t)
		4:
			var t := (pool - 40.0) / 20.0
			speed = lerpf(SPEED_4, SPEED_6, t)
		6:
			var t := (pool - 60.0) / 20.0
			speed = lerpf(SPEED_6, SPEED_8, t)
		8:
			var t := (pool - 80.0) / 20.0
			speed = lerpf(SPEED_8, SPEED_8 * 1.4, t)
		_:
			speed = 0.0
	_ring_angle          += speed * delta
	_ring_root.rotation.y = _ring_angle


# ── Ready dim ─────────────────────────────────────────────────────────────────

## After the actor's turn is taken their tempo_pool drops back below 100.
## We detect that transition and fade the ready orb out.
func _tick_ready_dim(delta: float, pool: float) -> void:
	if not _was_ready:
		return
	if pool < 99.0:
		# Turn was just taken — begin dimming.
		_ready_alpha = maxf(0.0, _ready_alpha - READY_DIM_SPEED * delta)
		if _ready_alpha <= 0.0:
			_was_ready = false
		var dim_col := Color(C_READY.r, C_READY.g, C_READY.b, _ready_alpha)
		_set_orb_colour(dim_col, EMIT_READY * _ready_alpha)


func _set_orb_colour(col: Color, emit_mult: float = EMIT_ORB) -> void:
	for mat in _orb_mats:
		if mat is StandardMaterial3D:
			mat.albedo_color     = col
			mat.emission         = Color(col.r, col.g, col.b, 1.0) * emit_mult


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
