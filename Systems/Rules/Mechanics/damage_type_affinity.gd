class_name DamageTypeAffinity
extends Mechanic
## Scales incoming damage of one type. 0.5 = resistance, 2.0 = weakness, 0 = immunity.
## Several affinities on one owner multiply together, each rounding down.

@export var damage_type: StringName = &"physical"
@export var multiplier: float = 0.5
## Subtracted after scaling (never below 0).
@export var flat_reduction: int = 0


func on_damage_taken(_owner: StatBlock, event: DamageEvent) -> void:
	if event.damage_type != damage_type:
		return
	var before := event.amount
	event.amount = maxi(0, floori(event.amount * multiplier) - flat_reduction)
	if event.amount < before:
		event.notes.append("resisted")
	elif event.amount > before:
		event.notes.append("vulnerable")
