extends Control
# Start screen — main menu with Continue and New Game submenu.

signal play_intro
signal skip_intro
signal start_new_run
signal continue_run
signal quit_game

const C_BG       := Color(0.04, 0.03, 0.03, 1.0)
const C_TEXT     := Color(0.88, 0.83, 0.74, 1.0)
const C_DIM      := Color(0.45, 0.40, 0.35, 1.0)
const C_ACCENT   := Color(0.72, 0.18, 0.18, 1.0)
const C_HOVER    := Color(0.20, 0.08, 0.08, 1.0)
const C_DISABLED := Color(0.30, 0.28, 0.25, 1.0)
const FONT_PATH  := "res://UI/Themes/Fonts/TerminalVector.ttf"

var _font : Font
var _col  : VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font

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


func _build_main_menu() -> void:
	_clear_col()

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
		"QUIT GAME",
		"",
		_font, func(): emit_signal("quit_game")))



func _build_new_game_menu() -> void:
	_clear_col()

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

	_col.add_child(_make_btn(
		"PLAY INTRO",
		"Take a stroll through the cloud waves.",
		_font, func(): emit_signal("play_intro")))

	_col.add_child(_make_btn(
		"PLAY TUTORIAL",
		"Start with the tutorial battle.",
		_font, func(): emit_signal("skip_intro")))

	_col.add_child(_make_btn(
		"START NEW RUN",
		"Skip straight to companion select.",
		_font, func(): emit_signal("start_new_run")))

	_col.add_child(_make_btn(
		"BACK",
		"",
		_font, func(): _build_main_menu()))


func _clear_col() -> void:
	for c in _col.get_children():
		c.queue_free()
	await get_tree().process_frame


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
