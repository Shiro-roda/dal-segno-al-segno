extends Control
class_name ChapelEvent
# Chapel rest event. Shows rest options as cards with a name and description.
# Supports fixed (RestOption.val_override) and random-rolled values.
# Also shows a Segno button if the room's allows_segno is true.
# Emits event_finished when the player picks an option or leaves.

signal event_finished

const C_BG       := Color(0.05, 0.04, 0.04, 1.0)
const C_BORDER   := Color(0.35, 0.28, 0.22, 1.0)
const C_ACCENT   := Color(0.52, 0.42, 0.28, 1.0)
const C_TEXT     := Color(0.88, 0.83, 0.74, 1.0)
const C_DIM      := Color(0.55, 0.50, 0.43, 1.0)
const C_SELECTED := Color(0.52, 0.42, 0.28, 0.22)
const C_SEGNO    := Color(0.32, 0.44, 0.58, 1.0)   # muted blue for segno button

const CARD_W := 220
const CARD_H := 200

var _room        : RoomInstance
var _run_state   : RunState
var _options     : Array = []   # Array of {name, desc, type, val}
var _allows_segno : bool = false

var _selected_index : int = -1
var _cards : Array = []
var _confirm_btn : Button
var _outer : VBoxContainer


func _ready() -> void:
	GlobalTheme.apply(self)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func setup(room: RoomInstance, run_state: RunState) -> void:
	_room      = room
	_run_state = run_state
	_allows_segno = room.room_data != null and room.room_data.allows_segno
	_resolve_options()
	if _outer != null:
		_populate_outer()


func _resolve_options() -> void:
	# Use fixed override options from RoomData if present
	if _room.room_data != null and not _room.room_data.rest_options_override.is_empty():
		for ro in _room.room_data.rest_options_override:
			var val : int = ro.val_override
			if val < 0:
				val = _roll_for_type(ro.type)
			_options.append({"name": ro.option_name, "desc": ro.description, "type": ro.type, "val": val})
		return

	# Fallback: generate random options (same logic as dungeonUI)
	if not _room.rest_options.is_empty():
		for o in _room.rest_options:
			_options.append({"name": o["text"], "desc": "", "type": o["type"], "val": o["val"]})
		return

	var members  = _run_state.party_members
	var avg_hp_lost : int = 0
	for m in members:
		avg_hp_lost += m.character.base_max_hp - m.current_hp
	avg_hp_lost /= max(1, members.size())
	var avg_max_hp : int = 0
	for m in members:
		avg_max_hp += m.character.base_max_hp
	avg_max_hp /= max(1, members.size())
	var pct_hp  := randi_range(int(avg_hp_lost * 0.4), int(avg_hp_lost * 1.6) + 1)
	var flat_hp := randi_range(int(avg_max_hp  * 0.3), int(avg_max_hp  * 0.7))

	var avg_will_lost : int = 0
	var will_members  : int = 0
	for m in members:
		if m.has_will():
			avg_will_lost += m.max_will - m.will
			will_members  += 1
	var pct_will  : int = 0
	var flat_will : int = 0
	if will_members > 0:
		avg_will_lost /= will_members
		var avg_max_will : int = 0
		for m in members:
			if m.has_will(): avg_max_will += m.max_will
		avg_max_will /= will_members
		pct_will  = randi_range(int(avg_will_lost * 0.4), int(avg_will_lost * 1.6) + 1)
		flat_will = randi_range(int(avg_max_will  * 0.3), int(avg_max_will  * 0.7))

	var ammo_spent := _run_state.max_ammo - _run_state.ammo
	var pct_ammo  := randi_range(int(ammo_spent              * 0.4), int(ammo_spent              * 1.6) + 1)
	var flat_ammo := randi_range(int(_run_state.max_ammo     * 0.3), int(_run_state.max_ammo     * 0.7))

	var all : Array = [
		{"name": "Rest",     "desc": "", "type": "hp",   "val": pct_hp},
		{"name": "Slumber",  "desc": "", "type": "hp",   "val": flat_hp},
		{"name": "Ruminate", "desc": "", "type": "will", "val": pct_will},
		{"name": "Pray",     "desc": "", "type": "will", "val": flat_will},
		{"name": "Scavenge", "desc": "", "type": "ammo", "val": pct_ammo},
		{"name": "Desecrate","desc": "", "type": "ammo", "val": flat_ammo},
	]
	all.shuffle()
	var chosen := all.slice(0, 3)
	# Cache on room so re-entry shows same choices
	_room.rest_options = chosen.map(func(o): return {"text": o["name"], "type": o["type"], "val": o["val"]})
	_options = chosen


func _roll_for_type(type: String) -> int:
	var members = _run_state.party_members
	match type:
		"hp":
			var avg_lost : int = 0
			for m in members:
				avg_lost += m.character.base_max_hp - m.current_hp
			avg_lost /= max(1, members.size())
			return randi_range(int(avg_lost * 0.4), int(avg_lost * 1.6) + 1)
		"will":
			var total : int = 0
			var count : int = 0
			for m in members:
				if m.has_will():
					total += m.max_will - m.will
					count += 1
			if count == 0: return 0
			var avg := total / count
			return randi_range(int(avg * 0.4), int(avg * 1.6) + 1)
		"ammo":
			var spent := _run_state.max_ammo - _run_state.ammo
			return randi_range(int(spent * 0.4), int(spent * 1.6) + 1)
	return 0


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_outer = VBoxContainer.new()
	_outer.add_theme_constant_override("separation", 0)
	center.add_child(_outer)

	if _room != null:
		_populate_outer()


func _populate_outer() -> void:
	for c in _outer.get_children():
		c.queue_free()
	_cards.clear()
	_selected_index = -1

	var top_space := Control.new()
	top_space.custom_minimum_size = Vector2(0, 32)
	_outer.add_child(top_space)

	var prompt := Label.new()
	prompt.text = _room.room_data.room_name.to_upper() if _room and _room.room_data else "REST"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", C_DIM)
	_outer.add_child(prompt)

	var div := ColorRect.new()
	div.color = C_ACCENT
	div.custom_minimum_size = Vector2(0, 1)
	_outer.add_child(div)

	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 28)
	_outer.add_child(spacer1)

	var card_row := HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 24)
	_outer.add_child(card_row)

	for i in _options.size():
		var card := _make_card(_options[i], i)
		card_row.add_child(card)
		_cards.append(card)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 28)
	_outer.add_child(spacer2)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	_outer.add_child(btn_row)

	# Confirm button
	_confirm_btn = Button.new()
	_confirm_btn.text = "CHOOSE"
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

	# Leave button
	var leave_btn := Button.new()
	leave_btn.text = "LEAVE"
	leave_btn.custom_minimum_size = Vector2(100, 44)
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
	leave_btn.pressed.connect(func(): emit_signal("event_finished"))
	btn_row.add_child(leave_btn)

	# Segno button (separate row, only if allowed)
	if _allows_segno:
		var spacer3 := Control.new()
		spacer3.custom_minimum_size = Vector2(0, 12)
		_outer.add_child(spacer3)

		var segno_row := HBoxContainer.new()
		segno_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_outer.add_child(segno_row)

		var segno_btn := Button.new()
		var has_segno := GameController.current_dungeon_run != null \
			and GameController.current_dungeon_run.last_segno_pos != Vector2i(-999, -999)
		segno_btn.text = "MOVE SEGNO HERE" if has_segno else "PLACE SEGNO HERE"
		segno_btn.custom_minimum_size = Vector2(280, 40)
		segno_btn.add_theme_font_size_override("font_size", 12)
		segno_btn.add_theme_color_override("font_color", C_TEXT)
		segno_btn.add_theme_color_override("font_hover_color", C_TEXT)
		segno_btn.add_theme_color_override("font_focus_color", C_TEXT)
		var seg_sbox := StyleBoxFlat.new()
		seg_sbox.bg_color = C_SEGNO
		seg_sbox.border_color = C_BORDER
		seg_sbox.set_border_width_all(1)
		seg_sbox.set_content_margin_all(8)
		segno_btn.add_theme_stylebox_override("normal",  seg_sbox)
		segno_btn.add_theme_stylebox_override("hover",   seg_sbox)
		segno_btn.add_theme_stylebox_override("pressed", seg_sbox)
		segno_btn.add_theme_stylebox_override("focus",   seg_sbox)
		segno_btn.pressed.connect(_on_segno)
		segno_row.add_child(segno_btn)

	var bot_space := Control.new()
	bot_space.custom_minimum_size = Vector2(0, 24)
	_outer.add_child(bot_space)


func _make_card(option: Dictionary, idx: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)

	var normal_sbox := StyleBoxFlat.new()
	normal_sbox.bg_color = Color(0.10, 0.09, 0.08, 1.0)
	normal_sbox.border_color = C_BORDER
	normal_sbox.set_border_width_all(2)
	normal_sbox.set_content_margin_all(20)
	card.add_theme_stylebox_override("panel", normal_sbox)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	card.add_child(inner)

	var name_lbl := Label.new()
	name_lbl.text = option["name"].to_upper()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	inner.add_child(name_lbl)

	var div := ColorRect.new()
	div.color = C_BORDER
	div.custom_minimum_size = Vector2(0, 1)
	inner.add_child(div)

	# Effect summary line
	var effect_lbl := Label.new()
	effect_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect_lbl.add_theme_font_size_override("font_size", 13)
	effect_lbl.add_theme_color_override("font_color", C_ACCENT)
	var val : int = option["val"]
	match option["type"]:
		"hp":    effect_lbl.text = "+%d CORP" % val
		"will":  effect_lbl.text = "+%d AP" % val
		"ammo":  effect_lbl.text = "+%d BB" % val
		"segno": effect_lbl.text = "1× Segno"
		_:       effect_lbl.text = str(val)
	inner.add_child(effect_lbl)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = option.get("desc", "")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", C_DIM)
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(desc_lbl)

	# Invisible full-card button
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
		sbox.bg_color     = C_SELECTED if sel else Color(0.10, 0.09, 0.08, 1.0)
		sbox.border_color = C_ACCENT   if sel else C_BORDER
		sbox.set_border_width_all(2)
		sbox.set_content_margin_all(20)
		card.add_theme_stylebox_override("panel", sbox)
	_confirm_btn.disabled = false


func _on_confirm() -> void:
	if _selected_index < 0:
		return
	var opt : Dictionary = _options[_selected_index]
	_room.rested = true
	var rs := _run_state
	match opt["type"]:
		"hp":
			for member in rs.party_members:
				member.current_hp = mini(member.current_hp + opt["val"], member.character.base_max_hp)
		"will":
			for member in rs.party_members:
				if member.has_will():
					member.restore_will(opt["val"])
		"ammo":
			rs.restore_ammo(opt["val"])
		"segno":
			var segno_data := SegnoItem.new()
			var segno_inst := ItemInstance.new()
			segno_inst.item_data = segno_data
			segno_inst.stacks = 1
			rs.inventory.append(segno_inst)
	emit_signal("event_finished")


func _on_segno() -> void:
	# Delegate to dungeon controller; it will show the segno event then return here
	var dc = get_tree().get_first_node_in_group("dungeon_controller")
	if dc:
		dc.place_segno(true)
