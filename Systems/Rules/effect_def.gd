class_name EffectDef
extends Resource
## One step of an action: damage, healing, applying a condition, or restoring Anima Portions.

enum Kind { DAMAGE, HEAL, APPLY_CONDITION, RESTORE_ANIMA, WEAPON_DAMAGE, CUSTOM }


enum OnSave { NONE, NEGATES, HALF }
enum Target { SELF, SINGLE_ENEMY, SINGLE_ALLY, ALL_ENEMIES, ALL_ALLIES }

## Who this step lands on. SELF is the user; the single-target kinds use the target the
## player (or AI) picked; the ALL kinds hit everyone on that side.
@export var target: Target = Target.SINGLE_ENEMY

func is_hostile() -> bool:
	return target == Target.SINGLE_ENEMY or target == Target.ALL_ENEMIES

## CUSTOM only. Override in a subclass.
func apply_custom(_engine: RulesEngine, _user: StatBlock, _target: StatBlock, _ctx: Dictionary) -> void:
	pass

@export var kind: Kind = Kind.DAMAGE
## Dice expression, e.g. "1d8" or "2d6+1". Used by DAMAGE, HEAL and RESTORE_ANIMA.
## For WEAPON_DAMAGE the weapon supplies the dice, so use this only for extra dice
## on top of the weapon (e.g. "1d6" of fire), or leave it blank.

@export var dice: String = ""
## Add this stat's modifier to the result (e.g. "volume" for melee damage).
@export var bonus_stat: StringName
## Free-form damage type, e.g. "physical", "red", "green", "blue". WEAPON_DAMAGE
## uses the weapon's own type.
@export var damage_type: StringName = &"physical"
@export var condition: ConditionDef
## Overrides the condition's own duration when >= 0.
@export var condition_duration: int = -1
## What a successful save does to this effect (SAVE-type actions only).
@export var on_save: OnSave = OnSave.NONE

@export_group("Upcasting")
## Cantos only. Extra dice rolled once for every level the Canto is cast above its
## own level, e.g. "1d6". Used by DAMAGE, HEAL, RESTORE_ANIMA and WEAPON_DAMAGE.
@export var upcast_dice: String = ""
## Cantos only. Extra rounds added to an applied condition per level cast above
## the Canto's own level.
@export var upcast_duration: int = 0
