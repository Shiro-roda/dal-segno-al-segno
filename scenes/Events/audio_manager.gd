

extends Node
class_name AudioManager

var bgm_bus: int
var sfx_bus: int
var bgm_lowpass: AudioEffectLowPassFilter
var sfx_distortion: AudioEffectDistortion
var bgm_distortion: AudioEffectDistortion
var bgm_highpass: AudioEffectHighPassFilter
var bgm_compressor: AudioEffectCompressor
var bgm_stereo: AudioEffectStereoEnhance
var bgm_reverb: AudioEffectReverb

var signal_integrity := 1.0  # 1.0 = perfect, 0.0 = broken
var base_noise := 0.0
var base_drive := 0.0
var base_lowpass_cutoff := 0.0
var base_pre_gain := 1.0
var _original_noise := 0.0  # true resting value, never overwritten mid-battle

# --- BGM STEM PLAYERS ---
@onready var bgm_base: AudioStreamPlayer = $BGM_Base
@onready var bgm_layers := {
	1: $BGM_R,  # R
	2: $BGM_G,  # G
	4: $BGM_B   # B
}

# --- SFX PLAYERS ---
@onready var sfx_players := [
	$SFXPlayer1,
	$SFXPlayer2
]

@onready var ui_player: AudioStreamPlayer = $UISFXPlayer
@onready var ambience_player: AudioStreamPlayer = $AmbiencePlayer


var sfx_index := 0
var layer_fade_time := 0.3

## How long the crossfade at loop point lasts (seconds).
const LOOP_FADE_TIME := 0.35
## True while a loop crossfade is in progress — prevents re-entrant triggers.
var _looping := false

func _ready() -> void:
	bgm_bus = AudioServer.get_bus_index("BGM")
	sfx_bus = AudioServer.get_bus_index("SFX")

	bgm_highpass = AudioServer.get_bus_effect(bgm_bus, 0) as AudioEffectHighPassFilter
	bgm_lowpass = AudioServer.get_bus_effect(bgm_bus, 1) as AudioEffectLowPassFilter
	bgm_distortion = AudioServer.get_bus_effect(bgm_bus, 2) as AudioEffectDistortion
	bgm_compressor = AudioServer.get_bus_effect(bgm_bus, 3) as AudioEffectCompressor
	bgm_stereo = AudioServer.get_bus_effect(bgm_bus, 4) as AudioEffectStereoEnhance
	bgm_reverb = AudioServer.get_bus_effect(bgm_bus, 5) as AudioEffectReverb


	sfx_distortion = AudioServer.get_bus_effect(sfx_bus, 1) as AudioEffectDistortion
	
	# Narrow band
	bgm_highpass.cutoff_hz = 260.0
	bgm_lowpass.cutoff_hz = 8200.0

	# Compression
	bgm_compressor.threshold = -10
	bgm_compressor.ratio = 4.0
	bgm_compressor.attack_us = 2000
	bgm_compressor.release_ms = 120

	# Subtle drive
	bgm_distortion.drive = 0.05
	bgm_distortion.pre_gain = 1.0
	
	base_noise = ambience_player.volume_db
	_original_noise = base_noise
	base_drive = bgm_distortion.drive
	base_lowpass_cutoff = bgm_lowpass.cutoff_hz
	
	bgm_reverb.room_size = 0.01

	# Connect loop crossfade: any stem finishing triggers a bus fade + restart.
	bgm_base.finished.connect(_on_bgm_finished)
	for player in bgm_layers.values():
		(player as AudioStreamPlayer).finished.connect(_on_bgm_finished)


# Stores the active dungeon track so it can be resumed after battle
var _current_dungeon_track : BattleTrack = null

# Dungeon ambient: muffled, distant, low volume
# Applied to the BGM bus while dungeon music plays; restored when battle starts.
const DUNGEON_VOLUME_DB   := -20.0   # faint overall level
const DUNGEON_LOWPASS_HZ  := 800.0   # heavy muffle - sound through walls
const DUNGEON_HIGHPASS_HZ := 400.0   # cut lows too, thin+hollow feel
const DUNGEON_REVERB_SIZE := 0.75    # large diffuse tail
const DUNGEON_DRIVE       := 0.0
const DUNGEON_PRE_GAIN    := 0.4

func _apply_dungeon_bus_state() -> void:
	bgm_lowpass.cutoff_hz   = DUNGEON_LOWPASS_HZ
	bgm_highpass.cutoff_hz  = DUNGEON_HIGHPASS_HZ
	bgm_reverb.room_size    = DUNGEON_REVERB_SIZE
	bgm_distortion.drive    = DUNGEON_DRIVE
	bgm_distortion.pre_gain = DUNGEON_PRE_GAIN

func _restore_battle_bus_state() -> void:
	bgm_highpass.cutoff_hz  = 260.0
	bgm_lowpass.cutoff_hz   = base_lowpass_cutoff
	bgm_reverb.room_size    = 0.01
	bgm_distortion.drive    = base_drive
	bgm_distortion.pre_gain = base_pre_gain

func play_dungeon_track(track: BattleTrack) -> void:
	if track == null:
		return
	_current_dungeon_track = track
	stop_bgm()
	_apply_dungeon_bus_state()
	bgm_base.stream = track.base
	bgm_layers[1].stream = track.red
	bgm_layers[2].stream = track.green
	bgm_layers[4].stream = track.blue
	bgm_base.volume_db = DUNGEON_VOLUME_DB
	for player in bgm_layers.values():
		player.volume_db = DUNGEON_VOLUME_DB
	var t = AudioServer.get_time_since_last_mix()
	if bgm_base.stream != null:
		bgm_base.play(t)
	for player in bgm_layers.values():
		if player.stream != null:
			player.play(t)

func resume_dungeon_track() -> void:
	if _current_dungeon_track != null:
		play_dungeon_track(_current_dungeon_track)

func play_battle_track(track: BattleTrack):

	stop_bgm() # ensure clean state
	_restore_battle_bus_state()

	bgm_base.stream = track.base
	bgm_layers[1].stream = track.red
	bgm_layers[2].stream = track.green
	bgm_layers[4].stream = track.blue

	# reset volumes
	bgm_base.volume_db = 0
	for player in bgm_layers.values():
		player.volume_db = 0

	var time = AudioServer.get_time_since_last_mix()

	bgm_base.play(time)

	for player in bgm_layers.values():
		player.play(time)



func stop_bgm():
	bgm_base.stop()
	for player in bgm_layers.values():
		player.stop()

func fade_out_bgm(duration := 0.6):

	var tween = create_tween()

	tween.tween_property(bgm_base, "volume_db", -80, duration)

	for player in bgm_layers.values():
		tween.parallel().tween_property(player, "volume_db", -80, duration)

	await tween.finished

	stop_bgm()


## Instantly reset all BGM stem volumes to 0 db with no tween.
## Called before handing audio control to the battle track so no
## dungeon fade tween can interfere with battle stem volumes.
func reset_dungeon_stem_volumes() -> void:
	for player in bgm_layers.values():
		(player as AudioStreamPlayer).volume_db = 0.0
	bgm_base.volume_db = 0.0


## Dungeon-specific channel layer update.
## Only mutes/unmutes stem players and adds relative degradation on top
## of the dungeon bus state — does NOT overwrite dungeon filter settings.
func update_dungeon_color_layers(removed_mask: int) -> void:
	# Mute/unmute the R/G/B stem players at dungeon volume (-20 db).
	for bit in bgm_layers.keys():
		var muted : bool = (removed_mask & bit) != 0
		_set_layer_volume(bgm_layers[bit], muted, DUNGEON_VOLUME_DB)

	# Count removed channels for degradation.
	var removed_count : int = 0
	var mask : int = removed_mask
	while mask > 0:
		removed_count += mask & 1
		mask >>= 1

	# No bus degradation in dungeon mode — stem muting is the only effect.


## Battle-mode channel layer update (full signal chain override).
func update_color_layers(removed_mask: int):

	for bit in bgm_layers.keys():
		var muted = (removed_mask & bit) != 0
		_set_layer_volume(bgm_layers[bit], muted)

	# Tonal degradation based on color loss
	var removed_count = 0
	var mask = removed_mask
	while mask > 0:
		removed_count += mask & 1
		mask >>= 1
	var target_drive := base_drive
	var target_pre_gain := base_pre_gain
	
	signal_integrity = 1.0 - (removed_count / 2.0)

	var damage = 1.0 - signal_integrity

	match removed_count:
		0:
			target_drive = 0.05
			target_pre_gain = 0.05
			bgm_reverb.room_size = 0.01
		1:
			target_drive = 2.00
			target_pre_gain = 2.0
			bgm_reverb.room_size = 0.1
		2:
			target_drive = 6.00
			target_pre_gain = 4.2
			bgm_compressor.ratio = 2
			bgm_reverb.room_size = 0.5


	var target_cutoff = lerp(2000.0, 800.0, damage)

	target_cutoff = clamp(target_cutoff, 500.0, 20000.0)
	
	
	
	var target_noise = lerp(base_noise, -40.0, 1.0 - signal_integrity)
	ambience_player.volume_db = target_noise

	var tween = create_tween()
	tween.tween_method(
		func(v): bgm_lowpass.cutoff_hz = v,
		bgm_lowpass.cutoff_hz,
		target_cutoff,
		0.4
	)
	
	tween.parallel().tween_property(
		bgm_distortion,
		"drive",
		target_drive,
		0.4
	)

	tween.parallel().tween_property(
		bgm_distortion,
		"pre_gain",
		target_pre_gain,
		0.4
	)
	var target_width = lerp(1.0, 0.0, 1.0 - signal_integrity)


	tween.parallel().tween_property(
		bgm_stereo,
		"pan_pullout",
		target_width,
		0.4
	)
	base_noise = ambience_player.volume_db
	base_drive = bgm_distortion.drive
	base_lowpass_cutoff = bgm_lowpass.cutoff_hz




func _set_layer_volume(player: AudioStreamPlayer, muted: bool, on_db: float = 0.0):
	var target_db : float = -80.0 if muted else on_db
	if is_equal_approx(player.volume_db, target_db):
		return
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(player, "volume_db", target_db, layer_fade_time)

func set_glitch_intensity(amount: float, duration: float = 0.2):

	var start_drive = base_drive
	var start_cutoff = base_lowpass_cutoff
	var start_noise = base_noise


	var target_drive = start_drive + amount
	var target_cutoff = lerp(start_cutoff, 300.0, amount)
	var target_noise = lerp(start_noise, -8.0, amount)

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_EXPO)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_method(
		func(v): sfx_distortion.drive = v,
		start_drive,
		target_drive,
		duration
	)
	
	var burst_drive = start_drive + (amount * 1.5)

	tween.parallel().tween_method(
		func(v): bgm_distortion.drive = v,
		start_drive,
		burst_drive,
		duration * 0.5
	)

	tween.tween_method(
		func(v): bgm_distortion.drive = v,
		burst_drive,
		start_drive,
		duration
	)


	
	tween.parallel().tween_method(
		func(v): bgm_lowpass.cutoff_hz = v,
		start_cutoff,
		target_cutoff,
		duration
	)
	
	tween.tween_method(
		func(v): bgm_lowpass.cutoff_hz = v,
		target_cutoff,
		start_cutoff,
		duration
	)
	
	tween.parallel().tween_property(
		ambience_player,
		"volume_db",
		target_noise,
		0.4
	)
	
	tween.parallel().tween_property(
		ambience_player,
		"volume_db",
		start_noise,
		0.4
	)
	





func _on_bgm_finished() -> void:
	if _looping:
		return
	_looping = true
	var normal_vol : float = AudioServer.get_bus_volume_db(bgm_bus)
	var tween := create_tween()
	# Fade bus out
	tween.tween_method(
		func(v): AudioServer.set_bus_volume_db(bgm_bus, v),
		normal_vol, -80.0, LOOP_FADE_TIME)
	await tween.finished
	# Restart all active streams from the top
	var t := AudioServer.get_time_since_last_mix()
	if bgm_base.stream != null:
		bgm_base.play(t)
	for player in bgm_layers.values():
		if (player as AudioStreamPlayer).stream != null:
			(player as AudioStreamPlayer).play(t)
	# Fade bus back in
	var tween2 := create_tween()
	tween2.tween_method(
		func(v): AudioServer.set_bus_volume_db(bgm_bus, v),
		-80.0, normal_vol, LOOP_FADE_TIME)
	await tween2.finished
	_looping = false


func reset_ambience() -> void:
	ambience_player.volume_db = _original_noise
	base_noise = _original_noise
	signal_integrity = 1.0

func play_sfx(stream: AudioStream):

	var player = sfx_players[sfx_index]
	sfx_index = (sfx_index + 1) % sfx_players.size()

	player.stream = stream
	player.play()

func play_ui(stream: AudioStream):
	ui_player.stream = stream
	ui_player.play()

func duck_bgm(strength: float = -6.0, duration: float = 0.3):

	var start_db = AudioServer.get_bus_volume_db(bgm_bus)

	var tween = create_tween()

	tween.tween_method(
		func(v): AudioServer.set_bus_volume_db(bgm_bus, v),
		start_db,
		strength,
		0.05
	)

	tween.tween_method(
		func(v): AudioServer.set_bus_volume_db(bgm_bus, v),
		strength,
		start_db,
		duration
	)
