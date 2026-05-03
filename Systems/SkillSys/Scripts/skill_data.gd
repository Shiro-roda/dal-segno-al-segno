extends Resource
class_name SkillData
## Describes one skill. All behaviour lives in the SkillEffect chain.
## Targeting booleans are inferred from effect TargetTypes — not stored here.

@export var skill_name  : String = ""
@export var command_key : String = ""  ## "attack" | "support" | "special" | "struggle"
@export var summary     : String = ""
@export var description : String = ""
@export var will_cost   : int    = 0
@export var ammo_cost   : int    = 0

## The ordered chain of atomic beats that fire when this skill is used.
@export var effects : Array[SkillEffect] = []

## AI weighting. Higher = more likely chosen. Default 1.
@export var ai_weight : int = 1
## Optional tempo override. 0 = use battle_manager default for the command_key.
@export var tempo_cost_override : int = 0


## ── Inferred targeting flags ───────────────────────────────────────────────────
## These replace the old exported booleans. Read-only computed properties.

func is_aoe() -> bool:
	for e in effects:
		if e.target in [
			SkillEffect.TargetType.ALL_OPPONENTS,
			SkillEffect.TargetType.ALL_ALLIES,
			SkillEffect.TargetType.ALL,
		]:
			return true
	return false

func is_struggle() -> bool:
	return command_key == "struggle"

func targets_allies() -> bool:
	for e in effects:
		if e.target in [
			SkillEffect.TargetType.ALL_ALLIES,
			SkillEffect.TargetType.RANDOM_ALLY,
		]:
			return true
	return false

func targets_enemies() -> bool:
	for e in effects:
		if e.target in [
			SkillEffect.TargetType.TARGET,
			SkillEffect.TargetType.ALL_OPPONENTS,
			SkillEffect.TargetType.RANDOM_OPPONENT,
		]:
			return true
	return false


## ── to_dict ───────────────────────────────────────────────────────────────────
## Produces the Dictionary battle_manager / radial UI / enemy_take_turn expect.
## Inferred flags are included so callers need no changes during migration.
func to_dict() -> Dictionary:
	var d : Dictionary = {
		"name":        skill_name,
		"key":         command_key,
		"summary":     summary,
		"description": description,
		"ai_weight":   ai_weight,
	}
	if will_cost > 0:            d["will_cost"]    = will_cost
	if ammo_cost > 0:            d["ammo_cost"]    = ammo_cost
	if is_aoe():                 d["aoe"]          = true
	if is_struggle():            d["struggle"]     = true
	if targets_allies():         d["ally_target"]  = true
	if targets_enemies():        d["enemy_target"] = true
	if tempo_cost_override > 0:  d["tempo_cost"]   = tempo_cost_override
	return d
