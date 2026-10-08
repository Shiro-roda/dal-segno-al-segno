class_name PartyMenu
extends CanvasLayer
## Party menu (TAB). Shows everyone recruited, who is going on the next expedition, and
## the selected character's stats and equipment.
##
##   - The leader (the player character) always goes. Pick which companions come with
##     "Bring" / "Leave"; with every slot full, bringing someone new replaces whoever has
##     been in the party longest. The party can only change while planning in town.
##   - Equipment comes from, and returns to, the party's shared bag (any time the menu
##     can be opened).
##
## GameController adds one of these at startup. Open it with TAB, or call show_menu() (the
## plan screen has a button for it). It joins the group "party_menu".

signal menu_opened
signal menu_closed

var _open := false
var _leveling := false  # a LevelUpScreen is up on top of the menu
var _selected: StringName = &""
var _roster: PartyRoster
var _link: PlayerLink

var _root: Control
var _hint: Label
var _roster_box: VBoxContainer
var _party_box: VBoxContainer
var _detail_box: VBoxContainer


func _ready() -> void:
	# GameRoot's WorldLayer is 201 and fills the screen; stay above it, but below the
	# system menu (229-230) so ESC still goes on top.
	layer = 220
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("party_menu")
	_build()
	_root.visible = false


func _exit_tree() -> void:
	_leveling = false
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
	var colors := ThemeManager.palette
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
		margin.add_theme_constant_override("margin_" + edge, 24)
	_root.add_child(margin)

	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	var base: Color = colors.get("bg", Color.BLACK)
	box.bg_color = Color(base.r, base.g, base.b, 0.97)
	box.border_color = colors.get("dim", Color.WHITE)
	box.set_border_width_all(2)
	box.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", box)
	margin.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)

	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := Label.new()
	title.text = "PARTY"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "Close (TAB)"
	close.pressed.connect(close_menu)
	header.add_child(close)

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_hint)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	outer.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	left.add_child(_heading("ROSTER"))
	var roster_scroll := ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(roster_scroll)
	_roster_box = VBoxContainer.new()
	_roster_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(_roster_box)
	left.add_child(_heading("NEXT EXPEDITION"))
	_party_box = VBoxContainer.new()
	left.add_child(_party_box)

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right_scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 6)
	right_scroll.add_child(_detail_box)


# ----------------------------------------------------------------- refresh

func _refresh() -> void:
	if not _open or _roster == null:
		return
	var editable := party_editable()
	_refresh_hint(editable)
	_refresh_roster(editable)
	_refresh_party()
	_refresh_detail()


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
		var tag := ""
		if char_id == lead:
			tag = "LEADER"
		elif going.has(char_id):
			tag = "GOING"
		if Leveling.can_level_up(sheet):
			tag = (tag + "  LEVEL UP").strip_edges()
		var pick := Button.new()
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.text = "%s %s   Lv %d   %s" % [
				">" if char_id == _selected else " ", _name_of(sheet), block.level, tag]
		pick.pressed.connect(_select.bind(char_id))
		row.add_child(pick)
		if char_id != lead:
			var bring := Button.new()
			bring.text = "Leave" if going.has(char_id) else "Bring"
			bring.disabled = not editable
			bring.pressed.connect(_on_bring.bind(char_id))
			row.add_child(bring)


func _refresh_party() -> void:
	_clear(_party_box)
	_party_box.add_child(_slot_label("Leader", _roster.leader_id()))
	var going := _roster.active_companions()
	for i in _roster.companion_slots():
		var char_id: StringName = going[i] if i < going.size() else &""
		_party_box.add_child(_slot_label("Companion %d" % (i + 1), char_id))


func _refresh_detail() -> void:
	_clear(_detail_box)
	var sheet := _roster.get_sheet(_selected)
	var block := _roster.get_block(_selected)
	if sheet == null or block == null:
		return
	_detail_box.add_child(_heading(_name_of(sheet).to_upper()))
	_detail_box.add_child(_text(_level_line(sheet, block)))
	if not sheet.is_player and Leveling.has_recommendations(sheet):
		var auto_pick := CheckBox.new()
		auto_pick.text = "Pick recommended level-ups automatically"
		auto_pick.button_pressed = sheet.auto_pick_recommended
		auto_pick.disabled = _leveling
		auto_pick.toggled.connect(_on_auto_pick_toggled.bind(_selected))
		_detail_box.add_child(auto_pick)
	if Leveling.can_level_up(sheet):
		var level_up := Button.new()
		level_up.text = "Level up to %d" % (sheet.level + 1)
		level_up.disabled = _leveling
		level_up.pressed.connect(_on_level_up.bind(_selected))
		_detail_box.add_child(level_up)
	_detail_box.add_child(_text("Corpus %d / %d    Anima %d / %d    Defense %d" % [
			block.corpus, block.max_corpus(), block.anima, block.max_anima(), block.defense()]))

	_detail_box.add_child(_heading("ATTRIBUTES"))
	for def in Rules.engine.stats_in_category(StatDef.Category.ATTRIBUTE):
		var label := def.display_name if def.display_name != "" else String(def.id)
		_detail_box.add_child(_text("%s  %d  (%+d)" % [label, block.score(def.id), block.total_mod(def.id)]))

	if not sheet.feats.is_empty():
		_detail_box.add_child(_heading("FEATS"))
		for feat in sheet.feats:
			if feat != null:
				var feat_label := _text(feat.display_name if feat.display_name != "" else String(feat.id))
				feat_label.tooltip_text = feat.description
				feat_label.mouse_filter = Control.MOUSE_FILTER_PASS
				_detail_box.add_child(feat_label)

	if not sheet.known_actions.is_empty():
		_detail_box.add_child(_heading("ABILITIES"))
		for action in sheet.known_actions:
			if action != null:
				_detail_box.add_child(_text(action.display_name if action.display_name != "" else String(action.id)))

	_detail_box.add_child(_heading("EQUIPMENT"))
	for slot in Rules.engine.config.equipment_slots:
		_detail_box.add_child(_equipment_row(sheet, slot))


## One slot: a dropdown showing what is worn, with the bag's items for that slot, and
## an option to take it off.
func _equipment_row(sheet: CharacterSheet, slot: StringName) -> Control:
	var row := HBoxContainer.new()
	var caption := Label.new()
	caption.text = String(slot).capitalize()
	caption.custom_minimum_size = Vector2(110, 0)
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
	choices.item_selected.connect(_on_equipment_chosen.bind(choices))
	row.add_child(choices)
	return row


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
	_refresh.call_deferred()


# ----------------------------------------------------------------- helpers

func _slot_label(slot_text: String, char_id: StringName) -> Label:
	var sheet := _roster.get_sheet(char_id) if char_id != &"" else null
	return _text("%s: %s" % [slot_text, _name_of(sheet) if sheet != null else "(empty)"])


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


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", ThemeManager.palette.get("secondary", Color.WHITE))
	return label


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
