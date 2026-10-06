class_name PartyRoster
extends RefCounted
## Everyone recruited, and which of them are in the active party.
## Not tied to any scene: the exploration and combat code will read from this.

signal changed

var engine: RulesEngine
## character id -> CharacterSheet
var sheets: Dictionary = {}
## character id -> StatBlock
var blocks: Dictionary = {}
## Active party, in order. At most RulesConfig.party_size.
var active: Array[StringName] = []


func _init(p_engine: RulesEngine) -> void:
	engine = p_engine


## Builds a StatBlock from the sheet and adds the character to the roster.
## They join the active party if there is room and `make_active` is true.
func recruit(sheet: CharacterSheet, make_active: bool = true) -> StatBlock:
	var block := sheet.build_block(engine)
	sheets[sheet.id] = sheet
	blocks[sheet.id] = block
	if make_active and not active.has(sheet.id) and active.size() < engine.config.party_size:
		active.append(sheet.id)
	changed.emit()
	return block


func dismiss(char_id: StringName) -> void:
	sheets.erase(char_id)
	blocks.erase(char_id)
	active.erase(char_id)
	changed.emit()


func get_block(char_id: StringName) -> StatBlock:
	return blocks.get(char_id) as StatBlock


func get_sheet(char_id: StringName) -> CharacterSheet:
	return sheets.get(char_id) as CharacterSheet


func is_active(char_id: StringName) -> bool:
	return active.has(char_id)


func active_blocks() -> Array[StatBlock]:
	var out: Array[StatBlock] = []
	for char_id in active:
		out.append(blocks[char_id])
	return out


## Replaces the active party. Returns false (and changes nothing) if an id is
## unknown, repeated, or there are more than RulesConfig.party_size.
func set_active(ids: Array) -> bool:
	if ids.size() > engine.config.party_size:
		return false
	var seen: Array[StringName] = []
	for char_id in ids:
		var key := StringName(char_id)
		if not blocks.has(key) or seen.has(key):
			return false
		seen.append(key)
	active = seen
	changed.emit()
	return true


## Equips an item in its slot. Returns the item it replaced, or null.
func equip(char_id: StringName, item: ItemDef) -> ItemDef:
	var sheet := get_sheet(char_id)
	if sheet == null or not engine.config.equipment_slots.has(item.slot):
		return null
	var previous: ItemDef = sheet.equipment.get(item.slot)
	sheet.equipment[item.slot] = item
	blocks[char_id].apply_equipment(sheet.equipment)
	changed.emit()
	return previous


## Removes whatever is in `slot`. Returns the removed item, or null.
func unequip(char_id: StringName, slot: StringName) -> ItemDef:
	var sheet := get_sheet(char_id)
	if sheet == null or not sheet.equipment.has(slot):
		return null
	var removed: ItemDef = sheet.equipment[slot]
	sheet.equipment.erase(slot)
	blocks[char_id].apply_equipment(sheet.equipment)
	changed.emit()
	return removed


## Writes runtime state (Corpus, Anima, level) back to the sheets, ready to save.
func sync_to_sheets() -> void:
	for char_id in blocks:
		sheets[char_id].sync_from(blocks[char_id])


## Full rest: refills Corpus and Anima Portions and clears conditions for everyone.
func rest_all() -> void:
	for char_id in blocks:
		var block: StatBlock = blocks[char_id]
		block.conditions.clear()
		block.refill()
	changed.emit()
