class_name ProgressionDef
extends Resource
## How a companion grows: XP thresholds and what each level offers. Corpus gains are
## rolled on the character's own hit die (CharacterSheet.corpus_die), not set here.
## The player character uses none: they earn no XP and don't level up. Assign it to
## CharacterSheet.progression.

## Highest level reachable.
@export var max_level: int = 12
## Cumulative XP needed to reach level 2, 3, 4... (entry 0 is level 2). A level
## with no entry can't be reached. These numbers are placeholders; tune them.
@export var xp_thresholds: PackedInt32Array = PackedInt32Array(
		[100, 250, 450, 700, 1000, 1350, 1750, 2200, 2700, 3250, 3850])

@export_group("Picks")
## First level that can grant picks.
@export var first_pick_level: int = 2
## A feat pick every N levels, starting at first_pick_level. 0 = never.
@export var feat_every: int = 1
## A Canto pick every N levels. 0 = never (the player character).
@export var canto_every: int = 1
## An attribute pick every N levels. 0 = never.
@export var attribute_every: int = 0
## How many random choices each feat or Canto pick offers.
@export var offer_size: int = 3
## Points added by one attribute pick.
@export var attribute_amount: int = 1

@export_group("Pools")
## Feats this character can be offered.
@export var feat_pool: Array[FeatDef] = []
## Cantos (and other actions) this character can be offered.
@export var canto_pool: Array[ActionDef] = []


## Cumulative XP needed to reach `level`, or -1 if that level can't be reached.
func xp_for_level(level: int) -> int:
	if level <= 1:
		return 0
	var i := level - 2
	if i < xp_thresholds.size():
		return xp_thresholds[i]
	return -1


## True if a character at `level` with `xp` has earned the next level.
func can_level(level: int, xp: int) -> bool:
	if level >= max_level:
		return false
	var need := xp_for_level(level + 1)
	return need >= 0 and xp >= need


## How many picks of each kind reaching `level` grants: {feat, canto, attribute}.
func picks_for(level: int) -> Dictionary:
	return {
		&"feat": _picks(feat_every, level),
		&"canto": _picks(canto_every, level),
		&"attribute": _picks(attribute_every, level),
	}


func _picks(every: int, level: int) -> int:
	if every <= 0 or level < first_pick_level:
		return 0
	return 1 if (level - first_pick_level) % every == 0 else 0
