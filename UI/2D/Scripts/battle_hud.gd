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
const QUEUE_STEPS = 6                  # how many acts ahead to project

var player_panels := {}
var enemy_panels := {}

# Log node refs - created at runtime if not found in scene
var _log_panel      : PanelContainer
var _log_label      : RichTextLabel
var _log_vbox       : VBoxContainer
var _log_lines      : Array = []

# ATB bar widgets keyed by BattleActor
var _atb_bars : Dictionary = {}
# Button overlay for player actors — clicking issues an order
var _atb_buttons : Dictionary = {}

# Turn order queue strip
var _queue_labels : Array = []

# Augur enemy intel panel - built lazily on first augur call
var _augur_panel   : PanelContainer
var _augur_labels  : Dictionary = {}  # actor -> VBoxContainer of labels


func _ready_log() -> void:
	if _log_vbox != null:
		return
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL

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
			lbl.text = actor.get_log_name() + "\n" + str(int(tempo))
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

# Menu button — built once, shown always during battle
var _menu_btn : Button = null

# Overview toggle — bottom-centre, toggles target cam between orbit and overhead
var _overview_btn : Button = null
var _overview_active : bool = false

func _build_menu_button() -> void:
	if _menu_btn != null:
		return
	var font : Font = load(HUD_FONT) if ResourceLoader.exists(HUD_FONT) else ThemeDB.fallback_font
	_menu_btn = Button.new()
	_menu_btn.text = "MENU"
	_menu_btn.anchor_left   = 0.0
	_menu_btn.anchor_top    = 0.0
	_menu_btn.anchor_right  = 0.0
	_menu_btn.anchor_bottom = 0.0
	_menu_btn.offset_left   = 10.0
	_menu_btn.offset_top    = 10.0
	_menu_btn.offset_right  = 90.0
	_menu_btn.offset_bottom = 42.0
	_menu_btn.add_theme_font_override("font", font)
	_menu_btn.add_theme_font_size_override("font_size", 13)
	_menu_btn.add_theme_color_override("font_color", HUD_TEXT)
	_menu_btn.add_theme_color_override("font_hover_color", HUD_TEXT)
	_menu_btn.add_theme_color_override("font_pressed_color", HUD_TEXT)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.10, 0.08, 0.07, 0.92)
	sn.border_color = HUD_ACCENT
	sn.set_border_width_all(1)
	sn.set_content_margin_all(6)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.20, 0.10, 0.08, 0.97)
	for st in ["normal", "focus"]: _menu_btn.add_theme_stylebox_override(st, sn)
	for st in ["hover", "pressed"]: _menu_btn.add_theme_stylebox_override(st, sh)
	_menu_btn.pressed.connect(_on_menu_btn_pressed)
	add_child(_menu_btn)


func _on_menu_btn_pressed() -> void:
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm == null:
		return
	# Only open during the player's command stage and when not locked
	if bm.input_locked or bm.input_stage != bm.InputStage.COMMAND:
		return
	var battle_menu = bm.battle_menu
	if is_instance_valid(battle_menu):
		battle_menu.open_for_turn(bm.active_player_actor, bm.actors, bm.context.run_state)


func _build_overview_toggle_button() -> void:
	if _overview_btn != null:
		return
	var font : Font = load(HUD_FONT) if ResourceLoader.exists(HUD_FONT) else ThemeDB.fallback_font
	_overview_btn = Button.new()
	_overview_btn.text = "[ OVERVIEW ]" if _overview_active else "[ ORBIT ]"
	# Anchor to bottom-centre
	_overview_btn.anchor_left   = 0.5
	_overview_btn.anchor_top    = 1.0
	_overview_btn.anchor_right  = 0.5
	_overview_btn.anchor_bottom = 1.0
	_overview_btn.offset_left   = -56.0
	_overview_btn.offset_right  =  56.0
	_overview_btn.offset_top    = -40.0
	_overview_btn.offset_bottom = -10.0
	_overview_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_overview_btn.add_theme_font_override("font", font)
	_overview_btn.add_theme_font_size_override("font_size", 11)
	_overview_btn.add_theme_color_override("font_color", HUD_TEXT)
	_overview_btn.add_theme_color_override("font_hover_color", HUD_TEXT)
	_overview_btn.add_theme_color_override("font_pressed_color", HUD_TEXT)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.10, 0.08, 0.07, 0.88)
	sn.border_color = HUD_ACCENT
	sn.set_border_width_all(1)
	sn.set_content_margin_all(5)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.22, 0.14, 0.08, 0.97)
	sh.border_color = HUD_TEXT
	for st in ["normal", "focus"]: _overview_btn.add_theme_stylebox_override(st, sn)
	for st in ["hover", "pressed"]: _overview_btn.add_theme_stylebox_override(st, sh)
	_overview_btn.pressed.connect(_on_overview_btn_pressed)
	add_child(_overview_btn)


func _on_overview_btn_pressed() -> void:
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm == null:
		return
	_overview_active = not _overview_active
	if _overview_active:
		bm.focus_overview()
		_overview_btn.text = "[ OVERVIEW ]"
	else:
		bm.focus_idle_orbit()
		_overview_btn.text = "[ ORBIT ]"


## Called by the battle manager whenever it switches camera mode so the
## button label stays in sync with programmatic transitions (e.g. turn start).
func sync_overview_button(is_overview: bool) -> void:
	_overview_active = is_overview
	if _overview_btn:
		_overview_btn.text = "[ OVERVIEW ]" if is_overview else "[ ORBIT ]"


func setup(actor_list : Array):
	_ready_log()
	_ready_queue()
	_apply_hud_style()
	_build_overview_toggle_button()
	# Reset toggle state at the start of each battle (overview is the initial state)
	_overview_active = true
	if _overview_btn:
		_overview_btn.text = "[ OVERVIEW ]"
	# Clear log entries and state from any previous battle
	_log_lines.clear()
	if _log_vbox:
		for c in _log_vbox.get_children():
			c.free()  # free() not queue_free() — must be synchronous

	# Build ATB bars if we're starting in ATB mode.
	if BattleSettings.battle_mode == BattleSettings.BattleMode.ATB:
		_build_atb_strip(actor_list)
	else:
		# Remove any leftover ATB strip from a previous ATB battle.
		if _atb_strip != null:
			_atb_strip.queue_free()
			_atb_strip = null
		_atb_bars.clear()

	for c in player_container.get_children():
		c.queue_free()

	for actor in actor_list:
		# Wire battle log to HUD; chatter goes to BattleSubtitles
		if actor.has_signal("battle_log") and not actor.battle_log.is_connected(push_log):
			actor.battle_log.connect(push_log)
		var subs = get_tree().get_first_node_in_group("battle_subtitles")
		if subs != null and actor.has_signal("chatter") \
				and not actor.chatter.is_connected(subs.push_chatter):
			actor.chatter.connect(subs.push_chatter)

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
	#_augur_panel.visible = true


func reset_augur_panel() -> void:
	if _augur_panel != null:
		_augur_panel.visible = false
		for child in _augur_panel.get_node("VBox").get_children():
			child.queue_free()
		_augur_labels.clear()


# ── Enemy skill announcement banner ──────────────────────────────────────────
# Shown for ~1.8 s before the enemy acts, then fades out.

var _announce_panel : PanelContainer = null
var _announce_tween : Tween = null

func announce_enemy_skill(enemy_name: String, skill_name: String, skill_summary: String) -> void:
	if _announce_panel == null:
		_build_announce_panel()
	# Kill any in-flight tween so a rapid new announcement starts clean.
	if is_instance_valid(_announce_tween):
		_announce_tween.kill()

	var font : Font = load(HUD_FONT) if ResourceLoader.exists(HUD_FONT) else ThemeDB.fallback_font

	var name_lbl  : Label = _announce_panel.get_node("VBox/EnemyName")
	var skill_lbl : Label = _announce_panel.get_node("VBox/SkillName")
	var desc_lbl  : Label = _announce_panel.get_node("VBox/SkillDesc")

	name_lbl.text  = enemy_name.to_upper()
	skill_lbl.text = skill_name.to_upper()
	desc_lbl.text  = skill_summary
	desc_lbl.visible = skill_summary != ""

	_announce_panel.modulate = Color(1, 1, 1, 0)
	_announce_panel.visible  = true

	_announce_tween = create_tween()
	_announce_tween.tween_property(_announce_panel, "modulate", Color(1, 1, 1, 1), 0.18)
	_announce_tween.tween_interval(1.6)
	_announce_tween.tween_property(_announce_panel, "modulate", Color(1, 1, 1, 0), 0.3)
	_announce_tween.tween_callback(func(): _announce_panel.visible = false)


func _build_announce_panel() -> void:
	var font : Font = load(HUD_FONT) if ResourceLoader.exists(HUD_FONT) else ThemeDB.fallback_font

	_announce_panel = PanelContainer.new()
	_announce_panel.name = "EnemySkillAnnounce"
	# Horizontally centred, sits in the upper-middle of the screen.
	_announce_panel.anchor_left   = 0.3
	_announce_panel.anchor_right  = 0.7
	_announce_panel.anchor_top    = 0.08
	_announce_panel.anchor_bottom = 0.08
	_announce_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_announce_panel.grow_vertical   = Control.GROW_DIRECTION_END

	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.06, 0.04, 0.04, 0.94)
	sbox.border_color = Color(0.65, 0.22, 0.22, 1.0)  # red-tinted border for enemy
	sbox.set_border_width_all(0)
	sbox.border_width_bottom = 2
	sbox.border_width_top    = 2
	sbox.set_content_margin_all(12)
	sbox.content_margin_left  = 18
	sbox.content_margin_right = 18
	_announce_panel.add_theme_stylebox_override("panel", sbox)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 4)
	_announce_panel.add_child(vbox)

	# Enemy name (small, dim)
	var name_lbl := Label.new()
	name_lbl.name = "EnemyName"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color(0.65, 0.45, 0.45, 1.0))
	if font: name_lbl.add_theme_font_override("font", font)
	vbox.add_child(name_lbl)

	# Skill name (large, prominent)
	var skill_lbl := Label.new()
	skill_lbl.name = "SkillName"
	skill_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skill_lbl.add_theme_font_size_override("font_size", 20)
	skill_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.72, 1.0))
	if font: skill_lbl.add_theme_font_override("font", font)
	vbox.add_child(skill_lbl)

	# Skill summary (small, italic-style, dim)
	var desc_lbl := Label.new()
	desc_lbl.name = "SkillDesc"
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.60, 0.55, 0.50, 1.0))
	if font: desc_lbl.add_theme_font_override("font", font)
	vbox.add_child(desc_lbl)

	_announce_panel.visible = false
	add_child(_announce_panel)


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


# ── ATB bar strip ─────────────────────────────────────────────────────────────────

## Container holding all ATB bars.  Created lazily on first ATB battle.
var _atb_strip : VBoxContainer = null

## Builds one ProgressBar + name Label per actor and stores them in _atb_bars.
## Placed at the right edge of the screen, above the TargetInfo panel.
func _build_atb_strip(actor_list: Array) -> void:
	if _atb_strip != null:
		_atb_strip.queue_free()
		_atb_strip = null
	_atb_bars.clear()
	_atb_buttons.clear()

	var font : Font = load(HUD_FONT) if ResourceLoader.exists(HUD_FONT) else ThemeDB.fallback_font

	_atb_strip = VBoxContainer.new()
	_atb_strip.name = "ATBStrip"
	_atb_strip.anchor_left   = 1.0
	_atb_strip.anchor_top    = 0.5
	_atb_strip.anchor_right  = 1.0
	_atb_strip.anchor_bottom = 0.5
	_atb_strip.offset_left   = -160.0
	_atb_strip.offset_right  = -10.0
	_atb_strip.offset_top    = -60.0
	_atb_strip.offset_bottom =  110.0
	_atb_strip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_atb_strip.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_atb_strip.add_theme_constant_override("separation", 6)
	add_child(_atb_strip)

	# Show all actors (players on top, enemies below) sorted by team then name.
	var sorted := actor_list.filter(func(a): return a.team == BattleActor.Team.PLAYER)
	sorted.append_array(actor_list.filter(func(a): return a.team == BattleActor.Team.ENEMY))

	for actor in sorted:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)

		var lbl := Label.new()
		lbl.text = actor.get_log_name().to_upper()
		lbl.add_theme_font_size_override("font_size", 10)
		var col := Color(0.75, 0.95, 1.0, 1.0) if actor.team == BattleActor.Team.PLAYER \
					else Color(1.0, 0.55, 0.55, 1.0)
		lbl.add_theme_color_override("font_color", col)
		if font:
			lbl.add_theme_font_override("font", font)
		row.add_child(lbl)

		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = actor.tempo_pool
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size = Vector2(0, 8)
		bar.show_percentage = false
		# Style the bar
		var fill := StyleBoxFlat.new()
		fill.bg_color = col
		bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.1, 0.1, 0.12, 0.85)
		bar.add_theme_stylebox_override("background", bg)
		row.add_child(bar)

		_atb_strip.add_child(row)
		_atb_bars[actor] = bar

		# Player actors get a transparent button overlay so the player can
		# click them to issue orders when their bar is full.
		if actor.team == BattleActor.Team.PLAYER:
			var btn := Button.new()
			btn.flat = true
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.size_flags_vertical   = Control.SIZE_EXPAND_FILL
			# Invisible until ready
			btn.modulate = Color(1, 1, 1, 0)
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var _actor: BattleActor = actor  # capture for lambda
			btn.pressed.connect(func():
				var bm = get_tree().get_first_node_in_group("battle_manager")
				if bm != null:
					bm._atb_player_issue_order(_actor)
			)
			row.add_child(btn)
			_atb_buttons[actor] = btn

## Update ATB bar values.  Called every _process frame from battle_manager in ATB mode.
func refresh_atb_bars(actor_list: Array) -> void:
	for actor in actor_list:
		if _atb_bars.has(actor):
			(_atb_bars[actor] as ProgressBar).value = actor.tempo_pool
		if _atb_buttons.has(actor):
			var btn : Button = _atb_buttons[actor]
			var ready : bool = actor.tempo_pool >= 100.0
			btn.mouse_filter = Control.MOUSE_FILTER_STOP if ready else Control.MOUSE_FILTER_IGNORE
			# Pulse the label alpha so it's obvious this character is ready.
			var pulse := (sin(Time.get_ticks_msec() * 0.005) * 0.5 + 0.5) if ready else 0.0
			btn.modulate = Color(1, 1, 1, pulse)

## Show or hide the ATB strip.  Called at battle start based on BattleSettings.
func set_atb_strip_visible(v: bool) -> void:
	if _atb_strip != null:
		_atb_strip.visible = v
	# Also hide the CTB projected queue when ATB is active.
	if is_instance_valid(_queue_vbox):
		_queue_vbox.get_parent().visible = not v  # hides the BattleLog/HBoxContainer/TurnQueue column
