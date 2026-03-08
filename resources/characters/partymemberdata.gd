extends Resource
class_name PartyMemberData

signal will_changed

@export var character : CharacterData

var current_hp : int
var bonus_attack : int = 0
var bonus_max_hp : int = 0
var temporary_traits : Array
var equipment : Dictionary # slot_name -> ItemInstance
var status_effects : Array

# Will resource — only meaningful for supporting characters.
# Player character leaves this at 0/0 by design.
var will : int = 0
var max_will : int = 0

func init_from_character(char_data: CharacterData) -> void:
	character = char_data
	current_hp = char_data.base_max_hp
	max_will = char_data.base_max_will
	will = max_will

func has_will() -> bool:
	return max_will > 0

func spend_will(amount: int) -> bool:
	if will < amount:
		return false
	will -= amount
	will_changed.emit()
	return true

func restore_will(amount: int) -> void:
	will = min(will + amount, max_will)
	will_changed.emit()
