extends Resource
class_name EncounterData

@export var enemy_scenes: Array[PackedScene]
@export var player_scenes: Array[PackedScene]
@export var battle_track: BattleTrack
@export var ambience_stream: AudioStream
@export var starting_removed_channels: int = 0
@export var encounter_id: String
