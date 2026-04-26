extends Control
## Sundown Market shop event.
## Loads a stock of items when first entered; stock persists on the RoomInstance
## so the player can return and see what's left.
## Emits event_finished when the player leaves.

signal event_finished

const C_BG     := Color(0.05, 0.04, 0.04, 1.0)
const C_BORDER := Color(0.35, 0.28, 0.22, 1.0)
const C_ACCENT := Color(0.72, 0.55, 0.18, 1.0)  # warm gold
const C_TEXT   := Color(0.88, 0.83, 0.74, 1.0)
const C_DIM    := Color(0.55, 0.50, 0.43, 1.0)
const C_RED    := Color(0.85, 0.22, 0.22, 1.0)
const C_GREEN  := Color(0.25, 0.75, 0.35, 1.0)

## Injected by dungeon_controller before _ready.
var run_state    : RunState        = null
var room_instance : RoomInstance   = null  # for persisting stock

## Stock is an Array of Dictionaries:
## { "name", "desc", "type", "amount", "cost", "sold_out" }
var _stock : Array = []

## Item catalogue — each entry maps to either a ConsumableData (added to inventory)
## or a direct-apply effect (reprises, ties).
## "item_data" key holds a ConsumableData ref for inventory items; null for direct.
func _build_catalogue() -> Array:
	var ir := ItemRegistry
	return [
		{"name": ir.MEAT.item_name,       "desc": ir.MEAT.description,
		 "type": "inventory", "item_data": ir.MEAT,       "cost": 12},
		{"name": ir.BIG_MEAT.item_name,   "desc": ir.BIG_MEAT.description,
		 "type": "inventory", "item_data": ir.BIG_MEAT,   "cost": 25},
		{"name": ir.JERKY.item_name,      "desc": ir.JERKY.description,
		 "type": "inventory", "item_data": ir.JERKY,      "cost": 18},
		{"name": ir.FEAST.item_name,      "desc": ir.FEAST.description,
		 "type": "inventory", "item_data": ir.FEAST,      "cost": 38},
		{"name": ir.CANDY.item_name,      "desc": ir.CANDY.description,
		 "type": "inventory", "item_data": ir.CANDY,      "cost": 10},
		{"name": ir.SWEET.item_name,      "desc": ir.SWEET.description,
		 "type": "inventory", "item_data": ir.SWEET,      "cost": 20},
		{"name": ir.HARD_CANDY.item_name, "desc": ir.HARD_CANDY.description,
		 "type": "inventory", "item_data": ir.HARD_CANDY, "cost": 16},
		{"name": ir.BONBON.item_name,     "desc": ir.BONBON.description,
		 "type": "inventory", "item_data": ir.BONBON,     "cost": 28},
		{"name": ir.FLOOR_MAP.item_name,  "desc": ir.FLOOR_MAP.description,
		 "type": "instant", "item_data": ir.FLOOR_MAP,  "cost": 22},
		{"name": ir.PRIMER.item_name,     "desc": ir.PRIMER.description,
		 "type": "instant", "item_data": ir.PRIMER,     "cost": 28},
		{"name": ir.RITORNELLO.item_name, "desc": ir.RITORNELLO.description,
		 "type": "inventory", "item_data": ir.RITORNELLO, "cost": 30},
		{"name": ir.FLEE_TOKEN.item_name, "desc": ir.FLEE_TOKEN.description,
		 "type": "inventory", "item_data": ir.FLEE_TOKEN,  "cost": 35},
	]

## How many distinct items appear in one shop visit (picked randomly).
const STOCK_SIZE := 4

# UI refs
var _money_lbl  : Label
var _item_rows  : Array = []


func _ready() -> void:
	GlobalTheme.apply(self)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_generate_stock()
	_build_ui()


## Generate or restore stock for this room.
func _generate_stock() -> void:
	# Reuse room_instance.rest_options as persistent stock storage.
	if room_instance != null and not room_instance.rest_options.is_empty():
		_stock = room_instance.rest_options.duplicate(true)
		return
	# First visit — pick STOCK_SIZE random items from the catalogue.
	var pool : Array = _build_catalogue()
	pool.shuffle()
	_stock = []
	for i in min(STOCK_SIZE, pool.size()):
		var entry : Dictionary = pool[i].duplicate()
		entry["sold_out"] = false
		_stock.append(entry)
	# Persist on the room.
	if room_instance != null:
		room_instance.rest_options = _stock.duplicate(true)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -300.0
	panel.offset_top    = -280.0
	panel.offset_right  =  300.0
	panel.offset_bottom =  280.0
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = C_BG
	sbox.border_color = C_BORDER
	sbox.set_border_width_all(2)
	sbox.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sbox)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Title row
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	var title := Label.new()
	title.text = "Sundown Market"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", C_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	_money_lbl = Label.new()
	_money_lbl.add_theme_font_size_override("font_size", 14)
	_money_lbl.add_theme_color_override("font_color", C_ACCENT)
	title_row.add_child(_money_lbl)
	_refresh_money()

	# Divider
	var div := ColorRect.new()
	div.color = C_BORDER
	div.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div)

	# Stock rows
	_item_rows.clear()
	for i in _stock.size():
		var row := _build_item_row(i)
		vbox.add_child(row)
		_item_rows.append(row)

	# Leave button
	var div2 := ColorRect.new()
	div2.color = C_BORDER
	div2.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div2)

	var leave := Button.new()
	leave.text = "Leave"
	leave.add_theme_font_size_override("font_size", 13)
	leave.pressed.connect(_on_leave)
	vbox.add_child(leave)


func _build_item_row(idx: int) -> HBoxContainer:
	var item : Dictionary = _stock[idx]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_lbl := Label.new()
	name_lbl.text = item.get("name", "?")
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = item.get("desc", "")
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", C_DIM)
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(desc_lbl)

	var cost_lbl := Label.new()
	cost_lbl.text = "%d₵" % item.get("cost", 0)
	cost_lbl.add_theme_font_size_override("font_size", 13)
	cost_lbl.add_theme_color_override("font_color", C_ACCENT)
	cost_lbl.custom_minimum_size = Vector2(48, 0)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(cost_lbl)

	var buy_btn := Button.new()
	buy_btn.custom_minimum_size = Vector2(70, 0)
	buy_btn.add_theme_font_size_override("font_size", 12)
	var captured := idx
	buy_btn.pressed.connect(func(): _on_buy(captured))
	row.add_child(buy_btn)

	_refresh_row(idx, row, buy_btn)
	return row


func _refresh_money() -> void:
	if run_state == null:
		return
	_money_lbl.text = "%d₵" % run_state.money


func _refresh_row(idx: int, row: HBoxContainer, buy_btn: Button) -> void:
	var item : Dictionary = _stock[idx]
	var sold_out : bool = item.get("sold_out", false)
	var can_afford : bool = run_state != null and \
		run_state.money >= item.get("cost", 0)
	if sold_out:
		buy_btn.text = "Sold Out"
		buy_btn.disabled = true
		row.modulate = Color(0.5, 0.5, 0.5, 1.0)
	elif not can_afford:
		buy_btn.text = "Buy"
		buy_btn.disabled = true
		row.modulate = Color(0.7, 0.7, 0.7, 1.0)
	else:
		buy_btn.text = "Buy"
		buy_btn.disabled = false
		row.modulate = Color(1, 1, 1, 1)


func _on_buy(idx: int) -> void:
	if run_state == null:
		return
	var item : Dictionary = _stock[idx]
	var cost : int = item.get("cost", 0)
	if run_state.money < cost:
		return
	run_state.money -= cost
	_apply_item(item)
	_stock[idx]["sold_out"] = true
	# Persist updated stock on the room.
	if room_instance != null:
		room_instance.rest_options = _stock.duplicate(true)
	_refresh_money()
	# Rebuild the row in place.
	var old_row : HBoxContainer = _item_rows[idx]
	var parent := old_row.get_parent()
	var pos := old_row.get_index()
	old_row.queue_free()
	var new_row := _build_item_row(idx)
	parent.add_child(new_row)
	parent.move_child(new_row, pos)
	_item_rows[idx] = new_row


func _apply_item(item: Dictionary) -> void:
	var item_data := item.get("item_data", null) as ConsumableData
	if item_data == null:
		return
	match item.get("type", ""):
		"instant":
			# Apply the effect immediately — no inventory slot consumed.
			ItemRegistry.apply_effect(run_state, item_data, null)
		_:
			ItemRegistry.add_to_inventory(run_state, item_data)


func _on_leave() -> void:
	emit_signal("event_finished")
