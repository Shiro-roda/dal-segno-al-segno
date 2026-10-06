class_name CharacterSheet
extends Resource
## The saved, editable definition of a character: attributes, skill ranks, level,
## known abilities, equipment and persistent Corpus/Anima. A StatBlock is built from it.

@export var id: StringName
@export var display_name: String = ""
## 3D model shown in exploration (and later combat). Optional.
@export var model_scene: PackedScene
@export var level: int = 1
@export var xp: int = 0
## This character's Corpus die: d6 for a frail one, d12 for a bruiser. Level 1 gets
## a full die and each later level its average, plus the Tone modifier each level.
@export_range(2, 20) var corpus_die: int = 8
## attribute id -> score. Missing attributes default to RulesConfig.attribute_base.
@export var scores: Dictionary = {}
## skill id -> ranks
@export var skill_ranks: Dictionary = {}
@export var known_actions: Array[ActionDef] = []
## slot id -> ItemDef
@export var equipment: Dictionary[StringName, ItemDef] = {}
## Persistent Corpus / Anima Portions. -1 means "full".
@export var current_corpus: int = -1
@export var current_anima: int = -1


func build_block(engine: RulesEngine) -> StatBlock:
	var block := StatBlock.new(engine, display_name, level)
	block.corpus_die = corpus_die
	block.scores = scores.duplicate()
	for def in engine.stats_in_category(StatDef.Category.ATTRIBUTE):
		if not block.scores.has(def.id):
			block.scores[def.id] = engine.config.attribute_base
	block.skill_ranks = skill_ranks.duplicate()
	block.known_actions = known_actions.duplicate()
	block.apply_equipment(equipment)
	block.refill()
	if current_corpus >= 0:
		block.corpus = mini(current_corpus, block.max_corpus())
	if current_anima >= 0:
		block.anima = mini(current_anima, block.max_anima())
	return block


## Copies runtime state back so it can be saved.
func sync_from(block: StatBlock) -> void:
	level = block.level
	current_corpus = block.corpus
	current_anima = block.anima
