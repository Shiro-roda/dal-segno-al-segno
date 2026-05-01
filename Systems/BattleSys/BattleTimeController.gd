## BattleTimeController
## Central authority for the ATB tick rate and all real-time time-scale
## modifiers during battle.
##
## Owned by BattleManager (one instance per battle).  Other systems push
## named modifiers here; the effective scale is the product of all active
## modifiers clamped to [MIN_SCALE, 1.0].
##
## ── Designed extension points ─────────────────────────────────────────────────
##
##   • Arrangement View slow-time
##     When the player opens "Arrangement View" (a future tactical pause/slowdown
##     mode) call:
##       time_controller.push_modifier("arrangement_view", ARRANGEMENT_SCALE)
##     and drain a gauge each frame via consume_arrangement_gauge(delta).
##     On close:
##       time_controller.remove_modifier("arrangement_view")
##     The gauge recharges automatically when the modifier is absent.
##
##   • Status effects (Haste / Slow auras, field effects)
##     push_modifier("haste_field", 1.5) / remove_modifier("haste_field")
##     Modifiers above 1.0 are allowed here (speed-up effects); clamped at
##     MAX_SCALE so the game never becomes a blur.
##
##   • Cutscene / dialogue freeze
##     push_modifier("cutscene", 0.0) freezes all ATB ticking without pausing
##     the SceneTree, keeping animations and tweens alive.
##
## ── Arrangement gauge ─────────────────────────────────────────────────────────
##   Max capacity, drain/recharge rates are tuning constants below.
##   UI should read arrangement_gauge / ARRANGEMENT_GAUGE_MAX each frame.

extends RefCounted
class_name BattleTimeController

# ── Tuning constants ───────────────────────────────────────────────────────────

## Slowdown factor applied while Arrangement View is active.
const ARRANGEMENT_SCALE      : float = 0.15
## Gauge drains by this much per second while arrangement_view is active.
const ARRANGEMENT_DRAIN_RATE : float = 30.0
## Gauge recharges by this much per second while arrangement_view is inactive.
const ARRANGEMENT_CHARGE_RATE: float = 12.0
## Maximum arrangement gauge charge.
const ARRANGEMENT_GAUGE_MAX  : float = 100.0
## Slowest the effective time-scale can go (prevents complete freeze via
## modifier stacking unless a deliberate 0.0 cutscene modifier is added).
const MIN_SCALE : float = 0.0
const MAX_SCALE : float = 3.0

# ── State ─────────────────────────────────────────────────────────────────────

## Named time-scale modifiers currently active.
## Each value multiplies into the final tick scale.
## Use push_modifier / remove_modifier rather than writing directly.
var _modifiers : Dictionary = {}

## Arrangement View gauge.  Full at battle start.
var arrangement_gauge : float = ARRANGEMENT_GAUGE_MAX

## True while the Arrangement View modifier is active.
var arrangement_view_active : bool = false

## True while the battle menu is open (even if the slowdown has lapsed).
## While true, the gauge will not recharge.
var menu_open : bool = false

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when the effective scale changes.  Useful for UI pulse effects.
signal time_scale_changed(new_scale: float)

# ── Modifier API ──────────────────────────────────────────────────────────────

## Add or overwrite a named time-scale modifier.
## scale_value of 0.0 freezes ATB ticking; 1.0 is neutral.
func push_modifier(id: String, scale_value: float) -> void:
	_modifiers[id] = scale_value
	time_scale_changed.emit(effective_scale())

func remove_modifier(id: String) -> void:
	if _modifiers.erase(id):
		time_scale_changed.emit(effective_scale())

func has_modifier(id: String) -> bool:
	return _modifiers.has(id)

## Returns the combined time-scale: product of all active modifier values,
## clamped to [MIN_SCALE, MAX_SCALE].
func effective_scale() -> float:
	var scale := 1.0
	for v in _modifiers.values():
		scale *= v
	return clampf(scale, MIN_SCALE, MAX_SCALE)

# ── Arrangement View ──────────────────────────────────────────────────────────

## Open Arrangement View.  Applies slowdown and starts draining the gauge.
## Returns false (and does nothing) if the gauge is empty.
func open_arrangement_view() -> bool:
	menu_open = true
	if arrangement_gauge <= 0.0:
		return false
	arrangement_view_active = true
	push_modifier("arrangement_view", ARRANGEMENT_SCALE)
	return true

## Close Arrangement View and remove the slowdown modifier.
func close_arrangement_view() -> void:
	menu_open = false
	arrangement_view_active = false
	remove_modifier("arrangement_view")

## Advance the arrangement gauge.  Call once per frame from BattleManager._process.
## Returns true if Arrangement View was auto-closed because the gauge ran out.
func tick_arrangement(delta: float) -> bool:
	var auto_closed := false
	if arrangement_view_active:
		arrangement_gauge -= ARRANGEMENT_DRAIN_RATE * delta
		if arrangement_gauge <= 0.0:
			arrangement_gauge = 0.0
			close_arrangement_view()
			auto_closed = true
	elif not menu_open:
		# Only recharge when the menu is fully closed.
		arrangement_gauge = minf(
			arrangement_gauge + ARRANGEMENT_CHARGE_RATE * delta,
			ARRANGEMENT_GAUGE_MAX
		)
	return auto_closed

## Normalised gauge level in [0, 1].  Drives the UI fill bar.
func arrangement_gauge_ratio() -> float:
	return arrangement_gauge / ARRANGEMENT_GAUGE_MAX
