class_name NthShotCrit
extends Mechanic
## Every Nth attack roll the owner makes while this is active hits and crits.
## Counts every attack roll, not just weapon attacks.

@export_range(2, 99) var every: int = 6


func on_attack_rolled(owner: StatBlock, _action: ActionDef, roll: RollResult,
		_target: StatBlock) -> void:
	if roll.kind != RollResult.Kind.ATTACK:
		return
	var s := state(owner)
	var shots := int(s.get("shots", 0)) + 1
	if shots >= every:
		shots = 0
		roll.success = true
		roll.crit = true
		roll.fumble = false
	s["shots"] = shots
