class_name PlanScreen
extends CanvasLayer
## The planning phase: spend stock on tiles, choose how the tithe is paid, then go.
##
## One screen for both kinds of tile. The Hub tab lists village tiles, which are
## always available. The Dungeon tab lists today's blueprints. Pick one, then click
## an open slot to place it. Erase mode removes tiles: only spent rooms, unless
## WorldConfig.erase_any_tile is on.
##
## Every label here is functional. Names, descriptions and colours come from your
## TileDef resources; nothing is written for you.

signal expedition_requested

const CELL := Vector2(104, 64)
const FAR := Vector2i(1 << 20, 1 << 20)  # a cell far from any ruin: undiscounted prices
const RUIN_COLOR := Color(0.28, 0.28, 0.28)
const SPENT_COLOR := Color(0.85, 0.85, 0.85)

var day: DayCycle

var _hub_defs: Array[TileDef] = []
var _selected: TileDef
var _erase := false

var _root: Control
var _title: Label
var _stock: Label
var _report: Label
var _status: Label
var _grid: GridContainer
var _hub_list: VBoxContainer
var _dungeon_list: VBoxContainer
var _info: Label
var _tithe: Label
var _dungeon_count: Label
var _notes_first: CheckButton
var _erase_button: Button


func _ready() -> void:
	layer = 11
	_build()


func _exit_tree() -> void:
	_disconnect()


# ------------------------------------------------------------------ public

## Starts showing `p_day`. `hub_defs` are the village tiles that can be built.
func open(p_day: DayCycle, hub_defs: Array[TileDef]) -> void:
	_build()
	_disconnect()
	day = p_day
	_hub_defs.clear()
	for def in hub_defs:
		if def != null and not def.is_exit:
			_hub_defs.append(def)
	day.phase_changed.connect(_on_phase_changed)
	day.tile_changed.connect(_on_tile_changed)
	day.blueprints_changed.connect(_refresh)
	day.log_line.connect(_on_log)
	_notes_first.set_pressed_no_signal(day.tithe_notes_first)
	_on_phase_changed(day.phase)


func is_open() -> bool:
	return _root != null and _root.visible


## Shows what the last expedition and the new day's turnover did.
func show_report(report: Dictionary, next_day: Dictionary) -> void:
	var lines: Array[String] = []
	lines.append("Banked: " + _amounts(report.get("banked", {})))
	lines.append("Left alive: %d" % int(report.get("left_alive", 0)))
	if not next_day.is_empty():
		lines.append("Income: " + _amounts(next_day.get("income", {})))
		lines.append("Tithe due %d, paid %d with %s, short %d" % [
				int(next_day.get("tithe_due", 0)), int(next_day.get("tithe_paid", 0)),
				_amounts(next_day.get("tithe_paid_with", {})), int(next_day.get("shortfall", 0))])
	_report.text = "\n".join(lines)
	_report.visible = true


## Picks a tile from the palette (or puts it back if it was already picked).
func choose_def(def: TileDef) -> void:
	_selected = null if _selected == def else def
	_erase = false
	_erase_button.set_pressed_no_signal(false)
	_refresh()


## Clicks a grid cell: erase it, place the chosen tile on it, or just inspect it.
func click_cell(pos: Vector2i) -> void:
	if day == null:
		return
	if _erase:
		day.erase_tile(pos)
		return
	if _selected != null:
		if day.place_tile(pos, _selected):
			# A blueprint is one card for one placement.
			if day.needs_blueprint(_selected) and not day.blueprints.has(_selected):
				_selected = null
		return
	_info.text = _info_for_cell(pos)


func set_erase(on: bool) -> void:
	_erase = on
	_erase_button.set_pressed_no_signal(on)
	if on:
		_selected = null
	_refresh()


func set_notes_first(on: bool) -> void:
	if day == null:
		return
	day.tithe_notes_first = on
	_notes_first.set_pressed_no_signal(on)
	_refresh_tithe()


func request_expedition() -> void:
	_report.text = ""
	_report.visible = false
	expedition_requested.emit()


# ------------------------------------------------------------------- build

func _build() -> void:
	if _root != null:
		return
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_root.add_child(margin)

	var outer := VBoxContainer.new()
	margin.add_child(outer)

	var header := HBoxContainer.new()
	outer.add_child(header)
	_title = Label.new()
	header.add_child(_title)
	_stock = Label.new()
	_stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_stock)

	_report = Label.new()
	_report.visible = false
	outer.add_child(_report)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_grid = GridContainer.new()
	scroll.add_child(_grid)

	var side_panel := VBoxContainer.new()
	side_panel.custom_minimum_size = Vector2(340, 0)
	body.add_child(side_panel)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_panel.add_child(tabs)
	_hub_list = _make_tab(tabs, "Hub")
	_dungeon_list = _make_tab(tabs, "Dungeon")

	_erase_button = Button.new()
	_erase_button.text = "Erase"
	_erase_button.toggle_mode = true
	_erase_button.toggled.connect(set_erase)
	side_panel.add_child(_erase_button)

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(0, 170)
	side_panel.add_child(_info)

	var footer := HBoxContainer.new()
	outer.add_child(footer)
	_tithe = Label.new()
	_tithe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_tithe)
	_notes_first = CheckButton.new()
	_notes_first.text = "Pay tithe with notes first"
	_notes_first.toggled.connect(set_notes_first)
	footer.add_child(_notes_first)

	var footer2 := HBoxContainer.new()
	outer.add_child(footer2)
	_dungeon_count = Label.new()
	footer2.add_child(_dungeon_count)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer2.add_child(_status)
	var go := Button.new()
	go.text = "Start expedition"
	go.pressed.connect(request_expedition)
	footer2.add_child(go)


func _make_tab(tabs: TabContainer, tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	tabs.add_child(scroll)
	return list


func _disconnect() -> void:
	if day == null:
		return
	if day.phase_changed.is_connected(_on_phase_changed):
		day.phase_changed.disconnect(_on_phase_changed)
	if day.tile_changed.is_connected(_on_tile_changed):
		day.tile_changed.disconnect(_on_tile_changed)
	if day.blueprints_changed.is_connected(_refresh):
		day.blueprints_changed.disconnect(_refresh)
	if day.log_line.is_connected(_on_log):
		day.log_line.disconnect(_on_log)


# ----------------------------------------------------------------- signals

func _on_phase_changed(phase: DayCycle.Phase) -> void:
	_root.visible = phase == DayCycle.Phase.PLAN
	if _root.visible:
		_selected = null
		_erase = false
		_erase_button.set_pressed_no_signal(false)
		_status.text = ""
		_refresh()


func _on_tile_changed(_pos: Vector2i) -> void:
	_refresh()


func _on_log(text: String) -> void:
	_status.text = text


# ----------------------------------------------------------------- refresh

func _refresh() -> void:
	if day == null or _root == null:
		return
	_title.text = "Day %d" % day.day
	_stock.text = _amounts(_stock_with_zeros())
	_refresh_tithe()
	_refresh_palette()
	_refresh_grid()
	_refresh_dungeon_count()
	_info.text = _describe_def(_selected, null) if _selected != null else ""


func _refresh_tithe() -> void:
	var preview := day.tithe_preview()
	var text := "Tithe tonight: %d   Pays: %s" % [day.tithe_tonight(), _amounts(preview["paid"])]
	if int(preview["shortfall"]) > 0:
		text += "   Short: %d" % int(preview["shortfall"])
	text += "   Debt: %d" % day.debt
	_tithe.text = text


func _refresh_dungeon_count() -> void:
	var tiles := 0
	var remnants := 0
	for pos: Vector2i in day.grid:
		var tile: TileInstance = day.grid[pos]
		if not tile.is_live() or tile.def.category != TileDef.Category.DUNGEON \
				or tile.def.is_exit or tile.def.enemies.is_empty():
			continue
		if day.distance_to_exit(pos) < 0:
			continue
		tiles += 1
		remnants += tile.def.spawn_count + int(day.carried.get(pos, 0))
	_dungeon_count.text = "Dungeon tiles: %d   Remnants: %d" % [tiles, remnants]


func _refresh_palette() -> void:
	_clear(_hub_list)
	_clear(_dungeon_list)
	for def in _hub_defs:
		_hub_list.add_child(_palette_button(def, 1))
	var counts := {}
	var order: Array[TileDef] = []
	for def in day.blueprints:
		if not counts.has(def):
			order.append(def)
		counts[def] = int(counts.get(def, 0)) + 1
	for def in order:
		_dungeon_list.add_child(_palette_button(def, int(counts[def])))


func _palette_button(def: TileDef, copies: int) -> Button:
	var b := Button.new()
	var label := _name_of(def)
	if copies > 1:
		label += "  x%d" % copies
	b.text = "%s\n%s" % [label, _amounts(_price(def))]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.button_pressed = _selected == def
	if not _can_afford(_price(def)):
		b.modulate = Color(1, 1, 1, 0.5)
	b.pressed.connect(choose_def.bind(def))
	b.mouse_entered.connect(_show_def_info.bind(def))
	return b


func _refresh_grid() -> void:
	_clear(_grid)
	var slots := day.open_slots()
	var slot_set := {}
	var lo := Vector2i.ZERO
	var hi := Vector2i.ZERO
	for pos: Vector2i in day.grid:
		lo = Vector2i(mini(lo.x, pos.x), mini(lo.y, pos.y))
		hi = Vector2i(maxi(hi.x, pos.x), maxi(hi.y, pos.y))
	for pos in slots:
		slot_set[pos] = true
		lo = Vector2i(mini(lo.x, pos.x), mini(lo.y, pos.y))
		hi = Vector2i(maxi(hi.x, pos.x), maxi(hi.y, pos.y))
	_grid.columns = hi.x - lo.x + 1
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			_grid.add_child(_make_cell(Vector2i(x, y), slot_set))


func _make_cell(pos: Vector2i, slot_set: Dictionary) -> Control:
	var tile: TileInstance = day.grid.get(pos)
	if tile == null and not slot_set.has(pos):
		var gap := Control.new()
		gap.custom_minimum_size = CELL
		return gap
	var b := Button.new()
	b.custom_minimum_size = CELL
	b.clip_text = true
	b.pressed.connect(click_cell.bind(pos))
	b.mouse_entered.connect(_show_cell_info.bind(pos))
	if tile != null:
		b.text = _tile_text(tile)
		var bg := Color(tile.color.x / 250.0, tile.color.y / 250.0, tile.color.z / 250.0).darkened(0.45)
		var border := Color(0.9, 0.5, 0.5)
		if tile.def.is_exit:
			border = Color.WHITE
		elif tile.def.category == TileDef.Category.VILLAGE:
			border = Color(0.6, 0.9, 0.6)
		if tile.ruined:
			bg = RUIN_COLOR
		elif tile.is_depleted():
			bg = SPENT_COLOR.darkened(0.5)
		_apply_box(b, bg, border, 3)
	else:
		b.text = "+"
		var ok: bool = _selected != null and day.can_place(pos, _selected)["ok"]
		_apply_box(b, Color(0.1, 0.1, 0.1), Color(0.4, 0.9, 0.4) if ok else Color(0.3, 0.3, 0.3), 2)
	return b


# ------------------------------------------------------------ descriptions

func _show_def_info(def: TileDef) -> void:
	_info.text = _describe_def(def, null)


func _show_cell_info(pos: Vector2i) -> void:
	_info.text = _info_for_cell(pos)


func _info_for_cell(pos: Vector2i) -> String:
	var tile: TileInstance = day.grid.get(pos)
	if tile != null:
		return _describe_tile(tile)
	if _selected != null:
		return _describe_def(_selected, pos)
	return "(%d, %d)" % [pos.x, pos.y]


func _tile_text(tile: TileInstance) -> String:
	var text := _name_of(tile.def)
	if tile.ruined:
		text += "\nruin"
	elif tile.is_depleted():
		text += "\nspent"
	elif tile.def.category == TileDef.Category.DUNGEON and not tile.def.is_exit:
		text += "\n%d %d %d" % [tile.color.x, tile.color.y, tile.color.z]
		var left := int(day.carried.get(tile.pos, 0))
		if left > 0:
			text += "  +%d" % left
	return text


## A tile that could be placed: its price and what it does, from the TileDef.
func _describe_def(def: TileDef, pos: Variant) -> String:
	var lines: Array[String] = []
	lines.append(_name_of(def))
	lines.append("Hub" if def.category == TileDef.Category.VILLAGE else "Dungeon")
	lines.append("Color: %d %d %d" % [def.color.x, def.color.y, def.color.z])
	lines.append("Cost: " + _amounts(day.cost_of(pos if pos != null else FAR, def)))
	if pos != null:
		var check := day.can_place(pos, def)
		if not check["ok"]:
			lines.append(String(check["reason"]))
	lines.append_array(_effects_of(def))
	if def.description != "":
		lines.append("")
		lines.append(def.description)
	return "\n".join(lines)


## A tile that is standing (or in ruins) on the grid.
func _describe_tile(tile: TileInstance) -> String:
	var lines: Array[String] = []
	lines.append(_name_of(tile.def))
	lines.append("Hub" if tile.def.category == TileDef.Category.VILLAGE else "Dungeon")
	lines.append("(%d, %d)" % [tile.pos.x, tile.pos.y])
	if tile.ruined:
		lines.append("Ruined")
	elif tile.is_depleted():
		lines.append("Spent")
	var steps := day.distance_to_exit(tile.pos)
	lines.append("Distance to exit: " + (str(steps) if steps >= 0 else "cut off"))
	lines.append("Color: %d %d %d" % [tile.color.x, tile.color.y, tile.color.z])
	if tile.def.category == TileDef.Category.DUNGEON and not tile.def.is_exit:
		var names: Array[String] = []
		for i in tile.lowest_channels():
			names.append(_channel_name(i))
		lines.append("Lowest: " + ", ".join(names))
		var left := int(day.carried.get(tile.pos, 0))
		if left > 0:
			lines.append("Remnants left alive: %d" % left)
	lines.append_array(_effects_of(tile.def))
	var erase := day.can_erase(tile.pos)
	if not erase["ok"]:
		lines.append(String(erase["reason"]))
	if tile.def.description != "":
		lines.append("")
		lines.append(tile.def.description)
	return "\n".join(lines)


func _effects_of(def: TileDef) -> Array[String]:
	var lines: Array[String] = []
	if def.category == TileDef.Category.VILLAGE:
		if not def.income.is_empty():
			lines.append("Income: " + _amounts(def.income))
	elif not def.is_exit:
		lines.append("Remnants: %d" % def.spawn_count)
		var names := {}
		for template in def.enemies:
			if template != null:
				names[template.display_name if template.display_name != "" else "?"] = true
		if not names.is_empty():
			var enemy_names: Array[String] = []
			for enemy_name: String in names:
				enemy_names.append(enemy_name)
			lines.append("Enemies: " + ", ".join(enemy_names))
		if def.notes_per_kill > 0:
			lines.append("Notes per kill: %d" % def.notes_per_kill)
		if not def.loot_per_kill.is_empty():
			lines.append("Loot per kill: " + _amounts(def.loot_per_kill))
	return lines


# ----------------------------------------------------------------- helpers

func _name_of(def: TileDef) -> String:
	return def.display_name if def.display_name != "" else String(def.id)


func _channel_name(channel: int) -> String:
	if channel >= 0 and channel < day.config.note_ids.size():
		return String(day.config.note_ids[channel])
	return str(channel)


func _price(def: TileDef) -> Dictionary:
	return day.cost_of(FAR, def)


func _can_afford(price: Dictionary) -> bool:
	for key in price:
		if int(day.stock.get(StringName(key), 0)) < int(price[key]):
			return false
	return true


## Stock with every note colour and cuts listed, even at zero.
func _stock_with_zeros() -> Dictionary:
	var out := day.stock.duplicate()
	for id in day.config.note_ids:
		if not out.has(id):
			out[id] = 0
	if not out.has(day.config.cuts_id):
		out[day.config.cuts_id] = 0
	return out


## "red_notes 10, cuts 3": note colours first, then cuts, then anything else.
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


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _apply_box(b: Button, bg: Color, border: Color, width: int) -> void:
	b.add_theme_stylebox_override("normal", _box(bg, border, width))
	b.add_theme_stylebox_override("hover", _box(bg.lightened(0.15), border, width))
	b.add_theme_stylebox_override("pressed", _box(bg.lightened(0.3), border, width))


func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_content_margin_all(4)
	return s
