extends Node
## Autoload "Rules": the game-facing entry point to the rules core.
##
## Holds the shared RulesEngine and a registry of actors (StatBlocks), and exposes
## methods that Dialogic can call without knowing anything about our stats.
##
## In a Dialogic timeline (conditions can call autoload methods directly):
##   if {Rules.check("persuasion", 12)}:
##       [Rules check: {Rules.last_roll_text}]
##       Elder: Very well.
##   else:
##       Elder: Not a chance.
## or with the Call event:  do Rules.check("persuasion", 12)
## then read {Rules.last_roll_success} / {Rules.last_roll_text} afterwards.

signal roll_made(result: RollResult)

const STATS_DIR := "res://Systems/Rules/Data/Stats"
## Every line the combat log can print. Edit this resource to write your own.
const LOG_TEXT_PATH := "res://Systems/Rules/Data/log_text.tres"
## Actor id used when a call does not name one: the player character.
const PLAYER := "pc"

var engine: RulesEngine
## Everyone recruited, and the active party.
var roster: PartyRoster
## actor id -> StatBlock
var actors: Dictionary = {}

var last_roll: RollResult
var last_roll_text: String = ""
var last_roll_success: bool = false
var last_roll_natural: int = 0
var last_roll_total: int = 0


func _ready() -> void:
	engine = RulesEngine.new()
	roster = PartyRoster.new(engine)
	var loaded := engine.load_stat_defs(STATS_DIR)
	print("[Rules] loaded %d stat definitions." % loaded)
	var log_text := load(LOG_TEXT_PATH) as LogText if ResourceLoader.exists(LOG_TEXT_PATH) else null
	if log_text == null:
		# First run from the editor: create the resource so there is a file to edit.
		log_text = LogText.new()
		if OS.has_feature("editor") and ResourceSaver.save(log_text, LOG_TEXT_PATH) == OK:
			print("[Rules] created %s: open it to write your own log text." % LOG_TEXT_PATH)
	engine.text = log_text


# ------------------------------------------------------------- actors

func register_actor(actor_id: String, block: StatBlock) -> void:
	actors[actor_id] = block


func get_actor(actor_id: String = PLAYER) -> StatBlock:
	return actors.get(actor_id) as StatBlock


## Adds a character to the roster and registers them as an actor under their sheet id
## (e.g. {Rules.check("persuasion", 12, "kendall")}). `is_player` also registers them
## as "pc", the default actor for checks that name no one.
func recruit(sheet: CharacterSheet, make_active: bool = true, is_player: bool = false) -> StatBlock:
	var block := roster.recruit(sheet, make_active)
	register_actor(String(sheet.id), block)
	if is_player:
		register_actor(PLAYER, block)
	return block


# ----------------------------------------------- Dialogic-friendly API

## Skill or attribute check against a DC. `mode` is "normal", "advantage" or
## "disadvantage". Returns true on success; details land in last_roll_*.
func check(stat: String, dc: int, actor_id: String = PLAYER, mode: String = "normal") -> bool:
	var actor := _resolve(stat, actor_id)
	if actor == null:
		return false
	return _record(engine.check(actor, StringName(stat), dc, _mode(mode)))


## Saving throw against a DC. Same arguments and results as check().
func save(stat: String, dc: int, actor_id: String = PLAYER, mode: String = "normal") -> bool:
	var actor := _resolve(stat, actor_id)
	if actor == null:
		return false
	return _record(engine.save(actor, StringName(stat), dc, _mode(mode)))


## Total modifier for a stat, for conditions like {Rules.mod("persuasion") >= 2}.
func mod(stat: String, actor_id: String = PLAYER) -> int:
	var actor := _resolve(stat, actor_id)
	if actor == null:
		return 0
	return actor.total_mod(StringName(stat))


func has_condition(condition_id: String, actor_id: String = PLAYER) -> bool:
	var actor := get_actor(actor_id)
	return actor != null and actor.has_condition(StringName(condition_id))


# ------------------------------------------------------------ internals

func _resolve(stat: String, actor_id: String) -> StatBlock:
	var actor := get_actor(actor_id)
	if actor == null:
		push_warning("[Rules] no actor registered as '%s'." % actor_id)
		return null
	if engine.get_stat(StringName(stat)) == null:
		push_warning("[Rules] unknown stat '%s'." % stat)
		return null
	return actor


func _mode(mode: String) -> RulesEngine.RollMode:
	match mode.to_lower():
		"advantage", "adv":
			return RulesEngine.RollMode.ADVANTAGE
		"disadvantage", "dis":
			return RulesEngine.RollMode.DISADVANTAGE
	return RulesEngine.RollMode.NORMAL


func _record(result: RollResult) -> bool:
	last_roll = result
	last_roll_text = result.describe()
	last_roll_success = result.success
	last_roll_natural = result.natural
	last_roll_total = result.total
	roll_made.emit(result)
	return result.success
