class_name PartyInventory
extends RefCounted
## The party's shared bag of ItemDefs. Items equipped on a character are not in here;
## unequipping puts them back (see PartyRoster.equip_from_inventory / unequip_to_inventory).
## Lives on PartyRoster, so PartySetup.reset() gives every new run an empty bag.

signal changed

## ItemDef -> how many
var _counts: Dictionary = {}


func add(item: ItemDef, amount: int = 1) -> void:
	if item == null or amount <= 0:
		return
	_counts[item] = int(_counts.get(item, 0)) + amount
	changed.emit()


## Takes `amount` of `item` out. Returns false (and takes nothing) if there isn't enough.
func remove(item: ItemDef, amount: int = 1) -> bool:
	if item == null or amount <= 0 or count(item) < amount:
		return false
	var left := count(item) - amount
	if left > 0:
		_counts[item] = left
	else:
		_counts.erase(item)
	changed.emit()
	return true


func count(item: ItemDef) -> int:
	return int(_counts.get(item, 0))


func has(item: ItemDef) -> bool:
	return count(item) > 0


## Every distinct item held, grouped by slot and then by name so the list is stable.
func items() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for item: ItemDef in _counts:
		out.append(item)
	out.sort_custom(func(a: ItemDef, b: ItemDef) -> bool:
		if a.slot != b.slot:
			return String(a.slot) < String(b.slot)
		return _label(a) < _label(b))
	return out


## Number of items counting stacks.
func total() -> int:
	var n := 0
	for item: ItemDef in _counts:
		n += int(_counts[item])
	return n


func is_empty() -> bool:
	return _counts.is_empty()


func clear() -> void:
	_counts.clear()
	changed.emit()


static func _label(item: ItemDef) -> String:
	return item.display_name if item.display_name != "" else String(item.id)
