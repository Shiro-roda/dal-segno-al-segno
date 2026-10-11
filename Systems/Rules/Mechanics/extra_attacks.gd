class_name ExtraAttacks
extends Mechanic
## Extra attacks with the basic Attack, and optionally permission for a secondary weapon.
## Stacks across feats: Guerriero I, II and III each carry one of these.

## Added to the primary weapon's attacks (it always has 1).
@export var primary: int = 0
## Attacks with the secondary weapon (counted only while one is equipped).
@export var secondary: int = 0
## Lets the owner hold a weapon in the armor or trinket slot.
@export var allows_secondary: bool = false


func extra_attacks(_owner: StatBlock, is_secondary: bool) -> int:
	return secondary if is_secondary else primary


func allows_secondary_weapon(_owner: StatBlock) -> bool:
	return allows_secondary
