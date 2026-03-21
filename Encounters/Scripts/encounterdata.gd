extends Resource
class_name EncounterData


@export var battlefield_scene : PackedScene
@export var enemies : Array[CharacterData] = []
# Full-screen splash cards shown before battle. Each has text + a speaker for colour.
@export var intro_splash : Array[SplashLine] = []
@export var intro_dialogue : EncounterDialogue
@export var override_music : BattleTrack
@export var forced_removed_channels : int = 0
@export var reticle_theme : ReticleTheme = null
@export var is_tutorial : bool = false
