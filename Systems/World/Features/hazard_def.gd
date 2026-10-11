class_name HazardDef
extends Resource
## Marks a dungeon tile as a hazard room. Set it on TileDef.hazard.
##
## The first time the party walks in each day, every active character makes a save
## against the DC and takes the damage (reduced or negated by a success, per on_save).
## A failed save also applies the condition, if one is set. Walking in also earns bonus
## blueprints, which join the hand at the next dawn.

## Stat id the save is rolled with.
@export var save_stat: StringName = &"tempo"
@export var save_dc := 12
## Dice expression, e.g. "1d6" or "2d4+1".
@export var damage := "1d6"
@export var damage_type: StringName = &"physical"
## What a successful save does to the damage.
@export var on_save: EffectDef.OnSave = EffectDef.OnSave.HALF
## Applied to anyone who fails the save. Optional.
@export var condition: ConditionDef
## Off: the hazard can leave a character at 1 Corpus but never knock them out.
@export var lethal := false
## Extra blueprints added to tomorrow's hand each day this hazard is triggered. They are
## drawn from the normal blueprint pool. WorldConfig.hazard_bonus_cap limits the total.
@export_range(0, 10) var bonus_blueprints := 1
## Text shown when the trap goes off.
## [Write the line shown when the party triggers this hazard.]
@export var trigger_text := ""
