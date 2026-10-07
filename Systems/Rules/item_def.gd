class_name ItemDef
extends Resource
## An equippable item: stat modifiers while equipped, and abilities it grants.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Which equipment slot it goes in (see RulesConfig.equipment_slots).
@export var slot: StringName = &"weapon"
## stat id -> modifier value. Pseudo-stats such as "defense", "damage",
## "initiative", "corpus_max" and "anima_max" are allowed.
@export var modifiers: Dictionary[StringName, int] = {}
@export var granted_actions: Array[ActionDef] = []

@export_group("Weapon")
## Only used by items in the weapon slot. Every character's Attack action rolls the
## equipped weapon's dice, e.g. "1d8" or "2d4+1". Leave blank for a non-weapon.
@export var damage_dice: String = ""
## Stat added to the attack roll. Blank uses RulesConfig.default_attack_stat.
@export var attack_stat: StringName = &""
## Stat whose modifier is added to the damage. Blank uses RulesConfig.default_damage_stat.
@export var damage_stat: StringName = &""
@export var damage_type: StringName = &"physical"
## Reach of the weapon's attack in metres. 0 = use the default: melee reach, or
## the ranged default if the weapon is tagged "ranged". Roughly: 2.2 sword,
## 3.5 spear, 12 bow.
@export var weapon_range: float = 0.0
@export var weapon_tags: PackedStringArray = PackedStringArray()
