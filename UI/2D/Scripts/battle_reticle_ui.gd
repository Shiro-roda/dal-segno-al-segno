extends CanvasLayer
## BattleReticleUI — AI-detection-box style battle targeting overlay.
##
## Aesthetic: flat unfilled rectangles floating in negative screen space,
## each connected by a thin line to its assigned 3D anchor point.
## Labels sit beside the floating box.
##
## Interaction:
##   Click a floating box → it tweens along the line to land over its anchor.
##   Label stays at the float end and expands into detail lines.
##   Clicking another option at the same depth → previous box tweens back,
##   new one tweens forward.
##
## Signals: skill_selected(skill), target_selected(target),
##          part_selected(part), confirmed, cancelled.

signal skill_selected(skill: Dictionary)
signal target_selected(target: BattleActor)
signal focus_requested(target: BattleActor)
signal part_selected(part: BodyPartData)
signal confirmed
signal cancelled
signal repeat_action  # emitted when the player presses the repeat button

# ── Colours ───────────────────────────────────────────────────────────────────
# Neon palette — one hue per slot, cycling through the set
const NEON_PALETTE : Array = [
	Color(0.00, 1.00, 0.85, 1.0),   # cyan
	Color(1.00, 0.10, 0.70, 1.0),   # magenta
	Color(0.15, 1.00, 0.15, 1.0),   # green
	Color(1.00, 0.55, 0.00, 1.0),   # orange
	Color(0.45, 0.15, 1.00, 1.0),   # violet
	Color(1.00, 1.00, 0.10, 1.0),   # yellow
]
const C_DETAIL      := Color(0.85, 0.90, 0.95, 0.92)
const C_PANEL_BG    := Color(0.02, 0.02, 0.06, 0.90)
const FONT_PATH     := "res://UI/Themes/Fonts/SpaceMono-Bold.ttf"
const FONT_SIZE_LBL := 13
const FONT_SIZE_DET := 12

# ── Box geometry ──────────────────────────────────────────────────────────────
# Tweak these to resize and reposition everything.
const BOX_W         := 54.0    # box size — BOX_H is ignored, squares enforced in draw
const BOX_H         := 54.0    # keep equal to BOX_W
const LINE_W        := 1.5
const TWEEN_TIME    := 0.35
const LABEL_PAD     := 7.0
const DRIFT_SPEED        := 3.5    # orbit drift speed
const DRIFT_SPEED_SEL    := 5.0    # selected travel speed — fast but visible
const DRIFT_SPEED_PUSH   := 5.0    # speed when pushed to edge

# ── Float orbit ───────────────────────────────────────────────────────────────
# Boxes float in a slow elliptical drift around the anchor rather than a
# fixed position. Amplitude and speed control how wide/fast the orbit is.
const ORBIT_RADIUS_X := 55.0   # pixels of horizontal wander from anchor
const ORBIT_RADIUS_Y := 40.0   # pixels of vertical wander from anchor
const ORBIT_SPEED    := 0.40   # radians/sec of the orbit cycle
# How far to pull the orbit centre toward the viewport centre (0=raw anchor, 1=vp centre)
const ORBIT_CENTRE_BIAS        := 0.55  # skills — cluster near centre
const ORBIT_CENTRE_BIAS_ENTITY := 0.20  # enemies/allies — stay near their anchor
# Each box gets a unique orbit phase so they don't all move in sync.
# Phase is seeded from the palette index at creation time.

# ── Trail ─────────────────────────────────────────────────────────────────────
const TRAIL_LEN     := 8       # number of ghost copies
const TRAIL_STEP    := 0.03    # seconds between trail samples

# ── Rotation ──────────────────────────────────────────────────────────────────
const ROT_SPEED     := 1.8     # radians/sec while in motion
const ROT_SNAP_SPD  := 10.0    # high value = crisp snap when landing

# ── Viewport layout ───────────────────────────────────────────────────────────
const LEFT_VP_X  := 0.0
const LEFT_VP_W  := 638.0
const RIGHT_VP_X := 642.0
const RIGHT_VP_W := 638.0

# ── State ─────────────────────────────────────────────────────────────────────
var _active            : bool = false
var _font              : Font = null
var _support_targeting : bool = false  # true = show allies, hide enemies

var _left_cam     : Camera3D = null
var _right_cam    : Camera3D = null
var _actor        : BattleActor = null
var _skills       : Array = []
var _enemies      : Array = []
var _allies       : Array = []
var _removed_mask : int = 0

var _sel_skill    : Dictionary = {}
var _sel_target   : BattleActor = null
var _sel_part     : BodyPartData = null

# Each entry: {box: Control, anchor_screen: Vector2, float_pos: Vector2,
#              label: String, data: Variant, tween: Tween, at_anchor: bool,
#              detail_lines: Array[Label]}
var _skill_boxes     : Array = []
var _enemy_boxes     : Array = []
var _ally_boxes      : Array = []
var _part_boxes      : Array = []
var _struggle_box    : Dictionary = {}
var _repeat_btn      : Button = null   # the REPEAT action button; null when not shown
var _repeat_lbl      : Control = null  # label panel paired with repeat button
var _tense_phase     : bool  = false
var _palette_counter : int   = 0
var _time            : float = 0.0

var _draw_node    : Node2D = null

## Set before calling open() to choose the colour scheme.
var reticle_theme : ReticleTheme = null
var _default_theme : ReticleTheme = null


func _active_theme() -> ReticleTheme:
	if reticle_theme != null:
		return reticle_theme
	if _default_theme == null:
		_default_theme = ReticleTheme.new()  # default = VAPORWAVE
	return _default_theme


func _ready() -> void:
	layer = 25
	_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	_draw_node = Node2D.new()
	_draw_node.name = "Lines"
	add_child(_draw_node)
	_draw_node.draw.connect(_on_draw)
	hide()


# ── Public API ────────────────────────────────────────────────────────────────

func open(actor: BattleActor, skills: Array, enemies: Array, allies: Array,
		removed_mask: int, left_cam: Camera3D, right_cam: Camera3D,
		tense_phase: bool = false, can_repeat: bool = false) -> void:
	_actor             = actor
	_skills            = skills
	_enemies           = enemies
	_allies            = allies
	_removed_mask      = removed_mask
	_left_cam          = left_cam
	_right_cam         = right_cam
	_sel_skill         = {}
	_sel_target        = null
	_sel_part          = null
	_support_targeting = false
	_tense_phase       = tense_phase
	_active            = true
	_clear_all_boxes()
	_clear_struggle_box()
	show()
	_build_skill_boxes()
	_build_enemy_boxes()
	_build_ally_boxes()
	if can_repeat:
		_build_repeat_button()
	else:
		_clear_repeat_button()


func close(silent: bool = false) -> void:
	_active = false
	_clear_all_boxes()
	_clear_struggle_box()
	_clear_repeat_button()
	_hide_filter_panel()
	hide()
	if not silent:
		emit_signal("cancelled")


## Reset all selections back to idle floating state without destroying boxes.
func reset_selection() -> void:
	_hide_filter_panel()
	_sel_skill  = {}
	_sel_target = null
	_sel_part   = null
	for e in _skill_boxes + _enemy_boxes + _ally_boxes + _part_boxes:
		e["selected"]  = false
		e["at_anchor"] = false
		e["edge_push"] = false
		_hide_detail(e)
	_clear_boxes(_part_boxes)
	set_support_targeting(false)
	emit_signal("cancelled")


## Hide/show skill boxes without destroying them (e.g. during enemy turns).
func set_skills_visible(visible_: bool) -> void:
	if not visible_:
		# Collapse any expanded skill details and reset state before hiding
		for e in _skill_boxes:
			e["selected"]  = false
			e["at_anchor"] = false
			_hide_detail(e)
		_sel_skill  = {}
		_sel_target = null
		_sel_part   = null
		_clear_struggle_box()
		_clear_boxes(_part_boxes)
		for eb in _enemy_boxes:
			eb["selected"]  = false
			eb["at_anchor"] = false
			eb["edge_push"] = false
			_hide_detail(eb)
	for e in _skill_boxes:
		var b : Button = e["box"]
		var lp : Control = e["label_panel"]
		if is_instance_valid(b):  b.visible  = visible_
		if is_instance_valid(lp): lp.visible = visible_


## Restrict which command keys are selectable. Empty array = all allowed.
var _allowed_commands : Array = []
func set_allowed_commands(keys: Array) -> void:
	_allowed_commands = keys
	for e in _skill_boxes:
		var sk : Dictionary = e["data"]
		var key : String = sk.get("key", "")
		var allowed : bool = keys.is_empty() or key in keys
		var b : Button = e["box"]
		if is_instance_valid(b):
			b.mouse_filter = Control.MOUSE_FILTER_STOP if allowed else Control.MOUSE_FILTER_IGNORE
		# Dim the box visually when locked
		e["_locked"] = not allowed


# ── Channel filter panel ──────────────────────────────────────────────────────
# Three RGB buttons shown when Kendall's "special" (Change Lens) is chosen.
# Emits filter_selected(channel_int) then hides itself.

signal filter_selected(channel: int)

var _filter_panel : Control = null

func show_filter_options(removed_mask: int = 0) -> void:
	_hide_filter_panel()
	var panel := PanelContainer.new()
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.02, 0.02, 0.06, 0.92)
	sbox.set_border_width_all(1)
	sbox.border_color = Color(0.25, 0.25, 0.35, 1.0)
	sbox.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sbox)
	panel.set_anchor(SIDE_LEFT,   0.5)
	panel.set_anchor(SIDE_RIGHT,  0.5)
	panel.set_anchor(SIDE_TOP,    0.5)
	panel.set_anchor(SIDE_BOTTOM, 0.5)
	panel.set_offset(SIDE_LEFT,   -130)
	panel.set_offset(SIDE_RIGHT,   130)
	panel.set_offset(SIDE_TOP,    -48)
	panel.set_offset(SIDE_BOTTOM,  48)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	panel.add_child(hbox)
	var channels := [
		{"label": "R", "channel": 1, "color": Color(1.0, 0.25, 0.25, 1.0)},
		{"label": "G", "channel": 2, "color": Color(0.25, 1.0, 0.35, 1.0)},
		{"label": "B", "channel": 4, "color": Color(0.25, 0.55, 1.0, 1.0)},
	]
	for ch in channels:
		var btn := Button.new()
		btn.text = ch["label"]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(60, 54)
		var already_used : bool = (removed_mask & int(ch["channel"])) != 0
		if _font: btn.add_theme_font_override("font", _font)
		btn.add_theme_font_size_override("font_size", 18)
		var col : Color = ch["color"]
		var normal_sbox := StyleBoxFlat.new()
		normal_sbox.bg_color = Color(col.r * 0.15, col.g * 0.15, col.b * 0.15, 1.0)
		normal_sbox.set_border_width_all(1)
		normal_sbox.border_color = Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 1.0)
		normal_sbox.set_content_margin_all(6)
		var hover_sbox := StyleBoxFlat.new()
		hover_sbox.bg_color = Color(col.r * 0.30, col.g * 0.30, col.b * 0.30, 1.0)
		hover_sbox.set_border_width_all(1)
		hover_sbox.border_color = col
		hover_sbox.set_content_margin_all(6)
		btn.add_theme_stylebox_override("normal",   normal_sbox)
		btn.add_theme_stylebox_override("hover",    hover_sbox)
		btn.add_theme_stylebox_override("pressed",  hover_sbox)
		btn.add_theme_stylebox_override("focus",    normal_sbox)
		btn.add_theme_stylebox_override("disabled", normal_sbox)
		btn.add_theme_color_override("font_color",          col)
		btn.add_theme_color_override("font_hover_color",    Color.WHITE)
		btn.add_theme_color_override("font_pressed_color",  Color.WHITE)
		btn.add_theme_color_override("font_disabled_color", Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, 1.0))
		btn.disabled = already_used
		var cap_ch : int = int(ch["channel"])
		btn.pressed.connect(func():
			_hide_filter_panel()
			emit_signal("filter_selected", cap_ch)
		)
		hbox.add_child(btn)
	add_child(panel)
	_filter_panel = panel


func _hide_filter_panel() -> void:
	if is_instance_valid(_filter_panel):
		_filter_panel.queue_free()
	_filter_panel = null


## Switch between enemy targeting and ally targeting.
## Enemy boxes are blocked during support; ally boxes are always clickable.
func set_support_targeting(support: bool) -> void:
	_support_targeting = support
	for e in _enemy_boxes:
		var b : Button = e["box"]
		if is_instance_valid(b):
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE if support else Control.MOUSE_FILTER_STOP


# ── Frame update ──────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	_refresh_anchor_positions()
	_update_drift(delta)
	_repulse_boxes()
	_update_struggle_box_position(delta)
	_draw_node.queue_redraw()


func _repulse_boxes() -> void:
	# Gather all active boxes into flat arrays grouped by viewport
	var left_boxes  : Array = []
	var right_boxes : Array = []
	for e in _skill_boxes + _ally_boxes + _part_boxes:
		left_boxes.append(e)
	for e in _enemy_boxes:
		right_boxes.append(e)
	const MIN_DIST : float = BOX_W * 1.3
	for group in [left_boxes, right_boxes]:
		for i in group.size():
			for j in range(i + 1, group.size()):
				var a : Dictionary = group[i]
				var b : Dictionary = group[j]
				var diff : Vector2 = (a["display_pos"] as Vector2) - (b["display_pos"] as Vector2)
				var dist : float = diff.length()
				if dist < MIN_DIST and dist > 0.001:
					var push : Vector2 = diff.normalized() * (MIN_DIST - dist) * 0.5
					# Don’t push selected boxes off their anchor
					if not a["selected"]:
						a["display_pos"] = (a["display_pos"] as Vector2) + push
					if not b["selected"]:
						b["display_pos"] = (b["display_pos"] as Vector2) - push


func _update_drift(delta: float) -> void:
	var all_sets : Array = [_skill_boxes, _enemy_boxes, _ally_boxes, _part_boxes]
	for set_ in all_sets:
		for e in set_:
			var box : Button = e["box"]
			if not is_instance_valid(box):
				continue
			var lbl_panel : Control = e["label_panel"]

			# ── Live part-HP label refresh ───────────────────────────────────
			if e["data_type"] == "part":
				var part := e["data"] as BodyPartData
				if part != null and part.has_part_hp():
					var fresh := part.part_name + "  %d/%d" % [part.current_part_hp, part.max_part_hp]
					if e["label"] != fresh:
						e["label"] = fresh
						var lbl_node : Label = e.get("label_node")
						if is_instance_valid(lbl_node):
							lbl_node.text = fresh.to_upper()

			# ── Position drift ──────────────────────────────────────────────
			# Determine which viewport this box lives in and its centre
			var is_right : bool = e["is_enemy"]
			var vp_x  : float = RIGHT_VP_X if is_right else LEFT_VP_X
			var vp_w  : float = RIGHT_VP_W if is_right else LEFT_VP_W
			var vp_cx : float = vp_x + vp_w * 0.5
			var vp_cy : float = 480.0   # vertical centre target
			var vp_centre := Vector2(vp_cx, vp_cy)

			# ── Off-screen snap: entity boxes and off-screen skills park in a corner row ───────
			var is_entity : bool = e["data_type"] in ["enemy", "ally", "part"]
			if (is_entity or e["data_type"] == "skill") and e.get("off_screen", false):
				var park : Vector2 = e.get("park_pos", e["display_pos"])
				e["display_pos"] = (e["display_pos"] as Vector2).lerp(park, clamp(20.0 * delta, 0.0, 1.0))
				var dp2 : Vector2 = e["display_pos"]
				box.position = dp2 - box.size * 0.5
				if is_instance_valid(lbl_panel):
					var lbl_x : float
					if e["data_type"] == "enemy":
						lbl_x = dp2.x - BOX_W * 0.5 - LABEL_PAD - lbl_panel.size.x
					else:
						# allies and skills: label to the right
						lbl_x = dp2.x + BOX_W * 0.5 + LABEL_PAD
					lbl_panel.position = Vector2(lbl_x, dp2.y - BOX_H * 0.5)
				continue

			# ── Target and speed ────────────────────────────────────────
			# Skill boxes bias toward the right edge of the left viewport
			var is_skill : bool = e["data_type"] == "skill"
			var sr : Rect2 = e.get("screen_rect", Rect2())
			var has_rect : bool = is_entity and sr.size.x > 4.0
			var bias : float = ORBIT_CENTRE_BIAS if is_skill else ORBIT_CENTRE_BIAS_ENTITY
			var orbit_bias_target : Vector2 = vp_centre
			if not is_right and is_skill:
				orbit_bias_target = Vector2(LEFT_VP_X + LEFT_VP_W * 0.82, vp_cy)
			var orbit_origin : Vector2 = e["anchor_screen"].lerp(orbit_bias_target, bias)
			var orbit_angle  : float   = _time * ORBIT_SPEED + float(e["orbit_phase"])
			var orbit_offset := Vector2(cos(orbit_angle) * ORBIT_RADIUS_X,
										sin(orbit_angle * 0.7) * ORBIT_RADIUS_Y)
			var target_centre : Vector2
			var spd : float
			if has_rect:
				# Entity boxes always track the projected model rect centre directly
				target_centre = sr.get_center()
				spd = 18.0  # snap tightly so bracket follows animation
			elif e["selected"]:
				if is_right and e["data_type"] == "enemy":
					target_centre = Vector2(vp_x + BOX_W * 1.2, e["anchor_screen"].y)
				else:
					target_centre = e["anchor_screen"]
				spd = DRIFT_SPEED_SEL
			elif e.get("edge_push", false):
				var push_x : float = vp_x + vp_w * 0.25 + float(e["orbit_phase"]) * 40.0
				var push_y : float = BOX_W * 1.5
				target_centre = Vector2(push_x, push_y)
				spd = DRIFT_SPEED_PUSH
			else:
				target_centre = orbit_origin + orbit_offset
				spd = DRIFT_SPEED
			var prev_dp : Vector2 = e["display_pos"]
			var raw_dp  : Vector2 = prev_dp.lerp(target_centre, clamp(spd * delta, 0.0, 1.0))
			var half_s  : float = BOX_W * 0.5
			var clamped_x : float = clamp(raw_dp.x, vp_x + half_s, vp_x + vp_w - half_s)
			var clamped_y : float = clamp(raw_dp.y, half_s, 960.0 - half_s)
			e["display_pos"] = Vector2(clamped_x, clamped_y)
			var dp : Vector2 = e["display_pos"]
			var velocity : float = dp.distance_to(prev_dp) / max(delta, 0.001)
			# Advance spawn animation
			if float(e["spawn_anim"]) < 1.0:
				e["spawn_anim"] = minf(float(e["spawn_anim"]) + delta / 0.4, 1.0)

			# ── Rotation ─────────────────────────────────────────────────
			# Roll along the line to anchor only while selected and moving.
			var moving : bool = velocity > 2.0
			# Roll while selected and far from anchor; snap once close enough
			var dist_to_anchor : float = dp.distance_to(e["anchor_screen"])
			if e["selected"] and dist_to_anchor > 8.0:
				var move_vec  : Vector2 = dp - prev_dp
				var to_anchor : Vector2 = e["anchor_screen"] - dp
				var roll_sign : float   = sign(move_vec.dot(to_anchor.normalized()))
				e["box_rot"] = float(e["box_rot"]) + roll_sign * (velocity * 0.0009)
			else:
				var r : float = float(e["box_rot"])
				var target_r : float = round(r / (PI * 0.5)) * (PI * 0.5)
				e["box_rot"] = r + (target_r - r) * clamp(ROT_SNAP_SPD * delta, 0.0, 1.0)

			# ── Click pulse decay ───────────────────────────────────────
			if float(e["click_pulse"]) > 0.0:
				e["click_pulse"] = max(0.0, float(e["click_pulse"]) - delta * 3.0)

			# ── Trail sampling ──────────────────────────────────────────
			e["trail_timer"] = float(e["trail_timer"]) - delta
			if not has_rect and e["selected"] and moving and float(e["trail_timer"]) <= 0.0:
				e["trail_timer"] = TRAIL_STEP
				var trail : Array = e["trail"]
				trail.push_front({"pos": dp, "rot": float(e["box_rot"])})
				if trail.size() > TRAIL_LEN:
					trail.resize(TRAIL_LEN)
			if not moving:
				# Fade trail away when stopped
				var trail : Array = e["trail"]
				if not trail.is_empty():
					trail.pop_back()

			# ── Node positions + label alpha ─────────────────────────────
			# Match label visibility to box: selected=bright, push=dim, float=mid
			var lbl_alpha : float
			if e["selected"]:
				lbl_alpha = 1.0
			elif e.get("edge_push", false):
				lbl_alpha = 0.55
			else:
				lbl_alpha = 0.75
			# Apply colour to the label text every frame so it resets cleanly
			# when toggling between modes. Allies turn green and enemies turn
			# red when selected; all other states use white at varying alpha.
			var lbl_node2 : Label = e.get("label_node")
			if is_instance_valid(lbl_node2):
				var lbl_col : Color
				if e["selected"]:
					match e["data_type"]:
						"ally":  lbl_col = Color(0.30, 1.00, 0.45, 1.0)
						"enemy": lbl_col = Color(1.00, 0.28, 0.28, 1.0)
						_:       lbl_col = Color(1.0, 1.0, 1.0, 1.0)
				else:
					lbl_col = Color(1.0, 1.0, 1.0, lbl_alpha)
				lbl_node2.add_theme_color_override("font_color", lbl_col)
			var t_sec2    : float = Time.get_ticks_msec() * 0.001
			var coloured2 : bool  = e["data_type"] == "skill" or not _sel_skill.is_empty()
			var th2       : ReticleTheme = _active_theme()
			var neon2     : Color = th2.get_neon(e["data_type"], int(e.get("palette_idx", 0)))
			var cycle2    : bool  = coloured2 and th2.allow_hue_cycle()
			var pulse2    : float = 0.70 + 0.30 * sin(t_sec2 * 1.8 + neon2.h * TAU)
			# Label text is always white; panel carries the colour when active
			if is_instance_valid(lbl_panel) and lbl_panel is ColorRect:
				var cr := lbl_panel as ColorRect
				if coloured2:
					if cycle2:
						var hue2 : float = fmod(neon2.h + t_sec2 * 0.08 + float(e.get("orbit_phase", 0.0)) * 0.05, 1.0)
						var comp2 : float = fmod(hue2 + 0.5, 1.0)
						var panel_val : float = 0.38 + 0.10 * sin(t_sec2 * 1.1 + comp2 * TAU)
						cr.color = Color.from_hsv(comp2, 0.80, panel_val, 1.0)
					else:
						var fade : float = 0.25
						cr.color = Color(neon2.r * fade, neon2.g * fade, neon2.b * fade, 1.0)
				else:
					cr.color = Color(0.08, 0.08, 0.08, 1.0)
			var e_sr : Rect2 = e.get("screen_rect", Rect2())
			var e_is_entity : bool = e["data_type"] in ["enemy", "ally", "part"]
			var e_has_rect  : bool = e_is_entity and e_sr.size.x > 4.0
			# Clip the screen rect to the entity's viewport, matching the draw section.
			var e_lbl_vp_x : float = RIGHT_VP_X if e["is_enemy"] else LEFT_VP_X
			var e_lbl_vp_w : float = RIGHT_VP_W if e["is_enemy"] else LEFT_VP_W
			var e_vp_rect  := Rect2(e_lbl_vp_x, 0, e_lbl_vp_w, 960.0)
			var e_clipped  : Rect2 = e_sr.intersection(e_vp_rect) if e_has_rect else e_sr
			# Button hit area always tracks display_pos at BOX size — screen_rect
			# is used only for drawing corner brackets, never for the click region.
			box.position = dp - box.size * 0.5
			if is_instance_valid(lbl_panel):
				# modulate drives all alpha — don’t encode it in the stylebox too
				lbl_panel.modulate = Color.WHITE
				var lp : Vector2
				var dtype2 : String = e["data_type"]
				const _P := 4.0
				var lv : VBoxContainer = e.get("label_vbox")
				if is_instance_valid(lv):
					var lv_min := lv.get_minimum_size()
					lbl_panel.size = Vector2(lv_min.x + _P * 2.0, lv_min.y + _P * 2.0)
				if dtype2 == "enemy" and e_has_rect:
					# Enemy maximised: label right of the projected bracket.
					var lbl_x := e_clipped.position.x + e_clipped.size.x + LABEL_PAD
					lbl_x = clampf(lbl_x, e_lbl_vp_x + LABEL_PAD, e_lbl_vp_x + e_lbl_vp_w - 150.0)
					lp = Vector2(lbl_x, e_clipped.position.y)
				elif dtype2 == "enemy":
					# Enemy floating/minimised: label left of the box.
					lp = dp + Vector2(-(lbl_panel.size.x + LABEL_PAD), -BOX_H * 0.5)
				else:
					# Allies, skills, parts: label always right of the box.
					lp = dp + Vector2(BOX_W * 0.5 + LABEL_PAD, -BOX_H * 0.5)
				lbl_panel.position = lp
				for j in e["detail_nodes"].size():
					var dn : Control = e["detail_nodes"][j]
					if is_instance_valid(dn):
						dn.position = lp + Vector2(0.0, lbl_panel.size.y + float(j) * 22.0)


# ── Projection ────────────────────────────────────────────────────────────────

func _project(world_pos: Vector3, cam: Camera3D, vp_x: float) -> Vector2:
	if cam == null or not is_instance_valid(cam):
		return Vector2(-9999, -9999)
	# If the point is behind the camera, unproject_position returns garbage.
	# Detect this via the sign of the dot product with the camera's forward axis.
	var to_point : Vector3 = world_pos - cam.global_position
	var forward  : Vector3 = -cam.global_transform.basis.z  # Godot: -Z is forward
	if to_point.dot(forward) <= 0.0:
		return Vector2(-9999, -9999)
	var p : Vector2 = cam.unproject_position(world_pos)
	return Vector2(vp_x + p.x, p.y)


func _anchor_screen(anchor: Node3D, is_enemy: bool) -> Vector2:
	var cam := _right_cam if is_enemy else _left_cam
	var ox  := RIGHT_VP_X if is_enemy else LEFT_VP_X
	return _project(anchor.global_position, cam, ox)


## Returns the parked position for an off-screen entity box.
## Enemies park in a row at the top-right of the right viewport.
## Allies and skills share a column at the left edge of the left viewport.
func _offscreen_park_pos(slot_index: int, is_enemy: bool) -> Vector2:
	const SLOT_H : float = BOX_H + 6.0
	const MARGIN : float = 8.0
	var y : float = BOX_H * 0.5 + MARGIN + float(slot_index) * SLOT_H
	var x : float
	if is_enemy:
		# Right edge of right viewport — label will go to the left of the box
		x = RIGHT_VP_X + RIGHT_VP_W - BOX_W * 0.5 - MARGIN
	else:
		# Left edge of left viewport — allies and skills share this column
		x = LEFT_VP_X + BOX_W * 0.5 + MARGIN
	return Vector2(x, y)


# ── Box building ──────────────────────────────────────────────────────────────

func _build_skill_boxes() -> void:
	if not is_instance_valid(_actor):
		return
	# Distribute floats evenly in the left viewport's negative space
	# (roughly the upper-left quadrant, away from the character)
	var n := _skills.size()
	for i in n:
		var sk : Dictionary = _skills[i]
		var anchor : Node3D = _actor.get_skill_anchor(sk)
		var float_pos := _skill_float_pos(i, n)
		var lbl : String = str(sk.get("name", sk.get("key", "?")))
		var entry := _make_box_entry(float_pos, lbl, sk, false, "skill")
		_skill_boxes.append(entry)


func _build_enemy_boxes() -> void:
	var n := _enemies.size()
	for i in n:
		var enemy : BattleActor = _enemies[i]
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var float_pos := _enemy_float_pos(i, n)
		var entry := _make_box_entry(float_pos, enemy.display_name, enemy, true, "enemy")
		# Seed display_pos at the actual anchor so no jump occurs
		var ca := enemy.get_node_or_null("CameraAnchor")
		var anchor_node : Node3D = ca if ca is Node3D else enemy
		var initial_pos : Vector2 = _anchor_screen(anchor_node, true)
		if initial_pos.x > -9000:  # valid projection
			entry["anchor_screen"] = initial_pos
			entry["display_pos"]   = initial_pos
			# Seed screen_rect immediately so first-frame size is correct
			entry["screen_rect"] = enemy.get_screen_rect(_right_cam, RIGHT_VP_X)
		_enemy_boxes.append(entry)


func _build_ally_boxes() -> void:
	var n := _allies.size()
	for i in n:
		var ally : BattleActor = _allies[i]
		if not is_instance_valid(ally) or not ally.is_alive():
			continue
		var float_pos := _ally_float_pos(i, n)
		var entry := _make_box_entry(float_pos, ally.display_name, ally, true, "ally")
		# Ally boxes are always clickable — they show details when no skill
		# is selected, and act as targets when a support skill is selected.
		# Seed screen_rect, display_pos, and anchor immediately.
		var ca := ally.get_node_or_null("CameraAnchor")
		var anchor_node : Node3D = ca if ca is Node3D else ally
		var initial_pos : Vector2 = _anchor_screen(anchor_node, true)
		if initial_pos.x > -9000:
			entry["anchor_screen"] = initial_pos
			entry["display_pos"]   = initial_pos
			entry["screen_rect"]   = ally.get_screen_rect(_right_cam, RIGHT_VP_X)
		_ally_boxes.append(entry)


func _build_part_boxes() -> void:
	_clear_boxes(_part_boxes)
	if not is_instance_valid(_sel_target):
		return
	var parts := _sel_target.get_visible_parts(_removed_mask)
	var n := parts.size()
	for i in n:
		var part : BodyPartData = parts[i]
		var float_pos := _part_float_pos(i, n)
		var lbl := part.part_name
		if part.has_part_hp():
			lbl += "  %d/%d" % [part.current_part_hp, part.max_part_hp]
		var entry := _make_box_entry(float_pos, lbl, part, true, "part")
		_part_boxes.append(entry)


# ── Float position layouts ────────────────────────────────────────────────────
# Spawn positions — boxes drift to orbit their anchors from here.
# Edit ORBIT_RADIUS_X/Y at the top to tune wander distance.
func _skill_float_pos(i: int, _n: int) -> Vector2:
	# Spawn near the right edge of the left viewport
	var phase : float = float(i) * (TAU / 5.0)
	return Vector2(LEFT_VP_X + LEFT_VP_W * 0.82 + cos(phase) * 55.0,
				   480.0 + sin(phase) * 120.0)


func _enemy_float_pos(i: int, _n: int) -> Vector2:
	var phase : float = float(i) * (TAU / 5.0) + 0.9
	return Vector2(RIGHT_VP_X + RIGHT_VP_W * 0.5 + cos(phase) * 160.0,
				   380.0 + sin(phase) * 180.0)


func _part_float_pos(i: int, n: int) -> Vector2:
	var phase : float = (float(i) / max(n, 1)) * TAU
	return Vector2(RIGHT_VP_X + RIGHT_VP_W * 0.5 + cos(phase) * 110.0,
				   480.0 + sin(phase) * 110.0)


func _ally_float_pos(i: int, _n: int) -> Vector2:
	var phase : float = float(i) * (TAU / 5.0) + 1.2
	return Vector2(RIGHT_VP_X + RIGHT_VP_W * 0.5 + cos(phase) * 120.0,
				   600.0 + sin(phase) * 100.0)


# ── Box entry factory ─────────────────────────────────────────────────────────

func _make_box_entry(float_pos: Vector2, label: String,
		data: Variant, is_enemy: bool, data_type_hint: String = "",
		press_override: Callable = Callable()) -> Dictionary:
	var palette_idx : int = _palette_counter
	_palette_counter += 1
	var dtype_for_neon : String = data_type_hint if data_type_hint != "" else ("skill" if data is Dictionary else "enemy")
	var neon : Color = _active_theme().get_neon(dtype_for_neon, palette_idx)
	# Root control — invisible, just a container for the hit area
	var box := Button.new()
	box.flat        = true
	box.focus_mode  = Control.FOCUS_NONE
	box.custom_minimum_size = Vector2(BOX_W, BOX_H)
	box.size        = Vector2(BOX_W, BOX_H)
	box.position    = float_pos - Vector2(BOX_W * 0.5, BOX_H * 0.5)
	# Fully transparent stylebox — click area only
	var sbox := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus"]:
		box.add_theme_stylebox_override(k, sbox)
	add_child(box)

	const LBL_MAX_W := 140.0
	const LBL_PAD   := 4.0
	var lbl_offset  := Vector2(BOX_W * 0.5 + LABEL_PAD, -BOX_H * 0.5)

	# Measure natural (unwrapped) label width first.
	var measure_lbl := Label.new()
	measure_lbl.text = label.to_upper()
	measure_lbl.add_theme_font_size_override("font_size", FONT_SIZE_LBL)
	if _font: measure_lbl.add_theme_font_override("font", _font)
	add_child(measure_lbl)  # must be in tree to measure
	var natural_w : float = measure_lbl.get_minimum_size().x
	remove_child(measure_lbl)
	measure_lbl.queue_free()
	var col_w : float = minf(natural_w, LBL_MAX_W)

	var lbl_panel := ColorRect.new()
	lbl_panel.color = Color(0.08, 0.08, 0.08, 1.0)
	lbl_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_panel.position = float_pos + lbl_offset
	add_child(lbl_panel)

	# VBoxContainer is child of ColorRect — positioned at (0,0) inside it.
	# We set lbl_panel.size manually each frame from lbl_vbox.get_minimum_size().
	var lbl_vbox := VBoxContainer.new()
	lbl_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_vbox.add_theme_constant_override("separation", 2)
	lbl_vbox.position = Vector2(LBL_PAD, LBL_PAD)
	lbl_vbox.size = Vector2(col_w, 0.0)
	lbl_panel.add_child(lbl_vbox)

	var lbl_node := Label.new()
	lbl_node.text = label.to_upper()
	lbl_node.add_theme_font_size_override("font_size", FONT_SIZE_LBL)
	if _font: lbl_node.add_theme_font_override("font", _font)
	lbl_node.add_theme_color_override("font_color", Color.WHITE)
	lbl_node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_node.custom_minimum_size = Vector2(col_w, 0.0)
	lbl_vbox.add_child(lbl_node)

	var entry := {
		"box":           box,
		"label_node":    lbl_node,
		"label_panel":   lbl_panel,
		"label_vbox":    lbl_vbox,
		"label":         label,
		"float_pos":     float_pos,   # kept for initial spawn position
		"display_pos":   float_pos,   # starts at float_pos, then orbits
		"anchor_screen": float_pos,
		"data":          data,
		"is_enemy":      is_enemy,
		"data_type":     data_type_hint if data_type_hint != "" else ("skill" if data is Dictionary else "enemy"),
		"tween":         null,
		"at_anchor":     false,
		"detail_nodes":  [],
		"selected":      false,
		"neon":          neon,
		"box_rot":       0.0,
		"trail":         [],
		"trail_timer":   0.0,
		"palette_idx":   palette_idx,
		"orbit_phase":   float(palette_idx) * (TAU / NEON_PALETTE.size()),
		"edge_push":     false,
		"click_pulse":   0.0,   # decays from 1.0 on press, drives size/brightness burst
		"screen_rect":   Rect2(), # computed each frame for entity boxes; empty for skills
		"spawn_anim":    0.0,   # 0.0 -> 1.0 over spawn; drives lock-on bracket animation
		"off_screen":    false,  # true when 3D anchor is behind/off camera
		"park_pos":      float_pos,  # corner-row position used when off_screen
	}

	var cap_entry := entry
	if press_override.is_valid():
		box.pressed.connect(press_override)
	else:
		box.pressed.connect(func(): _on_box_pressed(cap_entry))
	return entry


# ── Anchor position refresh ───────────────────────────────────────────────────

func _refresh_anchor_positions() -> void:
	# Skill boxes → actor's skill anchors (left cam)
	var left_park_slot : int = 0
	for i in _skill_boxes.size():
		var e : Dictionary = _skill_boxes[i]
		if i < _skills.size() and is_instance_valid(_actor):
			var anchor := _actor.get_skill_anchor(_skills[i])
			if is_instance_valid(anchor):
				var proj : Vector2 = _anchor_screen(anchor, false)
				if proj.x <= -9000:
					e["off_screen"] = true
					e["park_pos"]   = _offscreen_park_pos(left_park_slot, false)
					left_park_slot += 1
				else:
					e["off_screen"]    = false
					e["anchor_screen"] = proj

	# Enemy boxes → CameraAnchor on each enemy (right cam)
	var enemy_park_slot : int = 0
	for i in _enemy_boxes.size():
		var e : Dictionary = _enemy_boxes[i]
		var raw = e["data"]
		if not is_instance_valid(raw):
			continue
		var enemy := raw as BattleActor
		# Hide and skip boxes whose enemy has died since the reticle was opened.
		if enemy != null and not enemy.is_alive():
			var dead_btn : Button = e["box"]
			if is_instance_valid(dead_btn):
				dead_btn.visible = false
			continue
		if enemy != null:
			var ca := enemy.get_node_or_null("CameraAnchor")
			var anchor : Node3D = ca if ca is Node3D else enemy
			var proj : Vector2 = _anchor_screen(anchor, true)
			var sr : Rect2 = enemy.get_screen_rect(_right_cam, RIGHT_VP_X)
			# Off-screen if projection failed OR the rect doesn't overlap the right viewport
			var vp_rect := Rect2(RIGHT_VP_X, 0.0, RIGHT_VP_W, 960.0)
			var is_off : bool = proj.x <= -9000 or sr.size.x <= 4.0 or not sr.intersects(vp_rect)
			if is_off:
				e["off_screen"]    = true
				e["park_pos"]      = _offscreen_park_pos(enemy_park_slot, true)
				e["screen_rect"]   = Rect2()
				enemy_park_slot += 1
			else:
				e["off_screen"]    = false
				e["anchor_screen"] = proj
				e["screen_rect"]   = sr

	# Ally boxes → CameraAnchor on each ally (right cam)
	# Share the left-edge parking column with off-screen skills.
	var ally_park_slot : int = left_park_slot
	for i in _ally_boxes.size():
		var e : Dictionary = _ally_boxes[i]
		var raw = e["data"]
		if not is_instance_valid(raw):
			continue
		var ally := raw as BattleActor
		if ally != null:
			var ca := ally.get_node_or_null("CameraAnchor")
			var anchor : Node3D = ca if ca is Node3D else ally
			var proj : Vector2 = _anchor_screen(anchor, true)
			if proj.x <= -9000:
				e["off_screen"]    = true
				e["park_pos"]      = _offscreen_park_pos(ally_park_slot, false)
				e["screen_rect"]   = Rect2()
				ally_park_slot += 1
			else:
				e["off_screen"]    = false
				e["anchor_screen"] = proj
				e["screen_rect"]   = ally.get_screen_rect(_right_cam, RIGHT_VP_X)

	# Part boxes → part anchors on selected target (right cam)
	for e in _part_boxes:
		var part := e["data"] as BodyPartData
		if is_instance_valid(_sel_target) and part != null:
			var anchor := _sel_target.get_part_anchor(part)
			if is_instance_valid(anchor):
				e["anchor_screen"] = _anchor_screen(anchor, true)


# ── Draw ──────────────────────────────────────────────────────────────────────

func _on_draw() -> void:
	if not _active:
		return
	_draw_box_set(_skill_boxes)
	_draw_box_set(_enemy_boxes)
	_draw_box_set(_ally_boxes)
	_draw_box_set(_part_boxes)
	_draw_struggle_box()
	_draw_repeat_button()


func _draw_box_set(entries: Array) -> void:
	for e in entries:
		var box : Button = e["box"]
		if not is_instance_valid(box) or not box.visible:
			continue
		# Off-screen entity: draw a plain dim rectangle with just the name — no fancy visuals.
		if e.get("off_screen", false):
			var dp2    : Vector2 = e["display_pos"]
			var half2  : Vector2 = Vector2(BOX_W, BOX_H) * 0.5
			var t_sec2 : float = Time.get_ticks_msec() * 0.001
			var pulse2 : float = 0.45 + 0.15 * sin(t_sec2 * 1.2)
			var sel2   : bool  = e.get("selected", false)
			var alpha2 : float = pulse2 * (1.0 if sel2 else 0.55)
			var th2    : ReticleTheme = _active_theme()
			var neon2  : Color = th2.get_neon(e["data_type"], int(e.get("palette_idx", 0)))
			var dim_col := Color(neon2.r * 0.5, neon2.g * 0.5, neon2.b * 0.5, alpha2)
			# Draw corner brackets at the parked box size
			var park_rect := Rect2(dp2 - half2, half2 * 2.0)
			_draw_corner_brackets(park_rect, neon2, alpha2, LINE_W * 1.5, 1.0)
			continue
		var dp    : Vector2 = e["display_pos"]
		var anch  : Vector2 = e["anchor_screen"]
		var sel   : bool    = e["selected"]
		var neon  : Color   = e["neon"]  # kept for pulse/line alpha calcs
		var rot   : float   = float(e["box_rot"])
		var side  : float   = BOX_W
		var t_sec     : float = Time.get_ticks_msec() * 0.001
		var locked    : bool  = e.get("_locked", false)
		var coloured  : bool  = (e["data_type"] == "skill" or not _sel_skill.is_empty()) and not locked
		var th        : ReticleTheme = _active_theme()
		var base_neon : Color = th.get_neon(e["data_type"], int(e.get("palette_idx", 0)))
		var cycle_on  : bool  = coloured and th.allow_hue_cycle()
		# In VAPORWAVE mode, drift the hue over time for cycling effect
		var hue_drifted : Color = base_neon
		if cycle_on:
			var hd : float = fmod(base_neon.h + t_sec * 0.08 + float(e.get("orbit_phase", 0.0)) * 0.05, 1.0)
			hue_drifted = Color.from_hsv(hd, 1.0, 1.0, 1.0)
		var pulse : float = 0.70 + 0.30 * sin(t_sec * 1.8 + base_neon.h * TAU)
		var cp    : float = float(e.get("click_pulse", 0.0))
		var half  : Vector2 = Vector2(side, side) * 0.5
		var box_a : float = pulse * 0.85 if sel else pulse * 0.38

		# ── Trail ghosts ────────────────────────────────────────────
		var _no_trail : bool = e["data_type"] in ["enemy", "ally", "part"] and e.get("screen_rect", Rect2()).size.x > 4.0
		if coloured and not _no_trail:
			var trail : Array = e["trail"]
			for ti in trail.size():
				var t_alpha : float = (1.0 - float(ti + 1) / float(TRAIL_LEN + 1)) * 0.28
				var td : Dictionary = trail[ti]
				_draw_rect_layered(td["pos"], half, float(td["rot"]), base_neon, t_alpha, LINE_W, cycle_on)

		# ── Connecting line: skip for entity boxes that have a screen rect
		var _ent_has_line : bool = not (e["data_type"] in ["enemy", "ally", "part"] and e.get("screen_rect", Rect2()).size.x > 4.0)
		var is_r  : bool  = e["is_enemy"]
		var vp_lx : float = RIGHT_VP_X if is_r else LEFT_VP_X
		var vp_rx : float = vp_lx + (RIGHT_VP_W if is_r else LEFT_VP_W)
		var line_a    : float = 0.55 if sel else 0.22
		# Line colour matches current hue_drift so it cycles with the box
		var line_rgb  : Color = hue_drifted if coloured else Color.WHITE
		var lc_dim    := Color(line_rgb.r, line_rgb.g, line_rgb.b, line_a * 0.4)
		var lc_bright := Color(line_rgb.r, line_rgb.g, line_rgb.b, line_a)
		# Offset line start to the box edge so it doesn’t draw through the interior
		var to_anch   : Vector2 = anch - dp
		var line_start : Vector2 = dp
		if to_anch.length_squared() > 0.01:
			line_start = dp + to_anch.normalized() * half.x
		if _ent_has_line:
			_draw_clipped_line(line_start, anch, lc_dim,    LINE_W * 4.0, vp_lx, vp_rx)
			_draw_clipped_line(line_start, anch, lc_bright, LINE_W,       vp_lx, vp_rx)

		# ── Click pulse
		var pulse_sr   : Rect2  = e.get("screen_rect", Rect2())
		var pulse_rect : bool   = e["data_type"] in ["enemy", "ally", "part"] and pulse_sr.size.x > 4.0
		if cp > 0.0 and not pulse_rect:
			var wave_t : float = 1.0 - cp
			const PULSE_LAYERS := 7
			const SPREAD : float = 0.40
			for pi in range(PULSE_LAYERS - 1, -1, -1):
				var band_t : float = float(pi) / float(PULSE_LAYERS - 1)
				var scale  : float = clamp(wave_t + (band_t - 1.0) * SPREAD, 0.0, 1.0)
				var p_a    : float = cp * 0.88 * (band_t * band_t)
				_draw_node.draw_colored_polygon(
						_rotated_corners(dp, half * scale, rot), Color(1.0, 1.0, 1.0, p_a))

		# ── Box ───────────────────────────────────────────────────
		var db_sr   : Rect2 = e.get("screen_rect", Rect2())
		var db_ent  : bool  = e["data_type"] in ["enemy", "ally", "part"]
		var db_is_r : bool  = e["is_enemy"]
		# Clamp the draw rect to whichever viewport this entity belongs to.
		var db_vp_x : float = RIGHT_VP_X if db_is_r else LEFT_VP_X
		var db_vp_w : float = RIGHT_VP_W if db_is_r else LEFT_VP_W
		var db_vp_rect := Rect2(db_vp_x, 0, db_vp_w, 960.0)
		var db_clipped  : Rect2 = db_sr.intersection(db_vp_rect)
		var db_rect : bool  = db_ent and db_clipped.size.x > 4.0
		if db_rect:
			var draw_col : Color = hue_drifted if coloured else Color.WHITE
			var spawn_t  : float = float(e.get("spawn_anim", 1.0))
			_draw_corner_brackets(db_clipped, draw_col, box_a, LINE_W * 2.0, spawn_t)
			if sel and coloured:
				_draw_corner_brackets(db_clipped.grow(4.0).intersection(db_vp_rect), draw_col, box_a * 0.45, LINE_W, spawn_t)
		elif coloured:
			var draw_col : Color = hue_drifted
			_draw_rect_layered(dp, half, rot, draw_col, box_a * 0.18, LINE_W * 5.0, cycle_on)
			_draw_rect_layered(dp, half, rot, draw_col, box_a, LINE_W * 1.5, cycle_on)
		else:
			var pts := _rotated_corners(dp, half, rot)
			_draw_node.draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, 0.35))
			var wc := Color(1.0, 1.0, 1.0, box_a)
			for i2 in 4:
				_draw_node.draw_line(pts[i2], pts[(i2 + 1) % 4], wc, LINE_W)


## Clip a line segment to [vp_left, vp_right] in screen X before drawing.
## Uses parametric clipping (Liang-Barsky in 1D on X axis only).
func _draw_clipped_line(a: Vector2, b: Vector2, col: Color, lw: float,
		vp_left: float, vp_right: float) -> void:
	var dx : float = b.x - a.x
	var t0 : float = 0.0
	var t1 : float = 1.0
	# Clip against left edge (x >= vp_left)
	if dx == 0.0:
		if a.x < vp_left or a.x > vp_right:
			return
	else:
		var tl : float = (vp_left  - a.x) / dx
		var tr : float = (vp_right - a.x) / dx
		if dx > 0.0:
			t0 = max(t0, tl); t1 = min(t1, tr)
		else:
			t0 = max(t0, tr); t1 = min(t1, tl)
	if t0 >= t1:
		return
	var ca : Vector2 = a + (b - a) * t0
	var cb : Vector2 = a + (b - a) * t1
	_draw_node.draw_line(ca, cb, col, lw)


func _rotated_corners(centre: Vector2, half: Vector2, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c : float = cos(rot)
	var s : float = sin(rot)
	for corner in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
		var cv : Vector2 = corner as Vector2
		var lx : float = cv.x * half.x
		var ly : float = cv.y * half.y
		pts.append(centre + Vector2(lx * c - ly * s, lx * s + ly * c))
	return pts


## Draw AR-style corner brackets around a Rect2.
## spawn_t: 0=brackets far out (lock-on start), 1=fully converged on rect.
func _draw_corner_brackets(rect: Rect2, col: Color, alpha: float, lw: float,
		spawn_t: float = 1.0) -> void:
	# Ease the spawn so it starts fast and snaps on
	var t : float = 1.0 - pow(1.0 - clamp(spawn_t, 0.0, 1.0), 3.0)
	# Expand rect outward during spawn
	var expand : float = (1.0 - t) * 22.0
	var r := rect.grow(expand)
	var arm_x : float = maxf(r.size.x * 0.22, 8.0)
	var arm_y : float = maxf(r.size.y * 0.22, 8.0)
	var c : Color = Color(col.r, col.g, col.b, alpha * t)
	var tl := r.position
	var tr := Vector2(r.position.x + r.size.x, r.position.y)
	var bl := Vector2(r.position.x,             r.position.y + r.size.y)
	var br := r.position + r.size
	# Top-left
	_draw_node.draw_line(tl, tl + Vector2(arm_x,  0), c, lw)
	_draw_node.draw_line(tl, tl + Vector2(0,  arm_y), c, lw)
	# Top-right
	_draw_node.draw_line(tr, tr + Vector2(-arm_x, 0), c, lw)
	_draw_node.draw_line(tr, tr + Vector2(0,  arm_y), c, lw)
	# Bottom-left
	_draw_node.draw_line(bl, bl + Vector2(arm_x,  0), c, lw)
	_draw_node.draw_line(bl, bl + Vector2(0, -arm_y), c, lw)
	# Bottom-right
	_draw_node.draw_line(br, br + Vector2(-arm_x, 0), c, lw)
	_draw_node.draw_line(br, br + Vector2(0, -arm_y), c, lw)
	# Very faint fill
	_draw_node.draw_rect(r, Color(col.r, col.g, col.b, alpha * t * 0.06), true)


## Draw a filled rotated square with:
## - Outer edge: hue at hue_base, bright, semi-opaque
## - Inner layers: hue shifts toward complement, fading to fully transparent
## - Bright neon outline on top
func _draw_rect_layered(centre: Vector2, half: Vector2, rot: float,
		base_col: Color, alpha: float, lw: float, cycle: bool = true) -> void:
	_draw_node.draw_colored_polygon(_rotated_corners(centre, half, rot), Color(0.0, 0.0, 0.0, 0.161))
	const FILL_LAYERS := 7
	for fi in FILL_LAYERS:
		var t_outer : float = float(fi)     / float(FILL_LAYERS)
		var t_inner : float = float(fi + 1) / float(FILL_LAYERS)
		var t_mid   : float = (t_outer + t_inner) * 0.5
		var band_col : Color
		if cycle:
			# VAPORWAVE: hue-shift toward complement, full saturation
			var band_hue : float = fmod(base_col.h + t_mid * 0.5, 1.0)
			var band_val : float = 1.0 - t_mid * 0.80
			var band_a   : float = alpha * 0.70 * pow(1.0 - t_mid, 2.8)
			band_col = Color.from_hsv(band_hue, 1.0, band_val, band_a)
		else:
			# TACTICAL: lerp base colour toward black at centre, preserve RGB
			var fade  : float = 1.0 - t_mid * 0.80
			var band_a : float = alpha * 0.70 * pow(1.0 - t_mid, 2.8)
			band_col = Color(base_col.r * fade, base_col.g * fade, base_col.b * fade, band_a)
		var h_out := half * (1.0 - t_outer)
		var h_in  := half * (1.0 - t_inner)
		var outer := _rotated_corners(centre, h_out, rot)
		var inner := _rotated_corners(centre, h_in,  rot)
		_draw_node.draw_colored_polygon(PackedVector2Array([
			outer[0], outer[1], outer[2], outer[3],
			inner[3], inner[2], inner[1], inner[0]
		]), band_col)
	# Edge outline — use base_col directly, no HSV reconstruction
	var edge_col : Color = Color(base_col.r, base_col.g, base_col.b, alpha * 0.9)
	var pts := _rotated_corners(centre, half, rot)
	for i in 4:
		_draw_node.draw_line(pts[i], pts[(i + 1) % 4], edge_col, lw)


# ── Box press handler ─────────────────────────────────────────────────────────

func _on_box_pressed(entry: Dictionary) -> void:
	
	var data    : Variant = entry["data"]
	var at_anch : bool    = entry["at_anchor"]

	var dtype : String = entry["data_type"]

	if dtype == "skill":
		print("CLICK skill | support targeting:", _support_targeting)
		var sk : Dictionary = data
		var already_sel : bool = (_sel_skill == sk)
		_deselect_all(_skill_boxes, entry)
		if already_sel and at_anch:
			if not _skill_needs_target(sk):
				# AoE / struggle: second click confirms immediately.
				emit_signal("skill_selected", sk)
				emit_signal("confirmed")
				return
			else:
				# Single-target skill already selected: deselect it so the player
				# can re-pick. Clear all dependent state and return to free-float.
				_sel_skill  = {}
				_sel_target = null
				_sel_part   = null
				_slide_to_float(entry)
				_clear_boxes(_part_boxes)
				_clear_struggle_box()
				for eb in _enemy_boxes:
					if eb["selected"] or eb["edge_push"]:
						_slide_to_float(eb)
				for ab in _ally_boxes:
					if ab["selected"]:
						_slide_to_float(ab)
				emit_signal("cancelled")
				return
		_sel_skill = sk
		_sel_target = null
		_sel_part = null
		emit_signal("skill_selected", sk)
		_slide_to_anchor(entry)
		_clear_boxes(_part_boxes)
		# Properly reset all enemy and ally boxes via _slide_to_float so their
		# detail nodes, label colours, and edge-push state are all cleaned up.
		for eb in _enemy_boxes:
			if eb["selected"] or eb["edge_push"]:
				_slide_to_float(eb)
		for ab in _ally_boxes:
			if ab["selected"]:
				_slide_to_float(ab)
		# Spawn struggle alternative if in tense phase and skill has one
		# Spawn struggle alternative if in tense phase and skill has one
		_clear_struggle_box()
		if _tense_phase and sk.get("struggle_name", "") != "":
			_spawn_struggle_box(entry)

	elif dtype == "enemy":
		print("CLICK enemy | support targeting:", _support_targeting)
		print("Enemy data type:", typeof(data), " value:", data)
		var actor = data as BattleActor
		print("Casted actor:", actor)
		if not is_instance_valid(data):
			return
		# During ally-targeting mode, enemy clicks do camera focus only.
		if _support_targeting:
			return
		var enemy : BattleActor = data as BattleActor
		var already_sel : bool = (_sel_target == enemy)
		# Second click on the same enemy while it is already at its anchor:
		# don't deselect and re-select — just leave state intact.
		if already_sel and at_anch:
			return
		_deselect_all(_enemy_boxes, entry)
		_sel_target = enemy
		_sel_part = null
		_slide_to_anchor(entry)
		if not _sel_skill.is_empty():
			# Skill already chosen — advance targeting normally
			for eb in _enemy_boxes:
				eb["edge_push"] = (eb != entry)
			emit_signal("target_selected", enemy)
			_clear_boxes(_part_boxes)
			_build_part_boxes()
		else:
			# No skill yet — camera focus only, no targeting state change
			emit_signal("focus_requested", enemy)

	elif dtype == "ally":
		if not is_instance_valid(data):
			return
		var ally : BattleActor = data as BattleActor
		if _sel_skill.is_empty() or (_sel_target != null and _sel_target.team == BattleActor.Team.ENEMY):
			# No skill selected — reset all other selections first, then show
			# ally details and focus camera; do not set _sel_target.
			_deselect_all(_skill_boxes, {})
			_sel_skill  = {}
			_sel_target = null
			_sel_part   = null
			_clear_boxes(_part_boxes)
			_clear_struggle_box()
			for eb in _enemy_boxes:
				if eb["selected"] or eb["edge_push"]:
					_slide_to_float(eb)
			_deselect_all(_ally_boxes, entry)
			_slide_to_anchor(entry)
			emit_signal("focus_requested", ally)
		else:
			# Support skill selected — commit as target.
			_deselect_all(_ally_boxes, entry)
			_sel_target = ally
			_sel_part   = null
			_slide_to_anchor(entry)
			emit_signal("target_selected", ally)

	elif dtype == "part":
		if _sel_skill.is_empty():
			return
		var part : BodyPartData = data as BodyPartData
		var already_sel : bool = (_sel_part == part)
		_deselect_all(_part_boxes, entry)
		if already_sel and at_anch:
			emit_signal("part_selected", part)
			emit_signal("confirmed")
			return
		_sel_part = part
		emit_signal("part_selected", part)
		_slide_to_anchor(entry)


# ── Slide animation ───────────────────────────────────────────────────────────

func _slide_to_anchor(entry: Dictionary) -> void:
	entry["selected"]     = true
	entry["click_pulse"]  = 0.75

	var lbl_node : Label = entry["label_node"]
	if is_instance_valid(entry.get("tween")):
		(entry["tween"] as Tween).kill()
	# Wait for drift to land (~travel time), then mark at_anchor and show detail
	var cap_entry := entry
	var tw := create_tween()
	tw.tween_interval(TWEEN_TIME * 1.5)
	tw.tween_callback(func():
		if cap_entry["selected"]:
			cap_entry["at_anchor"] = true
			_show_detail(cap_entry))
	entry["tween"] = tw


func _slide_to_float(entry: Dictionary) -> void:
	entry["selected"]  = false
	entry["at_anchor"] = false
	entry["edge_push"] = false   # always clear push when returning to float
	_hide_detail(entry)
	if entry.get("data_type") == "skill":
		_hide_filter_panel()
	if is_instance_valid(entry.get("tween")):
		(entry["tween"] as Tween).kill()


# ── Detail expansion ──────────────────────────────────────────────────────────

func _show_detail(entry: Dictionary) -> void:
	_hide_detail(entry)
	var data     : Variant = entry["data"]
	var lbl_node : Label   = entry["label_node"]
	if not is_instance_valid(lbl_node):
		return

	var lines : Array = []
	var dtype : String = entry.get("data_type", "")
	if dtype == "skill":
		var sk : Dictionary = data
		var summary : String = str(sk.get("summary", ""))
		if summary != "" and summary != " ":
			lines.append(summary)
		var will_cost : int = int(sk.get("will_cost", 0))
		if will_cost > 0:
			lines.append("%d AP" % will_cost)
		if bool(sk.get("aoe", false)):
			lines.append("ALL TARGETS")
	elif dtype == "enemy" or dtype == "ally":
		if is_instance_valid(data):
			var actor : BattleActor = data as BattleActor
			var revealed : bool = actor.team == BattleActor.Team.PLAYER or actor.stats_revealed
			if revealed:
				lines.append("CORP  %d/%d" % [actor.hp, actor.max_hp])
			else:
				lines.append("CORP  ???")
			if revealed:
				lines.append("SHARP  %d" % actor.attack_power)
				lines.append("FLAT  %d" % actor.flat_defense)
				for fx in actor.active_effects:
					var dur : int = int(fx.get("duration", 0))
					var dur_str : String = " %dt" % dur if dur > 0 else ""
					var fid : String = str(fx.get("id", ""))
					if fid == "_stat_change":
						var delta : int = int(fx.get("delta", 0))
						var stat  : String = str(fx.get("stat", "")).to_upper()
						var sign  : String = "+" if delta >= 0 else ""
						lines.append("%s%d %s%s" % [sign, delta, stat, dur_str])
					else:
						lines.append(fid.to_upper() + dur_str)
	elif dtype == "part":
		var part : BodyPartData = data as BodyPartData
		if part != null:
			lines.append("x%.2f DMG" % part.damage_multiplier)
			if part.is_cognitohazard:
				lines.append("[HAZARD]")
			if part.has_part_hp():
				lines.append("STRUCT  %d/%d" % [part.current_part_hp, part.max_part_hp])

	# Each detail line gets its own dark panel, stacked below the label panel
	var lbl_panel : Control = entry["label_panel"]
	for i in lines.size():
		var dp_node := PanelContainer.new()
		var psbox := StyleBoxFlat.new()
		psbox.bg_color = C_PANEL_BG
		psbox.set_corner_radius_all(0)
		psbox.set_content_margin_all(3)
		psbox.set_border_width_all(0)
		dp_node.add_theme_stylebox_override("panel", psbox)
		dp_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dl := Label.new()
		dl.text = lines[i].to_upper()
		dl.add_theme_font_size_override("font_size", FONT_SIZE_DET)
		if _font: dl.add_theme_font_override("font", _font)
		dl.add_theme_color_override("font_color", C_DETAIL)
		dp_node.add_child(dl)
		# Position is driven every frame by _update_drift relative to lbl_panel
		dp_node.position = lbl_panel.position + Vector2(0.0, float(i + 1) * 40.0)
		dp_node.modulate.a = 0.0
		add_child(dp_node)
		entry["detail_nodes"].append(dp_node)
		var tw := dp_node.create_tween()
		tw.tween_interval(i * 0.05)
		tw.tween_property(dp_node, "modulate:a", 1.0, 0.14)


func _hide_detail(entry: Dictionary) -> void:
	for dl in entry["detail_nodes"]:
		if is_instance_valid(dl):
			dl.queue_free()
	entry["detail_nodes"].clear()


# ── Deselect helpers ──────────────────────────────────────────────────────────

func _deselect_all(entries: Array, except: Dictionary) -> void:
	for e in entries:
		if e == except:
			continue
		if e["selected"]:
			_slide_to_float(e)


# ── Cleanup ───────────────────────────────────────────────────────────────────

# ── Struggle box ──────────────────────────────────────────────────────────────

func _spawn_struggle_box(parent_entry: Dictionary) -> void:
	_clear_struggle_box()
	var sk : Dictionary = parent_entry["data"]
	var struggle_name : String = sk.get("struggle_name", "")
	if struggle_name == "":
		return
	var struggle_sk : Dictionary = SkillDirectory.get_dict(struggle_name)
	if struggle_sk.is_empty():
		return
	var start_pos : Vector2 = parent_entry["display_pos"] + Vector2(0.0, BOX_H + 6.0)
	var lbl : String = struggle_sk.get("name", struggle_name)
	# Pass the press handler directly so no disconnect is needed
	var cap_sk := struggle_sk
	var handler := func():
		_clear_struggle_box()
		emit_signal("skill_selected", cap_sk)
		emit_signal("confirmed")
	var entry := _make_box_entry(start_pos, lbl, struggle_sk, false, "skill", handler)
	entry["_struggle"] = true
	entry["_parent_entry"] = parent_entry
	# Add summary as a subtitle under the label
	var summary : String = struggle_sk.get("summary", "")
	if summary != "" and summary.strip_edges() != " ":
		var lv : VBoxContainer = entry.get("label_vbox")
		if is_instance_valid(lv):
			var sub := Label.new()
			sub.text = summary
			sub.add_theme_font_size_override("font_size", 10)
			if _font: sub.add_theme_font_override("font", _font)
			sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
			sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sub.custom_minimum_size = Vector2(180, 0)
			lv.add_child(sub)
	_struggle_box = entry


func _clear_struggle_box() -> void:
	if _struggle_box.is_empty():
		return
	if is_instance_valid(_struggle_box.get("box")):
		_struggle_box["box"].queue_free()
	if is_instance_valid(_struggle_box.get("label_panel")):
		_struggle_box["label_panel"].queue_free()
	for dn in _struggle_box.get("detail_nodes", []):
		if is_instance_valid(dn): dn.queue_free()
	_struggle_box = {}


func _clear_repeat_button() -> void:
	if is_instance_valid(_repeat_btn): _repeat_btn.queue_free()
	if is_instance_valid(_repeat_lbl): _repeat_lbl.queue_free()
	_repeat_btn = null
	_repeat_lbl = null


func _build_repeat_button() -> void:
	_clear_repeat_button()
	# Position at the bottom of the skill box column, in the left viewport.
	var base_x : float = LEFT_VP_X + LEFT_VP_W * 0.1
	var base_y : float = 960 - base_x  # near bottom of left viewport
	var half   : Vector2 = Vector2(BOX_W, BOX_H) * 0.5

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(BOX_W, BOX_H)
	btn.size = Vector2(BOX_W, BOX_H)
	btn.flat = true
	btn.position = Vector2(base_x - half.x, base_y - half.y)
	# Transparent so _draw handles visuals
	var sbox := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", sbox)
	btn.add_theme_stylebox_override("hover",  sbox)
	btn.add_theme_stylebox_override("pressed", sbox)
	btn.add_theme_stylebox_override("focus",  sbox)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(func(): emit_signal("repeat_action"))
	add_child(btn)
	_repeat_btn = btn

	# Label panel
	var lbl_panel := ColorRect.new()
	lbl_panel.color = Color(0.04, 0.04, 0.04, 1.0)
	lbl_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl_panel)

	var lv := VBoxContainer.new()
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_theme_constant_override("separation", 2)
	lbl_panel.add_child(lv)

	var name_lbl := Label.new()
	name_lbl.text = " REPRISE"
	name_lbl.add_theme_font_size_override("font_size", FONT_SIZE_LBL)
	if _font: name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	lv.add_child(name_lbl)

	var hint_lbl := Label.new()
	hint_lbl.text = " Repeat last\n action"
	hint_lbl.add_theme_font_size_override("font_size", 10)
	if _font: hint_lbl.add_theme_font_override("font", _font)
	hint_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	lv.add_child(hint_lbl)

	# Position label to the right of the button
	var lp_pos := Vector2(base_x + half.x + LABEL_PAD, base_y - half.y)
	lbl_panel.position = lp_pos
	_repeat_lbl = lbl_panel
	_draw_node.queue_redraw()


func _update_struggle_box_position(delta: float) -> void:
	if _struggle_box.is_empty():
		return
	var parent : Dictionary = _struggle_box.get("_parent_entry", {})
	if parent.is_empty():
		return
	var target : Vector2 = parent["display_pos"] + Vector2(0.0, BOX_H + 6.0)
	_struggle_box["display_pos"] = _struggle_box["display_pos"].lerp(target, clamp(12.0 * delta, 0.0, 1.0))
	var dp : Vector2 = _struggle_box["display_pos"]
	var box : Button = _struggle_box.get("box")
	var lp  : Control = _struggle_box.get("label_panel")
	if is_instance_valid(box):
		box.position = dp - box.size * 0.5
	if is_instance_valid(lp):
		lp.position = dp + Vector2(BOX_W * 0.5 + LABEL_PAD, -BOX_H * 0.5)


func _draw_struggle_box() -> void:
	if _struggle_box.is_empty():
		return
	var dp   : Vector2 = _struggle_box["display_pos"]
	var half : Vector2 = Vector2(BOX_W, BOX_H) * 0.5
	var t_sec : float = Time.get_ticks_msec() * 0.001
	var pulse : float = 0.55 + 0.20 * sin(t_sec * 1.4)
	var dim   : Color = Color(0.75, 0.60, 0.25, pulse)
	_draw_rect_layered(dp, half, 0.0, dim, pulse, LINE_W * 1.2, false)
	_draw_rect_layered(dp, half, 0.0, dim, pulse * 0.12, LINE_W * 5.0, false)


func _draw_repeat_button() -> void:
	if not is_instance_valid(_repeat_btn):
		return
	var dp   : Vector2 = _repeat_btn.position + _repeat_btn.size * 0.5
	var half : Vector2 = Vector2(BOX_W, BOX_H) * 0.5
	var t_sec : float = Time.get_ticks_msec() * 0.001
	var pulse : float = 0.50 + 0.20 * sin(t_sec * 1.1)
	# Muted cyan — distinct from skill palette, reads as a utility action
	var col  : Color = Color(0.20, 0.80, 0.75, pulse)
	_draw_rect_layered(dp, half, 0.0, col, pulse * 0.85, LINE_W * 1.2, false)
	_draw_rect_layered(dp, half, 0.0, col, pulse * 0.10, LINE_W * 5.0, false)
	# Size the label panel now that it has children
	if is_instance_valid(_repeat_lbl):
		var lv := _repeat_lbl.get_child(0) if _repeat_lbl.get_child_count() > 0 else null
		if lv != null:
			var lv_min := (lv as Control).get_minimum_size()
			_repeat_lbl.size = Vector2(lv_min.x + 8.0, lv_min.y + 8.0)


func _clear_boxes(entries: Array) -> void:
	for e in entries:
		if is_instance_valid(e.get("box")):
			e["box"].queue_free()
		if is_instance_valid(e.get("label_panel")):
			e["label_panel"].queue_free()  # frees label_node too (child)
		for dn in e["detail_nodes"]:
			if is_instance_valid(dn): dn.queue_free()
		if is_instance_valid(e.get("tween")):
			(e["tween"] as Tween).kill()
	entries.clear()


func _clear_all_boxes() -> void:
	_clear_struggle_box()
	_clear_boxes(_skill_boxes)
	_clear_boxes(_enemy_boxes)
	_clear_boxes(_ally_boxes)
	_clear_boxes(_part_boxes)
	_palette_counter = 0


## Called by the battle manager when an actor dies mid-turn.
## Removes that actor's box from the reticle without resetting skill selection.
func notify_actor_died(actor: BattleActor) -> void:
	if not _active:
		return
	# Remove from the tracking arrays so future rebuilds skip them
	_enemies.erase(actor)
	_allies.erase(actor)
	# Find and remove the dead actor's box entry
	for list in [_enemy_boxes, _ally_boxes]:
		var to_remove : Dictionary = {}
		for e in list:
			if e.get("data") == actor:
				to_remove = e
				break
		if not to_remove.is_empty():
			if is_instance_valid(to_remove.get("box")):
				to_remove["box"].queue_free()
			if is_instance_valid(to_remove.get("label_panel")):
				to_remove["label_panel"].queue_free()
			for dn in to_remove.get("detail_nodes", []):
				if is_instance_valid(dn): dn.queue_free()
			if is_instance_valid(to_remove.get("tween")):
				(to_remove["tween"] as Tween).kill()
			list.erase(to_remove)
	# If the dead actor was the selected target, clear that selection
	if _sel_target == actor:
		_sel_target = null
		_clear_boxes(_part_boxes)
	_draw_node.queue_redraw()


# ── Skill targeting check ─────────────────────────────────────────────────────

func _skill_needs_target(sk: Dictionary) -> bool:
	if bool(sk.get("aoe", false)) or bool(sk.get("struggle", false)):
		return false
	return true


# ── ESC to step back ──────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _active: return
	# Right-click deselects everything and returns to free-float
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		reset_selection()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _sel_part != null:
			_sel_part = null
			_deselect_all(_part_boxes, {})
		elif _sel_target != null:
			_sel_target = null
			_deselect_all(_enemy_boxes, {})
			_clear_boxes(_part_boxes)
		elif not _sel_skill.is_empty():
			_sel_skill = {}
			_deselect_all(_skill_boxes, {})
			# Reset all enemy boxes back to white floating state
			for eb in _enemy_boxes:
				eb["selected"]  = false
				eb["at_anchor"] = false
				eb["edge_push"] = false
				_hide_detail(eb)
