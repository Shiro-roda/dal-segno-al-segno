extends CanvasLayer
## SystemMenu — ESC-key system overlay.
##
## Layout: left sidebar (vertical tab list + session actions) | right content panel.
## Looks like a monitor OSD / settings screen.
## Tabs: AUDIO | DISPLAY | RENDERING | BATTLE | THEME
## ESC opens/closes from any context except boot sequence.

signal menu_opened
signal menu_closed

# ── Tab indices ───────────────────────────────────────────────────────────────
const TAB_AUDIO     := 0
const TAB_DISPLAY   := 1
const TAB_RENDERING := 2
const TAB_BATTLE    := 3
const TAB_THEME     := 4

var _open       := false
var _active_tab := TAB_AUDIO

# ── Palette ───────────────────────────────────────────────────────────────────
var C_BG        := Color.BLACK
var C_SIDEBAR   := Color.BLACK
var C_BORDER    := Color.WHITE
var C_ACCENT    := Color.WHITE
var C_TEXT      := Color.WHITE
var C_DIM       := Color.WHITE
var C_GOLD      := Color.WHITE
var C_TAB_ACT   := Color.WHITE
var C_TAB_INACT := Color.BLACK
var C_DANGER    := Color(0.85, 0.22, 0.18, 1.0)

# ── Layout constants ──────────────────────────────────────────────────────────
const SIDEBAR_W := 220

# ── Node refs ─────────────────────────────────────────────────────────────────
var _root_panel  : PanelContainer
var _tab_btns    : Array = []
var _pages       : Array = []
var _dim_layer   : CanvasLayer
var _dim_rect    : ColorRect

# Audio refs
var _master_slider    : HSlider
var _bgm_slider       : HSlider
var _sfx_slider       : HSlider

# Display refs
var _ca_slider         : HSlider
var _brightness_slider : HSlider
var _contrast_slider   : HSlider
var _saturation_slider : HSlider

# Rendering refs
var _ssao_check : CheckButton
var _ssil_check : CheckButton
var _glow_check : CheckButton

# Per-tab apply buttons (one per settings tab so rendering has its own)
var _apply_btns  : Dictionary = {}   # tab_index -> Button
var _committed   : Dictionary = {}
var _pending     : Dictionary = {}

# ── Defaults ──────────────────────────────────────────────────────────────────
const OPT_DEFAULTS := {
	"master": 1.0, "bgm": 1.0, "sfx": 1.0,
	"ca": 0.5, "brightness": 1.1, "contrast": 1.0, "saturation": 1.0,
	"ssao": false, "ssil": false, "glow": false,
}

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	layer = 130
	process_mode = PROCESS_MODE_ALWAYS
	add_to_group("system_menu")
	_refresh_palette()
	ThemeManager.theme_changed.connect(_on_theme_changed)
	_build_ui()
	_build_dim_overlay()
	hide_menu()

func _refresh_palette() -> void:
	var p := ThemeManager.palette
	C_BG        = p.bg
	C_SIDEBAR   = Color(p.bg.r * 1.4, p.bg.g * 1.4, p.bg.b * 1.4, 1.0).darkened(0.1)
	C_BORDER    = p.dim
	C_ACCENT    = p.primary
	C_TEXT      = p.text
	C_DIM       = p.dim
	C_GOLD      = p.secondary
	C_TAB_ACT   = p.primary
	C_TAB_INACT = p.hover

func _on_theme_changed(_id: int) -> void:
	_refresh_palette()
	_rebuild_ui()

func _rebuild_ui() -> void:
	var was_open  := _open
	var saved_tab := _active_tab
	if is_instance_valid(_root_panel):
		_root_panel.queue_free()
		_root_panel = null
	_tab_btns.clear()
	_pages.clear()
	_apply_btns.clear()
	_master_slider = null; _bgm_slider = null; _sfx_slider = null
	_ca_slider = null; _brightness_slider = null
	_contrast_slider = null; _saturation_slider = null
	_ssao_check = null; _ssil_check = null; _glow_check = null
	_build_ui()
	if was_open:
		_root_panel.visible = true
		_switch_tab(saved_tab)
	else:
		_root_panel.visible = false

# ── Input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and (event as InputEventKey).pressed):
		return
	var kc := (event as InputEventKey).keycode

	if kc == KEY_ESCAPE:
		if _open:
			hide_menu()
			get_viewport().set_input_as_handled()
		else:
			var boot = get_tree().get_first_node_in_group("boot_sequence")
			if boot != null and boot.visible:
				return
			# Block on start screen
			var on_start_screen := get_tree().get_first_node_in_group("start_screen") != null
			if on_start_screen:
				return
			show_menu()
			get_viewport().set_input_as_handled()
		return

	if not _open:
		return

	if kc == KEY_UP:
		_switch_tab((_active_tab - 1 + _tab_btns.size()) % _tab_btns.size())
		get_viewport().set_input_as_handled()
	elif kc == KEY_DOWN:
		_switch_tab((_active_tab + 1) % _tab_btns.size())
		get_viewport().set_input_as_handled()

# ── Dim overlay ───────────────────────────────────────────────────────────────
func _build_dim_overlay() -> void:
	_dim_layer = CanvasLayer.new()
	_dim_layer.layer = 129
	get_tree().root.call_deferred("add_child", _dim_layer)
	_dim_rect = ColorRect.new()
	_dim_rect.color = Color(0.0, 0.0, 0.0, 0.70)
	_dim_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim_layer.add_child(_dim_rect)
	_dim_layer.visible = false
	call_deferred("_resize_dim_rect")

func _resize_dim_rect() -> void:
	if _dim_rect == null: return
	var vp := get_viewport()
	if vp:
		_dim_rect.position = Vector2.ZERO
		_dim_rect.size = vp.get_visible_rect().size
		if not vp.size_changed.is_connected(_resize_dim_rect):
			vp.size_changed.connect(_resize_dim_rect)

# ── Show / Hide ───────────────────────────────────────────────────────────────
func show_menu(tab: int = TAB_AUDIO) -> void:
	_open = true
	_root_panel.visible = true
	if _dim_layer: _dim_layer.visible = true
	get_tree().paused = true

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

	_pending = _committed.duplicate()
	_sync_controls_to(_pending)
	_refresh_all_apply_btns()
	_switch_tab(tab)
	UISounds.play("menu_open")
	emit_signal("menu_opened")

func hide_menu() -> void:
	_open = false
	_root_panel.visible = false
	if _dim_layer: _dim_layer.visible = false
	get_tree().paused = false
	if not _committed.is_empty():
		_apply_options(_committed)
		_pending = _committed.duplicate()
		_sync_controls_to(_committed)
		_refresh_all_apply_btns()
	UISounds.play("menu_close")
	emit_signal("menu_closed")

func _sync_controls_to(s: Dictionary) -> void:
	if _master_slider:     _master_slider.set_value_no_signal(s.master)
	if _bgm_slider:        _bgm_slider.set_value_no_signal(s.bgm)
	if _sfx_slider:        _sfx_slider.set_value_no_signal(s.sfx)
	if _ca_slider:         _ca_slider.set_value_no_signal(s.ca)
	if _brightness_slider: _brightness_slider.set_value_no_signal(s.brightness)
	if _contrast_slider:   _contrast_slider.set_value_no_signal(s.contrast)
	if _saturation_slider: _saturation_slider.set_value_no_signal(s.saturation)
	if _ssao_check: _ssao_check.set_pressed_no_signal(s.ssao)
	if _ssil_check: _ssil_check.set_pressed_no_signal(s.ssil)
	if _glow_check: _glow_check.set_pressed_no_signal(s.glow)

func _refresh_all_apply_btns() -> void:
	var dirty := (_pending != _committed)
	for tab_idx in _apply_btns:
		var btn : Button = _apply_btns[tab_idx]
		if is_instance_valid(btn):
			btn.disabled = not dirty
			btn.modulate = Color(1, 1, 1, 1.0) if dirty else Color(1, 1, 1, 0.4)

# ── UI Construction ───────────────────────────────────────────────────────────
func _build_ui() -> void:
	# Seed _pending before building pages so sliders have initial values
	if _pending.is_empty():
		_pending = OPT_DEFAULTS.duplicate()

	_root_panel = PanelContainer.new()
	_root_panel.name = "SystemMenuRoot"
	# Full-screen coverage
	_root_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_panel.offset_left   = 0
	_root_panel.offset_top    = 0
	_root_panel.offset_right  = 0
	_root_panel.offset_bottom = 0

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(C_BG.r, C_BG.g, C_BG.b, 0.96)
	panel_style.border_color = C_ACCENT
	panel_style.set_border_width_all(0)
	panel_style.set_content_margin_all(0)
	_root_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_root_panel)

	# Root HBox: sidebar | divider | content
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	_root_panel.add_child(hbox)

	# ── LEFT SIDEBAR ─────────────────────────────────────────────────────────
	var sidebar := _build_sidebar()
	hbox.add_child(sidebar)

	# Vertical divider
	var vdiv := ColorRect.new()
	vdiv.color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.35)
	vdiv.custom_minimum_size = Vector2(1, 0)
	vdiv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(vdiv)

	# ── RIGHT CONTENT ─────────────────────────────────────────────────────────
	var content := Control.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	content.clip_contents = true
	hbox.add_child(content)

	var pages_data := [
		["AudioPage",     _build_audio_page()],
		["DisplayPage",   _build_display_page()],
		["RenderingPage", _build_rendering_page()],
		["BattlePage",    _build_battle_page()],
		["ThemePage",     _build_theme_page()],
	]
	for i in pages_data.size():
		var pg : Control = pages_data[i][1]
		pg.name = pages_data[i][0]
		pg.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.add_child(pg)
		_pages.append(pg)

func _build_sidebar() -> Control:
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size = Vector2(SIDEBAR_W, 0)
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var sb_style := StyleBoxFlat.new()
	sb_style.bg_color = C_SIDEBAR
	sb_style.set_content_margin_all(0)
	sidebar.add_theme_stylebox_override("panel", sb_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	sidebar.add_child(vbox)

	# System label at top
	var title_pad := MarginContainer.new()
	title_pad.add_theme_constant_override("margin_left", 14)
	title_pad.add_theme_constant_override("margin_top", 16)
	title_pad.add_theme_constant_override("margin_bottom", 8)
	vbox.add_child(title_pad)

	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 2)
	title_pad.add_child(title_vbox)

	var sys_lbl := Label.new()
	sys_lbl.text = "SYSTEM"
	sys_lbl.add_theme_font_size_override("font_size", 9)
	sys_lbl.add_theme_color_override("font_color", C_ACCENT)
	title_vbox.add_child(sys_lbl)

	var esc_lbl := Label.new()
	esc_lbl.text = "[ESC] CLOSE"
	esc_lbl.add_theme_font_size_override("font_size", 9)
	esc_lbl.add_theme_color_override("font_color", Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.6))
	title_vbox.add_child(esc_lbl)

	# Thin accent rule
	var rule := ColorRect.new()
	rule.color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.4)
	rule.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(rule)

	# Spacer
	var sp1 := Control.new()
	sp1.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(sp1)

	# Tab buttons — vertical list
	var tab_names := ["AUDIO", "DISPLAY", "RENDERING", "BATTLE", "THEME"]
	for i in tab_names.size():
		var btn := Button.new()
		btn.text = tab_names[i]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(SIDEBAR_W, 36)
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", C_TEXT)
		btn.add_theme_color_override("font_focus_color", C_TEXT)
		btn.add_theme_color_override("font_hover_color", C_TEXT)
		btn.add_theme_color_override("font_pressed_color", C_TEXT)
		var idx := i
		btn.pressed.connect(func(): _switch_tab(idx))
		vbox.add_child(btn)
		_tab_btns.append(btn)

	# Push session actions to bottom
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(push)

	# Session divider
	var sess_rule := ColorRect.new()
	sess_rule.color = Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.4)
	sess_rule.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(sess_rule)

	var sess_pad := MarginContainer.new()
	sess_pad.add_theme_constant_override("margin_left", 10)
	sess_pad.add_theme_constant_override("margin_right", 10)
	sess_pad.add_theme_constant_override("margin_top", 8)
	sess_pad.add_theme_constant_override("margin_bottom", 12)
	vbox.add_child(sess_pad)

	var sess_vbox := VBoxContainer.new()
	sess_vbox.add_theme_constant_override("separation", 4)
	sess_pad.add_child(sess_vbox)

	var sess_lbl := Label.new()
	sess_lbl.text = "SESSION"
	sess_lbl.add_theme_font_size_override("font_size", 9)
	sess_lbl.add_theme_color_override("font_color", Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.6))
	sess_vbox.add_child(sess_lbl)

	# Save & Exit — saves then quits to desktop
	var save_exit_btn := _make_session_btn("SAVE & EXIT")
	save_exit_btn.pressed.connect(func():
		if GameController.current_run != null:
			SaveManager.save_run(GameController.current_run, GameController.current_dungeon_run)
		BattleSettings.save()
		get_tree().quit())
	sess_vbox.add_child(save_exit_btn)

	# Return to Menu — saves and goes to main menu
	var menu_btn := _make_session_btn("RETURN TO MENU")
	menu_btn.pressed.connect(func():
		if GameController.current_run != null:
			SaveManager.save_run(GameController.current_run, GameController.current_dungeon_run)
		BattleSettings.save()
		hide_menu()
		GameController._show_start_screen())
	sess_vbox.add_child(menu_btn)

	# Restart Run
	var restart_btn := _make_session_btn("RESTART RUN")
	_style_danger_btn(restart_btn)
	restart_btn.pressed.connect(func():
		hide_menu()
		GameController.start_new_game())
	sess_vbox.add_child(restart_btn)

	return sidebar

# ── Tab switching ─────────────────────────────────────────────────────────────
func _switch_tab(idx: int) -> void:
	_active_tab = idx
	for i in _pages.size():
		_pages[i].visible = (i == idx)
	_style_tab_buttons(idx)
	UISounds.play("tab_switch")

func _style_tab_buttons(idx: int) -> void:
	for i in _tab_btns.size():
		var btn : Button = _tab_btns[i]
		var active := (i == idx)
		var sbox := StyleBoxFlat.new()
		sbox.bg_color     = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.18) if active else Color(0, 0, 0, 0)
		sbox.border_color = C_ACCENT
		sbox.set_border_width_all(0)
		sbox.border_width_left = 3 if active else 0
		sbox.set_content_margin_all(6)
		sbox.content_margin_left = 14
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, sbox)
		btn.add_theme_color_override("font_color", C_ACCENT if active else C_TEXT)

# ── AUDIO PAGE ────────────────────────────────────────────────────────────────
func _build_audio_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := _make_content_vbox(scroll)

	_add_section_header(page, "AUDIO")

	var refs := []
	for entry in [
		["MASTER VOLUME", "master", _pending.master, 0.0, 2.0, 0.01, "%d%%"],
		["MUSIC VOLUME",  "bgm",    _pending.bgm,    0.0, 2.0, 0.01, "%d%%"],
		["SFX VOLUME",    "sfx",    _pending.sfx,    0.0, 2.0, 0.01, "%d%%"],
	]:
		var key := entry[1] as String
		var fmt := entry[6] as String
		refs.append(_add_slider_row(page, entry[0], entry[3], entry[4], entry[5], float(entry[2]),
			func(v, _k, lbl):
				_pending[key] = v
				lbl.text = fmt % (int(v * 100) if "%d%%" in fmt else v)
				_apply_options(_pending)
				_refresh_all_apply_btns(),
			key, fmt))

	_master_slider = refs[0]
	_bgm_slider    = refs[1]
	_sfx_slider    = refs[2]

	_add_apply_restore_row(page, TAB_AUDIO)
	return scroll

# ── DISPLAY PAGE ──────────────────────────────────────────────────────────────
func _build_display_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := _make_content_vbox(scroll)

	_add_section_header(page, "DISPLAY")

	_ca_slider = _add_slider_row(page, "CHROMATIC ABERRATION", 0.0, 10.0, 0.1, _pending.ca,
		func(v, _k, lbl): _pending.ca = v; lbl.text = "%.1f" % v; _apply_options(_pending); _refresh_all_apply_btns(),
		"", "%.1f")
	_brightness_slider = _add_slider_row(page, "BRIGHTNESS", 0.5, 2.0, 0.01, _pending.brightness,
		func(v, _k, lbl): _pending.brightness = v; lbl.text = "%.2f" % v; _apply_options(_pending); _refresh_all_apply_btns(),
		"", "%.2f")
	_contrast_slider = _add_slider_row(page, "CONTRAST", 0.5, 2.0, 0.01, _pending.contrast,
		func(v, _k, lbl): _pending.contrast = v; lbl.text = "%.2f" % v; _apply_options(_pending); _refresh_all_apply_btns(),
		"", "%.2f")
	_saturation_slider = _add_slider_row(page, "SATURATION", 0.0, 2.0, 0.01, _pending.saturation,
		func(v, _k, lbl): _pending.saturation = v; lbl.text = "%.2f" % v; _apply_options(_pending); _refresh_all_apply_btns(),
		"", "%.2f")

	_add_apply_restore_row(page, TAB_DISPLAY)
	return scroll

# ── RENDERING PAGE ────────────────────────────────────────────────────────────
func _build_rendering_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := _make_content_vbox(scroll)

	_add_section_header(page, "RENDERING")

	_ssao_check = _add_toggle_row(page, "SSAO (Screen Space Ambient Occlusion)", _pending.ssao,
		func(on): _pending.ssao = on; _apply_options(_pending); _refresh_all_apply_btns())
	_ssil_check = _add_toggle_row(page, "SSIL (Screen Space Indirect Lighting)", _pending.ssil,
		func(on): _pending.ssil = on; _apply_options(_pending); _refresh_all_apply_btns())
	_glow_check = _add_toggle_row(page, "GLOW", _pending.glow,
		func(on): _pending.glow = on; _apply_options(_pending); _refresh_all_apply_btns())

	var note := Label.new()
	note.text = "These options affect 3D scene quality and may impact performance."
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.6))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(note)

	_add_apply_restore_row(page, TAB_RENDERING)
	return scroll

# ── BATTLE PAGE ───────────────────────────────────────────────────────────────
func _build_battle_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := _make_content_vbox(scroll)
	page.add_theme_constant_override("separation", 14)

	_add_section_header(page, "BATTLE MODE")

	for pair in [
		["CTB — CHARGE TURN", BattleSettings.BattleMode.CTB],
		["ATB — ACTIVE TIME", BattleSettings.BattleMode.ATB],
	]:
		var mode_name : String = pair[0]
		var mode_val  : int    = pair[1]
		var active := (BattleSettings.battle_mode == mode_val)
		var btn := _make_option_btn(mode_name + ("  ◄" if active else ""), func():
			BattleSettings.battle_mode = mode_val
			BattleSettings.save()
			_rebuild_battle_page())
		page.add_child(btn)

	_add_section_header(page, "BPM SCALE  —  %.0f%%" % (BattleSettings.atb_speed_multiplier * 100))

	for pair in [
		["LENTO (50%)", 0.5], ["MODERATO (100%)", 1.0],
		["ALLEGRO (150%)", 1.5], ["PRESTO (200%)", 2.0],
	]:
		var speed_name : String = pair[0]
		var speed_val  : float  = pair[1]
		var active := absf(BattleSettings.atb_speed_multiplier - speed_val) < 0.01
		var btn := _make_option_btn(speed_name + ("  ◄" if active else ""), func():
			BattleSettings.atb_speed_multiplier = speed_val
			BattleSettings.save()
			_rebuild_battle_page())
		page.add_child(btn)

	return scroll

func _rebuild_battle_page() -> void:
	var idx := TAB_BATTLE
	if idx >= _pages.size(): return
	var old = _pages[idx]
	var parent = old.get_parent()
	old.queue_free()
	var new_page := _build_battle_page()
	new_page.name = "BattlePage"
	new_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(new_page)
	_pages[idx] = new_page
	_switch_tab(idx)

# ── THEME PAGE ────────────────────────────────────────────────────────────────
func _build_theme_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := _make_content_vbox(scroll)
	page.add_theme_constant_override("separation", 10)

	_add_section_header(page, "UI THEME")

	var desc := Label.new()
	desc.text = "Select a colour palette and sound style for the interface."
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", C_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(desc)

	for i in ThemeManager.UITheme.size():
		var theme_id := i
		var is_active := (ThemeManager.current_theme == i)
		var theme_name_str := ThemeManager.theme_name(i)

		# Get swatch color from that palette
		var swatch_pal := ThemeManager._build_palette(i)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		page.add_child(row)

		# Primary colour swatch
		var sw1 := ColorRect.new()
		sw1.custom_minimum_size = Vector2(16, 32)
		sw1.color = swatch_pal.primary
		row.add_child(sw1)

		# Secondary colour swatch
		var sw2 := ColorRect.new()
		sw2.custom_minimum_size = Vector2(16, 32)
		sw2.color = swatch_pal.secondary
		row.add_child(sw2)

		# BG swatch
		var sw3 := ColorRect.new()
		sw3.custom_minimum_size = Vector2(16, 32)
		sw3.color = Color(swatch_pal.bg.r * 4 + 0.15, swatch_pal.bg.g * 4 + 0.15, swatch_pal.bg.b * 4 + 0.15, 1.0)
		row.add_child(sw3)

		var btn := _make_option_btn(theme_name_str + ("   ◄  ACTIVE" if is_active else ""), func():
			ThemeManager.set_theme(theme_id)
			UISounds.play("confirm"))
		row.add_child(btn)

	# Sound pack info
	var div := ColorRect.new()
	div.color = Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.3)
	div.custom_minimum_size = Vector2(0, 1)
	page.add_child(div)

	var sound_lbl := Label.new()
	sound_lbl.text = "UI SOUNDS: " + ThemeManager.current_sound_pack_name()
	sound_lbl.add_theme_font_size_override("font_size", 11)
	sound_lbl.add_theme_color_override("font_color", C_DIM)
	page.add_child(sound_lbl)

	return scroll

# ── Shared helpers ────────────────────────────────────────────────────────────
func _make_content_vbox(scroll: ScrollContainer) -> VBoxContainer:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left",   28)
	pad.add_theme_constant_override("margin_top",    24)
	pad.add_theme_constant_override("margin_right",  28)
	pad.add_theme_constant_override("margin_bottom", 24)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 14)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	pad.add_child(inner)
	return inner

func _add_section_header(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", C_ACCENT)
	parent.add_child(lbl)
	var div := ColorRect.new()
	div.color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.35)
	div.custom_minimum_size = Vector2(0, 1)
	parent.add_child(div)

func _add_slider_row(parent: VBoxContainer, label_text: String,
		min_v: float, max_v: float, step: float, cur: float,
		on_change: Callable, _key: String, fmt: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(210, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = clampf(cur, min_v, max_v)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(52, 0)
	val_lbl.add_theme_font_size_override("font_size", 11)
	val_lbl.add_theme_color_override("font_color", C_DIM)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	val_lbl.text = _fmt_val(cur, fmt)
	row.add_child(val_lbl)

	slider.value_changed.connect(func(v: float): on_change.call(v, _key, val_lbl))
	return slider

func _fmt_val(v: float, fmt: String) -> String:
	if "%d%%" in fmt:
		return "%d%%" % int(v * 100)
	return fmt % v

func _add_toggle_row(parent: VBoxContainer, label_text: String,
		cur: bool, on_toggle: Callable) -> CheckButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var check := CheckButton.new()
	check.button_pressed = cur
	check.toggled.connect(on_toggle)
	row.add_child(check)
	return check

func _add_apply_restore_row(parent: VBoxContainer, tab_idx: int) -> void:
	# Push to bottom
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(0, 8)
	parent.add_child(spacer)

	var div := ColorRect.new()
	div.color = Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.25)
	div.custom_minimum_size = Vector2(0, 1)
	parent.add_child(div)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var row_spacer := Control.new()
	row_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(row_spacer)

	var defaults_btn := _make_small_btn("RESTORE DEFAULTS")
	defaults_btn.pressed.connect(func():
		for k in OPT_DEFAULTS:
			_pending[k] = OPT_DEFAULTS[k]
		_sync_controls_to(_pending)
		_apply_options(_pending)
		_refresh_all_apply_btns()
		UISounds.play("navigate"))
	row.add_child(defaults_btn)

	var apply_btn := _make_small_btn("APPLY")
	var sbox_apply := StyleBoxFlat.new()
	sbox_apply.bg_color = C_ACCENT
	sbox_apply.border_color = C_ACCENT
	sbox_apply.set_border_width_all(1)
	sbox_apply.set_content_margin_all(8)
	apply_btn.add_theme_stylebox_override("normal",  sbox_apply)
	apply_btn.add_theme_stylebox_override("hover",   sbox_apply)
	apply_btn.add_theme_stylebox_override("pressed", sbox_apply)
	apply_btn.add_theme_stylebox_override("focus",   sbox_apply)
	apply_btn.add_theme_color_override("font_color",         C_BG)
	apply_btn.add_theme_color_override("font_hover_color",   C_BG)
	apply_btn.add_theme_color_override("font_pressed_color", C_BG)
	apply_btn.disabled = true
	apply_btn.modulate = Color(1, 1, 1, 0.4)
	apply_btn.pressed.connect(func():
		_committed = _pending.duplicate()
		_refresh_all_apply_btns()
		UISounds.play("confirm"))
	row.add_child(apply_btn)
	_apply_btns[tab_idx] = apply_btn

func _make_option_btn(label: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color",         C_TEXT)
	btn.add_theme_color_override("font_hover_color",   C_TEXT)
	btn.add_theme_color_override("font_pressed_color", C_TEXT)
	btn.add_theme_color_override("font_focus_color",   C_TEXT)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.set_content_margin_all(6)
	var flat_h := StyleBoxFlat.new()
	flat_h.bg_color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.12)
	flat_h.border_color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.25)
	flat_h.border_width_left = 2
	flat_h.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal",  flat)
	btn.add_theme_stylebox_override("focus",   flat)
	btn.add_theme_stylebox_override("hover",   flat_h)
	btn.add_theme_stylebox_override("pressed", flat_h)
	btn.pressed.connect(callback)
	return btn

func _make_small_btn(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 11)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0, 0, 0, 0)
	sbox.border_color = C_BORDER
	sbox.set_border_width_all(1)
	sbox.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", sbox)
	var sbox_h := sbox.duplicate() as StyleBoxFlat
	sbox_h.bg_color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.15)
	sbox_h.border_color = C_ACCENT
	btn.add_theme_stylebox_override("hover",   sbox_h)
	btn.add_theme_stylebox_override("pressed", sbox_h)
	btn.add_theme_stylebox_override("focus",   sbox)
	return btn

func _make_session_btn(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color",         C_TEXT)
	btn.add_theme_color_override("font_hover_color",   C_TEXT)
	btn.add_theme_color_override("font_pressed_color", C_TEXT)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.set_content_margin_all(4)
	var flat_h := StyleBoxFlat.new()
	flat_h.bg_color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.12)
	flat_h.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal",  flat)
	btn.add_theme_stylebox_override("focus",   flat)
	btn.add_theme_stylebox_override("hover",   flat_h)
	btn.add_theme_stylebox_override("pressed", flat_h)
	return btn

func _style_danger_btn(btn: Button) -> void:
	btn.add_theme_color_override("font_color",         Color(C_DANGER.r, C_DANGER.g, C_DANGER.b, 0.7))
	btn.add_theme_color_override("font_hover_color",   C_DANGER)
	btn.add_theme_color_override("font_pressed_color", C_DANGER)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.set_content_margin_all(4)
	var flat_h := StyleBoxFlat.new()
	flat_h.bg_color = Color(C_DANGER.r, C_DANGER.g, C_DANGER.b, 0.10)
	flat_h.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal",  flat)
	btn.add_theme_stylebox_override("focus",   flat)
	btn.add_theme_stylebox_override("hover",   flat_h)
	btn.add_theme_stylebox_override("pressed", flat_h)

# ── Option application ────────────────────────────────────────────────────────
func _apply_options(s: Dictionary) -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	var bgm_bus    := AudioServer.get_bus_index("BGM")
	var sfx_bus    := AudioServer.get_bus_index("SFX")
	for pair in [[master_bus, s.master], [bgm_bus, s.bgm], [sfx_bus, s.sfx]]:
		var bus : int  = pair[0]
		var v   : float = pair[1]
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, linear_to_db(v) if v > 0.0 else -80.0)
	var mat := _get_crt_mat()
	if mat:
		mat.set_shader_parameter("ca_strength", s.ca)
		mat.set_shader_parameter("brightness",  s.brightness)
		mat.set_shader_parameter("contrast",    s.contrast)
		mat.set_shader_parameter("saturation",  s.saturation)
	for ep in [
		"GameRoot/BattleLayer/BattleScene/WorldEnvironment",
		"GameRoot/DungeonMap3D/WorldEnvironment",
	]:
		var enode := get_tree().root.get_node_or_null(ep)
		if enode and enode.environment:
			enode.environment.ssao_enabled = s.ssao
			enode.environment.ssil_enabled = s.ssil
			enode.environment.glow_enabled = s.glow

func _get_crt_mat() -> ShaderMaterial:
	var mesh := get_tree().root.get_node_or_null("GameRoot/TVOverlay/MeshInstance2D") as MeshInstance2D
	return mesh.material as ShaderMaterial if (mesh and mesh.material) else null

func _get_env() -> Environment:
	for path in ["GameRoot/BattleLayer/BattleScene/WorldEnvironment",
			"GameRoot/DungeonMap3D/WorldEnvironment"]:
		var node := get_tree().root.get_node_or_null(path)
		if node and node.environment:
			return node.environment
	return null

func _shader_param(mat: ShaderMaterial, key: String, default_val: Variant) -> Variant:
	if mat == null: return default_val
	var v = mat.get_shader_parameter(key)
	return v if v != null else default_val
