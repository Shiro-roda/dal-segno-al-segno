class_name EnemyTemplate
extends Resource
## Authoring data for one enemy. Build a fresh StatBlock per fight with build_block().

@export var display_name: String = "Enemy"
@export var level: int = 1
## This enemy's Corpus die: d6 for a frail one, d12 for a bruiser.
@export_range(2, 20) var corpus_die: int = 8
## Attribute id -> score, e.g. {"volume": 14, "tone": 12}. Missing attributes use the default.
@export var scores: Dictionary[StringName, int] = {}
@export var known_actions: Array[ActionDef] = []
## slot id -> ItemDef, same as a CharacterSheet. A weapon sets the attack dice and reach.
@export var equipment: Dictionary[StringName, ItemDef] = {}
## Shown in the exploration space during the fight. Optional.
@export var model_scene: PackedScene
## 0 = take the reach from the equipped weapon. Anything above 0 overrides it.
@export var attack_range: float = 0.0
@export var move_speed: float = 3.0
## XP each active companion earns when a fight containing this enemy is won.
## Kendall earns none. 0 = awards nothing.
@export var xp_value: int = 0

enum NoteColor { NONE, RED, GREEN, BLUE }
## The colour this enemy belongs to. A room is most likely to gather enemies of its
## lowest colour(s), and every note a kill drops is this colour. NONE (uncoloured) counts
## as neutral when a room picks enemies, and each note it drops is a random colour.
@export var note_color: NoteColor = NoteColor.NONE
## How many notes this enemy drops when it is laid to rest, before the room's
## note_multiplier and the main-path bonus. 0 = drops none.
@export_range(0, 100) var notes_per_kill: int = 4


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
	b.refill()
	return b
