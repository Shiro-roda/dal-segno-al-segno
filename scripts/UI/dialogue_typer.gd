# DialogueTyper — shared typewriter helper used by BattleDialogueBox,
# WorldDialogueBox, and BattleHUD chatter.
#
# Usage:
#   var typer := DialogueTyper.new()
#   add_child(typer)
#   await typer.type_into(rich_text_label, full_text, chars_per_sec, sound_stream)
#   typer.skip()   # call this on confirm input to reveal all text instantly
extends Node
class_name DialogueTyper

# Speaker default speeds (chars/sec). Tweak freely.
const SPEAKER_SPEEDS : Dictionary = {
	"Kendall": 40.0,
	"Hue":     36.0,
	"Indra":   44.0,
	"Vritra":  30.0,
	"Helenus": 18.0,
}
const DEFAULT_SPEED    := 38.0   # fallback for unknown speakers / narration
const NARRATE_SPEED    := 50.0   # narration (no speaker) tends to be faster

# If true, the current type_into call is still running
var is_typing := false

var _skip_requested := false
var _player : AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "SFX"
	_player.volume_db = -8.0
	add_child(_player)


# Returns the default chars/sec for a given speaker name.
static func speed_for_speaker(speaker: String) -> float:
	if speaker.strip_edges() == "":
		return NARRATE_SPEED
	return SPEAKER_SPEEDS.get(speaker, DEFAULT_SPEED)


# Type `full_text` into `label` (RichTextLabel) one character at a time.
# chars_per_sec: 0 or negative means instant. sound: played per character.
# Awaitable — resolves when typing finishes or skip() is called.
func type_into(label: RichTextLabel, full_text: String,
		chars_per_sec: float, sound: AudioStream = null) -> void:
	is_typing = true
	_skip_requested = false

	if chars_per_sec <= 0.0:
		label.clear()
		label.append_text(full_text)
		is_typing = false
		return

	# We use RichTextLabel's visible_characters to reveal text gradually.
	# Set the full text first so BBCode is parsed, then animate visible_ratio.
	label.clear()
	label.append_text(full_text)
	label.visible_ratio = 0.0

	var total_chars : int = label.get_total_character_count()
	if total_chars == 0:
		is_typing = false
		return

	var interval : float = 1.0 / chars_per_sec
	var shown    : int   = 0

	while shown < total_chars:
		if _skip_requested:
			break
		shown += 1
		label.visible_characters = shown
		if sound and _player and shown % 2 == 0:  # play every 2nd char to avoid noise spam
			_player.stream = sound
			if not _player.playing:
				_player.play()
		await get_tree().create_timer(interval, false).timeout

	# Reveal everything on finish or skip
	label.visible_ratio = 1.0
	is_typing = false
	_skip_requested = false


# Call this to instantly reveal remaining text mid-type
func skip() -> void:
	_skip_requested = true
