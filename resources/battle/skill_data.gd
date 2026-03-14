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
	return d
