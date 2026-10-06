class_name EnemyTemplate
extends Resource
## Authoring data for one enemy. Build a fresh StatBlock per fight with build_block().

@export var display_name: String = "Enemy"
@export var level: int = 1
## Attribute id -> score, e.g. {"volume": 14, "tone": 12}. Missing attributes use the engine default.
@export var scores: Dictionary = {}
@export var known_actions: Array[ActionDef] = []
## Shown in the exploration space during the fight. Optional.
@export var model_scene: PackedScene

## Reach of the basic attack in metres. Raise it for archers and casters.
@export var attack_range: float = 2.2
@export var move_speed: float = 3.0

func build_block(engine: RulesEngine) -> StatBlock:
	var b := StatBlock.new(engine, display_name, level)
	# Editor dictionaries use String keys; the rules code uses StringNames.
	for key in scores:
		b.scores[StringName(key)] = scores[key]
	b.known_actions = known_actions.duplicate()
	b.refill()
	return b
