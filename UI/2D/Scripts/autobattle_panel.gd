extends CanvasLayer
class_name AutobattlePanel
## AutobattlePanel — in-battle overlay for managing per-actor autobattle enrollment.
##
## Opened from the battle menu or a dedicated keybind.
## Shows each player actor as a card with:
##   - Name + HP
##   - Toggle button: MANUAL / AUTO
##   - (Future) "EDIT SCRIPT" button to open the visual rule editor
##
## Changes are applied immediately via BattleSettings.set_actor_autobattle().
## The panel does NOT pause the battle — the caller should handle time freezing.

signal closed

const FONT_PATH    := "res://UI/Themes/Fonts/SpaceMono-Bold.ttf"
const FONT_SM_PATH := "res://UI/Themes/Fonts/SpaceMono-Bold.ttf"

const C_BG       := Color(0.04, 0.03, 0.05, 0.96)
const C_BORDER   := Color(0.25, 0.20, 0.35, 1.0)
const C_CARD_BG  := Color(0.08, 0.06, 0.10, 1.0)
const C_AUTO     := Color(0.15, 1.00, 0.45, 1.0)   # green — autobattle on
const C_MANUAL   := Color(0.65, 0.65, 0.70, 1.0)   # grey — manual
const C_TEXT     := Color(0.88, 0.85, 0.92, 1.0)
const C_DIM      := Color(0.50, 0.48, 0.55, 1.0)
const C_HP_BAR   := Color(0.20, 0.85, 0.45, 1.0)
const C_HP_EMPTY := Color(0.20, 0.18, 0.22, 1.0)
const C_TITLE    := Color(0.55, 0.35, 0.90, 1.0)

var _font    : Font = null
var _font_sm : Font = null
var _actors  : Array = []   # Array[BattleActor]
var _cards   : Array = []   # Array[Control] — one per actor

var _root_panel : PanelContainer = null

func _ready() -> void:
	layer = 30
	_font    = load(FONT_PATH)    if ResourceLoader.exists(FONT_PATH)    else null
	_font_sm = load(FONT_SM_PATH) if ResourceLoader.exists(FONT_SM_PATH) else null
	hide()


# ── Public API ────────────────────────────────────────────────────────────────

## Open the panel and populate it with the provided player actors.
func open(player_actors: Array) -> void:
	_actors = player_actors.filter(func(a): return is_instance_valid(a) and a.is_alive())
	_rebuild()
	show()


func close() -> void:
	_clear()
	hide()
	emit_signal("closed")


# ── Build UI ──────────────────────────────────────────────────────────────────

func _rebuild() -> void:
	_clear()

	# ── Root panel ────────────────────────────────────────────────────────────
	var root := PanelContainer.new()
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = C_BG
	sbox.set_border_width_all(1)
	sbox.border_color = C_BORDER
	sbox.set_content_margin_all(20)
	root.add_theme_stylebox_override("panel", sbox)
	root.set_anchor(SIDE_LEFT,   0.15)
	root.set_anchor(SIDE_RIGHT,  0.85)
	root.set_anchor(SIDE_TOP,    0.15)
	root.set_anchor(SIDE_BOTTOM, 0.85)
	add_child(root)
	_root_panel = root

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	root.add_child(vbox)

	# ── Title row ─────────────────────────────────────────────────────────────
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	var title_lbl := Label.new()
	title_lbl.text = "AUTOBATTLE  —  MANAGE ACTORS"
	if _font: title_lbl.add_theme_font_override("font", _font)
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", C_TITLE)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕  CLOSE"
	if _font: close_btn.add_theme_font_override("font", _font)
	close_btn.add_theme_font_size_override("font_size", 12)
	_style_btn(close_btn, C_DIM)
	close_btn.pressed.connect(close)
	title_row.add_child(close_btn)

	# ── Separator ─────────────────────────────────────────────────────────────
	var sep := HSeparator.new()
	var sep_sbox := StyleBoxFlat.new()
	sep_sbox.bg_color = C_BORDER
	sep_sbox.content_margin_top    = 0
	sep_sbox.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", sep_sbox)
	vbox.add_child(sep)

	# ── Description line ──────────────────────────────────────────────────────
	var desc := Label.new()
	desc.text = "Toggle AUTO to let an actor act on their own each turn.  MANUAL = you control them."
	if _font_sm: desc.add_theme_font_override("font", _font_sm)
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", C_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	# ── Actor cards ───────────────────────────────────────────────────────────
	var cards_grid := HFlowContainer.new()
	cards_grid.add_theme_constant_override("h_separation", 14)
	cards_grid.add_theme_constant_override("v_separation", 14)
	vbox.add_child(cards_grid)

	for actor in _actors:
		var card := _make_actor_card(actor)
		cards_grid.add_child(card)
		_cards.append(card)

	# ── Footer hint ───────────────────────────────────────────────────────────
	var footer := Label.new()
	footer.text = "EDIT SCRIPT  coming soon — define priority rules, conditions, and target logic per actor."
	if _font_sm: footer.add_theme_font_override("font", _font_sm)
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", C_DIM)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(footer)


func _make_actor_card(actor: BattleActor) -> Control:
	var is_auto : bool = BattleSettings.is_actor_autobattling(actor)

	var card := PanelContainer.new()
	var card_sbox := StyleBoxFlat.new()
	card_sbox.bg_color = C_CARD_BG
	card_sbox.set_border_width_all(1)
	card_sbox.border_color = C_AUTO if is_auto else C_BORDER
	card_sbox.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", card_sbox)
	card.custom_minimum_size = Vector2(200, 110)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	card.add_child(cv)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = actor.display_name.to_upper()
	if _font: name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", C_AUTO if is_auto else C_TEXT)
	cv.add_child(name_lbl)

	# HP bar
	var hp_row := HBoxContainer.new()
	cv.add_child(hp_row)

	var hp_bar := ProgressBar.new()
	hp_bar.min_value = 0
	hp_bar.max_value = max(actor.max_hp, 1)
	hp_bar.value = actor.hp
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(120, 6)
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hp_fg := StyleBoxFlat.new(); hp_fg.bg_color = C_HP_BAR
	var hp_bg := StyleBoxFlat.new(); hp_bg.bg_color = C_HP_EMPTY
	hp_bar.add_theme_stylebox_override("fill",       hp_fg)
	hp_bar.add_theme_stylebox_override("background", hp_bg)
	hp_row.add_child(hp_bar)

	var hp_lbl := Label.new()
	hp_lbl.text = "  %d/%d" % [actor.hp, actor.max_hp]
	if _font_sm: hp_lbl.add_theme_font_override("font", _font_sm)
	hp_lbl.add_theme_font_size_override("font_size", 10)
	hp_lbl.add_theme_color_override("font_color", C_DIM)
	hp_row.add_child(hp_lbl)

	# Toggle button
	var toggle := Button.new()
	toggle.text = "●  AUTO" if is_auto else "○  MANUAL"
	if _font: toggle.add_theme_font_override("font", _font)
	toggle.add_theme_font_size_override("font_size", 12)
	_style_btn(toggle, C_AUTO if is_auto else C_MANUAL)
	var cap_actor := actor
	var cap_card  := card
	var cap_name  := name_lbl
	var cap_toggle := toggle
	var cap_sbox  := card_sbox
	toggle.pressed.connect(func(): _on_toggle(cap_actor, cap_card, cap_name, cap_toggle, cap_sbox))
	cv.add_child(toggle)

	return card


func _on_toggle(
		actor: BattleActor,
		card: Control,
		name_lbl: Label,
		toggle: Button,
		card_sbox: StyleBoxFlat) -> void:

	var currently_auto : bool = BattleSettings.is_actor_autobattling(actor)

	if currently_auto:
		# Switch to manual — remove the runtime config override.
		BattleSettings.set_actor_autobattle(actor.display_name, null)
	else:
		# Switch to auto — create a minimal config that enables the actor.
		# If CharacterData already has a full config, we just need to enable it.
		var existing_cfg : ActorAutobattleConfig = null
		if is_instance_valid(actor.party_member) and \
				is_instance_valid(actor.party_member.character) and \
				actor.party_member.character.get("autobattle_config") != null:
			existing_cfg = actor.party_member.character.autobattle_config
		if existing_cfg != null:
			existing_cfg.enabled = true
			BattleSettings.set_actor_autobattle(actor.display_name, existing_cfg)
		else:
			# No authored config — create a default REPEAT_LAST fallback config.
			var cfg := ActorAutobattleConfig.new()
			cfg.enabled = true
			cfg.fallback_repeat_last = true
			BattleSettings.set_actor_autobattle(actor.display_name, cfg)

	var now_auto : bool = BattleSettings.is_actor_autobattling(actor)
	toggle.text      = "●  AUTO" if now_auto else "○  MANUAL"
	name_lbl.add_theme_color_override("font_color", C_AUTO if now_auto else C_TEXT)
	card_sbox.border_color = C_AUTO if now_auto else C_BORDER
	_style_btn(toggle, C_AUTO if now_auto else C_MANUAL)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _style_btn(btn: Button, col: Color) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(col.r * 0.12, col.g * 0.12, col.b * 0.12, 1.0)
	n.set_border_width_all(1)
	n.border_color = Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 1.0)
	n.set_content_margin_all(6)
	var h := StyleBoxFlat.new()
	h.bg_color = Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 1.0)
	h.set_border_width_all(1)
	h.border_color = col
	h.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal",  n)
	btn.add_theme_stylebox_override("hover",   h)
	btn.add_theme_stylebox_override("pressed", h)
	btn.add_theme_stylebox_override("focus",   n)
	btn.add_theme_color_override("font_color",         col)
	btn.add_theme_color_override("font_hover_color",   Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)


func _clear() -> void:
	if is_instance_valid(_root_panel):
		_root_panel.queue_free()
	_root_panel = null
	_cards.clear()


func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
