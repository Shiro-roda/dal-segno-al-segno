class_name CombatOptions
extends RefCounted
## Player preferences for combat. Static, so every fight shares them; saved between runs.

const _FILE := "user://combat_options.cfg"
const _SECTION := "combat"

## Show the combat log panel.
static var log_visible: bool = true
## false = Overview (real time, as before). true = Focus: the camera follows each
## combatant's turn and everyone else slows down while they act.
static var focus_turns: bool = false
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(_FILE) != OK:
		return
	log_visible = bool(cfg.get_value(_SECTION, "log_visible", true))
	focus_turns = bool(cfg.get_value(_SECTION, "focus_turns", false))


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(_SECTION, "log_visible", log_visible)
	cfg.set_value(_SECTION, "focus_turns", focus_turns)
	if cfg.save(_FILE) != OK:
		push_warning("CombatOptions: couldn't save preferences.")


static func set_log_visible(value: bool) -> void:
	ensure_loaded()
	log_visible = value
	save()


static func set_focus_turns(value: bool) -> void:
	ensure_loaded()
	focus_turns = value
	save()
