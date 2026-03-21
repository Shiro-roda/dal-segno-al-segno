extends CanvasLayer
class_name BattleHUD

@onready var player_container: HBoxContainer = $"Player Status/PlayerContainer"
@onready var target_info = $TargetInfo/TargetInfoBox
@onready var _queue_vbox: VBoxContainer = $BattleLog/HBoxContainer/TurnQueue
@onready var vbox: VBoxContainer = $BattleLog/HBoxContainer/Log


const ACTOR_PANEL = preload("res://UI/2D/Scenes/actor_panel.tscn")

const LOG_MAX_LINES      = 6
const LOG_FADE_DURATION  = 0.4   # seconds each log entry fades in
const LOG_LINE_SPACING   = 6     # extra pixels between log entries
const CHATTER_DURATION = 2.6   # seconds a chatter line stays visible
const QUEUE_STEPS = 6                  # how many acts ahead to project

var player_panels := {}
var enemy_panels := {}

# Log node refs - created at runtime if not found in scene
var _log_panel      : PanelContainer
var _log_label      : RichTextLabel
var _log_vbox       : VBoxContainer
var _chatter_label  : Label
var _chatter_mat    : ShaderMaterial
var _log_lines      : Array = []

# Turn order queue strip
var _queue_labels : Array = []

# Augur enemy intel panel - built lazily on first augur call
var _augur_panel   : PanelContainer
var _augur_labels  : Dictionary = {}  # actor -> VBoxContainer of labels


func _ready_log() -> void:
	# Only build once - guard against multiple setup() calls
	if _log_vbox != null:
		return
	# vbox is already in the scene ($BattleLog/HBoxContainer/Log); just configure it
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL

	_chatter_label = Label.new()
	_chatter_label.name = "ChatterLabel"
	_chatter_label.add_theme_font_size_override("font_size", 18)
	_chatter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_chatter_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chatter_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chatter_label.text = ""
	_chatter_mat = ShaderMaterial.new()
	_chatter_mat.shader = load("res://Shaders/chatter_crt.gdshader")
	_chatter_label.material = _chatter_mat
	vbox.add_child(_chatter_label)
	
	_log_vbox = VBoxContainer.new()
	_log_vbox.name = "LogVBox"
	_log_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_vbox.add_theme_constant_override("separation", LOG_LINE_SPACING)
	vbox.add_child(_log_vbox)
	


	


func _ready_queue() -> void:
	if not _queue_labels.is_empty():
		return  # already built

	_queue_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_vbox.add_theme_constant_override("separation", 2)

	for i in range(QUEUE_STEPS):
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.clip_text = true
		_queue_vbox.add_child(lbl)
		_queue_labels.append(lbl)


func refresh_queue(manager) -> void:
	if _queue_labels.is_empty():
		return
	var queue : Array = manager.get_projected_queue(QUEUE_STEPS)
	var active = manager.active_player_actor
	for i in range(_queue_labels.size()):
		var lbl : Label = _queue_labels[i]
		if i < queue.size():
			var entry : Dictionary = queue[i]
			var actor : BattleActor = entry["actor"]
			var tempo : float = entry["tempo"]
			# Two-line format: name on top, tempo value below
			lbl.text = actor.name + "\n" + str(int(tempo))
			if actor == active and i == 0:
				lbl.modulate = Color(1.0, 0.95, 0.3, 1.0)   # gold - acting now
			elif actor.team == BattleActor.Team.PLAYER:
				lbl.modulate = Color(0.75, 0.95, 1.0, 1.0)  # pale blue - ally
			else:
				lbl.modulate = Color(1.0, 0.55, 0.55, 1.0)  # pale red - enemy
		else:
			lbl.text = ""


func push_log(msg: String) -> void:
	_log_lines.push_front(msg)
	if _log_lines.size() > LOG_MAX_LINES:
		_log_lines.resize(LOG_MAX_LINES)
	if _log_vbox == null:
		return
	# Remove oldest entries immediately (free(), not queue_free()) so
	# get_child_count() reflects the removal right away — queue_free() is
	# deferred and would cause an infinite loop here.
	while _log_vbox.get_child_count() >= LOG_MAX_LINES:
		_log_vbox.get_child(_log_vbox.get_child_count() - 1).free()
	# Create new label, insert at top
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.modulate = Color(1, 1, 1, 0)
	_log_vbox.add_child(lbl)
	_log_vbox.move_child(lbl, 0)
	# Fade in
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "modulate", Color(1, 1, 1, 1), LOG_FADE_DURATION)


const CHATTER_COLORS : Dictionary = {
	"Hue":    Color(3.337, 3.085, 0.765, 1.0),  # yellow
	"Indra":  Color(0.613, 2.318, 2.708, 1.0),  # cerulean
	"Vritra": Color(2.871, 0.0, 0.904, 1.0),
}
const CHATTER_DEFAULT := Color(0.88, 0.83, 0.74, 1.0)

var _chatter_gen : int = 0  # incremented each push; callbacks ignore stale gens

func push_chatter(msg: String, speaker: String = "") -> void:
	if _chatter_label == null:
		return
	# Bump generation — any timer from a previous call will see a stale gen
	# and do nothing when it fires.  SceneTreeTimer has no cancel().
	_chatter_gen += 1
	var my_gen := _chatter_gen
	var col : Color = CHATTER_COLORS.get(speaker, CHATTER_DEFAULT)
	_chatter_mat.set_shader_parameter("font_color", col)
	_chatter_label.text = " " + msg
	get_tree().create_timer(CHATTER_DURATION, false).timeout.connect(func():
		if my_gen == _chatter_gen and is_instance_valid(_chatter_label):
			_chatter_label.text = ""
	, CONNECT_ONE_SHOT)

const HUD_BG     := Color(0.08, 0.07, 0.06, 0.96)
const HUD_BORDER := Color(0.35, 0.28, 0.22, 1.0)
const HUD_ACCENT := Color(0.52, 0.42, 0.28, 1.0)
const HUD_TEXT   := Color(0.88, 0.83, 0.74, 1.0)
const HUD_DIM    := Color(0.45, 0.40, 0.35, 1.0)
const HUD_FONT   := "res://UI/Themes/Fonts/TerminalVector.ttf"

func _make_hud_panel_style(accent_bottom: bool = false, accent_top: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = HUD_BG
	s.set_border_width_all(0)
	if accent_bottom:
		s.border_width_bottom = 2
		s.border_color = HUD_ACCENT
	elif accent_top:
		s.border_width_top = 2
		s.border_color = HUD_ACCENT
	s.set_content_margin_all(10)
	return s

func _apply_hud_style() -> void:
	var font : Font = load(HUD_FONT) if ResourceLoader.exists(HUD_FONT) else ThemeDB.fallback_font

	# Player Status: accent on bottom (the seam)
	var player_status = get_node_or_null("Player Status")
	if player_status is PanelContainer:
		player_status.add_theme_stylebox_override("panel", _make_hud_panel_style(true, false))

	# BattleLog: accent on top (the seam)
	var battle_log = get_node_or_null("BattleLog")
	if battle_log is PanelContainer:
		battle_log.add_theme_stylebox_override("panel", _make_hud_panel_style(false, true))

	# TargetInfo: left accent border (floating card)
	var target_info_panel = get_node_or_null("TargetInfo")
	if target_info_panel is PanelContainer:
		var ti_sbox := StyleBoxFlat.new()
		ti_sbox.bg_color = HUD_BG
		ti_sbox.set_border_width_all(0)
		ti_sbox.border_width_left = 2
		ti_sbox.border_color = HUD_ACCENT
		ti_sbox.set_content_margin_all(10)
		target_info_panel.add_theme_stylebox_override("panel", ti_sbox)
		target_info_panel.add_theme_stylebox_override("panel", _make_hud_panel_style(false, true))

	# Style all labels in the HUD
	for lbl in _find_labels(get_children()):
		lbl.add_theme_color_override("font_color", HUD_TEXT)
		lbl.add_theme_font_override("font", font)

	# Queue labels use dim colour
	for lbl in _queue_labels:
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_color_override("font_color", HUD_DIM)

	# TargetInfo HPBar tinted accent
	var hpbar = get_node_or_null("TargetInfo/TargetInfoBox/HPBar")
	if hpbar:
		hpbar.modulate = HUD_ACCENT


func _find_labels(nodes: Array) -> Array:
	var out := []
	for n in nodes:
		if n is Label: out.append(n)
		out.append_array(_find_labels(n.get_children()))
	return out

func setup(actor_list : Array):
	_ready_log()
	_ready_queue()
	_apply_hud_style()
	# Clear log entries and state from any previous battle
	_log_lines.clear()
	if _log_vbox:
		for c in _log_vbox.get_children():
			c.free()  # free() not queue_free() — must be synchronous

	for c in player_container.get_children():
		c.queue_free()

	for actor in actor_list:
		# Wire battle log and chatter signals for every actor
		if actor.has_signal("battle_log") and not actor.battle_log.is_connected(push_log):
			actor.battle_log.connect(push_log)
		if actor.has_signal("chatter") and not actor.chatter.is_connected(push_chatter):
			actor.chatter.connect(push_chatter)

		var panel = ACTOR_PANEL.instantiate()

		if actor.team == BattleActor.Team.PLAYER:
			player_container.add_child(panel)
			player_panels[actor] = panel
		else:
			continue

		panel.setup(actor)


func show_target(actor : BattleActor):

	target_info.show()

	target_info.get_node("NameLabel").text = actor.name
	target_info.get_node("HPBar").max_value = actor.max_hp
	target_info.get_node("HPBar").value = actor.hp
	target_info.get_node("HPText").text = "%d / %d" % [actor.hp, actor.max_hp]

func set_active_actor(actor, active:= true):

	if actor in player_panels:
		if active:
			player_panels[actor].modulate = Color(5.195, 5.195, 5.195, 1.0)
		else:
			player_panels[actor].modulate = Color.WHITE


# --- Augur enemy intel panel ---

func show_augur_panel(enemies: Array) -> void:
	if _augur_panel == null:
		_build_augur_panel()
	# Rebuild content each call (enemies may have changed)
	for child in _augur_panel.get_node("VBox").get_children():
		child.queue_free()
	_augur_labels.clear()
	for enemy in enemies:
		var entry := _make_augur_entry(enemy)
		_augur_panel.get_node("VBox").add_child(entry)
		_augur_labels[enemy] = entry
	_augur_panel.visible = true


func reset_augur_panel() -> void:
	if _augur_panel != null:
		_augur_panel.visible = false
		for child in _augur_panel.get_node("VBox").get_children():
			child.queue_free()
		_augur_labels.clear()


func _build_augur_panel() -> void:
	_augur_panel = PanelContainer.new()
	_augur_panel.name = "AugurPanel"
	# Mirror TargetInfo anchor: right edge, vertically centred, above TargetInfo
	_augur_panel.anchor_left   = 1.0
	_augur_panel.anchor_top    = 0.5
	_augur_panel.anchor_right  = 1.0
	_augur_panel.anchor_bottom = 0.5
	_augur_panel.offset_left   = -800.0
	_augur_panel.offset_right  = -642.0
	_augur_panel.offset_top    = 50.0    # sits above TargetInfo (offset_top = 170)
	_augur_panel.offset_bottom = 167.0  # 3px gap above TargetInfo
	_augur_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_augur_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	var ps := StyleBoxFlat.new()
	ps.bg_color    = Color(0.06, 0.06, 0.08, 0.82)
	ps.border_color = Color(0.28, 0.22, 0.35, 1.0)
	ps.set_border_width_all(2)
	ps.set_content_margin_all(8)
	_augur_panel.add_theme_stylebox_override("panel", ps)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 6)
	_augur_panel.add_child(vbox)
	_augur_panel.visible = false
	add_child(_augur_panel)


func _make_augur_entry(enemy: BattleActor) -> VBoxContainer:
	var C_TEXT_L := Color(0.88, 0.83, 0.74, 1.0)
	var C_DIM_L  := Color(0.55, 0.50, 0.43, 1.0)
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)

	var name_lbl := Label.new()
	name_lbl.text = enemy.name.to_upper()
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", C_TEXT_L)
	entry.add_child(name_lbl)

	var atk_lbl := Label.new()
	atk_lbl.text = "SHARP %d   FLAT %d   TEMPO %d" % [enemy.attack_power, enemy.flat_defense, enemy.tempo_stat]
	atk_lbl.add_theme_font_size_override("font_size", 10)
	atk_lbl.add_theme_color_override("font_color", C_DIM_L)
	entry.add_child(atk_lbl)

	return entry
