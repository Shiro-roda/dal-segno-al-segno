class_name Mechanic
extends Resource
## A passive rule attached to a feat, item, condition, action, or enemy.
## Override only the hooks you need. `owner` is the StatBlock the mechanic belongs to.

@export var display_name: String = ""
@export_multiline var description: String = ""


## The owner is about to take damage. Edit event.amount, or set event.cancelled.
func on_damage_taken(_owner: StatBlock, _event: DamageEvent) -> void:
	pass

## The owner just dealt damage. event.dealt is final.
func on_damage_dealt(_owner: StatBlock, _event: DamageEvent) -> void:
	pass

## The owner just rolled an attack. May edit roll.success / roll.crit.
func on_attack_rolled(_owner: StatBlock, _action: ActionDef, _roll: RollResult,
		_target: StatBlock) -> void:
	pass

## The feat or item carrying this was just chosen for `sheet` (a level-up or starting pick).
func on_chosen(_sheet: CharacterSheet) -> void:
	pass

## Attacks added to the basic Attack. `secondary` asks about the secondary weapon's attacks.
func extra_attacks(_owner: StatBlock, _secondary: bool) -> int:
	return 0

## True if the owner may hold a weapon in place of armor or a trinket.
func allows_secondary_weapon(_owner: StatBlock) -> bool:
	return false

## Per-owner runtime state. Resources are shared by every holder, so counters live on the owner.
func state(owner: StatBlock) -> Dictionary:
	var key := get_instance_id()
	if not owner.mechanic_state.has(key):
		owner.mechanic_state[key] = {}
	return owner.mechanic_state[key]
