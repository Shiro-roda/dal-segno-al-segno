extends Control
class_name ActorPanel

var actor : BattleActor

@onready var name_label: Label = $ActorPanelVBox/NameLabel
@onready var hp_bar: TextureProgressBar = $ActorPanelVBox/HPBar
@onready var hp_text: Label = $ActorPanelVBox/HPText
@onready var will_bar: TextureProgressBar = $ActorPanelVBox/WillBar
@onready var ammo_label: Label = $ActorPanelVBox/AmmoLabel
@onready var will_label: Label = $ActorPanelVBox/WillLabel


# Overlay ColorRect drawn on top of the HP bar to show temp (shield) HP
var _shield_overlay : ColorRect
const SHIELD_COLOR := Color(0.49, 0.918, 0.024, 1.0)  # yellow-green




func setup(a : BattleActor):
	actor = a
	# Defer display setup until _ready so @onready vars are resolved
	if is_inside_tree():
		_apply_setup()


var _setup_done := false

func _ready():
	if actor and not _setup_done:
		_apply_setup()


const _HUD_BG     := Color(0.08, 0.07, 0.06, 0.96)
const _HUD_ACCENT := Color(0.52, 0.42, 0.28, 1.0)
const _HUD_TEXT   := Color(0.88, 0.83, 0.74, 1.0)
const _HUD_DIM    := Color(0.45, 0.40, 0.35, 1.0)
const _HUD_FONT   := "res://assets/Fonts/TerminalVector.ttf"

func _apply_setup():
	_setup_done = true
	# Panel style — dark bg, accent on top edge
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = _HUD_BG
	sbox.set_border_width_all(0)
	sbox.border_width_top = 2
	sbox.border_color = _HUD_ACCENT
	sbox.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sbox)
	# Font + colour on all labels
	var font : Font = load(_HUD_FONT) if ResourceLoader.exists(_HUD_FONT) else ThemeDB.fallback_font
	for lbl in [name_label, hp_text, will_label, ammo_label]:
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_color_override("font_color", _HUD_TEXT)
	# HP bar tinted to accent gold
	hp_bar.modulate = _HUD_ACCENT
	will_bar.modulate = _HUD_ACCENT
	name_label.text = actor.name
	hp_bar.max_value = actor.max_hp

	var has_will = actor.party_member != null and actor.party_member.has_will()
	will_bar.visible = has_will
	will_label.visible = has_will
	ammo_label.visible = not has_will
	if has_will:
		will_bar.max_value = actor.party_member.max_will

	# Shield overlay — sits on top of the HP bar, right-aligned to show temp HP
	_shield_overlay = ColorRect.new()
	_shield_overlay.color = SHIELD_COLOR
	_shield_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.add_child(_shield_overlay)

	update_display()

	actor.hp_changed.connect(update_display)
	actor.turn_finished.connect(update_display)
	actor.died.connect(_on_died)
	actor.status_applied.connect(_on_status_applied)
	if actor.party_member != null and actor.party_member.has_will():
		actor.party_member.will_changed.connect(update_display)

func update_display():
	hp_bar.value = actor.hp
	var shield: int = actor.shield_hp if actor.shield_hp > 0 else 0
	# HP text shows real hp / max_hp; temp HP shown separately in overlay
	if shield > 0:
		hp_text.text = "%d (+%d) / %d" % [actor.hp, shield, actor.max_hp]
	else:
		hp_text.text = "%d / %d" % [actor.hp, actor.max_hp]
	if actor.party_member != null and actor.party_member.has_will():
		will_bar.value = actor.party_member.will
		will_label.text = "%d / %d" % [actor.party_member.will, actor.party_member.max_will]
	elif actor.run_state != null:
		ammo_label.text = "AMMO: %d/%d" % [actor.run_state.ammo, actor.run_state.max_ammo]
	_update_shield_overlay()


func _update_shield_overlay() -> void:
	if _shield_overlay == null:
		return
	var shield: int = actor.shield_hp if actor.shield_hp > 0 else 0
	if shield <= 0:
		_shield_overlay.visible = false
		return
	_shield_overlay.visible = true
	# Size the overlay proportionally to shield_hp / max_hp, right-aligned
	var bar_w := hp_bar.size.x
	var bar_h := hp_bar.size.y
	# Overlay starts where the real HP fill ends, extends rightward by the shield amount.
	# This means it sits adjacent to the HP fill rather than overlapping it.
	var hp_ratio     : float = clampf(float(actor.hp) / float(actor.max_hp), 0.0, 1.0)
	var shield_ratio : float = clampf(float(shield) / float(actor.max_hp), 0.0, 1.0 - hp_ratio)
	var hp_x         : float = bar_w * hp_ratio
	var shield_w     : float = bar_w * shield_ratio
	_shield_overlay.size     = Vector2(shield_w, bar_h)
	_shield_overlay.position = Vector2(hp_x, 0.0)


func _on_status_applied(_effect_id: String) -> void:
	_update_shield_overlay()


func _on_died(_a):
	modulate.a = 0.4
