extends Resource
class_name LevelTable
# Defines EXP thresholds and what each level-up grants per character.
# Level 1 = starting state (no exp needed).
# Level 2+ require accumulated exp.
#
# Each entry in LEVELS: { "exp": int, "stat": String, "amount": int, "unlock": String }
# "stat"   — "hp", "atk", "will", "tempo", or ""
# "amount" — flat bonus added to PartyMemberData bonus fields
# "unlock" — skill key string unlocked at this level, or ""
#
# Character identity is matched by CharacterData.display_name (lowercase).

const MAX_LEVEL := 5

# exp required to reach each level (index = level, index 0 unused)
const EXP_THRESHOLDS := [0, 0, 10, 25, 45, 70]

# Per-character level rewards.
# Key: display_name.to_lower()
# Value: Array of 5 dicts (index = level 1..5; index 0 unused, so size 6)
const LEVEL_REWARDS : Dictionary = {
	"kendall": [
		{},  # level 1 placeholder
		{"stat": "", "amount": 0, "unlock": ""},
		{"stat": "atk", "amount": 1, "unlock": "Augur"},            # level 1 base
		{"stat": "hp", "amount": 3, "unlock": ""},         # level 2
		{"stat": "atk",  "amount": 1, "unlock": "Change Lens"},  # level 3
		{"stat": "tempo", "amount": 2, "unlock": ""},         # level 4
		{"stat": "hp", "amount": 4, "unlock": ""},  # level 5
		{"stat": "atk", "amount": 2, "unlock": ""},  # level 6
		{"stat": "tempo", "amount": 4, "unlock": ""},
		{"stat": "atk", "amount": 3, "unlock": ""},
	],
	"hue": [
		{},
		{"stat": "",   "amount": 0, "unlock": ""},
		{"stat": "will", "amount": 3, "unlock": "Shelter"},
		{"stat": "hp",   "amount": 4, "unlock": ""},
		{"stat": "will", "amount": 5, "unlock": "Calcify"},
		{"stat": "hp",   "amount": 5, "unlock": ""},
		{"stat": "atk",  "amount": 2, "unlock": ""},
		{"stat": "tempo", "amount": 2, "unlock": ""},
	],
	"indra": [
		{},
		{"stat": "", "amount": 0, "unlock": ""},
		{"stat": "hp",  "amount": 3, "unlock": "Galvanize"},
		{"stat": "atk",   "amount": 1, "unlock": ""},
		{"stat": "will",  "amount": 4, "unlock": "Fulminate"},
		{"stat": "tempo", "amount": 2, "unlock": ""},
		{"stat": "hp",  "amount": 4, "unlock": ""},
		{"stat": "atk",   "amount": 2, "unlock": ""},
	],
	"vritra": [
		{},
		{"stat": "", "amount": 0, "unlock": ""},
		{"stat": "hp",   "amount": 2, "unlock": "Wither"},
		{"stat": "atk",  "amount": 1, "unlock": ""},
		{"stat": "will", "amount": 2, "unlock": "Devour"},
		{"stat": "atk",   "amount": 1, "unlock": ""},
		{"stat": "tempo",   "amount": 3, "unlock": ""},
		{"stat": "atk",  "amount": 3, "unlock": ""},
	],
}


static func get_rewards_for(display_name: String) -> Array:
	return LEVEL_REWARDS.get(display_name.to_lower(), [])


static func exp_to_next_level(current_level: int) -> int:
	if current_level >= MAX_LEVEL:
		return -1  # maxed
	return EXP_THRESHOLDS[current_level + 1]


static func exp_needed_for_level(target_level: int) -> int:
	if target_level <= 0 or target_level >= EXP_THRESHOLDS.size():
		return 0
	return EXP_THRESHOLDS[target_level]
