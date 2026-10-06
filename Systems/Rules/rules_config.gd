class_name RulesConfig
extends Resource
## Tunable rule knobs. Changing a rule should be a one-line edit here.

# --- Dice ---
@export var die_sides: int = 20
## A natural roll at or above this is a critical.
@export var crit_min: int = 20
## A natural roll at or below this is a fumble.
@export var fumble_max: int = 1
@export var natural_crit_auto_hit: bool = true
@export var natural_fumble_auto_miss: bool = true
## Dice are multiplied by this on a critical hit (flat bonuses are not).
@export var crit_dice_multiplier: int = 2
## If true, any advantage plus any disadvantage cancel to a normal roll.
@export var advantage_cancels: bool = true

# --- Attributes ---
@export var attribute_base: int = 10
@export var attribute_step: int = 2
## Bonus per rank in a skill.
@export var skill_rank_bonus: int = 1

# --- Defense and saves ---
@export var base_defense: int = 10
@export var defense_stat: StringName = &"tempo"
@export var initiative_stat: StringName = &"tempo"
@export var save_dc_base: int = 8
## +1 to save DCs per this many levels.
@export var save_dc_level_step: int = 4

# --- Corpus Portions (health) ---
## Flat Corpus every character has, on top of their dice.
@export var corpus_base: int = 10
## Corpus die for characters that don't set their own (CharacterSheet.corpus_die).
## Level 1 gets a full die; each later level gets the die's average (half + 1).
## The corpus_stat modifier is added at every level.
@export var default_corpus_die: int = 8
@export var corpus_stat: StringName = &"tone"

# --- Party and equipment ---
@export var party_size: int = 3
@export var equipment_slots: Array[StringName] = [&"weapon", &"armor", &"trinket"]

# --- Anima Portions (spell slots) ---
@export var anima_base: int = 2
## +1 Anima Portion per this many levels.
@export var anima_level_step: int = 2
## Colour stats; the highest modifier among them adds to max Anima Portions.
@export var color_stats: Array[StringName] = [&"aversion", &"attachment", &"delusion"]

# --- Cantos ---
## Anima Portions a Canto costs when cast at each level; entry 0 is level 1.
## The number of entries is the number of Canto levels.
@export var canto_costs: Array[int] = [1, 2, 3]
## Character level at which each Canto level unlocks, in the same order as
## canto_costs, lowest first: by default Canto level 2 at character level 5 and
## level 3 at 10. A character can't cast a Canto above their unlocked level, and
## upcasting is held at it.
@export var canto_unlock_levels: Array[int] = [1, 5, 10]

# --- Weapons ---
## Used when nothing is equipped in the weapon slot, and for any stat a weapon
## leaves blank.
@export var unarmed_name: String = "Fists"
@export var unarmed_dice: String = "1d2"
@export var default_attack_stat: StringName = &"volume"
@export var default_damage_stat: StringName = &"volume"
@export var unarmed_damage_type: StringName = &"physical"
## Optional: your own Attack action, replacing the built-in one that every
## character gets. It should use a WEAPON_DAMAGE effect.
@export var basic_attack: ActionDef

var _unarmed: ItemDef
var _builtin_attack: ActionDef


## Cost of casting a Canto at `level` (clamped to the configured levels).
func canto_cost(level: int) -> int:
	if canto_costs.is_empty():
		return 0
	return canto_costs[clampi(level - 1, 0, canto_costs.size() - 1)]


func canto_level_count() -> int:
	return canto_costs.size()


## The highest Canto level a character of `character_level` has unlocked
## (0 if none). Assumes canto_unlock_levels is in ascending order.
func max_canto_level_for(character_level: int) -> int:
	var best := 0
	for i in canto_unlock_levels.size():
		if character_level >= canto_unlock_levels[i]:
			best = i + 1
	return mini(best, canto_costs.size())


## The weapon used when none is equipped.
func unarmed_weapon() -> ItemDef:
	if _unarmed == null:
		_unarmed = ItemDef.new()
		_unarmed.id = &"unarmed"
		_unarmed.display_name = unarmed_name
		_unarmed.slot = &"weapon"
		_unarmed.damage_dice = unarmed_dice
		_unarmed.damage_type = unarmed_damage_type
	return _unarmed


## The Attack action every character has: an attack roll, then the equipped
## weapon's dice.
func get_basic_attack() -> ActionDef:
	if basic_attack != null:
		return basic_attack
	if _builtin_attack == null:
		_builtin_attack = ActionDef.new()
		_builtin_attack.id = &"attack"
		_builtin_attack.display_name = "Attack"
		_builtin_attack.description = "Attack with your equipped weapon."
		_builtin_attack.roll = ActionDef.Roll.ATTACK
		_builtin_attack.target = ActionDef.Target.SINGLE_ENEMY
		var fx := EffectDef.new()
		fx.kind = EffectDef.Kind.WEAPON_DAMAGE
		_builtin_attack.effects = [fx]
	return _builtin_attack


func ability_mod(score: int) -> int:
	return floori((score - attribute_base) / float(attribute_step))


## One attribute's share of a multi-attribute stat: modifier / count, rounded up.
func split_mod(mod: int, count: int) -> int:
	return ceili(mod / float(maxi(1, count)))
