extends CanvasLayer
## BattleMenu — persistent in-battle command overlay.
##
## Has two parts:
##   1. A small MENU button always visible in the top-left corner.
##   2. A full-screen command panel that opens on demand.
##
## The panel shows:
##   - Active actor's skills (attack / support / special)
##   - Enemy list with visible body parts for targeting
##   - Party stat cards
##   - Inventory items usable in battle
##
## Signals:
##   skill_chosen(actor, skill_dict, target_actor, target_part)
##       Emitted when a skill is confirmed. Battle manager should execute it.
##   item_used(actor, item_inst, target_member)
##       Emitted after item is applied. Battle manager should spend the turn.
##   closed()
##       Panel dismissed with no action. Turn is not consumed.

signal skill_chosen(actor: BattleActor, skill: Dictionary, target: BattleActor, part: BodyPartData)
signal item_used(actor: BattleActor, item_inst: ItemInstance, target_member: PartyMemberData)
signal closed()

# ── Style ────────────────────────────────────────────────────────────────────
const C_BG       := Color(0.05, 0.04, 0.04, 0.97)
const C_PANEL    := Color(0.09, 0.08, 0.07, 1.0)
const C_BORDER   := Color(0.28, 0.22, 0.18, 1.0)
const C_ACCENT   := Color(0.65, 0.16, 0.16, 1.0)
const C_TEXT     := Color(0.88, 0.83, 0.74, 1.0)
const C_DIM      := Color(0.50, 0.45, 0.38, 1.0)
const C_GREEN    := Color(0.28, 0.82, 0.42, 1.0)
const C_BLUE    := Color(0.278, 0.765, 0.988, 1.0)
const C_RED      := Color(0.95, 0.28, 0.28, 1.0)
const C_GOLD     := Color(0.92, 0.76, 0.28, 1.0)
const C_SEL      := Color(0.18, 0.14, 0.10, 1.0)
const FONT_PATH  := "res://UI/Themes/Fonts/TerminalVector.ttf"

# ── State ────────────────────────────────────────────────────────────────────
var _open         : bool            = false
var _actor        : BattleActor     = null   # whose turn it is
var _all_actors   : Array           = []
var _run_state    : RunState        = null
var _removed_channels : int         = 0
var _font         : Font

# Selection state for multi-step confirm
enum _Phase { NONE, SKILL_CHOSEN, TARGET_CHOSEN, ITEM_CHOSEN, FILTER_CHOSEN }
var _phase        : _Phase          = _Phase.NONE
var _sel_skill    : Dictionary      = {}
var _sel_target   : BattleActor     = null
var _sel_part     : BodyPartData    = null
var _sel_item     : ItemInstance    = null
var _sel_item_pm  : PartyMemberData = null
var _sel_filter   : int             = -1

# Node refs
var _open_btn     : Button          # always-visible top-left button
var _panel        : Control         # the full overlay (hide/show)
var _status_lbl   : Label
var _confirm_btn  : Button
var _skill_col    : VBoxContainer
var _target_col   : VBoxContainer
var _part_col     : VBoxContainer
var _party_col    : VBoxContainer
var _item_col     : VBoxContainer
var _log_col      : VBoxContainer
var _tempo_score  : Control         # TempoScore custom Control


# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 60
	add_to_group("battle_menu")
	_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font
	_build_open_button()
	_build_panel()
	_panel.hide()


func _process(_delta: float) -> void:
	if _open and is_instance_valid(_tempo_score):
		_tempo_score.refresh(_all_actors, _actor)


# ── Public API ───────────────────────────────────────────────────────────────

func open_for_turn(actor: BattleActor, all_actors: Array, run_state: RunState, removed_channels: int = 0) -> void:
	_actor            = actor
	_all_actors       = all_actors
	_run_state        = run_state
	_removed_channels = removed_channels
	_reset_selection()
	_refresh_skills()
	_refresh_enemies()
	_refresh_party()
	_refresh_items()
	_clear_part_col()
	_update_confirm()
	_set_status("")
	_panel.show()
	_open = true
	# Initialise tempo score
	if is_instance_valid(_tempo_score):
		_tempo_score.setup(_all_actors, _actor, _font)


## Called by the battle manager on open to populate the log with existing lines.
func refresh_log(lines: Array) -> void:
	if not is_instance_valid(_log_col):
		return
	for c in _log_col.get_children():
		c.queue_free()
	# lines[0] is the newest — display oldest at top, newest at bottom
	for i in range(lines.size() - 1, -1, -1):
		_log_col.add_child(_make_log_line(lines[i]))


## Called whenever a new battle log line is pushed (wire alongside BattleHUD.push_log).
func push_log(msg: String) -> void:
	if not is_instance_valid(_log_col):
		return
	_log_col.add_child(_make_log_line(msg))
	# Trim to same cap as BattleHUD
	while _log_col.get_child_count() > 12:
		_log_col.get_child(0).free()


func _make_log_line(msg: String) -> Label:
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_font_size_override("font_size", 11)
	if _font:
		lbl.add_theme_font_override("font", _font)
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl


func close_panel() -> void:
	if not _open:
		return
	_open = false
	_panel.hide()
	closed.emit()


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	# Close on Escape or the same open_menu hotkey
	if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) \
			or event.is_action_pressed("open_menu"):
		close_panel()
		get_viewport().set_input_as_handled()
		return
	# Right-click resets to initial state
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_reset_to_initial()
		get_viewport().set_input_as_handled()


# ── Always-visible open button ────────────────────────────────────────────────

func _build_open_button() -> void:
	# Wrap in a Control anchored full-rect so we can position freely
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_ctrl)

	_open_btn = Button.new()
	_open_btn.text = "ARG"
	_open_btn.focus_mode = Control.FOCUS_NONE
	_open_btn.anchor_left   = 0.0
	_open_btn.anchor_top    = 0.0
	_open_btn.anchor_right  = 0.0
	_open_btn.anchor_bottom = 0.0
	_open_btn.offset_left   = 10.0
	_open_btn.offset_top    = 10.0
	_open_btn.offset_right  = 90.0
	_open_btn.offset_bottom = 40.0
	if _font:
		_open_btn.add_theme_font_override("font", _font)
	_open_btn.add_theme_font_size_override("font_size", 13)
	_open_btn.add_theme_color_override("font_color", C_TEXT)
	_open_btn.add_theme_color_override("font_hover_color", C_TEXT)
	_open_btn.add_theme_color_override("font_pressed_color", C_TEXT)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.10, 0.08, 0.07, 0.92)
	sn.border_color = C_ACCENT
	sn.set_border_width_all(1)
	sn.set_content_margin_all(6)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.22, 0.10, 0.08, 0.97)
	for st in ["normal", "focus"]: _open_btn.add_theme_stylebox_override(st, sn)
	for st in ["hover", "pressed"]: _open_btn.add_theme_stylebox_override(st, sh)
	_open_btn.pressed.connect(_on_open_btn_pressed)
	root_ctrl.add_child(_open_btn)


func _on_open_btn_pressed() -> void:
	if _open:
		close_panel()
		return
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm == null:
		return
	if bm.input_locked or bm.input_stage != bm.InputStage.COMMAND:
		return
	open_for_turn(bm.active_player_actor, bm.actors, bm.context.run_state, bm.removed_channels)


# ── Full panel ────────────────────────────────────────────────────────────────

func _build_panel() -> void:
	# Root control anchored full-rect — panel sits inside this
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_ctrl)
	_panel = root_ctrl

	# Dim background
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(dim)

	# Centred panel box
	var box := PanelContainer.new()
	box.anchor_left   = 0.5
	box.anchor_top    = 0.5
	box.anchor_right  = 0.5
	box.anchor_bottom = 0.5
	box.offset_left   = -600.0
	box.offset_top    = -400.0
	box.offset_right  =  600.0
	box.offset_bottom =  400.0
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = C_BG
	sbox.border_color = C_BORDER
	sbox.set_border_width_all(1)
	sbox.border_width_bottom = 2
	sbox.set_content_margin_all(16)
	box.add_theme_stylebox_override("panel", sbox)
	_panel.add_child(box)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	box.add_child(outer)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	outer.add_child(header)
	var title := _lbl("ARRANGEMENT VIEW", 17, C_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var actor_lbl := _lbl("", 13, C_GOLD)
	actor_lbl.name = "ActorLbl"
	header.add_child(actor_lbl)

	var rule := _hrule(C_ACCENT)
	outer.add_child(rule)

	# Body: three columns
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	# Left column: party
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(220, 0)
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	left.add_child(_lbl("PARTY", 11, C_DIM))
	left.add_child(_hrule(C_BORDER))
	var party_scroll := ScrollContainer.new()
	party_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	party_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(party_scroll)
	_party_col = VBoxContainer.new()
	_party_col.add_theme_constant_override("separation", 6)
	_party_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_scroll.add_child(_party_col)
	
	left.add_child(_lbl("ENEMIES", 11, C_DIM))
	left.add_child(_hrule(C_BORDER))

	var enemy_scroll := ScrollContainer.new()
	enemy_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(enemy_scroll)
	_target_col = VBoxContainer.new()
	_target_col.add_theme_constant_override("separation", 4)
	_target_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_scroll.add_child(_target_col)
	
	
	
	body.add_child(_vrule())
	
	# Middle column: skills + parts
	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(220, 0)
	mid.add_theme_constant_override("separation", 8)
	body.add_child(mid)

	mid.add_child(_lbl("SKILLS", 11, C_DIM))
	mid.add_child(_hrule(C_BORDER))

	var skill_scroll := ScrollContainer.new()
	skill_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(skill_scroll)
	_skill_col = VBoxContainer.new()
	_skill_col.add_theme_constant_override("separation", 4)
	_skill_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_scroll.add_child(_skill_col)

	mid.add_child(_lbl("ENEMY COMPONENTS", 11, C_DIM))
	mid.add_child(_hrule(C_BORDER))
	var part_scroll := ScrollContainer.new()
	part_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	part_scroll.custom_minimum_size = Vector2(0, 100)
	part_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(part_scroll)
	_part_col = VBoxContainer.new()
	_part_col.add_theme_constant_override("separation", 3)
	_part_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	part_scroll.add_child(_part_col)


	body.add_child(_vrule())


	# Right column: items
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(240, 0)
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)

	right.add_child(_lbl("ITEMS", 11, C_DIM))
	right.add_child(_hrule(C_BORDER))
	var item_scroll := ScrollContainer.new()
	item_scroll.custom_minimum_size = Vector2(0, 100)
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(item_scroll)
	_item_col = VBoxContainer.new()
	_item_col.add_theme_constant_override("separation", 3)
	_item_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_scroll.add_child(_item_col)
	
	
	


	body.add_child(_vrule())

	# Log column: battle log fed from battle_hud
	var log_col_wrap := VBoxContainer.new()
	log_col_wrap.custom_minimum_size = Vector2(220, 0)
	log_col_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_col_wrap.add_theme_constant_override("separation", 8)
	body.add_child(log_col_wrap)

	log_col_wrap.add_child(_lbl("BATTLE LOG", 11, C_DIM))
	log_col_wrap.add_child(_hrule(C_BORDER))
	var log_scroll := ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_col_wrap.add_child(log_scroll)
	_log_col = VBoxContainer.new()
	_log_col.add_theme_constant_override("separation", 5)
	_log_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(_log_col)
	outer.add_child(_hrule(C_BORDER))

	# Tempo score strip
	var score_script := load("res://UI/2D/Scripts/tempo_score.gd")
	_tempo_score = score_script.new()
	_tempo_score.custom_minimum_size = Vector2(0, 90)
	_tempo_score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(_tempo_score)

	outer.add_child(_hrule(Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.4)))
	_status_lbl = _lbl("", 12, C_DIM)
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_status_lbl)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	footer.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(footer)

	var cancel := _btn("RETURN TO SESSION VIEW", func(): close_panel())
	footer.add_child(cancel)

	_confirm_btn = _btn("CONFIRM", func(): _on_confirm())
	_confirm_btn.disabled = true
	footer.add_child(_confirm_btn)


# ── Skills ────────────────────────────────────────────────────────────────────

func _refresh_skills() -> void:
	for c in _skill_col.get_children(): c.queue_free()
	if _actor == null:
		return
	# Update actor name in header
	var actor_lbl := _panel.find_child("ActorLbl", true, false) as Label
	if actor_lbl:
		actor_lbl.text = _actor.display_name.to_upper()

	var skills := _actor.get_skills()
	if skills.is_empty():
		_skill_col.add_child(_lbl("No actions available.", 11, C_DIM))
		return

	# Sort into canonical order: attack → support → special
	const KEY_ORDER := {"attack": 0, "support": 1, "special": 2}
	skills.sort_custom(func(a, b):
		return KEY_ORDER.get(a.get("key", ""), 99) < KEY_ORDER.get(b.get("key", ""), 99))

	for sk in skills:
		var sd : Dictionary = sk
		var key  : String = sd.get("key",  "attack")
		var name_str : String = sd.get("name", key.capitalize())
		var aoe  : bool   = sd.get("aoe",  false)
		var struggle : bool = sd.get("struggle", false)
		var cost_str : String = _skill_cost_string(sd, key)

		var btn := _btn(name_str, func(): _on_skill_pressed(sd))
		_skill_col.add_child(btn)

		# Cost + tags line
		var tags : String = cost_str
		if aoe:     tags += "  [ALL]"
		if struggle: tags += "  [STRUGGLE]"
		_skill_col.add_child(_lbl(tags, 10, C_DIM))

		# Summary from SkillDirectory
		var skill_data = SkillDirectory.get_skill(name_str)
		var summary : String = skill_data.summary if skill_data != null and skill_data.summary.strip_edges() != "" else ""
		if summary != "":
			var sum_lbl := _lbl(summary, 10, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.75))
			sum_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sum_lbl.custom_minimum_size = Vector2(180, 0)
			_skill_col.add_child(sum_lbl)

		# Small gap between skills
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 4)
		_skill_col.add_child(gap)


func _skill_cost_string(sd: Dictionary, key: String) -> String:
	if key == "attack":
		if sd.get("struggle", false):
			return "No cost"
		var cost : int = sd.get("ammo_cost", 1)
		return "%d BB" % cost
	var will_cost : int = sd.get("will_cost", 0)
	if will_cost > 0:
		return "%d AP" % will_cost
	return "No cost"


func _on_skill_pressed(sd: Dictionary) -> void:
	_sel_skill  = sd
	_sel_target = null
	_sel_part   = null
	_sel_item   = null
	_sel_filter = -1
	_phase      = _Phase.SKILL_CHOSEN
	_update_confirm()

	var key     : String = sd.get("key", "")
	var aoe     : bool   = sd.get("aoe",      false)
	var struggle: bool   = sd.get("struggle", false)
	var support : bool   = sd.get("ally_target", false) or key == "support"
	# Unveil (special) for ammo users: needs a channel filter, not a target
	var is_filter : bool = key == "special" and _actor != null and \
		(_actor.party_member == null or not _actor.party_member.has_will())

	if is_filter:
		_set_status("Choose a channel to unveil.")
		_show_filter_buttons()
		_refresh_enemies()
	elif aoe or struggle:
		_set_status("Targets: ALL  —  press CONFIRM.")
		_clear_part_col()
		_phase = _Phase.TARGET_CHOSEN
		_update_confirm()
	elif support:
		_set_status("Select an ally to target.")
		_refresh_enemies()
		_clear_part_col()
	else:
		_set_status("Select an enemy, then one of their components.")
		_refresh_enemies()
		_clear_part_col()


# ── Filter (Unveil / Change Lens) ────────────────────────────────────────────

const _FILTER_CHANNELS := [
	{"label": "R", "channel": 1, "color": Color(1.0, 0.25, 0.25, 1.0)},
	{"label": "G", "channel": 2, "color": Color(0.25, 1.0, 0.35, 1.0)},
	{"label": "B", "channel": 4, "color": Color(0.25, 0.55, 1.0, 1.0)},
]

func _show_filter_buttons() -> void:
	_clear_part_col()
	var hdr := _lbl("CHANNEL", 11, C_DIM)
	_part_col.add_child(hdr)
	for ch in _FILTER_CHANNELS:
		var already_used : bool = (_removed_channels & int(ch["channel"])) != 0
		var cap_ch : int = int(ch["channel"])
		var col : Color = ch["color"]
		var btn := Button.new()
		btn.text = ch["label"]
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = already_used
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _font:
			btn.add_theme_font_override("font", _font)
			btn.add_theme_font_size_override("font_size", 16)
		var sn := StyleBoxFlat.new()
		sn.bg_color = Color(col.r * 0.12, col.g * 0.12, col.b * 0.12, 1.0)
		sn.border_color = Color(col.r * 0.45, col.g * 0.45, col.b * 0.45, 1.0)
		sn.set_border_width_all(1)
		sn.set_content_margin_all(8)
		var sh := sn.duplicate() as StyleBoxFlat
		sh.bg_color = Color(col.r * 0.28, col.g * 0.28, col.b * 0.28, 1.0)
		sh.border_color = col
		for st in ["normal", "focus", "disabled"]: btn.add_theme_stylebox_override(st, sn)
		for st in ["hover", "pressed"]:            btn.add_theme_stylebox_override(st, sh)
		btn.add_theme_color_override("font_color",          col if not already_used else C_DIM)
		btn.add_theme_color_override("font_hover_color",    Color.WHITE)
		btn.add_theme_color_override("font_disabled_color", Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 1.0))
		if not already_used:
			btn.pressed.connect(func(): _on_filter_pressed(cap_ch))
		_part_col.add_child(btn)


func _on_filter_pressed(channel: int) -> void:
	_sel_filter = channel
	_phase      = _Phase.FILTER_CHOSEN
	var names := {1: "RED", 2: "GREEN", 4: "BLUE"}
	_set_status("Channel: %s  —  press CONFIRM." % names.get(channel, str(channel)))
	_update_confirm()


# ── Enemies ───────────────────────────────────────────────────────────────────

func _refresh_enemies() -> void:
	for c in _target_col.get_children(): c.queue_free()

	var support_mode : bool = not _sel_skill.is_empty() and \
		(_sel_skill.get("ally_target", false) or _sel_skill.get("key", "") == "support")

	if support_mode:
		# Show party members as targets
		var players := _all_actors.filter(func(a): return (a as BattleActor).team == BattleActor.Team.PLAYER)
		if players.is_empty():
			_target_col.add_child(_lbl("No allies.", 11, C_DIM))
			return
		for actor in players:
			var a := actor as BattleActor
			_target_col.add_child(_make_target_card(a, true))
		return

	var enemies := _all_actors.filter(func(a): return (a as BattleActor).team == BattleActor.Team.ENEMY and (a as BattleActor).is_alive())
	if enemies.is_empty():
		_target_col.add_child(_lbl("No enemies.", 11, C_DIM))
		return
	for actor in enemies:
		_target_col.add_child(_make_target_card(actor as BattleActor, false))


func _make_target_card(a: BattleActor, is_ally: bool) -> Control:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 3)

	var highlight : bool = (a == _sel_target)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.15, 0.12, 0.10) if highlight else C_PANEL
	sbox.border_color = C_GOLD if highlight else C_BORDER
	sbox.set_border_width_all(1)
	sbox.set_content_margin_all(7)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sbox)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	panel.add_child(inner)

	# Name + HP
	var revealed : bool = is_ally or a.stats_revealed
	var name_col : Color = C_GOLD if highlight else (C_GREEN if is_ally else C_TEXT)
	var hp_col   : Color = C_RED if a.hp <= int(a.max_hp * 0.25) else C_TEXT
	inner.add_child(_lbl(a.display_name.to_upper(), 13, name_col))
	if revealed:
		inner.add_child(_lbl("CORP  %d / %d" % [a.hp, a.max_hp], 11, hp_col))
	else:
		inner.add_child(_lbl("CORP  ???", 11, C_DIM))

	# Stats — only when revealed
	if revealed:
		var stat_row := HBoxContainer.new()
		stat_row.add_theme_constant_override("separation", 10)
		stat_row.add_child(_lbl("SHARP %d" % a.attack_power, 10, C_DIM))
		if a.flat_defense > 0:
			stat_row.add_child(_lbl("FLAT %d" % a.flat_defense, 10, C_DIM))
		inner.add_child(stat_row)

	# Status effects — only when revealed
	if revealed and not a.active_effects.is_empty():
		var fx_parts : Array = []
		for fx in a.active_effects:
			var fid : String = str(fx.get("id", ""))
			var dur : int    = int(fx.get("duration", 0))
			if fid != "" and fid != "_stat_change":
				fx_parts.append(fid.to_upper() + (" %dt" % dur if dur > 0 else ""))
		if not fx_parts.is_empty():
			inner.add_child(_lbl(" · ".join(fx_parts), 10, C_DIM))

	# Body parts preview — only parts currently visible via channel removal
	if not is_ally:
		var visible_parts := a.get_visible_parts(_removed_channels)
		if not visible_parts.is_empty():
			var part_labels : Array = []
			for bp in visible_parts:
				var m := (" ×%.1f" % bp.damage_multiplier) if bp.damage_multiplier != 1.0 else ""
				part_labels.append(bp.part_name + m)
			inner.add_child(_lbl("  " + "  ".join(part_labels), 10, C_DIM))

	# Click to select
	if not _sel_skill.is_empty():
		var cap_a := a
		var area := Button.new()
		area.flat = true
		area.focus_mode = Control.FOCUS_NONE
		area.set_anchors_preset(Control.PRESET_FULL_RECT)
		area.text = ""
		# Transparent overlay button — size matches panel
		var t := StyleBoxEmpty.new()
		for st in ["normal","hover","pressed","focus"]: area.add_theme_stylebox_override(st, t)
		area.pressed.connect(func(): _on_target_pressed(cap_a, is_ally))
		panel.add_child(area)

	return card


func _on_target_pressed(a: BattleActor, is_ally: bool) -> void:
	_sel_target = a
	_sel_part   = null
	_phase      = _Phase.TARGET_CHOSEN

	var aoe : bool = _sel_skill.get("aoe", false)
	var support : bool = is_ally or _sel_skill.get("ally_target", false) or _sel_skill.get("key", "") == "support"

	if aoe or support:
		_set_status("Target: %s  —  press CONFIRM." % a.display_name.to_upper())
		_clear_part_col()
		_update_confirm()
		_refresh_enemies()
		return

	# Show body parts for this target
	_set_status("Select a body part.")
	_refresh_enemies()
	_populate_parts(a)
	


func _populate_parts(a: BattleActor) -> void:
	_clear_part_col()
	var visible_parts : Array[BodyPartData] = a.get_visible_parts(_removed_channels)
	if visible_parts.is_empty():
		# No parts visible under current lenses — skip part selection
		_sel_part = null
		_phase    = _Phase.TARGET_CHOSEN
		_set_status("Target: %s  —  press CONFIRM." % a.display_name.to_upper())
		_update_confirm()
		return
	for bp in visible_parts:
		var cap_bp : BodyPartData = bp
		var mult_str : String = ("  ×%.1f" % bp.damage_multiplier) if bp.damage_multiplier != 1.0 else ""
		var btn := _btn(bp.part_name + mult_str, func(): _on_part_pressed(cap_bp))
		_part_col.add_child(btn)


func _on_part_pressed(bp: BodyPartData) -> void:
	_sel_part = bp
	_phase    = _Phase.TARGET_CHOSEN
	_set_status("Target: %s — %s  —  press CONFIRM." % [_sel_target.display_name.to_upper(), bp.part_name])
	_update_confirm()


func _clear_part_col() -> void:
	for c in _part_col.get_children(): c.queue_free()


# ── Party ─────────────────────────────────────────────────────────────────────

func _refresh_party() -> void:
	for c in _party_col.get_children(): c.queue_free()
	var players := _all_actors.filter(func(a): return (a as BattleActor).team == BattleActor.Team.PLAYER)
	for actor in players:
		_party_col.add_child(_make_party_card(actor as BattleActor))


func _make_party_card(a: BattleActor) -> Control:
	var card := PanelContainer.new()
	var highlight : bool = (a == _actor)
	var cs := StyleBoxFlat.new()
	cs.bg_color = C_PANEL
	cs.border_color = C_ACCENT if highlight else C_BORDER
	cs.border_width_left = 3 if highlight else 1
	cs.set_border_width_all(0)
	if highlight: cs.border_width_left = 3
	cs.border_color = C_ACCENT
	cs.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", cs)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	var name_col : Color = C_GOLD if a == _actor else C_TEXT
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	var nl := _lbl(a.display_name.to_upper(), 13, name_col)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(nl)
	var lv_str : String = "LV %d" % (a.party_member.level if a.party_member else 1)
	name_row.add_child(_lbl(lv_str, 10, C_DIM))
	vbox.add_child(name_row)

	var hp_col : Color = C_RED if a.hp <= int(a.max_hp * 0.25) else C_TEXT
	vbox.add_child(_lbl("CORP  %d / %d" % [a.hp, a.max_hp], 11, hp_col))

	if a.party_member != null and a.party_member.has_will():
		var ap_col : Color = C_BLUE if a.party_member.will >= a.party_member.max_will else C_DIM
		vbox.add_child(_lbl("AP  %d / %d" % [a.party_member.will, a.party_member.max_will], 11, ap_col))
	elif a.run_state != null:
		vbox.add_child(_lbl("BB  %d / %d" % [a.run_state.ammo, a.run_state.gun_clip], 11, C_GOLD))

	if not a.active_effects.is_empty():
		var parts : Array = []
		for fx in a.active_effects:
			var fid : String = str(fx.get("id", ""))
			if fid != "" and fid != "_stat_change":
				parts.append(fid.to_upper())
		if not parts.is_empty():
			vbox.add_child(_lbl(" · ".join(parts), 10, C_DIM))

	return card


# ── Items ─────────────────────────────────────────────────────────────────────

func _refresh_items() -> void:
	for c in _item_col.get_children(): c.queue_free()
	if _run_state == null:
		_item_col.add_child(_lbl("No inventory.", 11, C_DIM))
		return
	var battle_items := _run_state.inventory.filter(func(inst):
		var cd := (inst as ItemInstance).item_data as ConsumableData
		return cd != null and cd.usable_in_battle)
	if battle_items.is_empty():
		_item_col.add_child(_lbl("None usable.", 11, C_DIM))
		return
	for inst in battle_items:
		var cd := inst.item_data as ConsumableData
		var cap : ItemInstance = inst
		var btn := _btn("%s ×%d" % [cd.item_name, inst.stacks], func(): _on_item_pressed(cap))
		_item_col.add_child(btn)


func _on_item_pressed(inst: ItemInstance) -> void:
	_sel_item   = inst
	_sel_skill  = {}
	_sel_target = null
	_sel_part   = null
	_phase      = _Phase.ITEM_CHOSEN
	var cd := inst.item_data as ConsumableData
	var needs_target := cd != null and cd.effect_type not in ["corpus_all", "will_all", "reprise", "tie"]
	if needs_target:
		_set_status("Select an ally to use %s on." % cd.item_name)
		_refresh_enemies()   # switches to ally display if needed
	else:
		_set_status("Use %s on EVERYONE  —  press CONFIRM." % cd.item_name)
	_update_confirm()
	_clear_part_col()


# ── Confirm ───────────────────────────────────────────────────────────────────

func _update_confirm() -> void:
	if _confirm_btn == null:
		return
	match _phase:
		_Phase.NONE:
			_confirm_btn.disabled = true
		_Phase.SKILL_CHOSEN:
			# AoE/struggle — no target needed
			var aoe     : bool = _sel_skill.get("aoe",     false)
			var struggle: bool = _sel_skill.get("struggle", false)
			_confirm_btn.disabled = not (aoe or struggle)
		_Phase.TARGET_CHOSEN:
			_confirm_btn.disabled = false
		_Phase.FILTER_CHOSEN:
			_confirm_btn.disabled = _sel_filter == -1
		_Phase.ITEM_CHOSEN:
			var cd := _sel_item.item_data as ConsumableData if _sel_item else null
			var needs_target := cd != null and cd.effect_type not in ["corpus_all", "will_all", "reprise", "tie"]
			_confirm_btn.disabled = needs_target and _sel_item_pm == null
		_:
			_confirm_btn.disabled = true


func _on_confirm() -> void:
	if _phase == _Phase.ITEM_CHOSEN:
		_do_item_confirm()
	elif _phase == _Phase.FILTER_CHOSEN:
		_do_filter_confirm()
	elif _phase == _Phase.SKILL_CHOSEN or _phase == _Phase.TARGET_CHOSEN:
		_do_skill_confirm()


func _do_skill_confirm() -> void:
	if _sel_skill.is_empty():
		return
	var actor  := _actor
	var skill  := _sel_skill
	var target := _sel_target
	var part   := _sel_part
	_open = false
	_panel.hide()
	skill_chosen.emit(actor, skill, target, part)


func _do_filter_confirm() -> void:
	if _sel_filter == -1:
		return
	var actor  := _actor
	var skill  := _sel_skill.duplicate()
	skill["_filter_channel"] = _sel_filter
	_open = false
	_panel.hide()
	skill_chosen.emit(actor, skill, null, null)


func _do_item_confirm() -> void:
	if _sel_item == null:
		return
	var used := ItemRegistry.use_item(_run_state, _sel_item, _sel_item_pm)
	if not used:
		_set_status("Cannot use that item right now.")
		return
	var actor := _actor
	var inst  := _sel_item
	var pm    := _sel_item_pm
	_open = false
	_panel.hide()
	item_used.emit(actor, inst, pm)


func _reset_selection() -> void:
	_phase       = _Phase.NONE
	_sel_skill   = {}
	_sel_target  = null
	_sel_part    = null
	_sel_item    = null
	_sel_item_pm = null
	_sel_filter  = -1


func _reset_to_initial() -> void:
	_reset_selection()
	_refresh_skills()
	_refresh_enemies()
	_refresh_items()
	_clear_part_col()
	_update_confirm()
	_set_status("")


# ── Helpers ───────────────────────────────────────────────────────────────────

func _set_status(msg: String) -> void:
	if is_instance_valid(_status_lbl):
		_status_lbl.text = msg


func _lbl(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	if _font: l.add_theme_font_override("font", _font)
	l.add_theme_color_override("font_color", col)
	return l


func _btn(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if _font: b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", C_TEXT)
	b.add_theme_color_override("font_pressed_color", C_TEXT)
	var sn := StyleBoxFlat.new()
	sn.bg_color = C_PANEL
	sn.border_color = C_BORDER
	sn.set_border_width_all(1)
	sn.set_content_margin_all(7)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = C_SEL
	sh.border_color = C_ACCENT
	for st in ["normal", "focus"]: b.add_theme_stylebox_override(st, sn)
	for st in ["hover", "pressed"]: b.add_theme_stylebox_override(st, sh)
	b.pressed.connect(cb)
	return b


func _hrule(col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.custom_minimum_size = Vector2(0, 1)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


func _vrule() -> ColorRect:
	var r := ColorRect.new()
	r.color = C_BORDER
	r.custom_minimum_size = Vector2(1, 0)
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return r
