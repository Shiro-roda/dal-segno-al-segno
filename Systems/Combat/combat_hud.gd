class_name CombatHUD
extends CanvasLayer
## Builds its own UI in code and drives a CombatSession.
## Mouse: click an enemy to target it, click an action to queue it.
## Keys: 1-9 pick a party member, Tab cycles the target, combat_pause pauses.

var session: CombatSession

var _selected: Combatant
var _enemy_box: VBoxContainer
var _party_box: HBoxContainer
var _menu_box: HFlowContainer
var _log: RichTextLabel
var _banner: Label
var _enemy_rows: Dictionary = {}  # Combatant -> {button, bar}
var _party_rows: Dictionary = {}  # Combatant -> {select, corpus, anima, gauge, order}
var _peaks: Dictionary = {}       # StatBlock -> {corpus, anima} fallbacks for max values


func bind(p_session: CombatSession) -> void:
	session = p_session
	layer = 20
	_build_frame()
	for c in session.enemies:
		_add_enemy_row(c)
	for c in session.party:
		_add_party_row(c)
	for line in session.history:
		_on_log_line(line)
	session.log_line.connect(_on_log_line)
	session.paused_changed.connect(_on_paused_changed)
	session.order_changed.connect(func(_c: Combatant): _refresh_menu())
	session.action_resolved.connect(func(_a: Combatant, _r: Dictionary): _refresh_menu())
	session.combat_ended.connect(_on_combat_ended)
	if not session.party.is_empty():
		_select(session.party[0])
	_on_paused_changed(session.paused)


# ── layout ───────────────────────────────────────────────────────────────────
func _build_frame() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_enemy_box = VBoxContainer.new()
	_enemy_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	_enemy_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(_enemy_box)

	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 8)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_banner)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 8)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bottom)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = false
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.custom_minimum_size = Vector2(0, 72)
	bottom.add_child(_log)

	_menu_box = HFlowContainer.new()
	bottom.add_child(_menu_box)

	_party_box = HBoxContainer.new()
	bottom.add_child(_party_box)


func _add_enemy_row(c: Combatant) -> void:
	var row := VBoxContainer.new()
	var button := _button("")
	button.pressed.connect(_on_enemy_pressed.bind(c))
	var bar := _bar(Color(0.8, 0.2, 0.2))
	row.add_child(button)
	row.add_child(bar)
	_enemy_box.add_child(row)
	_enemy_rows[c] = {"button": button, "bar": bar}
	_remember_peaks(c)


func _add_party_row(c: Combatant) -> void:
	var panel := PanelContainer.new()
	var col := VBoxContainer.new()
	panel.add_child(col)
	var select := _button("")
	select.pressed.connect(_select.bind(c))
	var corpus := _bar(Color(0.8, 0.2, 0.2))
	var anima := Label.new()
	var gauge := _bar(Color(0.9, 0.8, 0.3))
	gauge.max_value = 1.0
	gauge.custom_minimum_size.y = 6
	var order := Label.new()
	for n in [select, corpus, anima, gauge, order]:
		col.add_child(n)
	_party_box.add_child(panel)
	_party_rows[c] = {"select": select, "corpus": corpus, "anima": anima, "gauge": gauge, "order": order}
	_remember_peaks(c)


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	# Without this a clicked button keeps focus, and Space would press it
	# instead of toggling the pause.
	b.focus_mode = Control.FOCUS_NONE
	return b


func _bar(color: Color) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(110, 10)
	p.modulate = color
	return p


# ── per-frame refresh ────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if session == null:
		return
	var targeted: Combatant = _selected.target if _selected != null else null
	for c: Combatant in _enemy_rows:
		var row: Dictionary = _enemy_rows[c]
		var bar: ProgressBar = row["bar"]
		bar.max_value = _max_corpus(c.block)
		bar.value = c.block.corpus
		var button: Button = row["button"]
		button.text = "%s%s" % ["> " if c == targeted else "", c.display_name()]
		button.disabled = c.is_down()
	for c: Combatant in _party_rows:
		var row: Dictionary = _party_rows[c]
		var bar: ProgressBar = row["corpus"]
		bar.max_value = _max_corpus(c.block)
		bar.value = c.block.corpus
		(row["select"] as Button).text = "%s%d. %s" % ["* " if c == _selected else "", session.party.find(c) + 1, c.display_name()]
		(row["anima"] as Label).text = "Anima %d/%d" % [c.block.anima, _max_anima(c.block)]
		(row["gauge"] as ProgressBar).value = c.gauge
		(row["order"] as Label).text = _order_text(c)


func _order_text(c: Combatant) -> String:
	if c.is_down():
		return "Down"
	if not c.has_order():
		return "Auto-attack"
	var action: ActionDef = c.order["action"]
	var level := int(c.order.get("level", 0))
	return "Order: %s%s" % [action.display_name, " L%d" % level if level > 0 else ""]


# ── max values ───────────────────────────────────────────────────────────────
## ASSUMPTION: I don't remember what StatBlock calls its maximums. This tries
## max_corpus()/corpus_max, then falls back to the value at fight start.
func _remember_peaks(c: Combatant) -> void:
	_peaks[c.block] = {"corpus": maxi(c.block.corpus, 1), "anima": maxi(c.block.anima, 1)}


func _max_corpus(b: StatBlock) -> int:
	return _max_of(b, "max_corpus", "corpus_max", int(_peaks[b]["corpus"]))


func _max_anima(b: StatBlock) -> int:
	return _max_of(b, "max_anima", "anima_max", int(_peaks[b]["anima"]))


func _max_of(b: StatBlock, method: String, prop: String, fallback: int) -> int:
	if b.has_method(method):
		return int(b.call(method))
	var v: Variant = b.get(prop)
	return int(v) if v != null else fallback


# ── interaction ──────────────────────────────────────────────────────────────
func _select(c: Combatant) -> void:
	if c == null or c.side != Combatant.Side.PARTY:
		return
	_selected = c
	_refresh_menu()


func _on_enemy_pressed(enemy: Combatant) -> void:
	if _selected != null:
		session.set_target(_selected, enemy)


func _refresh_menu() -> void:
	for child in _menu_box.get_children():
		_menu_box.remove_child(child)
		child.queue_free()
	if session == null or not session.active or _selected == null or _selected.is_down():
		return
	for opt: Dictionary in session.options_for(_selected):
		var cost := int(opt["cost"])
		var b := _button("%s (%d)" % [opt["label"], cost] if cost > 0 else str(opt["label"]))
		b.disabled = not opt["affordable"]
		b.pressed.connect(_on_option_pressed.bind(opt))
		_menu_box.add_child(b)
	var hold := _button("Hold: ON" if _selected.hold_position else "Hold: off")
	hold.pressed.connect(func():
		session.set_hold(_selected, not _selected.hold_position)
		_refresh_menu())
	_menu_box.add_child(hold)
	if _selected.has_order():
		var clear := _button("Clear order")
		clear.pressed.connect(func(): session.clear_order(_selected))
		_menu_box.add_child(clear)


func _on_option_pressed(opt: Dictionary) -> void:
	if _selected == null:
		return
	# Single-ally and group actions ignore an enemy target; the session picks.
	session.queue_action(_selected, opt["action"], int(opt["level"]), _selected.target)


func _unhandled_input(event: InputEvent) -> void:
	if session == null or not session.active:
		return
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		_move_order_at(mouse.position)
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var idx := key.keycode - KEY_1
	if idx >= 0 and idx < session.party.size():
		_select(session.party[idx])
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_TAB:
		_cycle_target()
		get_viewport().set_input_as_handled()

## Right-click the ground to send the selected party member there.
func _move_order_at(screen_pos: Vector2) -> void:
	if _selected == null or _selected.is_down():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)  # layer 1 = the world
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		session.order_move(_selected, hit["position"])


func _cycle_target() -> void:
	if _selected == null:
		return
	var alive: Array[Combatant] = []
	for e in session.enemies:
		if not e.is_down():
			alive.append(e)
	if alive.is_empty():
		return
	var i := alive.find(_selected.target)
	session.set_target(_selected, alive[(i + 1) % alive.size()])


# ── session signals ──────────────────────────────────────────────────────────
func _on_log_line(line: String) -> void:
	_log.append_text(line.replace("[", "[lb]") + "\n")


func _on_paused_changed(is_paused: bool) -> void:
	if session != null and session.active:
		_banner.text = "PAUSED (Space to resume)" if is_paused else ""


func _on_combat_ended(victory: bool) -> void:
	_banner.text = "VICTORY" if victory else "DEFEAT"
	_refresh_menu()
	await get_tree().create_timer(2.5).timeout
	queue_free()
