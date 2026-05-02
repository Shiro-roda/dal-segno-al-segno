extends CanvasLayer
## BattleMenu — persistent in-battle command overlay.
##
## Layout (4 columns):
##   Col 1  PARTY    — player character cards
##   Col 2  ACTIONS  — upper half: section picker → skills OR items (warm tint, linked to Col 1)
##                     lower half: enemy body parts (cool tint, linked to Col 3)
##   Col 3  ENEMIES  — enemy / ally target cards
##   Col 4  LOG      — battle log
##
## Selection flow:  party → section → skill/item → [target] → [part] → confirm
##
## Keyboard:  ↑↓ within list  |  ← back one stage  |  → / Enter advance
##
## Has two parts:
##   1. A small ARG button always visible at the top-centre.
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
## Emitted when the player selects a ready actor to command — before any skill is chosen.
## Battle manager uses this to populate the floating reticle's skill boxes.
signal actor_commanding(actor: BattleActor)

# ── Style ────────────────────────────────────────────────────────────────────
const C_BG      := Color(0.051, 0.039, 0.039, 1.0)
const C_PANEL   := Color(0.09, 0.08, 0.07, 1.0)
const C_BORDER  := Color(0.28, 0.22, 0.18, 1.0)
const C_ACCENT  := Color(0.65, 0.16, 0.16, 1.0)
const C_TEXT    := Color(0.88, 0.83, 0.74, 1.0)
const C_DIM     := Color(0.50, 0.45, 0.38, 1.0)
const C_GREEN   := Color(0.28, 0.82, 0.42, 1.0)
const C_BLUE    := Color(0.278, 0.765, 0.988, 1.0)
const C_RED     := Color(0.95, 0.28, 0.28, 1.0)
const C_GOLD    := Color(0.92, 0.76, 0.28, 1.0)
const C_SEL     := Color(0.18, 0.14, 0.10, 1.0)
# Tint colours bridging connected half-columns
const C_WARM_BG := Color(0.10, 0.07, 0.05, 1.0)  # party ↔ action-top
const C_COOL_BG := Color(0.05, 0.07, 0.10, 1.0)  # parts ↔ enemy
const FONT_PATH := "res://UI/Themes/Fonts/TerminalVector.ttf"

# ── Selection stage ───────────────────────────────────────────────────────────
enum Stage { PARTY, SECTION, SKILL_LIST, ITEM_LIST, TARGET, PART, DONE }
var _stage : Stage = Stage.PARTY

# ── Keyboard cursor ───────────────────────────────────────────────────────────
var _kb_index : int = 0
var _kb_focused_btn : Button = null

func _stage_col() -> VBoxContainer:
	match _stage:
		Stage.PARTY:      return _party_col
		Stage.SECTION:    return _section_col
		Stage.SKILL_LIST: return _skill_col
		Stage.ITEM_LIST:  return _item_col
		Stage.TARGET:     return _target_col
		Stage.PART:       return _part_col
		_:                return null

func _col_buttons(col: VBoxContainer) -> Array:
	if not is_instance_valid(col): return []
	var out : Array = []
	_collect_btns(col, out)
	return out

func _collect_btns(node: Node, out: Array) -> void:
	for ch in node.get_children():
		if ch is Button and not (ch as Button).disabled: out.append(ch)
		elif ch is Control: _collect_btns(ch, out)

func _kb_apply_focus() -> void:
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = C_PANEL; btn_normal.border_color = C_BORDER
	btn_normal.set_border_width_all(1); btn_normal.set_content_margin_all(7)
	var btn_focused := StyleBoxFlat.new()
	btn_focused.bg_color = C_SEL; btn_focused.border_color = C_GOLD
	btn_focused.set_border_width_all(2); btn_focused.set_content_margin_all(7)

	# Reset all column buttons and any card panels they reference
	for col in [_party_col, _skill_col, _item_col, _target_col, _part_col]:
		if not is_instance_valid(col): continue
		for b in _col_buttons(col):
			(b as Button).add_theme_stylebox_override("normal", btn_normal)
			if (b as Button).has_meta("card_style"):
				var cs := (b as Button).get_meta("card_style") as StyleBoxFlat
				if cs != null:
					cs.bg_color = C_PANEL; cs.border_color = C_BORDER; cs.set_border_width_all(1)
	# Tab buttons in _section_col are managed separately by _refresh_tab_highlight
	# so we skip _section_col in the reset above and restore it here only when
	# we are NOT in SECTION stage (where the tab highlight owns the styling).
	if _stage != Stage.SECTION and is_instance_valid(_section_col):
		for b in _col_buttons(_section_col):
			(b as Button).add_theme_stylebox_override("normal", btn_normal)

	# Reset confirm button to its default unfocused style
	if is_instance_valid(_confirm_btn):
		var cn := StyleBoxFlat.new(); cn.bg_color = C_PANEL; cn.border_color = C_BORDER
		cn.set_border_width_all(1); cn.set_content_margin_all(7)
		_confirm_btn.add_theme_stylebox_override("normal", cn)

	_kb_focused_btn = null

	# Stage.DONE: focus the confirm button directly
	if _stage == Stage.DONE:
		if is_instance_valid(_confirm_btn) and not _confirm_btn.disabled:
			var cf := StyleBoxFlat.new(); cf.bg_color = Color(0.22, 0.16, 0.04, 1.0)
			cf.border_color = C_GOLD; cf.set_border_width_all(2); cf.set_content_margin_all(7)
			_confirm_btn.add_theme_stylebox_override("normal", cf)
			_kb_focused_btn = _confirm_btn
			_scroll_to_show(_confirm_btn)
		return

	var col := _stage_col()
	if col == null: return
	var list := _col_buttons(col)
	if list.is_empty(): return
	_kb_index = clampi(_kb_index, 0, list.size() - 1)
	var focused_btn := list[_kb_index] as Button
	_kb_focused_btn = focused_btn

	if focused_btn.has_meta("card_style"):
		var cs := focused_btn.get_meta("card_style") as StyleBoxFlat
		if cs != null:
			cs.bg_color = Color(0.18, 0.14, 0.08, 1.0)
			cs.border_color = C_GOLD
			cs.set_border_width_all(2)
		# Scroll the card panel itself into view, not the invisible overlay button
		var card_panel := focused_btn.get_parent()
		if is_instance_valid(card_panel): _scroll_to_show(card_panel as Control)
	else:
		focused_btn.add_theme_stylebox_override("normal", btn_focused)
		_scroll_to_show(focused_btn)

func _kb_set_stage(s: Stage) -> void:
	_stage = s; _kb_index = 0
	call_deferred("_kb_apply_focus")

# ── State ─────────────────────────────────────────────────────────────────────
var _open             : bool            = false
var _actor            : BattleActor     = null
var _ready_actors     : Array           = []
var _all_actors       : Array           = []
var _run_state        : RunState        = null
var _removed_channels : int             = 0
var _font             : Font
var _item_used_this_turn : bool         = false
var _active_tab : int = 0   # 0 = SKILLS, 1 = ITEMS
## Pending actions for non-ready actors: keyed by actor instance ID.
## Each entry: {actor, skill, target (weakref or null), part}
var _queued_actions : Dictionary = {}

var _sel_skill      : Dictionary      = {}
var _sel_item       : ItemInstance    = null
var _sel_item_pm    : PartyMemberData = null
var _sel_target     : BattleActor     = null
var _sel_part       : BodyPartData    = null
var _sel_filter     : int             = -1
var _is_filter_mode : bool            = false

# Cached refs to the split-viewport nodes we hide when the menu is fullscreen
var _viewport_split  : Node = null   # HBoxContainer
var _viewport_sep    : Node = null   # VSeparator

var _open_btn    : Button
var _panel       : Control
var _status_lbl  : Label
var _confirm_btn : Button
var _party_col   : VBoxContainer
var _section_col : VBoxContainer
var _skill_col   : VBoxContainer
var _item_col    : VBoxContainer
var _target_col  : VBoxContainer
var _part_col    : VBoxContainer
var _log_col     : VBoxContainer
var _tempo_score : Control
var _action_top  : PanelContainer
var _action_bot  : PanelContainer
var _skill_scroll : ScrollContainer
var _item_scroll  : ScrollContainer
var _enemy_col_style  : StyleBoxFlat  # live ref to col3 panel stylebox for tinting
var _action_bot_style : StyleBoxFlat  # live ref to col2 bottom stylebox for tinting
var _cool_divider     : ColorRect     # col2-bottom header rule, tinted with enemy colour
var _enemy_divider    : ColorRect     # col3 header rule, tinted with enemy colour
var _log_scroll       : ScrollContainer  # col4 scroll container — auto-scrolled on new log entries


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 110
	add_to_group("battle_menu")
	_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font
	_build_open_button()
	_build_panel()
	_panel.hide()

func _process(_delta: float) -> void:
	if _open and is_instance_valid(_tempo_score):
		var live := _all_actors.filter(func(a): return is_instance_valid(a))
		var active : BattleActor = _actor if is_instance_valid(_actor) else null
		var bm = get_tree().get_first_node_in_group("battle_manager")
		var gauge_ratio : float = 1.0
		if bm != null and bm.time_controller != null:
			gauge_ratio = bm.time_controller.arrangement_gauge_ratio()
		_tempo_score.refresh(live, active, gauge_ratio)


# ── Public API ────────────────────────────────────────────────────────────────

func sync_and_open(all_actors: Array, run_state: RunState, removed_channels: int = 0) -> void:
	_all_actors = all_actors; _run_state = run_state; _removed_channels = removed_channels
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm != null: _ready_actors = bm._atb_ready_players.duplicate()
	# If the currently-commanded actor is no longer ready, drop their selection.
	if _actor != null and _actor not in _ready_actors and not _queued_actions.has(_actor.get_instance_id()):
		_actor = null; _reset_selection()
	if _drain_ready_queues(bm): return  # queued action fired; don't stomp it
	var was_open := _open
	if not _open:
		_panel.show(); _open = true
		var bm0 = get_tree().get_first_node_in_group("battle_manager")
		if bm0 != null and bm0.time_controller != null:
			bm0.time_controller.open_arrangement_view()
		_hide_viewport_split()
		AudioManagerAuto.arrangement_mute()
		_spawn_crt_flash()
	_apply_enemy_col_tint()
	if is_instance_valid(_tempo_score): _tempo_score.setup(_all_actors, _actor, _font)
	if was_open and _actor != null:
		# Already mid-selection — silently refresh data columns only.
		_refresh_party_silent(); _refresh_enemies()
		call_deferred("_kb_apply_focus")
		return
	_refresh_party(); _refresh_enemies()
	if _actor == null:
		_clear_action_top(); _clear_part_col(); _update_confirm()
		if _ready_actors.size() == 1:
			call_deferred("_on_ready_actor_selected", _ready_actors[0]); return
		_set_status("Select a ready ally to command." if not _ready_actors.is_empty() else "No allies ready.")
		_kb_set_stage(Stage.PARTY)
	else:
		call_deferred("_kb_apply_focus")

func open_for_turn(actor: BattleActor, all_actors: Array, run_state: RunState, removed_channels: int = 0) -> void:
	sync_and_open(all_actors, run_state, removed_channels)

func notify_actor_ready(actor: BattleActor, all_actors: Array, run_state: RunState, removed_channels: int = 0) -> void:
	_all_actors = all_actors; _run_state = run_state; _removed_channels = removed_channels
	if actor != null and actor not in _ready_actors: _ready_actors.append(actor)
	# Drain all queued actions whose actors are now ready (covers the case where
	# an actor was already in _atb_ready_players when the action was queued).
	var bm2 = get_tree().get_first_node_in_group("battle_manager")
	if _drain_ready_queues(bm2): return
	if not _open: return
	# Silently update the party column so the new READY badge appears,
	# but do NOT touch the stage, keyboard focus, or action columns —
	# the player may be mid-selection for another actor.
	_refresh_party_silent()
	if is_instance_valid(_tempo_score): _tempo_score.setup(_all_actors, _actor, _font)
	# Only auto-select if the player has not started commanding anyone yet.
	if _actor == null and _stage == Stage.PARTY:
		if _ready_actors.size() == 1: _on_ready_actor_selected(actor)
		else: _set_status("Select a ready ally to command."); _kb_set_stage(Stage.PARTY)

func notify_actor_unready(actor: BattleActor) -> void:
	_ready_actors.erase(actor)
	if _actor == actor:
		# The actor the player was commanding just acted — reset to party selection.
		_actor = null; _reset_selection()
		_clear_action_top(); _refresh_enemies(); _clear_part_col(); _update_confirm()
		_set_status("Select a ready ally to command." if not _ready_actors.is_empty() else "")
		_refresh_party(); _kb_set_stage(Stage.PARTY)
	else:
		# A different actor's turn resolved — just refresh their card badge silently.
		_refresh_party_silent()

func refresh_log(lines: Array) -> void:
	if not is_instance_valid(_log_col): return
	for c in _log_col.get_children(): c.queue_free()
	for i in range(lines.size() - 1, -1, -1): _log_col.add_child(_make_log_line(lines[i]))
	if is_instance_valid(_log_scroll):
		await get_tree().process_frame
		_log_scroll.scroll_vertical = _log_scroll.get_v_scroll_bar().max_value

func push_log(msg: String) -> void:
	if not is_instance_valid(_log_col): return
	_log_col.add_child(_make_log_line(msg))
	if is_instance_valid(_log_scroll):
		await get_tree().process_frame
		_log_scroll.scroll_vertical = _log_scroll.get_v_scroll_bar().max_value

func _make_log_line(msg: String) -> Label:
	var lbl := Label.new(); lbl.text = msg
	lbl.add_theme_font_size_override("font_size", 11)
	if _font: lbl.add_theme_font_override("font", _font)
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl

func close_panel() -> void:
	if not _open: return
	_open = false; _panel.hide()
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm != null:
		bm._player_menu_open = false
		if bm.time_controller != null: bm.time_controller.close_arrangement_view()
	_show_viewport_split()
	AudioManagerAuto.arrangement_unmute()
	_spawn_crt_flash()
	closed.emit()


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _open: return
	if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or event.is_action_pressed("open_menu"):
		close_panel(); get_viewport().set_input_as_handled(); return
	if not (event is InputEventKey and event.pressed): return
	var kc : int = (event as InputEventKey).keycode

	# ── Tab row: axes are flipped ─────────────────────────────────────────────
	if _stage == Stage.SECTION:
		match kc:
			KEY_LEFT, KEY_RIGHT:
				# Cycle tabs
				var dir := 1 if kc == KEY_RIGHT else -1
				_active_tab = (_active_tab + dir + 2) % 2
				_refresh_tab_highlight()
				get_viewport().set_input_as_handled(); return
			KEY_UP:
				# Back to party list
				_step_back(); get_viewport().set_input_as_handled(); return
			KEY_DOWN, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				# Activate the focused tab
				if _active_tab == 0: _enter_skill_list()
				else:                _enter_item_list()
				get_viewport().set_input_as_handled(); return
			KEY_ESCAPE: pass  # handled above already
		return

	# ── All other stages ──────────────────────────────────────────────────────
	if kc == KEY_UP or kc == KEY_DOWN:
		var dir := 1 if kc == KEY_DOWN else -1
		var col := _stage_col()
		if col != null:
			var list := _col_buttons(col)
			if not list.is_empty():
				_kb_index = (_kb_index + dir + list.size()) % list.size()
				_kb_apply_focus()
		get_viewport().set_input_as_handled(); return

	if kc == KEY_LEFT:
		_step_back(); get_viewport().set_input_as_handled(); return

	if kc == KEY_RIGHT or kc == KEY_ENTER or kc == KEY_KP_ENTER or kc == KEY_SPACE:
		if _stage == Stage.DONE and is_instance_valid(_confirm_btn) and not _confirm_btn.disabled:
			_on_confirm(); get_viewport().set_input_as_handled(); return
		var col := _stage_col()
		if col != null:
			var list := _col_buttons(col)
			if not list.is_empty():
				_kb_index = clampi(_kb_index, 0, list.size() - 1)
				(list[_kb_index] as Button).emit_signal("pressed")
		get_viewport().set_input_as_handled(); return


func _step_back() -> void:
	match _stage:
		Stage.PARTY: pass
		Stage.SECTION:
			_actor = null; _reset_selection(); _clear_action_top()
			_clear_part_col(); _refresh_party(); _refresh_enemies(); _update_confirm()
			_set_status("Select a ready ally to command."); _kb_set_stage(Stage.PARTY)
		Stage.SKILL_LIST, Stage.ITEM_LIST:
			_sel_skill = {}; _sel_item = null; _clear_part_col(); _update_confirm()
			_set_status("Choose SKILLS or ITEMS.")
			_refresh_tab_highlight()
			_kb_set_stage(Stage.SECTION)
		Stage.TARGET:
			_sel_target = null; _sel_part = null; _clear_part_col(); _refresh_enemies(); _update_confirm()
			if _sel_item != null:
				_set_status("Select an item."); _kb_set_stage(Stage.ITEM_LIST)
			else:
				_set_status("Select a skill."); _kb_set_stage(Stage.SKILL_LIST)
		Stage.PART:
			_sel_part = null; _sel_filter = -1; _is_filter_mode = false
			_clear_part_col(); _update_confirm()
			_set_status("Select an enemy."); _kb_set_stage(Stage.TARGET)
		Stage.DONE:
			if _is_filter_mode:
				_sel_filter = -1; _show_filter_buttons(); _update_confirm(); _kb_set_stage(Stage.PART)
			elif _sel_part != null:
				_sel_part = null; _update_confirm(); _kb_set_stage(Stage.PART)
			elif _sel_target != null:
				_sel_target = null; _clear_part_col(); _refresh_enemies(); _update_confirm()
				_kb_set_stage(Stage.TARGET)
			else:
				_update_confirm(); _kb_set_stage(Stage.SKILL_LIST)


# ── Open button ────────────────────────────────────────────────────────────────

func _build_open_button() -> void:
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_ctrl)
	_open_btn = Button.new(); _open_btn.text = "ARG"; _open_btn.focus_mode = Control.FOCUS_NONE
	_open_btn.anchor_left = 0.5; _open_btn.anchor_right  = 0.5
	_open_btn.anchor_top  = 0.0; _open_btn.anchor_bottom = 0.0
	_open_btn.offset_left = -40.0; _open_btn.offset_right  =  40.0
	_open_btn.offset_top  =  10.0; _open_btn.offset_bottom =  40.0
	if _font: _open_btn.add_theme_font_override("font", _font)
	_open_btn.add_theme_font_size_override("font_size", 13)
	for cn in ["font_color","font_hover_color","font_pressed_color"]: _open_btn.add_theme_color_override(cn, C_TEXT)
	var sn := StyleBoxFlat.new(); sn.bg_color = Color(0.10,0.08,0.07,0.92); sn.border_color = C_ACCENT
	sn.set_border_width_all(1); sn.set_content_margin_all(6)
	var sh := sn.duplicate() as StyleBoxFlat; sh.bg_color = Color(0.22,0.10,0.08,0.97)
	for st in ["normal","focus"]:   _open_btn.add_theme_stylebox_override(st, sn)
	for st in ["hover","pressed"]:  _open_btn.add_theme_stylebox_override(st, sh)
	_open_btn.pressed.connect(_on_open_btn_pressed)
	root_ctrl.add_child(_open_btn)

func _on_open_btn_pressed() -> void:
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if _open:
		close_panel()
		if bm != null: bm._player_menu_open = false
		return
	if bm == null: return
	bm._player_menu_open = true
	sync_and_open(bm.actors, bm.context.run_state, bm.removed_channels)
	refresh_log(bm.battle_hud._log_lines)


# ── Panel layout ──────────────────────────────────────────────────────────────

func _build_panel() -> void:
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_ctrl); _panel = root_ctrl

	# Fully opaque background — covers the entire screen with no bleed-through
	var dim := ColorRect.new(); dim.color = C_BG
	dim.set_anchors_preset(Control.PRESET_FULL_RECT); dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(dim)

	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.set_offsets_preset(Control.PRESET_FULL_RECT)
	var sbox := StyleBoxFlat.new(); sbox.bg_color = Color(0,0,0,0)  # transparent — dim provides the bg
	sbox.border_color = C_BORDER
	sbox.set_border_width_all(0); sbox.set_content_margin_all(24)
	box.add_theme_stylebox_override("panel", sbox); _panel.add_child(box)

	var outer := VBoxContainer.new(); outer.add_theme_constant_override("separation", 12)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	box.add_child(outer)

	# Header
	var header := HBoxContainer.new(); header.add_theme_constant_override("separation", 0)
	outer.add_child(header)
	var title := _lbl("ARRANGEMENT VIEW", 17, C_TEXT); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var actor_lbl := _lbl("", 13, C_GOLD); actor_lbl.name = "ActorLbl"; header.add_child(actor_lbl)
	outer.add_child(_hrule(C_ACCENT))

	var body_wrap := HBoxContainer.new()  # centres the column layout horizontally
	body_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	body_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body_wrap)

	var body := HBoxContainer.new(); body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(1240, 0)  # cap total column width
	body_wrap.add_child(body)

	# Col 1 — Party (warm)
	var col1 := PanelContainer.new(); col1.custom_minimum_size = Vector2(220, 0)
	col1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var c1s := StyleBoxFlat.new(); c1s.bg_color = C_WARM_BG; c1s.border_color = C_BORDER
	c1s.set_border_width_all(1); c1s.border_width_right = 0; c1s.set_content_margin_all(10)
	col1.add_theme_stylebox_override("panel", c1s); body.add_child(col1)
	var c1i := VBoxContainer.new(); c1i.add_theme_constant_override("separation", 6); col1.add_child(c1i)
	c1i.add_child(_lbl("PARTY", 11, C_DIM))
	c1i.add_child(_hrule(Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.35)))
	var ps := ScrollContainer.new(); ps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ps.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; c1i.add_child(ps)
	_party_col = VBoxContainer.new(); _party_col.add_theme_constant_override("separation", 6)
	_party_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ps.add_child(_party_col)

	# Col 2 — Actions (split: warm top + cool bottom)
	var col2 := VBoxContainer.new(); col2.custom_minimum_size = Vector2(230, 0)
	col2.add_theme_constant_override("separation", 0); body.add_child(col2)

	_action_top = PanelContainer.new()
	_action_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_action_top.size_flags_stretch_ratio = 0.55
	var ts := StyleBoxFlat.new(); ts.bg_color = C_WARM_BG; ts.border_color = C_BORDER
	ts.set_border_width_all(1); ts.border_width_right = 0; ts.set_content_margin_all(10)
	_action_top.add_theme_stylebox_override("panel", ts); col2.add_child(_action_top)
	var ti := VBoxContainer.new(); ti.add_theme_constant_override("separation", 6)
	ti.size_flags_vertical = Control.SIZE_EXPAND_FILL; _action_top.add_child(ti)
	ti.add_child(_lbl("ACTIONS", 11, C_DIM))
	ti.add_child(_hrule(Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.35)))
	var ss2 := ScrollContainer.new(); ss2.custom_minimum_size = Vector2(0, 38)
	ss2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; ti.add_child(ss2)
	_section_col = VBoxContainer.new(); _section_col.add_theme_constant_override("separation", 4)
	_section_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ss2.add_child(_section_col)
	ti.add_child(_hrule(Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.5)))
	_skill_scroll = ScrollContainer.new(); var sksc := _skill_scroll
	sksc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sksc.size_flags_stretch_ratio = 1.0
	sksc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; ti.add_child(sksc)
	_skill_col = VBoxContainer.new(); _skill_col.add_theme_constant_override("separation", 4)
	_skill_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sksc.add_child(_skill_col)
	_item_scroll = ScrollContainer.new(); var itsc := _item_scroll
	itsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	itsc.size_flags_stretch_ratio = 1.0
	itsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; ti.add_child(itsc)
	_item_col = VBoxContainer.new(); _item_col.add_theme_constant_override("separation", 3)
	_item_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; itsc.add_child(_item_col)

	_action_bot = PanelContainer.new()
	_action_bot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_action_bot.size_flags_stretch_ratio = 0.45
	var bs := StyleBoxFlat.new(); bs.bg_color = C_COOL_BG; bs.border_color = C_BORDER
	bs.set_border_width_all(1); bs.border_width_right = 0; bs.border_width_top = 0
	bs.set_content_margin_all(10)
	_action_bot.add_theme_stylebox_override("panel", bs); col2.add_child(_action_bot)
	_action_bot_style = bs
	var bi := VBoxContainer.new(); bi.add_theme_constant_override("separation", 6); _action_bot.add_child(bi)
	bi.add_child(_lbl("COMPONENTS", 11, C_DIM))
	var cd := _hrule(Color(C_BLUE.r, C_BLUE.g, C_BLUE.b, 0.35))
	_cool_divider = cd
	bi.add_child(cd)
	var ptsc := ScrollContainer.new(); ptsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ptsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; bi.add_child(ptsc)
	_part_col = VBoxContainer.new(); _part_col.add_theme_constant_override("separation", 3)
	_part_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ptsc.add_child(_part_col)

	# Col 3 — Enemies (cool)
	var col3 := PanelContainer.new(); col3.custom_minimum_size = Vector2(230, 0)
	col3.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var c3s := StyleBoxFlat.new(); c3s.bg_color = C_COOL_BG; c3s.border_color = C_BORDER
	c3s.set_border_width_all(1); c3s.border_width_left = 0; c3s.set_content_margin_all(10)
	col3.add_theme_stylebox_override("panel", c3s); body.add_child(col3)
	_enemy_col_style = c3s
	var c3i := VBoxContainer.new(); c3i.add_theme_constant_override("separation", 6); col3.add_child(c3i)
	c3i.add_child(_lbl("ENEMIES", 11, C_DIM))
	var ed := _hrule(Color(C_BLUE.r, C_BLUE.g, C_BLUE.b, 0.35))
	_enemy_divider = ed
	c3i.add_child(ed)
	var es := ScrollContainer.new(); es.size_flags_vertical = Control.SIZE_EXPAND_FILL
	es.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; c3i.add_child(es)
	_target_col = VBoxContainer.new(); _target_col.add_theme_constant_override("separation", 4)
	_target_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; es.add_child(_target_col)

	# Divider + Col 4 — Log
	body.add_child(_vrule())
	var col4 := VBoxContainer.new(); col4.custom_minimum_size = Vector2(200, 0)
	col4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col4.add_theme_constant_override("separation", 6); body.add_child(col4)
	col4.add_child(_lbl("BATTLE LOG", 11, C_DIM)); col4.add_child(_hrule(C_BORDER))
	var lsc := ScrollContainer.new(); lsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; col4.add_child(lsc)
	_log_scroll = lsc
	_log_col = VBoxContainer.new(); _log_col.add_theme_constant_override("separation", 5)
	_log_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; lsc.add_child(_log_col)

	# Footer
	outer.add_child(_hrule(C_BORDER))
	var score_script := load("res://UI/2D/Scripts/tempo_score.gd")
	_tempo_score = score_script.new()
	_tempo_score.custom_minimum_size = Vector2(0, 90)
	_tempo_score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(_tempo_score)
	outer.add_child(_hrule(Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.4)))
	_status_lbl = _lbl("", 12, C_DIM); _status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_status_lbl)
	var footer := HBoxContainer.new(); footer.add_theme_constant_override("separation", 10)
	footer.alignment = BoxContainer.ALIGNMENT_END; outer.add_child(footer)
	footer.add_child(_btn("RETURN TO SESSION VIEW", func(): close_panel()))
	_confirm_btn = _btn("CONFIRM", func(): _on_confirm()); _confirm_btn.disabled = true
	footer.add_child(_confirm_btn)


# ── Party ───────────────────────────────────────────────────────────────────────

func _refresh_party() -> void:
	for c in _party_col.get_children(): c.queue_free()
	var players := _all_actors.filter(func(a): return (a as BattleActor).team == BattleActor.Team.PLAYER)
	for actor in players: _party_col.add_child(_make_party_card(actor as BattleActor))

## Refresh party cards without disturbing the current stage or keyboard focus.
## Safe to call while the player is mid-selection.
func _refresh_party_silent() -> void:
	_refresh_party()
	# Re-apply focus so the highlight isn't lost after the card rebuild.
	if _stage == Stage.PARTY:
		call_deferred("_kb_apply_focus")

func _make_party_card(a: BattleActor) -> Control:
	var is_active := (a == _actor); var is_ready := a in _ready_actors
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new(); cs.set_content_margin_all(8)
	if is_active:
		cs.bg_color = Color(0.18,0.12,0.04); cs.border_color = C_GOLD; cs.set_border_width_all(2)
	elif is_ready:
		cs.bg_color = Color(0.07,0.12,0.06); cs.border_color = C_GREEN; cs.set_border_width_all(1)
	else:
		cs.bg_color = C_PANEL; cs.border_color = C_BORDER; cs.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", cs); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new(); vbox.add_theme_constant_override("separation", 3); card.add_child(vbox)
	var name_col : Color = C_GOLD if is_active else (C_GREEN if is_ready else C_TEXT)
	var name_row := HBoxContainer.new(); name_row.add_theme_constant_override("separation", 8)
	var nl := _lbl(a.display_name.to_upper(), 13, name_col); nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(nl)
	if is_ready and not is_active: name_row.add_child(_lbl("READY", 10, C_GREEN))
	name_row.add_child(_lbl("LV %d" % (a.party_member.level if a.party_member else 1), 10, C_DIM))
	vbox.add_child(name_row)
	var hp_col : Color = C_RED if a.hp <= int(a.max_hp * 0.25) else C_TEXT
	vbox.add_child(_lbl("CORP  %d / %d" % [a.hp, a.max_hp], 11, hp_col))
	if a.party_member != null and a.party_member.has_will():
		var ap_col : Color = C_BLUE if a.party_member.will >= a.party_member.max_will else C_DIM
		vbox.add_child(_lbl("AP  %d / %d" % [a.party_member.will, a.party_member.max_will], 11, ap_col))
	elif a.run_state != null:
		vbox.add_child(_lbl("BB  %d / %d" % [a.run_state.ammo, a.run_state.gun_clip], 11, C_GOLD))
	vbox.add_child(_lbl("BPM  %d" % a.bpm, 11, C_DIM))
	vbox.add_child(_lbl("TEMPO  %d" % a.tempo, 11, C_DIM))
	if not a.active_effects.is_empty():
		var parts : Array = []
		for fx in a.active_effects:
			var fid := str(fx.get("id","")); if fid != "" and fid != "_stat_change": parts.append(fid.to_upper())
		if not parts.is_empty(): vbox.add_child(_lbl(" · ".join(parts), 10, C_DIM))
	# Show queued action if one is pending for this actor
	var qid := a.get_instance_id()
	if _queued_actions.has(qid):
		var qa : Dictionary = _queued_actions[qid]
		var qname : String = qa["skill"].get("name", qa["skill"].get("key", "act")).to_upper()
		vbox.add_child(_lbl("⏳ " + qname, 10, C_GOLD))
		var cap_a := a; var area := Button.new()
		area.flat = true; area.focus_mode = Control.FOCUS_NONE
		area.set_anchors_preset(Control.PRESET_FULL_RECT); area.text = ""
		var t := StyleBoxEmpty.new()
		for st in ["normal","focus"]: area.add_theme_stylebox_override(st, t)
		var hs := StyleBoxFlat.new(); hs.bg_color = Color(0.12,0.20,0.10,0.6); hs.set_border_width_all(0)
		for st in ["hover","pressed"]: area.add_theme_stylebox_override(st, hs)
		area.pressed.connect(func(): _on_ready_actor_selected(cap_a))
		area.set_meta("card_style", cs)
		card.add_child(area)
	elif not is_active and a.is_alive():
		# Non-ready, living ally — allow pre-queuing an action
		var cap_a := a; var area := Button.new()
		area.flat = true; area.focus_mode = Control.FOCUS_NONE
		area.set_anchors_preset(Control.PRESET_FULL_RECT); area.text = ""
		var t := StyleBoxEmpty.new()
		for st in ["normal","focus"]: area.add_theme_stylebox_override(st, t)
		var hs := StyleBoxFlat.new(); hs.bg_color = Color(0.10,0.10,0.18,0.5); hs.set_border_width_all(0)
		for st in ["hover","pressed"]: area.add_theme_stylebox_override(st, hs)
		area.pressed.connect(func(): _on_any_actor_selected(cap_a))
		area.set_meta("card_style", cs)
		card.add_child(area)
	return card


func _on_ready_actor_selected(actor: BattleActor) -> void:
	_actor = actor; _reset_selection(); _clear_action_top(); _clear_part_col()
	_refresh_party(); _refresh_enemies(); _update_confirm()
	if is_instance_valid(_tempo_score): _tempo_score.setup(_all_actors, _actor, _font)
	var actor_lbl := _panel.find_child("ActorLbl", true, false) as Label
	if actor_lbl: actor_lbl.text = _actor.display_name.to_upper()
	_build_section_picker()
	_set_status("Choose SKILLS or ITEMS."); _kb_set_stage(Stage.SECTION)
	actor_commanding.emit(actor)

func _on_any_actor_selected(actor: BattleActor) -> void:
	## Select a non-ready actor to pre-queue their next action.
	_actor = actor; _reset_selection(); _clear_action_top(); _clear_part_col()
	_refresh_party(); _refresh_enemies(); _update_confirm()
	if is_instance_valid(_tempo_score): _tempo_score.setup(_all_actors, _actor, _font)
	var actor_lbl := _panel.find_child("ActorLbl", true, false) as Label
	if actor_lbl: actor_lbl.text = _actor.display_name.to_upper() + "  [QUEUING]"
	_build_section_picker()
	_set_status("Queue an action for %s." % actor.display_name.to_upper())
	_kb_set_stage(Stage.SECTION)


# ── Action top: section picker + lists ───────────────────────────────────────────

func _clear_action_top() -> void:
	for c in _section_col.get_children(): c.queue_free()
	for c in _skill_col.get_children():   c.queue_free()
	for c in _item_col.get_children():    c.queue_free()
	if is_instance_valid(_skill_scroll): _skill_scroll.show()
	if is_instance_valid(_item_scroll):  _item_scroll.show()

func _build_section_picker() -> void:
	_clear_action_top()
	var skills_btn := _tab_btn("SKILLS", func(): _enter_skill_list())
	var items_btn  := _tab_btn("ITEMS",  func(): _enter_item_list())
	skills_btn.set_meta("tab_index", 0)
	items_btn.set_meta("tab_index", 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(skills_btn)
	row.add_child(items_btn)
	_section_col.add_child(row)

func _section_btn(txt: String, cb: Callable) -> Button:
	var b := Button.new(); b.text = txt; b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if _font: b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 13)
	for cn in ["font_color","font_hover_color","font_pressed_color"]: b.add_theme_color_override(cn, C_TEXT)
	var sn := StyleBoxFlat.new(); sn.bg_color = Color(0.12,0.09,0.06)
	sn.border_color = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.4)
	sn.set_border_width_all(1); sn.set_content_margin_all(8)
	var sh := sn.duplicate() as StyleBoxFlat; sh.bg_color = Color(0.20,0.14,0.06); sh.border_color = C_GOLD
	for st in ["normal","focus"]:   b.add_theme_stylebox_override(st, sn)
	for st in ["hover","pressed"]:  b.add_theme_stylebox_override(st, sh)
	b.pressed.connect(cb); return b

func _enter_skill_list() -> void:
	for c in _skill_col.get_children(): c.queue_free()
	for c in _item_col.get_children():  c.queue_free()
	
	if is_instance_valid(_skill_scroll): _skill_scroll.show()
	if is_instance_valid(_item_scroll):  _item_scroll.hide()
	_active_tab = 0; _refresh_tab_highlight()
	
	if _actor == null: return
	var skills := _actor.get_skills()
	const KEY_ORDER := {"attack": 0, "support": 1, "special": 2}
	skills.sort_custom(func(a, b): return KEY_ORDER.get(a.get("key",""), 99) < KEY_ORDER.get(b.get("key",""), 99))
	if skills.is_empty():
		_skill_col.add_child(_lbl("No actions available.", 11, C_DIM))
	else:
		for sk in skills:
			var sd : Dictionary = sk
			var key : String = sd.get("key", "attack")
			var name_str : String = sd.get("name", key.capitalize())
			var btn := _btn(name_str, func(): _on_skill_pressed(sd))
			_skill_col.add_child(btn)
			var tags : String = _skill_cost_string(sd, key)
			if sd.get("aoe", false):     tags += "  [ALL]"
			if sd.get("struggle",false): tags += "  [STRUGGLE]"
			_skill_col.add_child(_lbl(tags, 10, C_DIM))
			var skill_data = SkillDirectory.get_skill(name_str)
			var summary : String = skill_data.summary if skill_data != null and skill_data.summary.strip_edges() != "" else ""
			if summary != "":
				var sl := _lbl(summary, 10, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.75))
				sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				sl.custom_minimum_size = Vector2(180, 0); _skill_col.add_child(sl)
			var gap := Control.new(); gap.custom_minimum_size = Vector2(0, 4); _skill_col.add_child(gap)
	_set_status("Select a skill."); _kb_set_stage(Stage.SKILL_LIST)

func _skill_cost_string(sd: Dictionary, key: String) -> String:
	if key == "attack":
		if sd.get("struggle", false): return "No cost"
		var cost : int = sd.get("ammo_cost", 0); if cost > 0: return "%d BB" % cost
		var will : int = sd.get("will_cost", 0); if will > 0: return "%d AP" % will
		return "1 BB"
	var wc : int = sd.get("will_cost", 0); if wc > 0: return "%d AP" % wc
	return "No cost"

func _enter_item_list() -> void:
	for c in _skill_col.get_children(): c.queue_free()
	for c in _item_col.get_children():  c.queue_free()
	
	if is_instance_valid(_skill_scroll): _skill_scroll.hide()
	if is_instance_valid(_item_scroll):  _item_scroll.show()
	_active_tab = 1; _refresh_tab_highlight()
	
	_refresh_items(); _set_status("Select an item."); _kb_set_stage(Stage.ITEM_LIST)	

func _refresh_tab_highlight() -> void:
	if not is_instance_valid(_section_col): return
	var row := _section_col.get_child(0) if _section_col.get_child_count() > 0 else null
	if not is_instance_valid(row): return
	var active_sn := StyleBoxFlat.new()
	active_sn.bg_color = Color(0.18, 0.13, 0.04); active_sn.border_color = C_GOLD
	active_sn.set_border_width_all(2); active_sn.set_content_margin_all(8)
	var inactive_sn := StyleBoxFlat.new()
	inactive_sn.bg_color = Color(0.07, 0.06, 0.05); inactive_sn.border_color = C_BORDER
	inactive_sn.set_border_width_all(1); inactive_sn.set_content_margin_all(8)
	for i in row.get_child_count():
		var b := row.get_child(i) as Button
		if b == null: continue
		b.add_theme_stylebox_override("normal", active_sn if i == _active_tab else inactive_sn)


func _refresh_items() -> void:
	for c in _item_col.get_children(): c.queue_free()
	if _run_state == null: _item_col.add_child(_lbl("No inventory.", 11, C_DIM)); return
	var battle_items := _run_state.inventory.filter(func(inst):
		var cd := (inst as ItemInstance).item_data as ConsumableData
		return cd != null and cd.usable_in_battle)
	if battle_items.is_empty(): _item_col.add_child(_lbl("None usable.", 11, C_DIM)); return
	for inst in battle_items:
		var cd := inst.item_data as ConsumableData; var cap : ItemInstance = inst
		var btn := _btn("%s ×%d" % [cd.item_name, inst.stacks], func(): _on_item_pressed(cap))
		if _item_used_this_turn: btn.disabled = true; btn.tooltip_text = "Already used an item this turn."
		_item_col.add_child(btn)
	if _item_used_this_turn: _item_col.add_child(_lbl("1 item per turn.", 10, C_DIM))


# ── Skill / Item handlers ───────────────────────────────────────────────────

func _on_skill_pressed(sd: Dictionary) -> void:
	_sel_skill = sd; _sel_target = null; _sel_part = null; _sel_item = null
	_sel_filter = -1; _is_filter_mode = false
	var key : String = sd.get("key", "")
	var aoe : bool = sd.get("aoe", false); var struggle : bool = sd.get("struggle", false)
	var support : bool = sd.get("ally_target", false) or key == "support"
	_is_filter_mode = key == "special" and _actor != null and (_actor.party_member == null or not _actor.party_member.has_will())
	if _is_filter_mode:
		_set_status("Choose a channel to unveil."); _show_filter_buttons(); _refresh_enemies()
		_kb_set_stage(Stage.PART)
	elif aoe or struggle:
		_sel_target = null; _clear_part_col()
		_set_status("Targets: ALL — press CONFIRM."); _update_confirm_done(); _kb_set_stage(Stage.DONE)
	elif support:
		_set_status("Select an ally to target."); _refresh_enemies(); _clear_part_col(); _kb_set_stage(Stage.TARGET)
	else:
		_set_status("Select an enemy."); _refresh_enemies(); _clear_part_col(); _kb_set_stage(Stage.TARGET)

func _on_item_pressed(inst: ItemInstance) -> void:
	_sel_item = inst; _sel_skill = {}; _sel_target = null; _sel_part = null
	var cd := inst.item_data as ConsumableData
	var needs_target := cd != null and cd.effect_type not in ["corpus_all","will_all","reprise","tie","flee"]
	_clear_part_col()
	if needs_target:
		_set_status("Select an ally to use %s on." % cd.item_name)
		_refresh_enemies(); _kb_set_stage(Stage.TARGET)
	else:
		_set_status("Use %s on EVERYONE — press CONFIRM." % cd.item_name)
		_update_confirm_done(); _kb_set_stage(Stage.DONE)


# ── Filter buttons ───────────────────────────────────────────────────────────

const _FILTER_CHANNELS := [
	{"label": "R", "channel": 1, "color": Color(1.0, 0.25, 0.25, 1.0)},
	{"label": "G", "channel": 2, "color": Color(0.25, 1.0, 0.35, 1.0)},
	{"label": "B", "channel": 4, "color": Color(0.25, 0.55, 1.0, 1.0)},
]

func _show_filter_buttons() -> void:
	_clear_part_col(); _part_col.add_child(_lbl("CHANNEL", 11, C_DIM))
	for ch in _FILTER_CHANNELS:
		var already_used : bool = (_removed_channels & int(ch["channel"])) != 0
		var cap_ch : int = int(ch["channel"]); var col : Color = ch["color"]
		var btn := Button.new(); btn.text = ch["label"]; btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = already_used; btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _font: btn.add_theme_font_override("font", _font)
		btn.add_theme_font_size_override("font_size", 16)
		var sn := StyleBoxFlat.new()
		sn.bg_color = Color(col.r*0.12, col.g*0.12, col.b*0.12, 1.0)
		sn.border_color = Color(col.r*0.45, col.g*0.45, col.b*0.45, 1.0)
		sn.set_border_width_all(1); sn.set_content_margin_all(8)
		var sh := sn.duplicate() as StyleBoxFlat
		sh.bg_color = Color(col.r*0.28, col.g*0.28, col.b*0.28, 1.0); sh.border_color = col
		for st in ["normal","focus","disabled"]: btn.add_theme_stylebox_override(st, sn)
		for st in ["hover","pressed"]:          btn.add_theme_stylebox_override(st, sh)
		btn.add_theme_color_override("font_color", col if not already_used else C_DIM)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("font_disabled_color", Color(col.r*0.25,col.g*0.25,col.b*0.25,1.0))
		if not already_used: btn.pressed.connect(func(): _on_filter_pressed(cap_ch))
		_part_col.add_child(btn)

func _on_filter_pressed(channel: int) -> void:
	_sel_filter = channel
	var names := {1: "RED", 2: "GREEN", 4: "BLUE"}
	_set_status("Channel: %s — press CONFIRM." % names.get(channel, str(channel)))
	_update_confirm_done(); _kb_set_stage(Stage.DONE)


# ── Enemy column ────────────────────────────────────────────────────────────────

func _apply_enemy_col_tint() -> void:
	if not is_instance_valid(_enemy_col_style): return
	var enemies := _all_actors.filter(func(a): return (a as BattleActor).team == BattleActor.Team.ENEMY)
	var tc : Color
	if enemies.is_empty():
		tc = Color(0.28, 0.22, 0.35, 1.0)  # default cool purple-grey
	else:
		tc = (enemies[0] as BattleActor).theme_col
		if tc == Color(): tc = Color(0.28, 0.22, 0.35, 1.0)
	var bg      := Color(tc.r * 0.10, tc.g * 0.10, tc.b * 0.10, 1.0)
	var border  := Color(tc.r * 0.35, tc.g * 0.35, tc.b * 0.35, 1.0)
	var divider := Color(tc.r * 0.55, tc.g * 0.55, tc.b * 0.55, 0.45)
	# Col 3 — enemy panel
	_enemy_col_style.bg_color     = bg
	_enemy_col_style.border_color = border
	# Col 2 bottom — parts panel
	if is_instance_valid(_action_bot_style):
		_action_bot_style.bg_color     = bg
		_action_bot_style.border_color = border
	# Dividers inside col2-bottom and col3
	if is_instance_valid(_cool_divider):   _cool_divider.color   = divider
	if is_instance_valid(_enemy_divider):  _enemy_divider.color  = divider

func _refresh_enemies() -> void:
	for c in _target_col.get_children(): c.queue_free()
	# Ally-targeting: support skills OR items that target individual allies
	var support_skill : bool = not _sel_skill.is_empty() and \
		(_sel_skill.get("ally_target", false) or _sel_skill.get("key", "") == "support")
	var item_needs_ally : bool = _sel_item != null and (_sel_item.item_data as ConsumableData) != null and \
		(_sel_item.item_data as ConsumableData).effect_type not in ["corpus_all","will_all","reprise","tie","flee"]
	var support_mode : bool = support_skill or item_needs_ally
	if support_mode:
		var players := _all_actors.filter(func(a): return (a as BattleActor).team == BattleActor.Team.PLAYER)
		if players.is_empty(): _target_col.add_child(_lbl("No allies.", 11, C_DIM)); return
		for actor in players: _target_col.add_child(_make_target_card(actor as BattleActor, true))
		return
	var enemies := _all_actors.filter(func(a):
		return (a as BattleActor).team == BattleActor.Team.ENEMY and (a as BattleActor).is_alive())
	if enemies.is_empty(): _target_col.add_child(_lbl("No enemies.", 11, C_DIM)); return
	for actor in enemies: _target_col.add_child(_make_target_card(actor as BattleActor, false))

func _make_target_card(a: BattleActor, is_ally: bool) -> Control:
	var card := VBoxContainer.new(); card.add_theme_constant_override("separation", 3)
	var highlight := (a == _sel_target)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07,0.10,0.15) if highlight else C_PANEL
	sbox.border_color = C_GOLD if highlight else C_BORDER
	sbox.set_border_width_all(1); sbox.set_content_margin_all(7)
	var panel := PanelContainer.new(); panel.add_theme_stylebox_override("panel", sbox)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; card.add_child(panel)
	var inner := VBoxContainer.new(); inner.add_theme_constant_override("separation", 2); panel.add_child(inner)
	var revealed : bool = is_ally or a.stats_revealed
	var name_col : Color = C_GOLD if highlight else (C_GREEN if is_ally else C_TEXT)
	var hp_col   : Color = C_RED if a.hp <= int(a.max_hp * 0.25) else C_TEXT
	inner.add_child(_lbl(a.display_name.to_upper(), 13, name_col))
	if revealed: inner.add_child(_lbl("CORP  %d / %d" % [a.hp, a.max_hp], 11, hp_col))
	else:        inner.add_child(_lbl("CORP  ???", 11, C_DIM))
	if revealed:
		var sr := HBoxContainer.new(); sr.add_theme_constant_override("separation", 10)
		sr.add_child(_lbl("SHARP %d" % a.attack_power, 10, C_DIM))
		if a.flat_defense > 0: sr.add_child(_lbl("FLAT %d" % a.flat_defense, 10, C_DIM))
		sr.add_child(_lbl("BPM %d" % a.bpm, 10, C_DIM))
		if a.tempo > 0: sr.add_child(_lbl("TEMPO %d" % a.tempo, 10, C_DIM))
		if a.flat_defense > 0: sr.add_child(_lbl("FLAT %d" % a.flat_defense, 10, C_DIM))
		inner.add_child(sr)
	if revealed and not a.active_effects.is_empty():
		var fp : Array = []
		for fx in a.active_effects:
			var fid := str(fx.get("id","")); var dur := int(fx.get("duration",0))
			if fid != "" and fid != "_stat_change": fp.append(fid.to_upper() + (" %dt" % dur if dur > 0 else ""))
		if not fp.is_empty(): inner.add_child(_lbl(" · ".join(fp), 10, C_DIM))
	if not is_ally:
		var vp := a.get_visible_parts(_removed_channels)
		if not vp.is_empty():
			var pl : Array = []
			for bp in vp:
				var m := (" ×%.1f" % bp.damage_multiplier) if bp.damage_multiplier != 1.0 else ""
				pl.append(bp.part_name + m)
			inner.add_child(_lbl("  " + "  ".join(pl), 10, C_DIM))
	var has_action := not _sel_skill.is_empty() or _sel_item != null
	if has_action and not _is_filter_mode:
		var cap_a := a; var area := Button.new()
		area.flat = true; area.focus_mode = Control.FOCUS_NONE
		area.set_anchors_preset(Control.PRESET_FULL_RECT); area.text = ""
		var t := StyleBoxEmpty.new()
		for st in ["normal","focus"]: area.add_theme_stylebox_override(st, t)
		var hs := StyleBoxFlat.new(); hs.bg_color = Color(C_GOLD.r,C_GOLD.g,C_GOLD.b,0.15)
		hs.border_color = C_GOLD; hs.set_border_width_all(1)
		for st in ["hover","pressed"]: area.add_theme_stylebox_override(st, hs)
		area.pressed.connect(func(): _on_target_pressed(cap_a, is_ally))
		area.set_meta("card_style", sbox)   # ← ADD THIS LINE
		panel.add_child(area)
	return card

func _on_target_pressed(a: BattleActor, is_ally: bool) -> void:
	_sel_target = a; _sel_part = null
	var aoe : bool = _sel_skill.get("aoe", false)
	var support : bool = is_ally or _sel_skill.get("ally_target",false) or _sel_skill.get("key","") == "support"
	_refresh_enemies()
	if aoe or support or _sel_item != null:
		_set_status("Target: %s — press CONFIRM." % a.display_name.to_upper())
		_clear_part_col(); _update_confirm_done(); _kb_set_stage(Stage.DONE)
		return
	_set_status("Select a body part."); _populate_parts(a); _kb_set_stage(Stage.PART)


# ── Parts ─────────────────────────────────────────────────────────────────────

func _populate_parts(a: BattleActor) -> void:
	_clear_part_col()
	var visible_parts : Array[BodyPartData] = a.get_visible_parts(_removed_channels)
	if visible_parts.is_empty():
		_sel_part = null
		_set_status("Target: %s — press CONFIRM." % a.display_name.to_upper())
		_update_confirm_done(); _kb_set_stage(Stage.DONE); return
	for bp in visible_parts:
		var cap_bp : BodyPartData = bp
		var mult_str := ("  ×%.1f" % bp.damage_multiplier) if bp.damage_multiplier != 1.0 else ""
		_part_col.add_child(_btn(bp.part_name + mult_str, func(): _on_part_pressed(cap_bp)))

func _on_part_pressed(bp: BodyPartData) -> void:
	_sel_part = bp
	_set_status("Target: %s — %s — press CONFIRM." % [_sel_target.display_name.to_upper(), bp.part_name])
	_update_confirm_done(); _kb_set_stage(Stage.DONE)

func _clear_part_col() -> void:
	for c in _part_col.get_children(): c.queue_free()


# ── Confirm ───────────────────────────────────────────────────────────────────

func _update_confirm_done() -> void:
	_stage = Stage.DONE; _update_confirm()

func _update_confirm() -> void:
	if _confirm_btn == null: return
	var can_confirm := false
	if not _sel_skill.is_empty():
		if _is_filter_mode: can_confirm = _sel_filter != -1
		elif _sel_skill.get("aoe",false) or _sel_skill.get("struggle",false): can_confirm = true
		else: can_confirm = _sel_target != null
	elif _sel_item != null:
		var cd := _sel_item.item_data as ConsumableData
		var needs_target := cd != null and cd.effect_type not in ["corpus_all","will_all","reprise","tie","flee"]
		can_confirm = not needs_target or _sel_target != null
	_confirm_btn.disabled = not can_confirm

func _on_confirm() -> void:
	if not _sel_skill.is_empty():
		if _is_filter_mode: _do_filter_confirm()
		else: _do_skill_confirm()
	elif _sel_item != null: _do_item_confirm()

func _do_skill_confirm() -> void:
	if _sel_skill.is_empty(): return
	var actor := _actor; var skill := _sel_skill
	var target := _sel_target; var part := _sel_part
	# Check readiness against the battle manager's authoritative list, not the
	# menu's snapshot — the snapshot may be stale for pre-queued actors.
	var bm = get_tree().get_first_node_in_group("battle_manager")
	var is_now_ready : bool = actor in _ready_actors or \
		(bm != null and actor in bm._atb_ready_players)
	if not is_now_ready:
		_queued_actions[actor.get_instance_id()] = {
			"actor": actor, "skill": skill,
			"target": weakref(target) if is_instance_valid(target) else null,
			"part": part
		}
		_reset_to_initial()
		_set_status("%s will %s when ready." % [actor.display_name.to_upper(), skill.get("name", skill.get("key", "act")).to_upper()])
		return
	skill_chosen.emit(actor, skill, target, part)
	_reset_to_initial()

func _do_filter_confirm() -> void:
	if _sel_filter == -1: return
	var actor := _actor; var skill := _sel_skill.duplicate()
	skill["_filter_channel"] = _sel_filter
	skill_chosen.emit(actor, skill, null, null)
	_reset_to_initial()

func _do_item_confirm() -> void:
	if _sel_item == null: return
	var used := ItemRegistry.use_item(_run_state, _sel_item, _sel_item_pm)
	if not used: _set_status("Cannot use that item right now."); return
	_item_used_this_turn = true; _reset_to_initial(); _set_status("Item used. Choose your action.")

func _reset_selection() -> void:
	_sel_skill = {}; _sel_target = null; _sel_part = null
	_sel_item = null; _sel_item_pm = null; _sel_filter = -1; _is_filter_mode = false

func _reset_to_initial() -> void:
	_actor = null; _reset_selection(); _clear_action_top(); _refresh_enemies()
	_clear_part_col(); _update_confirm()
	_set_status("Select a ready ally to command." if not _ready_actors.is_empty() else "")
	_refresh_party(); _kb_set_stage(Stage.PARTY)


# ── Helpers ───────────────────────────────────────────────────────────────────

## Check all queued actions and fire any whose actor is now ready according to
## Hide the 3D split-viewport so the battle menu occupies the full screen.
func _hide_viewport_split() -> void:
	_resolve_viewport_nodes()
	if is_instance_valid(_viewport_split): _viewport_split.hide()
	if is_instance_valid(_viewport_sep):   _viewport_sep.hide()

## Restore the 3D split-viewport after the menu closes.
func _show_viewport_split() -> void:
	if is_instance_valid(_viewport_split): _viewport_split.show()
	if is_instance_valid(_viewport_sep):   _viewport_sep.show()

## Walk up from the battle manager to find the scene root, then locate the
## split-viewport nodes by their fixed names.  Results are cached.
func _resolve_viewport_nodes() -> void:
	if is_instance_valid(_viewport_split): return   # already cached
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm == null: return
	var root : Node = bm.get_parent()
	if root == null: return
	_viewport_split = root.get_node_or_null("HBoxContainer")
	_viewport_sep   = root.get_node_or_null("VSeparator")

## Spawn a one-shot CRT channel-switch flash overlay.
func _spawn_crt_flash() -> void:
	var CrtScript := load("res://UI/2D/Scripts/crt_channel_switch.gd") as GDScript
	if CrtScript == null: return
	var layer := CanvasLayer.new()
	layer.layer = 120   # above everything
	var node := Node2D.new()
	node.set_script(CrtScript)
	layer.add_child(node)
	get_tree().root.add_child(layer)
	node.play(get_viewport().get_visible_rect().size)
	node.tree_exited.connect(layer.queue_free)

## the battle manager. Returns true if at least one action was fired (so callers
## can skip further UI work for that frame).
func _drain_ready_queues(bm) -> bool:
	if _queued_actions.is_empty(): return false
	var fired := false
	for iid in _queued_actions.keys():
		var qa : Dictionary = _queued_actions[iid]
		var actor : BattleActor = qa.get("actor") as BattleActor
		if not is_instance_valid(actor) or not actor.is_alive():
			_queued_actions.erase(iid); continue
		var is_ready : bool = actor in _ready_actors or \
			(bm != null and actor in bm._atb_ready_players)
		if not is_ready: continue
		# Resolve target
		var tgt : BattleActor = null
		if qa.get("target") != null:
			var ref = qa["target"].get_ref()
			if is_instance_valid(ref) and (ref as BattleActor).is_alive():
				tgt = ref as BattleActor
		var needed_target : bool = not qa["skill"].get("aoe", false) \
			and not qa["skill"].get("struggle", false) \
			and qa.get("target") != null
		_queued_actions.erase(iid)
		if needed_target and tgt == null:
			_ready_actors.erase(actor)
			if _open:
				_refresh_party_silent()
				_set_status("%s's queued target is gone — choose a new action." % actor.display_name.to_upper())
				if _actor == null: call_deferred("_on_ready_actor_selected", actor)
			continue
		skill_chosen.emit(actor, qa["skill"], tgt, qa.get("part"))
		if bm != null: bm._atb_ready_players.erase(actor)
		_ready_actors.erase(actor)
		if _open: _refresh_party_silent()
		fired = true
	return fired

func _scroll_to_show(control: Control) -> void:
	if not is_instance_valid(control): return
	var node : Node = control.get_parent()
	while node != null:
		if node is ScrollContainer:
			(node as ScrollContainer).ensure_control_visible(control)
			return
		node = node.get_parent()

func _set_status(msg: String) -> void:
	if is_instance_valid(_status_lbl): _status_lbl.text = msg

func _lbl(txt: String, size: int, col: Color) -> Label:
	var l := Label.new(); l.text = txt
	l.add_theme_font_size_override("font_size", size)
	if _font: l.add_theme_font_override("font", _font)
	l.add_theme_color_override("font_color", col)
	return l

func _btn(txt: String, cb: Callable) -> Button:
	var b := Button.new(); b.text = txt; b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if _font: b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 12)
	for cn in ["font_color","font_hover_color","font_pressed_color"]: b.add_theme_color_override(cn, C_TEXT)
	var sn := StyleBoxFlat.new(); sn.bg_color = C_PANEL; sn.border_color = C_BORDER
	sn.set_border_width_all(1); sn.set_content_margin_all(7)
	var sh := sn.duplicate() as StyleBoxFlat; sh.bg_color = C_SEL; sh.border_color = C_ACCENT
	for st in ["normal","focus"]:   b.add_theme_stylebox_override(st, sn)
	for st in ["hover","pressed"]:  b.add_theme_stylebox_override(st, sh)
	b.pressed.connect(cb); return b

func _tab_btn(txt: String, cb: Callable) -> Button:
	var b := Button.new(); b.text = txt; b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font: b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 12)
	for cn in ["font_color","font_hover_color","font_pressed_color"]:
		b.add_theme_color_override(cn, C_TEXT)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.07, 0.06, 0.05); sn.border_color = C_BORDER
	sn.set_border_width_all(1); sn.border_width_bottom = 0; sn.set_content_margin_all(7)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.20, 0.14, 0.06); sh.border_color = C_GOLD
	for st in ["normal", "focus"]:  b.add_theme_stylebox_override(st, sn)
	for st in ["hover", "pressed"]: b.add_theme_stylebox_override(st, sh)
	b.pressed.connect(cb); return b

func _hrule(col: Color) -> ColorRect:
	var r := ColorRect.new(); r.color = col
	r.custom_minimum_size = Vector2(0, 1); r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r

func _vrule() -> ColorRect:
	var r := ColorRect.new(); r.color = C_BORDER
	r.custom_minimum_size = Vector2(1, 0); r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return r
