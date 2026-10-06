class_name StatDef
extends Resource
## Definition of one attribute, skill or derived stat.
## The engine knows nothing about specific stats; everything comes from these resources.

enum Category { ATTRIBUTE, SKILL, DERIVED, SAVE }

@export var id: StringName
@export var display_name: String = ""
@export var category: Category = Category.ATTRIBUTE
## For skills and saves: the attributes this stat is built from. With more than one,
## each attribute contributes its modifier divided by the count, rounded up
## (two attributes = half of each, rounded up). Empty for attributes themselves.
@export var governing_stats: Array[StringName] = []
## Tags for grouping and filtering, e.g. "physical", "mental", "color".
@export var tags: PackedStringArray = PackedStringArray()
## UI / magic colour (used by the colour stats; white otherwise).
@export var color: Color = Color.WHITE
@export_multiline var description: String = ""


func has_tag(tag: String) -> bool:
	return tags.has(tag)
