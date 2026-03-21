extends Resource
class_name LevelTable
# Defines EXP thresholds and what each level-up grants per character.

## Hard cap for static reward table. Beyond this, rewards are generated.
const MAX_LEVEL := 99
const STATIC_MAX_LEVEL := 15

const EXP_THRESHOLDS := [0, 0, 10, 30, 58, 92, 131, 176, 225, 279, 336, 398, 464, 533, 606, 682]

const LEVEL_REWARDS : Dictionary = {
	"kendall": [
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 0 placeholder
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 1 placeholder
		[{"stat": "sharp", "amount": 1, "unlock": "Augur"}, {"stat": "tempo", "amount": 1, "unlock": ""}],  # level 2
		[{"stat": "hp", "amount": 1, "unlock": ""}],  # level 3
		[{"stat": "tempo", "amount": 1, "unlock": "Unveil"}],  # level 4
		[{"stat": "sharp", "amount": 2, "unlock": ""}, {"stat": "tempo", "amount": 2, "unlock": ""}],  # level 5
		[{"stat": "hp", "amount": 2, "unlock": ""}],  # level 6
		[{"stat": "tempo", "amount": 2, "unlock": ""}],  # level 7
		[{"stat": "sharp", "amount": 2, "unlock": ""}, {"stat": "tempo", "amount": 2, "unlock": ""}],  # level 8
		[{"stat": "hp", "amount": 2, "unlock": ""}],  # level 9
		[{"stat": "tempo", "amount": 2, "unlock": ""}],  # level 10
		[{"stat": "sharp", "amount": 3, "unlock": ""}, {"stat": "tempo", "amount": 2, "unlock": ""}],  # level 11
		[{"stat": "hp", "amount": 2, "unlock": ""}],  # level 12
		[{"stat": "tempo", "amount": 3, "unlock": ""}],  # level 13
		[{"stat": "sharp", "amount": 3, "unlock": ""}, {"stat": "tempo", "amount": 3, "unlock": ""}],  # level 14
		[{"stat": "hp", "amount": 3, "unlock": ""}],  # level 15
	],
	"hue": [
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 0 placeholder
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 1 placeholder
		[{"stat": "will", "amount": 2, "unlock": "Shelter"}, {"stat": "tempo", "amount": 1, "unlock": ""}],  # level 2
		[{"stat": "hp", "amount": 2, "unlock": ""}],  # level 3
		[{"stat": "sharp", "amount": 1, "unlock": "Calcify"}, {"stat": "will", "amount": 2, "unlock": ""}],  # level 4
		[{"stat": "tempo", "amount": 1, "unlock": ""}],  # level 5
		[{"stat": "hp", "amount": 2, "unlock": ""}, {"stat": "will", "amount": 2, "unlock": ""}],  # level 6
		[{"stat": "sharp", "amount": 1, "unlock": ""}],  # level 7
		[{"stat": "will", "amount": 3, "unlock": ""}, {"stat": "tempo", "amount": 1, "unlock": ""}],  # level 8
		[{"stat": "hp", "amount": 2, "unlock": ""}],  # level 9
		[{"stat": "sharp", "amount": 1, "unlock": ""}, {"stat": "will", "amount": 3, "unlock": ""}],  # level 10
		[{"stat": "tempo", "amount": 2, "unlock": ""}],  # level 11
		[{"stat": "hp", "amount": 3, "unlock": ""}, {"stat": "will", "amount": 3, "unlock": ""}],  # level 12
		[{"stat": "sharp", "amount": 1, "unlock": ""}],  # level 13
		[{"stat": "will", "amount": 4, "unlock": ""}, {"stat": "tempo", "amount": 2, "unlock": ""}],  # level 14
		[{"stat": "hp", "amount": 3, "unlock": ""}],  # level 15
	],
	"indra": [
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 0 placeholder
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 1 placeholder
		[{"stat": "sharp", "amount": 1, "unlock": "Galvanize"}],  # level 2
		[{"stat": "flat", "amount": 1, "unlock": ""}, {"stat": "will", "amount": 2, "unlock": ""}],  # level 3
		[{"stat": "tempo", "amount": 2, "unlock": "Fulminate"}],  # level 4
		[{"stat": "flat", "amount": 1, "unlock": ""}, {"stat": "hp", "amount": 1, "unlock": ""}],  # level 5
		[{"stat": "will", "amount": 3, "unlock": ""}],  # level 6
		[{"stat": "flat", "amount": 2, "unlock": ""}, {"stat": "tempo", "amount": 2, "unlock": ""}],  # level 7
		[{"stat": "sharp", "amount": 1, "unlock": ""}],  # level 8
		[{"stat": "flat", "amount": 2, "unlock": ""}, {"stat": "will", "amount": 3, "unlock": ""}],  # level 9
		[{"stat": "hp", "amount": 2, "unlock": ""}, {"stat": "tempo", "amount": 2, "unlock": ""}],  # level 10
		[{"stat": "flat", "amount": 2, "unlock": ""}, {"stat": "sharp", "amount": 2, "unlock": ""}],  # level 11
		[{"stat": "will", "amount": 3, "unlock": ""}],  # level 12
		[{"stat": "flat", "amount": 3, "unlock": ""}, {"stat": "hp", "amount": 2, "unlock": ""}],  # level 13
		[{"stat": "sharp", "amount": 2, "unlock": ""}],  # level 14
		[{"stat": "flat", "amount": 3, "unlock": ""}, {"stat": "will", "amount": 4, "unlock": ""}],  # level 15
	],
	"vritra": [
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 0 placeholder
		[{"stat": "", "amount": 0, "unlock": ""}],  # level 1 placeholder
		[{"stat": "tempo", "amount": 1, "unlock": "Vice"}],  # level 2
		[{"stat": "sharp", "amount": 1, "unlock": ""}, {"stat": "will", "amount": 2, "unlock": ""}],  # level 3
		[{"stat": "hp", "amount": 2, "unlock": ""}],  # level 4
		[{"stat": "sharp", "amount": 1, "unlock": "Devour"}, {"stat": "tempo", "amount": 1, "unlock": ""}],  # level 5
		[{"stat": "will", "amount": 2, "unlock": ""}],  # level 6
		[{"stat": "hp", "amount": 2, "unlock": ""}, {"stat": "sharp", "amount": 1, "unlock": ""}],  # level 7
		[{"stat": "tempo", "amount": 2, "unlock": ""}],  # level 8
		[{"stat": "sharp", "amount": 1, "unlock": ""}, {"stat": "will", "amount": 2, "unlock": ""}],  # level 9
		[{"stat": "hp", "amount": 3, "unlock": ""}],  # level 10
		[{"stat": "sharp", "amount": 1, "unlock": ""}, {"stat": "tempo", "amount": 2, "unlock": ""}],  # level 11
		[{"stat": "will", "amount": 2, "unlock": ""}],  # level 12
		[{"stat": "hp", "amount": 3, "unlock": ""}, {"stat": "sharp", "amount": 2, "unlock": ""}],  # level 13
		[{"stat": "tempo", "amount": 3, "unlock": ""}],  # level 14
		[{"stat": "sharp", "amount": 2, "unlock": ""}, {"stat": "will", "amount": 2, "unlock": ""}],  # level 15
	]
}

static func get_rewards_for(display_name: String) -> Array:
	return LEVEL_REWARDS.get(display_name.to_lower(), [])


## Returns generated level rewards for levels beyond STATIC_MAX_LEVEL.
## Primary stat increases every even level; secondary stats cycle on odd levels.
## Amounts grow on a per-character curve based on the pattern already established.
static func generate_reward(display_name: String, level: int) -> Array:
	var name_key := display_name.to_lower()
	# How many "cycles" past the static table (each cycle = 2 levels).
	var cycle : int = (level - STATIC_MAX_LEVEL + 1) / 2
	# Curve exponent: gentle logarithmic growth so amounts don't explode.
	var scale : float = 1.0 + 0.08 * cycle

	match name_key:
		"kendall":
			# Primary: sharp+tempo every even level. Odd levels: hp.
			if level % 2 == 0:
				return [
					{"stat": "sharp", "amount": int(3 * scale), "unlock": ""},
					{"stat": "tempo", "amount": int(3 * scale), "unlock": ""}
				]
			else:
				return [{"stat": "hp", "amount": int(3 * scale), "unlock": ""}]
		"hue":
			# Primary: will every even level. Odd levels cycle: hp -> sharp -> tempo.
			if level % 2 == 0:
				return [{"stat": "will", "amount": int(4 * scale), "unlock": ""}]
			else:
				var hc : int = (level / 2) % 3
				var hs : String = "hp" if hc == 0 else ("sharp" if hc == 1 else "tempo")
				return [{"stat": hs, "amount": int(2 * scale), "unlock": ""}]
		"indra":
			# Primary: flat every even level. Odd levels cycle: will -> sharp -> tempo.
			if level % 2 == 0:
				return [
					{"stat": "flat", "amount": int(3 * scale), "unlock": ""},
					{"stat": "hp",   "amount": int(1 * scale), "unlock": ""}
				]
			else:
				var ic : int = (level / 2) % 3
				var is_ : String = "will" if ic == 0 else ("sharp" if ic == 1 else "tempo")
				return [{"stat": is_, "amount": int(2 * scale), "unlock": ""}]
		"vritra":
			# Primary: sharp every even level. Odd levels cycle: will -> hp -> tempo.
			if level % 2 == 0:
				return [{"stat": "sharp", "amount": int(3 * scale), "unlock": ""}]
			else:
				var vc : int = (level / 2) % 3
				var vs : String = "will" if vc == 0 else ("hp" if vc == 1 else "tempo")
				return [{"stat": vs, "amount": int(2 * scale), "unlock": ""}]
		_:
			return [{"stat": "hp", "amount": int(2 * scale), "unlock": ""}]


## EXP needed to reach target_level. Extends beyond the static table.
static func exp_needed_for_level(target_level: int) -> int:
	if target_level <= 0:
		return 0
	if target_level < EXP_THRESHOLDS.size():
		return EXP_THRESHOLDS[target_level]
	# Continue the curve: each step grows by ~10% over the previous gap.
	var base : int = EXP_THRESHOLDS[EXP_THRESHOLDS.size() - 1]
	var last_gap : int = EXP_THRESHOLDS[EXP_THRESHOLDS.size() - 1] \
		- EXP_THRESHOLDS[EXP_THRESHOLDS.size() - 2]
	var extra : int = target_level - (EXP_THRESHOLDS.size() - 1)
	var total : int = base
	var gap : float = float(last_gap)
	for i in extra:
		gap *= 1.10
		total += int(gap)
	return total


static func exp_to_next_level(current_level: int) -> int:
	if current_level >= MAX_LEVEL:
		return -1
	return exp_needed_for_level(current_level + 1)
