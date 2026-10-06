class_name ConditionDef
extends Resource
## A timed or permanent effect that modifies stats, grants advantage/disadvantage,
## ticks damage, or blocks actions.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Rounds remaining when applied. -1 = lasts until removed.
@export var duration_rounds: int = 3
## stat id -> modifier value. Pseudo-stats such as "defense" are allowed.
@export var modifiers: Dictionary = {}
## Stat ids (or "all") this condition gives advantage on.
@export var advantage_on: PackedStringArray = PackedStringArray()
## Stat ids (or "all") this condition gives disadvantage on.
@export var disadvantage_on: PackedStringArray = PackedStringArray()
@export var blocks_actions: bool = false
## Dice expression dealt to the bearer at the end of each round, e.g. "1d4". Empty = none.
@export var tick_damage: String = ""
