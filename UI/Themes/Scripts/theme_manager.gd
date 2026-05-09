extends Node
## ThemeManager — universal UI colour/font palette distributor.
##
## Two built-in themes:
##   TERMINAL  — phosphor-green CRT aesthetic (as seen in boot_sequence)
##   CLASSIC   — warm red/cream menu aesthetic (the previous default)
##
## Usage:
##   ThemeManager.set_theme(ThemeManager.UITheme.TERMINAL)
##   var col = ThemeManager.palette.bg
##   ThemeManager.theme_changed.connect(_on_theme_changed)

# ── Signal ──────────────────────────────────────────────────────────────────
signal theme_changed(new_theme: int)

# ── Enum ────────────────────────────────────────────────────────────────────
enum UITheme { TERMINAL, CLASSIC }

# ── Palette struct (plain Dictionary) ───────────────────────────────────────
## Keys present in every palette:
##   bg, text, dim, primary, secondary, alert, hover, focus_border
##   key_face, key_edge, key_lit_primary, key_lit_secondary
##   font_mono (Font), font_term (Font)

# ── State ────────────────────────────────────────────────────────────────────
var current_theme : int = UITheme.TERMINAL
var palette       : Dictionary = {}

# ── Font paths ───────────────────────────────────────────────────────────────
const _FONT_MONO := "res://UI/Themes/Fonts/SpaceMono-Bold.ttf"
const _FONT_TERM := "res://UI/Themes/Fonts/TerminalVector.ttf"

var _font_mono : Font = null
var _font_term : Font = null

# ── Palettes ─────────────────────────────────────────────────────────────────
## TERMINAL — phosphor-green CRT (default, matches boot_sequence)
const _PALETTE_TERMINAL := {
	"bg":               Color(0.012, 0.018, 0.012, 1.0),
	"text":             Color(0.92,  0.95,  0.92,  1.0),
	"dim":              Color(0.698, 0.788, 0.697, 0.7),
	"primary":          Color(0.18,  1.00,  0.35,  1.0),   # phosphor green
	"secondary":        Color(1.00,  0.72,  0.08,  1.0),   # amber
	"alert":            Color(1.00,  0.22,  0.18,  1.0),   # red
	"hover":            Color(0.03,  0.08,  0.04,  1.0),   # very dark, near-invisible green tint
	"focus_border":     Color(0.18,  1.00,  0.35,  1.0),   # green
	"key_face":         Color(0.10,  0.13,  0.10,  1.0),
	"key_edge":         Color(0.30,  0.40,  0.30,  0.85),
	"key_lit_primary":  Color(0.08,  0.55,  0.22,  1.0),   # dungeon key tint
	"key_lit_secondary":Color(0.69,  0.365, 0.0,   1.0),   # battle key tint
	"use_mono_font":    true,   # prefer SpaceMono for body text
}

## CLASSIC — warm red/cream (previous menu default)
const _PALETTE_CLASSIC := {
	"bg":               Color(0.04,  0.03,  0.03,  1.0),
	"text":             Color(0.88,  0.83,  0.74,  1.0),
	"dim":              Color(0.45,  0.40,  0.35,  1.0),
	"primary":          Color(0.72,  0.18,  0.18,  1.0),   # dark red accent
	"secondary":        Color(0.92,  0.76,  0.28,  1.0),   # gold
	"alert":            Color(1.00,  0.22,  0.18,  1.0),   # same red
	"hover":            Color(0.20,  0.08,  0.08,  1.0),
	"focus_border":     Color(0.92,  0.76,  0.28,  1.0),   # gold
	"key_face":         Color(0.12,  0.10,  0.10,  1.0),
	"key_edge":         Color(0.40,  0.30,  0.30,  0.85),
	"key_lit_primary":  Color(0.55,  0.12,  0.12,  1.0),
	"key_lit_secondary":Color(0.69,  0.56,  0.0,   1.0),
	"use_mono_font":    false,  # prefer TerminalVector for body text
}

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_font_mono = _try_load(_FONT_MONO)
	_font_term = _try_load(_FONT_TERM)
	# Restore saved preference (falls back to TERMINAL if not set)
	var saved : int = _load_preference()
	_apply_theme(saved, false)


# ── Public API ───────────────────────────────────────────────────────────────

## Switch to the given UITheme and notify all listeners.
func set_theme(theme_id: int) -> void:
	_apply_theme(theme_id, true)


## Convenience — cycle to the next theme in the enum (wraps around).
func cycle_theme() -> void:
	var next := (current_theme + 1) % UITheme.size()
	set_theme(next)


## Return the Font best suited for body/mono text in the current theme.
func body_font() -> Font:
	if palette.get("use_mono_font", true):
		return _font_mono if _font_mono else _font_term
	else:
		return _font_term if _font_term else _font_mono


## Return the Font always used for monospace / terminal output.
func mono_font() -> Font:
	return _font_mono if _font_mono else _font_term


## Return the Font always used for terminal / pixel style labels.
func term_font() -> Font:
	return _font_term if _font_term else _font_mono


## Human-readable name for a UITheme id.
func theme_name(theme_id: int) -> String:
	match theme_id:
		UITheme.TERMINAL: return "TERMINAL"
		UITheme.CLASSIC:  return "CLASSIC"
	return "UNKNOWN"

## Human-readable name for the current theme's sound pack.
func current_sound_pack_name() -> String:
	if Engine.has_singleton("UISounds"):
		return (Engine.get_singleton("UISounds") as Node).current_pack_name()
	return theme_name(current_theme)


# ── Internal ──────────────────────────────────────────────────────────────────

func _apply_theme(theme_id: int, save_pref: bool) -> void:
	current_theme = clampi(theme_id, 0, UITheme.size() - 1)
	palette = _build_palette(current_theme)
	if save_pref:
		_save_preference(current_theme)
	emit_signal("theme_changed", current_theme)


func _build_palette(theme_id: int) -> Dictionary:
	var base : Dictionary
	match theme_id:
		UITheme.TERMINAL: base = _PALETTE_TERMINAL.duplicate()
		UITheme.CLASSIC:  base = _PALETTE_CLASSIC.duplicate()
		_:                base = _PALETTE_TERMINAL.duplicate()
	# Inject live font references
	base["font_mono"] = _font_mono
	base["font_term"] = _font_term
	return base


func _try_load(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path) as Font
	push_warning("ThemeManager: could not load font: " + path)
	return null


# ── Persistence ───────────────────────────────────────────────────────────────
const _PREF_FILE := "user://ui_theme.cfg"
const _SECTION   := "theme"
const _KEY       := "id"

func _save_preference(theme_id: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(_SECTION, _KEY, theme_id)
	var err := cfg.save(_PREF_FILE)
	if err != OK:
		push_warning("ThemeManager: failed to save theme preference (err %d)" % err)


func _load_preference() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(_PREF_FILE) != OK:
		return UITheme.TERMINAL   # default
	return int(cfg.get_value(_SECTION, _KEY, UITheme.TERMINAL))
