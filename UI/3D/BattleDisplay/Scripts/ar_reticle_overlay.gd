extends CanvasLayer
## ARReticleOverlay — screen-space AI recognition reticle drawn over all BattleActors.
##
## Add as autoload (scene) so it persists across scenes.
## Each frame: finds all "battle_actor" group members, projects their bound anchors
## to screen space, and draws corner-bracket boxes with label chips.
##
## Per-actor data is stored in _boxes (Dictionary keyed by actor instance_id).
## When stats_revealed becomes true on an enemy, the box "draws in" via a tween.

# ── Tunables ──────────────────────────────────────────────────────────────────

## Fraction of each edge that is drawn as a corner bracket (0.0–0.5).
const CORNER_FRAC      := 0.22
## Extra screen-space padding around the projected AABB (pixels).
const BOX_PADDING      := 10.0
## Line thickness for bracket strokes.
const LINE_WIDTH       := 1.5
## How fast the box tracks the projected rect (lerp speed, units/sec).
const TRACK_SPEED      := 14.0
## Fake confidence jitter amplitude (percentage points).
const CONF_JITTER      := 3
## Label chip height in pixels.
const LABEL_H          := 18.0
## Label font size.
const LABEL_FONT_SIZE  := 11
## Corner tick: small inward bar that caps each corner bracket.
const TICK_LEN         := 4.0

# ── Colours ───────────────────────────────────────────────────────────────────
# Player team: cold cyan
const C_PLAYER         := Color(0.20, 0.90, 1.00, 0.92)
const C_PLAYER_FILL    := Color(0.20, 0.90, 1.00, 0.06)
const C_PLAYER_LABEL   := Color(0.05, 0.10, 0.14, 0.88)
# Enemy team: hot red-orange
const C_ENEMY          := Color(1.00, 0.32, 0.12, 0.92)
const C_ENEMY_FILL     := Color(1.00, 0.32, 0.12, 0.06)
const C_ENEMY_LABEL    := Color(0.14, 0.04, 0.02, 0.88)
# Targeted actor: bright white tint overlay
const C_TARGET         := Color(1.00, 1.00, 1.00, 1.00)

# ── Internal state ────────────────────────────────────────────────────────────

## Per-actor render entry:
## { actor, rect: Rect2, draw_progress: float 0-1, conf_base: int, label: String, visible: bool }
var _boxes : Dictionary = {}

## Draw node — a plain Control that calls queue_redraw each frame.
var _draw_node : Control

var _font : Font

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 100   # above game UI but below critical overlays
	_font = ThemeDB.fallback_font

	_draw_node = Control.new()
	_draw_node.name = "ARDrawSurface"
	_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_node.draw.connect(_on_draw)
	add_child(_draw_node)


func _process(delta: float) -> void:
	_sync_actors()
	_update_rects(delta)
	_draw_node.queue_redraw()


# ── Actor sync ────────────────────────────────────────────────────────────────

func _sync_actors() -> void:
	var current_ids : Array = []

	var tree := get_tree()
	if tree == null:
		return

	for actor in tree.get_nodes_in_group("battle_actor"):
		if not is_instance_valid(actor):
			continue
		var id : int = actor.get_instance_id()
		current_ids.append(id)

		if not _boxes.has(id):
			_register_actor(actor)

	# Remove stale entries (actor freed or left scene)
	for id in _boxes.keys():
		if id not in current_ids:
			_boxes.erase(id)


func _register_actor(actor) -> void:
	var is_enemy : bool = actor.get("team") == 1
	var label : String = actor.get("display_name")
	if label == "":
		label = actor.name
	var conf_base : int = randi_range(85, 97)

	_boxes[actor.get_instance_id()] = {
		"actor":         actor,
		"rect":          Rect2(Vector2.ZERO, Vector2.ZERO),
		"target_rect":   Rect2(Vector2.ZERO, Vector2.ZERO),
		"draw_progress": 0.0 if is_enemy else 1.0,   # enemies draw in on reveal
		"conf_base":     conf_base,
		"label":         label,
		"is_enemy":      is_enemy,
		"visible":       not is_enemy,   # enemies hidden until stats_revealed
	}


# ── Rect projection ───────────────────────────────────────────────────────────

func _update_rects(delta: float) -> void:
	var camera : Camera3D = _get_active_camera()
	if camera == null:
		return

	var vp_size : Vector2 = get_viewport().get_visible_rect().size

	for id in _boxes.keys():
		var entry : Dictionary = _boxes[id]
		var actor = entry["actor"]
		if not is_instance_valid(actor):
			continue

		# Check reveal state for enemies
		if entry["is_enemy"]:
			var revealed : bool = actor.get("stats_revealed") == true
			if revealed and entry["draw_progress"] < 1.0:
				entry["draw_progress"] = minf(entry["draw_progress"] + delta * 4.0, 1.0)
			entry["visible"] = revealed
		else:
			entry["visible"] = true

		if not entry["visible"]:
			continue

		# Collect projection points: BoundsBottom (feet) and BoundsTop (head), else AABB corners
		var world_points : Array = _get_bound_points(actor)
		if world_points.is_empty():
			continue

		var screen_min := Vector2(INF, INF)
		var screen_max := Vector2(-INF, -INF)
		var all_behind := true

		for wp in world_points:
			# Cull points behind the camera
			var to_point : Vector3 = wp - camera.global_position
			if to_point.dot(-camera.global_transform.basis.z) <= 0.0:
				continue
			all_behind = false
			var sp : Vector2 = camera.unproject_position(wp)
			screen_min = Vector2(minf(screen_min.x, sp.x), minf(screen_min.y, sp.y))
			screen_max = Vector2(maxf(screen_max.x, sp.x), maxf(screen_max.y, sp.y))

		if all_behind:
			entry["visible"] = false
			continue

		# Pad and clamp to viewport
		screen_min -= Vector2(BOX_PADDING, BOX_PADDING)
		screen_max += Vector2(BOX_PADDING, BOX_PADDING)

		var target := Rect2(screen_min, screen_max - screen_min)
		entry["target_rect"] = target

		# Smooth tracking lerp
		var cur : Rect2 = entry["rect"]
		if cur.size == Vector2.ZERO:
			entry["rect"] = target
		else:
			var lerp_t := clampf(TRACK_SPEED * 0.016, 0.0, 1.0)  # approx 60fps step
			entry["rect"] = Rect2(
				cur.position.lerp(target.position, lerp_t),
				cur.size.lerp(target.size, lerp_t)
			)


func _get_bound_points(actor) -> Array:
	## Tries BoundsTop / BoundsBottom markers first, then PartAnchors children,
	## then falls back to CameraAnchor ± 1m.
	var points : Array = []

	var bt : Node3D = actor.get_node_or_null("BoundsTop")
	var bb : Node3D = actor.get_node_or_null("BoundsBottom")
	if bt and bb:
		points.append(bt.global_position)
		points.append(bb.global_position)
		# Add slight width samples
		var right : Vector3 = actor.global_transform.basis.x * 0.3
		points.append(bt.global_position + right)
		points.append(bt.global_position - right)
		points.append(bb.global_position + right)
		points.append(bb.global_position - right)
		return points

	# Use PartAnchors children to build a tight AABB
	var pa : Node3D = actor.get_node_or_null("PartAnchors")
	if pa and pa.get_child_count() > 0:
		for child in pa.get_children():
			if child is Node3D:
				points.append(child.global_position)
		if points.size() > 0:
			# widen by half-body width
			var right : Vector3 = actor.global_transform.basis.x * 0.35
			var extras : Array = []
			for p in points:
				extras.append(p + right)
				extras.append(p - right)
			points.append_array(extras)
			return points

	# Fallback: CameraAnchor or self ± rough body half-extents
	var anchor : Node3D = actor.get_node_or_null("CameraAnchor")
	var base_pos : Vector3 = anchor.global_position if anchor else actor.global_position
	var right2 : Vector3 = actor.global_transform.basis.x * 0.35
	points.append(base_pos + Vector3(0,  0.6, 0) + right2)
	points.append(base_pos + Vector3(0,  0.6, 0) - right2)
	points.append(base_pos + Vector3(0, -0.6, 0) + right2)
	points.append(base_pos + Vector3(0, -0.6, 0) - right2)
	return points


# ── Camera lookup ─────────────────────────────────────────────────────────────

func _get_active_camera() -> Camera3D:
	var vp := get_viewport()
	if vp:
		var cam := vp.get_camera_3d()
		if cam:
			return cam
	return null


# ── Draw ──────────────────────────────────────────────────────────────────────

func _on_draw() -> void:
	var vp_rect : Rect2 = get_viewport().get_visible_rect()
	var t : float = Time.get_ticks_msec() * 0.001

	# Determine targeted actor (battle_manager.selected_target)
	var targeted_id : int = -1
	var mgr = _get_battle_manager()
	if mgr:
		var sel = mgr.get("selected_target")
		if is_instance_valid(sel):
			targeted_id = sel.get_instance_id()

	for id in _boxes.keys():
		var entry : Dictionary = _boxes[id]
		if not entry["visible"]:
			continue

		var rect : Rect2 = entry["rect"]
		if rect.size.x < 2.0 or rect.size.y < 2.0:
			continue

		var progress : float = entry["draw_progress"]
		var is_enemy : bool  = entry["is_enemy"]
		var is_targeted : bool = (id == targeted_id)

		var c_line  : Color = C_ENEMY   if is_enemy else C_PLAYER
		var c_fill  : Color = C_ENEMY_FILL  if is_enemy else C_PLAYER_FILL
		var c_lbl   : Color = C_ENEMY_LABEL if is_enemy else C_PLAYER_LABEL

		if is_targeted:
			c_line = C_TARGET.lerp(c_line, 0.35)

		c_line.a  *= progress
		c_fill.a  *= progress

		_draw_box(rect, c_line, c_fill, progress, vp_rect)
		_draw_label(rect, entry, c_line, c_lbl, t, progress)


func _draw_box(rect: Rect2, c_line: Color, c_fill: Color, progress: float, vp_rect: Rect2) -> void:
	var tl := rect.position
	var br := rect.end
	var w  := rect.size.x
	var h  := rect.size.y

	# Corner arm lengths — animate draw-in by shrinking arms from zero
	var cx := w * CORNER_FRAC * progress
	var cy := h * CORNER_FRAC * progress

	# Subtle fill
	_draw_node.draw_rect(rect, c_fill)

	# ── Four corner brackets ──
	# Top-left
	_draw_node.draw_line(tl, tl + Vector2(cx, 0),            c_line, LINE_WIDTH)
	_draw_node.draw_line(tl, tl + Vector2(0,  cy),           c_line, LINE_WIDTH)
	# Tick dots at corner
	_draw_node.draw_line(tl + Vector2(cx, 0), tl + Vector2(cx, TICK_LEN),  c_line, LINE_WIDTH)
	_draw_node.draw_line(tl + Vector2(0, cy), tl + Vector2(TICK_LEN, cy),  c_line, LINE_WIDTH)

	# Top-right
	var tr := Vector2(br.x, tl.y)
	_draw_node.draw_line(tr, tr + Vector2(-cx, 0),           c_line, LINE_WIDTH)
	_draw_node.draw_line(tr, tr + Vector2(0,   cy),          c_line, LINE_WIDTH)
	_draw_node.draw_line(tr + Vector2(-cx, 0), tr + Vector2(-cx, TICK_LEN), c_line, LINE_WIDTH)
	_draw_node.draw_line(tr + Vector2(0, cy),  tr + Vector2(-TICK_LEN, cy), c_line, LINE_WIDTH)

	# Bottom-left
	var bl := Vector2(tl.x, br.y)
	_draw_node.draw_line(bl, bl + Vector2(cx, 0),            c_line, LINE_WIDTH)
	_draw_node.draw_line(bl, bl + Vector2(0, -cy),           c_line, LINE_WIDTH)
	_draw_node.draw_line(bl + Vector2(cx, 0),  bl + Vector2(cx, -TICK_LEN),  c_line, LINE_WIDTH)
	_draw_node.draw_line(bl + Vector2(0, -cy), bl + Vector2(TICK_LEN, -cy),  c_line, LINE_WIDTH)

	# Bottom-right
	_draw_node.draw_line(br, br + Vector2(-cx, 0),           c_line, LINE_WIDTH)
	_draw_node.draw_line(br, br + Vector2(0,  -cy),          c_line, LINE_WIDTH)
	_draw_node.draw_line(br + Vector2(-cx, 0),  br + Vector2(-cx, -TICK_LEN),  c_line, LINE_WIDTH)
	_draw_node.draw_line(br + Vector2(0, -cy),  br + Vector2(-TICK_LEN, -cy),  c_line, LINE_WIDTH)


func _draw_label(rect: Rect2, entry: Dictionary, c_line: Color, c_label_bg: Color, t: float, progress: float) -> void:
	if progress < 0.3:
		return

	var alpha_fade : float = clampf((progress - 0.3) / 0.4, 0.0, 1.0)

	# Fluctuating confidence %
	var jitter : int = int(sin(t * 1.7 + entry["conf_base"] * 0.1) * CONF_JITTER)
	var conf   : int = clampi(entry["conf_base"] + jitter, 70, 99)
	var text   : String = "%s  %d%%" % [entry["label"].to_upper(), conf]

	# Measure text
	var font_size : int = LABEL_FONT_SIZE
	var text_w : float  = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var chip_w : float  = text_w + 10.0
	var chip_h : float  = LABEL_H

	# Position chip at top-left corner of box
	var chip_pos := rect.position + Vector2(0.0, -chip_h - 2.0)
	# Clamp to stay on screen
	chip_pos.x = clampf(chip_pos.x, 0.0, get_viewport().get_visible_rect().size.x - chip_w)
	chip_pos.y = clampf(chip_pos.y, 0.0, get_viewport().get_visible_rect().size.y - chip_h)

	var chip_rect := Rect2(chip_pos, Vector2(chip_w, chip_h))

	# Background chip
	var bg := c_label_bg
	bg.a *= alpha_fade
	_draw_node.draw_rect(chip_rect, bg)

	# Chip border (same colour as bracket)
	var bc := c_line
	bc.a *= alpha_fade * 0.6
	_draw_node.draw_rect(chip_rect, bc, false, 1.0)

	# Text
	var text_col := c_line
	text_col.a *= alpha_fade
	_draw_node.draw_string(
		_font,
		chip_pos + Vector2(5.0, chip_h - 5.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		text_col
	)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_battle_manager() -> Node:
	var tree := get_tree()
	if tree:
		return tree.get_first_node_in_group("battle_manager")
	return null
