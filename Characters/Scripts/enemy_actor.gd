extends BattleActor
class_name EnemyActor
## Base actor for data-driven enemies.
##
## Assign SkillData resources (with SkillEffect chains) to the `skills` export.
## The AI loop inherited from BattleActor.enemy_take_turn() will pick skills
## automatically.  Skills with empty `effects` arrays are silently skipped in
## execute_effects() — override use_skill() in a subclass for bespoke behaviour.
##
## Custom enemy scripts should extend EnemyActor (not BattleActor directly)
## so they inherit execute_effects() and the helper methods here.

## Assign SkillData resources in the Inspector (or via CharacterData.skills).
@export var skills : Array[SkillData] = []

# Optional flavour lines per skill key.  Override in subclass.
var chatter_attack  : Array = []
var chatter_special : Array = []
var chatter_support : Array = []
var chatter_hurt    : Array = []
var chatter_low_hp  : Array = []
var chatter_kill    : Array = []
var chatter_die     : Array = []
var chatter_turn_start : Array = []

## Set to true the first time the low-HP line fires, so it only plays once per battle.
var _low_hp_chatter_fired : bool = false


func _ready() -> void:
	super._ready()


# ── Skill API ─────────────────────────────────────────────────────────────────

func get_skills() -> Array:
	# Return Dictionary form so BattleActor.enemy_take_turn() can read keys.
	var out : Array = []
	for sd in skills:
		if sd != null:
			out.append(sd.to_dict())
	return out


func use_skill(skill_name: String, targets: Array, _part: BodyPartData = null) -> void:
	# Try to find the skill by exact name first, then fall back to command_key match.
	var sd : SkillData = _find_skill_by_name(skill_name)
	if sd == null:
		sd = _find_skill_by_key(skill_name)  # skill_name may actually be a key when called directly
	if sd == null or sd.effects.is_empty():
		if not targets.is_empty():
			await take_turn(targets[0])
		else:
			spend_turn()
		return
	# Spend will cost if the skill has one and this enemy has a party_member.
	if sd.will_cost > 0 and party_member != null:
		if not party_member.spend_will(sd.will_cost):
			# Can't afford it — fall back to plain attack.
			if not targets.is_empty():
				await take_turn(targets[0])
			else:
				spend_turn()
			return

	# Chatter
	match sd.command_key:
		"attack":  say_random(chatter_attack)
		"special": say_random(chatter_special)
		"support": say_random(chatter_support)

	await execute_effects(sd, targets)
	emit_signal("turn_finished")


## Execute the SkillEffect chain of a SkillData against a list of targets.
## Each effect resolves its own targets from TargetType, then calls
## ConditionRunner.execute_effect() which handles dice damage and condition application.
func execute_effects(sd: SkillData, hint_targets: Array) -> void:
	for effect in sd.effects:
		if not is_inside_tree():
			return

		if effect.pre_delay > 0.0:
			await get_tree().create_timer(effect.pre_delay).timeout

		# Resolve target list from TargetType
		var resolved : Array = _resolve_targets(effect.target, hint_targets)

		# Animation — play before damage if there are targets
		if effect.num_dice > 0 and not resolved.is_empty():
			# Use the first hint target for the animation anchor
			var anim_target : BattleActor = resolved[0]
			await play_attack_animation(anim_target, 1.0, 1.0, 0)
			# Damage + conditions applied synchronously by execute_effect
			ConditionRunner.execute_effect(effect, self, resolved)
		else:
			# Pure condition delivery (no dice roll), no animation
			ConditionRunner.execute_effect(effect, self, resolved)

		if effect.post_delay > 0.0:
			await get_tree().create_timer(effect.post_delay).timeout


## Translate TargetType to a concrete list of BattleActors.
func _resolve_targets(target_type: SkillEffect.TargetType,
		hint_targets: Array) -> Array:
	match target_type:
		SkillEffect.TargetType.SELF:
			return [self]
		SkillEffect.TargetType.ALL_OPPONENTS:
			return get_opponents()
		SkillEffect.TargetType.ALL_ALLIES:
			return get_allies()
		SkillEffect.TargetType.ALL:
			return get_opponents() + get_allies() + [self]
		SkillEffect.TargetType.RANDOM_OPPONENT:
			var ops := get_opponents()
			return [ops[randi() % ops.size()]] if not ops.is_empty() else []
		SkillEffect.TargetType.RANDOM_ALLY:
			var als := get_allies()
			return [als[randi() % als.size()]] if not als.is_empty() else []
		_: # TargetType.TARGET — use whatever the caller passed in
			return hint_targets.filter(func(t): return is_instance_valid(t) and t.is_alive())


# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_skill_by_key(command_key: String) -> SkillData:
	for sd in skills:
		if sd != null and sd.command_key == command_key:
			return sd
	return null

func _find_skill_by_name(sname: String) -> SkillData:
	for sd in skills:
		if sd != null and sd.skill_name == sname:
			return sd
	return null


func take_damage(amount: int, attacker: BattleActor = null) -> void:
	super.take_damage(amount, attacker)
	if is_alive():
		# Low-HP chatter fires once, the first time HP reaches or drops below 50%.
		if not _low_hp_chatter_fired and float(hp) / float(max_hp) <= 0.5:
			_low_hp_chatter_fired = true
			say_random(chatter_low_hp)
		else:
			say_random(chatter_hurt)

func say_kill() -> void:
	say_random(chatter_kill)

func say_die() -> void:
	say_random(chatter_die)

func say_turn_start() -> void:
	say_random(chatter_turn_start)
