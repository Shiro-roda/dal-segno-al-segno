class_name AllyTemplate
extends Resource
## Authoring data for one friendly NPC unit, the counterpart of EnemyTemplate. A defensive
## room (a TileDef with an `ally`) musters these. Build a StatBlock with build_block(); the
## unit then fights through the same CombatSession as the party, whether on screen or
## resolved off-screen.
##
## How it behaves (guard its room's vertex, or patrol the roads) belongs to the room that
## musters it, not to the unit.

@export var display_name: String = "Guard"
@export var level: int = 1
## This unit's Corpus die: d6 for a frail one, d12 for a bruiser.
@export_range(2, 20) var corpus_die: int = 8
## Attribute id -> score, e.g. {"volume": 14, "tone": 12}. Missing attributes use the default.
@export var scores: Dictionary[StringName, int] = {}
@export var known_actions: Array[ActionDef] = []
## slot id -> ItemDef. A weapon sets the attack dice and reach.
@export var equipment: Dictionary[StringName, ItemDef] = {}
## Shown in the exploration space when the unit is in the party's room. Optional.
@export var model_scene: PackedScene
## 0 = take the reach from the equipped weapon. Anything above 0 overrides it.
@export var attack_range: float = 0.0
@export var move_speed: float = 3.5
@export var mechanics: Array[Mechanic] = []


func build_block(engine: RulesEngine) -> StatBlock:
	var b := StatBlock.new(engine, display_name, level)
	b.corpus_die = corpus_die
	# Editor dictionaries may use String keys; the rules code uses StringNames.
	for key in scores:
		b.scores[StringName(key)] = scores[key]
	for def in engine.stats_in_category(StatDef.Category.ATTRIBUTE):
		if not b.scores.has(def.id):
			b.scores[def.id] = engine.config.attribute_base
	b.known_actions = known_actions.duplicate()
	b.apply_equipment(equipment)
	b.innate_mechanics.assign(mechanics)
	b.refill()
	return b
