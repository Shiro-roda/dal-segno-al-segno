class_name LogText
extends Resource
## Every line the combat log and roll breakdown can print, in one place. Open
## Data/log_text.tres in the Inspector and write your own.
##
## Each entry is a list of VARIANTS: one is picked at random each time, so you can
## write several phrasings of the same event. Leave the list empty to print nothing
## for that event. Put {placeholders} where values go; the ones each entry offers
## are listed above it. An unknown placeholder is left as written.

# ------------------------------------------------------------ combat flow
@export_group("Combat flow")
@export var combat_begins: Array[String] = ["Combat begins."]
@export var victory: Array[String] = ["Victory."]
@export var defeat: Array[String] = ["The party has fallen."]
## {actor}
@export var downed: Array[String] = ["{actor} is down."]
## {actor}, {action}: a player order was queued.
@export var order_queued: Array[String] = ["{actor}: {action} queued."]

# --------------------------------------------------------- using actions
@export_group("Using actions")
## {actor}, {action}
@export var action_used: Array[String] = ["{actor} uses {action}."]
## {actor}, {action}, {level}: casting a Canto, at the level it was actually cast.
@export var canto_used: Array[String] = ["{actor} casts {action} at level {level}."]
## {actor}
@export var cannot_act: Array[String] = ["{actor} cannot act."]
@export var canto_locked: Array[String] = ["{actor} has not unlocked {action} (level {level}) yet."]
@export var no_anima: Array[String] = ["Not enough Anima Portions."]
## {actor}, {action}: a queued order the actor could no longer pay for.
@export var cannot_afford: Array[String] = ["{actor} cannot afford {action}."]

# ----------------------------------------------------------------- effects
@export_group("Effects")
## {target}, {amount}, {type}, {corpus}, {max_corpus}
@export var damage: Array[String] = ["{target} takes {amount} {type} damage (Corpus {corpus}/{max_corpus})."]
## {target}, {amount}
@export var heal: Array[String] = ["{target} recovers {amount} Corpus."]
## {target}, {amount}
@export var anima_restored: Array[String] = ["{target} recovers {amount} Anima Portions."]
## {target}, {condition}
@export var condition_applied: Array[String] = ["{target} is afflicted with {condition}."]
## {target}: a save negated the effect.
@export var resisted: Array[String] = ["{target} resists."]

# ------------------------------------------------------- conditions in time
@export_group("Conditions over time")
## {target}, {amount}, {condition}: damage at the end of a round.
@export var condition_tick: Array[String] = ["{target} takes {amount} from {condition}."]
## {target}, {condition}
@export var condition_ends: Array[String] = ["{condition} wears off {target}."]

# ----------------------------------------------------------------- rolls
@export_group("Roll breakdown")
## Names a roll. {attacker}, {defender}
@export var attack_label: Array[String] = ["{attacker} attacks {defender}"]
## Names a skill or attribute check. {actor}, {stat}
@export var check_label: Array[String] = ["{actor} {stat}"]
## The whole roll line. {label}, {math}, {total}, {target}, {outcome}
@export var roll_line: Array[String] = ["{label}: {math} = {total} vs {target} -> {outcome}"]
@export var outcome_success: Array[String] = ["SUCCESS"]
@export var outcome_failure: Array[String] = ["FAILURE"]
@export var outcome_critical_success: Array[String] = ["CRITICAL SUCCESS"]
@export var outcome_fumble: Array[String] = ["FUMBLE"]
## Appended to the dice math when the roll had advantage / disadvantage.
@export var mode_advantage: Array[String] = [" (advantage)"]
@export var mode_disadvantage: Array[String] = [" (disadvantage)"]


## Picks a variant of `event` (the name of one of the lists above) and fills in the
## placeholders from `vars`. Returns "" if the list is empty or the name is unknown.
func line(event: StringName, vars: Dictionary = {}, rng: RandomNumberGenerator = null) -> String:
	var variants = get(event)
	if not (variants is Array):
		push_warning("LogText: no entry named '%s'." % event)
		return ""
	if variants.is_empty():
		return ""
	var index := 0
	if variants.size() > 1:
		index = (rng.randi() if rng != null else randi()) % variants.size()
	var out := String(variants[index])
	for key in vars:
		out = out.replace("{%s}" % key, str(vars[key]))
	return out
