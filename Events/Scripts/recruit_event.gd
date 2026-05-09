extends Control
# Recruit event - lets the player pick one more support from available_supports.
# If available_supports is empty, completes immediately.

signal event_finished

var C_BG        := Color.BLACK
var C_BORDER    := Color.WHITE
var C_ACCENT    := Color.WHITE
var C_TEXT      := Color.WHITE
var C_DIM       := Color.WHITE
var C_SELECTED  := Color.WHITE

func _refresh_palette() -> void:
	var p := ThemeManager.palette
	C_BG       = p.bg
	C_BORDER   = p.dim
	C_ACCENT   = p.primary
	C_TEXT     = p.text
	C_DIM      = p.dim
	C_SELECTED = Color(p.primary.r, p.primary.g, p.primary.b, 0.22)

func _on_theme_changed(_id: int) -> void:
	_refresh_palette()
	if is_instance_valid(_bg):
		_bg.color = C_BG
	# Rebuild card area with new colors
	if is_instance_valid(_outer):
		for c in _outer.get_children(): c.queue_free()
	_cards.clear()
	_confirm_btn = null
	_selected_index = -1
	if not _available.is_empty():
		_populate_outer()

const CARD_W := 260
const CARD_H := 340

var _selected_index : int = -1
var _cards          : Array = []
var _confirm_btn    : Button
var _available      : Array = []

@onready var _bg    : ColorRect     = $BG
@onready var _outer : VBoxContainer = $CenterContainer/Outer


func _ready() -> void:
	_refresh_palette()
	ThemeManager.theme_changed.connect(_on_theme_changed)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = C_BG
	var run := GameController.current_run
	if run == null or run.available_supports.is_empty():
		# Defer so the caller has time to connect event_finished
		call_deferred("emit_signal", "event_finished")
		return
	_available = run.available_supports.duplicate()
	_populate_outer()


func _populate_outer() -> void:
	# Clear anything already in Outer from the editor
	for c in _outer.get_children():
		c.queue_free()
	_outer.add_theme_constant_override("separation", 0)

	var top_space := Control.new()
	top_space.custom_minimum_size = Vector2(0, 32)
	_outer.add_child(top_space)

	var prompt := Label.new()
	prompt.text = "SOMEONE IS WAITING"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", C_DIM)
	_outer.add_child(prompt)

	var prompt_div := ColorRect.new()
	prompt_div.color = C_ACCENT
	prompt_div.custom_minimum_size = Vector2(0, 1)
	_outer.add_child(prompt_div)

	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 32)
	_outer.add_child(spacer1)

	var card_row := HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 28)
	_outer.add_child(card_row)

	for i in _available.size():
		var card := _make_card(_available[i], i)
		card_row.add_child(card)
		_cards.append(card)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 36)
	_outer.add_child(spacer2)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_outer.add_child(btn_row)

	_confirm_btn = Button.new()
	_confirm_btn.text = "RECRUIT"
	_confirm_btn.custom_minimum_size = Vector2(180, 48)
	_confirm_btn.add_theme_font_size_override("font_size", 16)
	_confirm_btn.add_theme_color_override("font_color", C_TEXT)
	_confirm_btn.add_theme_color_override("font_hover_color", C_TEXT)
	_confirm_btn.add_theme_color_override("font_pressed_color", C_TEXT)
	_confirm_btn.add_theme_color_override("font_focus_color", C_TEXT)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = C_ACCENT
	sbox.border_color = C_BORDER
	sbox.set_border_width_all(1)
	sbox.set_content_margin_all(10)
	var sbox_dis := StyleBoxFlat.new()
	sbox_dis.bg_color = Color(0.18, 0.15, 0.12, 1.0)
	sbox_dis.border_color = C_BORDER
	sbox_dis.set_border_width_all(1)
	sbox_dis.set_content_margin_all(10)
	_confirm_btn.add_theme_stylebox_override("normal",   sbox)
	_confirm_btn.add_theme_stylebox_override("hover",    sbox)
	_confirm_btn.add_theme_stylebox_override("pressed",  sbox)
	_confirm_btn.add_theme_stylebox_override("focus",    sbox)
	_confirm_btn.add_theme_stylebox_override("disabled", sbox_dis)
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(_confirm_btn)

	var leave_btn := Button.new()
	leave_btn.text = "LEAVE (You may not choose again.)"
	leave_btn.custom_minimum_size = Vector2(100, 48)
	leave_btn.add_theme_font_size_override("font_size", 13)
	leave_btn.add_theme_color_override("font_color", C_DIM)
	leave_btn.add_theme_color_override("font_hover_color", C_TEXT)
	leave_btn.add_theme_color_override("font_focus_color", C_DIM)
	var leave_sbox := StyleBoxFlat.new()
	leave_sbox.bg_color = Color(0, 0, 0, 0)
	leave_sbox.border_color = C_BORDER
	leave_sbox.set_border_width_all(1)
	leave_sbox.set_content_margin_all(10)
	leave_btn.add_theme_stylebox_override("normal",  leave_sbox)
	leave_btn.add_theme_stylebox_override("hover",   leave_sbox)
	leave_btn.add_theme_stylebox_override("pressed", leave_sbox)
	leave_btn.add_theme_stylebox_override("focus",   leave_sbox)
	leave_btn.pressed.connect(_on_leave)
	var leave_margin := MarginContainer.new()
	leave_margin.add_theme_constant_override("margin_left", 20)
	leave_margin.add_child(leave_btn)
	btn_row.add_child(leave_margin)

	var bot_space := Control.new()
	bot_space.custom_minimum_size = Vector2(0, 24)
	_outer.add_child(bot_space)


func _make_card(char_data: CharacterData, idx: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.10, 0.09, 1.0)
	normal_style.border_color = C_BORDER
	normal_style.set_border_width_all(2)
	normal_style.set_content_margin_all(22)
	card.add_theme_stylebox_override("panel", normal_style)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	card.add_child(inner)

	var name_lbl := Label.new()
	name_lbl.text = char_data.display_name.to_upper()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	inner.add_child(name_lbl)

	var div := ColorRect.new()
	div.color = C_BORDER
	div.custom_minimum_size = Vector2(0, 1)
	inner.add_child(div)

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 5)
	inner.add_child(stats)

	var stat_lines := [
		["CORP",  str(char_data.base_max_hp)],
		["AP",    str(char_data.base_max_will)],
		["SHARP", str(char_data.base_attack)],
		["FLAT",  str(char_data.base_flat_defense)],
		["TEMPO", str(char_data.tempo)],
	]
	for sl in stat_lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		stats.add_child(row)
		var key := Label.new()
		key.text = sl[0]
		key.custom_minimum_size = Vector2(80, 0)
		key.add_theme_font_size_override("font_size", 13)
		key.add_theme_color_override("font_color", C_DIM)
		row.add_child(key)
		var val := Label.new()
		val.text = sl[1]
		val.add_theme_font_size_override("font_size", 13)
		val.add_theme_color_override("font_color", C_TEXT)
		row.add_child(val)

	var div2 := ColorRect.new()
	div2.color = C_BORDER
	div2.custom_minimum_size = Vector2(0, 1)
	inner.add_child(div2)

	var desc := Label.new()
	desc.text = char_data.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
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
		sbox.bg_color    = C_SELECTED if sel else Color(0.12, 0.10, 0.09, 1.0)
		sbox.border_color = C_ACCENT if sel else C_BORDER
		sbox.set_border_width_all(2)
		sbox.set_content_margin_all(22)
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
	# Pick a random unchosen support as the boss target
	if not run.available_supports.is_empty() and run.boss_target == null:
		run.boss_target = run.available_supports[randi() % run.available_supports.size()]
	emit_signal("event_finished")


func _on_leave() -> void:
	emit_signal("event_finished")
