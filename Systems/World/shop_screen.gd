class_name ShopScreen
extends CanvasLayer
## The buy screen for one shop tile. Opened from the in-world shop counter and from a
## double-click on the shop's tile in the plan screen; both go through WorldController.
##
## Lists the shelves DayCycle stocked for the tile: item, copies left, price and a Buy
## button. Buying goes through RoomFeatures.buy, so the cost comes out of the run's stock
## and the item lands in the party's bag. Buying is only possible while planning; the
## reason is shown otherwise.
##
## Every label here is functional. Item names and descriptions come from ItemDef, and the
## shop's name from its TileDef.

signal opened
signal closed

var day: DayCycle

var _pos := Vector2i.ZERO
var _root: Control
var _title: Label
var _stock: Label
var _status: Label
var _list: VBoxContainer


func _ready() -> void:
	layer = 12
	_build()


func _exit_tree() -> void:
	_disconnect()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ public

## Shows the shop on Treble cell `pos`.
func open(p_day: DayCycle, pos: Vector2i) -> void:
	_build()
	_disconnect()
	day = p_day
	_pos = pos
	day.shop_changed.connect(_on_shop_changed)
	day.phase_changed.connect(_on_phase_changed)
	_status.text = ""
	if not _root.visible:
		_root.visible = true
		opened.emit()
	_refresh()


func close() -> void:
	if _root == null or not _root.visible:
		return
	_root.visible = false
	closed.emit()


func is_open() -> bool:
	return _root != null and _root.visible


## Buys shelf `index` of the open shop and reports the result in the status line.
func buy(index: int) -> void:
	if day == null:
		return
	var report := RoomFeatures.buy(day, _pos, index, Rules.roster)
	if bool(report["ok"]):
		_status.text = "Bought %s." % _item_name(report["item"] as ItemDef)
	else:
		_status.text = String(report["reason"])
	_refresh()


# ------------------------------------------------------------------- build

func _build() -> void:
	if _root != null:
		return
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var outer := VBoxContainer.new()
	margin.add_child(outer)

	var header := HBoxContainer.new()
	outer.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_stock = Label.new()
	_stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_stock)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_status)


func _disconnect() -> void:
	if day == null:
		return
	if day.shop_changed.is_connected(_on_shop_changed):
		day.shop_changed.disconnect(_on_shop_changed)
	if day.phase_changed.is_connected(_on_phase_changed):
		day.phase_changed.disconnect(_on_phase_changed)


# ----------------------------------------------------------------- signals

func _on_shop_changed(pos: Vector2i) -> void:
	if pos == _pos:
		_refresh()


func _on_phase_changed(phase: DayCycle.Phase) -> void:
	if phase != DayCycle.Phase.PLAN:
		close()


# ----------------------------------------------------------------- refresh

func _refresh() -> void:
	if day == null or _root == null:
		return
	var tile := day.tile_at(_pos, TileDef.Clef.TREBLE)
	_title.text = (tile.def.display_name if tile.def.display_name != "" else String(tile.def.id)) \
			if tile != null else "(%d, %d)" % [_pos.x, _pos.y]
	_stock.text = _amounts(day.stock)
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var shelves := day.shop_offers(_pos)
	if shelves.is_empty():
		var empty := Label.new()
		empty.text = "Nothing for sale."
		_list.add_child(empty)
		return
	for i in shelves.size():
		_list.add_child(_make_row(i, shelves[i]))


func _make_row(index: int, shelf: Dictionary) -> Control:
	var offer := shelf["offer"] as ShopOffer
	var left := int(shelf["left"])
	var row := HBoxContainer.new()

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name_label := Label.new()
	name_label.text = "%s  (%d left)" % [_item_name(offer.item), left]
	text.add_child(name_label)
	if offer.item != null and offer.item.description != "":
		var desc := Label.new()
		desc.text = offer.item.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(300, 0)
		text.add_child(desc)

	var price_label := Label.new()
	price_label.text = _amounts(day.shop_price(_pos, index))
	row.add_child(price_label)

	var b := Button.new()
	b.text = "Buy"
	b.disabled = left <= 0
	var check := day.can_buy(_pos, index)
	if not bool(check["ok"]):
		b.modulate = Color(1, 1, 1, 0.5)
		b.tooltip_text = String(check["reason"])
	b.pressed.connect(buy.bind(index))
	row.add_child(b)
	return row


# ----------------------------------------------------------------- helpers

func _item_name(item: ItemDef) -> String:
	if item == null:
		return "?"
	return item.display_name if item.display_name != "" else String(item.id)


## "cuts 3, red 2": note colours first, then cuts, then anything else.
func _amounts(amounts: Dictionary) -> String:
	if amounts.is_empty():
		return "-"
	var left := {}
	for key in amounts:
		left[StringName(key)] = int(amounts[key])
	var order: Array[StringName] = []
	order.append_array(day.config.note_ids)
	order.append(day.config.cuts_id)
	var parts: Array[String] = []
	for id in order:
		if left.has(id):
			parts.append("%s %d" % [id, left[id]])
			left.erase(id)
	var rest := left.keys()
	rest.sort()
	for id in rest:
		parts.append("%s %d" % [id, left[id]])
	return ", ".join(parts)
