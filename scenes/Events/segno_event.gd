extends Control
# Segno event - shown when the player places or re-places a segno.
# Emits event_finished when dismissed.

signal event_finished

const C_BG     := Color(0.05, 0.04, 0.04, 1.0)
const C_BORDER := Color(0.35, 0.28, 0.22, 1.0)
const C_ACCENT := Color(0.52, 0.42, 0.28, 1.0)   # warm gold
const C_TEXT   := Color(0.88, 0.83, 0.74, 1.0)
const C_DIM    := Color(0.55, 0.50, 0.43, 1.0)

# Set to true before showing if replacing an existing segno
var is_replacing : bool = false


func _ready() -> void:
	GlobalTheme.apply(self)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.08, 0.07, 0.06, 1.0)
	sbox.border_color = C_ACCENT
	sbox.set_border_width_all(2)
	sbox.set_content_margin_all(40)
	panel.add_theme_stylebox_override("panel", sbox)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "SEGNO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", C_ACCENT)
	vbox.add_child(title)

	var div := ColorRect.new()
	div.color = C_ACCENT
	div.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div)

	# Body text
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", C_TEXT)
	body.text = ""  # set below
	vbox.add_child(body)

	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", C_DIM)
	note.text = ""  # set below
	vbox.add_child(note)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	var btn := Button.new()
	btn.text = "CONTINUE"
	btn.custom_minimum_size = Vector2(180, 44)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_color_override("font_hover_color", C_TEXT)
	btn.add_theme_color_override("font_pressed_color", C_TEXT)
	btn.add_theme_color_override("font_focus_color", C_TEXT)
	var btn_sbox := StyleBoxFlat.new()
	btn_sbox.bg_color = C_ACCENT
	btn_sbox.border_color = C_BORDER
	btn_sbox.set_border_width_all(1)
	btn_sbox.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal",  btn_sbox)
	btn.add_theme_stylebox_override("hover",   btn_sbox)
	btn.add_theme_stylebox_override("pressed", btn_sbox)
	btn.add_theme_stylebox_override("focus",   btn_sbox)
	btn.pressed.connect(func(): emit_signal("event_finished"))

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_child(btn)
	vbox.add_child(btn_row)

	# Fill text after layout (is_replacing is set before _ready by the caller)
	await get_tree().process_frame
	if is_replacing:
		body.text = ""
		note.text = "Your previous mark has been moved."
	else:
		body.text = ""
		note.text = "If you fall, you will return here."
