## BattleSettings
## Persistent player preferences for battle behaviour.
## Saved to / loaded from user://saves/battle_settings.json automatically.
##
## Designed as an autoload singleton (add as "BattleSettings" in Project > AutoLoad).
##
## ── Battle Mode ──────────────────────────────────────────────────────────────
##   CTB  — Charge Turn Battle (default).  Tempo bars fill in real-time, but
##           player bars pause whenever a command menu is open.  No time
##           pressure while choosing — mirrors FF6 "Wait".
##   ATB  — Active Turn Battle.  Tempo bars fill at all times, including while
##           the player is choosing an action.  Maximum time pressure —
##           mirrors FF4/FF5 "Active".
##
## ── Time-Scale Modifiers (hooks for future features) ─────────────────────────
##   Time-scale is applied to the tempo tick rate only — it never affects
##   _process, physics, or animations, so the game stays deterministic.
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

## The current mode.  Writing triggers settings_changed and an autosave.
var battle_mode : BattleMode = BattleMode.CTB :
	set(v):
		if battle_mode == v: return
		battle_mode = v
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
	# Migration: old format had BattleMode { CTB=0, ATB=1 } + ATBSubmode { ACTIVE=0, WAIT=1 }.
	# Old CTB(0) was a sequential mode we no longer support — map it to new CTB.
	# Old ATB(1)+WAIT(1) → new CTB(0); old ATB(1)+ACTIVE(0) → new ATB(1).
	var raw_mode    : int = int(result.get("battle_mode",          BattleMode.CTB))
	var raw_submode : int = int(result.get("atb_submode",          1))  # 1=WAIT was the old default
	if raw_mode == 0:
		# Old CTB (sequential) — map to new CTB (wait-style real-time)
		battle_mode = BattleMode.CTB
	elif raw_mode == 1 and raw_submode == 0:
		# Old ATB + ACTIVE → new ATB
		battle_mode = BattleMode.ATB
	else:
		# Old ATB + WAIT → new CTB
		battle_mode = BattleMode.CTB
	atb_speed_multiplier = float(result.get("atb_speed_multiplier", 1.0))
	autobattle_mode      = int(result.get("autobattle_mode",      AutobattleMode.OFF))
