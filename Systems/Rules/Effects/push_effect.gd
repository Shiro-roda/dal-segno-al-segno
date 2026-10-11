class_name PushEffect
extends EffectDef
## Repel's push and stop. Records the request on the target; combat movement code must read it.

@export var distance_m: float = 10.0
@export var stop_turns: int = 1


func _init() -> void:
	kind = Kind.CUSTOM


func apply_custom(_engine: RulesEngine, _user: StatBlock, victim: StatBlock, _ctx: Dictionary) -> void:
	victim.flags[&"push_m"] = distance_m
	victim.flags[&"stopped_turns"] = stop_turns
	# Add a log event (e.g. &"pushed") to LogText and call engine._log(ctx["result"], ...) here.
