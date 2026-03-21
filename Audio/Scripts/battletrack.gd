extends Resource
class_name BattleTrack

@export var base: AudioStream
@export var red: AudioStream
@export var green: AudioStream
@export var blue: AudioStream

## Optional per-encounter bus effect override.
## Leave null to use the standard clean battle chain.
@export var audio_settings : BattleAudioSettings = null
