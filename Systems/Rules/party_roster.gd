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
## The shared bag. Items worn by a character are not in it.
var inventory := PartyInventory.new()


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


# ------------------------------------------------------- choosing a party

## The player character: the sheet that sets is_player, else whoever is first in the
## roster. Always leads the active party and can't be left behind.
func leader_id() -> StringName:
	for char_id in sheets:
		if (sheets[char_id] as CharacterSheet).is_player:
			return char_id
	if not active.is_empty():
		return active[0]
	for char_id in sheets:
		return char_id
	return &""


## Everyone recruited except the leader, in the order they joined.
func companion_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var lead := leader_id()
	for char_id in sheets:
		if char_id != lead:
			out.append(char_id)
	return out


## How many companions go on an expedition: the party size minus the leader.
func companion_slots() -> int:
	return maxi(engine.config.party_size - 1, 0)


## The companions currently in the active party, in party order.
func active_companions() -> Array[StringName]:
	var out: Array[StringName] = []
	var lead := leader_id()
	for char_id in active:
		if char_id != lead:
			out.append(char_id)
	return out


## True once the party is as full as the roster allows: every companion slot is taken,
## or there are no spare companions left to take.
func party_ready() -> bool:
	if sheets.is_empty() or not active.has(leader_id()):
		return false
	return active_companions().size() >= mini(companion_slots(), companion_ids().size())


## Sets the companions who go (the leader is always added in front). Returns false
## and changes nothing for an unknown or repeated id, the leader, or too many.
func set_companions(ids: Array) -> bool:
	var lead := leader_id()
	if lead == &"" or ids.size() > companion_slots():
		return false
	var party: Array = [lead]
	for char_id in ids:
		var key := StringName(char_id)
		if key == lead or party.has(key):
			return false
		party.append(key)
	return set_active(party)


## Takes `char_id` along, or leaves them behind if they are already going. With every
## slot full, bringing someone new bumps the companion who has been in the party
## longest. Returns false for the leader or an unknown id.
func toggle_companion(char_id: StringName) -> bool:
	if char_id == leader_id() or not blocks.has(char_id):
		return false
	var going := active_companions()
	if going.has(char_id):
		going.erase(char_id)
	else:
		if going.size() >= companion_slots():
			if going.is_empty():
				return false
			going.pop_front()
		going.append(char_id)
	return set_companions(going)


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


## Equips an item from the shared bag. Whatever it replaces goes back into the bag.
## Returns false (and changes nothing) if the bag doesn't hold it or the slot is unknown.
func equip_from_inventory(char_id: StringName, item: ItemDef) -> bool:
	var sheet := get_sheet(char_id)
	if sheet == null or item == null or not inventory.has(item) \
			or not engine.config.equipment_slots.has(item.slot):
		return false
	inventory.remove(item)
	var previous := equip(char_id, item)
	if previous != null:
		inventory.add(previous)
	return true


## Takes whatever is in `slot` off and puts it in the shared bag.
func unequip_to_inventory(char_id: StringName, slot: StringName) -> bool:
	var removed := unequip(char_id, slot)
	if removed == null:
		return false
	inventory.add(removed)
	return true


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
