extends CanvasLayer
## BattleSubtitles — live broadcast-style subtitle ticker.
##
## Each chatter call adds a new line at the bottom of a stacked column.
## Lines stack upward as new ones arrive (newest at bottom, oldest at top).
## Each line has its own lifetime — it fades out after HOLD_TIME independently.
## Up to MAX_LINES are shown simultaneously; the oldest is immediately dropped
## when the cap is hit, matching the battle log's behaviour.
##
## Layout: full screen width, lower 26% of the screen.
## Each line: [SPEAKER NAME chip]  [message text with CRT shader]

const FONT_PATH      := "res://UI/Themes/Fonts/TerminalVector.ttf"
const SHADER_PATH    := "res://Shaders/chatter_crt.gdshader"
const FADE_IN_TIME   := 0.01
const FADE_OUT_TIME  := 0.01
const HOLD_TIME      := 3.2
const MAX_LINES      := 5
const FONT_SIZE_MSG  := 20
const LINE_SEP       := 6
const C_DEFAULT_SPKR := Color(0.65, 0.55, 0.42, 1.0)

const FALLBACK_COLORS : Dictionary = {
	"Kendall": Color(0.92, 0.72, 0.28, 1.0),
	"Hue":     Color(0.50, 0.82, 1.00, 1.0),
	"Indra":   Color(0.50, 0.88, 0.55, 1.0),
	"Vritra":  Color(0.78, 0.38, 0.95, 1.0),
}

var _font   : Font
var _shader : Shader
var _vbox   : VBoxContainer


func _ready() -> void:
	layer = 50
	add_to_group("battle_subtitles")
	_font   = load(FONT_PATH)   if ResourceLoader.exists(FONT_PATH)   else ThemeDB.fallback_font
	_shader = load(SHADER_PATH) if ResourceLoader.exists(SHADER_PATH) else null
	_build_ui()


# ── Public API ────────────────────────────────────────────────────────────────

func push_chatter(msg: String, speaker_name: String = "") -> void:
	if msg.strip_edges() == "" or msg == " ":
		return

	# Drop oldest if at capacity
	while _vbox.get_child_count() >= MAX_LINES:
		_vbox.get_child(0).free()

	var spkr_col := _resolve_speaker_color(speaker_name)

	# Wrap in a plain container so the tween animates a shader-free node,
	# matching the old row pattern (parent modulate propagates to child label).
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, FONT_SIZE_MSG + 6)
	row.modulate = Color(1, 1, 1, 0)
	_vbox.add_child(row)

	# Single label — just the message, in the speaker's colour
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_font_size_override("font_size", FONT_SIZE_MSG)
	lbl.add_theme_color_override("font_color", spkr_col)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font:
		lbl.add_theme_font_override("font", _font)
	if _shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("font_color", spkr_col)
		mat.set_shader_parameter("sync_jitter_px", 2.5)
		mat.set_shader_parameter("noise_amount",   0.055)
		lbl.material = mat
	row.add_child(lbl)

	var tw := row.create_tween()
	tw.tween_property(row, "modulate", Color(1, 1, 1, 1), FADE_IN_TIME)
	tw.tween_interval(HOLD_TIME)
	tw.tween_property(row, "modulate", Color(1, 1, 1, 0), FADE_OUT_TIME)
	tw.tween_callback(func():
		if is_instance_valid(row):
			row.queue_free())


func clear() -> void:
	for c in _vbox.get_children():
		c.free()


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var base := Control.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", LINE_SEP)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Full width, lower 26% of screen, lines aligned to bottom (newest at bottom)
	_vbox.anchor_left   = 0.0
	_vbox.anchor_right  = 1.0
	_vbox.anchor_top    = 0.73
	_vbox.anchor_bottom = 0.92
	_vbox.offset_left   = 32.0
	_vbox.offset_right  = -32.0
	_vbox.offset_top    = 0.0
	_vbox.offset_bottom = 0.0
	_vbox.alignment = BoxContainer.ALIGNMENT_END
	base.add_child(_vbox)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _resolve_speaker_color(speaker_name: String) -> Color:
	if speaker_name == "":
		return C_DEFAULT_SPKR
	var actors := get_tree().get_nodes_in_group("battle_actor")
	for a in actors:
		if (a as BattleActor).display_name == speaker_name:
			var pm = (a as BattleActor).party_member
			if pm != null and pm.character != null:
				var col : Color = pm.character.theme_color
				if col.r != 1.0 or col.g != 1.0 or col.b != 1.0:
					return col
	return FALLBACK_COLORS.get(speaker_name, C_DEFAULT_SPKR)
