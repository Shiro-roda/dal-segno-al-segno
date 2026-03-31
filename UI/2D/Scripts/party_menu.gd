extends CanvasLayer

# -----------------------------------------------------------------------
# Party / Options overlay menu
# Tab to open/close. Works from dungeon and battle contexts.
# -----------------------------------------------------------------------

signal menu_opened
signal menu_closed

const TAB_PARTY     := 0
const TAB_SKILLS    := 1
const TAB_INVENTORY := 2
const TAB_OPTIONS   := 3

var _open       := false
var _active_tab := TAB_PARTY

# Root panel
var _root_panel   : PanelContainer
var _tab_bar      : HBoxContainer
var _tab_btns     : Array = []
var _pages        : Array = []  # one Control per tab

# Party page node refs
var _party_rows    : Array = []  # VBoxContainers, one per member
var _party_cap_lbl : Label = null  # shows active level cap

# Inventory page node refs
var _inventory_vbox  : VBoxContainer
var _inventory_money : Label

# Skills page node refs
var _skill_detail_name : Label
var _skill_detail_type : Label
var _skill_detail_cost : Label
var _skill_detail_summary : Label
var _skill_detail_desc : Label
var _skill_list_vbox   : VBoxContainer
var _skill_btns        : Array = []

# Options page node refs
var _master_slider    : HSlider
var _bgm_slider       : HSlider
var _sfx_slider       : HSlider
var _ca_slider         : HSlider
var _brightness_slider : HSlider
var _contrast_slider   : HSlider
var _saturation_slider : HSlider
var _ssao_check       : CheckButton
var _ssil_check       : CheckButton
var _glow_check       : CheckButton
# Last-applied settings — used to revert on menu close and detect dirty state
var _committed : Dictionary = {}
# Live-edited settings while the options page is open
var _pending : Dictionary = {}
# Reference to Apply button so we can grey it out
var _apply_btn : Button

# Dim overlay shown behind the menu when open.
var _dim_layer  : CanvasLayer
var _dim_rect   : ColorRect

# -----------------------------------------------------------------------
# -----------------------------------------------------------------------
# Colours / style constants
# -----------------------------------------------------------------------
const C_BG        := Color(0.08, 0.07, 0.06, 0.97)   # near-black parchment
const C_BORDER    := Color(0.35, 0.28, 0.22, 1.0)    # worn sepia border
const C_ACCENT    := Color(0.72, 0.18, 0.18, 1.0)    # dull crimson
const C_TEXT      := Color(0.88, 0.83, 0.74, 1.0)    # aged paper
const C_DIM       := Color(0.55, 0.50, 0.43, 1.0)    # muted label
const C_TAB_ACT   := Color(0.72, 0.18, 0.18, 1.0)    # active tab = accent
const C_TAB_INACT := Color(0.18, 0.15, 0.12, 1.0)    # inactive tab

const W := 1280
const H := 960
const MENU_W := 920
const MENU_H := 620

# -----------------------------------------------------------------------
func _ready() -> void:
	# Remove Tab from ui_focus_next so it doesn't get eaten before we see it
	var tab_ev := InputEventKey.new()
	tab_ev.keycode = KEY_TAB
	if InputMap.has_action("ui_focus_next"):
		InputMap.action_erase_event("ui_focus_next", tab_ev)

	# Register open_menu on both Tab and I
	if not InputMap.has_action("open_menu"):
		InputMap.add_action("open_menu")
	InputMap.action_erase_events("open_menu")
	var ev_tab := InputEventKey.new()
	ev_tab.keycode = KEY_TAB
	InputMap.action_add_event("open_menu", ev_tab)
	var ev_i := InputEventKey.new()
	ev_i.keycode = KEY_I
	InputMap.action_add_event("open_menu", ev_i)

	layer = 127   # above everything
	add_to_group("party_menu")
	_build_ui()
	_build_dim_overlay()
	hide_menu()

# -----------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("open_menu"):
		if _open:
			hide_menu()
		else:
			show_menu()
		get_viewport().set_input_as_handled()

# -----------------------------------------------------------------------
func _build_dim_overlay() -> void:
	_dim_layer = CanvasLayer.new()
	_dim_layer.layer = 126  # just below the menu panel at 127
	get_tree().root.add_child(_dim_layer)
	_dim_rect = ColorRect.new()
	_dim_rect.color = Color(0.0, 0.0, 0.0, 0.55)
	_dim_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim_layer.add_child(_dim_rect)
	_dim_layer.visible = false
	# Size must be set after the viewport is ready.
	call_deferred("_resize_dim_rect")

func _resize_dim_rect() -> void:
	if _dim_rect == null:
		return
	var vp := get_viewport()
	if vp:
		# CanvasLayer has no rect — anchors don't work. Set position + size directly.
		_dim_rect.position = Vector2.ZERO
		_dim_rect.size = vp.get_visible_rect().size
		if not vp.size_changed.is_connected(_resize_dim_rect):
			vp.size_changed.connect(_resize_dim_rect)


# -----------------------------------------------------------------------
func show_menu() -> void:
	_open = true
	_root_panel.visible = true
	if _dim_layer: _dim_layer.visible = true
	# Seed _committed from live systems on first open (deferred so scene tree is ready)
	if _committed.is_empty():
		var master_bus := AudioServer.get_bus_index("Master")
		var bgm_bus    := AudioServer.get_bus_index("BGM")
		var sfx_bus    := AudioServer.get_bus_index("SFX")
		var mat0 := _get_crt_mat()
		var env0  := _get_env()
		_committed = {
			"master":     db_to_linear(AudioServer.get_bus_volume_db(master_bus)) if master_bus >= 0 else 1.0,
			"bgm":        db_to_linear(AudioServer.get_bus_volume_db(bgm_bus))    if bgm_bus    >= 0 else 1.0,
			"sfx":        db_to_linear(AudioServer.get_bus_volume_db(sfx_bus))    if sfx_bus    >= 0 else 1.0,
			"ca":         _shader_param(mat0, "ca_strength", OPT_DEFAULTS.ca),
			"brightness": _shader_param(mat0, "brightness",  OPT_DEFAULTS.brightness),
			"contrast":   _shader_param(mat0, "contrast",    OPT_DEFAULTS.contrast),
			"saturation": _shader_param(mat0, "saturation",  OPT_DEFAULTS.saturation),
			"ssao": env0.ssao_enabled if env0 else false,
			"ssil": env0.ssil_enabled if env0 else false,
			"glow": env0.glow_enabled if env0 else false,
		}
	# Sync sliders and _pending to committed every time menu opens
	_pending = _committed.duplicate()
	if _master_slider:     _master_slider.set_value_no_signal(_committed.master)
	if _bgm_slider:        _bgm_slider.set_value_no_signal(_committed.bgm)
	if _sfx_slider:        _sfx_slider.set_value_no_signal(_committed.sfx)
	if _ca_slider:         _ca_slider.set_value_no_signal(_committed.ca)
	if _brightness_slider: _brightness_slider.set_value_no_signal(_committed.brightness)
	if _contrast_slider:   _contrast_slider.set_value_no_signal(_committed.contrast)
	if _saturation_slider: _saturation_slider.set_value_no_signal(_committed.saturation)
	if _ssao_check: _ssao_check.set_pressed_no_signal(_committed.ssao)
	if _ssil_check: _ssil_check.set_pressed_no_signal(_committed.ssil)
	if _glow_check: _glow_check.set_pressed_no_signal(_committed.glow)
	_refresh_apply_btn()
	_refresh_party()
	_switch_tab(_active_tab)
	emit_signal("menu_opened")

func hide_menu() -> void:
	_open = false
	_root_panel.visible = false
	if _dim_layer: _dim_layer.visible = false
	# Revert any uncommitted preview changes back to last applied state
	if not _committed.is_empty():
		_apply_options(_committed)
		_pending = _committed.duplicate()
		# Reset sliders/toggles to match committed values
		if _master_slider:     _master_slider.set_value_no_signal(_committed.master)
		if _bgm_slider:        _bgm_slider.set_value_no_signal(_committed.bgm)
		if _sfx_slider:        _sfx_slider.set_value_no_signal(_committed.sfx)
		if _ca_slider:         _ca_slider.set_value_no_signal(_committed.ca)
		if _brightness_slider: _brightness_slider.set_value_no_signal(_committed.brightness)
		if _contrast_slider:   _contrast_slider.set_value_no_signal(_committed.contrast)
		if _saturation_slider: _saturation_slider.set_value_no_signal(_committed.saturation)
		if _ssao_check: _ssao_check.set_pressed_no_signal(_committed.ssao)
		if _ssil_check: _ssil_check.set_pressed_no_signal(_committed.ssil)
		if _glow_check: _glow_check.set_pressed_no_signal(_committed.glow)
		_refresh_apply_btn(_pending)
	emit_signal("menu_closed")

# -----------------------------------------------------------------------
# UI CONSTRUCTION
# -----------------------------------------------------------------------
func _build_ui() -> void:
	_root_panel = PanelContainer.new()
	_root_panel.name = "MenuRoot"
	# Anchor to centre, then offset inward by half the menu size
	_root_panel.anchor_left   = 0.5
	_root_panel.anchor_top    = 0.5
	_root_panel.anchor_right  = 0.5
	_root_panel.anchor_bottom = 0.5
	_root_panel.offset_left   = -MENU_W * 0.5
	_root_panel.offset_top    = -MENU_H * 0.5
	_root_panel.offset_right  =  MENU_W * 0.5
	_root_panel.offset_bottom =  MENU_H * 0.5
	_root_panel.custom_minimum_size = Vector2(MENU_W, MENU_H)

	var style := StyleBoxFlat.new()
	style.bg_color = C_BG
	style.border_color = C_BORDER
	style.set_border_width_all(2)
	style.set_content_margin_all(0)
	_root_panel.add_theme_stylebox_override("panel", style)
	add_child(_root_panel)
	GlobalTheme.apply(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_root_panel.add_child(vbox)

	# --- Tab bar ---
	_tab_bar = HBoxContainer.new()
	_tab_bar.custom_minimum_size = Vector2(MENU_W, 32)
	_tab_bar.add_theme_constant_override("separation", 0)
	vbox.add_child(_tab_bar)

	var tab_names := ["PARTY", "SKILLS", "ITEMS", "OPTIONS"]
	for i in tab_names.size():
		var btn := Button.new()
		btn.text = tab_names[i]
		btn.custom_minimum_size = Vector2(110, 32)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", C_TEXT)
		btn.add_theme_color_override("font_focus_color", C_TEXT)
		btn.add_theme_color_override("font_hover_color", C_TEXT)
		btn.add_theme_color_override("font_pressed_color", C_TEXT)
		var idx := i
		btn.pressed.connect(func(): _switch_tab(idx))
		_tab_bar.add_child(btn)
		_tab_btns.append(btn)

	# Divider
	var div := ColorRect.new()
	div.color = C_BORDER
	div.custom_minimum_size = Vector2(MENU_W, 2)
	vbox.add_child(div)

	# --- Content area ---
	var content := Control.new()
	content.custom_minimum_size = Vector2(MENU_W, MENU_H - 34)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.clip_contents = true
	vbox.add_child(content)

	# Party page
	var party_page := _build_party_page()
	party_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_child(party_page)
	_pages.append(party_page)

	# Skills page
	var skills_page := _build_skills_page()
	skills_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_child(skills_page)
	_pages.append(skills_page)

	# Inventory page
	var inventory_page := _build_inventory_page()
	inventory_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_child(inventory_page)
	_pages.append(inventory_page)

	# Options page
	var options_page := _build_options_page()
	options_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_child(options_page)
	_pages.append(options_page)

# -----------------------------------------------------------------------
# PARTY PAGE
# -----------------------------------------------------------------------
func _build_party_page() -> Control:
	var page := ScrollContainer.new()
	page.name = "PartyPage"
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO

	var vbox := VBoxContainer.new()
	vbox.name = "PartyVBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 1)
	page.add_child(vbox)

	# Cap info row — right-aligned, shows active level ceiling.
	_party_cap_lbl = Label.new()
	_party_cap_lbl.text = ""
	_party_cap_lbl.add_theme_font_size_override("font_size", 11)
	_party_cap_lbl.add_theme_color_override("font_color", C_DIM)
	_party_cap_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_party_cap_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_cap_lbl.custom_minimum_size = Vector2(0, 20)
	var cap_pad := MarginContainer.new()
	cap_pad.add_theme_constant_override("margin_right", 14)
	cap_pad.add_theme_constant_override("margin_top", 4)
	cap_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap_pad.add_child(_party_cap_lbl)
	vbox.add_child(cap_pad)

	# Header row
	var header := _make_member_header()
	vbox.add_child(header)

	var hdiv := ColorRect.new()
	hdiv.color = C_ACCENT
	hdiv.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(hdiv)

	# Member rows - populated by _refresh_party()
	_party_rows.clear()
	for i in range(4):  # max 4 party members
		var row := _make_member_row_placeholder()
		row.visible = false
		vbox.add_child(row)
		_party_rows.append(row)

	return page


func _make_member_header() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 28)
	row.add_theme_constant_override("separation", 0)

	# Must mirror data row col widths, padding, and expand flags exactly.
	var cols := [
		["NAME",    160, HORIZONTAL_ALIGNMENT_LEFT,   true],
		["LV",       36, HORIZONTAL_ALIGNMENT_CENTER, false],
		["CORP",     80, HORIZONTAL_ALIGNMENT_CENTER, false],
		["AP / BB",  72, HORIZONTAL_ALIGNMENT_CENTER, false],
		["SHARP",    48, HORIZONTAL_ALIGNMENT_CENTER, false],
		["FLAT",     40, HORIZONTAL_ALIGNMENT_CENTER, false],
		["TEMPO",    48, HORIZONTAL_ALIGNMENT_CENTER, false],
		["STATUS",   60, HORIZONTAL_ALIGNMENT_LEFT,   true],
	]

	for c in cols:
		var lbl := Label.new()
		lbl.text = c[0]
		lbl.custom_minimum_size = Vector2(c[1], 28)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", C_DIM)
		lbl.horizontal_alignment = c[2]
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		if c[3]:
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pad := _padded(lbl, 8, 0)
		if c[3]:
			pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pad)

	return row


func _make_member_row_placeholder() -> Control:
	# Outer VBox holds the stat row + a small description line
	var outer_row := VBoxContainer.new()
	outer_row.add_theme_constant_override("separation", 0)

	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 56)
	row.add_theme_constant_override("separation", 0)
	outer_row.add_child(row)

	# Cols: [name, min_w, h_align, font_size, color, expand]
	# expand=true uses SIZE_EXPAND_FILL so the column grows to fill spare space.
	var cols := [
		["name_lbl",  160, HORIZONTAL_ALIGNMENT_LEFT,   15, C_TEXT,  true],
		["level_lbl",  36, HORIZONTAL_ALIGNMENT_CENTER, 12, C_DIM,   false],
		["hp_lbl",     80, HORIZONTAL_ALIGNMENT_CENTER, 12, C_TEXT,  false],
		["will_lbl",   72, HORIZONTAL_ALIGNMENT_CENTER, 12, C_TEXT,  false],
		["sharp_lbl",  48, HORIZONTAL_ALIGNMENT_CENTER, 12, C_TEXT,  false],
		["flat_lbl",   40, HORIZONTAL_ALIGNMENT_CENTER, 12, C_TEXT,  false],
		["tempo_lbl",  48, HORIZONTAL_ALIGNMENT_CENTER, 12, C_TEXT,  false],
		["status_lbl", 60, HORIZONTAL_ALIGNMENT_LEFT,   11, C_DIM,   true],
	]

	for c in cols:
		var lbl := Label.new()
		lbl.name = c[0]
		lbl.custom_minimum_size = Vector2(c[1], 52)
		lbl.add_theme_font_size_override("font_size", c[3])
		lbl.add_theme_color_override("font_color", c[4])
		lbl.horizontal_alignment = c[2]
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
		if c[5]:
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pad := _padded(lbl, 8, 0)
		if c[5]:
			pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pad)

	# Description line beneath stats
	var desc_lbl := Label.new()
	desc_lbl.name = "desc_lbl"
	desc_lbl.text = ""
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", C_DIM)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.custom_minimum_size = Vector2(0, 0)
	var desc_pad := _padded(desc_lbl, 24, 4)
	desc_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_row.add_child(desc_pad)

	# Bottom border
	var sep := ColorRect.new()
	sep.color = C_BORDER
	sep.custom_minimum_size = Vector2(0, 1)
	outer_row.add_child(sep)

	return outer_row


func _refresh_party() -> void:
	var run := GameController.current_run
	if run == null:
		return

	# Update cap label.
	if _party_cap_lbl:
		var dr : DungeonRunState = GameController.current_dungeon_run
		if dr != null:
			var in_al : bool = dr.is_battle_reprimed_transit()
			if in_al:
				_party_cap_lbl.text = "  The Segno has been lifted : The party's growth is unbound."
				_party_cap_lbl.add_theme_color_override("font_color",
					Color(0.85, 0.60, 0.20, 1.0))
			else:
				_party_cap_lbl.text = "  The Segno is waiting : The party may not grow past Lv. %d." % dr.segno_level_ceiling
				_party_cap_lbl.add_theme_color_override("font_color", C_DIM)
		else:
			_party_cap_lbl.text = ""

	var members := run.party_members

	for i in _party_rows.size():
		var row : Control = _party_rows[i]
		if i >= members.size():
			row.visible = false
			continue

		row.visible = true
		var m : PartyMemberData = members[i]
		var char_data : CharacterData = m.character
		var max_hp := char_data.base_max_hp + m.bonus_max_hp
		var dead := m.current_hp <= 0

		_set_row_label(row, "name_lbl",  char_data.display_name)
		_set_row_label(row, "level_lbl", str(m.level))
		_set_row_label(row, "desc_lbl",  char_data.description)
		_set_row_label(row, "hp_lbl",   "%d / %d" % [m.current_hp, max_hp])
		_set_row_label(row, "sharp_lbl", str(char_data.base_attack + m.bonus_attack))
		_set_row_label(row, "flat_lbl",  str(char_data.base_flat_defense + m.bonus_flat_defense))
		_set_row_label(row, "tempo_lbl", str(char_data.tempo))

		if m.has_will():
			_set_row_label(row, "will_lbl", "%d / %d" % [m.will, m.max_will])
		else:
			var rs := GameController.current_run
			if rs != null:
				_set_row_label(row, "will_lbl", "%d / %d" % [rs.ammo, rs.max_ammo])
			else:
				_set_row_label(row, "will_lbl", "-- / --")

		# Status summary
		var status_parts : Array = []
		if dead:
			status_parts.append("DEAD")
		for effect in m.status_effects:
			if effect is Dictionary and effect.has("id"):
				status_parts.append(effect["id"].to_upper())
		_set_row_label(row, "status_lbl",
			", ".join(status_parts) if not status_parts.is_empty() else "OK")

		# Tint dead members
		var tint := Color(0.55, 0.55, 0.55, 0.6) if dead else Color.WHITE
		row.modulate = tint


func _set_row_label(row: Control, lbl_name: String, value: String) -> void:
	var lbl := row.find_child(lbl_name, true, false)
	if lbl:
		lbl.text = value

# -----------------------------------------------------------------------
# SKILLS PAGE
# -----------------------------------------------------------------------
# Layout: left panel = scrollable per-character skill list
#         right panel = fixed detail card for the selected skill
# -----------------------------------------------------------------------
func _build_skills_page() -> Control:
	var page := HBoxContainer.new()
	page.name = "SkillsPage"
	page.add_theme_constant_override("separation", 0)

	# --- Left: character + skill list (fixed width column) ---
	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(292, 0)
	left.size_flags_horizontal = Control.SIZE_FILL  # fixed, don't expand
	left.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(left)

	_skill_list_vbox = VBoxContainer.new()
	_skill_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_list_vbox.add_theme_constant_override("separation", 0)
	left.add_child(_skill_list_vbox)

	# Vertical divider
	var vdiv := ColorRect.new()
	vdiv.color = C_BORDER
	vdiv.custom_minimum_size = Vector2(2, 0)
	vdiv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(vdiv)

	# --- Right: detail panel ---
	# Give the right panel a concrete minimum width so labels can resolve
	# their wrap width during the layout pass.
	const RIGHT_W : int = MENU_W - 292 - 2  # total - left col - divider
	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size   = Vector2(RIGHT_W, 0)
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(right_scroll)

	var right := MarginContainer.new()
	right.custom_minimum_size = Vector2(RIGHT_W, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("margin_left",   28)
	right.add_theme_constant_override("margin_top",    28)
	right.add_theme_constant_override("margin_right",  28)
	right.add_theme_constant_override("margin_bottom", 28)
	right_scroll.add_child(right)

	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	right.add_child(detail)

	# Skill name
	_skill_detail_name = Label.new()
	_skill_detail_name.text = "Select a skill"
	_skill_detail_name.add_theme_font_size_override("font_size", 18)
	_skill_detail_name.add_theme_color_override("font_color", C_TEXT)
	detail.add_child(_skill_detail_name)

	# Type + cost row
	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 12)
	detail.add_child(meta_row)

	_skill_detail_type = Label.new()
	_skill_detail_type.add_theme_font_size_override("font_size", 11)
	_skill_detail_type.add_theme_color_override("font_color", C_ACCENT)
	meta_row.add_child(_skill_detail_type)

	_skill_detail_cost = Label.new()
	_skill_detail_cost.add_theme_font_size_override("font_size", 11)
	_skill_detail_cost.add_theme_color_override("font_color", C_DIM)
	meta_row.add_child(_skill_detail_cost)
	
	# Summary lives below the meta row so it can wrap properly.
	_skill_detail_summary = Label.new()
	_skill_detail_summary.add_theme_font_size_override("font_size", 12)
	_skill_detail_summary.add_theme_color_override("font_color", C_DIM)
	_skill_detail_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_detail_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_skill_detail_summary)


	# Divider under meta
	var detail_div := ColorRect.new()
	detail_div.color = C_BORDER
	detail_div.custom_minimum_size = Vector2(0, 1)
	detail.add_child(detail_div)

	# Description
	_skill_detail_desc = Label.new()
	_skill_detail_desc.add_theme_font_size_override("font_size", 13)
	_skill_detail_desc.add_theme_color_override("font_color", C_TEXT)
	_skill_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_detail_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_detail_desc.custom_minimum_size   = Vector2(0, 0)
	detail.add_child(_skill_detail_desc)

	# Populate list
	_populate_skill_list()

	return page


func _populate_skill_list() -> void:
	for child in _skill_list_vbox.get_children():
		child.queue_free()
	_skill_btns.clear()

	# All skills per character - static, not runtime get_skills()
	# key: "attack" | "special" | "support"   cost: shown in detail panel
	var roster : Array = [
		{"character": "Kendall", "skills": [
			{"name": "Shoot",       "type": "ATTACK",  "cost": "X BB [1]"},
			{"name": "Pistol Whip", "type": "ATTACK",  "cost": "Beatless"},
			{"name": "Augur",       "type": "SUPPORT", "cost": "2 AP (allies)"},
			{"name": "Evade",       "type": "SUPPORT", "cost": "Ally Unwilling"},
			{"name": "Unveil", "type": "SPECIAL", "cost": "2 AP (allies)"},
		]},
		{"character": "Hue", "skills": [
			{"name": "Rebuke",  "type": "ATTACK (AoE)",  "cost": "1 AP"},
			{"name": "Cling",   "type": "ATTACK",  "cost": "Unwilling"},
			{"name": "Shelter", "type": "SUPPORT", "cost": "2 AP"},
			{"name": "Embrace", "type": "SUPPORT", "cost": "Unwilling"},
			{"name": "Calcify", "type": "SPECIAL", "cost": "3 AP"},
		]},
		{"character": "Indra", "skills": [
			{"name": "Crucify",   "type": "ATTACK",  "cost": "1 AP"},
			{"name": "Clobber",   "type": "ATTACK",  "cost": "Unwilling"},
			{"name": "Galvanize", "type": "SUPPORT", "cost": "2 AP"},
			{"name": "Martyr",    "type": "SUPPORT", "cost": "Unwilling"},
			{"name": "Fulminate", "type": "SPECIAL (AoE)", "cost": "3 AP"},
		]},
		{"character": "Vritra", "skills": [
			{"name": "Wither",      "type": "ATTACK", "cost": "1 AP"},
			{"name": "Waste",       "type": "ATTACK", "cost": "Unwilling"},
			{"name": "Vice",        "type": "SUPPORT",  "cost": "2 AP"},
			{"name": "Malice", "type": "SUPPORT",  "cost": "Unwilling"},
			{"name": "Devour",      "type": "SPECIAL", "cost": "3 AP"},
		]},
	]

	for entry in roster:
		# Character header
		var char_lbl := Label.new()
		char_lbl.text = entry["character"].to_upper()
		char_lbl.add_theme_font_size_override("font_size", 10)
		char_lbl.add_theme_color_override("font_color", C_DIM)
		char_lbl.custom_minimum_size = Vector2(0, 24)
		char_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var char_pad := MarginContainer.new()
		char_pad.add_theme_constant_override("margin_left", 16)
		char_pad.add_child(char_lbl)
		_skill_list_vbox.add_child(char_pad)

		var char_div := ColorRect.new()
		char_div.color = C_ACCENT
		char_div.custom_minimum_size = Vector2(0, 1)
		_skill_list_vbox.add_child(char_div)

		for skill in entry["skills"]:
			var skill_data : Dictionary = skill
			var btn := Button.new()
			btn.text = skill["name"]
			btn.custom_minimum_size = Vector2(0, 32)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_font_size_override("font_size", 12)
			btn.add_theme_color_override("font_color", C_TEXT)
			btn.add_theme_color_override("font_hover_color", C_TEXT)
			btn.add_theme_color_override("font_pressed_color", C_TEXT)
			btn.add_theme_color_override("font_focus_color", C_TEXT)
			var flat := StyleBoxFlat.new()
			flat.bg_color = Color(0, 0, 0, 0)
			flat.set_content_margin_all(0)
			var flat_hover := StyleBoxFlat.new()
			flat_hover.bg_color = Color(0.72, 0.18, 0.18, 0.18)
			flat_hover.set_content_margin_all(0)
			btn.add_theme_stylebox_override("normal",  flat)
			btn.add_theme_stylebox_override("focus",   flat)
			btn.add_theme_stylebox_override("pressed", flat_hover)
			btn.add_theme_stylebox_override("hover",   flat_hover)
			btn.pressed.connect(func(): _show_skill_detail(skill_data))
			var btn_pad := MarginContainer.new()
			btn_pad.add_theme_constant_override("margin_left", 16)
			btn_pad.add_theme_constant_override("margin_right", 8)
			btn_pad.add_child(btn)
			_skill_list_vbox.add_child(btn_pad)
			_skill_btns.append(btn)

		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		_skill_list_vbox.add_child(gap)


func _show_skill_detail(skill: Dictionary) -> void:
	_skill_detail_name.text = skill["name"]
	_skill_detail_type.text = skill["type"]
	_skill_detail_cost.text = skill["cost"]
	
	var _sd := SkillDirectory.get_skill(skill["name"])
	_skill_detail_summary.text = _sd.summary if _sd else ""
	_skill_detail_desc.text = _sd.description if _sd else ""


# -----------------------------------------------------------------------
# OPTIONS PAGE
# -----------------------------------------------------------------------
# Defaults used by both _build_options_page and Apply
const OPT_DEFAULTS := {
	"master": 1.0, "bgm": 1.0, "sfx": 1.0,
	"ca": 2.0, "brightness": 1.0, "contrast": 1.0, "saturation": 1.0,
	"ssao": false, "ssil": false, "glow": false,
}

# Helper: read a shader parameter, falling back to a default if null/missing
func _shader_param(mat: ShaderMaterial, key: String, default_val: Variant) -> Variant:
	if mat == null: return default_val
	var v = mat.get_shader_parameter(key)
	return v if v != null else default_val

# Helper: get the battleglitch ShaderMaterial from GameRoot/TVOverlay/MeshInstance2D
# This canvas_item shader runs over everything: world, battle, and UI
func _get_crt_mat() -> ShaderMaterial:
	var mesh := get_tree().root.get_node_or_null("GameRoot/TVOverlay/MeshInstance2D") as MeshInstance2D
	return mesh.material as ShaderMaterial if (mesh and mesh.material) else null

# Helper: get live Environment — checks battle scene, dungeon, and world scene
func _get_env() -> Environment:
	var candidates := [
		"GameRoot/BattleLayer/BattleScene/WorldEnvironment",
		"GameRoot/DungeonMap3D/WorldEnvironment",
		"White_Test/Main/Level/WorldEnvironment",
	]
	for path in candidates:
		var node := get_tree().root.get_node_or_null(path)
		if node and node.environment:
			return node.environment
	return null

# Update Apply button appearance based on whether pending differs from committed
func _refresh_apply_btn(_p: Dictionary = {}) -> void:
	if _apply_btn == null: return
	var dirty := (_pending != _committed)
	_apply_btn.disabled = not dirty
	_apply_btn.modulate = Color(1, 1, 1, 1.0) if dirty else Color(1, 1, 1, 0.4)

# Commit a settings dict to all live systems
func _apply_options(s: Dictionary) -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	var bgm_bus    := AudioServer.get_bus_index("BGM")
	var sfx_bus    := AudioServer.get_bus_index("SFX")
	for pair in [[master_bus, s.master], [bgm_bus, s.bgm], [sfx_bus, s.sfx]]:
		var bus : int = pair[0]
		var v   : float = pair[1]
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, linear_to_db(v) if v > 0.0 else -80.0)
	var mat := _get_crt_mat()
	if mat:
		mat.set_shader_parameter("ca_strength", s.ca)
		mat.set_shader_parameter("brightness",  s.brightness)
		mat.set_shader_parameter("contrast",    s.contrast)
		mat.set_shader_parameter("saturation",  s.saturation)
	# Apply to all active environments (battle + dungeon may both exist)
	var env_paths := [
		"GameRoot/BattleLayer/BattleScene/WorldEnvironment",
		"GameRoot/DungeonMap3D/WorldEnvironment",
		"White_Test/Main/Level/WorldEnvironment",
	]
	for ep in env_paths:
		var enode := get_tree().root.get_node_or_null(ep)
		if enode and enode.environment:
			enode.environment.ssao_enabled = s.ssao
			enode.environment.ssil_enabled = s.ssil
			enode.environment.glow_enabled = s.glow

# -----------------------------------------------------------------------
# INVENTORY PAGE
# -----------------------------------------------------------------------
func _build_inventory_page() -> Control:
	var page := ScrollContainer.new()
	page.name = "InventoryPage"
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 0)
	page.add_child(outer)

	# Header row: title + money
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 38)
	header.add_theme_constant_override("separation", 0)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(pad)
	outer.add_child(header)

	var header_hbox := HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(header_hbox)

	var title_lbl := Label.new()
	title_lbl.text = "Items"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", C_TEXT)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_lbl)

	_inventory_money = Label.new()
	_inventory_money.add_theme_font_size_override("font_size", 14)
	_inventory_money.add_theme_color_override("font_color", C_ACCENT)
	_inventory_money.text = ""
	header_hbox.add_child(_inventory_money)

	var hdiv := ColorRect.new()
	hdiv.color = C_ACCENT
	hdiv.custom_minimum_size = Vector2(0, 1)
	outer.add_child(hdiv)

	# Item list — populated by _refresh_inventory()
	_inventory_vbox = VBoxContainer.new()
	_inventory_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_vbox.add_theme_constant_override("separation", 0)
	outer.add_child(_inventory_vbox)

	return page


func _refresh_inventory() -> void:
	if _inventory_vbox == null:
		return
	for c in _inventory_vbox.get_children():
		c.queue_free()

	var rs : RunState = GameController.current_run
	if rs == null:
		return

	if _inventory_money:
		_inventory_money.text = "%d\u20b5" % rs.money

	if rs.inventory.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Nothing here."
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", C_DIM)
		empty_lbl.custom_minimum_size = Vector2(0, 40)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_inventory_vbox.add_child(empty_lbl)
		return

	for inst in rs.inventory:
		if inst == null or inst.item_data == null:
			continue
		_inventory_vbox.add_child(_build_inventory_row(inst, rs))


## Build one row for an inventory item.
func _build_inventory_row(inst: ItemInstance, rs: RunState) -> VBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 42)
	row.add_theme_constant_override("separation", 12)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 8)
	row.add_child(pad)

	var inner := HBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 10)
	pad.add_child(inner)

	# Name + stack count
	var name_lbl := Label.new()
	name_lbl.text = "%s  x%d" % [inst.item_data.item_name, inst.stacks]
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	name_lbl.custom_minimum_size = Vector2(180, 0)
	inner.add_child(name_lbl)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = inst.item_data.description
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", C_DIM)
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(desc_lbl)

	# Use buttons — context-gated.
	var consumable := inst.item_data as ConsumableData
	var in_battle : bool = get_tree().get_first_node_in_group("battle_layer") != null \
		and (get_tree().get_first_node_in_group("battle_layer") as CanvasLayer).visible
	var can_use : bool = consumable != null and \
		(in_battle and consumable.usable_in_battle or
		 not in_battle and consumable.usable_in_dungeon)
	if can_use:
		var btn_col := VBoxContainer.new()
		btn_col.add_theme_constant_override("separation", 2)
		var party_wide : bool = consumable.effect_type in ["corpus_all", "will_all",
			"reprise", "tie"]
		if party_wide:
			# Single Use button for party-wide and utility effects.
			var use_btn := Button.new()
			use_btn.text = "Use"
			use_btn.custom_minimum_size = Vector2(80, 0)
			use_btn.add_theme_font_size_override("font_size", 11)
			var captured_inst := inst
			use_btn.pressed.connect(func():
				ItemRegistry.use_item(rs, captured_inst)
				_refresh_inventory())
			btn_col.add_child(use_btn)
		else:
			# Per-member buttons for single-target corpus/will.
			for member in rs.party_members:
				var m := member as PartyMemberData
				if m == null or m.character == null:
					continue
				var use_btn := Button.new()
				use_btn.text = m.character.display_name
				use_btn.custom_minimum_size = Vector2(80, 0)
				use_btn.add_theme_font_size_override("font_size", 11)
				match consumable.effect_type:
					"corpus": use_btn.disabled = m.current_hp <= 0
					"will":   use_btn.disabled = not m.has_will()
				var captured_inst := inst
				var captured_m    := m
				use_btn.pressed.connect(func():
					ItemRegistry.use_item(rs, captured_inst, captured_m)
					_refresh_inventory())
				btn_col.add_child(use_btn)
		var right_pad := MarginContainer.new()
		right_pad.add_theme_constant_override("margin_right", 16)
		right_pad.add_child(btn_col)
		row.add_child(right_pad)

	# Bottom divider
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(row)
	var div := ColorRect.new()
	div.color = Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.4)
	div.custom_minimum_size = Vector2(0, 1)
	wrap.add_child(div)
	return wrap


func _build_options_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "OptionsPage"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 0)
	scroll.add_child(page)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left",  32)
	pad.add_theme_constant_override("margin_top",   32)
	pad.add_theme_constant_override("margin_right", 32)
	pad.add_theme_constant_override("margin_bottom",32)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(pad)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 24)
	pad.add_child(inner)

	# _pending starts as OPT_DEFAULTS at build time; resynced in show_menu once live systems are ready
	if _pending.is_empty():
		_pending = OPT_DEFAULTS.duplicate()

	# Section label
	var sec_lbl := Label.new()
	sec_lbl.text = "AUDIO"
	sec_lbl.add_theme_font_size_override("font_size", 10)
	sec_lbl.add_theme_color_override("font_color", C_DIM)
	inner.add_child(sec_lbl)

	var audio_div := ColorRect.new()
	audio_div.color = C_BORDER
	audio_div.custom_minimum_size = Vector2(0, 1)
	inner.add_child(audio_div)

	var slider_data := [
		["MASTER VOLUME", "master", _pending.master],
		["MUSIC VOLUME",  "bgm",    _pending.bgm],
		["SFX VOLUME",    "sfx",    _pending.sfx],
	]

	var slider_refs := []
	for entry in slider_data:
		var label_text : String = entry[0]
		var pkey       : String = entry[1]
		var cur        : float  = float(entry[2])

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		inner.add_child(row)

		var lbl := Label.new()
		lbl.text = label_text
		lbl.custom_minimum_size = Vector2(180, 0)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", C_TEXT)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(lbl)

		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 2.0  # 1.0 = 100%, slider midpoint
		slider.step      = 0.01
		slider.value     = clampf(cur, 0.0, 2.0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var k := pkey
		row.add_child(slider)

		var val_lbl := Label.new()
		val_lbl.custom_minimum_size = Vector2(42, 0)
		val_lbl.add_theme_font_size_override("font_size", 12)
		val_lbl.add_theme_color_override("font_color", C_DIM)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		val_lbl.text = "%d%%" % int(cur * 100)
		row.add_child(val_lbl)

		slider.value_changed.connect(func(v: float):
			_pending[k] = v
			val_lbl.text = "%d%%" % int(v * 100)
			_apply_options(_pending)
			_refresh_apply_btn(_pending)
		)

		slider_refs.append(slider)

	if slider_refs.size() >= 3:
		_master_slider = slider_refs[0]
		_bgm_slider    = slider_refs[1]
		_sfx_slider    = slider_refs[2]

	# --- DISPLAY section ---
	var disp_lbl := Label.new()
	disp_lbl.text = "DISPLAY"
	disp_lbl.add_theme_font_size_override("font_size", 10)
	disp_lbl.add_theme_color_override("font_color", C_DIM)
	inner.add_child(disp_lbl)

	var disp_div := ColorRect.new()
	disp_div.color = C_BORDER
	disp_div.custom_minimum_size = Vector2(0, 1)
	inner.add_child(disp_div)

	# Chromatic aberration slider
	var ca_default: float = _pending.ca

	var ca_row := HBoxContainer.new()
	ca_row.add_theme_constant_override("separation", 16)
	inner.add_child(ca_row)

	var ca_label := Label.new()
	ca_label.text = "CHROMATIC ABERRATION"
	ca_label.custom_minimum_size = Vector2(180, 0)
	ca_label.add_theme_font_size_override("font_size", 13)
	ca_label.add_theme_color_override("font_color", C_TEXT)
	ca_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ca_row.add_child(ca_label)

	_ca_slider = HSlider.new()
	_ca_slider.min_value = 0.0
	_ca_slider.max_value = 10.0
	_ca_slider.step      = 0.1
	_ca_slider.value     = ca_default
	_ca_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ca_row.add_child(_ca_slider)

	var ca_val_lbl := Label.new()
	ca_val_lbl.custom_minimum_size = Vector2(42, 0)
	ca_val_lbl.add_theme_font_size_override("font_size", 12)
	ca_val_lbl.add_theme_color_override("font_color", C_DIM)
	ca_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ca_val_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	ca_val_lbl.text = "%.1f" % ca_default
	ca_row.add_child(ca_val_lbl)

	_ca_slider.value_changed.connect(func(v: float):
		_pending.ca = v
		ca_val_lbl.text = "%.1f" % v
		_apply_options(_pending)
		_refresh_apply_btn(_pending)
	)

	# --- Brightness slider ---
	var bright_default: float = _pending.brightness

	var bright_row := HBoxContainer.new()
	bright_row.add_theme_constant_override("separation", 16)
	inner.add_child(bright_row)

	var bright_lbl := Label.new()
	bright_lbl.text = "BRIGHTNESS"
	bright_lbl.custom_minimum_size = Vector2(180, 0)
	bright_lbl.add_theme_font_size_override("font_size", 13)
	bright_lbl.add_theme_color_override("font_color", C_TEXT)
	bright_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bright_row.add_child(bright_lbl)

	_brightness_slider = HSlider.new()
	_brightness_slider.min_value = 0.5
	_brightness_slider.max_value = 2.0
	_brightness_slider.step      = 0.01
	_brightness_slider.value     = bright_default
	_brightness_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bright_row.add_child(_brightness_slider)

	var bright_val := Label.new()
	bright_val.custom_minimum_size = Vector2(42, 0)
	bright_val.add_theme_font_size_override("font_size", 12)
	bright_val.add_theme_color_override("font_color", C_DIM)
	bright_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bright_val.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	bright_val.text = "%.2f" % bright_default
	bright_row.add_child(bright_val)

	_brightness_slider.value_changed.connect(func(v: float):
		_pending.brightness = v
		bright_val.text = "%.2f" % v
		_apply_options(_pending)
		_refresh_apply_btn(_pending)
	)

	# --- Contrast slider ---
	var contrast_default: float = _pending.contrast

	var contrast_row := HBoxContainer.new()
	contrast_row.add_theme_constant_override("separation", 16)
	inner.add_child(contrast_row)

	var contrast_lbl := Label.new()
	contrast_lbl.text = "CONTRAST"
	contrast_lbl.custom_minimum_size = Vector2(180, 0)
	contrast_lbl.add_theme_font_size_override("font_size", 13)
	contrast_lbl.add_theme_color_override("font_color", C_TEXT)
	contrast_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	contrast_row.add_child(contrast_lbl)

	_contrast_slider = HSlider.new()
	_contrast_slider.min_value = 0.5
	_contrast_slider.max_value = 2.0
	_contrast_slider.step      = 0.01
	_contrast_slider.value     = contrast_default
	_contrast_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contrast_row.add_child(_contrast_slider)

	var contrast_val := Label.new()
	contrast_val.custom_minimum_size = Vector2(42, 0)
	contrast_val.add_theme_font_size_override("font_size", 12)
	contrast_val.add_theme_color_override("font_color", C_DIM)
	contrast_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	contrast_val.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	contrast_val.text = "%.2f" % contrast_default
	contrast_row.add_child(contrast_val)

	_contrast_slider.value_changed.connect(func(v: float):
		_pending.contrast = v
		contrast_val.text = "%.2f" % v
		_apply_options(_pending)
		_refresh_apply_btn(_pending)
	)

	# --- Saturation slider ---
	var sat_default : float = _pending.saturation

	var sat_row := HBoxContainer.new()
	sat_row.add_theme_constant_override("separation", 16)
	inner.add_child(sat_row)

	var sat_lbl := Label.new()
	sat_lbl.text = "SATURATION"
	sat_lbl.custom_minimum_size = Vector2(180, 0)
	sat_lbl.add_theme_font_size_override("font_size", 13)
	sat_lbl.add_theme_color_override("font_color", C_TEXT)
	sat_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sat_row.add_child(sat_lbl)

	_saturation_slider = HSlider.new()
	_saturation_slider.min_value = 0.0
	_saturation_slider.max_value = 2.0
	_saturation_slider.step      = 0.01
	_saturation_slider.value     = sat_default
	_saturation_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sat_row.add_child(_saturation_slider)

	var sat_val := Label.new()
	sat_val.custom_minimum_size = Vector2(42, 0)
	sat_val.add_theme_font_size_override("font_size", 12)
	sat_val.add_theme_color_override("font_color", C_DIM)
	sat_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sat_val.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	sat_val.text = "%.2f" % sat_default
	sat_row.add_child(sat_val)

	_saturation_slider.value_changed.connect(func(v: float):
		_pending.saturation = v
		sat_val.text = "%.2f" % v
		_apply_options(_pending)
		_refresh_apply_btn(_pending)
	)

	# --- Rendering toggles section header ---
	var render_lbl := Label.new()
	render_lbl.text = "RENDERING"
	render_lbl.add_theme_font_size_override("font_size", 10)
	render_lbl.add_theme_color_override("font_color", C_DIM)
	inner.add_child(render_lbl)

	var render_div := ColorRect.new()
	render_div.color = C_BORDER
	render_div.custom_minimum_size = Vector2(0, 1)
	inner.add_child(render_div)

	# Helper to build a toggle row
	var _make_toggle := func(label_text: String, current: bool) -> CheckButton:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		inner.add_child(row)
		var lbl := Label.new()
		lbl.text = label_text
		lbl.custom_minimum_size = Vector2(180, 0)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", C_TEXT)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(lbl)
		var check := CheckButton.new()
		check.button_pressed = current
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(check)
		return check

	_ssao_check = _make_toggle.call("SSAO", _pending.ssao)
	_ssil_check = _make_toggle.call("SSIL", _pending.ssil)
	_glow_check = _make_toggle.call("GLOW", _pending.glow)

	_ssao_check.toggled.connect(func(on: bool): _pending.ssao = on; _apply_options(_pending); _refresh_apply_btn(_pending))
	_ssil_check.toggled.connect(func(on: bool): _pending.ssil = on; _apply_options(_pending); _refresh_apply_btn(_pending))
	_glow_check.toggled.connect(func(on: bool): _pending.glow = on; _apply_options(_pending); _refresh_apply_btn(_pending))

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(spacer)

	# --- Apply / Restore Defaults buttons ---
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	inner.add_child(btn_row)

	var btn_spacer := Control.new()
	btn_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(btn_spacer)

	var _make_btn := func(label: String) -> Button:
		var btn := Button.new()
		btn.text = label
		btn.add_theme_font_size_override("font_size", 12)
		var sbox := StyleBoxFlat.new()
		sbox.bg_color = C_TAB_INACT
		sbox.border_color = C_BORDER
		sbox.set_border_width_all(1)
		sbox.set_content_margin_all(8)
		btn.add_theme_stylebox_override("normal", sbox)
		var sbox_hov := sbox.duplicate()
		sbox_hov.bg_color = C_TAB_ACT
		sbox_hov.border_color = C_ACCENT
		btn.add_theme_stylebox_override("hover", sbox_hov)
		btn.add_theme_stylebox_override("pressed", sbox_hov)
		btn.add_theme_stylebox_override("focus", sbox)
		return btn

	var defaults_btn: Variant = _make_btn.call("RESTORE DEFAULTS")
	btn_row.add_child(defaults_btn)

	_apply_btn = _make_btn.call("APPLY") as Button
	var sbox_apply := StyleBoxFlat.new()
	sbox_apply.bg_color = C_ACCENT
	sbox_apply.border_color = C_ACCENT
	sbox_apply.set_border_width_all(1)
	sbox_apply.set_content_margin_all(8)
	_apply_btn.add_theme_stylebox_override("normal", sbox_apply)
	_apply_btn.add_theme_stylebox_override("hover", sbox_apply)
	_apply_btn.add_theme_stylebox_override("pressed", sbox_apply)
	_apply_btn.add_theme_stylebox_override("focus", sbox_apply)
	btn_row.add_child(_apply_btn)

	# Apply: save _pending as committed
	_apply_btn.pressed.connect(func():
		_committed = _pending.duplicate()
		_refresh_apply_btn(_pending)
	)

	# Restore Defaults: reset controls and _pending to OPT_DEFAULTS, preview live
	defaults_btn.pressed.connect(func():
		for k in OPT_DEFAULTS:
			_pending[k] = OPT_DEFAULTS[k]
		if _master_slider:     _master_slider.set_value_no_signal(OPT_DEFAULTS.master)
		if _bgm_slider:        _bgm_slider.set_value_no_signal(OPT_DEFAULTS.bgm)
		if _sfx_slider:        _sfx_slider.set_value_no_signal(OPT_DEFAULTS.sfx)
		if _ca_slider:         _ca_slider.set_value_no_signal(OPT_DEFAULTS.ca)
		if _brightness_slider: _brightness_slider.set_value_no_signal(OPT_DEFAULTS.brightness)
		if _contrast_slider:   _contrast_slider.set_value_no_signal(OPT_DEFAULTS.contrast)
		if _saturation_slider: _saturation_slider.set_value_no_signal(OPT_DEFAULTS.saturation)
		if _ssao_check: _ssao_check.set_pressed_no_signal(OPT_DEFAULTS.ssao)
		if _ssil_check: _ssil_check.set_pressed_no_signal(OPT_DEFAULTS.ssil)
		if _glow_check: _glow_check.set_pressed_no_signal(OPT_DEFAULTS.glow)
		_apply_options(_pending)
		_refresh_apply_btn(_pending)
	)

	# Set initial Apply button state
	_refresh_apply_btn(_pending)

	# Close hint
	var hint := Label.new()
	hint.text = "[TAB] close"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", C_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inner.add_child(hint)

	return scroll

# -----------------------------------------------------------------------
# TAB SWITCHING
# -----------------------------------------------------------------------
func _switch_tab(idx: int) -> void:
	_active_tab = idx
	for i in _pages.size():
		_pages[i].visible = (i == idx)
	if idx == TAB_INVENTORY:
		_refresh_inventory()
	for i in _tab_btns.size():
		var btn : Button = _tab_btns[i]
		var active := (i == idx)
		var sbox := StyleBoxFlat.new()
		sbox.bg_color    = C_TAB_ACT if active else C_TAB_INACT
		sbox.border_color = C_ACCENT if active else C_BORDER
		sbox.set_border_width_all(0)
		sbox.border_width_bottom = 2 if active else 0
		sbox.set_content_margin_all(6)
		btn.add_theme_stylebox_override("normal",   sbox)
		btn.add_theme_stylebox_override("hover",    sbox)
		btn.add_theme_stylebox_override("pressed",  sbox)
		btn.add_theme_stylebox_override("focus",    sbox)

# -----------------------------------------------------------------------
# HELPERS
# -----------------------------------------------------------------------
func _padded(child: Control, h: int, v: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",   h)
	m.add_theme_constant_override("margin_right",  h)
	m.add_theme_constant_override("margin_top",    v)
	m.add_theme_constant_override("margin_bottom", v)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL if child.custom_minimum_size.x == 0 else Control.SIZE_SHRINK_BEGIN
	m.add_child(child)
	return m
