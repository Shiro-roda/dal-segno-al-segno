extends Resource
class_name EncounterData


@export var battlefield_scene : PackedScene
@export var enemies : Array[CharacterData] = []
@export var intro_dialogue : EncounterDialogue
@export var override_music : BattleTrack
@export var forced_removed_channels : int = 0
