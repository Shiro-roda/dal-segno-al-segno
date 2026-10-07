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
## a full die; each later level is a roll of it (stored in corpus_rolls), plus the
## Tone modifier each level.
@export_range(2, 20) var corpus_die: int = 8
## The hit-die roll made for each level after the first (entry 0 is level 2). Filled
## in automatically when a level-up is applied, or the first time a sheet authored
## above level 1 is built. Not used by the player character.
@export var corpus_rolls: Array[int] = []
## attribute id -> score. Missing attributes default to RulesConfig.attribute_base.
@export var scores: Dictionary[StringName, int] = {}
## skill id -> ranks
@export var skill_ranks: Dictionary = {}
@export var known_actions: Array[ActionDef] = []
## The player character: always first in the active party. Only one sheet should set this.
@export var is_player: bool = false
## How this character levels up. Null = no level-ups.
@export var progression: ProgressionDef
## Feats taken so far (repeat an entry for stacks).
@export var feats: Array[FeatDef] = []
## slot id -> ItemDef
@export var equipment: Dictionary[StringName, ItemDef] = {}
## Corpus gained from companions levelling up (the player character's main source).
@export var bonus_corpus: int = 0
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
	fill_corpus_rolls(engine)
	block.corpus_rolls = corpus_rolls.duplicate()
	block.bonus_corpus = bonus_corpus
	block.apply_feats(feats)
	block.apply_equipment(equipment)
	block.refill()
	if current_corpus >= 0:
		block.corpus = mini(current_corpus, block.max_corpus())
	if current_anima >= 0:
		block.anima = mini(current_anima, block.max_anima())
	return block


## Rolls the hit die for any level above 1 that has no stored roll yet, so a sheet
## authored at a higher level gets a fixed result the first time it is built.
## The player character makes no hit-die rolls: their Corpus comes from companions.
func fill_corpus_rolls(engine: RulesEngine) -> void:
	if is_player:
		return
	var die := corpus_die if corpus_die > 0 else engine.config.default_corpus_die
	while corpus_rolls.size() < level - 1:
		corpus_rolls.append(Dice.roll(die, engine.rng))


## Copies runtime state back so it can be saved.
func sync_from(block: StatBlock) -> void:
	level = block.level
	corpus_rolls = block.corpus_rolls.duplicate()
	bonus_corpus = block.bonus_corpus
	current_corpus = block.corpus
	current_anima = block.anima
