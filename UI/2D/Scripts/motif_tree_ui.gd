extends Control
## MotifTreeUI — between-run skill upgrade screen.
## Shown from the main menu via GameControl._open_motif_tree().
## Emits `closed` when the player exits back to the main menu.

signal closed

var C_BG       := Color.BLACK
var C_TEXT     := Color.WHITE
var C_DIM      := Color.WHITE
var C_ACCENT   := Color.WHITE
var C_HOVER    := Color.BLACK
const C_UNLOCKED := Color(0.18, 0.50, 0.22, 1.0)
const C_LOCKED   := Color(0.25, 0.22, 0.20, 1.0)
const C_AVAIL    := Color(0.55, 0.45, 0.12, 1.0)
const FONT_PATH  := "res://UI/Themes/Fonts/TerminalVector.ttf"

func _refresh_palette() -> void:
	var p := ThemeManager.palette
	C_BG     = p.bg
	C_TEXT   = p.text
	C_DIM    = p.dim
	C_ACCENT = p.primary
	C_HOVER  = p.hover

func _on_theme_changed(_id: int) -> void:
	_refresh_palette()
	for c in get_children(): c.queue_free()
	_points_label = null
	_detail_panel = null
	_detail_name = null
	_detail_char = null
	_detail_skill = null
	_detail_desc = null
	_detail_cost = null
	_unlock_btn = null
	_node_buttons.clear()
	_selected_id = ""
	_build_ui()

var _font : Font
var _selected_id : String = ""

# UI refs
var _points_label  : Label
var _detail_panel  : Control
var _detail_name   : Label
var _detail_char   : Label
var _detail_skill  : Label
var _detail_desc   : Label
var _detail_cost   : Label
var _unlock_btn    : Button
var _node_buttons  : Dictionary = {}   # motif_id -> Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_refresh_palette()
	ThemeManager.theme_changed.connect(_on_theme_changed)
	_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font
	_build_ui()
	MetaProgress.motif_points_changed.connect(_on_points_changed)
	MetaProgress.motif_unlocked.connect(_on_motif_unlocked)


func _build_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Root layout: left panel (tree) + right panel (detail)
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	add_child(hbox)

	# ── Left: tree scroll ────────────────────────────────────────────────────
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(780, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(left)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	left.add_child(header)

	var title := Label.new()
	title.text = "MOTIF TREE"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_font_override("font", _font)
	title.add_theme_color_override("font_color", C_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 16)
	_points_label.add_theme_font_override("font", _font)
	_points_label.add_theme_color_override("font_color", C_AVAIL)
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_points_label)
	_update_points_label()

	var rule := ColorRect.new()
	rule.color = C_ACCENT
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(rule)

	# Scrollable area for the nodes, organised by character
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)

	var tree_col := VBoxContainer.new()
	tree_col.add_theme_constant_override("separation", 16)
	tree_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tree_col)

	# Organise by character
	var chars := ["Kendall", "Hue", "Indra", "Vritra"]
	for char_name in chars:
		var nodes : Array = MotifRegistry.get_for_character(char_name)
		if nodes.is_empty():
			continue
		tree_col.add_child(_make_char_section(char_name, nodes))

	# ── Right: detail panel ───────────────────────────────────────────────────
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(340, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	hbox.add_child(right)

	var right_bg := StyleBoxFlat.new()
	right_bg.bg_color = Color(0.06, 0.05, 0.04)
	right_bg.border_color = C_ACCENT
	right_bg.set_border_width_all(1)

	_detail_panel = PanelContainer.new()
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_detail_panel)
	(_detail_panel as PanelContainer).add_theme_stylebox_override("panel", right_bg)

	var detail_col := VBoxContainer.new()
	detail_col.add_theme_constant_override("separation", 8)
	_detail_panel.add_child(detail_col)

	_detail_name = _make_label("", 18, C_TEXT)
	_detail_char = _make_label("", 12, C_DIM)
	_detail_skill = _make_label("", 12, C_ACCENT)
	_detail_desc = _make_label("", 12, C_TEXT)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_cost = _make_label("", 13, C_AVAIL)

	detail_col.add_child(_detail_name)
	detail_col.add_child(_detail_char)
	detail_col.add_child(_detail_skill)
	var detail_rule := ColorRect.new()
	detail_rule.color = C_ACCENT
	detail_rule.custom_minimum_size = Vector2(0, 1)
	detail_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_col.add_child(detail_rule)
	detail_col.add_child(_detail_desc)
	detail_col.add_child(_detail_cost)

	_unlock_btn = Button.new()
	_unlock_btn.text = "UNLOCK"
	_unlock_btn.add_theme_font_override("font", _font)
	_unlock_btn.add_theme_font_size_override("font_size", 14)
	_unlock_btn.custom_minimum_size = Vector2(0, 44)
	_unlock_btn.pressed.connect(_on_unlock_pressed)
	_unlock_btn.visible = false
	detail_col.add_child(_unlock_btn)

	# Back button at bottom of right panel
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)

	var back_btn := Button.new()
	back_btn.text = "← BACK TO MENU"
	back_btn.custom_minimum_size = Vector2(0, 44)
	back_btn.add_theme_font_override("font", _font)
	back_btn.add_theme_font_size_override("font_size", 13)
	back_btn.add_theme_color_override("font_color", C_DIM)
	back_btn.pressed.connect(func(): closed.emit())
	right.add_child(back_btn)


func _make_char_section(char_name: String, nodes: Array) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)

	var char_label := Label.new()
	char_label.text = char_name.to_upper()
	char_label.add_theme_font_size_override("font_size", 14)
	char_label.add_theme_font_override("font", _font)
	char_label.add_theme_color_override("font_color", C_ACCENT)
	section.add_child(char_label)

	# Group nodes by skill (upgrade + sidegrade under same skill label)
	var by_skill : Dictionary = {}
	for n in nodes:
		var mn : MotifNode = n
		if not by_skill.has(mn.skill_name):
			by_skill[mn.skill_name] = []
		by_skill[mn.skill_name].append(mn)

	for skill in by_skill:
		var skill_row := HBoxContainer.new()
		skill_row.add_theme_constant_override("separation", 6)
		section.add_child(skill_row)

		var skill_lbl := Label.new()
		skill_lbl.text = skill + ":"
		skill_lbl.custom_minimum_size = Vector2(90, 0)
		skill_lbl.add_theme_font_size_override("font_size", 11)
		skill_lbl.add_theme_font_override("font", _font)
		skill_lbl.add_theme_color_override("font_color", C_DIM)
		skill_row.add_child(skill_lbl)

		for mn in by_skill[skill]:
			skill_row.add_child(_make_node_btn(mn))

	return section


func _make_node_btn(mn: MotifNode) -> Button:
	var btn := Button.new()
	btn.text = mn.motif_name
	btn.custom_minimum_size = Vector2(140, 36)
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 12)
	_style_node_btn(btn, mn.motif_id)
	btn.pressed.connect(func(): _select_node(mn.motif_id))
	_node_buttons[mn.motif_id] = btn
	return btn


func _style_node_btn(btn: Button, motif_id: String) -> void:
	var is_unlocked : bool = MetaProgress.is_unlocked(motif_id)
	var can_unlock  : bool = MetaProgress.can_unlock(motif_id)
	var col : Color
	if is_unlocked:
		col = C_UNLOCKED
	elif can_unlock:
		col = C_AVAIL
	else:
		col = C_LOCKED

	var sn := StyleBoxFlat.new()
	sn.bg_color = col.darkened(0.6)
	sn.border_color = col
	sn.set_border_width_all(1)
	sn.set_content_margin_all(8)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = col.darkened(0.3)

	for st in ["normal", "focus"]:
		btn.add_theme_stylebox_override(st, sn)
	for st in ["hover", "pressed"]:
		btn.add_theme_stylebox_override(st, sh)
	for col_key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(col_key, C_TEXT)


func _select_node(motif_id: String) -> void:
	_selected_id = motif_id
	var mn : MotifNode = MotifRegistry.get_node_by_id(motif_id)
	if mn == null:
		return

	_detail_name.text  = mn.motif_name
	_detail_char.text  = mn.character
	_detail_skill.text = mn.skill_name + "  [" + ("EXTENSION" if mn.upgrade_type == MotifNode.UpgradeType.EXTENSION else "VARIATION") + "]"
	_detail_desc.text  = mn.description

	var is_unlocked := MetaProgress.is_unlocked(motif_id)
	var can_unlock  := MetaProgress.can_unlock(motif_id)

	if is_unlocked:
		_detail_cost.text = "✓ Unlocked"
		_detail_cost.add_theme_color_override("font_color", C_UNLOCKED)
		_unlock_btn.visible = false
	elif can_unlock:
		_detail_cost.text = "Cost: %d Motifs  (you have %d)" % [mn.cost, MetaProgress.motif_points]
		_detail_cost.add_theme_color_override("font_color", C_AVAIL)
		_unlock_btn.visible = true
		_unlock_btn.text = "UNLOCK  [%d Motifs]" % mn.cost
	else:
		var missing_prereqs := mn.requires.filter(func(r): return not MetaProgress.is_unlocked(r))
		if missing_prereqs.is_empty():
			_detail_cost.text = "Cost: %d Motifs  (you have %d)" % [mn.cost, MetaProgress.motif_points]
			_detail_cost.add_theme_color_override("font_color", C_ACCENT)
		else:
			var req_names := missing_prereqs.map(func(r):
				var rn := MotifRegistry.get_node_by_id(r)
				return rn.motif_name if rn else r)
			_detail_cost.text = "Requires: " + ", ".join(req_names)
			_detail_cost.add_theme_color_override("font_color", C_DIM)
		_unlock_btn.visible = false


func _on_unlock_pressed() -> void:
	if _selected_id == "":
		return
	if MetaProgress.unlock_motif(_selected_id):
		_select_node(_selected_id)   # refresh detail
		_style_node_btn(_node_buttons[_selected_id], _selected_id)
		_update_points_label()
		# Re-style any nodes that became newly available.
		for id in _node_buttons:
			_style_node_btn(_node_buttons[id], id)


func _on_points_changed(_new_total: int) -> void:
	_update_points_label()


func _on_motif_unlocked(_id: String) -> void:
	for id in _node_buttons:
		_style_node_btn(_node_buttons[id], id)


func _update_points_label() -> void:
	_points_label.text = "%d Motifs" % MetaProgress.motif_points


func _make_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_color_override("font_color", color)
	return lbl
