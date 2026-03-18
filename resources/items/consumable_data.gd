extends ItemData
class_name ConsumableData
## Extra fields for items that can be used from the inventory.

## The effect type this item applies when used.
## Matches the type strings used in shop_event and _apply_battle_reward.
@export var effect_type : String = ""   # "corpus" | "will" | "reroll" | "road_tile"
@export var effect_amount : int = 0

## Whether this item can be used during battle.
@export var usable_in_battle : bool = false
## Whether this item can be used in the dungeon map.
@export var usable_in_dungeon : bool = true
