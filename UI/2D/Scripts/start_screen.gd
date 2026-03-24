extends Control
# Start screen — shown once at game launch.
# Signals gamecontrol to either play the intro or skip straight to tutorial.

signal play_intro
signal skip_intro

const C_BG     := Color(0.04, 0.03, 0.03, 1.0)
const C_TEXT   := Color(0.88, 0.83, 0.74, 1.0)
const C_DIM    := Color(0.45, 0.40, 0.35, 1.0)
const C_ACCENT := Color(0.72, 0.18, 0.18, 1.0)
const C_HOVER  := Color(0.20, 0.08, 0.08, 1.0)
const FONT_PATH := "res://UI/Themes/Fonts/TerminalVector.ttf"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var font : Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font

	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var outer := CenterContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 24)
	outer.add_child(col)

	# Title
	var title := Label.new()
	title.text = "DAL SEGNO AL SEGNO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_font_override("font", font)
	title.add_theme_color_override("font_color", C_TEXT)
	col.add_child(title)

	var rule := ColorRect.new()
	rule.color = C_ACCENT
	rule.custom_minimum_size = Vector2(420, 1)
	col.add_child(rule)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	col.add_child(spacer)

	col.add_child(_make_btn(
		"PLAY INTRO SCENE",
		"Take a stroll through the cloud waves.",
		font, func(): emit_signal("play_intro")))

	col.add_child(_make_btn(
		"START TUTORIAL",
		"Begin directly with the tutorial battle.",
		font, func(): emit_signal("skip_intro")))


func _make_btn(label: String, hint: String, font: Font, callback: Callable) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)

	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(420, 52)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_font_override("font", font)
	for col_key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(col_key, C_TEXT)

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.10, 0.08, 0.07)
	sn.border_color = C_ACCENT
	sn.set_border_width_all(1)
	sn.set_content_margin_all(12)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = C_HOVER

	for st in ["normal", "focus"]:
		btn.add_theme_stylebox_override(st, sn)
	for st in ["hover", "pressed"]:
		btn.add_theme_stylebox_override(st, sh)

	btn.pressed.connect(callback)
	wrap.add_child(btn)

	var hint_lbl := Label.new()
	hint_lbl.text = hint
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 11)
	hint_lbl.add_theme_font_override("font", font)
	hint_lbl.add_theme_color_override("font_color", C_DIM)
	wrap.add_child(hint_lbl)

	return wrap
