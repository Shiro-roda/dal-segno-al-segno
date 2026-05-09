extends Control

# Colours from ThemeManager — call _p() to get the palette.
func _p() -> Dictionary: return ThemeManager.palette


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = _p().bg
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
	title.add_theme_color_override("font_color", _p().text)
	vbox.add_child(title)

	var div := ColorRect.new()
	div.color = _p().primary
	div.custom_minimum_size = Vector2(320, 2)
	vbox.add_child(div)

	var sub := Label.new()
	sub.text = "..."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", _p().dim)
	vbox.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(spacer)

	var btn := Button.new()
	btn.text = "CONTINUE"
	btn.custom_minimum_size = Vector2(200, 52)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", _p().text)
	btn.add_theme_color_override("font_hover_color", _p().text)
	btn.add_theme_color_override("font_pressed_color", _p().text)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = _p().primary
	sbox.border_color = _p().dim
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
