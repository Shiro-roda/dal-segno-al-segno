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

# EXP & levelling
var exp   : int = 0
var level : int = 1
var skill_unlocks : Array = []  # Array of String skill keys

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


func is_skill_unlocked(key: String) -> bool:
	return key in skill_unlocks


# Add exp and process level-ups. Returns Array of dicts describing each level gained:
# { "level": int, "stat": String, "amount": int, "unlock": String }
func add_exp(amount: int) -> Array:
	if level >= LevelTable.MAX_LEVEL:
		return []
	exp += amount
	var events : Array = []
	while level < LevelTable.MAX_LEVEL:
		var needed := LevelTable.exp_needed_for_level(level + 1)
		if exp < needed:
			break
		level += 1
		var rewards := LevelTable.get_rewards_for(character.display_name)
		var reward : Dictionary = rewards[level] if level < rewards.size() else {}
		var stat   : String = reward.get("stat",   "")
		var amt    : int    = reward.get("amount",  0)
		var unlock : String = reward.get("unlock", "")
		# Apply stat bonus
		match stat:
			"hp":    bonus_max_hp  += amt; current_hp = min(current_hp + amt, character.base_max_hp + bonus_max_hp)
			"atk":   bonus_attack  += amt
			"will":  max_will      += amt; will = min(will + amt, max_will)
			"tempo": pass  # tempo handled per-actor at battle start
		# Apply skill unlock
		if unlock != "" and unlock not in skill_unlocks:
			skill_unlocks.append(unlock)
		events.append({"level": level, "stat": stat, "amount": amt, "unlock": unlock})
	return events
