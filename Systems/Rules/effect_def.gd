class_name EffectDef
extends Resource
## One step of an action: damage, healing, applying a condition, or restoring Anima Portions.

enum Kind { DAMAGE, HEAL, APPLY_CONDITION, RESTORE_ANIMA, WEAPON_DAMAGE }
enum OnSave { NONE, NEGATES, HALF }

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
