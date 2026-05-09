extends Control
# Start screen — main menu with Continue and New Game submenu.

signal play_intro
signal skip_intro
signal start_new_run
signal continue_run
signal quit_game

# Colours — refreshed from ThemeManager on ready and on theme change.
var C_BG       := Color.BLACK
var C_TEXT     := Color.WHITE
var C_DIM      := Color.WHITE
var C_ACCENT   := Color.WHITE
var C_HOVER    := Color.BLACK
var C_DISABLED := Color.WHITE
const FONT_PATH  := "res://UI/Themes/Fonts/TerminalVector.ttf"

var _font : Font
var _col  : VBoxContainer
var _current_page : Callable  # which build fn to re-run on theme change

# ── Keyboard navigation ──────────────────────────────────────────────────────
var _kb_index : int    = 0
var _kb_btn   : Button = null  # currently highlighted button

func _menu_buttons() -> Array:
	var result : Array = []
	for child in _col.get_children():
		# Buttons are wrapped in VBoxContainers by _make_btn
		if child is VBoxContainer:
			for sub in (child as VBoxContainer).get_children():
				if sub is Button and not (sub as Button).disabled:
					result.append(sub)
					break
		elif child is Button and not (child as Button).disabled:
			result.append(child)
	return result

func _kb_apply_focus() -> void:
	# Restore previous button's original stylebox before moving focus
	if is_instance_valid(_kb_btn):
		if _kb_btn.has_meta("kb_orig_normal"):
			_kb_btn.add_theme_stylebox_override("normal", _kb_btn.get_meta("kb_orig_normal"))
		else:
			_kb_btn.remove_theme_stylebox_override("normal")
		_kb_btn = null
	var list := _menu_buttons()
	if list.is_empty():
		return
	_kb_index = clampi(_kb_index, 0, list.size() - 1)
	_kb_btn = list[_kb_index]
	# Save the current normal stylebox so we can restore it on blur
	var orig := _kb_btn.get_theme_stylebox("normal")
	_kb_btn.set_meta("kb_orig_normal", orig)
	var focused := StyleBoxFlat.new()
	focused.bg_color = C_HOVER
	focused.border_color = C_TEXT
	focused.set_border_width_all(1)
	focused.set_content_margin_all(12)
	_kb_btn.add_theme_stylebox_override("normal", focused)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var kc : int = (event as InputEventKey).keycode
	var list := _menu_buttons()
	if list.is_empty():
		return
	if kc == KEY_UP:
		_kb_index = (_kb_index - 1 + list.size()) % list.size()
		_kb_apply_focus()
		get_viewport().set_input_as_handled()
	elif kc == KEY_DOWN:
		_kb_index = (_kb_index + 1) % list.size()
		_kb_apply_focus()
		get_viewport().set_input_as_handled()
	elif kc == KEY_SPACE or kc == KEY_ENTER or kc == KEY_KP_ENTER:
		_kb_index = clampi(_kb_index, 0, list.size() - 1)
		(list[_kb_index] as Button).emit_signal("pressed")
		get_viewport().set_input_as_handled()

func _ready() -> void:
	add_to_group("start_screen")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font
	_refresh_palette()
	ThemeManager.theme_changed.connect(_on_theme_changed)

	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var outer := CenterContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer)

	_col = VBoxContainer.new()
	_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_col.add_theme_constant_override("separation", 18)
	outer.add_child(_col)

	_build_main_menu()


func _refresh_palette() -> void:
	var p := ThemeManager.palette
	C_BG       = p.bg
	C_TEXT     = p.text
	C_DIM      = p.dim
	C_ACCENT   = p.primary
	C_HOVER    = p.hover
	C_DISABLED = p.dim


func _on_theme_changed(_id: int) -> void:
	_refresh_palette()
	if _current_page.is_valid():
		_current_page.call()
	else:
		_build_main_menu()


func _build_main_menu() -> void:
	_current_page = _build_main_menu
	await _clear_col()

	# Title
	var title := Label.new()
	title.text = "DAL SEGNO AL SEGNO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_font_override("font", _font)
	title.add_theme_color_override("font_color", C_TEXT)
	_col.add_child(title)

	var rule := ColorRect.new()
	rule.color = C_ACCENT
	rule.custom_minimum_size = Vector2(420, 1)
	_col.add_child(rule)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_col.add_child(spacer)

	# Continue button — only shown when a save exists.
	if SaveManager.has_run_save():
		_col.add_child(_make_btn(
			"CONTINUE",
			"Resume your interrupted run.",
			_font, func(): emit_signal("continue_run")))

	# New Game → submenu
	_col.add_child(_make_btn(
		"NEW GAME",
		"Begin a fresh run.",
		_font, func(): _build_new_game_menu()))

	_col.add_child(_make_btn(
		"SETTINGS",
		"Battle mode, ATB speed, and accessibility.",
		_font, func(): _build_settings_menu()))

	_col.add_child(_make_btn(
		"MANUAL",
		"View the keyboard & combat reference.",
		_font, func(): _open_manual()))

	_col.add_child(_make_btn(
		"QUIT GAME",
		"",
		_font, func(): emit_signal("quit_game")))
	_kb_apply_focus()



func _build_new_game_menu() -> void:
	_current_page = _build_new_game_menu
	await _clear_col()

	var title := Label.new()
	title.text = "NEW GAME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_font_override("font", _font)
	title.add_theme_color_override("font_color", C_TEXT)
	_col.add_child(title)

	var rule := ColorRect.new()
	rule.color = C_ACCENT
	rule.custom_minimum_size = Vector2(420, 1)
	_col.add_child(rule)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_col.add_child(spacer)

	_col.add_child(_make_section_label("START WITH"))

	_col.add_child(_make_btn(
		"PLAY INTRO",
		"Take a stroll through the cloud waves.",
		_font, func(): _build_battle_settings_menu("play_intro")))

	_col.add_child(_make_btn(
		"PLAY TUTORIAL",
		"Start with the tutorial battle.",
		_font, func(): _build_battle_settings_menu("skip_intro")))

	_col.add_child(_make_btn(
		"SKIP TO RUN",
		"Skip straight to companion select.",
		_font, func(): _build_battle_settings_menu("start_new_run")))

	_col.add_child(_make_btn(
		"BACK",
		"",
		_font, func(): _build_main_menu()))
	_kb_apply_focus()


func _build_battle_settings_menu(destination: String) -> void:
	_current_page = func(): _build_battle_settings_menu(destination)
	await _clear_col()

	var title := Label.new()
	title.text = "BATTLE SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_font_override("font", _font)
	title.add_theme_color_override("font_color", C_TEXT)
	_col.add_child(title)

	var rule := ColorRect.new()
	rule.color = C_ACCENT
	rule.custom_minimum_size = Vector2(420, 1)
	_col.add_child(rule)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_col.add_child(spacer)

	# ── Battle Mode ──────────────────────────────────────────────────────────
	_col.add_child(_make_section_label("BATTLE MODE"))

	var is_ctb := BattleSettings.battle_mode == BattleSettings.BattleMode.CTB
	_col.add_child(_make_btn(
		"CTB — CHARGE TURN" + ("  ◄" if is_ctb else ""),
		"Combatants charge BPM in real time. One acts at a time. Very Fast speed recommended.",
		_font, func():
			BattleSettings.battle_mode = BattleSettings.BattleMode.CTB
			_build_battle_settings_menu(destination)))

	_col.add_child(_make_btn(
		"ATB — ACTIVE TIME" + ("  ◄" if not is_ctb else ""),
		"All combatants charge simultaneously and act immediately when ready.",
		_font, func():
			BattleSettings.battle_mode = BattleSettings.BattleMode.ATB
			_build_battle_settings_menu(destination)))

	# ── BPM Speed ─────────────────────────────────────────────────────────────
	_col.add_child(_make_section_label(
		"BPM SCALE  —  %.0f%%" % (BattleSettings.atb_speed_multiplier * 100)))

	var speeds := [["LENTO (50%)", 0.5], ["MODERATO (100%)", 1.0],
				   ["ALLEGRO (150%)", 1.5], ["PRESTO (200%)", 2.0]]
	for pair in speeds:
		var label_str : String = pair[0]
		var val       : float  = pair[1]
		var active    := absf(BattleSettings.atb_speed_multiplier - val) < 0.01
		_col.add_child(_make_btn(
			label_str + ("  ◄" if active else ""),
			"", _font,
			func():
				BattleSettings.atb_speed_multiplier = val
				_build_battle_settings_menu(destination)))

	# ── Confirm ───────────────────────────────────────────────────────────────
	var confirm_spacer := Control.new()
	confirm_spacer.custom_minimum_size = Vector2(0, 4)
	_col.add_child(confirm_spacer)

	_col.add_child(_make_btn(
		"BEGIN  ▶",
		"",
		_font, func(): _launch_game(destination)))

	_col.add_child(_make_btn(
		"BACK",
		"",
		_font, func(): _build_new_game_menu()))
	_kb_apply_focus()


func _launch_game(destination: String) -> void:
	match destination:
		"play_intro":    emit_signal("play_intro")
		"skip_intro":    emit_signal("skip_intro")
		"start_new_run": emit_signal("start_new_run")


func _build_settings_menu() -> void:
	_current_page = _build_settings_menu
	await _clear_col()

	# ── Header ─────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_font_override("font", _font)
	title.add_theme_color_override("font_color", C_TEXT)
	_col.add_child(title)

	var rule := ColorRect.new()
	rule.color = C_ACCENT
	rule.custom_minimum_size = Vector2(900, 1)
	_col.add_child(rule)

	# ── Two-column grid ──────────────────────────────────────────────────────
	# LEFT column: Audio + Display
	# RIGHT column: Battle Mode/Speed + Theme
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	cols.custom_minimum_size = Vector2(900, 0)
	_col.add_child(cols)

	var left  := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)

	var divider := ColorRect.new()
	divider.color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.25)
	divider.custom_minimum_size = Vector2(1, 0)
	divider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(divider)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	# ── LEFT: Audio ────────────────────────────────────────────────────────
	left.add_child(_make_settings_header("AUDIO"))
	left.add_child(_make_slider_row("MASTER", "Master", 0.0, 2.0, 0.01))
	left.add_child(_make_slider_row("MUSIC",  "BGM",    0.0, 2.0, 0.01))
	left.add_child(_make_slider_row("SFX",    "SFX",    0.0, 2.0, 0.01))

	var sp_l := Control.new()
	sp_l.custom_minimum_size = Vector2(0, 8)
	left.add_child(sp_l)

	# ── LEFT: Display ────────────────────────────────────────────────────
	left.add_child(_make_settings_header("DISPLAY"))
	var mat := _get_crt_mat()
	if mat:
		var ca  = mat.get_shader_parameter("ca_strength")
		var bri = mat.get_shader_parameter("brightness")
		var con = mat.get_shader_parameter("contrast")
		var sat = mat.get_shader_parameter("saturation")
		left.add_child(_make_shader_slider_row("CHROM. ABR.", mat, "ca_strength", 0.0, 10.0, 0.1,  ca  if ca  != null else 2.0))
		left.add_child(_make_shader_slider_row("BRIGHTNESS",  mat, "brightness",  0.5, 2.0,  0.01, bri if bri != null else 1.0))
		left.add_child(_make_shader_slider_row("CONTRAST",    mat, "contrast",    0.5, 2.0,  0.01, con if con != null else 1.0))
		left.add_child(_make_shader_slider_row("SATURATION",  mat, "saturation",  0.0, 2.0,  0.01, sat if sat != null else 1.0))
	else:
		var ndl := Label.new()
		ndl.text = "Display options unavailable."
		ndl.add_theme_font_size_override("font_size", 11)
		ndl.add_theme_font_override("font", _font)
		ndl.add_theme_color_override("font_color", C_DIM)
		ndl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(ndl)

	# ── RIGHT: Battle Mode ───────────────────────────────────────────────
	right.add_child(_make_settings_header("BATTLE MODE"))

	var is_ctb := BattleSettings.battle_mode == BattleSettings.BattleMode.CTB
	right.add_child(_make_settings_btn(
		"CTB — CHARGE TURN" + ("  ◄" if is_ctb else ""),
		"Combatants charge BPM in real time. One acts at a time.",
		func():
			BattleSettings.battle_mode = BattleSettings.BattleMode.CTB
			BattleSettings.save()
			_build_settings_menu()))
	right.add_child(_make_settings_btn(
		"ATB — ACTIVE TIME" + ("  ◄" if not is_ctb else ""),
		"All combatants charge simultaneously and act when ready.",
		func():
			BattleSettings.battle_mode = BattleSettings.BattleMode.ATB
			BattleSettings.save()
			_build_settings_menu()))

	var sp_r := Control.new()
	sp_r.custom_minimum_size = Vector2(0, 8)
	right.add_child(sp_r)

	# ── RIGHT: BPM Speed ────────────────────────────────────────────────
	right.add_child(_make_settings_header(
		"BPM SCALE  —  %.0f%%" % (BattleSettings.atb_speed_multiplier * 100)))
	for pair in [["LENTO (50%)", 0.5], ["MODERATO (100%)", 1.0],
				 ["ALLEGRO (150%)", 1.5], ["PRESTO (200%)", 2.0]]:
		var label_str : String = pair[0]
		var val       : float  = pair[1]
		var active    := absf(BattleSettings.atb_speed_multiplier - val) < 0.01
		right.add_child(_make_settings_btn(
			label_str + ("  ◄" if active else ""), "",
			func():
				BattleSettings.atb_speed_multiplier = val
				BattleSettings.save()
				_build_settings_menu()))

	var sp_r2 := Control.new()
	sp_r2.custom_minimum_size = Vector2(0, 8)
	right.add_child(sp_r2)

	# ── RIGHT: UI Theme ────────────────────────────────────────────────
	right.add_child(_make_settings_header("UI THEME"))
	for i in ThemeManager.UITheme.size():
		var theme_id := i
		var is_active := (ThemeManager.current_theme == i)
		right.add_child(_make_settings_btn(
			ThemeManager.theme_name(i) + ("   ◄  ACTIVE" if is_active else ""), "",
			func():
				ThemeManager.set_theme(theme_id)
				_build_settings_menu()))

	# ── Back button ─────────────────────────────────────────────────────────
	var back_rule := ColorRect.new()
	back_rule.color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.4)
	back_rule.custom_minimum_size = Vector2(900, 1)
	_col.add_child(back_rule)

	var back_btn := _make_settings_btn("BACK", "", func(): _build_main_menu())
	back_btn.custom_minimum_size = Vector2(900, 44)
	_col.add_child(back_btn)
	_kb_apply_focus()


# ── Helper: audio bus slider row ──────────────────────────────────────────────
func _make_slider_row(label_text: String, bus_name: String,
		min_v: float, max_v: float, step: float) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	wrap.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(120, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	var bus_idx := AudioServer.get_bus_index(bus_name)
	var cur : float = 1.0
	if bus_idx >= 0:
		cur = db_to_linear(AudioServer.get_bus_volume_db(bus_idx))
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = clampf(cur, min_v, max_v)
	slider.custom_minimum_size = Vector2(200, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var val_lbl := Label.new()
	val_lbl.text = "%d%%" % int(cur * 100)
	val_lbl.custom_minimum_size = Vector2(44, 0)
	val_lbl.add_theme_font_size_override("font_size", 11)
	val_lbl.add_theme_font_override("font", _font)
	val_lbl.add_theme_color_override("font_color", C_DIM)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	row.add_child(val_lbl)
	slider.value_changed.connect(func(v: float):
		val_lbl.text = "%d%%" % int(v * 100)
		if bus_idx >= 0:
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(v) if v > 0.0 else -80.0))
	return wrap

# ── Helper: CRT shader parameter slider row ───────────────────────────────────
func _make_shader_slider_row(label_text: String, mat: ShaderMaterial,
		param: String, min_v: float, max_v: float, step: float, cur: float) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	wrap.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(120, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = clampf(cur, min_v, max_v)
	slider.custom_minimum_size = Vector2(200, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var val_lbl := Label.new()
	val_lbl.text = "%.2f" % cur
	val_lbl.custom_minimum_size = Vector2(44, 0)
	val_lbl.add_theme_font_size_override("font_size", 11)
	val_lbl.add_theme_font_override("font", _font)
	val_lbl.add_theme_color_override("font_color", C_DIM)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	row.add_child(val_lbl)
	slider.value_changed.connect(func(v: float):
		val_lbl.text = "%.2f" % v
		mat.set_shader_parameter(param, v))
	return wrap

# ── Helper: get CRT ShaderMaterial ───────────────────────────────────────────
func _get_crt_mat() -> ShaderMaterial:
	var mesh := get_tree().root.get_node_or_null("GameRoot/TVOverlay/MeshInstance2D") as MeshInstance2D
	return mesh.material as ShaderMaterial if (mesh and mesh.material) else null


func _make_section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_color_override("font_color", C_DIM)
	return lbl


## Compact left-aligned section header for two-column settings layout.
func _make_settings_header(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_color_override("font_color", C_ACCENT)
	return lbl


## Compact button for two-column settings layout (no hint label, left-aligned).
func _make_settings_btn(label: String, hint: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_font_override("font", _font)
	for col_key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(col_key, C_TEXT)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.10, 0.08, 0.07)
	sn.border_color = C_ACCENT
	sn.set_border_width_all(0)
	sn.border_width_left = 2
	sn.set_content_margin_all(8)
	var sh := StyleBoxFlat.new()
	sh.bg_color = C_HOVER
	sh.border_color = C_ACCENT
	sh.set_border_width_all(0)
	sh.border_width_left = 2
	sh.set_content_margin_all(8)
	for st in ["normal", "focus"]:
		btn.add_theme_stylebox_override(st, sn)
	for st in ["hover", "pressed"]:
		btn.add_theme_stylebox_override(st, sh)
	if hint != "":
		btn.tooltip_text = hint
	btn.pressed.connect(callback)
	return btn


func _clear_col() -> void:
	for c in _col.get_children():
		c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_kb_index = 0
	_kb_btn   = null


func _make_btn(label: String, hint: String, font: Font, callback: Callable, disabled: bool = false) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)

	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(420, 52)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_font_override("font", font)
	btn.disabled = disabled

	var text_col := C_DIM if disabled else C_TEXT
	for col_key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_disabled_color"]:
		btn.add_theme_color_override(col_key, text_col)

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.07, 0.06, 0.05) if disabled else Color(0.10, 0.08, 0.07)
	sn.border_color = C_DIM if disabled else C_ACCENT
	sn.set_border_width_all(1)
	sn.set_content_margin_all(12)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = C_HOVER

	for st in ["normal", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, sn)
	for st in ["hover", "pressed"]:
		btn.add_theme_stylebox_override(st, sh)

	if not disabled:
		btn.pressed.connect(callback)
	wrap.add_child(btn)

	if hint != "":
		var hint_lbl := Label.new()
		hint_lbl.text = hint
		hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint_lbl.add_theme_font_size_override("font_size", 11)
		hint_lbl.add_theme_font_override("font", font)
		hint_lbl.add_theme_color_override("font_color", C_DIM)
		wrap.add_child(hint_lbl)

	return wrap


## Open the boot_sequence manual directly (skipping the POST sequence).
func _open_manual() -> void:
	var nodes := get_tree().get_nodes_in_group("boot_sequence")
	if nodes.is_empty():
		push_warning("StartScreen: no boot_sequence node found in group 'boot_sequence'")
		return
	var boot = nodes[0]
	if boot.has_method("show_manual"):
		if not boot.finished.is_connected(_on_manual_closed):
			boot.finished.connect(_on_manual_closed, CONNECT_ONE_SHOT)
		boot.show_manual()


func _on_manual_closed() -> void:
	pass  # Manual just hides itself; start screen stays as-is.
