extends CanvasLayer
class_name BattleIntroSplash
# Full-screen battle intro splash. Shows each SplashLine one at a time,
# centred, large, with constant sync-jitter CRT shader.
# Speaker field is used only for colour; the name is never displayed.
# Auto-advances through all lines with no player input required.
# Await play(lines) to block until all lines have finished.

# ── Timing ────────────────────────────────────────────────────────────────────
var HOLD_TIME := 3.0# seconds each card is held on screen
const FLASH_IN_TIME := 0.02   # black gap between cards

# ── Text ──────────────────────────────────────────────────────────────────────
const FONT_SIZE := 106
const LABEL_WIDTH   := 1240# custom_minimum_size.x; text wraps within this

# ── Shadow ────────────────────────────────────────────────────────────────────
# Shadow colour is computed per-speaker as the complementary of the text colour.
# These constants control the shadow independently of that.
const SHADOW_ALPHA:= 0.92   # opacity of the drop shadow
const SHADOW_OFFSET_X := 3 # pixels right
const SHADOW_OFFSET_Y := 3 # pixels down
const SHADOW_OUTLINE_SIZE := 4# softness / spread

# ── Background ────────────────────────────────────────────────────────────────
const BG_COLOR := Color(0.03, 0.02, 0.02, 0.88)

# ── CRT shader uniforms ───────────────────────────────────────────────────────
const SHADER_SYNC_JITTER_PX := 1.5# max horizontal sync-roll in pixels
const SHADER_SYNC_SPEED := 197.0   # how many times per second the roll snaps
const SHADER_INTERLACE_PX   := 0.5# per-scanline interlace split in pixels
const SHADER_NOISE_AMOUNT   := 0.035   # fraction of pixels randomly dark per frame

# ── Colours ───────────────────────────────────────────────────────────────────
const SPEAKER_COLORS : Dictionary = {
	"Hue":     Color(1.0,  0.92, 0.2,  1.0),
	"Indra":   Color(0.532, 1.951, 2.375, 1.0),
	"Vritra":  Color(2.871, 0.0, 0.904, 1.0),
	"Kendall": Color(0.88, 0.83, 0.74, 1.0),
	"Huginn":  Color(0.992, 0.749, 0.314, 1.0),
	"Helenus": Color(0.957, 0.867, 0.0),
}
const DEFAULT_COLOR := Color(0.0, 0.0, 0.0, 1.0)

const OUTLINE_COLOR := Color(1,1,1,1)
const OUTLINE_SIZE  := 10

const SPEAKER_FONTS : Dictionary = {
	"Kendall": "res://UI/Themes/Fonts/SpaceMono-Bold.ttf",
	"Hue":     "res://UI/Themes/Fonts/Lora/Lora-VariableFont_wght.ttf",
	"Indra":   "res://UI/Themes/Fonts/Josefin_Slab/JosefinSlab-VariableFont_wght.ttf",
	"Vritra":  "res://UI/Themes/Fonts/Cormorant_Garamond/CormorantGaramond-Italic-VariableFont_wght.ttf",
	"Helenus": "res://UI/Themes/Fonts/SpaceMono-Regular.ttf",
}
const DEFAULT_FONT := "res://UI/Themes/Fonts/SpaceMono-Italic.ttf"

# ── Internals ─────────────────────────────────────────────────────────────────
var _label      : Label
var _mat_crt    : ShaderMaterial  # chatter_crt — used for all non-Helenus lines
var _mat_flicker: ShaderMaterial  # flicker_text_2d — used for Helenus lines
var _blocker    : ColorRect


func _ready() -> void:
	layer = 30
	hide()
	_build_ui()


func _build_ui() -> void:
	# Input blocker — eats all events while splash is visible
	_blocker = ColorRect.new()
	_blocker.color = Color(0, 0, 0, 0)
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_blocker)

	# Dark background
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Centre container
	var anchor := CenterContainer.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	# Main label
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode= TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size  = Vector2(LABEL_WIDTH, 0)
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	# Shadow is handled entirely inside the shader; no theme overrides needed
	anchor.add_child(_label)

	# CRT shader — default for all speakers
	_mat_crt = ShaderMaterial.new()
	_mat_crt.shader = load("res://Shaders/chatter_crt.gdshader")
	_mat_crt.set_shader_parameter("sync_jitter_px", SHADER_SYNC_JITTER_PX)
	_mat_crt.set_shader_parameter("sync_speed",     SHADER_SYNC_SPEED)
	_mat_crt.set_shader_parameter("interlace_px",   SHADER_INTERLACE_PX)
	_mat_crt.set_shader_parameter("noise_amount",   SHADER_NOISE_AMOUNT)
	_mat_crt.set_shader_parameter("font_color",     DEFAULT_COLOR)
	_mat_crt.set_shader_parameter("shadow_color",   Color(0.0, 0.0, 0.0, SHADOW_ALPHA))
	_mat_crt.set_shader_parameter("shadow_offset",  Vector2(SHADOW_OFFSET_X, SHADOW_OFFSET_Y))

	# Flicker shader — Helenus only
	_mat_flicker = ShaderMaterial.new()
	_mat_flicker.shader = load("res://Shaders/flicker_text_2d.gdshader")
	_mat_flicker.set_shader_parameter("flicker_speed",     0.2)
	_mat_flicker.set_shader_parameter("flicker_intensity", 0.24)
	_mat_flicker.set_shader_parameter("pixel_size",        50.0)
	_mat_flicker.set_shader_parameter("shadow_color",      Color(0.0, 0.0, 0.0, SHADOW_ALPHA))
	_mat_flicker.set_shader_parameter("shadow_pixel_steps",Vector2(0.0, 0.0))
	_mat_flicker.set_shader_parameter("interlace_jitter",  0.0)

	_label.material = _mat_crt


func play(lines: Array, run_state: RunState = null) -> void:
	if lines.is_empty():
		return
	show()
	for entry in lines:
		if entry is SplashLine:
			if entry.text.strip_edges() == "":
				continue
			await _show_line(entry.text, entry.speaker)
		elif entry is String:
			if entry.strip_edges() == "":
				continue
			await _show_line(entry, "")
	hide()
	_label.text = ""


func _show_line(text: String, speaker: String) -> void:
	var col : Color = SPEAKER_COLORS.get(speaker, DEFAULT_COLOR).clamp()
	

	# Font
	var font_path : String = SPEAKER_FONTS.get(speaker, DEFAULT_FONT)
	_label.add_theme_font_override("font", load(font_path))

	_label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	_label.add_theme_constant_override("outline_size", OUTLINE_SIZE)

	if speaker == "Helenus":
		HOLD_TIME = 6.0
		_mat_flicker.set_shader_parameter("font_color",   Color(col.r, col.g, col.b, 1.0))
		_mat_flicker.set_shader_parameter("seed_offset",  randf_range(0.0, 1000.0))
		_label.material = _mat_flicker
	else:
		HOLD_TIME = 3.0
		var shadow_col := Color(1.0 - col.r, 1.0 - col.g, 1.0 - col.b, SHADOW_ALPHA)
		_mat_crt.set_shader_parameter("font_color",    col)
		_mat_crt.set_shader_parameter("shadow_color",  shadow_col)
		_mat_crt.set_shader_parameter("shadow_offset", Vector2(SHADOW_OFFSET_X, SHADOW_OFFSET_Y))
		_label.material = _mat_crt

	_label.text = text
	_label.modulate = Color(1, 1, 1, 0)
	await get_tree().process_frame   # let label lay out before flashing in
	_label.modulate = Color(1, 1, 1, 1)
	await get_tree().create_timer(HOLD_TIME, false).timeout
	_label.modulate = Color(1, 1, 1, 0)
	await get_tree().create_timer(FLASH_IN_TIME, false).timeout
