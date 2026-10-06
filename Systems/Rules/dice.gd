class_name Dice
extends RefCounted
## Dice helpers. Expressions look like "2d6+3", "d8", "1d4-1" or "5".


static func roll(sides: int, rng: RandomNumberGenerator = null) -> int:
	if rng == null:
		return randi_range(1, sides)
	return rng.randi_range(1, sides)


## Returns {count, sides, bonus}.
static func parse(expr: String) -> Dictionary:
	var s := expr.strip_edges().to_lower().replace(" ", "")
	var bonus := 0
	var split := maxi(s.rfind("+"), s.rfind("-"))
	var dice_part := s
	if split > 0:
		bonus = s.substr(split).to_int()
		dice_part = s.substr(0, split)
	var count := 0
	var sides := 0
	var d := dice_part.find("d")
	if d == -1:
		bonus += dice_part.to_int()
	else:
		count = 1 if d == 0 else dice_part.substr(0, d).to_int()
		sides = dice_part.substr(d + 1).to_int()
	return {"count": count, "sides": sides, "bonus": bonus}


## Rolls an expression. `dice_multiplier` scales the dice count (for crits).
## Returns {total, rolls, bonus}.
static func roll_expr(expr: String, rng: RandomNumberGenerator = null, dice_multiplier: int = 1) -> Dictionary:
	var p := parse(expr)
	var rolls: Array[int] = []
	var total: int = p["bonus"]
	for _i in int(p["count"]) * dice_multiplier:
		var r := roll(int(p["sides"]), rng)
		rolls.append(r)
		total += r
	return {"total": total, "rolls": rolls, "bonus": p["bonus"]}
