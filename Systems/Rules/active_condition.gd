class_name ActiveCondition
extends RefCounted
## A ConditionDef currently applied to a StatBlock.

var def: ConditionDef
## Rounds left. -1 = permanent.
var remaining: int = 0
var source: String = ""


static func make(p_def: ConditionDef, p_source: String = "", p_duration: int = -2) -> ActiveCondition:
	var c := ActiveCondition.new()
	c.def = p_def
	c.source = p_source if p_source != "" else p_def.display_name
	c.remaining = p_def.duration_rounds if p_duration == -2 else p_duration
	return c
