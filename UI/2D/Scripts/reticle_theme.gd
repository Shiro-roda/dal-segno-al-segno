extends Resource
class_name ReticleTheme
## Defines the colour scheme for BattleReticleUI.
##
## VAPORWAVE (default): hue-cycling neon palette, everything cycles over time.
## TACTICAL:            fixed colours — enemies red, allies green, skills white.
##
## Assign a ReticleTheme to BattleReticleUI.theme before calling open().

enum Mode { VAPORWAVE, TACTICAL }

@export var mode : Mode = Mode.TACTICAL

# ── TACTICAL mode palette ─────────────────────────────────────────────────────
@export var skill_color  : Color = Color(1.0, 1.0, 1.0, 1.0)   # white
@export var enemy_color  : Color = Color(1.0, 0.18, 0.18, 1.0) # red
@export var ally_color   : Color = Color(0.18, 1.0, 0.35, 1.0) # green
@export var part_color   : Color = Color(1.0, 0.65, 0.10, 1.0) # amber

# ── VAPORWAVE mode palette ────────────────────────────────────────────────────
# Base hues for each slot; cycling is applied on top of these at runtime.
@export var neon_palette : Array[Color] = [
	Color(0.00, 1.00, 0.85, 1.0),   # cyan
	Color(1.00, 0.10, 0.70, 1.0),   # magenta
	Color(0.15, 1.00, 0.15, 1.0),   # green
	Color(1.00, 0.55, 0.00, 1.0),   # orange
	Color(0.45, 0.15, 1.00, 1.0),   # violet
	Color(1.00, 1.00, 0.10, 1.0),   # yellow
]

## Return the base neon colour for a given entry, given its data_type and
## palette slot index. In TACTICAL mode returns a fixed colour; in VAPORWAVE
## mode returns the cycling palette entry.
func get_neon(data_type: String, palette_idx: int) -> Color:
	if mode == Mode.TACTICAL:
		match data_type:
			"skill":  return skill_color
			"enemy":  return enemy_color
			"ally":   return ally_color
			"part":   return part_color
		return Color.WHITE
	# VAPORWAVE
	return neon_palette[palette_idx % neon_palette.size()]

## In TACTICAL mode, colour cycling is suppressed — hue_drift stays fixed.
func allow_hue_cycle() -> bool:
	return mode == Mode.VAPORWAVE
