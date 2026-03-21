extends Resource
class_name BattleAudioSettings
## Per-encounter BGM bus effect settings.
##
## Leave audio_settings null on BattleTrack to use the standard clean battle chain.
## Create a BattleAudioSettings resource and set audio_settings on BattleTrack to override.
##
## use_dungeon_as_base: when true all defaults match the dungeon ambient chain
## (muffled, distant, reverbed). Individual values can still be tweaked on top.

## Start from the dungeon effect chain instead of the clean battle chain.
## Tick this when the battle should feel like it's happening inside the dungeon ambience.
## All defaults below reflect the dungeon values when this is true.
@export var use_dungeon_as_base : bool = false

## Lowpass filter cutoff (Hz). Lower = more muffled.
## Battle default: 8200 Hz. Dungeon default: 800 Hz.
@export_range(200.0, 20000.0, 10.0, "suffix:Hz") var lowpass_cutoff_hz  : float = 8200.0

## Highpass filter cutoff (Hz). Higher = thinner/hollower.
## Battle default: 260 Hz. Dungeon default: 400 Hz.
@export_range(20.0, 8000.0, 10.0, "suffix:Hz")  var highpass_cutoff_hz : float = 260.0

## Reverb room size (0–1). Larger = more diffuse tail.
## Battle default: 0.01. Dungeon default: 0.75.
@export_range(0.0, 1.0, 0.01) var reverb_room_size : float = 0.01

## Distortion drive (0–1).
## Battle default: 0.05. Dungeon default: 0.0.
@export_range(0.0, 1.0, 0.01) var distortion_drive : float = 0.05

## Distortion pre-gain.
## Battle default: 1.0. Dungeon default: 0.4.
@export_range(0.0, 4.0, 0.01) var distortion_pre_gain : float = 1.0
