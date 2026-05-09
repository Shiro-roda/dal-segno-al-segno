extends Control
class_name ChapelEvent
# Chapel rest event — phase-aware.
#
# DA_CAPO / AL_CODA:  Restore (full HP) | Compose (Semiosis) | [locked]
# DAL_SEGNO:          Restore (full HP) | Transpose (pick 2-of-3 resources) | [locked]
# AL_SEGNO / AL_FINE: Transpose benefits rolled and presented; pick up to 2.
#                     If no Transpose was prepared, all three cards are locked.
#
# Emits event_finished when the player leaves or confirms.

signal event_finished

var C_BG       := Color.BLACK
var C_BORDER   := Color.WHITE
var C_ACCENT   := Color.WHITE
var C_TEXT     := Color.WHITE
var C_DIM      := Color.WHITE
var C_SELECTED := Color.WHITE
const C_SEGNO     := Color(0.32, 0.44, 0.58, 1.0)
const C_TRANSPOSE := Color(0.38, 0.58, 0.38, 1.0)

func _refresh_palette() -> void:
	var p := ThemeManager.palette
	C_BG       = p.bg
	C_BORDER   = p.dim
	C_ACCENT   = p.secondary
	C_TEXT     = p.text
	C_DIM      = p.dim
	C_SELECTED = Color(p.secondary.r, p.secondary.g, p.secondary.b, 0.22)

func _on_theme_changed(_id: int) -> void:
	_refresh_palette()
	for c in get_children(): c.queue_free()
	_cards.clear()
	_confirm_btn = null
	_outer = null
	_selected_indices.clear()
	_build_ui()

const CARD_W := 220
const CARD_H := 220
## Number of resource picks the player makes during Transpose (DAL_SEGNO).
## Duplicates are allowed. Increase this for future balance changes or player bonuses.
const TRANSPOSE_PICK_COUNT : int = 3
## Number of rolled benefits the player may redeem during transit (AL_SEGNO/AL_FINE).
const TRANSPOSE_REDEEM_COUNT : int = 2

var _room        : RoomInstance
var _run_state   : RunState
var _allows_segno : bool = false

# Mode flags set in _resolve_mode().
enum Mode { SAFE, TRANSPOSE_PICK, TRANSPOSE_USE, TENSE_LOCKED }
var _mode : Mode = Mode.SAFE

# Options shown as cards.
var _options     : Array = []   # Array of {name, desc, type, val, locked?}

# Multi-select support: up to MAX_PICKS selections.
var _selected_indices : Array = []  # Array[int]
var _cards : Array = []
var _confirm_btn : Button
var _outer : VBoxContainer


func _ready() -> void:
	_refresh_palette()
	ThemeManager.theme_changed.connect(_on_theme_changed)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func setup(room: RoomInstance, run_state: RunState) -> void:
	_room         = room
	_run_state    = run_state
	_allows_segno = room.room_data != null and room.room_data.allows_segno
	_resolve_mode()
	if _outer != null:
		_populate_outer()


# ── Mode resolution ──────────────────────────────────────────────────────────────────

func _resolve_mode() -> void:
	_options.clear()
	var dr     : DungeonRunState = GameController.current_dungeon_run
	var phase  : int = dr.phase if dr != null else DungeonRunState.Phase.DA_CAPO
	var tense  : bool = phase == DungeonRunState.Phase.DS_AL_SEGNO \
					 or phase == DungeonRunState.Phase.AL_FINE
	var dal    : bool = phase == DungeonRunState.Phase.DAL_SEGNO
	# DC_AL_SEGNO is a gentle transit — treat like a tense phase for chapel
	# (no Compose, no Transpose — only the Transpose benefits if prepared).
	var dc_transit : bool = phase == DungeonRunState.Phase.DC_AL_SEGNO

	if tense or dc_transit:
		_resolve_mode_tense()
	elif dal:
		_resolve_mode_dal_segno()
	else:  # DA_CAPO / GRAND_PAUSE
		_resolve_mode_safe()


## DA_CAPO and GRAND_PAUSE: Restore + Compose(Semiosis) + locked Transpose slot.
func _resolve_mode_safe() -> void:
	_mode = Mode.SAFE
	var charges  := _run_state.segno_charges
	var rem      := RunState.MAX_SEGNO_CHARGES - charges
	var compose_locked : bool = _run_state.has_full_segno()
	var compose_desc : String
	if compose_locked:
		compose_desc = "Segno already complete."
	else:
		compose_desc = "Inscribe a measure of the Segno. (%d/%d — %d remaining.)" \
			% [charges, RunState.MAX_SEGNO_CHARGES, rem]
	_options = [
		{"name": "Restore",  "desc": "Fully restore Corpus Portions to all allies.",
			"type": "restore_full", "val": 0},
		{"name": "Compose",  "desc": compose_desc,
			"type": "semiosis", "val": 1, "locked": compose_locked},
		{"name": "Transpose", "desc": "Only available during Dal Segno.",
			"type": "locked", "val": 0},
	]


## DAL_SEGNO: three-pick resource queue. Each click adds one pick (duplicates allowed).
func _resolve_mode_dal_segno() -> void:
	if _room.transpose_picks.size() >= TRANSPOSE_PICK_COUNT:
		# Already fully prepared; show a locked summary.
		_mode = Mode.TENSE_LOCKED
		var counts : Dictionary = {}
		for r in _room.transpose_picks: counts[r] = counts.get(r, 0) + 1
		var parts : Array = []
		for r in counts: parts.append("%s×%d" % [r.capitalize(), counts[r]])
		var summary := ", ".join(parts)
		_options = [
			{"name": "Restore",   "desc": "Fully restore Corpus Portions to all allies.",
				"type": "restore_full", "val": 0},
			{"name": "Transpose", "desc": "Prepared: " + summary + ".",
				"type": "locked", "val": 0},
			{"name": "Compose",   "desc": "Only available in Da Capo and Grand Pause.",
				"type": "locked", "val": 0},
		]
		return
	# Unprepared: show main 3 options.
	# Clicking Transpose opens the resource picker sub-screen (type = "open_transpose").
	_mode = Mode.SAFE  # re-use SAFE card layout
	_options = [
		{"name": "Restore",   "desc": "Fully restore Corpus Portions to all allies.",
			"type": "restore_full", "val": 0},
		{"name": "Transpose", "desc": "Prepare resource caches for the transit ahead. Choose %d." % TRANSPOSE_PICK_COUNT,
			"type": "open_transpose", "val": 0},
		{"name": "Compose",   "desc": "Only available in Da Capo and Grand Pause.",
			"type": "locked", "val": 0},
	]


## AL_SEGNO / AL_FINE: Roll the cached Transpose picks into actual restores (once),
## then present them so the player can redeem up to MAX_PICKS.
func _resolve_mode_tense() -> void:
	if _room.rested:
		# Already used during this transit.
		_mode = Mode.TENSE_LOCKED
		_options = [
			{"name": "Corpus",     "desc": "Already redeemed.", "type": "locked", "val": 0},
			{"name": "Anima",      "desc": "Already redeemed.", "type": "locked", "val": 0},
			{"name": "Beat Bolts", "desc": "Already redeemed.", "type": "locked", "val": 0},
		]
		return
	if _room.transpose_picks.is_empty():
		# No Transpose was prepared during DAL_SEGNO.
		_mode = Mode.TENSE_LOCKED
		_options = [
			{"name": "Corpus",     "desc": "Not prepared.", "type": "locked", "val": 0},
			{"name": "Anima",      "desc": "Not prepared.", "type": "locked", "val": 0},
			{"name": "Beat Bolts", "desc": "Not prepared.", "type": "locked", "val": 0},
		]
		return
	# Roll each pick individually (once per chapel entry; cached on re-entry).
	if not _room.transpose_rolled:
		_room.rest_options = _roll_transpose_picks(_room.transpose_picks)
		_room.transpose_rolled = true
	# All picks become individual cards (duplicates get numbered labels).
	_mode = Mode.TRANSPOSE_USE
	_options.clear()
	var label_counts : Dictionary = {}
	for i in _room.rest_options.size():
		var opt : Dictionary = _room.rest_options[i].duplicate()
		var base_name : String = opt.get("name", "")
		label_counts[base_name] = label_counts.get(base_name, 0) + 1
		var count_so_far : int = label_counts[base_name]
		# Count total occurrences to decide whether to number them at all
		var total_of_type : int = 0
		for o in _room.rest_options:
			if o.get("name", "") == base_name: total_of_type += 1
		if total_of_type > 1:
			opt["name"] = base_name + " ×" + str(count_so_far)
		_options.append(opt)


## Roll a single resource pick into a concrete restore dict.
func _roll_transpose_picks(picks: Array) -> Array:
	var rolled : Array = []
	for res in picks:
		rolled.append(_roll_one_pick(res))
	return rolled


func _roll_one_pick(resource: String) -> Dictionary:
	var members := _run_state.party_members
	match resource:
		"corpus":
			var avg_lost : int = 0
			for m in members: avg_lost += m.character.base_max_hp - m.current_hp
			avg_lost /= max(1, members.size())
			var avg_max : int = 0
			for m in members: avg_max += m.character.base_max_hp + m.bonus_max_hp
			avg_max /= max(1, members.size())
			# Randomly choose between pct-missing and flat-average rolls
			if randi() % 2 == 0:
				var val := randi_range(int(avg_lost * 0.5), int(avg_lost * 1.5) + 1)
				return {"name": "Corpus", "desc": "Restore ~%d%% of missing CORP to each ally." \
					% int(float(val) / float(max(1, avg_max)) * 100),
					"type": "hp", "val": val, "resource": "corpus"}
			else:
				var val := randi_range(int(avg_max * 0.25), int(avg_max * 0.55) + 1)
				return {"name": "Corpus", "desc": "Restore ~%d CORP to each ally." % val,
					"type": "hp", "val": val, "resource": "corpus"}
		"anima":
			var total_lost : int = 0; var will_count : int = 0
			for m in members:
				if m.has_will(): total_lost += m.max_will - m.will; will_count += 1
			var avg_max_will : int = 0
			for m in members:
				if m.has_will(): avg_max_will += m.max_will
			if will_count > 0:
				total_lost /= will_count
				avg_max_will /= will_count
			if randi() % 2 == 0:
				var val := randi_range(int(total_lost * 0.5), int(total_lost * 1.5) + 1)
				return {"name": "Anima", "desc": "Restore ~%d AP to each support." % val,
					"type": "will", "val": val, "resource": "anima"}
			else:
				var val := randi_range(int(avg_max_will * 0.25), int(avg_max_will * 0.55) + 1)
				return {"name": "Anima", "desc": "Restore ~%d AP to each support." % val,
					"type": "will", "val": val, "resource": "anima"}
		"bb":
			# Beat Bolts: either permanently expand clip OR restore a full clip
			if randi() % 2 == 0:
				return {"name": "Beat Bolts", "desc": "Permanently increase max clip by 2.",
					"type": "max_ammo", "val": 2, "resource": "bb"}
			else:
				return {"name": "Beat Bolts", "desc": "Restore a full clip of ammo.",
					"type": "ammo_full", "val": 0, "resource": "bb"}
	return {}





func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_outer = VBoxContainer.new()
	_outer.add_theme_constant_override("separation", 0)
	center.add_child(_outer)

	if _room != null:
		_populate_outer()


func _populate_outer() -> void:
	for c in _outer.get_children():
		c.queue_free()
	_cards.clear()
	_selected_indices.clear()

	var top_space := Control.new()
	top_space.custom_minimum_size = Vector2(0, 32)
	_outer.add_child(top_space)

	var prompt := Label.new()
	var room_name : String = _room.room_data.room_name.to_upper() if _room and _room.room_data else "REST"
	match _mode:
		Mode.TRANSPOSE_PICK:
			var so_far := _room.transpose_picks.size()
			prompt.text = room_name + "  —  TRANSPOSE  (%d / %d picks)" % [so_far, TRANSPOSE_PICK_COUNT]
		Mode.TRANSPOSE_USE:
			prompt.text = room_name + "  —  REDEEM  (choose %d of %d)" \
				% [TRANSPOSE_REDEEM_COUNT, _options.size()]
		_: prompt.text = room_name
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", C_DIM)
	_outer.add_child(prompt)

	var div := ColorRect.new()
	div.color = C_ACCENT
	div.custom_minimum_size = Vector2(0, 1)
	_outer.add_child(div)

	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 28)
	_outer.add_child(spacer1)

	var card_row := HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 24)
	_outer.add_child(card_row)

	for i in _options.size():
		var card := _make_card(_options[i], i)
		card_row.add_child(card)
		_cards.append(card)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 28)
	_outer.add_child(spacer2)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	_outer.add_child(btn_row)

	# Confirm button
	_confirm_btn = Button.new()
	if _mode == Mode.TRANSPOSE_PICK:
		_confirm_btn.text = "PREPARE"
	elif _mode == Mode.TRANSPOSE_USE:
		_confirm_btn.text = "REDEEM"
	else:
		_confirm_btn.text = "CHOOSE"
	_confirm_btn.custom_minimum_size = Vector2(160, 44)
	_confirm_btn.add_theme_font_size_override("font_size", 14)
	_confirm_btn.add_theme_color_override("font_color", C_TEXT)
	_confirm_btn.add_theme_color_override("font_hover_color", C_TEXT)
	_confirm_btn.add_theme_color_override("font_pressed_color", C_TEXT)
	_confirm_btn.add_theme_color_override("font_focus_color", C_TEXT)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = C_ACCENT
	sbox.border_color = C_BORDER
	sbox.set_border_width_all(1)
	sbox.set_content_margin_all(10)
	var sbox_dis := StyleBoxFlat.new()
	sbox_dis.bg_color = Color(0.18, 0.15, 0.12, 1.0)
	sbox_dis.border_color = C_BORDER
	sbox_dis.set_border_width_all(1)
	sbox_dis.set_content_margin_all(10)
	_confirm_btn.add_theme_stylebox_override("normal",   sbox)
	_confirm_btn.add_theme_stylebox_override("hover",    sbox)
	_confirm_btn.add_theme_stylebox_override("pressed",  sbox)
	_confirm_btn.add_theme_stylebox_override("focus",    sbox)
	_confirm_btn.add_theme_stylebox_override("disabled", sbox_dis)
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(_confirm_btn)

	# Leave button
	var leave_btn := Button.new()
	leave_btn.text = "LEAVE"
	leave_btn.custom_minimum_size = Vector2(100, 44)
	leave_btn.add_theme_font_size_override("font_size", 13)
	leave_btn.add_theme_color_override("font_color", C_DIM)
	leave_btn.add_theme_color_override("font_hover_color", C_TEXT)
	leave_btn.add_theme_color_override("font_focus_color", C_DIM)
	var leave_sbox := StyleBoxFlat.new()
	leave_sbox.bg_color = Color(0, 0, 0, 0)
	leave_sbox.border_color = C_BORDER
	leave_sbox.set_border_width_all(1)
	leave_sbox.set_content_margin_all(10)
	leave_btn.add_theme_stylebox_override("normal",  leave_sbox)
	leave_btn.add_theme_stylebox_override("hover",   leave_sbox)
	leave_btn.add_theme_stylebox_override("pressed", leave_sbox)
	leave_btn.add_theme_stylebox_override("focus",   leave_sbox)
	leave_btn.pressed.connect(func(): emit_signal("event_finished"))
	btn_row.add_child(leave_btn)



	var bot_space := Control.new()
	bot_space.custom_minimum_size = Vector2(0, 24)
	_outer.add_child(bot_space)


func _make_card(option: Dictionary, idx: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)

	var normal_sbox := StyleBoxFlat.new()
	normal_sbox.bg_color = Color(0.10, 0.09, 0.08, 1.0)
	normal_sbox.border_color = C_BORDER
	normal_sbox.set_border_width_all(2)
	normal_sbox.set_content_margin_all(20)
	card.add_theme_stylebox_override("panel", normal_sbox)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	card.add_child(inner)

	var name_lbl := Label.new()
	name_lbl.text = option["name"].to_upper()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	inner.add_child(name_lbl)

	var div := ColorRect.new()
	div.color = C_BORDER
	div.custom_minimum_size = Vector2(0, 1)
	inner.add_child(div)

	# Effect summary line
	var effect_lbl := Label.new()
	effect_lbl.name = "EffectLabel"
	effect_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect_lbl.add_theme_font_size_override("font_size", 13)
	effect_lbl.add_theme_color_override("font_color", C_ACCENT)
	var val : int = option["val"]
	var charges := _run_state.segno_charges if _run_state else 0
	var is_locked : bool = option.get("locked", false) or option["type"] == "locked"
	match option["type"]:
		"hp":             effect_lbl.text = "+%d CORP" % val
		"will":           effect_lbl.text = "+%d AP" % val
		"ammo":           effect_lbl.text = "+%d BB" % val
		"max_ammo":       effect_lbl.text = "+%d max BB" % val
		"ammo_full":      effect_lbl.text = "Full clip"
		"restore_full":   effect_lbl.text = "Full CORP"
		"open_transpose": effect_lbl.text = "↕"
		"transpose_pick": effect_lbl.text = "Cache"
		"semiosis":
			var pips := ""
			for p in RunState.MAX_SEGNO_CHARGES:
				pips += ("§" if p < charges else "·")
			effect_lbl.text = pips + "  →  "
			for p in RunState.MAX_SEGNO_CHARGES:
				effect_lbl.text += ("§" if p <= charges else "·")
			effect_lbl.add_theme_color_override("font_color", C_SEGNO if not is_locked else C_DIM)
		"locked":         effect_lbl.text = "—"
		_:                effect_lbl.text = str(val)
	if is_locked:
		name_lbl.add_theme_color_override("font_color", C_DIM)
		effect_lbl.add_theme_color_override("font_color", C_DIM)
	elif option["type"] == "transpose_pick":
		effect_lbl.add_theme_color_override("font_color", C_TRANSPOSE)
	inner.add_child(effect_lbl)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = option.get("desc", "")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", C_DIM)
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(desc_lbl)

	# Invisible full-card button
	var btn := Button.new()
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.flat = true
	var transparent := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal",  transparent)
	btn.add_theme_stylebox_override("hover",   transparent)
	btn.add_theme_stylebox_override("pressed", transparent)
	btn.add_theme_stylebox_override("focus",   transparent)
	btn.pressed.connect(func(): _select_card(idx))
	card.add_child(btn)

	return card


func _select_card(idx: int) -> void:
	var opt : Dictionary = _options[idx]
	if opt.get("locked", false) or opt["type"] == "locked":
		return
	if _mode == Mode.TRANSPOSE_PICK:
		# Each click appends one pick. Right-click (or clicking again after TRANSPOSE_PICK_COUNT)
		# undoes the last pick of this resource type.
		var total_so_far := _room.transpose_picks.size() + _selected_indices.size()
		var res : String = opt.get("resource", "")
		# Find how many of this resource are already queued in _selected_indices
		var queued_of_type := _selected_indices.filter(func(i): return i == idx).size()
		# Right-click / dequeue: if already picked at least once, remove one
		# (We use a secondary flag — but since we only have pressed(), simulate
		#  undo by checking if this card was the last appended index.)
		if _selected_indices.size() > 0 and _selected_indices.back() == idx:
			# Undo last pick of this card
			_selected_indices.pop_back()
		elif total_so_far < TRANSPOSE_PICK_COUNT:
			_selected_indices.append(idx)
		_refresh_card_visuals()
		var total := _room.transpose_picks.size() + _selected_indices.size()
		_confirm_btn.disabled = total < TRANSPOSE_PICK_COUNT
	else:
		# TRANSPOSE_USE / SAFE: toggle with cap at TRANSPOSE_REDEEM_COUNT
		var cap := TRANSPOSE_REDEEM_COUNT if _mode == Mode.TRANSPOSE_USE else 1
		if idx in _selected_indices:
			_selected_indices.erase(idx)
		else:
			if _selected_indices.size() >= cap:
				_selected_indices.pop_front()
			_selected_indices.append(idx)
		_refresh_card_visuals()
		_confirm_btn.disabled = _selected_indices.is_empty()


func _refresh_card_visuals() -> void:
	for i in _cards.size():
		var card : PanelContainer = _cards[i]
		var count : int = _selected_indices.filter(func(x): return x == i).size()
		var sel   : bool = count > 0 if _mode == Mode.TRANSPOSE_PICK else (i in _selected_indices)
		var sbox := StyleBoxFlat.new()
		sbox.bg_color     = C_SELECTED if sel else Color(0.10, 0.09, 0.08, 1.0)
		sbox.border_color = C_ACCENT   if sel else C_BORDER
		sbox.set_border_width_all(2)
		sbox.set_content_margin_all(20)
		card.add_theme_stylebox_override("panel", sbox)
		# Show pick count badge on the effect label in TRANSPOSE_PICK mode
		if _mode == Mode.TRANSPOSE_PICK:
			var effect_lbl : Label = card.find_child("EffectLabel", true, false)
			if effect_lbl and count > 0:
				effect_lbl.text = "×%d" % count


func _on_confirm() -> void:
	if _selected_indices.is_empty():
		return
	var rs := _run_state

	if _mode == Mode.TRANSPOSE_PICK:
		# Append queued picks to the room's transpose_picks list.
		for idx in _selected_indices:
			var opt : Dictionary = _options[idx]
			# Only append resource picks, not Restore/Compose cards appended at end.
			if opt["type"] == "transpose_pick":
				_room.transpose_picks.append(opt.get("resource", ""))
		_selected_indices.clear()
		_options.clear()
		_resolve_mode()
		_populate_outer()
		return

	# Single-select action types that rebuild the UI without closing.
	if _selected_indices.size() == 1:
		var single_opt : Dictionary = _options[_selected_indices[0]]
		if single_opt["type"] == "open_transpose":
			# Enter the resource-picker sub-screen.
			_selected_indices.clear()
			_options.clear()
			_mode = Mode.TRANSPOSE_PICK
			_options = [
				{"name": "Corpus",     "desc": "Cache one Corpus restore for transit.",
					"type": "transpose_pick", "val": 0, "resource": "corpus"},
				{"name": "Anima",      "desc": "Cache one Anima restore for transit.",
					"type": "transpose_pick", "val": 0, "resource": "anima"},
				{"name": "Beat Bolts", "desc": "Cache one BB restore. May expand your clip.",
					"type": "transpose_pick", "val": 0, "resource": "bb"},
			]
			_populate_outer()
			return

	# Apply all selected options.
	for idx in _selected_indices:
		var opt : Dictionary = _options[idx]
		_apply_option(opt, rs)

	_room.rested = true
	emit_signal("event_finished")


func _apply_option(opt: Dictionary, rs: RunState) -> void:
	match opt["type"]:
		"hp":
			for member in rs.party_members:
				member.set_hp(mini(member.current_hp + opt["val"],
					member.character.base_max_hp + member.bonus_max_hp))
		"will":
			for member in rs.party_members:
				if member.has_will():
					member.restore_will(opt["val"])
		"ammo":
			rs.restore_ammo(opt["val"])
		"ammo_full":
			rs.ammo = rs.max_ammo
		"max_ammo":
			rs.increase_max_ammo(opt["val"])
		"restore_full":
			for member in rs.party_members:
				member.set_hp(member.character.base_max_hp + member.bonus_max_hp)
		"semiosis":
			rs.add_semiosis_charge()
			if rs.has_full_segno():
				var dc = get_tree().get_first_node_in_group("dungeon_controller")
				if dc: dc.on_semiosis_complete()
