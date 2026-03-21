extends Resource
class_name SkillData

@export var skill_name  : String = ""
@export var command_key : String = ""   # "attack" | "support" | "special"
@export var summary : String = ""
@export var description : String = ""
@export var will_cost   : int    = 0    # 0 = free / uses ammo instead
@export var ammo_cost   : int    = 0
# Targeting flags
@export var is_aoe         : bool = false  # hits all enemies / all allies
@export var is_struggle    : bool = false  # no ammo fallback, no target ring
@export var ally_target    : bool = false  # targets allies only
@export var enemy_target   : bool = false  # forces enemy target even as support

## Optional chain of atomic effects executed when this skill fires.
## Used by EnemyActor (and any actor that calls execute_effects).
## Leave empty for skills whose logic lives in a custom actor script.
@export var effects : Array[SkillEffect] = []

## Path to a Node3D on the CASTING actor (relative to actor root) from which
## the reticle line originates. E.g. "PartAnchors/Head" for a head-level attack,
## "PartAnchors/Arm" for a weapon swing.
## Leave empty to fall back to CameraAnchor.
@export var anchor_path : NodePath = NodePath("")
## Name of the struggle-version skill shown as a secondary option during AL_SEGNO/AL_FINE.
## Leave empty if this skill has no struggle fallback.
@export var struggle_name : String = ""

# Returns a Dictionary in the format battle_manager / radial UI expect.
func to_dict() -> Dictionary:
	var d := {
		"name":        skill_name,
		"key":         command_key,
		"summary":     summary,
		"description": description,
	}
	if is_aoe:       d["aoe"]          = true
	if is_struggle:  d["struggle"]     = true
	if ally_target:  d["ally_target"]  = true
	if enemy_target: d["enemy_target"] = true
	if not anchor_path.is_empty(): d["anchor_path"] = anchor_path
	if struggle_name != "": d["struggle_name"] = struggle_name
	return d
