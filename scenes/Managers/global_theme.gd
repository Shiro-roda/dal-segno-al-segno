extends Node
# Applies TerminalVector as the global default font for all UI.
# Runs at startup before any scene is loaded.

const FONT_PATH := "res://assets/Fonts/TerminalVector.ttf"

# Static reference so any code-built UI can call GlobalTheme.apply(my_control)
static var theme: Theme

func _ready() -> void:
	var font := load(FONT_PATH) as FontFile
	if font == null:
		push_error("GlobalTheme: failed to load font at " + FONT_PATH)
		return

	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 13

	# Apply to the root viewport — covers Controls in the main scene tree
	get_tree().root.theme = theme

static func apply(control: Control) -> void:
	if theme != null:
		control.theme = theme
