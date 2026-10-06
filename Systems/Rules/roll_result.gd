class_name RollResult
extends RefCounted
## Full breakdown of one d20 roll, suitable for a combat log.

enum Kind { CHECK, ATTACK, SAVE }

var kind: Kind = Kind.CHECK
var label: String = ""
var stat: StringName
## 0 = normal, 1 = advantage, -1 = disadvantage.
var mode: int = 0
var rolls: Array[int] = []
var natural: int = 0
## Array of {source: String, value: int}.
var parts: Array = []
var bonus: int = 0
var total: int = 0
## DC for checks and saves, defense for attacks.
var target: int = 0
var success: bool = false
var crit: bool = false
var fumble: bool = false
## Where the wording comes from. Set by the engine; a default is used if null.
var text: LogText


func describe() -> String:
	var t := text if text != null else LogText.new()
	var mode_text := ""
	if mode > 0:
		mode_text = t.line(&"mode_advantage")
	elif mode < 0:
		mode_text = t.line(&"mode_disadvantage")
	var rolls_text := str(natural)
	if rolls.size() > 1:
		rolls_text = "%d [%s]" % [natural, ", ".join(rolls.map(func(r): return str(r)))]
	var bits: Array[String] = []
	for p in parts:
		bits.append("%s %+d" % [p["source"], p["value"]])
	var math := "d20 %s%s" % [rolls_text, mode_text]
	if not bits.is_empty():
		math += " + " + ", ".join(bits)
	var outcome_event := &"outcome_success" if success else &"outcome_failure"
	if crit:
		outcome_event = &"outcome_critical_success"
	elif fumble:
		outcome_event = &"outcome_fumble"
	return t.line(&"roll_line", {"label": label, "math": math, "total": total,
			"target": target, "outcome": t.line(outcome_event)})
