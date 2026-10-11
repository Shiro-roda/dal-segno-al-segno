class_name PartyMenu
extends CanvasLayer
## Party menu (TAB). Three tabs:
##
##   Party      everyone recruited, who is going on the next expedition, and the selected
##              character's vitals, attributes, feats, abilities and equipment.
##   Inventory  the party's shared bag, with the details of the selected item.
##   Map        where the party is: the current room, or the whole dungeon, with the
##              day's resources and status beside it.
##
##   - The leader (the player character) always goes. Pick which companions come with
##     "Bring" / "Leave"; with every slot full, bringing someone new replaces whoever has
##     been in the party longest. The party can only change while planning in town.
##   - Equipment comes from, and returns to, the party's shared bag (any time the menu
##     can be opened).
##
## The look comes from MenuStyle (one Theme built from the active UI palette) and the
## maps are MapView controls. GameController adds one of these at startup. Open it with
## TAB, or call show_menu() (the plan screen has a button for it). It joins the group
## "party_menu".

signal menu_opened
signal menu_closed

const LEFT_COLUMN_WIDTH := 360.0
const SIDE_COLUMN_WIDTH := 320.0
const ANIMA_COLOR := Color(0.3, 0.55, 1.0)

var _open := false
var _leveling := false  # a LevelUpScreen is up on top of the menu
var _selected: StringName = &""
var _roster: PartyRoster
var _link: PlayerLink

var _root: Control
var _hint: Label
var _tabs: TabContainer
var _roster_box: VBoxContainer
var _party_box: VBoxContainer
var _detail_box: VBoxContainer
var _inventory_box: VBoxContainer
var _inventory_detail: VBoxContainer
var _map_tabs: TabContainer
var _room_view: MapView
var _dungeon_view: MapView
var _map_box: VBoxContainer
var _shown_item: ItemDef
var _shown_action: ActionDef


func _ready() -> void:
	# GameRoot's WorldLayer is 201 and fills the screen; stay above it, but below the
	# system menu (229-230) so ESC still goes on top.
	layer = 220
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("party_menu")
	_build()
	_root.visible = false
	ThemeManager.theme_changed.connect(_on_theme_changed)


func _exit_tree() -> void:
	_leveling = false
	if ThemeManager.theme_changed.is_connected(_on_theme_changed):
		ThemeManager.theme_changed.disconnect(_on_theme_changed)
	if _open:
		close_menu()


# ------------------------------------------------------------------ public

func is_open() -> bool:
	return _open


## Opens the menu if the game is in a state where that makes sense.
func show_menu() -> void:
	if _open or Rules.roster == null:
		return
	_roster = Rules.roster
	_roster.changed.connect(_refresh)
	if _selected == &"" or not _roster.blocks.has(_selected):
		_selected = _roster.leader_id()
	_open = true
	_root.visible = true
	_lock_player()
	# Open the map on the view that matters: the room if you are in one, else the dungeon.
	_map_tabs.current_tab = 0 if MapView.find_room(get_tree()) != null else 1
	_refresh()
	UISounds.play("menu_open")
	menu_opened.emit()


func close_menu() -> void:
	if not _open or _leveling:
		return
	_open = false
	_root.visible = false
	if _roster != null and _roster.changed.is_connected(_refresh):
		_roster.changed.disconnect(_refresh)
	_unlock_player()
	UISounds.play("menu_close")
	menu_closed.emit()


## True while companions can be swapped: planning in the Town (or no run started yet).
func party_editable() -> bool:
	var cycle := GameController.day_cycle
	return cycle == null or cycle.phase == DayCycle.Phase.PLAN


# ------------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_TAB:
		return
	if _leveling:
		get_viewport().set_input_as_handled()  # finish the level-up first
		return
	if _open:
		close_menu()
		get_viewport().set_input_as_handled()
	elif _can_open():
		show_menu()
		get_viewport().set_input_as_handled()


## Not over the boot sequence, start screen, system menu, a fight, a level-up or a
## dialogue, and only once a game is actually running.
func _can_open() -> bool:
	var boot := get_tree().get_first_node_in_group("boot_sequence") as CanvasItem
	if boot != null and boot.visible:
		return false
	if get_tree().get_first_node_in_group("start_screen") != null:
		return false
	var system := get_tree().get_first_node_in_group("system_menu")
	if system != null and bool(system.get("_open")):
		return false
	if GameController.world_layer == null or not GameController.world_layer.visible:
		return false
	for node in get_tree().get_nodes_in_group("dungeon_room"):
		if not node.is_queued_for_deletion() and not bool(node.call("can_leave")):
			return false
	var dialogic := get_node_or_null("/root/Dialogic")
	if dialogic != null and dialogic.get("current_timeline") != null:
		return false
	return Rules.roster != null and not Rules.roster.sheets.is_empty()


## Freezes the player while the menu is up. lock_controls() is a counter, so this
## stacks safely with the plan screen.
func _lock_player() -> void:
	_link = null
	for node in get_tree().get_nodes_in_group("party_link"):
		if not node.is_queued_for_deletion():
			_link = node as PlayerLink
	if _link != null:
		_link.lock_controls()


func _unlock_player() -> void:
	if is_instance_valid(_link):
		_link.unlock_controls()
	_link = null


# ------------------------------------------------------------------- build

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 28)
	_root.add_child(margin)

	var frame := PanelContainer.new()
	frame.theme_type_variation = &"MenuPanel"
	margin.add_child(frame)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	frame.add_child(outer)

	var header := HBoxContainer.new()
	outer.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	header.add_child(titles)
	titles.add_child(MenuStyle.label("PARTY", &"TitleLabel", false))
	_hint = MenuStyle.label("", &"DimLabel")
	titles.add_child(_hint)
	var close := Button.new()
	close.text = "Close (TAB)"
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(close_menu)
	header.add_child(close)
	outer.add_child(HSeparator.new())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_tabs)
	_build_party_tab()
	_build_inventory_tab()
	_build_map_tab()
	_root.theme = MenuStyle.build_theme()


func _build_party_tab() -> void:
	var body := HBoxContainer.new()
	body.name = "Party"
	body.add_theme_constant_override("separation", 14)
	_tabs.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(LEFT_COLUMN_WIDTH, 0.0)
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	var roster_card := MenuStyle.card(left, "ROSTER", true)
	var roster_scroll := MenuStyle.scroll()
	roster_card.add_child(roster_scroll)
	_roster_box = VBoxContainer.new()
	_roster_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_box.add_theme_constant_override("separation", 2)
	roster_scroll.add_child(_roster_box)
	_party_box = MenuStyle.card(left)

	var right := MenuStyle.scroll()
	body.add_child(right)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 10)
	right.add_child(_detail_box)


func _build_inventory_tab() -> void:
	var inv := HBoxContainer.new()
	inv.name = "Inventory"
	inv.add_theme_constant_override("separation", 14)
	_tabs.add_child(inv)

	var bag_card := MenuStyle.card(inv, "", true)
	var bag_panel := bag_card.get_parent() as Control
	bag_panel.size_flags_horizontal = Control.SIZE_FILL
	bag_panel.custom_minimum_size = Vector2(LEFT_COLUMN_WIDTH, 0.0)
	var bag_scroll := MenuStyle.scroll()
	bag_card.add_child(bag_scroll)
	_inventory_box = VBoxContainer.new()
	_inventory_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_box.add_theme_constant_override("separation", 2)
	bag_scroll.add_child(_inventory_box)

	var detail_scroll := MenuStyle.scroll()
	inv.add_child(detail_scroll)
	_inventory_detail = MenuStyle.card(detail_scroll)


func _build_map_tab() -> void:
	var body := HBoxContainer.new()
	body.name = "Map"
	body.add_theme_constant_override("separation", 14)
	_tabs.add_child(body)

	# Left: the map itself, as a room view and a whole-dungeon view.
	_map_tabs = TabContainer.new()
	_map_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_tabs.size_flags_stretch_ratio = 2.2
	body.add_child(_map_tabs)
	_room_view = MapView.new()
	_room_view.mode = MapView.Mode.ROOM
	_map_tabs.add_child(_room_view)
	_map_tabs.set_tab_title(0, "Current room")
	_dungeon_view = MapView.new()
	_dungeon_view.mode = MapView.Mode.DUNGEON
	_map_tabs.add_child(_dungeon_view)
	_map_tabs.set_tab_title(1, "Whole dungeon")

	# Right: where you are, the day's resources and the state of the dungeon.
	var side := MenuStyle.scroll(SIDE_COLUMN_WIDTH)
	body.add_child(side)
	_map_box = VBoxContainer.new()
	_map_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_box.add_theme_constant_override("separation", 10)
	side.add_child(_map_box)


func _on_theme_changed(_theme_id: int) -> void:
	_root.theme = MenuStyle.build_theme()
	_refresh()


# ----------------------------------------------------------------- refresh

func _refresh() -> void:
	if not _open or _roster == null:
		return
	var editable := party_editable()
	_refresh_hint(editable)
	_refresh_roster(editable)
	_refresh_party()
	_refresh_detail()
	_refresh_inventory()
	_refresh_map()


func _refresh_hint(editable: bool) -> void:
	var needed := mini(_roster.companion_slots(), _roster.companion_ids().size())
	if not editable:
		_hint.text = "The party is fixed while the expedition is under way."
	elif not _roster.party_ready():
		_hint.text = "Choose %d companion%s to bring on the next expedition." % [
				needed, "" if needed == 1 else "s"]
	else:
		_hint.text = "Party ready. Bringing someone new when full replaces whoever has been in longest."
	var can_level := Leveling.ready_to_level(_roster)
	if not can_level.is_empty():
		var names: Array[String] = []
		for id in can_level:
			names.append(_name_of(_roster.get_sheet(id)))
		_hint.text += "\nReady to level up: %s." % ", ".join(names)


func _refresh_roster(editable: bool) -> void:
	_clear(_roster_box)
	var lead := _roster.leader_id()
	var ids: Array[StringName] = [lead]
	ids.append_array(_roster.companion_ids())
	var going := _roster.active_companions()
	for char_id in ids:
		var sheet := _roster.get_sheet(char_id)
		var block := _roster.get_block(char_id)
		if sheet == null or block == null:
			continue
		var row := HBoxContainer.new()
		_roster_box.add_child(row)
		var pick := MenuStyle.list_button("%s    Lv %d" % [_name_of(sheet), block.level], char_id == _selected)
		pick.pressed.connect(_select.bind(char_id))
		row.add_child(pick)
		var tag := ""
		if char_id == lead:
			tag = "LEADER"
		elif going.has(char_id):
			tag = "GOING"
		if Leveling.can_level_up(sheet):
			tag = (tag + "  LEVEL UP").strip_edges()
		if tag != "":
			row.add_child(MenuStyle.label(tag, &"HeadingLabel", false))
		if char_id != lead:
			var bring := Button.new()
			bring.text = "Leave" if going.has(char_id) else "Bring"
			bring.disabled = not editable
			bring.pressed.connect(_on_bring.bind(char_id))
			row.add_child(bring)


func _refresh_party() -> void:
	_clear(_party_box)
	_party_box.add_child(MenuStyle.heading("CURRENT PARTY"))
	_add_slot_row(_party_box, "Leader", _roster.leader_id())
	var going := _roster.active_companions()
	for i in _roster.companion_slots():
		var char_id: StringName = going[i] if i < going.size() else &""
		_add_slot_row(_party_box, "Companion %d" % (i + 1), char_id)


func _add_slot_row(into: Control, slot_text: String, char_id: StringName) -> void:
	var sheet := _roster.get_sheet(char_id) if char_id != &"" else null
	MenuStyle.pair(into, slot_text, _name_of(sheet) if sheet != null else "(empty)", &"", 100.0)


func _refresh_detail() -> void:
	_clear(_detail_box)
	var sheet := _roster.get_sheet(_selected)
	var block := _roster.get_block(_selected)
	if sheet == null or block == null:
		return

	var who := MenuStyle.card(_detail_box)
	who.add_child(MenuStyle.label(_name_of(sheet).to_upper(), &"TitleLabel"))
	who.add_child(MenuStyle.label(_level_line(sheet, block), &"DimLabel"))
	if not sheet.is_player and Leveling.has_recommendations(sheet):
		var auto_pick := CheckBox.new()
		auto_pick.text = "Pick recommended level-ups automatically"
		auto_pick.button_pressed = sheet.auto_pick_recommended
		auto_pick.disabled = _leveling
		auto_pick.toggled.connect(_on_auto_pick_toggled.bind(_selected))
		who.add_child(auto_pick)
	if Leveling.can_level_up(sheet):
		var level_up := Button.new()
		level_up.text = "Level up to %d" % (sheet.level + 1)
		level_up.disabled = _leveling
		level_up.pressed.connect(_on_level_up.bind(_selected))
		who.add_child(level_up)

	var vitals := MenuStyle.card(_detail_box, "VITALS")
	vitals.add_child(MenuStyle.bar(block.corpus, block.max_corpus(), MenuStyle.pal("alert"),
			"Corpus    %d / %d" % [block.corpus, block.max_corpus()]))
	vitals.add_child(MenuStyle.bar(block.anima, block.max_anima(), ANIMA_COLOR,
			"Anima    %d / %d" % [block.anima, block.max_anima()]))
	MenuStyle.pair(vitals, "Defense", str(block.defense()))

	var attributes := MenuStyle.card(_detail_box, "ATTRIBUTES")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attributes.add_child(grid)
	for def in Rules.engine.stats_in_category(StatDef.Category.ATTRIBUTE):
		var stat_name := def.display_name if def.display_name != "" else String(def.id)
		var entry := HBoxContainer.new()
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key := MenuStyle.label(stat_name, &"DimLabel", false)
		key.custom_minimum_size = Vector2(100.0, 0.0)
		entry.add_child(key)
		entry.add_child(MenuStyle.label("%d  (%+d)" % [block.score(def.id), block.total_mod(def.id)], &"", false))
		grid.add_child(entry)

	if not sheet.feats.is_empty():
		var feats := MenuStyle.card(_detail_box, "FEATS")
		for feat in sheet.feats:
			if feat != null:
				var feat_label := MenuStyle.label(feat.display_name if feat.display_name != "" else String(feat.id))
				feat_label.tooltip_text = feat.description
				feat_label.mouse_filter = Control.MOUSE_FILTER_PASS
				feats.add_child(feat_label)

	if not sheet.known_actions.is_empty():
		var abilities := MenuStyle.card(_detail_box, "ABILITIES")
		for action in sheet.known_actions:
			if action != null:
				_add_action_entry(abilities, action)

	var gear := MenuStyle.card(_detail_box, "EQUIPMENT")
	for slot in Rules.engine.config.equipment_slots:
		gear.add_child(_equipment_row(sheet, slot))


## One slot: a dropdown showing what is worn, with the bag's items for that slot, and
## an option to take it off.
func _equipment_row(sheet: CharacterSheet, slot: StringName) -> Control:
	var row := HBoxContainer.new()
	var caption := MenuStyle.label(String(slot).capitalize(), &"DimLabel", false)
	caption.custom_minimum_size = Vector2(100.0, 0.0)
	row.add_child(caption)
	var current: ItemDef = sheet.equipment.get(slot)
	var choices := OptionButton.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_item(_item_name(current) if current != null else "(empty)")
	choices.set_item_metadata(0, {"kind": "keep"})
	if current != null:
		choices.add_item("Take off")
		choices.set_item_metadata(choices.item_count - 1, {"kind": "unequip", "slot": slot})
	for item in _roster.inventory.items():
		if item.slot == slot:
			choices.add_item("%s  (x%d)" % [_item_name(item), _roster.inventory.count(item)])
			choices.set_item_metadata(choices.item_count - 1, {"kind": "equip", "item": item})
	var block := _roster.get_block(sheet.id)
	if slot != &"weapon" and block != null and block.allows_secondary_weapon():
		for item in _roster.inventory.items():
			if item.slot == &"weapon" and item.damage_dice != "":
				choices.add_item("%s  (secondary)" % _item_name(item))
				choices.set_item_metadata(choices.item_count - 1,
						{"kind": "equip_secondary", "item": item, "slot": slot})
	choices.item_selected.connect(_on_equipment_chosen.bind(choices))
	row.add_child(choices)
	return row


# -------------------------------------------------------- action details

## A clickable ability line; clicking it opens its full details (cost, roll, reach,
## targets and every effect) directly underneath. Hovering shows the same text.
func _add_action_entry(into: Container, action: ActionDef) -> void:
	var shown := _shown_action == action
	var btn := MenuStyle.list_button("%s %s   [%s]" % [
			"v" if shown else ">", ActionInfo.title(action), ActionInfo.summary(action)], shown)
	btn.tooltip_text = ActionInfo.details(action)
	btn.pressed.connect(_toggle_action.bind(action))
	into.add_child(btn)
	if shown:
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 18)
		pad.add_child(MenuStyle.label(ActionInfo.details(action), &"DimLabel"))
		into.add_child(pad)


func _toggle_action(action: ActionDef) -> void:
	_shown_action = null if _shown_action == action else action
	_refresh()


# --------------------------------------------------------------- inventory

func _refresh_inventory() -> void:
	_clear(_inventory_box)
	_clear(_inventory_detail)
	var bag := _roster.inventory
	_inventory_box.add_child(MenuStyle.heading("BAG  (%d item%s)" % [bag.total(), "" if bag.total() == 1 else "s"]))
	if bag.is_empty():
		_inventory_box.add_child(MenuStyle.label("Nothing in the bag.", &"DimLabel"))
		_inventory_detail.add_child(MenuStyle.label("Select an item to see its details.", &"DimLabel"))
		_shown_item = null
		return
	if _shown_item == null or bag.count(_shown_item) <= 0:
		_shown_item = bag.items()[0]
	var last_slot: StringName = &""
	for item in bag.items():
		if item.slot != last_slot:
			last_slot = item.slot
			_inventory_box.add_child(MenuStyle.label(String(item.slot).to_upper(), &"DimLabel", false))
		var pick := MenuStyle.list_button("%s  (x%d)" % [_item_name(item), bag.count(item)], item == _shown_item)
		pick.pressed.connect(_show_item.bind(item))
		_inventory_box.add_child(pick)

	_inventory_detail.add_child(MenuStyle.label(_item_name(_shown_item).to_upper(), &"TitleLabel"))
	MenuStyle.pair(_inventory_detail, "Slot", String(_shown_item.slot).capitalize(), &"", 80.0)
	MenuStyle.pair(_inventory_detail, "In bag", str(bag.count(_shown_item)), &"", 80.0)
	if _shown_item.description != "":
		_inventory_detail.add_child(MenuStyle.label(_shown_item.description))
	if _shown_item.damage_dice != "":
		var cfg: RulesConfig = Rules.engine.config
		var attack := _shown_item.attack_stat if _shown_item.attack_stat != &"" else cfg.default_attack_stat
		var dmg := _shown_item.damage_stat if _shown_item.damage_stat != &"" else cfg.default_damage_stat
		_inventory_detail.add_child(HSeparator.new())
		_inventory_detail.add_child(MenuStyle.heading("WEAPON"))
		MenuStyle.pair(_inventory_detail, "Damage", "%s %s  (+%s)" % [
				_shown_item.damage_dice, _shown_item.damage_type, String(dmg).capitalize()], &"", 80.0)
		MenuStyle.pair(_inventory_detail, "Attacks with", String(attack).capitalize(), &"", 80.0)
		if _shown_item.weapon_range > 0.0:
			MenuStyle.pair(_inventory_detail, "Reach", "%s m" % snappedf(_shown_item.weapon_range, 0.1), &"", 80.0)
		if not _shown_item.weapon_tags.is_empty():
			MenuStyle.pair(_inventory_detail, "Tags", ", ".join(_shown_item.weapon_tags), &"", 80.0)
	if not _shown_item.modifiers.is_empty():
		_inventory_detail.add_child(HSeparator.new())
		_inventory_detail.add_child(MenuStyle.heading("WHILE EQUIPPED"))
		for stat in _shown_item.modifiers:
			MenuStyle.pair(_inventory_detail, String(stat).capitalize(),
					"%+d" % int(_shown_item.modifiers[stat]), &"", 80.0)
	if not _shown_item.granted_actions.is_empty():
		_inventory_detail.add_child(HSeparator.new())
		_inventory_detail.add_child(MenuStyle.heading("GRANTS"))
		for action in _shown_item.granted_actions:
			if action != null:
				_add_action_entry(_inventory_detail, action)
	var who := _roster.get_sheet(_selected)
	if who != null:
		_inventory_detail.add_child(HSeparator.new())
		var equip := Button.new()
		equip.text = "Equip on %s" % _name_of(who)
		equip.pressed.connect(_equip_shown_item)
		_inventory_detail.add_child(equip)


func _show_item(item: ItemDef) -> void:
	_shown_item = item
	_refresh()


func _equip_shown_item() -> void:
	if _shown_item != null:
		_roster.equip_from_inventory(_selected, _shown_item)
	_refresh.call_deferred()


# --------------------------------------------------------------------- map

## The cards beside the map. The map itself (MapView) redraws on its own.
func _refresh_map() -> void:
	_clear(_map_box)
	var day := GameController.day_cycle
	if day == null:
		var empty := MenuStyle.card(_map_box, "MAP")
		empty.add_child(MenuStyle.label("No expedition has been planned yet.", &"DimLabel"))
		return
	var room := MapView.find_room(get_tree())
	var inside := room != null and day.phase == DayCycle.Phase.EXPEDITION

	var where := MenuStyle.card(_map_box, "LOCATION")
	MenuStyle.pair(where, "Day", "%d  -  %s" % [day.day, String(DayCycle.Phase.keys()[day.phase]).capitalize()], &"", 100.0)
	if inside:
		var tile := day.tile_at(room.cell, TileDef.Clef.BASS)
		MenuStyle.pair(where, "Room", _tile_title(tile), &"", 100.0)
		MenuStyle.pair(where, "Cell", "(%d, %d)" % [room.cell.x, room.cell.y], &"", 100.0)
		var ways: Array[String] = []
		for side in day.open_sides(room.cell):
			ways.append(String(DayCycle.Side.keys()[side]).capitalize())
		MenuStyle.pair(where, "Doors", ", ".join(ways) if not ways.is_empty() else "none", &"", 100.0)
		var here := _remnants_at(day, room.cell)
		MenuStyle.pair(where, "Remnants", str(here), &"AlertLabel" if here > 0 else &"", 100.0)
	else:
		MenuStyle.pair(where, "Place", "Town" if day.phase == DayCycle.Phase.PLAN else "Not in a room", &"", 100.0)

	var resources := MenuStyle.card(_map_box, "RESOURCES")
	MenuStyle.pair(resources, "Stock", _amounts(day.stock), &"", 100.0)
	MenuStyle.pair(resources, "Carried loot", _amounts(day.carried_loot), &"", 100.0)
	MenuStyle.pair(resources, "Tithe tonight", str(day.tithe_tonight()), &"", 100.0)
	MenuStyle.pair(resources, "Debt", str(day.debt), &"AlertLabel" if day.debt > 0 else &"", 100.0)
	var counts := {}
	for def in day.blueprints:
		counts[def.display_name] = int(counts.get(def.display_name, 0)) + 1
	MenuStyle.pair(resources, "Blueprints", _amounts(counts), &"", 100.0)

	var dungeon := MenuStyle.card(_map_box, "DUNGEON")
	if day.has_segno():
		var info := day.main_path()
		MenuStyle.pair(dungeon, "Segno", "(%d, %d)" % [day.segno.x, day.segno.y], &"", 100.0)
		MenuStyle.pair(dungeon, "Main path", "%d steps, %d loops" % [int(info["steps"]), int(info["loops"])], &"", 100.0)
	else:
		MenuStyle.pair(dungeon, "Segno", "not placed", &"", 100.0)
	MenuStyle.pair(dungeon, "Rooms", str(day.bass.size()), &"", 100.0)
	MenuStyle.pair(dungeon, "Remnants left", str(day.remaining()), &"", 100.0)


func _amounts(amounts: Dictionary) -> String:
	if amounts.is_empty():
		return "-"
	var parts: Array[String] = []
	for key in amounts:
		parts.append("%s %d" % [key, int(amounts[key])])
	return ", ".join(parts)


func _tile_title(tile: TileInstance) -> String:
	if tile == null or tile.def == null:
		return "Room"
	return tile.def.display_name if tile.def.display_name != "" else String(tile.def.id)


func _remnants_at(day: DayCycle, cell: Vector2i) -> int:
	var count := 0
	for s: Dictionary in day.spawns:
		if bool(s["alive"]) and s["pos"] == cell:
			count += 1
	return count


# ----------------------------------------------------------------- actions

func _select(char_id: StringName) -> void:
	_selected = char_id
	_refresh()


func _on_bring(char_id: StringName) -> void:
	if party_editable():
		_roster.toggle_companion(char_id)  # emits changed, which refreshes


## Switches automatic picking for a character. If they have a level waiting, it is spent
## now; whatever can't be settled from the recommendations stays for the Level up button.
func _on_auto_pick_toggled(on: bool, char_id: StringName) -> void:
	var sheet := _roster.get_sheet(char_id)
	if sheet == null:
		return
	sheet.auto_pick_recommended = on
	if on and Leveling.can_level_up(sheet):
		Leveling.auto_resolve(_roster, Leveling.build_offer(_roster, char_id))
	_refresh()


## Opens the level-up screen above the menu. Leveling.apply() emits roster.changed, which
## refreshes the menu; this just keeps TAB and Close from pulling the menu out from under it.
func _on_level_up(char_id: StringName) -> void:
	if _leveling or _roster == null:
		return
	var offer := Leveling.build_offer(_roster, char_id)
	if offer == null:
		return
	_leveling = true
	var screen := LevelUpScreen.new()
	add_child(screen)
	screen.open(offer)
	screen.layer = layer + 1  # open() puts it at 30, behind this menu
	UISounds.play("menu_open")
	await screen.finished
	_leveling = false
	_refresh()


func _on_equipment_chosen(index: int, choices: OptionButton) -> void:
	var choice: Dictionary = choices.get_item_metadata(index)
	match String(choice.get("kind", "keep")):
		"unequip":
			_roster.unequip_to_inventory(_selected, choice["slot"])
		"equip":
			_roster.equip_from_inventory(_selected, choice["item"])
		"equip_secondary":
			_roster.equip_secondary_from_inventory(_selected, choice["item"], choice["slot"])
	_refresh.call_deferred()


# ----------------------------------------------------------------- helpers

func _name_of(sheet: CharacterSheet) -> String:
	return sheet.display_name if sheet.display_name != "" else String(sheet.id)


## "Level 3    XP 140 / 200", "... XP 480 (max level)", or just the level for Kendall,
## who earns no XP.
func _level_line(sheet: CharacterSheet, block: StatBlock) -> String:
	if sheet.is_player:
		return "Level %d    (earns no XP)" % block.level
	var line := "Level %d    XP %d" % [block.level, sheet.xp]
	var prog := sheet.progression
	if prog == null:
		return line
	var need := prog.xp_for_level(sheet.level + 1)
	if sheet.level >= prog.max_level or need < 0:
		return line + "  (max level)"
	return "%s / %d" % [line, need]


func _item_name(item: ItemDef) -> String:
	return item.display_name if item.display_name != "" else String(item.id)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
