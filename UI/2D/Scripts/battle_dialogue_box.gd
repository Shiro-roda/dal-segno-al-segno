extends CanvasLayer
class_name BattleDialogueBox
# Attach this script to a CanvasLayer node in the battle scene.
# Call play_lines(dialogue, run_state) and await it to block until all lines finish.
# While playing, is_playing == true — BattleUI checks this to gate player input.

signal all_done

const SPEAKER_COLORS : Dictionary = {
	"Hue":     Color(1.0,  0.92, 0.2,  1.0),
	"Indra":   Color(0.2,  0.85, 1.0,  1.0),
	"Vritra":  Color(0.851, 0.149, 0.459, 1.0),
	"Kendall": Color(0.88, 0.83, 0.74, 1.0),
	"Helenus": Color(0.55, 0.95, 0.85, 1.0),
}
const DEFAULT_COLOR  := Color(1.02, 0.966, 0.862, 1.0)
const NARRATE_COLOR  := Color(0.769, 0.724, 0.661, 1.0)

const C_BG         := Color(0.04, 0.04, 0.06, 0.96)
const C_BORDER     := Color(0.20, 0.20, 0.28, 1.0)
const FONT_PATH    := "res://UI/Themes/Fonts/SpaceMono-Bold.ttf"
const FONT_ITALIC  := "res://UI/Themes/Fonts/SpaceMono-BoldItalic.ttf"

var _panel        : PanelContainer
var _border_sbox  : StyleBoxFlat
var _speaker_lbl  : Label
var _text_lbl     : RichTextLabel
var _prompt_lbl   : Label
var _typer        : DialogueTyper

var _waiting := false

# True while dialogue is actively showing — BattleUI checks this to gate player commands.
var is_playing := false


func _ready() -> void:
	layer = 10  # render above BattleHUD and BattleUI
	hide()
	_build_ui()
	_typer = DialogueTyper.new()
	add_child(_typer)


func _build_ui() -> void:
	# Dim background
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# Dialogue panel anchored to bottom
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_panel = PanelContainer.new()
	_panel.set_anchor(SIDE_LEFT,   0.0)
	_panel.set_anchor(SIDE_RIGHT,  1.0)
	_panel.set_anchor(SIDE_TOP,    0.72)
	_panel.set_anchor(SIDE_BOTTOM, 1.0)
	_panel.set_offset(SIDE_LEFT,   104)
	_panel.set_offset(SIDE_RIGHT,  -104)
	_panel.set_offset(SIDE_TOP,    0)
	_panel.set_offset(SIDE_BOTTOM, -24)
	_border_sbox = StyleBoxFlat.new()
	_border_sbox.bg_color = C_BG
	_border_sbox.border_color = C_BORDER
	_border_sbox.set_border_width_all(1)
	_border_sbox.border_width_left = 3  # thicker left edge for speaker accent
	_border_sbox.set_content_margin_all(18)
	_border_sbox.content_margin_left = 22
	_panel.add_theme_stylebox_override("panel", _border_sbox)
	anchor.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	var font      : Font = load(FONT_PATH)   if ResourceLoader.exists(FONT_PATH)   else null
	var font_ital : Font = load(FONT_ITALIC) if ResourceLoader.exists(FONT_ITALIC) else null

	_speaker_lbl = Label.new()
	_speaker_lbl.add_theme_font_size_override("font_size", 16)
	if font: _speaker_lbl.add_theme_font_override("font", font)
	_speaker_lbl.add_theme_color_override("font_color", DEFAULT_COLOR)
	_speaker_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_speaker_lbl.add_theme_constant_override("outline_size", 2)
	vbox.add_child(_speaker_lbl)

	_text_lbl = RichTextLabel.new()
	_text_lbl.bbcode_enabled = true
	_text_lbl.scroll_active = false
	_text_lbl.fit_content = true
	if font:      _text_lbl.add_theme_font_override("normal_font",       font)
	if font_ital: _text_lbl.add_theme_font_override("italics_font",      font_ital)
	if font:      _text_lbl.add_theme_font_override("bold_font",         font)
	if font_ital: _text_lbl.add_theme_font_override("bold_italics_font", font_ital)
	_text_lbl.add_theme_font_size_override("normal_font_size",       18)
	_text_lbl.add_theme_font_size_override("italics_font_size",      18)
	_text_lbl.add_theme_font_size_override("bold_font_size",         18)
	_text_lbl.add_theme_font_size_override("bold_italics_font_size", 18)
	_text_lbl.add_theme_color_override("default_color", DEFAULT_COLOR)
	_text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_lbl.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	vbox.add_child(_text_lbl)

	_prompt_lbl = Label.new()
	_prompt_lbl.text = "_"
	if font: _prompt_lbl.add_theme_font_override("font", font)
	_prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt_lbl.add_theme_font_size_override("font_size", 11)
	_prompt_lbl.add_theme_color_override("font_color", Color(0.30, 0.30, 0.40, 0.0))
	vbox.add_child(_prompt_lbl)


# Evaluate whether a DialogueLine's condition passes given the current run state.
static func _check_condition(line: DialogueLine, run_state: RunState) -> bool:
	var cond := line.condition.strip_edges()
	if cond == "" or cond == "always":
		return true
	if run_state == null:
		return false
	var names : Array = run_state.party_members.map(func(m): return m.character.display_name)
	match cond:
		"party_has_hue":    return "Hue"    in names
		"party_has_indra":  return "Indra"  in names
		"party_has_vritra": return "Vritra" in names
		"kendall_low_hp":
			for m in run_state.party_members:
				if m.character.display_name == "Kendall":
					return float(m.current_hp) / float(m.character.base_max_hp) < 0.4
			return false
		"any_low_hp":
			for m in run_state.party_members:
				if float(m.current_hp) / float(m.character.base_max_hp) < 0.4:
					return true
			return false
	return true  # unknown conditions pass by default


# Play all lines that pass their condition. Awaitable.
func play_lines(dialogue: EncounterDialogue, run_state: RunState) -> void:
	if dialogue == null or dialogue.lines.is_empty():
		return
	var filtered : Array = dialogue.lines.filter(
		func(l): return _check_condition(l, run_state)
	)
	if filtered.is_empty():
		return

	is_playing = true
	show()
	for line in filtered:
		await _show_line(line)
	hide()
	is_playing = false
	emit_signal("all_done")


func _show_line(line: DialogueLine) -> void:
	var has_speaker := line.speaker.strip_edges() != ""
	var speaker_col : Color = SPEAKER_COLORS.get(line.speaker, DEFAULT_COLOR)
	if has_speaker:
		_speaker_lbl.text = line.speaker.to_upper()
		_speaker_lbl.add_theme_color_override("font_color", speaker_col)
		_speaker_lbl.visible = true
	else:
		_speaker_lbl.visible = false
	# Tint the left border to the speaker's colour
	if _border_sbox:
		_border_sbox.border_color = speaker_col if has_speaker else C_BORDER

	var text_color : Color = SPEAKER_COLORS.get(line.speaker, NARRATE_COLOR if not has_speaker else DEFAULT_COLOR)
	_text_lbl.add_theme_color_override("default_color", text_color)
	if line.speaker == "Helenus":
		if _text_lbl.material == null:
			var mat := ShaderMaterial.new()
			mat.shader = load("res://Shaders/flicker_text.gdshader")
			mat.set_shader_parameter("text_color", Vector3(1.0, 1.0, 1.0))
			mat.set_shader_parameter("flicker_speed", 1.0)
			mat.set_shader_parameter("uv_aspect", 10.0)
			mat.set_shader_parameter("pixel_size", 5.0)
			mat.set_shader_parameter("flicker_intensity", 0.14)
			mat.set_shader_parameter("shadow_color", Vector3(0.0, 0.0, 0.0))
			mat.set_shader_parameter("shadow_pixel_steps", Vector2(0.0, 0.0))
			_text_lbl.material = mat
	else:
		_text_lbl.material = null

	var full_text := line.text.replace("[br]", "\n")
	var use_typewriter := line.typewriter
	var spd := line.typewriter_speed if line.typewriter_speed > 0.0 \
			else DialogueTyper.speed_for_speaker(line.speaker)
	var snd : AudioStream = line.typing_sound  # may be null

	if use_typewriter:
		await get_tree().create_timer(0.1, false).timeout
		_waiting = true
		await _typer.type_into(_text_lbl, full_text, spd, snd)
		_start_cursor_blink()
		while _waiting:
			await get_tree().process_frame
		_stop_cursor_blink()
	else:
		_text_lbl.clear()
		_text_lbl.append_text(full_text)
		_waiting = true
		await get_tree().create_timer(0.15, false).timeout
		_start_cursor_blink()
		while _waiting:
			await get_tree().process_frame
		_stop_cursor_blink()


var _cursor_tween : Tween = null

func _start_cursor_blink() -> void:
	if _prompt_lbl == null:
		return
	if is_instance_valid(_cursor_tween):
		_cursor_tween.kill()
	_prompt_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.75, 1.0))
	_cursor_tween = create_tween().set_loops()
	_cursor_tween.tween_property(_prompt_lbl, "modulate:a", 0.0, 0.45)
	_cursor_tween.tween_property(_prompt_lbl, "modulate:a", 1.0, 0.45)

func _stop_cursor_blink() -> void:
	if is_instance_valid(_cursor_tween):
		_cursor_tween.kill()
		_cursor_tween = null
	if _prompt_lbl:
		_prompt_lbl.modulate.a = 0.0


func _input(event: InputEvent) -> void:
	if not is_playing or not _waiting:
		return
	var confirmed : bool = event.is_action_pressed("ui_accept") \
		or event.is_action_pressed("ui_select") \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not confirmed:
		return
	get_viewport().set_input_as_handled()
	if _typer and _typer.is_typing:
		# First confirm: skip typewriter, reveal full text
		_typer.skip()
	else:
		# Second confirm (or no typewriter): advance to next line
		_waiting = false
