class_name FeatDef
extends Resource
## A permanent upgrade a character can take on level-up.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## stat id -> bonus while owned. The same pseudo-stats ItemDef allows
## ("defense", "damage", "initiative", "corpus_max", "anima_max") work here.
@export var modifiers: Dictionary = {}
@export var granted_actions: Array[ActionDef] = []

@export_group("Offering")
## Relative chance of being offered when it is eligible.
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0
## Not offered below this character level.
@export var min_level: int = 1
## The character must already own all of these.
@export var required_feats: Array[FeatDef] = []
## attribute id -> minimum score needed to be offered.
@export var min_scores: Dictionary = {}
## How many times it can be taken (stacks).
@export var max_stacks: int = 1
@export var tags: PackedStringArray = PackedStringArray()
