class_name MenuStyle
extends RefCounted
## The party menu's look, built from ThemeManager.palette so it follows the active UI
## theme. One Theme resource styles every control in the menu; type variations give the
## few special looks (headings, list rows, cards). The static helpers build the small
## widgets the menu repeats: cards, key/value rows and stat bars.
##
## Variations: HeadingLabel, DimLabel, TitleLabel, AlertLabel (on Label),
## ListButton, ListButtonSelected (on Button), CardPanel, MenuPanel (on PanelContainer).

const FONT_SIZE := 14
const SMALL_SIZE := 12
const HEADING_SIZE := 13
const TITLE_SIZE := 22


# ----------------------------------------------------------------- colours

static func pal(key: String, fallback: Color = Color.WHITE) -> Color:
	var value: Variant = ThemeManager.palette.get(key, fallback)
	if value is Color:
		return value
	return fallback


static func fade(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


# ------------------------------------------------------------- style boxes

static func box(fill: Color, border: Color = Color.TRANSPARENT, border_width := 0,
		margin := 8.0, radius := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


static func _padded(sb: StyleBoxFlat, horizontal: float, vertical: float) -> StyleBoxFlat:
	sb.content_margin_left = horizontal
	sb.content_margin_right = horizontal
	sb.content_margin_top = vertical
	sb.content_margin_bottom = vertical
	return sb


# ------------------------------------------------------------------- theme

static func build_theme() -> Theme:
	var t := Theme.new()
	var text := pal("text")
	var dim := pal("dim")
	var accent := pal("primary")
	var gold := pal("secondary")
	var back := pal("bg", Color.BLACK)
	var font := ThemeManager.body_font()
	if font != null:
		t.default_font = font
	t.default_font_size = FONT_SIZE

	# Labels
	t.set_color(&"font_color", &"Label", text)
	_label_variation(t, &"HeadingLabel", gold, HEADING_SIZE)
	_label_variation(t, &"DimLabel", dim, SMALL_SIZE)
	_label_variation(t, &"TitleLabel", accent, TITLE_SIZE)
	_label_variation(t, &"AlertLabel", pal("alert"), FONT_SIZE)

	# Buttons
	_button_look(t, &"Button")
	_button_look(t, &"OptionButton")
	_list_button(t, &"ListButton", false)
	_list_button(t, &"ListButtonSelected", true)
	for kind: StringName in [&"CheckBox", &"CheckButton"]:
		for key: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color",
				&"font_focus_color", &"font_hover_pressed_color"]:
			t.set_color(key, kind, text)

	# Dropdown list of an OptionButton
	t.set_stylebox(&"panel", &"PopupMenu", box(back.lightened(0.04), accent, 1, 4.0))
	t.set_stylebox(&"hover", &"PopupMenu", box(fade(accent, 0.28), Color.TRANSPARENT, 0, 4.0))
	t.set_color(&"font_color", &"PopupMenu", text)
	t.set_color(&"font_hover_color", &"PopupMenu", text)

	# Tabs
	var selected := _padded(box(fade(accent, 0.18), Color.TRANSPARENT, 0, 8.0, 2), 18.0, 8.0)
	selected.border_color = accent
	selected.border_width_bottom = 3
	var idle := _padded(box(fade(back.lightened(0.08), 0.6), Color.TRANSPARENT, 0, 8.0, 2), 18.0, 8.0)
	var hovered := _padded(box(fade(accent, 0.08), Color.TRANSPARENT, 0, 8.0, 2), 18.0, 8.0)
	hovered.border_color = fade(accent, 0.5)
	hovered.border_width_bottom = 3
	t.set_stylebox(&"tab_selected", &"TabContainer", selected)
	t.set_stylebox(&"tab_unselected", &"TabContainer", idle)
	t.set_stylebox(&"tab_hovered", &"TabContainer", hovered)
	t.set_stylebox(&"tab_disabled", &"TabContainer", idle)
	t.set_stylebox(&"tab_focus", &"TabContainer", StyleBoxEmpty.new())
	t.set_stylebox(&"panel", &"TabContainer", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 10.0))
	t.set_color(&"font_selected_color", &"TabContainer", text)
	t.set_color(&"font_unselected_color", &"TabContainer", dim)
	t.set_color(&"font_hovered_color", &"TabContainer", text)
	t.set_font_size(&"font_size", &"TabContainer", FONT_SIZE)
	t.set_constant(&"side_margin", &"TabContainer", 0)

	# Panels
	var card_style := box(back.lightened(0.07), fade(dim, 0.3), 1, 12.0, 4)
	t.set_type_variation(&"CardPanel", &"PanelContainer")
	t.set_stylebox(&"panel", &"CardPanel", card_style)
	var frame := box(fade(back.lightened(0.03), 0.97), fade(accent, 0.65), 2, 18.0, 4)
	t.set_type_variation(&"MenuPanel", &"PanelContainer")
	t.set_stylebox(&"panel", &"MenuPanel", frame)

	# Separators and spacing
	var line := StyleBoxLine.new()
	line.color = fade(dim, 0.35)
	line.thickness = 1
	t.set_stylebox(&"separator", &"HSeparator", line)
	t.set_constant(&"separation", &"HSeparator", 10)
	t.set_constant(&"separation", &"VBoxContainer", 6)
	t.set_constant(&"separation", &"HBoxContainer", 8)
	t.set_constant(&"h_separation", &"GridContainer", 24)
	t.set_constant(&"v_separation", &"GridContainer", 4)

	# Tooltips
	t.set_stylebox(&"panel", &"TooltipPanel", box(back.lightened(0.04), accent, 1, 8.0))
	t.set_color(&"font_color", &"TooltipLabel", text)
	t.set_font_size(&"font_size", &"TooltipLabel", SMALL_SIZE + 1)
	return t


static func _label_variation(t: Theme, variation: StringName, color: Color, font_size: int) -> void:
	t.set_type_variation(variation, &"Label")
	t.set_color(&"font_color", variation, color)
	t.set_font_size(&"font_size", variation, font_size)


static func _button_look(t: Theme, kind: StringName) -> void:
	var text := pal("text")
	var dim := pal("dim")
	var accent := pal("primary")
	var face := pal("bg", Color.BLACK).lightened(0.12)
	t.set_stylebox(&"normal", kind, _padded(box(face, fade(dim, 0.35), 1), 12.0, 6.0))
	t.set_stylebox(&"hover", kind, _padded(box(fade(accent, 0.16), fade(accent, 0.7), 1), 12.0, 6.0))
	t.set_stylebox(&"pressed", kind, _padded(box(fade(accent, 0.28), accent, 1), 12.0, 6.0))
	t.set_stylebox(&"disabled", kind, _padded(box(face.darkened(0.2), fade(dim, 0.15), 1), 12.0, 6.0))
	var focus := _padded(box(Color.TRANSPARENT, fade(pal("focus_border"), 0.8), 1), 12.0, 6.0)
	focus.draw_center = false
	t.set_stylebox(&"focus", kind, focus)
	for key: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color",
			&"font_focus_color", &"font_hover_pressed_color"]:
		t.set_color(key, kind, text)
	t.set_color(&"font_disabled_color", kind, fade(dim, 0.5))


## A flat, left-aligned row for lists. The selected one carries an accent bar on its left.
static func _list_button(t: Theme, variation: StringName, selected: bool) -> void:
	var text := pal("text")
	var accent := pal("primary")
	t.set_type_variation(variation, &"Button")
	var resting := _padded(box(fade(accent, 0.18) if selected else Color.TRANSPARENT,
			accent if selected else Color.TRANSPARENT, 0, 8.0, 2), 12.0, 6.0)
	if selected:
		resting.border_width_left = 3
	var hover := _padded(box(fade(accent, 0.12), Color.TRANSPARENT, 0, 8.0, 2), 12.0, 6.0)
	var pressed := _padded(box(fade(accent, 0.26), Color.TRANSPARENT, 0, 8.0, 2), 12.0, 6.0)
	if selected:
		hover.border_color = accent
		hover.border_width_left = 3
		pressed.border_color = accent
		pressed.border_width_left = 3
	var focus := _padded(box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 8.0, 2), 12.0, 6.0)
	t.set_stylebox(&"normal", variation, resting)
	t.set_stylebox(&"hover", variation, hover)
	t.set_stylebox(&"pressed", variation, pressed)
	t.set_stylebox(&"focus", variation, focus)
	t.set_stylebox(&"disabled", variation, resting)
	for key: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color",
			&"font_focus_color", &"font_hover_pressed_color"]:
		t.set_color(key, variation, text)


# ----------------------------------------------------------------- widgets

static func label(text: String, variation: StringName = &"", autowrap := true) -> Label:
	var l := Label.new()
	l.text = text
	if autowrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		l.theme_type_variation = variation
	return l


static func heading(text: String) -> Label:
	return label(text.to_upper(), &"HeadingLabel", false)


## A bordered section. Returns the box to put its content in.
static func card(parent: Control, title := "", expand := false) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"CardPanel"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand:
		frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 5)
	frame.add_child(inner)
	if title != "":
		inner.add_child(heading(title))
	return inner


## "Key      value" on one line, the key dimmed and aligned.
static func pair(parent: Control, key: String, value: String, variation: StringName = &"",
		key_width := 110.0) -> void:
	var row := HBoxContainer.new()
	var left := label(key, &"DimLabel", false)
	left.custom_minimum_size = Vector2(key_width, 0.0)
	row.add_child(left)
	row.add_child(label(value, variation))
	parent.add_child(row)


## A filled bar with its text centred on it, for Corpus and Anima.
static func bar(current: int, maximum: int, fill: Color, text: String) -> Control:
	var top := maxi(maximum, 1)
	var progress := ProgressBar.new()
	progress.min_value = 0.0
	progress.max_value = float(top)
	progress.value = float(clampi(current, 0, top))
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(0.0, 22.0)
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.add_theme_stylebox_override("background",
			box(pal("bg", Color.BLACK).lightened(0.1), fade(pal("dim"), 0.4), 1, 0.0, 2))
	progress.add_theme_stylebox_override("fill", box(fade(fill, 0.75), Color.TRANSPARENT, 0, 0.0, 2))
	var caption := Label.new()
	caption.text = text
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_child(caption)
	return progress


## A flat, left-aligned list row. `selected` gives it the accent bar.
static func list_button(text: String, selected: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.theme_type_variation = &"ListButtonSelected" if selected else &"ListButton"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


## A scroll area that never scrolls sideways, so wrapped text fits its width.
static func scroll(min_width := 0.0) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(min_width, 0.0)
	return s
