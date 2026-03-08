extends Control
# Recruit event - lets the player pick one more support from available_supports.
# If available_supports is empty, completes immediately.

signal event_finished

const C_BG        := Color(0.08, 0.07, 0.06, 1.0)
const C_BORDER    := Color(0.35, 0.28, 0.22, 1.0)
const C_ACCENT    := Color(0.72, 0.18, 0.18, 1.0)
const C_TEXT      := Color(0.88, 0.83, 0.74, 1.0)
const C_DIM       := Color(0.55, 0.50, 0.43, 1.0)
const C_SELECTED  := Color(0.72, 0.18, 0.18, 0.22)

var _selected_index : int = -1
var _cards : Array = []
var _confirm_btn : Button
var _available : Array = []  # CharacterData entries

func _ready() -> void:
	var run := GameController.current_run
	if run == null or run.available_supports.is_empty():
		emit_signal("event_finished")
		return
	_available = run.available_supports.duplicate()
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 0)
	add_child(outer)

	var top_space := Control.new()
	top_space.custom_minimum_size = Vector2(0, 80)
	outer.add_child(top_space)

	var prompt := Label.new()
	prompt.text = "SOMEONE IS WAITING"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 14)
	prompt.add_theme_color_override("font_color", C_DIM)
	outer.add_child(prompt)

	var prompt_div := ColorRect.new()
	prompt_div.color = C_ACCENT
	prompt_div.custom_minimum_size = Vector2(0, 1)
	outer.add_child(prompt_div)

	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 40)
	outer.add_child(spacer1)

	var card_row := HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 24)
	card_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	outer.add_child(card_row)

	for i in _available.size():
		var card := _make_card(_available[i], i)
		card_row.add_child(card)
		_cards.append(card)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 48)
	outer.add_child(spacer2)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(btn_row)

	_confirm_btn = Button.new()
	_confirm_btn.text = "RECRUIT"
	_confirm_btn.custom_minimum_size = Vector2(160, 44)
	_confirm_btn.add_theme_font_size_override("font_size", 14)
	_confirm_btn.add_theme_color_override("font_color", C_TEXT)
	_confirm_btn.add_theme_color_override("font_hover_color", C_TEXT)
	_confirm_btn.add_theme_color_override("font_pressed_color", C_TEXT)
	_confirm_btn.add_theme_color_override("font_focus_color", C_TEXT)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = C_ACCENT
	sbox.border_color = C_BORDER
	sbox.set_border_width_all(1)
	sbox.set_content_margin_all(8)
	var sbox_dis := StyleBoxFlat.new()
	sbox_dis.bg_color = Color(0.18, 0.15, 0.12, 1.0)
	sbox_dis.border_color = C_BORDER
	sbox_dis.set_border_width_all(1)
	sbox_dis.set_content_margin_all(8)
	_confirm_btn.add_theme_stylebox_override("normal",   sbox)
	_confirm_btn.add_theme_stylebox_override("hover",    sbox)
	_confirm_btn.add_theme_stylebox_override("pressed",  sbox)
	_confirm_btn.add_theme_stylebox_override("focus",    sbox)
	_confirm_btn.add_theme_stylebox_override("disabled", sbox_dis)
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(_confirm_btn)

	# Leave button (skip)
	var leave_btn := Button.new()
	leave_btn.text = "LEAVE"
	leave_btn.custom_minimum_size = Vector2(100, 44)
	leave_btn.add_theme_font_size_override("font_size", 12)
	leave_btn.add_theme_color_override("font_color", C_DIM)
	leave_btn.add_theme_color_override("font_hover_color", C_TEXT)
	leave_btn.add_theme_color_override("font_focus_color", C_DIM)
	var leave_sbox := StyleBoxFlat.new()
	leave_sbox.bg_color = Color(0, 0, 0, 0)
	leave_sbox.border_color = C_BORDER
	leave_sbox.set_border_width_all(1)
	leave_sbox.set_content_margin_all(8)
	leave_btn.add_theme_stylebox_override("normal",  leave_sbox)
	leave_btn.add_theme_stylebox_override("hover",   leave_sbox)
	leave_btn.add_theme_stylebox_override("pressed", leave_sbox)
	leave_btn.add_theme_stylebox_override("focus",   leave_sbox)
	leave_btn.pressed.connect(_on_leave)
	var leave_margin := MarginContainer.new()
	leave_margin.add_theme_constant_override("margin_left", 16)
	leave_margin.add_child(leave_btn)
	btn_row.add_child(leave_margin)


func _make_card(char_data: CharacterData, idx: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(220, 300)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.10, 0.09, 1.0)
	normal_style.border_color = C_BORDER
	normal_style.set_border_width_all(2)
	normal_style.set_content_margin_all(20)
	card.add_theme_stylebox_override("panel", normal_style)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	card.add_child(inner)

	var name_lbl := Label.new()
	name_lbl.text = char_data.display_name.to_upper()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	inner.add_child(name_lbl)

	var div := ColorRect.new()
	div.color = C_BORDER
	div.custom_minimum_size = Vector2(0, 1)
	inner.add_child(div)

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 4)
	inner.add_child(stats)

	var stat_lines := [
		["HP",    str(char_data.base_max_hp)],
		["WILL",  str(char_data.base_max_will)],
		["ATK",   str(char_data.base_attack)],
		["TEMPO", str(char_data.tempo)],
	]
	for sl in stat_lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		stats.add_child(row)
		var key := Label.new()
		key.text = sl[0]
		key.custom_minimum_size = Vector2(70, 0)
		key.add_theme_font_size_override("font_size", 11)
		key.add_theme_color_override("font_color", C_DIM)
		row.add_child(key)
		var val := Label.new()
		val.text = sl[1]
		val.add_theme_font_size_override("font_size", 11)
		val.add_theme_color_override("font_color", C_TEXT)
		row.add_child(val)

	var div2 := ColorRect.new()
	div2.color = C_BORDER
	div2.custom_minimum_size = Vector2(0, 1)
	inner.add_child(div2)

	var desc := Label.new()
	desc.text = ""
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", C_DIM)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(desc)

	var btn := Button.new()
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.flat = true
	var transparent := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal",  transparent)
	btn.add_theme_stylebox_override("hover",   transparent)
	btn.add_theme_stylebox_override("pressed", transparent)
	btn.add_theme_stylebox_override("focus",   transparent)
	btn.pressed.connect(func(): _select_card(idx))
	card.add_child(btn)

	return card


func _select_card(idx: int) -> void:
	_selected_index = idx
	for i in _cards.size():
		var card : PanelContainer = _cards[i]
		var sel := (i == idx)
		var sbox := StyleBoxFlat.new()
		sbox.bg_color = C_SELECTED if sel else Color(0.12, 0.10, 0.09, 1.0)
		sbox.border_color = C_ACCENT if sel else C_BORDER
		sbox.set_border_width_all(2)
		sbox.set_content_margin_all(20)
		card.add_theme_stylebox_override("panel", sbox)
	_confirm_btn.disabled = false


func _on_confirm() -> void:
	if _selected_index < 0:
		return
	var run := GameController.current_run
	var chosen : CharacterData = _available[_selected_index]
	var member := PartyMemberData.new()
	member.init_from_character(chosen)
	run.party_members.append(member)
	run.available_supports.erase(chosen)
	emit_signal("event_finished")


func _on_leave() -> void:
	emit_signal("event_finished")
