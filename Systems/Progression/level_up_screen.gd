class_name LevelUpScreen
extends CanvasLayer
## Shows a LevelUpOffer: one row per pick, one button per option. Confirm applies
## the choices through Leveling.apply(). Descriptions come from your resources
## and show as tooltips; this script writes no text of its own beyond labels.
##
##   var screen := LevelUpScreen.new()
##   add_child(screen)
##   screen.open(Leveling.build_offer(Rules.roster, id))
##   await screen.finished

signal finished(char_id: StringName)

var offer: LevelUpOffer

var _sheet: CharacterSheet
var _confirm: Button
var _buttons: Array = []  # per pick: Array of {button, option}


func open(p_offer: LevelUpOffer) -> void:
	offer = p_offer
	layer = 30
	var sheet := Rules.roster.get_sheet(offer.char_id)
	_sheet = sheet
	# A character set to pick automatically arrives here only when something was left
	# open; show what could be filled from their recommendations already chosen.
	if sheet != null and sheet.auto_pick_recommended:
		Leveling.apply_recommended(offer, sheet)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)

	var title := Label.new()
	var who := sheet.display_name if sheet != null else str(offer.char_id)
	title.text = "%s: starting picks" % who if offer.is_starting \
		else "%s: level %d" % [who, offer.new_level]
	column.add_child(title)

	for i in offer.picks.size():
		var pick: Dictionary = offer.picks[i]
		var heading := Label.new()
		heading.text = str(pick["kind"]).capitalize()
		column.add_child(heading)
		var row := HBoxContainer.new()
		column.add_child(row)
		var entries: Array = []
		for option in pick["options"]:
			var b := Button.new()
			b.text = _label(option) + (" ★" if Leveling.is_recommended(sheet, option) else "")
			b.tooltip_text = _tooltip(option)
			b.focus_mode = Control.FOCUS_NONE
			b.toggle_mode = true
			b.pressed.connect(_on_option.bind(i, option))
			row.add_child(b)
			entries.append({"button": b, "option": option})
		_buttons.append(entries)

	if Leveling.has_recommendations(sheet):
		var recommended := Button.new()
		recommended.text = "Use recommended"
		recommended.tooltip_text = "Fill every pick with this character's recommended choice (marked with a star) where one is on offer."
		recommended.focus_mode = Control.FOCUS_NONE
		recommended.pressed.connect(_on_use_recommended)
		column.add_child(recommended)
		var auto := CheckBox.new()
		auto.text = "Pick recommended automatically from now on"
		auto.button_pressed = sheet.auto_pick_recommended
		auto.focus_mode = Control.FOCUS_NONE
		auto.toggled.connect(_on_auto_toggled)
		column.add_child(auto)

	_confirm = Button.new()
	_confirm.text = "Confirm"
	_confirm.disabled = true
	_confirm.pressed.connect(_on_confirm)
	column.add_child(_confirm)
	_refresh()


func _on_option(index: int, option: Variant) -> void:
	offer.choose(index, option)
	_refresh()


func _on_use_recommended() -> void:
	Leveling.apply_recommended(offer, _sheet, true)
	_refresh()


func _on_auto_toggled(on: bool) -> void:
	if _sheet != null:
		_sheet.auto_pick_recommended = on


func _refresh() -> void:
	for i in _buttons.size():
		for entry: Dictionary in _buttons[i]:
			(entry["button"] as Button).set_pressed_no_signal(offer.picks[i]["chosen"] == entry["option"])
	_confirm.disabled = not offer.is_complete()


func _on_confirm() -> void:
	if Leveling.apply(offer, Rules.roster):
		finished.emit(offer.char_id)
		queue_free()


func _label(option: Variant) -> String:
	if option is FeatDef:
		return (option as FeatDef).display_name
	if option is ActionDef:
		var action := option as ActionDef
		if action.is_canto():
			return "%s L%d" % [action.display_name, action.canto_level]
		if action.is_cantrip():
			return "%s (Cantrip)" % action.display_name
		return action.display_name
	var def := Rules.engine.get_stat(StringName(option))
	return def.display_name if def != null else str(option)


func _tooltip(option: Variant) -> String:
	if option is FeatDef:
		return (option as FeatDef).description
	if option is ActionDef:
		return (option as ActionDef).description
	var def := Rules.engine.get_stat(StringName(option))
	return def.description if def != null else ""
