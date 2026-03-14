extends Resource
class_name LevelTable
# Defines EXP thresholds and what each level-up grants per character.

const MAX_LEVEL := 15

const EXP_THRESHOLDS := [0, 0, 10, 30, 58, 92, 131, 176, 225, 279, 336, 398, 464, 533, 606, 682]

const LEVEL_REWARDS : Dictionary = {
	"kendall": [
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 0 placeholder
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 1 placeholder
		[{"stat": "atk", "amount": 1, "unlock": ""}, {"stat": "tempo", "amount": 1, "unlock": ""}],  # level 2
		[{"stat": "hp", "amount": 1, "unlock": "Change Lens"}],  # level 3
		[{"stat": "tempo", "amount": 1, "unlock": ""}],  # level 4
		[{"stat": "atk", "amount": 2, "unlock": ""}, {"stat": "tempo", "amount": 2, "unlock": ""}],  # level 5
		[{"stat": "hp", "amount": 2, "unlock": ""}],  # level 6
		[{"stat": "tempo", "amount": 2, "unlock": ""}],  # level 7
		[{"stat": "atk", "amount": 2, "unlock": ""}, {"stat": "tempo", "amount": 2, "unlock": ""}],  # level 8
		[{"stat": "hp", "amount": 2, "unlock": ""}],  # level 9
		[{"stat": "tempo", "amount": 2, "unlock": ""}],  # level 10
		[{"stat": "atk", "amount": 3, "unlock": ""}, {"stat": "tempo", "amount": 2, "unlock": ""}],  # level 11
		[{"stat": "hp", "amount": 2, "unlock": ""}],  # level 12
		[{"stat": "tempo", "amount": 3, "unlock": ""}],  # level 13
		[{"stat": "atk", "amount": 3, "unlock": ""}, {"stat": "tempo", "amount": 3, "unlock": ""}],  # level 14
		[{"stat": "hp", "amount": 3, "unlock": ""}],  # level 15
	],
	"hue": [
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 0 placeholder
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 1 placeholder
		[{"stat": "will", "amount": 2, "unlock": "Shelter"}, {"stat": "tempo", "amount": 1, "unlock": ""}],  # level 2
		[{"stat": "hp", "amount": 2, "unlock": ""}],  # level 3
		[{"stat": "atk", "amount": 1, "unlock": "Calcify"}, {"stat": "will", "amount": 2, "unlock": ""}],  # level 4
		[{"stat": "tempo", "amount": 1, "unlock": ""}],  # level 5
		[{"stat": "hp", "amount": 2, "unlock": ""}, {"stat": "will", "amount": 2, "unlock": ""}],  # level 6
		[{"stat": "atk", "amount": 1, "unlock": ""}],  # level 7
		[{"stat": "will", "amount": 3, "unlock": ""}, {"stat": "tempo", "amount": 1, "unlock": ""}],  # level 8
		[{"stat": "hp", "amount": 2, "unlock": ""}],  # level 9
		[{"stat": "atk", "amount": 1, "unlock": ""}, {"stat": "will", "amount": 3, "unlock": ""}],  # level 10
		[{"stat": "tempo", "amount": 2, "unlock": ""}],  # level 11
		[{"stat": "hp", "amount": 3, "unlock": ""}, {"stat": "will", "amount": 3, "unlock": ""}],  # level 12
		[{"stat": "atk", "amount": 1, "unlock": ""}],  # level 13
		[{"stat": "will", "amount": 4, "unlock": ""}, {"stat": "tempo", "amount": 2, "unlock": ""}],  # level 14
		[{"stat": "hp", "amount": 3, "unlock": ""}],  # level 15
	],
	"indra": [
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 0 placeholder
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 1 placeholder
		[{"stat": "atk", "amount": 1, "unlock": "Galvanize"}],  # level 2
		[{"stat": "hp", "amount": 2, "unlock": ""}, {"stat": "will", "amount": 2, "unlock": ""}],  # level 3
		[{"stat": "tempo", "amount": 2, "unlock": "Fulminate"}],  # level 4
		[{"stat": "hp", "amount": 2, "unlock": ""}, {"stat": "atk", "amount": 1, "unlock": ""}],  # level 5
		[{"stat": "will", "amount": 3, "unlock": ""}],  # level 6
		[{"stat": "hp", "amount": 3, "unlock": ""}, {"stat": "tempo", "amount": 2, "unlock": ""}],  # level 7
		[{"stat": "atk", "amount": 1, "unlock": ""}],  # level 8
		[{"stat": "hp", "amount": 3, "unlock": ""}, {"stat": "will", "amount": 3, "unlock": ""}],  # level 9
		[{"stat": "tempo", "amount": 2, "unlock": ""}],  # level 10
		[{"stat": "hp", "amount": 3, "unlock": ""}, {"stat": "atk", "amount": 2, "unlock": ""}],  # level 11
		[{"stat": "will", "amount": 3, "unlock": ""}],  # level 12
		[{"stat": "hp", "amount": 3, "unlock": ""}, {"stat": "tempo", "amount": 2, "unlock": ""}],  # level 13
		[{"stat": "atk", "amount": 2, "unlock": ""}],  # level 14
		[{"stat": "hp", "amount": 3, "unlock": ""}, {"stat": "will", "amount": 4, "unlock": ""}],  # level 15
	],
	"vritra": [
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 0 placeholder
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 1 placeholder
		[{"stat": "tempo", "amount": 1, "unlock": "Vice"}],  # level 2
		[{"stat": "atk", "amount": 1, "unlock": ""}, {"stat": "will", "amount": 2, "unlock": ""}],  # level 3
		[{"stat": "hp", "amount": 2, "unlock": ""}],  # level 4
		[{"stat": "atk", "amount": 1, "unlock": "Devour"}, {"stat": "tempo", "amount": 1, "unlock": ""}],  # level 5
		[{"stat": "will", "amount": 2, "unlock": ""}],  # level 6
		[{"stat": "hp", "amount": 2, "unlock": ""}, {"stat": "atk", "amount": 1, "unlock": ""}],  # level 7
		[{"stat": "tempo", "amount": 2, "unlock": ""}],  # level 8
		[{"stat": "atk", "amount": 1, "unlock": ""}, {"stat": "will", "amount": 2, "unlock": ""}],  # level 9
		[{"stat": "hp", "amount": 3, "unlock": ""}],  # level 10
		[{"stat": "atk", "amount": 1, "unlock": ""}, {"stat": "tempo", "amount": 2, "unlock": ""}],  # level 11
		[{"stat": "will", "amount": 2, "unlock": ""}],  # level 12
		[{"stat": "hp", "amount": 3, "unlock": ""}, {"stat": "atk", "amount": 2, "unlock": ""}],  # level 13
		[{"stat": "tempo", "amount": 3, "unlock": ""}],  # level 14
		[{"stat": "atk", "amount": 2, "unlock": ""}, {"stat": "will", "amount": 2, "unlock": ""}],  # level 15
	]
}

static func get_rewards_for(display_name: String) -> Array:
	return LEVEL_REWARDS.get(display_name.to_lower(), [])

static func exp_to_next_level(current_level: int) -> int:
	if current_level >= MAX_LEVEL:
		return -1
	return EXP_THRESHOLDS[current_level + 1]

static func exp_needed_for_level(target_level: int) -> int:
	if target_level <= 0 or target_level >= EXP_THRESHOLDS.size():
		return 0
	return EXP_THRESHOLDS[target_level]
