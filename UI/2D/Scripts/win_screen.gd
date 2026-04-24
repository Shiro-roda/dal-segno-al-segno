extends Control

const C_BG     := Color(0.04, 0.03, 0.03, 1.0)
const C_TEXT   := Color(0.88, 0.83, 0.74, 1.0)
const C_DIM    := Color(0.55, 0.50, 0.43, 1.0)
const C_ACCENT := Color(0.72, 0.18, 0.18, 1.0)


func _ready() -> void:
	GlobalTheme.apply(self)
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 28)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "YOU WIN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", C_TEXT)
	vbox.add_child(title)

	var div := ColorRect.new()
	div.color = C_ACCENT
	div.custom_minimum_size = Vector2(320, 2)
	vbox.add_child(div)

	var sub := Label.new()
	sub.text = "..."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", C_DIM)
	vbox.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(spacer)

	var btn := Button.new()
	btn.text = "CONTINUE"
	btn.custom_minimum_size = Vector2(200, 52)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_color_override("font_hover_color", C_TEXT)
	btn.add_theme_color_override("font_pressed_color", C_TEXT)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = C_ACCENT
	sbox.border_color = Color(0.35, 0.28, 0.22, 1.0)
	sbox.set_border_width_all(1)
	sbox.set_content_margin_all(12)
	btn.add_theme_stylebox_override("normal",  sbox)
	btn.add_theme_stylebox_override("hover",   sbox)
	btn.add_theme_stylebox_override("pressed", sbox)
	btn.add_theme_stylebox_override("focus",   sbox)
	btn.pressed.connect(_on_continue)
	vbox.add_child(btn)


func _on_continue() -> void:
	# Show the motif tree then return to the main menu.
	GameController._show_start_screen()
