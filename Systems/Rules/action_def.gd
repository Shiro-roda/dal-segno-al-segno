class_name ActionDef
extends Resource
## A usable ability (attack, Canto, technique) described entirely as data.
##
## Ordinary actions cost `anima_cost` (usually 0). A Canto has a level of 1 or more
## and costs whatever RulesConfig.canto_costs says for the level it is cast at.

enum Roll { AUTO, ATTACK, SAVE }
enum Target { SELF, SINGLE_ENEMY, SINGLE_ALLY, ALL_ENEMIES, ALL_ALLIES }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Anima Portions spent by an ordinary action. Ignored for Cantos, which cost
## their level's price from RulesConfig.canto_costs.
@export var anima_cost: int = 0
@export var roll: Roll = Roll.AUTO
@export var target: Target = Target.SINGLE_ENEMY
## ATTACK: the stat added to the attack roll. Blank uses the equipped weapon's.
@export var attack_stat: StringName
## SAVE: the stat the target rolls.
@export var save_stat: StringName
## SAVE: the user's stat that sets the DC.
@export var dc_stat: StringName
## Reach in metres for single-target use. 0 = the session's default spell range.
@export var max_range: float = 0.0
@export var effects: Array[EffectDef] = []
@export var tags: PackedStringArray = PackedStringArray()

@export_group("Canto")
## 0 = not a Canto. 1, 2 or 3 = the level this Canto is cast at. A Canto that is
## simply a higher-level spell in its own right just has a higher level here.
@export_range(0, 3) var canto_level: int = 0
## Highest level this Canto can be upcast to. 0, or anything not above
## `canto_level`, means it can't be upcast. Upcasting costs the higher level's
## price and adds each effect's upcast dice and duration for every level gained.
@export_range(0, 3) var max_canto_level: int = 0

@export_group("Cantrip")
## A cantrip costs no Anima and can be used every turn. Leave canto_level at 0.
## Its effects gain `upcast_dice` / `upcast_duration` once per tier of the caster's
## level (RulesConfig.cantrip_scale_levels).
@export var cantrip: bool = false

func is_canto() -> bool:
	return canto_level > 0

func is_cantrip() -> bool:
	return cantrip and not is_canto()

## Highest level this can be cast at (0 for an ordinary action).
func top_level() -> int:
	if not is_canto():
		return 0
	return maxi(canto_level, max_canto_level)


func can_upcast() -> bool:
	return top_level() > canto_level


## Every level this can be cast at, lowest first. Empty for an ordinary action.
func castable_levels() -> Array[int]:
	var out: Array[int] = []
	if is_canto():
		for level in range(canto_level, top_level() + 1):
			out.append(level)
	return out


## The level a cast actually happens at: the Canto's own level if none is asked
## for, otherwise the request limited to what this Canto allows. 0 if ordinary.
func resolve_level(requested: int = 0) -> int:
	if not is_canto():
		return 0
	if requested <= 0:
		return canto_level
	return clampi(requested, canto_level, top_level())
