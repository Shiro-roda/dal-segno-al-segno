extends Resource
class_name GunData
## GunData — an equippable gun for Kendall.
## Guns occupy one of two equipment slots ("gun_primary", "gun_secondary").
## They modify how Shoot behaves: clip size, damage multiplier, special properties.
##
## The "Shoot" skill entry in SkillDirectory is the TEMPLATE; at runtime
## KendallActor reads the equipped gun and applies overrides via get_shoot_dict().

## How many bullets this gun holds (overrides RunState.gun_clip when equipped).
@export var clip_size        : int   = 6

## Damage multiplier applied on top of Kendall's base attack_power.
## 1.0 = identical to the default Shoot. 1.5 = 50% more damage.
@export var damage_mult      : float = 1.0

## Flat bonus damage added per shot (before defense, after mult).
@export var damage_bonus     : int   = 0

## Ammo cost per shot. Default 1. Some exotic guns cost 2 for a stronger shot.
@export var ammo_cost        : int   = 1

## If true the gun is AoE — hits all enemies per shot.
@export var is_aoe           : bool  = false

## Special property tag — drives unique behaviours in KendallActor.
## "" = none  |  "pierce" = ignores FLAT  |  "bleed" = applies bleeding
## "double" = fires twice at 0.6x each   |  "reload" = restores 1 ammo on kill
@export var special_property : String = ""

## Status inflicted on hit (if any). Works with special_property = "bleed" etc.
@export var on_hit_status    : String = ""
## Chance (0-1) the on_hit_status is applied.
@export var on_hit_chance    : float  = 0.0
## Duration of on_hit_status in turns.
@export var on_hit_duration  : int    = 2

## Flavour text shown in the Motif Tree and equipment tooltip.
@export var gun_flavour      : String = ""

## Display name shown in the skill slot when this gun is equipped.
@export var gun_name         : String = ""

## Build the skill Dictionary that KendallActor's get_skills() will return
## in place of the default "Shoot" entry when this gun is equipped.
func get_shoot_dict(struggle_fallback: bool = false) -> Dictionary:
	if struggle_fallback:
		return SkillDirectory.get_dict("Pistol Whip")
	var d : Dictionary = SkillDirectory.get_dict("Shoot").duplicate()
	d["gun_data"]       = self
	d["damage_mult"]    = damage_mult
	d["damage_bonus"]   = damage_bonus
	d["ammo_cost"]      = ammo_cost
	d["is_aoe"]         = is_aoe
	d["special"]        = special_property
	d["on_hit_status"]  = on_hit_status
	d["on_hit_chance"]  = on_hit_chance
	d["on_hit_duration"] = on_hit_duration
	# Show the gun name in the skill slot so the player always knows what's loaded.
	if gun_name != "":
		d["name"] = gun_name
	return d
