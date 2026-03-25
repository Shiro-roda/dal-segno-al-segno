extends CanvasLayer
class_name InventoryBar
# Dungeon HUD: phase label + Segno pips + excess ammo.
# Lives as its own CanvasLayer in game_root so anchoring is always viewport-relative.
# layer = 50 keeps it above dungeon/battle but below the TV overlay (layer 100+).

const C_BG       := Color(0.06, 0.05, 0.05, 0.92)
const C_BORDER   := Color(0.35, 0.28, 0.22, 1.0)
const C_DIM      := Color(0.45, 0.40, 0.35, 1.0)
const C_TEXT     := Color(0.88, 0.83, 0.74, 1.0)
# Per-pip colours: R, G, B at three fill states
const C_PIP_EMPTY := Color(0.082, 0.082, 0.097, 1.0)  # all pips unlit
const C_PIP_RGB_PART := [
	Color(0.55, 0.10, 0.10, 1.0),  # R dim
	Color(0.10, 0.40, 0.10, 1.0),  # G dim
	Color(0.10, 0.18, 0.55, 1.0),  # B dim
]
const C_PIP_RGB_FULL := [
	Color(1.0,  0.20, 0.20, 1.0),  # R bright
	Color(0.20, 1.0,  0.20, 1.0),  # G bright
	Color(0.25, 0.55, 1.0,  1.0),  # B bright
]
# Phase label colours
const C_PHASE_DC   := Color(0.55, 0.50, 0.43, 1.0)  # D.C.         — dim
const C_PHASE_DS   := Color(0.52, 0.42, 0.28, 1.0)  # D.S.         — warm gold
const C_PHASE_DCAS := Color(0.65, 0.72, 0.45, 1.0)  # D.C. al §    — muted green (gentle transit)
const C_PHASE_DSAS := Color(0.85, 0.60, 0.20, 1.0)  # D.S. al §    — amber warning
const C_PHASE_CA   := Color(0.72, 0.30, 0.30, 1.0)  # caesura      — muted red
const C_PHASE_AF   := Color(0.90, 0.80, 0.30, 1.0)  # al fine      — bright gold

const PIP_SIZE   := 10
const PIP_GAP    := 4

var _run_state    : RunState        = null
var _dungeon_run  : DungeonRunState = null
var _phase_lbl    : Button          = null   # was Label — Button handles input reliably
var _phase_sbox : StyleBoxFlat
var _annotation_lbl : Label         = null
var _annotation_open : bool         = false
var _phase_acknowledged : bool      = false  # true once player clicks the phase label
var _phase_flash_tween  : Tween     = null   # drives the strobe
var _pip_row      : HBoxContainer   = null
var _pip_nodes    : Array           = []   # Array[ColorRect]
var _excess_lbl   : Label           = null  # shows excess ammo pool
var _reroll_lbl      : Label           = null  # shows reroll charges
var _road_lbl        : Label           = null  # shows road tile count
var _money_lbl       : Label           = null  # shows current cuts
var _cap_lbl         : Label           = null  # shows active level cap
var _last_cap        : int             = -1
# RGB channel pip buttons
var _chan_btns       : Array           = []    # [r_btn, g_btn, b_btn]
var _channel_mask    : int             = 0b111 # mirrors dungeon_map_3d state

# Polling state
var _last_charges : int  = -1
var _last_phase   : int  = -1
var _last_excess  : int  = -1
var _last_rerolls : int  = -1
var _last_road    : int  = -1
var _last_money   : int  = -1


func _ready() -> void:
	layer = 50  # above dungeon/battle, below TV overlay
	add_to_group("phase_hud")
	_build_ui()
	call_deferred("_connect_party_menu")


func _connect_party_menu() -> void:
	var menu := get_tree().get_first_node_in_group("party_menu")
	if menu:
		if not menu.menu_opened.is_connected(_on_menu_opened):
			menu.menu_opened.connect(_on_menu_opened)
		if not menu.menu_closed.is_connected(_on_menu_closed):
			menu.menu_closed.connect(_on_menu_closed)


func _update_visibility() -> void:
	var dl := get_tree().get_first_node_in_group("dungeon_layer")
	var in_dungeon : bool = dl != null and (dl as CanvasLayer).visible
	var menu := get_tree().get_first_node_in_group("party_menu")
	var menu_open : bool = menu != null and menu.get("_open") == true
	visible = in_dungeon or menu_open


func _on_menu_opened() -> void:
	_update_visibility()


func _on_menu_closed() -> void:
	_update_visibility()


func _build_ui() -> void:
	# Full-rect container so anchors inside it are viewport-relative
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_ctrl)
	# The actual panel is a child of root_ctrl, pinned to its top-left
	var bar : Control = Control.new()
	bar.set("anchor_left",   0.0)
	bar.set("anchor_top",    0.0)
	bar.set("anchor_right",  0.0)
	bar.set("anchor_bottom", 0.0)
	bar.set("anchor_right",  0.0)
	bar.set("anchor_bottom", 0.0)
	bar.set("offset_left",   18.0)
	bar.set("offset_top",    18.0)
	bar.set("offset_right",  490.0)
	bar.set("offset_bottom", 82.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bar.set("mouse_filter",  Control.MOUSE_FILTER_IGNORE)
	root_ctrl.add_child(bar)
	_build_bar(bar)


func _build_bar(bar: Control) -> void:
	var bg_sbox := StyleBoxFlat.new()
	bg_sbox.bg_color     = C_BG
	bg_sbox.border_color = C_BORDER
	bg_sbox.set_border_width_all(1)
	bg_sbox.set_corner_radius_all(3)
	bg_sbox.set_content_margin_all(8)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", bg_sbox)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(panel)

	# Outer VBox — top row + collapsible annotation row
	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 0)
	outer_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(outer_vbox)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer_vbox.add_child(hbox)

	# Phase button — flat button so it looks like a label but takes input reliably.
	# Generous content margins widen the click area around the text.
	_phase_sbox = StyleBoxFlat.new()
	_phase_lbl = Button.new()
	_phase_lbl.text = "D.C."
	_phase_lbl.add_theme_font_size_override("font_size", 14)
	_phase_lbl.add_theme_color_override("font_color",         C_PHASE_DC)
	_phase_lbl.add_theme_color_override("font_hover_color",   C_PHASE_DC)
	_phase_lbl.add_theme_color_override("font_pressed_color", C_PHASE_DC)
	_phase_lbl.add_theme_color_override("font_focus_color",   C_PHASE_DC)
	_phase_lbl.focus_mode = Control.FOCUS_NONE
	_phase_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_phase_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_phase_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_phase_sbox.bg_color = Color(0.329, 0.306, 0.306, 0.05)
	_phase_sbox.set_border_width_all(0)
	_phase_sbox.set_content_margin_all(10) # this expands clickable area
	_phase_lbl.add_theme_constant_override("h_separation", 0) # optional
	_phase_lbl.add_theme_constant_override("outline_size", 0) # optional
	for st in ["normal", "hover", "pressed", "focus"]:
		_phase_lbl.add_theme_stylebox_override(st, _phase_sbox)
	_phase_lbl.pressed.connect(_on_phase_btn_pressed)
	_phase_lbl.mouse_entered.connect(_on_phase_hover_enter)
	_phase_lbl.mouse_exited.connect(_on_phase_hover_exit)
	_phase_lbl.resized.connect(func():
		_phase_lbl.pivot_offset = _phase_lbl.size / 2.0
	)
	hbox.add_child(_phase_lbl)

	# Vertical divider
	var div := ColorRect.new()
	div.color = C_BORDER
	div.custom_minimum_size = Vector2(1, 24)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(div)

	# Segno symbol label
	var sym_lbl := Label.new()
	sym_lbl.text = "§"
	sym_lbl.add_theme_font_size_override("font_size", 16)
	sym_lbl.add_theme_color_override("font_color", C_DIM)
	sym_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sym_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(sym_lbl)

	# Pip row
	_pip_row = HBoxContainer.new()
	_pip_row.add_theme_constant_override("separation", PIP_GAP)
	_pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_pip_row)

	for i in RunState.MAX_SEGNO_CHARGES:
		var pip := ColorRect.new()
		pip.color = C_PIP_EMPTY
		pip.custom_minimum_size = Vector2(PIP_SIZE, PIP_SIZE)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pip_row.add_child(pip)
		_pip_nodes.append(pip)

	# Excess ammo indicator (shown as "BB+N" when excess > 0)
	var div2 := ColorRect.new()
	div2.color = C_BORDER
	div2.custom_minimum_size = Vector2(1, 24)
	div2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(div2)

	_excess_lbl = Label.new()
	_excess_lbl.text = ""
	_excess_lbl.add_theme_font_size_override("font_size", 12)
	_excess_lbl.add_theme_color_override("font_color", C_DIM)
	_excess_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_excess_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_excess_lbl)

	var div3 := ColorRect.new()
	div3.color = C_BORDER
	div3.custom_minimum_size = Vector2(1, 24)
	div3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(div3)

	_reroll_lbl = Label.new()
	_reroll_lbl.text = ""
	_reroll_lbl.add_theme_font_size_override("font_size", 14)
	_reroll_lbl.add_theme_color_override("font_color", C_DIM)
	_reroll_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reroll_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_reroll_lbl)

	_road_lbl = Label.new()
	_road_lbl.text = ""
	_road_lbl.add_theme_font_size_override("font_size", 14)
	_road_lbl.add_theme_color_override("font_color", C_DIM)
	_road_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_road_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_road_lbl)

	var div_money := ColorRect.new()
	div_money.color = C_BORDER
	div_money.custom_minimum_size = Vector2(1, 24)
	div_money.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(div_money)

	_money_lbl = Label.new()
	_money_lbl.text = ""
	_money_lbl.add_theme_font_size_override("font_size", 13)
	_money_lbl.add_theme_color_override("font_color", Color(0.90, 0.75, 0.20, 1.0))
	_money_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_money_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_money_lbl)

	var div_cap := ColorRect.new()
	div_cap.color = C_BORDER
	div_cap.custom_minimum_size = Vector2(1, 24)
	div_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(div_cap)

	_cap_lbl = Label.new()
	_cap_lbl.text = ""
	_cap_lbl.add_theme_font_size_override("font_size", 12)
	_cap_lbl.add_theme_color_override("font_color", C_DIM)
	_cap_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cap_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_cap_lbl)

	var div_ch := ColorRect.new()
	div_ch.color = C_BORDER
	div_ch.custom_minimum_size = Vector2(1, 24)
	div_ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(div_ch)

	# RGB channel pips: Q=R, W=G, E=B
	const CHAN_COLORS := [Color.RED, Color.GREEN, Color.BLUE]
	const CHAN_LABELS := ["R", "G", "B"]
	const CHAN_TIPS   := ["Toggle Red channel  [Q]",
						  "Toggle Green channel  [W]",
						  "Toggle Blue channel  [E]"]
	_chan_btns.clear()
	for i in 3:
		var cb := Button.new()
		cb.text = CHAN_LABELS[i]
		cb.tooltip_text = CHAN_TIPS[i]
		cb.custom_minimum_size = Vector2(22, 22)
		cb.add_theme_font_size_override("font_size", 11)
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(0, 0, 0, 0)
		cs.set_border_width_all(0)
		cs.set_content_margin_all(2)
		var cs_h := cs.duplicate() as StyleBoxFlat
		cs_h.bg_color = CHAN_COLORS[i].darkened(0.7)
		cb.add_theme_stylebox_override("normal",  cs)
		cb.add_theme_stylebox_override("focus",   cs)
		cb.add_theme_stylebox_override("hover",   cs_h)
		cb.add_theme_stylebox_override("pressed", cs_h)
		cb.add_theme_color_override("font_color",       CHAN_COLORS[i])
		cb.add_theme_color_override("font_hover_color", CHAN_COLORS[i])
		var captured_bit : int = 1 << i
		cb.pressed.connect(func(): _on_chan_btn_pressed(captured_bit))
		_chan_btns.append(cb)
		hbox.add_child(cb)

	# Annotation row — hidden until phase label is clicked
	_annotation_lbl = Label.new()
	_annotation_lbl.add_theme_font_size_override("font_size", 11)
	_annotation_lbl.add_theme_color_override("font_color", C_DIM)
	_annotation_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_annotation_lbl.custom_minimum_size = Vector2(440, 0)
	_annotation_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_annotation_lbl.visible = false
	outer_vbox.add_child(_annotation_lbl)


func _on_phase_btn_pressed() -> void:
	_annotation_open = not _annotation_open
	if _annotation_lbl:
		_annotation_lbl.visible = _annotation_open
	if not _phase_acknowledged:
		_phase_acknowledged = true
		_stop_phase_flash()



func _on_phase_hover_enter() -> void:
	if _phase_flash_tween:
		_phase_flash_tween.pause()
	create_tween().tween_property(_phase_lbl, "scale", Vector2(1.4, 1.4), 0.05)

func _on_phase_hover_exit() -> void:
	if not _phase_acknowledged and _phase_flash_tween:
		_phase_flash_tween.play()
	create_tween().tween_property(_phase_lbl, "scale", Vector2.ONE, 0.15)


func _start_phase_flash() -> void:
	_phase_acknowledged = false

	if _phase_flash_tween:
		_phase_flash_tween.kill()

	var base_color : Color = _phase_sbox.bg_color
	var dim_color  : Color = base_color
	dim_color.a = 0.05

	var bright_color : Color = base_color
	bright_color.a = 0.6

	_phase_flash_tween = create_tween().set_loops()

	_phase_flash_tween.tween_method(
		func(c): _phase_sbox.bg_color = c,
		dim_color,
		bright_color,
		0.45
	).set_trans(Tween.TRANS_SINE)

	_phase_flash_tween.tween_method(
		func(c): _phase_sbox.bg_color = c,
		bright_color,
		dim_color,
		0.45
	).set_trans(Tween.TRANS_SINE)
	_phase_flash_tween.parallel().tween_property(
		_phase_lbl, "scale",
		Vector2(1.05, 1.05),
		0.45
	).set_trans(Tween.TRANS_SINE)

	_phase_flash_tween.parallel().tween_property(
		_phase_lbl, "scale",
		Vector2.ONE,
		0.45
	).set_trans(Tween.TRANS_SINE)


func _stop_phase_flash() -> void:
	if _phase_flash_tween:
		_phase_flash_tween.kill()
		_phase_flash_tween = null

	if _phase_sbox:
		_phase_sbox.bg_color = Color(0.329, 0.306, 0.306, 0.05)


func _phase_annotation(phase: int, run: RunState) -> String:
	match phase:
		DungeonRunState.Phase.DA_CAPO:
			return "\nSelect the spaces around you to view the options for your next composition.\n\nVisit the chapel when you need rest, or wish to move on.\n\nReturn to the atrium once you have found the Segno."
		DungeonRunState.Phase.DAL_SEGNO:
			#if run != null and run.boss_battle_triggered:
			#	return "[placeholder]"
			return "\nExpand and explore, and make preparation for when you next return to the Segno."
		DungeonRunState.Phase.DC_AL_SEGNO:
			return "\nBring the Segno to the untouched yellow room."
		DungeonRunState.Phase.DS_AL_SEGNO:
			return "\nBring the Segno to its new resting place at the frontier.\n\nTake care, your enemies have returned to where you last met them."
		DungeonRunState.Phase.CAESURA:
			return "\nRepeat your search for the Segno."
		DungeonRunState.Phase.AL_FINE:
			return "[placeholder]"
		_:
			return ""


func _process(_delta: float) -> void:
	_update_visibility()
	var dr : DungeonRunState = GameController.current_dungeon_run
	var rs : RunState        = GameController.current_run
	if dr == null or rs == null:
		return
	var charges : int = rs.segno_charges
	var phase   : int = dr.phase
	var excess  : int = rs.excess_ammo
	var rerolls : int = rs.reroll_charges
	var road    : int = rs.road_tiles_remaining
	var money   : int = rs.money
	var cap     : int = dr.segno_level_ceiling
	if charges != _last_charges or phase != _last_phase or excess != _last_excess \
			or rerolls != _last_rerolls or road != _last_road or money != _last_money \
			or cap != _last_cap:
		_last_charges = charges
		_last_phase   = phase
		_last_excess  = excess
		_last_rerolls = rerolls
		_last_road    = road
		_last_money   = money
		_last_cap     = cap
		_refresh_display(charges, phase, excess, rerolls, road, money, cap)


func _on_chan_btn_pressed(chan_bit: int) -> void:
	var dl := get_tree().get_first_node_in_group("dungeon_layer")
	if dl == null or not (dl as CanvasLayer).visible:
		return
	var map := get_tree().get_first_node_in_group("dungeon_map_3d")
	if map and map.has_method("toggle_channel"):
		map.toggle_channel(chan_bit)


## Called by dungeon_map_3d after each channel toggle to sync pip visuals.
func set_channel_mask(mask: int) -> void:
	_channel_mask = mask
	const CHAN_COLORS := [Color.RED, Color.GREEN, Color.BLUE]
	for i in _chan_btns.size():
		var btn : Button = _chan_btns[i]
		var active : bool = bool(mask & (1 << i))
		var col : Color = CHAN_COLORS[i] if active else C_DIM
		btn.add_theme_color_override("font_color",       col)
		btn.add_theme_color_override("font_hover_color", col)


## Legacy stub kept so old call sites don't crash.
func set_overlay_active(_active: bool) -> void:
	pass


func setup(run_state: RunState) -> void:
	# Called by DungeonUI.setup(); just force a redraw on next process tick.
	_last_charges = -1
	_last_phase   = -1


func _refresh_display(charges: int, phase: int, excess: int = 0, rerolls: int = 0, road: int = 0, money: int = 0, cap: int = 0) -> void:
	# Update phase label
	if _phase_lbl:
		var label_text : String
		var label_color : Color
		match phase:
			DungeonRunState.Phase.DA_CAPO:
				label_text  = "D.C."
				label_color = C_PHASE_DC
			DungeonRunState.Phase.DAL_SEGNO:
				label_text  = "D.S."
				label_color = C_PHASE_DS
			DungeonRunState.Phase.DC_AL_SEGNO:
				label_text  = "D.C. al §"
				label_color = C_PHASE_DCAS
			DungeonRunState.Phase.DS_AL_SEGNO:
				label_text  = "D.S. al §"
				label_color = C_PHASE_DSAS
			DungeonRunState.Phase.CAESURA:
				label_text  = "caesura"
				label_color = C_PHASE_CA
			DungeonRunState.Phase.AL_FINE:
				label_text  = "al fine"
				label_color = C_PHASE_AF
			_:
				label_text  = ""
				label_color = C_DIM
		_phase_lbl.text = label_text
		for col_key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			_phase_lbl.add_theme_color_override(col_key, label_color)
		if _annotation_lbl:
			_annotation_lbl.text = _phase_annotation(phase, GameController.current_run)
			_annotation_lbl.add_theme_color_override("font_color", label_color.darkened(0.3))
		# Flash on every phase change until the player acknowledges
		if phase != _last_phase or not _phase_acknowledged:
			_annotation_open = false
			if _annotation_lbl: _annotation_lbl.visible = false
			_start_phase_flash()

	# Update pips — each pip has its own R/G/B colour.
	var full : bool = charges >= RunState.MAX_SEGNO_CHARGES
	for i in _pip_nodes.size():
		var pip : ColorRect = _pip_nodes[i]
		if full:
			pip.color = C_PIP_RGB_FULL[i]
		elif i < charges:
			pip.color = C_PIP_RGB_PART[i]
		else:
			pip.color = C_PIP_EMPTY

	# Update excess ammo label
	if _excess_lbl:
		if excess > 0:
			_excess_lbl.text = "BB + %d" % excess
			_excess_lbl.add_theme_color_override("font_color", C_TEXT)
		else:
			_excess_lbl.text = ""
			_excess_lbl.add_theme_color_override("font_color", C_DIM)

	# Reroll charges
	if _reroll_lbl:
		if rerolls > 0:
			_reroll_lbl.text = "↺ %d" % rerolls
			_reroll_lbl.add_theme_color_override("font_color", C_TEXT)
		else:
			_reroll_lbl.text = ""

	# Road tiles
	if _road_lbl:
		if road > 0:
			_road_lbl.text = "⌒ %d" % road
			_road_lbl.add_theme_color_override("font_color", C_TEXT)
		else:
			_road_lbl.text = ""

	# Cuts
	if _money_lbl:
		if money > 0:
			_money_lbl.text = "%d\u20b5" % money
			_money_lbl.add_theme_color_override("font_color", Color(0.90, 0.75, 0.20, 1.0))
		else:
			_money_lbl.text = "0\u20b5"
			_money_lbl.add_theme_color_override("font_color", C_DIM)

	# Level cap — shows current ceiling and whether it's lifted.
	if _cap_lbl:
		var in_al_segno : bool = phase == DungeonRunState.Phase.DS_AL_SEGNO \
			or phase == DungeonRunState.Phase.DC_AL_SEGNO \
			or phase == DungeonRunState.Phase.AL_FINE
		if in_al_segno:
			_cap_lbl.text = "Lv. cap ≤ \u221e"
			_cap_lbl.add_theme_color_override("font_color", C_PHASE_DSAS)
		else:
			_cap_lbl.text = "Lv. cap ≤ %d" % cap
			_cap_lbl.add_theme_color_override("font_color", C_DIM)
