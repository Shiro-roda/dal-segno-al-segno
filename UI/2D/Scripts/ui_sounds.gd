extends Node
## UISounds — per-theme UI sound effects, integrated with ThemeManager.
##
## Sound packs are defined per UITheme.  Each pack maps action names to
## AudioStream resources.  Actions are intentionally high-level so themes
## can swap in different sonic textures without touching call sites.
##
## Usage (from any script):
##   UISounds.play("confirm")
##   UISounds.play("navigate")
##   UISounds.play("menu_open")
##   UISounds.play("menu_close")
##   UISounds.play("tab_switch")
##   UISounds.play("boot_beep")
##   UISounds.play("boot_warning")
##   UISounds.play("boot_error")
##   UISounds.play("boot_complete")

# ── Sound pack definition ─────────────────────────────────────────────────────
## A SoundPack maps action names -> AudioStream.
## Packs are built lazily from path definitions below.
class SoundPack:
	var name     : String = ""
	var sounds   : Dictionary = {}  # action -> AudioStream

	func play(action: String, player: AudioStreamPlayer) -> void:
		if sounds.has(action) and sounds[action] != null:
			player.stream = sounds[action]
			player.play()

# ── Per-theme path tables ─────────────────────────────────────────────────────
## Each entry maps action -> res:// path.
## Files that don't exist yet are silently skipped (no crash).
## Add new sound files to Audio/Assets/UI/ and reference them here.
const _PACK_DEFS := {
	# ThemeManager.UITheme.TERMINAL (0)
	0: {
		"name": "TERMINAL",
		"sounds": {
			"confirm":      "res://Audio/Assets/UI/terminal_confirm.wav",
			"navigate":     "res://Audio/Assets/UI/terminal_navigate.wav",
			"menu_open":    "res://Audio/Assets/UI/terminal_open.wav",
			"menu_close":   "res://Audio/Assets/UI/terminal_close.wav",
			"tab_switch":   "res://Audio/Assets/UI/terminal_tab.wav",
			"boot_beep":    "res://Audio/Assets/UI/terminal_beep.wav",
			"boot_warning": "res://Audio/Assets/UI/terminal_warning.wav",
			"boot_error":   "res://Audio/Assets/UI/terminal_error.wav",
			"boot_complete":"res://Audio/Assets/UI/terminal_complete.wav",
		}
	},
	# ThemeManager.UITheme.CLASSIC (1)
	1: {
		"name": "CLASSIC",
		"sounds": {
			"confirm":      "res://Audio/Assets/UI/classic_confirm.wav",
			"navigate":     "res://Audio/Assets/UI/classic_navigate.wav",
			"menu_open":    "res://Audio/Assets/UI/classic_open.wav",
			"menu_close":   "res://Audio/Assets/UI/classic_close.wav",
			"tab_switch":   "res://Audio/Assets/UI/classic_tab.wav",
			"boot_beep":    "res://Audio/Assets/UI/terminal_beep.wav",  # reuse terminal for boot
			"boot_warning": "res://Audio/Assets/UI/terminal_warning.wav",
			"boot_error":   "res://Audio/Assets/UI/terminal_error.wav",
			"boot_complete":"res://Audio/Assets/UI/terminal_complete.wav",
		}
	},
}

# ── State ─────────────────────────────────────────────────────────────────────
var _packs  : Dictionary = {}  # theme_id -> SoundPack (loaded lazily)
var _player : AudioStreamPlayer = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Dedicated audio player on the UI bus
	_player = AudioStreamPlayer.new()
	_player.bus = "UI" if AudioServer.get_bus_index("UI") >= 0 else "Master"
	add_child(_player)

	ThemeManager.theme_changed.connect(_on_theme_changed)
	# Warm up the current theme's pack
	_get_pack(ThemeManager.current_theme)

# ── Public API ────────────────────────────────────────────────────────────────

## Play a UI sound action for the current theme.
## If the sound file doesn't exist yet, does nothing gracefully.
func play(action: String) -> void:
	var pack := _get_pack(ThemeManager.current_theme)
	if pack:
		pack.play(action, _player)

## Play a UI sound on a specific AudioStreamPlayer (e.g. for spatial UI).
func play_on(action: String, player: AudioStreamPlayer) -> void:
	var pack := _get_pack(ThemeManager.current_theme)
	if pack:
		pack.play(action, player)

## Check whether a sound exists for the given action in the current theme.
func has(action: String) -> bool:
	var pack := _get_pack(ThemeManager.current_theme)
	return pack != null and pack.sounds.has(action) and pack.sounds[action] != null

## The human-readable name of the current sound pack.
func current_pack_name() -> String:
	var pack := _get_pack(ThemeManager.current_theme)
	return pack.name if pack else "NONE"

# ── Internal ──────────────────────────────────────────────────────────────────
func _get_pack(theme_id: int) -> SoundPack:
	if _packs.has(theme_id):
		return _packs[theme_id]
	# Build and cache
	if not _PACK_DEFS.has(theme_id):
		return null
	var def : Dictionary = _PACK_DEFS[theme_id]
	var pack := SoundPack.new()
	pack.name = def.get("name", "UNKNOWN")
	var sound_defs : Dictionary = def.get("sounds", {})
	for action in sound_defs:
		var path : String = sound_defs[action]
		if ResourceLoader.exists(path):
			pack.sounds[action] = load(path) as AudioStream
		else:
			pack.sounds[action] = null  # placeholder — no crash
	_packs[theme_id] = pack
	return pack

func _on_theme_changed(_id: int) -> void:
	# Warm up the new theme pack
	_get_pack(_id)
