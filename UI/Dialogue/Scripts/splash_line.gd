extends Resource
class_name SplashLine

# Text to display full-screen.
@export var text : String = ""

# Speaker name used only for colour styling (name is never shown).
# Use the same values as DialogueLine.speaker:
# "Hue", "Indra", "Vritra", "Kendall", or "" for white.
@export var speaker : String = ""

# If true, the splash waits for player input (ui_accept / left-click) before
# advancing, instead of auto-advancing after HOLD_TIME.
@export var wait_for_input : bool = false
