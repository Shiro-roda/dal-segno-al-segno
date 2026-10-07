class_name LevelUpOffer
extends RefCounted
## The choices a character faces on reaching a new level. Built by Leveling,
## filled in by the player (or an AI), then applied with Leveling.apply().

const FEAT := &"feat"
const CANTO := &"canto"
const ATTRIBUTE := &"attribute"

var char_id: StringName
var new_level: int = 1
## The hit-die roll made when this offer was applied (0 until then).
var corpus_roll: int = 0
## One entry per pick: {kind: StringName, options: Array, chosen: Variant}.
## `chosen` is null until a choice is made. Options are FeatDefs, ActionDefs,
## or attribute ids, depending on the kind.
var picks: Array[Dictionary] = []


func is_empty() -> bool:
	return picks.is_empty()


func is_complete() -> bool:
	for p in picks:
		if p["chosen"] == null:
			return false
	return true


## Records a choice for pick `index`. Returns false if it isn't one of the options.
func choose(index: int, option: Variant) -> bool:
	if index < 0 or index >= picks.size():
		return false
	if not (picks[index]["options"] as Array).has(option):
		return false
	picks[index]["chosen"] = option
	return true


## Chooses at random for every pick that is still open.
func auto_choose(rng: RandomNumberGenerator) -> void:
	for p in picks:
		var options: Array = p["options"]
		if p["chosen"] == null and not options.is_empty():
			p["chosen"] = options[rng.randi_range(0, options.size() - 1)]
