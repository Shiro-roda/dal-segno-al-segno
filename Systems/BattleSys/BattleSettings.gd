## BattleSettings
## Persistent player preferences for battle behaviour.
## Saved to / loaded from user://saves/battle_settings.json automatically.
##
## Designed as an autoload singleton (add as "BattleSettings" in Project > AutoLoad).
##
## ── Battle Mode ──────────────────────────────────────────────────────────────
##   ATB  — Active Turn Battle.  Tempo bars fill in real-time; enemies and
##           ready players act as their bars complete.  Time pressure exists.
##   CTB  — Charge Turn Battle (current default).  The game is fully
##           paused between turns; no real-time pressure.
##
## ── ATB Submode ──────────────────────────────────────────────────────────────
##   ACTIVE — Player bars continue filling even while they are choosing an
##            action.  Maximum pressure; mirrors FF4/FF5 "Active".
##   WAIT   — Player bars pause whenever the player has a command menu open.
##            Mirrors FF6 "Wait"; a good accessibility default.
##
## ── Time-Scale Modifiers (hooks for future features) ─────────────────────────
##   Time-scale is applied to the ATB tick rate only — it never affects
##   _process physics or animations, so the game stays deterministic.
##   Systems that need to modify time write to the BattleTimeController (see
##   res://Systems/BattleSys/BattleTimeController.gd) rather than here.
##
## ── Autobattle ───────────────────────────────────────────────────────────────
##   Autobattle hooks are declared as typed signals / callbacks here so every
##   future autobattle strategy (repeat-last, AI-script, full AI) has a single
##   well-defined integration point.  The actual strategy implementations live
##   elsewhere and register themselves via register_autobattle_strategy().

extends Node

# ── Save path ────────────────────────────────────────────────────────────────

const SETTINGS_PATH := "user://saves/battle_settings.json"

# ── Signals ──────────────────────────────────────────────────────────────────

## Emitted whenever any setting changes so UI can refresh without polling.
signal settings_changed

# ── Battle mode ───────────────────────────────────────────────────────────────

enum BattleMode { CTB, ATB }
enum ATBSubmode  { ACTIVE, WAIT }

## The current mode.  Writing triggers settings_changed and an autosave.
var battle_mode : BattleMode = BattleMode.ATB :
	set(v):
		if battle_mode == v: return
		battle_mode = v
		settings_changed.emit()
		save()

## ATB submode (only relevant when battle_mode == ATB).
var atb_submode : ATBSubmode = ATBSubmode.WAIT :
	set(v):
		if atb_submode == v: return
		atb_submode = v
		settings_changed.emit()
		save()

# ── ATB speed ─────────────────────────────────────────────────────────────────

## Global ATB fill-rate multiplier.  1.0 = default.  Range [0.25, 3.0].
## Adjust this in settings to let players control the overall pace.
var atb_speed_multiplier : float = 1.0 :
	set(v):
		atb_speed_multiplier = clampf(v, 0.25, 3.0)
		settings_changed.emit()
		save()

# ── Autobattle ────────────────────────────────────────────────────────────────

enum AutobattleMode {
	OFF,           ## Player controls all input (default).
	REPEAT_LAST,   ## Automatically repeat each character's last confirmed action.
	AI_SCRIPT,     ## Reserved: run a designer-authored action script.
	FULL_AI,       ## Reserved: run a learned / heuristic AI policy.
}

var autobattle_mode : AutobattleMode = AutobattleMode.OFF :
	set(v):
		if autobattle_mode == v: return
		autobattle_mode = v
		settings_changed.emit()
		save()

## Registered strategy callables keyed by AutobattleMode value.
## A strategy receives (BattleActor, BattleManager) and returns a Dictionary
## describing the chosen action, or {} to fall back to player input.
## Register via register_autobattle_strategy(); called by BattleManager.
var _autobattle_strategies : Dictionary = {}

func register_autobattle_strategy(mode: AutobattleMode, strategy: Callable) -> void:
	_autobattle_strategies[mode] = strategy

## Returns the registered callable for the current autobattle_mode, or an invalid Callable.
func get_autobattle_strategy() -> Callable:
	if autobattle_mode == AutobattleMode.OFF:
		return Callable()
	return _autobattle_strategies.get(autobattle_mode, Callable())

## True when autobattle is on AND a strategy has been registered for the current mode.
func is_autobattling() -> bool:
	return autobattle_mode != AutobattleMode.OFF and \
		   _autobattle_strategies.has(autobattle_mode)

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	load_settings()

# ── Persistence ───────────────────────────────────────────────────────────────

func save() -> void:
	var data := {
		"battle_mode":           battle_mode,
		"atb_submode":           atb_submode,
		"atb_speed_multiplier":  atb_speed_multiplier,
		"autobattle_mode":       autobattle_mode,
	}
	var dir := "user://saves/"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	var result: Variant = JSON.parse_string(text)
	if result == null or not result is Dictionary:
		return
	# Read with safe defaults so old saves forward-compat gracefully.
	battle_mode          = int(result.get("battle_mode",          BattleMode.ATB))
	atb_submode          = int(result.get("atb_submode",          ATBSubmode.WAIT))
	atb_speed_multiplier = float(result.get("atb_speed_multiplier", 1.0))
	autobattle_mode      = int(result.get("autobattle_mode",      AutobattleMode.OFF))
