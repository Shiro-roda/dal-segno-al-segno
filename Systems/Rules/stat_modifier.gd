class_name StatModifier
extends RefCounted
## A bonus or penalty to a stat (or pseudo-stat such as "defense", "damage",
## "initiative", "corpus_max") with a named source, so rolls can show their math.

var stat: StringName
var value: int
var source: String
## Where it came from, e.g. "equipment", so a whole group can be removed at once.
var origin: StringName


static func make(p_stat: StringName, p_value: int, p_source: String, p_origin: StringName = &"") -> StatModifier:
	var m := StatModifier.new()
	m.stat = p_stat
	m.value = p_value
	m.source = p_source
	m.origin = p_origin
	return m
