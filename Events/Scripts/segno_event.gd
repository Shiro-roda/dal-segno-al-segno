extends Control
# Segno event — two modes:
#   Placement: shown after placing/re-placing the Segno. Single CONTINUE button.
#   Pickup prompt: shown when the player steps on a Segno room ready to pick up.
#     Two buttons: PICK UP (emits pickup_confirmed) and LEAVE (emits event_finished).

signal event_finished   # dismissed without picking up, or placement acknowledged
signal pickup_confirmed # player chose to pick up the Segno

const C_BG       := Color(0.05, 0.04, 0.04, 1.0)
const C_BORDER   := Color(0.35, 0.28, 0.22, 1.0)
const C_ACCENT   := Color(0.52, 0.42, 0.28, 1.0)
const C_SEGNO_DC := Color(0.45, 0.65, 0.35, 1.0)  # green  — D.C. al Segno
const C_SEGNO_DS := Color(0.85, 0.60, 0.20, 1.0)  # amber  — D.S. al Segno
const C_TEXT     := Color(0.88, 0.83, 0.74, 1.0)
const C_DIM      := Color(0.55, 0.50, 0.43, 1.0)

## Placement mode: true if replacing an existing segno.
var is_replacing : bool = false
## Pickup-prompt mode: set before _ready by dungeon_controller.
var is_pickup_prompt : bool = false
## true = D.S. al Segno (battles reprimed); false = D.C. al Segno (no reprime).
var is_ds_transit : bool = false
## Blocked-notice mode: shown when there are no valid Segno target candidates yet.
var is_blocked_notice : bool = false


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

	var accent_color : Color
	if is_blocked_notice:
		accent_color = C_DIM
	elif is_ds_transit:
		accent_color = C_SEGNO_DS
	elif is_pickup_prompt:
		accent_color = C_SEGNO_DC
	else:
		accent_color = C_ACCENT

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.08, 0.07, 0.06, 1.0)
	sbox.border_color = accent_color
	sbox.set_border_width_all(2)
	sbox.set_content_margin_all(40)
	panel.add_theme_stylebox_override("panel", sbox)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	if is_blocked_notice:
		title.text = "§"
	elif is_pickup_prompt:
		title.text = "D.S. al §" if is_ds_transit else "D.C. al §"
	else:
		title.text = "§"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", accent_color)
	vbox.add_child(title)

	var div := ColorRect.new()
	div.color = accent_color
	div.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", C_TEXT)
	vbox.add_child(body)

	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", C_DIM)
	vbox.add_child(note)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	if is_blocked_notice:
		# ── Blocked notice: single CONTINUE ─────────────────────────────
		var ok_btn := _make_btn("CONTINUE", C_DIM, C_BORDER,
			func(): emit_signal("event_finished"))
		btn_row.add_child(ok_btn)
	elif is_pickup_prompt:
		# ── Pickup prompt: two buttons ──────────────────────────────────────
		var pickup_btn := _make_btn(
			"PICK UP", accent_color, C_BORDER,
			func(): emit_signal("pickup_confirmed"))
		btn_row.add_child(pickup_btn)

		var leave_btn := _make_btn(
			"LEAVE", Color(0,0,0,0), C_BORDER,
			func(): emit_signal("event_finished"))
		leave_btn.add_theme_color_override("font_color", C_DIM)
		leave_btn.add_theme_color_override("font_hover_color", C_TEXT)
		btn_row.add_child(leave_btn)
	else:
		# ── Placement acknowledgement: single CONTINUE ───────────────────
		var cont_btn := _make_btn(
			"CONTINUE", C_ACCENT, C_BORDER,
			func(): emit_signal("event_finished"))
		btn_row.add_child(cont_btn)

	# Fill body/note text after layout so vars are set.
	await get_tree().process_frame
	if is_blocked_notice:
		body.text = "The path ahead is not yet clear."
		note.text = "Explore further before relocating the Segno.\nPress E to disable the Blue channel, and see how far you must expand."
	elif is_pickup_prompt:
		if is_ds_transit:
			body.text = "Pick up the Segno and carry it to its new resting place."
			note.text = "All battles along the route have been reprimed.\nYour Beat Bolts(ammunition) and your allies' will to fight will no longer be restored at the end of a battle."
		else:
			body.text = "The Segno awaits. Carry it forward to mark your path."
			note.text = "Building is suspended until you set it down."
	else:
		if is_replacing:
			body.text = "Your mark has been moved."
			note.text = "The Segno will no longer prevent your allies from reinvigorating their anima,\nand will resume supplying you with Beat Bolts."
		else:
			body.text = "If you fall, you will return here."
			note.text = "You will need to find the Segno once again if it expires in your stead."


func _make_btn(label: String, bg: Color, border: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(160, 44)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_color_override("font_hover_color", C_TEXT)
	btn.add_theme_color_override("font_pressed_color", C_TEXT)
	btn.add_theme_color_override("font_focus_color", C_TEXT)
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_content_margin_all(10)
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, s)
	btn.pressed.connect(cb)
	return btn
