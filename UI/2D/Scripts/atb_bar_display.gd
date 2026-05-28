## ATBBarDisplay
## Builds and updates the ATB tempo bar strip shown in BattleHUD when the
## battle mode is set to ATB.  Created programmatically by BattleHUD and
## placed above the player status panel.
##
## Each bar is a thin horizontal ProgressBar labelled with the actor name.
## In CTB mode the whole container is hidden and the projected-queue strip
## is shown instead.
##
## Extension points:
##   • Arrangement gauge:  call set_arrangement_gauge(ratio) each frame.
##     The gauge strip is built lazily the first time that method is called.
##   • Enemy bars: call set_show_enemy_bars(true) to reveal enemy tempo bars
##     (useful for autobattle UI or a "Scan" ability that reveals bar state).

extends VBoxContainer
class_name ATBBarDisplay

var HUD_BG     := Color(0.08, 0.07, 0.06, 0.96)
var HUD_ACCENT := Color(0.52, 0.42, 0.28, 1.0)
var HUD_TEXT   := Color(0.88, 0.83, 0.74, 1.0)
var HUD_DIM    := Color(0.45, 0.40, 0.35, 1.0)
const HUD_ENEMY  := Color(1.0,  0.40, 0.40, 1.0)
const HUD_READY  := Color(0.30, 1.0,  0.55, 1.0)  # bar turns green when full
const HUD_FONT   := "res://UI/Themes/Fonts/TerminalVector.ttf"

func _refresh_palette() -> void:
	var p := ThemeManager.palette
	HUD_BG     = Color(p.bg.r, p.bg.g, p.bg.b, 0.96)
	HUD_ACCENT = p.secondary
	HUD_TEXT   = p.text
	HUD_DIM    = p.dim

## actor -> { bar: ProgressBar, label: Label, row: HBoxContainer }
var _bars : Dictionary = {}

var _arrangement_row   : HBoxContainer = null
var _arrangement_bar   : ProgressBar   = null
var _arrangement_label : Label         = null

var _show_enemy_bars := false

# ── Setup ──────────────────────────────────────────────────────────────────────

func build(actor_list: Array) -> void:
	_refresh_palette()
	# Clear any leftovers from a previous battle
	for c in get_children():
		c.queue_free()
	_bars.clear()
	_arrangement_row   = null
	_arrangement_bar   = null
	_arrangement_label = null

	add_theme_constant_override("separation", 3)

	for actor in actor_list:
		if actor.team == BattleActor.Team.ENEMY and not _show_enemy_bars:
			continue
		_add_bar_for(actor)

func _add_bar_for(actor: BattleActor) -> void:
	var font : Font = load(HUD_FONT) if ResourceLoader.exists(HUD_FONT) else ThemeDB.fallback_font

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var lbl := Label.new()
	lbl.text = actor.get_log_name()
	lbl.custom_minimum_size = Vector2(72, 0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color",
		HUD_TEXT if actor.team == BattleActor.Team.PLAYER else HUD_ENEMY)
	if font:
		lbl.add_theme_font_override("font", font)
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_END

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value     = actor.tempo_pool
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size   = Vector2(0, 10)
	_style_bar(bar, HUD_ACCENT)

	row.add_child(lbl)
	row.add_child(bar)
	add_child(row)

	_bars[actor] = { "bar": bar, "label": lbl, "row": row }

func _style_bar(bar: ProgressBar, tint: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.13, 0.11, 0.9)
	bg.set_border_width_all(0)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = tint
	bar.add_theme_stylebox_override("fill", fill)

# ── Per-frame update ───────────────────────────────────────────────────────────

## Call this every frame from BattleHUD._process when in ATB mode.
func refresh(actors: Array) -> void:
	for actor in actors:
		if not _bars.has(actor):
			continue
		var entry : Dictionary = _bars[actor]
		var bar   : ProgressBar = entry["bar"]
		bar.value = actor.tempo_pool
		# Tint the fill green when the bar is ready to act
		var ready: bool = actor.tempo_pool >= 100.0
		var tint  := HUD_READY if ready else \
			(HUD_ACCENT if actor.team == BattleActor.Team.PLAYER else HUD_ENEMY)
		_style_bar(bar, tint)

# ── Arrangement gauge ──────────────────────────────────────────────────────────

## Show or update the Arrangement View gauge strip.
## ratio is in [0, 1].  The strip is built lazily on first call.
func set_arrangement_gauge(ratio: float) -> void:
	if _arrangement_row == null:
		_build_arrangement_strip()
	_arrangement_bar.value = clampf(ratio, 0.0, 1.0) * 100.0
	# Dim the bar when nearly empty
	var tint := Color(0.30, 0.72, 1.0, 1.0) if ratio > 0.2 else Color(0.55, 0.30, 0.30, 1.0)
	_style_bar(_arrangement_bar, tint)

func _build_arrangement_strip() -> void:
	var font : Font = load(HUD_FONT) if ResourceLoader.exists(HUD_FONT) else ThemeDB.fallback_font

	_arrangement_row = HBoxContainer.new()
	_arrangement_row.add_theme_constant_override("separation", 6)

	_arrangement_label = Label.new()
	_arrangement_label.text = "ARRANGE"
	_arrangement_label.custom_minimum_size = Vector2(72, 0)
	_arrangement_label.add_theme_font_size_override("font_size", 11)
	_arrangement_label.add_theme_color_override("font_color", Color(0.30, 0.72, 1.0, 1.0))
	if font:
		_arrangement_label.add_theme_font_override("font", font)
	_arrangement_label.size_flags_horizontal = Control.SIZE_SHRINK_END

	_arrangement_bar = ProgressBar.new()
	_arrangement_bar.min_value  = 0.0
	_arrangement_bar.max_value  = 100.0
	_arrangement_bar.value      = 100.0
	_arrangement_bar.show_percentage = false
	_arrangement_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_arrangement_bar.custom_minimum_size   = Vector2(0, 10)
	_style_bar(_arrangement_bar, Color(0.30, 0.72, 1.0, 1.0))

	_arrangement_row.add_child(_arrangement_label)
	_arrangement_row.add_child(_arrangement_bar)

	# Insert at the top, above the actor bars
	add_child(_arrangement_row)
	move_child(_arrangement_row, 0)

# ── Enemy bar visibility ───────────────────────────────────────────────────────

## Show or hide enemy ATB bars (for scan abilities, autobattle mode UI, etc.)
## Takes effect at the next build() call.
func set_show_enemy_bars(show: bool) -> void:
	_show_enemy_bars = show

## Dynamically add an enemy bar mid-battle (e.g. after a scan skill fires).
func reveal_enemy_bar(actor: BattleActor) -> void:
	if _bars.has(actor):
		return
	_show_enemy_bars = true
	_add_bar_for(actor)

## Hide enemy bar (called when enemy dies so the bar disappears cleanly).
func remove_actor_bar(actor: BattleActor) -> void:
	if not _bars.has(actor):
		return
	var entry : Dictionary = _bars[actor]
	entry["row"].queue_free()
	_bars.erase(actor)
