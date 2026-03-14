extends CanvasLayer
class_name WorldDialogueBox
# Reuses the same DialogueLine / EncounterDialogue resources as battle dialogue.
# Attach to a CanvasLayer node (layer 10) in any world scene.
# Call play_lines(dialogue) and await it — freezes player input until done.

signal all_done

const SPEAKER_COLORS : Dictionary = {
	"Hue":    Color(1.0,  0.92, 0.2,  1.0),
	"Indra":  Color(0.2,  0.85, 1.0,  1.0),
	"Vritra": Color(0.851, 0.149, 0.459, 1.0),
	"Kendall":Color(0.88, 0.83, 0.74, 1.0),
}
const DEFAULT_COLOR := Color(1.0, 0.966, 0.862, 1.0)
const NARRATE_COLOR := Color(0.769, 0.724, 0.661, 1.0)
const C_BG     := Color(0.06, 0.05, 0.04, 0.92)
const C_BORDER := Color(0.35, 0.28, 0.22, 1.0)

var _panel       : PanelContainer
var _speaker_lbl : Label
var _text_lbl    : RichTextLabel
var _prompt_lbl  : Label
var _typer       : DialogueTyper

var _waiting   := false
var is_playing := false


func _ready() -> void:
	layer = 10
	hide()
	_build_ui()
	_typer = DialogueTyper.new()
	add_child(_typer)


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

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
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = C_BG
	sbox.border_color = C_BORDER
	sbox.set_border_width_all(1)
	sbox.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", sbox)
	anchor.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	_speaker_lbl = Label.new()
	_speaker_lbl.add_theme_font_size_override("font_size", 22)
	_speaker_lbl.add_theme_color_override("font_color", DEFAULT_COLOR)
	_speaker_lbl.modulate = Color(1.0, 1.0, 1.0, 0.6)
	_speaker_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_speaker_lbl.add_theme_constant_override("shadow_offset_y", 1)
	_speaker_lbl.add_theme_constant_override("shadow_outline_size", 4)
	vbox.add_child(_speaker_lbl)

	_text_lbl = RichTextLabel.new()
	_text_lbl.bbcode_enabled = true
	_text_lbl.scroll_active = false
	_text_lbl.fit_content = true
	_text_lbl.add_theme_font_size_override("normal_font_size", 22)
	_text_lbl.add_theme_font_size_override("italics_font_size", 22)
	_text_lbl.add_theme_font_size_override("bold_font_size", 22)
	_text_lbl.add_theme_font_size_override("bold_italics_font_size", 22)
	_text_lbl.add_theme_color_override("default_color", DEFAULT_COLOR)
	_text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_lbl.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	vbox.add_child(_text_lbl)

	_prompt_lbl = Label.new()
	_prompt_lbl.text = "[ confirm ]"
	_prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt_lbl.add_theme_font_size_override("font_size", 11)
	_prompt_lbl.add_theme_color_override("font_color", Color(0.45, 0.40, 0.35, 1.0))
	vbox.add_child(_prompt_lbl)


# Play an EncounterDialogue resource. run_state may be null for world dialogue
# (conditions that reference party membership will simply fail gracefully).
func play_lines(dialogue: EncounterDialogue, run_state: RunState = null) -> void:
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
	return true


func _show_line(line: DialogueLine) -> void:
	var has_speaker := line.speaker.strip_edges() != ""
	if has_speaker:
		_speaker_lbl.text = line.speaker.to_upper()
		var c : Color = SPEAKER_COLORS.get(line.speaker, DEFAULT_COLOR)
		_speaker_lbl.add_theme_color_override("font_color", c)
		var shadow := Color(1.0 - c.r, 1.0 - c.g, 1.0 - c.b, 0.85)
		_speaker_lbl.add_theme_color_override("font_shadow_color", shadow)
		_speaker_lbl.visible = true
	else:
		_speaker_lbl.visible = false

	var text_color : Color = SPEAKER_COLORS.get(line.speaker, NARRATE_COLOR if not has_speaker else DEFAULT_COLOR)
	_text_lbl.add_theme_color_override("default_color", text_color)

	var full_text := line.text.replace("[br]", "\n")
	var use_typewriter := line.typewriter
	var spd := line.typewriter_speed if line.typewriter_speed > 0.0 \
			else DialogueTyper.speed_for_speaker(line.speaker)
	var snd : AudioStream = line.typing_sound

	if use_typewriter:
		await get_tree().create_timer(0.1, false).timeout
		_waiting = true
		await _typer.type_into(_text_lbl, full_text, spd, snd)
		while _waiting:
			await get_tree().process_frame
	else:
		_text_lbl.clear()
		_text_lbl.append_text(full_text)
		_waiting = true
		await get_tree().create_timer(0.15, false).timeout
		while _waiting:
			await get_tree().process_frame


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
		_typer.skip()
	else:
		_waiting = false
