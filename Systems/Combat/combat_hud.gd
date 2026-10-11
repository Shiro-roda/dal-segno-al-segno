class_name CombatHUD
extends CanvasLayer
## Drives the combat UI in res://UI/2D/Scenes/combat_hud.tscn. Layout and styling live in
## that scene; colours, ring sizes and wording are the exports below.
## Mouse: click an enemy to target it. Click an action to queue it once; double-click
## it to make it the character's automatic action (double-click again to undo).
## Right-click the ground to send the selected character there.
## Keys: 1-9 pick a party member, Tab cycles the target, L toggles the log,
## V toggles Overview / Focus turns, combat_pause pauses.
## A ring on the floor shows who you're commanding (in Focus view: whoever is taking
## their turn), and another who they're aiming at.

@export_group("Scenes")
@export var party_row_scene: PackedScene
@export var enemy_row_scene: PackedScene
## Optional. Used for the action buttons; a plain Button if left empty.
@export var action_button_scene: PackedScene

@export_group("Rings")
@export var select_color := Color(0.35, 0.9, 1.0)
@export var target_color := Color(1.0, 0.35, 0.3)
## Ring under an enemy that is taking its turn in Focus view.
@export var enemy_turn_color := Color(1.0, 0.75, 0.2)
@export var select_radius := 0.8
@export var target_radius := 0.95
## Rings sit this far above the body's origin so the floor doesn't hide them.
@export var ring_height := 0.05

@export_group("Text")
@export var turn_format := "%s's turn"
@export var victory_text := "VICTORY"
@export var defeat_text := "DEFEAT"
## How long VICTORY / DEFEAT stays up before the HUD closes.
@export var result_hold_seconds := 2.5

@export_group("Row text")
@export var down_text := "Down"
@export var order_format := "Order: %s%s"
@export var auto_format := "Auto: %s"
@export var behavior_suffix_format := " | %s"

@export_group("Action menu text")
@export var auto_prefix := "[Auto] "
@export var hold_on_text := "Hold: ON"
@export var hold_off_text := "Hold: off"
@export var behavior_format := "Behavior: %s"
@export var reset_auto_text := "Reset auto"
@export var clear_order_text := "Clear order"
@export_multiline var action_tooltip := "Click: use once.\nDouble-click: make this the automatic action.\nDouble-click the [Auto] one to undo."
@export_multiline var behavior_tooltip := "What this character does on their own turn.\nHeal Wounded: heal allies below half Corpus before attacking."

@onready var _party_bar: Container = %PartyBar
@onready var _enemy_list: Container = %EnemyList
@onready var _action_menu: Container = %ActionMenu
@onready var _log: RichTextLabel = %Log
@onready var _pause_label: Label = %PauseLabel
@onready var _banner: Label = %BannerLabel
@onready var _log_toggle: BaseButton = %LogToggle
@onready var _view_toggle: BaseButton = %ViewToggle
@onready var _roll_display: RollDisplay = %RollDisplay

var session: CombatSession

var _selected: Combatant
var _spot_name := ""
var _enemy_rows: Dictionary = {}  # Combatant -> CombatEnemyRow
var _party_rows: Dictionary = {}  # Combatant -> CombatPartyRow
var _peaks: Dictionary = {}       # StatBlock -> {corpus, anima} fallbacks for max values
# Variant, not SelectionRing: the ring is freed with the body it rides on, and a freed
# object can't be passed to a typed parameter.
var _select_ring: Variant = null
var _target_ring: Variant = null


func _ready() -> void:
	# A clicked button that keeps focus would eat Space instead of letting it pause.
	for b in find_children("*", "BaseButton", true, false):
		(b as BaseButton).focus_mode = Control.FOCUS_NONE
	_banner.text = ""
	_pause_label.hide()
	_log_toggle.toggled.connect(func(on: bool):
		CombatOptions.set_log_visible(on)
		_apply_options())
	_view_toggle.toggled.connect(func(on: bool):
		CombatOptions.set_focus_turns(on)
		_apply_options())


func bind(p_session: CombatSession) -> void:
	if party_row_scene == null or enemy_row_scene == null:
		push_error("CombatHUD: assign Party Row Scene and Enemy Row Scene in the Inspector (Scenes group).")
		return
	session = p_session
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
	session.turn_spotlight_changed.connect(_on_spotlight)
	_roll_display.bind(session)
	_apply_options()
	if not session.party.is_empty():
		_select(session.party[0])
	_on_paused_changed(session.paused)


func _exit_tree() -> void:
	_clear_rings()


# ── rows ─────────────────────────────────────────────────────────────────────
func _add_enemy_row(c: Combatant) -> void:
	var row := enemy_row_scene.instantiate() as CombatEnemyRow
	_enemy_list.add_child(row)
	row.pressed.connect(_on_enemy_pressed.bind(c))
	_enemy_rows[c] = row
	_remember_peaks(c)


func _add_party_row(c: Combatant) -> void:
	var row := party_row_scene.instantiate() as CombatPartyRow
	_party_bar.add_child(row)
	row.selected.connect(_select.bind(c))
	_party_rows[c] = row
	_remember_peaks(c)


func _new_button(text: String) -> Button:
	var b: Button = action_button_scene.instantiate() as Button if action_button_scene != null else Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	return b


# ── per-frame refresh ────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if session == null:
		return
	_update_rings()
	var targeted: Combatant = _selected.target if _selected != null else null
	for c: Combatant in _enemy_rows:
		(_enemy_rows[c] as CombatEnemyRow).show_state(
				c.display_name(), c == targeted, c.block.corpus, _max_corpus(c.block), c.is_down())
	for c: Combatant in _party_rows:
		(_party_rows[c] as CombatPartyRow).show_state(
				session.party.find(c) + 1, c.display_name(), c == _selected,
				c.block.corpus, _max_corpus(c.block), c.block.anima, _max_anima(c.block),
				c.gauge, _order_text(c))


func _order_text(c: Combatant) -> String:
	if c.is_down():
		return down_text
	if c.has_order():
		var action: ActionDef = c.order["action"]
		var level := int(c.order.get("level", 0))
		return order_format % [action.display_name, " L%d" % level if level > 0 else ""]
	var text := auto_format % _auto_name(c)
	if c.behavior != Combatant.Behavior.ATTACK:
		text += behavior_suffix_format % _behavior_name(c.behavior)
	return text


func _auto_name(c: Combatant) -> String:
	if c.default_action == null:
		return "Attack"
	return "%s%s" % [c.default_action.display_name, " L%d" % c.default_level if c.default_level > 0 else ""]


func _behavior_name(behavior: int) -> String:
	return str(Combatant.Behavior.keys()[behavior]).capitalize()


# ── selection rings ──────────────────────────────────────────────────────────
## Whose ring to show: in Focus view, whoever is taking their turn; otherwise (and
## between turns) the character you're commanding.
func _ring_subject() -> Combatant:
	if CombatOptions.focus_turns:
		var spot := session.spotlight()
		if spot != null and not spot.is_down():
			return spot
	return _selected


## Who `actor` is aiming at: the target of the turn they're taking, else their usual one.
func _aim_of(actor: Combatant) -> Combatant:
	if actor.turn_pending and actor.pending_plan is Dictionary:
		var planned := (actor.pending_plan as Dictionary).get("target") as Combatant
		if planned != null:
			return planned
	return actor.target


## A ring under the subject, and another under whoever they're aiming at.
func _update_rings() -> void:
	if not session.active:
		return
	var subject := _ring_subject()
	var picked: Node3D = null
	var aimed: Node3D = null
	var picked_color := select_color
	if subject != null and not subject.is_down():
		picked = subject.body
		if subject.side == Combatant.Side.ENEMY:
			picked_color = enemy_turn_color
		var aim := _aim_of(subject)
		if aim != null and aim != subject and not aim.is_down():
			aimed = aim.body
	_select_ring = _place_ring(_select_ring, picked, picked_color, select_radius)
	_target_ring = _place_ring(_target_ring, aimed, target_color, target_radius)


## Puts `ring` on `body` (creating it if needed) or hides it if there is no body.
func _place_ring(ring: Variant, body: Node3D, color: Color, radius: float) -> Variant:
	if body == null or not is_instance_valid(body):
		if is_instance_valid(ring):
			(ring as SelectionRing).visible = false
		return ring
	var live: SelectionRing
	if is_instance_valid(ring):
		live = ring as SelectionRing
		live.set_color(color)
	else:
		live = SelectionRing.new()
		live.color = color
		live.radius = radius
	if live.get_parent() != body:
		if live.get_parent() != null:
			live.get_parent().remove_child(live)
		body.add_child(live)
		live.position = Vector3(0.0, ring_height, 0.0)
	live.visible = true
	return live


func _clear_rings() -> void:
	for ring: Variant in [_select_ring, _target_ring]:
		if is_instance_valid(ring):
			(ring as SelectionRing).queue_free()
	_select_ring = null
	_target_ring = null


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


## Hover text for an action button: what the action does, then how to click it.
func _option_tooltip(opt: Dictionary) -> String:
	var action := opt.get("action") as ActionDef
	if action == null:
		return action_tooltip
	return ActionInfo.details(action, int(opt.get("level", 0))) + "\n\n" + action_tooltip


func _refresh_menu() -> void:
	for child in _action_menu.get_children():
		_action_menu.remove_child(child)
		child.queue_free()
	if session == null or not session.active or _selected == null or _selected.is_down():
		return
	for opt: Dictionary in session.options_for(_selected):
		var cost := int(opt["cost"])
		var text := "%s (%d)" % [opt["label"], cost] if cost > 0 else str(opt["label"])
		if _is_default(opt):
			text = auto_prefix + text
		var b := _new_button(text)
		b.disabled = not opt["affordable"]
		b.tooltip_text = _option_tooltip(opt)
		# Handled in gui_input rather than `pressed`, so a double-click can be told
		# apart from a single click.
		b.gui_input.connect(_on_option_gui_input.bind(opt, b))
		_action_menu.add_child(b)
	var hold := _new_button(hold_on_text if _selected.hold_position else hold_off_text)
	hold.pressed.connect(func():
		session.set_hold(_selected, not _selected.hold_position)
		_refresh_menu())
	_action_menu.add_child(hold)
	var usable := session.behaviors_for(_selected)
	var behavior := _new_button(behavior_format % _behavior_name(_selected.behavior))
	behavior.disabled = usable.size() < 2
	behavior.tooltip_text = behavior_tooltip
	behavior.pressed.connect(func():
		session.set_behavior(_selected, _next_behavior(usable, _selected.behavior)))
	_action_menu.add_child(behavior)
	if _selected.default_action != null:
		var reset := _new_button(reset_auto_text)
		reset.pressed.connect(func(): session.clear_default_action(_selected))
		_action_menu.add_child(reset)
	if _selected.has_order():
		var clear := _new_button(clear_order_text)
		clear.pressed.connect(func(): session.clear_order(_selected))
		_action_menu.add_child(clear)


func _next_behavior(usable: Array[int], current: int) -> int:
	var i := usable.find(current)
	return usable[(i + 1) % usable.size()]


func _is_basic(action: ActionDef) -> bool:
	return action == session.engine.config.get_basic_attack()


## True if this option is the selected character's current automatic action. The basic
## attack is the default when nothing else has been chosen.
func _is_default(opt: Dictionary) -> bool:
	if _selected == null:
		return false
	var action: ActionDef = opt["action"]
	if _is_basic(action):
		return _selected.default_action == null
	return _selected.default_action == action \
			and _selected.default_level == action.resolve_level(int(opt["level"]))


func _on_option_gui_input(event: InputEvent, opt: Dictionary, button: Button) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT or button.disabled:
		return
	if mouse.double_click:
		_on_option_double_clicked(opt)
	else:
		_on_option_pressed(opt)


func _on_option_pressed(opt: Dictionary) -> void:
	if _selected == null:
		return
	# Single-ally and group actions ignore an enemy target; the session picks.
	session.queue_action(_selected, opt["action"], int(opt["level"]), _selected.target)


## Makes the action the automatic one, or undoes it if it already is.
func _on_option_double_clicked(opt: Dictionary) -> void:
	if _selected == null:
		return
	var action: ActionDef = opt["action"]
	# The first click of the double-click already queued it once; the default covers it.
	session.clear_order(_selected)
	if _is_default(opt) and not _is_basic(action):
		session.clear_default_action(_selected)
	else:
		session.set_default_action(_selected, action, int(opt["level"]))


# ── options (log / view) ──
func _apply_options() -> void:
	CombatOptions.ensure_loaded()
	_log.visible = CombatOptions.log_visible
	_log_toggle.set_pressed_no_signal(CombatOptions.log_visible)
	_view_toggle.set_pressed_no_signal(CombatOptions.focus_turns)


func _toggle_log() -> void:
	CombatOptions.set_log_visible(not CombatOptions.log_visible)
	_apply_options()


func _toggle_view() -> void:
	CombatOptions.set_focus_turns(not CombatOptions.focus_turns)
	_apply_options()


# ── banner ──
func _on_spotlight(actor: Combatant) -> void:
	_spot_name = actor.display_name() if actor != null else ""
	_refresh_banner()


func _refresh_banner() -> void:
	if session == null or not session.active:
		return
	_pause_label.visible = session.paused
	if not session.paused and _spot_name != "":
		_banner.text = turn_format % _spot_name
	else:
		_banner.text = ""


# ── input ──
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
	elif key.keycode == KEY_L:
		_toggle_log()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_V:
		_toggle_view()
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


func _on_paused_changed(_is_paused: bool) -> void:
	_refresh_banner()


func _on_combat_ended(victory: bool) -> void:
	_pause_label.hide()
	_banner.text = victory_text if victory else defeat_text
	_clear_rings()
	_refresh_menu()
	await get_tree().create_timer(result_hold_seconds).timeout
	# Let the last turn's dice finish rolling before the HUD closes.
	while not _roll_display.is_idle():
		await get_tree().process_frame
	queue_free()
