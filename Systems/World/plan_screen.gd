class_name PlanScreen
extends CanvasLayer
## The planning phase: spend stock on tiles, place the Segno, choose how the tithe is
## paid, then go.
##
## Two grids, one screen. The Treble tab shows the Town and lists village tiles, which
## are always available. The Bass tab shows the Dungeon and lists today's blueprints.
## Pick a tile, then click an open slot to place it. Segno mode (Bass tab) moves the
## party's spawn. Erase mode removes tiles: only spent rooms, unless
## WorldConfig.erase_any_tile is on.
##
## Every label here is functional. Names, descriptions and colours come from your
## TileDef resources; nothing is written for you.

signal expedition_requested
## The screen became visible / hidden (the world controller locks the player on this).
signal opened
signal closed

const CELL := Vector2(104, 64)
const FAR := Vector2i(1 << 20, 1 << 20)  # a cell far from any ruin: undiscounted prices
const RUIN_COLOR := Color(0.28, 0.28, 0.28)
const SPENT_COLOR := Color(0.85, 0.85, 0.85)
const SEGNO_COLOR := Color(1.0, 0.85, 0.2)
const PATH_COLOR := Color(0.45, 0.75, 1.0)

var day: DayCycle
## Show the screen whenever a day's planning begins. Turn off when something else (the
## console on the Town's origin tile) opens it with show_screen().
var auto_show := true

var _hub_defs: Array[TileDef] = []
var _selected: TileDef
var _erase := false
var _segno_mode := false
var _view: TileDef.Clef = TileDef.Clef.TREBLE

var _root: Control
var _title: Label
var _stock: Label
var _report: Label
var _status: Label
var _grid: GridContainer
var _tabs: TabContainer
var _hub_list: VBoxContainer
var _dungeon_list: VBoxContainer
var _info: Label
var _tithe: Label
var _dungeon_count: Label
var _path_label: Label
var _party_label: Label
var _notes_first: CheckButton
var _erase_button: Button
var _segno_button: Button
var _close_button: Button


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
		if def != null and not def.is_exit and not def.is_origin:
			_hub_defs.append(def)
	day.phase_changed.connect(_on_phase_changed)
	day.tile_changed.connect(_on_tile_changed)
	day.segno_changed.connect(_refresh)
	day.blueprints_changed.connect(_refresh)
	day.log_line.connect(_on_log)
	_notes_first.set_pressed_no_signal(day.tithe_notes_first)
	_on_phase_changed(day.phase)


func is_open() -> bool:
	return _root != null and _root.visible


## Opens the screen (only while planning).
func show_screen() -> void:
	if day == null or day.phase != DayCycle.Phase.PLAN:
		return
	_set_visible(true)
	_refresh()


func close_screen() -> void:
	_set_visible(false)


## Which grid is on show.
func view() -> TileDef.Clef:
	return _view


func set_view(clef: TileDef.Clef) -> void:
	if _view == clef:
		return
	_view = clef
	_tabs.current_tab = int(clef)
	if _selected != null and _selected.clef() != clef:
		_selected = null
	if clef == TileDef.Clef.TREBLE:
		_segno_mode = false
		_segno_button.set_pressed_no_signal(false)
	_refresh()


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


## Picks a tile from the palette (or puts it back if it was already picked). Switches to
## the tab of the clef the tile belongs on.
func choose_def(def: TileDef) -> void:
	_selected = null if _selected == def else def
	_erase = false
	_segno_mode = false
	_erase_button.set_pressed_no_signal(false)
	_segno_button.set_pressed_no_signal(false)
	if _selected != null:
		set_view(_selected.clef())
	_refresh()


## Clicks a grid cell: erase it, move the Segno there, place the chosen tile on it, or
## just inspect it.
func click_cell(pos: Vector2i) -> void:
	if day == null:
		return
	if _erase:
		day.erase_tile(pos, _view)
		return
	if _segno_mode:
		day.set_segno(pos)
		return
	if _selected != null:
		if _selected.clef() != _view:
			_status.text = "That tile belongs on the other clef."
			return
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
		_segno_mode = false
		_segno_button.set_pressed_no_signal(false)
	_refresh()


## Segno mode: clicking an empty Bass cell next to a standing room builds the Segno room
## there (free), moving it if it was already placed. Press Erase on it to pick it up.
func set_segno_mode(on: bool) -> void:
	_segno_mode = on
	_segno_button.set_pressed_no_signal(on)
	if on:
		_selected = null
		_erase = false
		_erase_button.set_pressed_no_signal(false)
		set_view(TileDef.Clef.BASS)
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


## Opens the party menu over this screen: pick companions, equip them, spend level-ups.
func open_party_menu() -> void:
	var menu := get_tree().get_first_node_in_group("party_menu") as PartyMenu
	if menu == null:
		_status.text = "The party menu isn't available."
		return
	if not menu.menu_closed.is_connected(_refresh_party):
		menu.menu_closed.connect(_refresh_party)
	menu.show_menu()


# ------------------------------------------------------------------- build

func _build() -> void:
	if _root != null:
		return
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
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
	_fit(_stock, 1.0)
	_stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_stock)
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(close_screen)
	header.add_child(_close_button)

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

	# Tab order matches TileDef.Clef: TREBLE = 0, BASS = 1.
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_panel.add_child(_tabs)
	_hub_list = _make_tab(_tabs, "Treble")
	_dungeon_list = _make_tab(_tabs, "Bass")
	_tabs.tab_changed.connect(_on_tab_changed)

	var tools := HBoxContainer.new()
	side_panel.add_child(tools)
	_erase_button = Button.new()
	_erase_button.text = "Erase"
	_erase_button.toggle_mode = true
	_erase_button.toggled.connect(set_erase)
	tools.add_child(_erase_button)
	_segno_button = Button.new()
	_segno_button.text = "Place Segno"
	_segno_button.toggle_mode = true
	_segno_button.toggled.connect(set_segno_mode)
	tools.add_child(_segno_button)

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(0, 170)
	side_panel.add_child(_info)

	var footer := HBoxContainer.new()
	outer.add_child(footer)
	_tithe = Label.new()
	_fit(_tithe, 3.0)
	footer.add_child(_tithe)
	_notes_first = CheckButton.new()
	_notes_first.text = "Pay tithe with notes first"
	_notes_first.toggled.connect(set_notes_first)
	footer.add_child(_notes_first)

	# Row of facts, then a row of status and buttons. Every label here can shrink, because a
	# container never gets narrower than its children's minimum sizes: one long line of
	# unwrapped text would make the whole screen wider than the viewport.
	var footer2 := HBoxContainer.new()
	outer.add_child(footer2)
	_dungeon_count = Label.new()
	_fit(_dungeon_count, 1.0)
	footer2.add_child(_dungeon_count)
	_path_label = Label.new()
	_path_label.add_theme_color_override("font_color", PATH_COLOR)
	_fit(_path_label, 2.0)
	footer2.add_child(_path_label)
	_party_label = Label.new()
	_party_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fit(_party_label, 2.0)
	footer2.add_child(_party_label)

	var footer3 := HBoxContainer.new()
	outer.add_child(footer3)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # messages matter: wrap, don't trim
	footer3.add_child(_status)
	var party_button := Button.new()
	party_button.text = "Party (TAB)"
	party_button.pressed.connect(open_party_menu)
	footer3.add_child(party_button)
	var go := Button.new()
	go.text = "Start expedition"
	go.pressed.connect(request_expedition)
	footer3.add_child(go)


## Lets a label give up width instead of demanding it: trimmed with an ellipsis when the
## row is tight. Needs expand so it still gets a share of the row.
func _fit(label: Label, ratio: float) -> void:
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_stretch_ratio = ratio
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_PASS


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
	if day.segno_changed.is_connected(_refresh):
		day.segno_changed.disconnect(_refresh)
	if day.blueprints_changed.is_connected(_refresh):
		day.blueprints_changed.disconnect(_refresh)
	if day.log_line.is_connected(_on_log):
		day.log_line.disconnect(_on_log)


func _set_visible(on: bool) -> void:
	if _root.visible == on:
		return
	_root.visible = on
	if on:
		opened.emit()
	else:
		closed.emit()


# ----------------------------------------------------------------- signals

func _on_phase_changed(phase: DayCycle.Phase) -> void:
	if phase != DayCycle.Phase.PLAN:
		_set_visible(false)
		return
	_selected = null
	_erase = false
	_segno_mode = false
	_erase_button.set_pressed_no_signal(false)
	_segno_button.set_pressed_no_signal(false)
	_status.text = ""
	if auto_show:
		_set_visible(true)
	_refresh()


func _on_tab_changed(index: int) -> void:
	set_view(index as TileDef.Clef)


func _on_tile_changed(_pos: Vector2i, _clef: TileDef.Clef) -> void:
	_refresh()


func _on_log(text: String) -> void:
	_status.text = text


# ----------------------------------------------------------------- refresh

func _refresh() -> void:
	if day == null or _root == null:
		return
	_title.text = "Day %d" % day.day
	_stock.text = _amounts(_stock_with_zeros())
	_close_button.visible = not auto_show
	_refresh_tithe()
	_refresh_palette()
	_refresh_grid()
	_refresh_dungeon_count()
	_refresh_path()
	_refresh_party()
	_info.text = _describe_def(_selected, null) if _selected != null else ""


## Who is going, and a nudge when the party needs choosing or someone can level up.
func _refresh_party() -> void:
	if _party_label == null:
		return
	var roster := Rules.roster
	if roster == null:
		_party_label.text = ""
		return
	var names: Array[String] = []
	for id in roster.active_companions():
		var sheet := roster.get_sheet(id)
		if sheet != null:
			names.append(sheet.display_name if sheet.display_name != "" else String(id))
	var text := "Party: " + (", ".join(names) if not names.is_empty() else "nobody chosen")
	if not roster.party_ready():
		text += "  (choose companions)"
	var levels := Leveling.ready_to_level(roster).size()
	if levels > 0:
		text += "  [%d ready to level up]" % levels
	_party_label.text = text


func _refresh_tithe() -> void:
	var preview := day.tithe_preview()
	var text := "Tithe tonight: %d   Pays: %s" % [day.tithe_tonight(), _amounts(preview["paid"])]
	if int(preview["shortfall"]) > 0:
		text += "   Short: %d" % int(preview["shortfall"])
	text += "   Debt: %d" % day.debt
	_tithe.text = text


## Dungeon rooms with a walking route to where the party will spawn, and their remnants.
func _refresh_dungeon_count() -> void:
	var tiles := 0
	var remnants := 0
	var reach: Dictionary = day.main_path()["reach"]
	for pos: Vector2i in day.bass.cells:
		var tile: TileInstance = day.bass.cells[pos]
		if not tile.is_live() or tile.def.is_exit or tile.def.enemies.is_empty():
			continue
		if not reach.has(pos):
			continue
		tiles += 1
		remnants += tile.def.spawn_count + int(day.carried.get(pos, 0))
	_dungeon_count.text = "Dungeon tiles: %d   Remnants: %d" % [tiles, remnants]


## The Segno and its scored main path.
func _refresh_path() -> void:
	if not day.config.require_segno:
		_path_label.text = ""
		return
	if not day.has_segno():
		_path_label.text = "   Segno: not placed"
		return
	var info := day.main_path()
	if not bool(info["found"]):
		_path_label.text = "   Segno (%d, %d): no route to the exit" % [day.segno.x, day.segno.y]
		return
	var text := "   Main path: %d steps, %d loops, loot +%d%%" % [
			int(info["steps"]), int(info["loops"]), roundi(float(info["bonus"]) * 100.0)]
	if bool(info["capped"]):
		text += " (search capped)"
	_path_label.text = text


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
	var slots := day.open_slots(_view)
	var slot_set := {}
	for pos in slots:
		slot_set[pos] = true
	var rect := day.grid_for(_view).bounds(slots)
	_grid.columns = rect.size.x
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_grid.add_child(_make_cell(Vector2i(x, y), slot_set))


func _make_cell(pos: Vector2i, slot_set: Dictionary) -> Control:
	var tile: TileInstance = day.grid_for(_view).get_tile(pos)
	if tile == null and not slot_set.has(pos):
		var gap := Control.new()
		gap.custom_minimum_size = CELL
		return gap
	var b := Button.new()
	b.custom_minimum_size = CELL
	b.clip_text = true
	b.pressed.connect(click_cell.bind(pos))
	b.mouse_entered.connect(_show_cell_info.bind(pos))
	var is_bass := _view == TileDef.Clef.BASS
	var is_segno: bool = is_bass and day.has_segno() and day.segno == pos
	if tile != null:
		b.text = _tile_text(tile)
		if is_segno:
			b.text = "(S) " + b.text
		var bg := Color(tile.color.x / 250.0, tile.color.y / 250.0, tile.color.z / 250.0).darkened(0.45)
		var border := Color(0.9, 0.5, 0.5)
		if tile.def.is_exit or tile.def.is_origin:
			border = Color.WHITE
		elif tile.def.category == TileDef.Category.VILLAGE:
			border = Color(0.6, 0.9, 0.6)
		if is_bass and (day.main_path()["on_path"] as Dictionary).has(pos):
			border = PATH_COLOR
		if is_segno:
			border = SEGNO_COLOR
		if tile.ruined:
			bg = RUIN_COLOR
		elif tile.is_depleted():
			bg = SPENT_COLOR.darkened(0.5)
		_apply_box(b, bg, border, 4 if is_segno else 3)
	else:
		b.text = "+"
		var ok: bool = (_selected != null and day.can_place(pos, _selected)["ok"]) \
				or (_segno_mode and is_bass and day.can_set_segno(pos)["ok"])
		_apply_box(b, Color(0.1, 0.1, 0.1), Color(0.4, 0.9, 0.4) if ok else Color(0.3, 0.3, 0.3), 2)
	return b


# ------------------------------------------------------------ descriptions

func _show_def_info(def: TileDef) -> void:
	_info.text = _describe_def(def, null)


func _show_cell_info(pos: Vector2i) -> void:
	_info.text = _info_for_cell(pos)


func _info_for_cell(pos: Vector2i) -> String:
	var tile: TileInstance = day.grid_for(_view).get_tile(pos)
	if tile != null:
		return _describe_tile(tile)
	if _selected != null and _selected.clef() == _view:
		return _describe_def(_selected, pos)
	return "(%d, %d)" % [pos.x, pos.y]


func _tile_text(tile: TileInstance) -> String:
	var text := _name_of(tile.def)
	if tile.ruined:
		text += "\nruin"
	elif tile.is_depleted():
		text += "\nspent"
	elif tile.def.category == TileDef.Category.DUNGEON and not tile.def.is_exit and not tile.def.is_segno:
		text += "\n%d %d %d" % [tile.color.x, tile.color.y, tile.color.z]
		var left := int(day.carried.get(tile.pos, 0))
		if left > 0:
			text += "  +%d" % left
	return text


## A tile that could be placed: its price and what it does, from the TileDef.
func _describe_def(def: TileDef, pos: Variant) -> String:
	var lines: Array[String] = []
	lines.append(_name_of(def))
	lines.append("Treble (Town)" if def.clef() == TileDef.Clef.TREBLE else "Bass (Dungeon)")
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
	var clef := tile.def.clef()
	var lines: Array[String] = []
	lines.append(_name_of(tile.def))
	lines.append("Treble (Town)" if clef == TileDef.Clef.TREBLE else "Bass (Dungeon)")
	lines.append("(%d, %d)" % [tile.pos.x, tile.pos.y])
	if tile.ruined:
		lines.append("Ruined")
	elif tile.is_depleted():
		lines.append("Spent")
	if clef == TileDef.Clef.BASS:
		if day.has_segno() and day.segno == tile.pos:
			lines.append("The Segno: the party spawns here")
		if (day.main_path()["on_path"] as Dictionary).has(tile.pos):
			lines.append("On the main path")
		var steps := day.distance_to_exit(tile.pos)
		lines.append("Distance to exit: " + (str(steps) if steps >= 0 else "cut off"))
	lines.append("Color: %d %d %d" % [tile.color.x, tile.color.y, tile.color.z])
	if tile.def.category == TileDef.Category.DUNGEON and not tile.def.is_exit and not tile.def.is_segno:
		var names: Array[String] = []
		for i in tile.lowest_channels():
			names.append(_channel_name(i))
		lines.append("Lowest: " + ", ".join(names))
		var left := int(day.carried.get(tile.pos, 0))
		if left > 0:
			lines.append("Remnants left alive: %d" % left)
	lines.append_array(_effects_of(tile.def))
	var erase := day.can_erase(tile.pos, clef)
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
	elif not def.is_exit and not def.is_segno:
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
		var fewest := -1
		var most := 0
		for template in def.enemies:
			if template == null:
				continue
			var drop := day.notes_dropped(def, template)
			fewest = drop if fewest < 0 else mini(fewest, drop)
			most = maxi(most, drop)
		if most > 0:
			lines.append("Notes per kill: %s" % (str(most) if fewest == most else "%d-%d" % [fewest, most]))
		if not is_equal_approx(def.note_multiplier, 1.0):
			lines.append("Note multiplier: x%s" % String.num(def.note_multiplier, 2))
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
