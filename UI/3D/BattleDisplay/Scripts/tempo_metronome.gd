extends Node3D
## TempoCentrifuge — 3D world-space tempo display.
##
## Behaviour:
##   0–19 tempo   : 10 small orbs (idle scatter)
##   20–39 tempo  : 8  orbs, slightly larger
##   40–59 tempo  : 6  orbs, medium
##   60–79 tempo  : 4  orbs, large
##   80–99 tempo  : 2  orbs, very large, spinning fast
##   100 tempo    : all orbs converge to the centre, forming one large bright orb
##                  ("ready" state). Dims back out after the actor's turn.
##
## Melt transitions: when the orb count drops, each old orb is assigned a target
## new-orb position and physically travels there while shrinking and fading.
## Multiple old orbs converge on the same target point, giving the impression of
## merging. When the count rises, new orbs are assigned origin positions from the
## old ring and travel outward to their final angles as they grow in.
## Ring radius interpolates continuously rather than snapping.
##
## Integration: actor_panel_3d.gd calls setup(actor) automatically.

const ORB_SCENE := preload("res://UI/3D/BattleDisplay/Scenes/ring nodes/small_orb.tscn")

# ── Tuning ────────────────────────────────────────────────────────────────────

## Target scale per orb count.  Fewer orbs → bigger orbs.
const ORB_SCALE_BY_COUNT := {
	10: 0.80,
	8:  0.95,
	6:  1.10,
	4:  1.35,
	2:  1.70,
}
const CENTER_SCALE  : float = 2.4

## Ring radius per orb count.  Lerped smoothly every frame.
const RADIUS_BY_COUNT := {
	10: 0.38,
	8:  0.34,
	6:  0.30,
	4:  0.26,
	2:  0.20,
}
const RADIUS_LERP_SPEED : float = 6.0

## Spin speeds (rad/s) per orb count.
const SPEED_BY_COUNT := {
	10: 0.8,
	8:  1.6,
	6:  2.4,
	4:  3.8,
	2:  8.2,
}

## Total duration of the melt crossfade (seconds).
const BLEND_DURATION : float = 0.5

## Y offset above the WorldSpacePanel origin.
const PANEL_Y_OFFSET : float = 0.65

const C_IDLE  := Color(0.12, 0.40, 0.16, 1.0)
const C_ORB   := Color(0.25, 0.80, 0.35, 1.0)
const C_READY := Color(0.60, 1.00, 0.65, 1.0)
const EMIT_ORB   : float = 0.55
const EMIT_READY : float = 0.10
const READY_DIM_SPEED : float = 2.5

# ── Internal state ────────────────────────────────────────────────────────────

var _actor  = null
var _camera : Node3D = null

var _ring_root  : Node3D = null
var _ring_angle : float  = 0.0

# Active (incoming) layer.
var _orbs          : Array = []
var _orb_mats      : Array = []
var _orb_emits     : Array = []   ## target emit multiplier per active orb
var _target_orb_scale : float = 0.80

# Outgoing layer.  Each entry carries its own blend metadata.
# Each element: { node, mat, emit_mult, start_pos, target_pos, start_scale }
var _retiring : Array = []

## 0 → 1 blend progress (shared by both layers).
var _blend_t : float = 1.0

var _current_tier   : int   = 0
var _current_radius : float = 0.38

var _was_ready   : bool  = false
var _ready_alpha : float = 1.0


# ── Setup ─────────────────────────────────────────────────────────────────────

func setup(actor) -> void:
	_actor = actor
	position.y = PANEL_Y_OFFSET
	_ring_root = Node3D.new()
	_ring_root.name = "RingRoot"
	add_child(_ring_root)
	_current_radius = RADIUS_BY_COUNT.get(10, 0.38)
	_rebuild_tier(10)


# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _actor == null or not is_instance_valid(_actor):
		return

	var pool : float = clampf(_actor.tempo_pool, 0.0, 100.0)
	var tier : int   = _pool_to_tier(pool)

	if tier != _current_tier:
		_current_tier = tier
		_rebuild_tier(tier)

	_tick_blend(delta)
	_tick_radius(delta, tier)
	_tick_spin(delta, tier, pool)
	_tick_ready_dim(delta, pool)
	_update_billboard()


# ── Tier logic ────────────────────────────────────────────────────────────────

func _pool_to_tier(pool: float) -> int:
	if   pool >= 100.0: return 100
	elif pool >=  80.0: return 2
	elif pool >=  60.0: return 4
	elif pool >=  40.0: return 6
	elif pool >=  20.0: return 8
	else:               return 10


# ── Rebuild ───────────────────────────────────────────────────────────────────

func _rebuild_tier(tier: int) -> void:
	# ── Decide new-orb positions ───────────────────────────────────────────
	var new_count  : int   = tier if tier != 100 else 1
	var new_radius : float = 0.0 if tier == 100 else RADIUS_BY_COUNT.get(tier, _current_radius)
	var new_positions : Array = []
	for i in new_count:
		if tier == 100:
			new_positions.append(Vector3.ZERO)
		else:
			var a := (TAU / new_count) * i
			new_positions.append(Vector3(sin(a) * new_radius, 0.0, cos(a) * new_radius))

	# ── Retire current orbs, assigning each a convergence target ──────────
	var old_count : int = _orbs.size()
	_retire_current_orbs(new_positions, old_count, new_count)

	# ── Spawn new orbs, giving each a launch origin from the old ring ──────
	_orbs.clear()
	_orb_mats.clear()
	_orb_emits.clear()
	_blend_t = 0.0

	match tier:
		2, 4, 6, 8, 10:
			_target_orb_scale = ORB_SCALE_BY_COUNT.get(tier, 1.0)
			var col       : Color = C_IDLE if tier == 10 else C_ORB
			var emit_mult : float = 0.0   if tier == 10 else EMIT_ORB
			for i in new_count:
				# New orbs start at the old orb position nearest to their target,
				# so they appear to blossom outward from the merge point.
				var origin := _old_origin_for(i, new_count, old_count)
				_spawn_orb(origin, 0.0, col, emit_mult)
		100:
			_ready_alpha      = 1.0
			_was_ready        = true
			_target_orb_scale = CENTER_SCALE
			_spawn_orb(Vector3.ZERO, 0.0, C_READY, EMIT_READY)
		_:
			pass


## Returns the world position that new orb [new_i] should start at (its origin).
## We map it to the old-ring position that corresponds to the same angular slot.
func _old_origin_for(new_i: int, new_count: int, old_count: int) -> Vector3:
	if old_count == 0:
		return Vector3.ZERO
	# Which old index maps to this new index's cluster?
	var old_i : int = int(round(float(new_i) * float(old_count) / float(new_count))) % old_count
	if old_i < _orbs.size() and is_instance_valid(_orbs[old_i]):
		return _orbs[old_i].position   # _orbs is still populated at this point
	# Fallback: compute geometrically from the old ring radius.
	var a := (TAU / old_count) * old_i
	return Vector3(sin(a) * _current_radius, 0.0, cos(a) * _current_radius)


## Moves current orbs into _retiring, assigning each a target position to
## converge toward.  Target = the new-orb position for the cluster it belongs to.
func _retire_current_orbs(new_positions: Array, old_count: int, new_count: int) -> void:
	# Free any already-retiring orbs from the previous blend.
	_free_retiring()

	for i in _orbs.size():
		if not is_instance_valid(_orbs[i]):
			continue
		# Assign this old orb to whichever new position it is "in" when evenly split.
		var target_idx : int
		if new_count == 0:
			target_idx = 0
		else:
			target_idx = int(float(i) * float(new_count) / float(old_count if old_count > 0 else 1))
			target_idx = clampi(target_idx, 0, new_positions.size() - 1)

		var target_pos : Vector3 = new_positions[target_idx] if new_positions.size() > 0 else Vector3.ZERO

		_retiring.append({
			"node":        _orbs[i],
			"mat":         _orb_mats[i] if i < _orb_mats.size() else null,
			"emit_mult":   _orb_emits[i] if i < _orb_emits.size() else EMIT_ORB,
			"start_pos":   _orbs[i].position,
			"target_pos":  target_pos,
			"start_scale": _orbs[i].scale.x,
		})


func _free_retiring() -> void:
	for entry in _retiring:
		if is_instance_valid(entry["node"]):
			entry["node"].queue_free()
	_retiring.clear()


# ── Spawn ─────────────────────────────────────────────────────────────────────

func _spawn_orb(local_pos: Vector3, scale_f: float, col: Color, emit_mult: float) -> void:
	var node : Node3D
	var mat  : StandardMaterial3D

	if ORB_SCENE:
		node = ORB_SCENE.instantiate()
		var mi : MeshInstance3D = node.get_child(0) if node.get_child_count() > 0 else null
		if mi and mi is MeshInstance3D:
			mat = StandardMaterial3D.new()
			mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.depth_draw_mode  = BaseMaterial3D.DEPTH_DRAW_DISABLED
			mat.emission_enabled = true
			mat.albedo_color     = Color(col.r, col.g, col.b, 0.0)
			mat.emission         = col * emit_mult
			mi.set_surface_override_material(0, mat)
			# Prevent distance-based frustum culling on dynamically spawned meshes.
			mi.extra_cull_margin = 8.0
	else:
		var mi2  := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.03
		mesh.height = 0.06
		mi2.mesh = mesh
		mat = StandardMaterial3D.new()
		mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.depth_draw_mode  = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.emission_enabled = true
		mat.albedo_color     = Color(col.r, col.g, col.b, 0.0)
		mat.emission         = col * emit_mult
		mi2.set_surface_override_material(0, mat)
		# Prevent distance-based frustum culling on dynamically spawned meshes.
		mi2.extra_cull_margin = 8.0
		node = mi2

	node.scale    = Vector3.ONE * scale_f
	node.position = local_pos
	_ring_root.add_child(node)
	_orbs.append(node)
	_orb_mats.append(mat)
	_orb_emits.append(emit_mult)


# ── Blend tick ────────────────────────────────────────────────────────────────

func _tick_blend(delta: float) -> void:
	if _blend_t >= 1.0:
		_free_retiring()
		return

	_blend_t = minf(_blend_t + delta / BLEND_DURATION, 1.0)

	# ease-in for new orbs (accelerate into place), ease-out for old orbs.
	var t_in  : float = ease(_blend_t,       -1.8)
	var t_out : float = ease(1.0 - _blend_t,  1.8)

	# ── Retiring orbs: travel to target, shrink, fade ──────────────────────
	for entry in _retiring:
		var orb : Node3D = entry["node"]
		if not is_instance_valid(orb):
			continue

		# Position: lerp from start toward the assigned new-orb target.
		orb.position = entry["start_pos"].lerp(entry["target_pos"], 1.0 - t_out)

		# Alpha: fade out (no scale change — new orb covers them as they converge).
		var mat = entry["mat"]
		var em  : float = entry["emit_mult"]
		if mat is StandardMaterial3D:
			var c : Color = mat.albedo_color
			mat.albedo_color = Color(c.r, c.g, c.b, t_out)
			mat.emission     = Color(c.r, c.g, c.b, 1.0) * (em * t_out)

	# ── New orbs: grow in, fade in ─────────────────────────────────────────
	for i in _orbs.size():
		if not is_instance_valid(_orbs[i]):
			continue
		_orbs[i].scale = Vector3.ONE * (_target_orb_scale * t_in)
		if i < _orb_mats.size() and _orb_mats[i] is StandardMaterial3D:
			var c  : Color = _orb_mats[i].albedo_color
			var em : float = _orb_emits[i] if i < _orb_emits.size() else EMIT_ORB
			_orb_mats[i].albedo_color = Color(c.r, c.g, c.b, t_in)
			_orb_mats[i].emission     = Color(c.r, c.g, c.b, 1.0) * (em * t_in)


# ── Radius interpolation ──────────────────────────────────────────────────────

func _tick_radius(delta: float, tier: int) -> void:
	var target : float = 0.0 if tier == 100 else RADIUS_BY_COUNT.get(tier, 0.26)
	_current_radius = lerpf(_current_radius, target, delta * RADIUS_LERP_SPEED)

	var count : int = _orbs.size()
	if count == 0 or tier == 100:
		return
	for i in count:
		if not is_instance_valid(_orbs[i]):
			continue
		var base_angle : float = (TAU / count) * i
		_orbs[i].position = Vector3(
			sin(base_angle) * _current_radius,
			0.0,
			cos(base_angle) * _current_radius
		)


# ── Spin ──────────────────────────────────────────────────────────────────────

func _tick_spin(delta: float, tier: int, pool: float) -> void:
	if not _ring_root:
		return
	var speed : float = 0.0
	match tier:
		10: speed = lerpf(SPEED_BY_COUNT[10], SPEED_BY_COUNT[8],  pool / 20.0)
		8:  speed = lerpf(SPEED_BY_COUNT[8],  SPEED_BY_COUNT[6],  (pool - 20.0) / 20.0)
		6:  speed = lerpf(SPEED_BY_COUNT[6],  SPEED_BY_COUNT[4],  (pool - 40.0) / 20.0)
		4:  speed = lerpf(SPEED_BY_COUNT[4],  SPEED_BY_COUNT[2],  (pool - 60.0) / 20.0)
		2:  speed = lerpf(SPEED_BY_COUNT[2],  SPEED_BY_COUNT[2] * 2.0, (pool - 80.0) / 20.0)
		_:  speed = 1.0
	_ring_angle          += speed * delta
	_ring_root.rotation.y = _ring_angle


# ── Ready dim ─────────────────────────────────────────────────────────────────

func _tick_ready_dim(delta: float, pool: float) -> void:
	if not _was_ready:
		return
	# If the tier has already changed away from 100 (new orbs are a different
	# tier), stop immediately — don't repaint the incoming orbs.
	if _current_tier != 100:
		_was_ready = false
		return
	if pool < 99.0:
		_ready_alpha = maxf(0.0, _ready_alpha - READY_DIM_SPEED * delta)
		if _ready_alpha <= 0.0:
			_was_ready = false
		var dim_col := Color(C_READY.r, C_READY.g, C_READY.b, _ready_alpha)
		_set_orb_colour(dim_col, EMIT_READY * _ready_alpha)


func _set_orb_colour(col: Color, emit_mult: float = EMIT_ORB) -> void:
	for mat in _orb_mats:
		if mat is StandardMaterial3D:
			mat.albedo_color = col
			mat.emission     = Color(col.r, col.g, col.b, 1.0) * emit_mult


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
