class_name RestDef
extends Resource
## Marks a dungeon tile as a short rest room. Set it on TileDef.rest.
##
## Interacting with the room (once per day by default) restores a fraction of every
## active character's Anima. The party may also spend daily hit dice there: each die
## heals its roll plus the character's Corpus stat modifier (at least 1). Hit dice are a
## daily pool per character (see WorldConfig.hit_dice_per_level), shared by every rest
## room, and refill when the next day begins.
##
## A room can't be rested in while remnants are still alive in it.

## Share of each character's max Anima restored, rounded up.
@export_range(0.0, 1.0, 0.05) var anima_fraction := 0.5
## Times the party can use this room per day.
@export_range(1, 10) var uses_per_day := 1
## Off: the room restores Anima only.
@export var allow_hit_dice := true
## Text on the interact prompt.
## [Write the interact prompt for a short rest room, e.g. what the player is told they can do here.]
@export var prompt := ""
