extends Control
# DungeonKeyItemsBar — a small persistent HUD strip shown during dungeon exploration.
# Displays key items from the run inventory (currently just the Segno).
# Mount it as a child of DungeonUI. Call refresh() whenever inventory changes.

var C_BG     := Color.BLACK
var C_BORDER := Color.WHITE
var C_ACCENT := Color.WHITE
const C_SEGNO  := Color(0.32, 0.44, 0.58, 1.0)
var C_TEXT   := Color.WHITE
var C_DIM    := Color.WHITE

func _refresh_palette() -> void:
	var p := ThemeManager.palette
	C_BG     = Color(p.bg.r, p.bg.g, p.bg.b, 0.88)
	C_BORDER = p.dim
	C_ACCENT = p.secondary
	C_TEXT   = p.text
	C_DIM    = p.dim

func _on_theme_changed(_id: int) -> void:
	_refresh_palette()
	# Restyle the background panel
	var bg := get_child(0) if get_child_count() > 0 else null
	if bg is PanelContainer:
		var sbox := StyleBoxFlat.new()
		sbox.bg_color = C_BG
		sbox.border_color = C_BORDER
		sbox.set_border_width_all(1)
		sbox.set_content_margin_all(8)
		(bg as PanelContainer).add_theme_stylebox_override("panel", sbox)
	# Refresh item chips so they pick up new colors
	refresh()

var _hbox : HBoxContainer
var _item_nodes : Array = []   # one PanelContainer per displayed item


func _ready() -> void:
	_refresh_palette()
	ThemeManager.theme_changed.connect(_on_theme_changed)
	# Pin to bottom-right of the screen viewport
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left   = -320
	offset_top    = -72
	offset_right  = -12
	offset_bottom = -12
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = C_BG
	sbox.border_color = C_BORDER
	sbox.set_border_width_all(1)
	sbox.set_content_margin_all(8)
	bg.add_theme_stylebox_override("panel", sbox)
	add_child(bg)

	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(outer)

	# "ITEMS" label
	var label := Label.new()
	label.text = "ITEMS"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", C_DIM)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	outer.add_child(label)

	var div := ColorRect.new()
	div.color = C_BORDER
	div.custom_minimum_size = Vector2(1, 0)
	div.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(div)

	_hbox = HBoxContainer.new()
	_hbox.add_theme_constant_override("separation", 6)
	_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(_hbox)

	# Refresh once at start and again each process tick so inventory changes reflect instantly
	refresh()


func _process(_delta: float) -> void:
	# Lightweight check: only redraw if item count has changed
	var run := GameController.current_run
	if run == null:
		if _item_nodes.size() > 0:
			_clear()
		return
	var key_items := _get_key_items(run)
	if key_items.size() != _item_nodes.size():
		refresh()


# Rebuild the bar from the current run inventory.
func refresh() -> void:
	_clear()
	var run := GameController.current_run
	if run == null:
		_show_empty()
		return

	var key_items := _get_key_items(run)
	if key_items.is_empty():
		_show_empty()
		return

	for item in key_items:
		_hbox.add_child(_make_item_chip(item))
		_item_nodes.append(true)  # just a size sentinel


# Returns array of ItemInstance that are key items (Segno, etc.)
func _get_key_items(run: RunState) -> Array:
	var result := []
	for item in run.inventory:
		if item.item_data is SegnoItem:
			result.append(item)
		# Future key item types can be added here
	return result


func _clear() -> void:
	for child in _hbox.get_children():
		child.queue_free()
	_item_nodes.clear()


func _show_empty() -> void:
	var lbl := Label.new()
	lbl.text = "—"
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", C_DIM)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hbox.add_child(lbl)
	_item_nodes.append(true)


func _make_item_chip(item: ItemInstance) -> Control:
	var chip := PanelContainer.new()
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = C_SEGNO if item.item_data is SegnoItem else C_ACCENT
	sbox.border_color = C_BORDER
	sbox.set_border_width_all(1)
	sbox.set_content_margin_all(6)
	chip.add_theme_stylebox_override("panel", sbox)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	chip.add_child(row)

	var name_lbl := Label.new()
	name_lbl.text = item.item_data.item_name.to_upper()
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_lbl)

	if item.stacks > 1:
		var count_lbl := Label.new()
		count_lbl.text = "×%d" % item.stacks
		count_lbl.add_theme_font_size_override("font_size", 11)
		count_lbl.add_theme_color_override("font_color", C_DIM)
		count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(count_lbl)

	# Tooltip: show item description on hover
	chip.tooltip_text = item.item_data.description if item.item_data.description != "" \
		else "Place in a room to mark your respawn point."
	chip.mouse_filter = Control.MOUSE_FILTER_STOP

	return chip
