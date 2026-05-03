extends Resource
class_name SkillEffect
## One atomic beat of a skill — who gets hit, with what chance,
## and which conditions land on them.
##
## Damage is no longer expressed here. Conditions carry formulas.
## The dice fields (num_dice, die_size, sharp_ratio) describe the
## damage roll only when this effect is used as a direct attack beat.
## They are read by ConditionRunner.execute_effect() and by the UI
## to render the range string: "(N+bonus)–(N×d+bonus)".

## ── Targeting ────────────────────────────────────────────────────────────────

enum TargetType {
	TARGET,          ## single chosen target (default)
	SELF,            ## the caster
	ALL_OPPONENTS,   ## every living enemy
	ALL_ALLIES,      ## every living ally (excl. self)
	ALL,             ## every living actor
	RANDOM_OPPONENT, ## one random living enemy
	RANDOM_ALLY,     ## one random living ally (excl. self)
}

@export var target : TargetType = TargetType.TARGET

## ── Dice damage ──────────────────────────────────────────────────────────────
## Roll num_dice d die_size, add flat bonus from sharp_ratio × attacker.attack_power.
## Min roll  = num_dice      + int(attack_power × sharp_ratio)
## Max roll  = num_dice×die_size + int(attack_power × sharp_ratio)
##
## Set num_dice = 0 to skip the dice roll entirely (pure condition delivery).

@export var num_dice    : int   = 0    ## number of dice to roll (0 = no roll)
@export var die_size    : int   = 6    ## faces per die (d6 default)
@export var sharp_ratio : float = 0.5  ## fraction of attack_power added as flat bonus

## ── Chance & conditions ───────────────────────────────────────────────────────
## Probability (0.0–1.0) that this entire effect fires. Checked once per beat.
@export var chance : float = 1.0

## Conditions applied to each resolved target when this effect fires.
## Applied via ConditionRunner.apply() after dice damage (if any) is resolved.
@export var conditions : Array[ConditionData] = []

## ── Timing & visuals ─────────────────────────────────────────────────────────
@export var animation_key : String = ""
@export var pre_delay     : float  = 0.0
@export var post_delay    : float  = 0.0


## ── Helpers ───────────────────────────────────────────────────────────────────

## Roll the dice for this effect given the caster's attack_power.
## Returns 0 if num_dice == 0 (no roll).
func roll_damage(attack_power: int) -> int:
	if num_dice <= 0:
		return 0
	var bonus : int = int(float(attack_power) * sharp_ratio)
	var total : int = bonus
	for i in num_dice:
		total += randi_range(1, die_size)
	return total


## Minimum possible damage (all dice show 1).
func min_damage(attack_power: int) -> int:
	if num_dice <= 0:
		return 0
	return num_dice + int(float(attack_power) * sharp_ratio)


## Maximum possible damage (all dice show die_size).
func max_damage(attack_power: int) -> int:
	if num_dice <= 0:
		return 0
	return num_dice * die_size + int(float(attack_power) * sharp_ratio)


## UI display string: "(min)–(max)"  e.g. "4–22"
func damage_range_string(attack_power: int) -> String:
	if num_dice <= 0:
		return ""
	return "%d–%d" % [min_damage(attack_power), max_damage(attack_power)]
