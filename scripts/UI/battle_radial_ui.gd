extends CanvasLayer
## BattleRadialUI — radial ring UI for battle command input.
##
## Rings: skill → target → part (enemy) or target confirm (ally).
## Change Lens (ammo user special): skill → channel ring → confirm.
##
## Signals: skill_chosen, target_chosen, part_chosen, filter_chosen, confirmed, cancelled.

signal skill_chosen(skill_key: String)
signal target_chosen(target: BattleActor)
signal part_chosen(part: BodyPartData)
signal filter_chosen(channel: int)
signal confirmed
signal cancelled

# ── Change Lens channels ───────────────────────────────────────────────────────
const CHANNELS := [
	{"label": "R", "value": 1, "color": Color(0.80, 0.22, 0.18, 1.0)},
	{"label": "G", "value": 2, "color": Color(0.22, 0.65, 0.30, 1.0)},
	{"label": "B", "value": 4, "color": Color(0.22, 0.45, 0.80, 1.0)},
]

# ── Visual constants (match dungeon_map_3d palette) ───────────────────────────
const FONT_PATH      := "res://assets/Fonts/TerminalVector.ttf"
const C_BG           := Color(0.08, 0.07, 0.06, 0.96)
const C_BORDER       := Color(0.35, 0.28, 0.22, 1.0)
const C_ACCENT       := Color(0.52, 0.42, 0.28, 1.0)
const C_TEXT         := Color(0.88, 0.83, 0.74, 1.0)
const C_DIM          := Color(0.45, 0.40, 0.35, 1.0)
const C_SEL          := Color(0.52, 0.42, 0.28, 0.28)
const C_ENEMY        := Color(0.72, 0.22, 0.18, 1.0)
const C_ALLY         := Color(0.22, 0.55, 0.38, 1.0)
const C_PART         := Color(0.28, 0.42, 0.62, 1.0)

# ── Ring geometry ─────────────────────────────────────────────────────────────
const SKILL_RADIUS   := 60.0
const TARGET_RADIUS  := 200.0
const PART_RADIUS    := 100.0
const CHANNEL_RADIUS := 190.0
const RADIAL_START_ANGLE := -90.0
const RING_BTN_W         := 75.0
const RING_BTN_H         := 75.0
const RING_ROLL_TIME     := 0.38
const RING_POP_TIME      := 0.18

# Evenly-spaced angles for up to 6 buttons; first always at the top.
func _angles_for(n: int, arc_deg: float = 220.0, center_deg: float = -90.0) -> Array:
	var out := []
	if n <= 0:
		return out

	# Clamp arc so spacing never becomes too small
	var min_spacing := 28.0
	var spacing: float = arc_deg / max(n - 1, 1)
	if spacing < min_spacing:
		spacing = min_spacing
		arc_deg = spacing * (n - 1)

	var start := center_deg - arc_deg * 0.5

	for i in n:
		out.append(start + spacing * i)

	return out

func _angle_between(a: Vector2, b: Vector2) -> float:
	return rad_to_deg((b - a).angle())

# ── State ─────────────────────────────────────────────────────────────────────
var _root_layer   : CanvasLayer = null
var _origin       : Vector2     = Vector2.ZERO

var _skill_wrappers : Array = []   # parallel to _skill_btns — the wrapper Controls
var _skill_btns   : Array = []
var _target_btns  : Array = []
var _part_btns    : Array = []
var _channel_btns : Array = []
var _info_card    : Control = null

var _skills       : Array = []
var _targets      : Array = []
var _ally_targets : Array = []

var _sel_skill        : Dictionary  = {}
var _sel_target       : BattleActor = null
var _sel_part         : BodyPartData = null
var _sel_channel      : int          = -1
var _sel_skill_center : Vector2      = Vector2.ZERO
var _sel_target_center: Vector2      = Vector2.ZERO

var _active_actor : BattleActor = null
var _manager      : Node        = null   # set by battle_manager after open()



# ══════════════════════════════════════════════════════════════════════════════
# Public API
# ══════════════════════════════════════════════════════════════════════════════

func open(origin: Vector2, skills: Array, targets: Array,
		ally_targets: Array, actor: BattleActor = null) -> void:
	close(true)
	_origin       = origin
	_skills       = skills
	_targets      = targets
	_ally_targets = ally_targets
	_active_actor = actor

	_root_layer       = CanvasLayer.new()
	_root_layer.layer = 20
	add_child(_root_layer)

	_build_skill_ring()


func close(silent: bool = false) -> void:
	if is_instance_valid(_root_layer):
		_root_layer.queue_free()
		_root_layer = null
	_skill_btns.clear()
	_target_btns.clear()
	_part_btns.clear()
	_channel_btns.clear()
	_info_card = null
	_sel_skill = {}
	_sel_target = null
	_sel_part = null
	_sel_channel = -1
	if not silent:
		emit_signal("cancelled")


# ══════════════════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════════════════

func _is_change_lens(sk: Dictionary) -> bool:
	if str(sk.get("key", "")) != "special": return false
	if _active_actor == null or _active_actor.party_member == null: return false
	return not _active_actor.party_member.has_will()

func _skill_has_target_children(sk: Dictionary) -> bool:
	if _is_change_lens(sk): return true
	if bool(sk.get("aoe", false)) or bool(sk.get("struggle", false)): return false
	var is_sup : bool = str(sk.get("key", "")) == "support"
	return not (_ally_targets if is_sup else _targets).is_empty()


# ══════════════════════════════════════════════════════════════════════════════
# Skill ring
# ══════════════════════════════════════════════════════════════════════════════

func _build_skill_ring() -> void:
	_skill_btns.clear()
	_skill_wrappers.clear()
	var angles := _angles_for(_skills.size(), 220.0, -90.0)
	for i in _skills.size():
		var skill : Dictionary = _skills[i]
		var wrapper := _make_wrapper()
		_root_layer.add_child(wrapper)
		var btn := _make_ring_btn("")
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(btn)
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
		_skill_btns.append(btn)
		_skill_wrappers.append(wrapper)
		var cap_skill := skill
		var cap_i     := i
		btn.pressed.connect(func(): _on_skill_pressed(cap_skill, cap_i))
		_animate_arc(wrapper, btn, _origin,
			RADIAL_START_ANGLE, angles[i],
			true, skill.get("name", skill.get("key", "?")),
			SKILL_RADIUS)


func _on_skill_pressed(skill: Dictionary, idx: int) -> void:
	var has_ch := _skill_has_target_children(skill)

	if _sel_skill == skill:
		# Second press on same skill — only confirm if no children are showing
		if not has_ch:
			var key : String = str(skill.get("key", ""))
			close(true)
			emit_signal("skill_chosen", key)
			emit_signal("confirmed")
		return

	# First press
	_sel_skill  = skill
	_sel_target = null
	_sel_part   = null
	_sel_channel = -1
	_clear_info_card()
	_clear_target_ring()
	_clear_part_ring()
	_clear_channel_ring()

	if idx < _skill_btns.size():
		var w := _skill_btns[idx].get_parent() as Control
		if is_instance_valid(w):
			_sel_skill_center = w.position + w.size * 0.5

	for i in _skill_btns.size():
		if i == idx:
			_morph_skill_btn_to_card(i, skill)
		else:
			_set_btn_selected(_skill_btns[i], false)

	if not has_ch:
		return

	if _is_change_lens(skill):
		_build_channel_ring(_sel_skill_center)
		return

	var is_sup      : bool = str(skill.get("key", "")) == "support"
	var ally_target : bool = bool(skill.get("ally_target", false))
	var enemy_target: bool = bool(skill.get("enemy_target", false))

	var pool : Array
	var is_ally := false

	if enemy_target:
		pool = _targets
		is_ally = false
	elif ally_target:
		pool = _ally_targets
		is_ally = true
	elif is_sup:
		pool = _ally_targets
		is_ally = true
	else:
		pool = _targets
		is_ally = false

	_build_target_ring(pool, is_ally)



# ══════════════════════════════════════════════════════════════════════════════
# Target ring
# ══════════════════════════════════════════════════════════════════════════════

func _build_target_ring(pool: Array, is_ally: bool) -> void:
	_target_btns.clear()
	var center := _angle_between(_origin, _sel_skill_center)
	var angles := _angles_for(pool.size(), 200.0, center)
	for i in pool.size():
		var actor : BattleActor = pool[i]
		var wrapper := _make_wrapper()
		_root_layer.add_child(wrapper)
		var btn := _make_ring_btn("", is_ally)
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(btn)
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
		_target_btns.append(btn)
		var cap_actor := actor
		var cap_i     := i
		btn.pressed.connect(func(): _on_target_pressed(cap_actor, cap_i, is_ally))
		_animate_arc(wrapper, btn, _sel_skill_center,
			RADIAL_START_ANGLE, angles[i],
			true, actor.name,
			TARGET_RADIUS)


func _on_target_pressed(actor: BattleActor, idx: int, is_ally: bool) -> void:
	if _sel_target == actor:
		if is_ally:
			# Second press on ally — confirm
			var key : String = _sel_skill.get("key", "")
			close(true)
			emit_signal("skill_chosen", key)
			emit_signal("target_chosen", actor)
			emit_signal("confirmed")
		return

	# First press
	_sel_target = actor
	_clear_info_card()
	_clear_part_ring()

	if idx < _target_btns.size():
		var w := _target_btns[idx].get_parent() as Control
		if is_instance_valid(w):
			_sel_target_center = w.position + w.size * 0.5

	for i in _target_btns.size():
		_set_btn_selected(_target_btns[i], i == idx)

	if is_ally:
		_show_target_card(actor)
		return

	# Enemy target — emit camera signals, then build part ring
	emit_signal("skill_chosen", _sel_skill.get("key", ""))
	emit_signal("target_chosen", actor)

	var mask  : int   = _manager.removed_channels if is_instance_valid(_manager) else 0
	var parts : Array = actor.get_visible_parts(mask)
	if parts.is_empty():
		close(true)
		emit_signal("confirmed")
		return

	_build_part_ring(parts, actor)


# ══════════════════════════════════════════════════════════════════════════════
# Part ring
# ══════════════════════════════════════════════════════════════════════════════

func _build_part_ring(parts: Array, _actor: BattleActor) -> void:
	_part_btns.clear()
	var center := _angle_between(_sel_skill_center, _sel_target_center) + 180.0
	var angles := _angles_for(parts.size(), 180.0, center)
	for i in parts.size():
		var part : BodyPartData = parts[i]
		var wrapper := _make_wrapper()
		_root_layer.add_child(wrapper)
		var btn := _make_ring_btn("", false, true)
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(btn)
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
		_part_btns.append(btn)
		var cap_part := part
		var cap_i    := i
		btn.pressed.connect(func(): _on_part_pressed(cap_part, cap_i))
		_animate_arc(wrapper, btn, _sel_target_center,
			RADIAL_START_ANGLE, angles[i],
			true, part.part_name,
			PART_RADIUS)


func _on_part_pressed(part: BodyPartData, idx: int) -> void:
	if _sel_part == part:
		# Second press — confirm
		close(true)
		emit_signal("part_chosen", part)
		emit_signal("confirmed")
		return

	_sel_part = part
	_clear_info_card()

	for i in _part_btns.size():
		_set_btn_selected(_part_btns[i], i == idx)

	_show_part_card(part)


# ══════════════════════════════════════════════════════════════════════════════
# Channel ring (Change Lens)
# ══════════════════════════════════════════════════════════════════════════════

func _build_channel_ring(origin: Vector2) -> void:
	_channel_btns.clear()
	var center := _angle_between(_origin, _sel_skill_center) + 180.0
	var angles := _angles_for(CHANNELS.size(), 160.0, center)
	for i in CHANNELS.size():
		var ch : Dictionary = CHANNELS[i]
		var wrapper := _make_wrapper()
		_root_layer.add_child(wrapper)
		var btn := _make_ring_btn("", false, false, ch["color"])
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(btn)
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
		_channel_btns.append(btn)
		var cap_ch := ch
		var cap_i  := i
		btn.pressed.connect(func(): _on_channel_pressed(cap_ch, cap_i))
		_animate_arc(wrapper, btn, origin,
			RADIAL_START_ANGLE, angles[i],
			true, ch["label"],
			CHANNEL_RADIUS)


func _on_channel_pressed(ch: Dictionary, idx: int) -> void:
	var val : int = ch["value"]
	if _sel_channel == val:
		# Second press — confirm
		close(true)
		emit_signal("skill_chosen", "special")
		emit_signal("filter_chosen", val)
		emit_signal("confirmed")
		return

	_sel_channel = val
	_clear_info_card()

	for i in _channel_btns.size():
		_set_btn_selected(_channel_btns[i], i == idx)

	_show_channel_card(ch)


# ══════════════════════════════════════════════════════════════════════════════
# Info cards
# ══════════════════════════════════════════════════════════════════════════════

func _morph_skill_btn_to_card(idx: int, skill: Dictionary) -> void:
	if idx >= _skill_wrappers.size(): return
	var wrapper : Control = _skill_wrappers[idx]
	var btn     : Button  = _skill_btns[idx]
	if not is_instance_valid(wrapper): return

	var center := wrapper.position + wrapper.size * 0.5
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Phase 1: collapse in to a point (EASE_IN)
	var tw_in := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw_in.tween_method(_skill_card_pop_cb.bind(wrapper, btn, center, RING_BTN_H, RING_BTN_H),
			1.0, 0.0, RING_POP_TIME)
	await tw_in.finished
	if not is_instance_valid(wrapper): return

	# Swap content while invisible
	btn.text = ""
	var card_sbox := StyleBoxFlat.new()
	card_sbox.bg_color     = C_BG
	card_sbox.border_color = C_ACCENT
	card_sbox.set_border_width_all(0)
	card_sbox.border_width_top = 2
	card_sbox.set_corner_radius_all(int(RING_BTN_H * 0.5))
	card_sbox.set_content_margin_all(12)
	for k in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(k, card_sbox)

	var vbox := VBoxContainer.new()

	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN

	vbox.add_theme_constant_override("separation", 6)

	vbox.add_theme_constant_override("margin_top", 4)
	vbox.add_theme_constant_override("margin_right", 4)
	vbox.add_theme_constant_override("margin_left", 4)


	btn.add_child(vbox)


	var name_lbl := _make_label(
			str(skill.get("name", skill.get("key", "?"))).to_upper(), 14, C_TEXT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var desc : String = str(skill.get("summary", ""))
	if desc != "":
		var dl := _make_label(desc, 12, C_DIM)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(dl)

	# Phase 2: expand out to card size (EASE_OUT)
	var tw_out := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_out.tween_method(_skill_card_pop_cb.bind(wrapper, btn, center, 120.0, 90.0),
			0.0, 1.0, RING_POP_TIME * 1.5)
	await tw_out.finished
	if is_instance_valid(btn):
		btn.mouse_filter = Control.MOUSE_FILTER_STOP


func _skill_card_pop_cb(t: float, wrapper: Control, btn: Button,
		center: Vector2, target_w: float, target_h: float) -> void:
	if not is_instance_valid(wrapper): return
	var w      : float = lerpf(0.0, target_w, t)
	var h      : float = lerpf(0.0, target_h, t)
	var radius : float = lerpf(target_w * 0.5, 8.0, t)
	wrapper.custom_minimum_size = Vector2(w, h)
	wrapper.size                = Vector2(w, h)
	wrapper.position = Vector2(
		center.x - w * 0.5,
		center.y - RING_BTN_H * 0.5
	)

	btn.size = Vector2(w, h)
	for key in ["normal", "hover", "pressed", "focus"]:
		var s : StyleBoxFlat = btn.get_theme_stylebox(key)
		if s is StyleBoxFlat:
			s.set_corner_radius_all(int(radius))


func _show_target_card(actor: BattleActor) -> void:
	_clear_info_card()
	var card := _make_card(Vector2(180, 80))
	card.position = _origin + Vector2(20, 20)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
	card.add_child(vbox)
	vbox.add_child(_make_label(actor.name, 13, C_TEXT))
	vbox.add_child(_make_label("HP  %d / %d" % [actor.hp, actor.max_hp], 10, C_DIM))
	_root_layer.add_child(card)
	_info_card = card


func _show_part_card(part: BodyPartData) -> void:
	_clear_info_card()
	var card := _make_card(Vector2(180, 70))
	card.position = _origin + Vector2(20, 20)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
	card.add_child(vbox)
	vbox.add_child(_make_label(part.part_name, 13, C_TEXT))
	var detail : String
	if not part.already_seen:
		detail = "unknown"
	else:
		detail = "x%.2f dmg" % part.damage_multiplier
		if part.is_cognitohazard: detail += "  [hazard]"
	vbox.add_child(_make_label(detail, 10, C_DIM))
	_root_layer.add_child(card)
	_info_card = card


func _show_channel_card(ch: Dictionary) -> void:
	_clear_info_card()
	var card := _make_card(Vector2(180, 70))
	card.position = _origin + Vector2(20, 20)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
	card.add_child(vbox)
	vbox.add_child(_make_label("Remove " + ch["label"], 13, C_TEXT))
	vbox.add_child(_make_label("channel filter", 10, C_DIM))
	_root_layer.add_child(card)
	_info_card = card


func _clear_info_card() -> void:
	if is_instance_valid(_info_card):
		_info_card.queue_free()
		_info_card = null


# ══════════════════════════════════════════════════════════════════════════════
# Ring clear helpers
# ══════════════════════════════════════════════════════════════════════════════

func _clear_target_ring() -> void:
	for b in _target_btns:
		if is_instance_valid(b):
			var w : Control = b.get_parent()
			if is_instance_valid(w): w.queue_free()
	_target_btns.clear()


func _clear_part_ring() -> void:
	for b in _part_btns:
		if is_instance_valid(b):
			var w : Control = b.get_parent()
			if is_instance_valid(w): w.queue_free()
	_part_btns.clear()


func _clear_channel_ring() -> void:
	for b in _channel_btns:
		if is_instance_valid(b):
			var w : Control = b.get_parent()
			if is_instance_valid(w): w.queue_free()
	_channel_btns.clear()


# ══════════════════════════════════════════════════════════════════════════════
# Dismiss on click-outside
# ══════════════════════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(_root_layer): return
	if event is InputEventMouseButton and event.pressed:
		close()


# ══════════════════════════════════════════════════════════════════════════════
# Ring animation (same machinery as dungeon_map_3d)
# ══════════════════════════════════════════════════════════════════════════════

func _animate_arc(wrapper: Control, btn: Button, origin: Vector2,
		start_deg: float, final_deg: float,
		was_revealed: bool, label: String, radius: float) -> void:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(
		_ring_arc_cb.bind(wrapper, origin, start_deg, final_deg, radius),
		0.0, 1.0, RING_ROLL_TIME)
	await tw.finished
	if not is_instance_valid(btn): return
	if was_revealed:
		btn.text = label
		var center := wrapper.position + Vector2(RING_BTN_H * 0.5, RING_BTN_H * 0.5)
		await _pop_ring_btn(wrapper, btn, center)
		return
	btn.mouse_filter = Control.MOUSE_FILTER_STOP


func _ring_arc_cb(t: float, wrapper: Control, origin: Vector2,
		start_deg: float, final_deg: float, radius_max: float) -> void:
	if not is_instance_valid(wrapper): return
	var angle_rad : float   = deg_to_rad(lerpf(start_deg, final_deg, t))
	var radius : float = radius_max * t
	var center    : Vector2 = origin + Vector2(cos(angle_rad), sin(angle_rad)) * radius
	var sz        : Vector2 = Vector2(RING_BTN_H, RING_BTN_H)
	wrapper.custom_minimum_size = sz
	wrapper.size                = sz
	wrapper.position            = center - sz * 0.5


func _pop_ring_btn(wrapper: Control, btn: Button, final_center: Vector2) -> void:
	if not is_instance_valid(wrapper): return
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(true)
	tw.tween_method(_ring_pop_cb.bind(wrapper, btn, final_center), 0.0, 1.0, RING_POP_TIME)
	await tw.finished
	if is_instance_valid(btn):
		btn.mouse_filter = Control.MOUSE_FILTER_STOP


func _ring_pop_cb(t: float, wrapper: Control, btn: Button, center: Vector2) -> void:
	if not is_instance_valid(wrapper): return
	var w      : float = lerpf(RING_BTN_H, RING_BTN_W, t)
	var radius : float = lerpf(RING_BTN_H * 0.5, 14.0, t)
	wrapper.custom_minimum_size = Vector2(w, RING_BTN_H)
	wrapper.size                = Vector2(w, RING_BTN_H)
	wrapper.position            = center - Vector2(w * 0.5, RING_BTN_H * 0.5)
	btn.size = Vector2(w, RING_BTN_H)
	for key in ["normal", "hover", "pressed", "focus"]:
		var s : StyleBoxFlat = btn.get_theme_stylebox(key)
		if s is StyleBoxFlat:
			s.set_corner_radius_all(int(radius))


# ══════════════════════════════════════════════════════════════════════════════
# Factory helpers
# ══════════════════════════════════════════════════════════════════════════════

func _make_wrapper() -> Control:
	var w := Control.new()
	w.clip_contents       = true
	w.custom_minimum_size = Vector2(RING_BTN_H, RING_BTN_H)
	w.size                = Vector2(RING_BTN_H, RING_BTN_H)
	return w


func _make_ring_btn(label_text: String, ally: bool = false,
		part: bool = false, color_override: Color = Color(-1,-1,-1,-1)) -> Button:
	var btn := Button.new()
	btn.text          = label_text
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_theme_font_size_override("font_size", 11)

	var border_col : Color
	if color_override.r >= 0.0:
		border_col = color_override
	elif part:
		border_col = C_PART
	elif ally:
		border_col = C_ALLY
	else:
		border_col = C_ENEMY

	var sbox := StyleBoxFlat.new()
	sbox.bg_color     = C_BG
	sbox.border_color = C_BORDER
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(int(RING_BTN_H * 0.5))
	sbox.set_content_margin_all(8)

	var sbox_h := StyleBoxFlat.new()
	sbox_h.bg_color     = C_SEL
	sbox_h.border_color = border_col
	sbox_h.set_border_width_all(2)
	sbox_h.set_corner_radius_all(int(RING_BTN_H * 0.5))
	sbox_h.set_content_margin_all(8)

	btn.add_theme_stylebox_override("normal",  sbox)
	btn.add_theme_stylebox_override("hover",   sbox_h)
	btn.add_theme_stylebox_override("pressed", sbox_h)
	btn.add_theme_stylebox_override("focus",   sbox)
	return btn


func _make_card(sz: Vector2) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = sz
	var sbox := StyleBoxFlat.new()
	sbox.bg_color     = C_BG
	sbox.border_color = C_BORDER
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(6)
	sbox.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", sbox)
	return card


func _make_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _set_btn_selected(btn: Button, selected: bool) -> void:
	var wrapper := btn.get_parent() as Control
	if not is_instance_valid(wrapper): return
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(wrapper, "modulate:a", 1.0 if selected else 0.45, 0.12)
