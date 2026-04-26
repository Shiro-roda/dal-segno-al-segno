extends Control
# Battle results screen — shown after every battle before returning to the dungeon.

signal results_dismissed
signal reward_chosen(reward: Dictionary)

const C_BG     := Color(0.06, 0.05, 0.05, 0.97)
const C_BORDER := Color(0.35, 0.28, 0.22, 1.0)
const C_ACCENT := Color(0.72, 0.18, 0.18, 1.0)
const C_TEXT   := Color(0.88, 0.83, 0.74, 1.0)
const C_DIM    := Color(0.55, 0.50, 0.43, 1.0)
const C_GREEN  := Color(0.40, 0.80, 0.45, 1.0)
const C_RED    := Color(0.85, 0.30, 0.28, 1.0)

var _victory        : bool       = false
var _party          : Array      = []
var _exp_per_member : Dictionary = {}
var _level_ups      : Dictionary = {}
var _rewards        : Array      = []  # Array[Dictionary] — reward choices to pick from
var _hp_labels      : Dictionary = {}  # PartyMemberData -> Label

@onready var _bg   : ColorRect      = $BG
@onready var _vbox : VBoxContainer  = $CenterContainer/Panel/VBox


func setup(victory: bool, party_members: Array, exp_per_member: Dictionary = {},
		level_up_events: Dictionary = {}, reward_choices: Array = []) -> void:
	_victory        = victory
	_party          = party_members
	_exp_per_member = exp_per_member
	_level_ups      = level_up_events
	_rewards        = reward_choices
	_build_ui()


func _ready() -> void:
	GlobalTheme.apply(self)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = C_BG
	# Style the Panel node from the scene
	var panel := $CenterContainer/Panel as PanelContainer
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.09, 0.08, 0.07, 1.0)
	ps.border_color = C_BORDER
	ps.set_border_width_all(2)
	ps.set_content_margin_all(40)
	panel.add_theme_stylebox_override("panel", ps)


func _build_ui() -> void:
	_vbox.add_theme_constant_override("separation", 18)
	# Clear any leftover children (safe to call multiple times)
	for c in _vbox.get_children():
		c.queue_free()

	var vbox := _vbox

	# --- Title ---
	var title := Label.new()
	title.text = "VICTORY" if _victory else "DEFEATED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", C_GREEN if _victory else C_RED)
	vbox.add_child(title)

	_divider(vbox)

	# --- Party table ---
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 8)
	vbox.add_child(table)

	table.add_child(_make_row(["NAME", "CORP"], [C_DIM, C_DIM], 12, true))

	for m_raw in _party:
		var m := m_raw as PartyMemberData
		if m == null:
			continue
		var cd : CharacterData = m.character
		var max_hp : int  = cd.base_max_hp + m.bonus_max_hp
		var dead   : bool = m.current_hp <= 0
		var hp_str := "DEAD" if dead else "%d / %d" % [m.current_hp, max_hp]
		var nm_col := Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.4) if dead else C_TEXT
		var hp_col := C_RED if dead else C_TEXT
		var row := _make_row([cd.display_name, hp_str], [nm_col, hp_col], 16, false)
		table.add_child(row)
		# Keep a ref to the HP label so reward_chosen can refresh it.
		var hp_lbl : Label = row.get_child(1)
		_hp_labels[m] = hp_lbl
		m.hp_changed.connect(func(): _refresh_hp_label(m))

	_divider(vbox)

	# --- EXP section (victory only) ---
	if _victory and not _exp_per_member.is_empty():
		var exp_vbox := VBoxContainer.new()
		exp_vbox.add_theme_constant_override("separation", 8)
		vbox.add_child(exp_vbox)

		exp_vbox.add_child(_make_row(["EXP", ""], [C_DIM, C_DIM], 12, true))

		for m_raw in _party:
			var m := m_raw as PartyMemberData
			if m == null:
				continue
			var cname := m.character.display_name
			var share : int = _exp_per_member.get(cname, 0)
			if share <= 0:
				continue
			var next := LevelTable.exp_needed_for_level(m.level + 1)
			var prog  := "%d / %d" % [m.exp, next] if next > 0 else "MAX"
			exp_vbox.add_child(_make_row(
				[cname, "+%d EXP   Lv.%d  (%s)" % [share, m.level, prog]],
				[C_TEXT, C_DIM], 14, false))

		if not _level_ups.is_empty():
			_divider(exp_vbox)
			for cname in _level_ups:
				for ev in _level_ups[cname]:
					var stat_display := {"hp": "CORP", "will": "AP", "sharp": "SHARP", "flat": "FLAT", "tempo": "TEMPO"}
					var raw_stat : String = ev.get("stat", "")
					var stat_label : String = stat_display.get(raw_stat, raw_stat.to_upper())
					var s := "  +%d %s" % [ev["amount"], stat_label] if raw_stat != "" else ""
					var u := "  UNLOCKED: %s" % ev["unlock"].replace("_", " ").to_upper() if ev.get("unlock", "") != "" else ""
					var lu := Label.new()
					lu.text = "%s  →  LV.%d%s%s" % [cname.to_upper(), ev["level"], s, u]
					lu.add_theme_font_size_override("font_size", 13)
					lu.add_theme_color_override("font_color", C_GREEN)
					exp_vbox.add_child(lu)

		_divider(vbox)

	# --- Reward picker (victory + rewards provided) ---
	if _victory and not _rewards.is_empty():
		var rew_lbl := Label.new()
		rew_lbl.text = "CHOOSE A REWARD"
		rew_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rew_lbl.add_theme_font_size_override("font_size", 13)
		rew_lbl.add_theme_color_override("font_color", C_DIM)
		vbox.add_child(rew_lbl)
		var rew_row := HBoxContainer.new()
		rew_row.alignment = BoxContainer.ALIGNMENT_CENTER
		rew_row.add_theme_constant_override("separation", 12)
		vbox.add_child(rew_row)
		for reward in _rewards:
			var rb := Button.new()
			rb.text = reward.get("label", "?")
			rb.custom_minimum_size = Vector2(120, 56)
			rb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rb.add_theme_font_size_override("font_size", 13)
			rb.add_theme_color_override("font_color", C_TEXT)
			var rs := StyleBoxFlat.new()
			rs.bg_color = Color(0.14, 0.12, 0.10)
			rs.border_color = C_ACCENT
			rs.set_border_width_all(1)
			rs.set_content_margin_all(8)
			var rs_h := rs.duplicate() as StyleBoxFlat
			rs_h.bg_color = Color(0.25, 0.15, 0.10)
			rb.add_theme_stylebox_override("normal", rs)
			rb.add_theme_stylebox_override("hover",  rs_h)
			rb.add_theme_stylebox_override("pressed", rs_h)
			rb.add_theme_stylebox_override("focus",  rs)
			var captured : Dictionary = reward
			rb.pressed.connect(func():
				# Disable all reward buttons after pick
				for sib in rew_row.get_children():
					sib.disabled = true
				emit_signal("reward_chosen", captured)
			)
			rew_row.add_child(rb)
		_divider(vbox)

	# --- Continue button ---
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var btn := Button.new()
	btn.text = "CONTINUE"
	btn.custom_minimum_size = Vector2(200, 48)
	btn.add_theme_font_size_override("font_size", 16)
	for col in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(col, C_TEXT)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = C_ACCENT
	sbox.border_color = C_BORDER
	sbox.set_border_width_all(1)
	sbox.set_content_margin_all(10)
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, sbox)
	btn.pressed.connect(func(): emit_signal("results_dismissed"))
	btn_row.add_child(btn)

	var hint := Label.new()
	hint.text = "[ENTER] continue"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", C_DIM)
	vbox.add_child(hint)


func _refresh_hp_label(m: PartyMemberData) -> void:
	var lbl : Label = _hp_labels.get(m)
	if lbl == null or not is_instance_valid(lbl):
		return
	var max_hp : int = m.character.base_max_hp + m.bonus_max_hp
	var dead   : bool = m.current_hp <= 0
	lbl.text = "DEAD" if dead else "%d / %d" % [m.current_hp, max_hp]
	lbl.add_theme_color_override("font_color", C_RED if dead else C_TEXT)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		emit_signal("results_dismissed")
		get_viewport().set_input_as_handled()


func _divider(parent: Control) -> void:
	var d := ColorRect.new()
	d.color = C_BORDER
	d.custom_minimum_size = Vector2(0, 1)
	parent.add_child(d)


func _make_row(texts: Array, colors: Array, font_size: int, is_header: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	for i in texts.size():
		var lbl := Label.new()
		lbl.text = texts[i]
		lbl.add_theme_font_size_override("font_size", font_size)
		lbl.add_theme_color_override("font_color",
			C_DIM if is_header else (colors[i] if i < colors.size() else C_TEXT))
		if i == 0:
			lbl.custom_minimum_size = Vector2(340, 0)
		else:
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(lbl)
	return row
