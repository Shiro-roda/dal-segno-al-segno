extends Node3D
class_name BattleActor

signal turn_finished
signal died
signal hp_changed
signal status_applied(effect_id: String)
signal battle_log(message: String)  # general battle narration
signal chatter(message: String, speaker: String)  # character voice line
signal skill_announced(actor: BattleActor, skill_name: String, skill_summary: String)  # fired before an enemy uses a skill

# --- Status effect IDs ---
const STATUS_FROZEN   = "frozen"   # tempo stops accumulating
const STATUS_SLOW     = "slow"     # tempo accumulates at reduced rate
const STATUS_BLEEDING = "bleeding" # takes damage each turn
const STATUS_LEECHED  = "leeched"  # heals attacker on hit
const STATUS_DODGING  = "dodging"  # chance to dodge incoming attacks
const STATUS_SHIELD   = "shield"   # has temporary HP buffer
const STATUS_COVERED  = "covered"  # damage redirected to another actor
const STATUS_LIFESTEAL = "lifesteal"
const STATUS_MALICE = "malice"
const STATUS_MARTYR = "martyr"




const DODGE_CHANCE          = 0.5
const STRUGGLE_MISS_CHANCE  = 0.35
const STRUGGLE_SELF_CHANCE  = 0.25
const SLOW_TEMPO_MULT       = 0.4  # slowed actors gain 40% of normal tempo
const LIFESTEAL_RATIO = 0.5
const WITHER_DRAIN_CHANCE = 0.6


# --- Actor-level FSM ---
const STATE_IDLE   = "Idle"
const STATE_ACTIVE = "Active"
const STATE_ACTING = "Acting"
const STATE_DEAD   = "Dead"
const STATE_FROZEN = "Frozen"

signal actor_state_changed(new_state: String)

var _actor_states : Dictionary = {}
var _current_actor_state : BattleActorState = null
var current_actor_state_name : String = ""

func _init_actor_states() -> void:
	_actor_states = {
		STATE_IDLE:   BattleActorStateIdle.new(),
		STATE_ACTIVE: BattleActorStateActive.new(),
		STATE_ACTING: BattleActorStateActing.new(),
		STATE_DEAD:   BattleActorStateDead.new(),
		STATE_FROZEN: BattleActorStateFrozen.new(),
	}

func set_actor_state(state_name: String) -> void:
	if _current_actor_state != null:
		_current_actor_state.exit()
	_current_actor_state = _actor_states[state_name]
	current_actor_state_name = state_name
	_current_actor_state.enter(self)
	emit_signal("actor_state_changed", state_name)

## Returns true when this actor is a valid target for incoming actions.
## Dead actors and actors mid-animation are excluded.
func can_be_targeted() -> bool:
	return current_actor_state_name in [STATE_IDLE, STATE_ACTIVE, STATE_FROZEN]

# Active effects: Array of {id, duration} dictionaries
var active_effects : Array = []

enum Team { PLAYER, ENEMY }
@export var team : Team

@export var max_hp : int = 10
@export var attack_power : int = 3
## Locked at battle-start value — never modified directly.
## All buffs/debuffs go through attack_modifier instead.
var base_attack_power : int = 0
## Flat modifier applied on top of base. Capped to [-base+1, +base].
var attack_modifier : int = 0

@export var flat_defense : int = 0
var base_flat_defense : int = 0
var flat_modifier : int = 0

@export var tempo_stat : int = 10    # base tempo gained per turn
@export var body_parts : Array[BodyPartData]
## NodePaths (relative to actor root) used to compute the screen-space AABB
## for the AR-style detection box. Populated automatically in _ready() from
## PartAnchors children if left empty.
@export var aabb_anchors : Array[NodePath] = []
var party_member : PartyMemberData
var run_state : RunState
## The CharacterData resource this actor was spawned from. Set by BattleManager
## for enemy actors so bestiary registration doesn't rely on name matching.
var character_data : CharacterData = null
@onready var camera_anchor: Node3D = $CameraAnchor



var perishing := false
var hp : int
## Set to true by Augur — reveals SHARP, FLAT, status lines in the reticle
## and makes the blood globe and will ring visible.
var stats_revealed : bool = false

## Project all aabb_anchors through cam and return a padded screen Rect2.
## Returns Rect2(-9999,-9999,0,0) if projection fails.
func get_screen_rect(cam: Camera3D, vp_offset_x: float) -> Rect2:
	if cam == null or aabb_anchors.is_empty():
		return Rect2(-9999, -9999, 0, 0)
	var min_x : float =  INF
	var max_x : float = -INF
	var min_y : float =  INF
	var max_y : float = -INF
	for np in aabb_anchors:
		var node : Node3D = get_node_or_null(np) as Node3D
		if not is_instance_valid(node):
			continue
		var sp : Vector2 = cam.unproject_position(node.global_position)
		sp.x += vp_offset_x
		min_x = min(min_x, sp.x)
		max_x = max(max_x, sp.x)
		min_y = min(min_y, sp.y)
		max_y = max(max_y, sp.y)
	if min_x == INF:
		return Rect2(-9999, -9999, 0, 0)
	var w : float = max(max_x - min_x, 24.0)
	var h : float = max(max_y - min_y, 24.0)
	var pad_x : float = w * 0.15
	var pad_y : float = h * 0.15
	return Rect2(min_x - pad_x, min_y - pad_y, w + pad_x * 2.0, h + pad_y * 2.0)


func reveal_stats() -> void:
	stats_revealed = true
	# Find all display nodes under WorldSpacePanel and show them
	var panel : Node = get_node_or_null("WorldSpacePanel")
	if is_instance_valid(panel):
		panel.visible = true
		for child in panel.get_children():
			child.visible = true
## Human-readable name shown in the HUD panel. Set from CharacterData.display_name.
## Not the same as node.name which Godot sanitises (spaces → underscores).
var display_name : String = ""
## Short name used in battle log lines. Falls back to display_name.
var log_name : String = ""
var theme_col : Color

func get_log_name() -> String:
	return log_name if log_name != "" else display_name if display_name != "" else name

var broken_parts_mask : int = 0   # bits set as parts are broken
var tempo_pool : float = 0.0          # accumulated tempo
var tempo_bonus : float = 0.0         # temporary flat bonus (e.g. from Evade/Augur)
var cover_source : BattleActor = null # actor absorbing damage on our behalf
var shield_hp : int = 0               # temporary HP from Shelter
var malice_source : BattleActor = null
var martyr_bonus_damage : int = 0
var martyr_tempo_bonus : float = 0.0



## Effective Sharp value used for all damage calculations.
## Always at least 1.
func effective_attack() -> int:
	return max(1, base_attack_power + attack_modifier)


## Apply a Sharp buff (positive) or debuff (negative).
## Caps so the actor can't exceed double base or drop below 1.
func modify_attack(delta: int) -> void:
	var cap_high : int =  base_attack_power
	var cap_low  : int = -(base_attack_power - 1)
	attack_modifier = clampi(attack_modifier + delta, cap_low, cap_high)
	attack_power = effective_attack()


## Effective Flat defense value. Always >= 0.
func effective_flat() -> int:
	return max(0, base_flat_defense + flat_modifier)


## Apply a Flat buff (positive) or debuff (negative).
## Capped at +100% of base; cannot go below 0.
func modify_flat(delta: int) -> void:
	var cap_high : int = base_flat_defense
	var cap_low  : int = -base_flat_defense
	flat_modifier = clampi(flat_modifier + delta, cap_low, cap_high)
	flat_defense  = effective_flat()


func _ready():
	base_attack_power = attack_power
	base_flat_defense = flat_defense
	add_to_group("battle_actor")
	_init_actor_states()
	set_actor_state(STATE_IDLE)
	# Deep-duplicate body_parts so runtime state (is_broken, current_part_hp, etc.)
	# doesn't bleed between battles that share the same .tres resource.
	var fresh : Array[BodyPartData] = []
	for part in body_parts:
		fresh.append(part.duplicate_for_battle())
	body_parts = fresh
	var panel = find_child("WorldSpacePanel", true, false)
	if panel and panel.has_method("setup"):
		panel.setup(self)
	# Auto-populate aabb_anchors from PartAnchors children if not set in Inspector.
	if aabb_anchors.is_empty():
		var ba := get_node_or_null("BoundAnchors")
		if ba:
			for child in ba.get_children():
				aabb_anchors.append(get_path_to(child))


func take_turn(target: BattleActor, part: BodyPartData = null) -> void:
	await get_tree().create_timer(0.1).timeout
	if not is_inside_tree():
		return
	set_actor_state(STATE_ACTING)
	tick_status_effects()
	# Encasement breaks the moment the actor takes a turn.
	active_effects = active_effects.filter(func(e): return e["id"] != "encased")
	if not is_alive() or not is_inside_tree():
		emit_signal("turn_finished")
		return
	if not is_instance_valid(target) or not target.is_alive():
		# Target already dead; skip attack, still end turn
		emit_signal("turn_finished")
		return
	if has_status(STATUS_FROZEN):
		log_msg("%s is frozen and cannot act." % get_log_name())
		spend_turn()
		return
	# All player attacks target a body part; enemies call with part = null
	if part != null:
		await attack_part(target, part)
	else:
		await attack(target)
	
	


func spend_turn():
	if current_actor_state_name != STATE_DEAD:
		set_actor_state(STATE_IDLE)
	emit_signal("turn_finished")


func attack(target: BattleActor) -> void:
	await play_attack_animation(target, attack_power, 2.0, attack_power)



	emit_signal("turn_finished")


func attack_part(target: BattleActor, part: BodyPartData) -> void:
	var damage := int(attack_power * part.damage_multiplier)
	if part.is_cognitohazard:
		perishing = true
	await play_attack_animation(target, 2.0, damage, damage)
	# Tick part HP separately with flat (un-multiplied) damage
	if part.has_part_hp():
		var broke : bool = part.take_part_damage(attack_power)
		if broke:
			target._on_part_broken(part)
	emit_signal("turn_finished")



func take_damage(amount: int, attacker: BattleActor = null) -> void:
	if has_status("encased"):
		amount = int(amount * 0.6)
	if has_status(STATUS_DODGING) and randf() < DODGE_CHANCE:
		log_msg("%s dodges!" % get_log_name())
		return
	# Cover redirect: another actor is absorbing damage for us
	if cover_source != null and cover_source.is_alive() and cover_source != attacker:
		amount *= 0.65
		if cover_source != self:
			cover_source.take_damage(int(amount), attacker)  # 15% reduction
			cover_source.party_member.will += int(amount)
			log_msg("Hue takes the blow for %s." % [get_log_name()])
			return
	# Shield: absorb with temporary HP first
	if shield_hp > 0:
		if amount <= shield_hp:
			shield_hp -= amount
			if shield_hp == 0:
				active_effects = active_effects.filter(func(e): return e["id"] != STATUS_SHIELD)
			emit_signal("hp_changed")
			return
		else:
			amount -= shield_hp
			shield_hp = 0
			active_effects = active_effects.filter(func(e): return e["id"] != STATUS_SHIELD)
	# Flat defense: damage = Sharp² / (Sharp + Flat). Always at least 1.
	var flat : int = effective_flat()
	if flat > 0:
		amount = max(1, int(float(amount * amount) / float(amount + flat)))
	hp -= amount
	emit_signal("hp_changed")
	log_msg("%s takes %d damage." % [get_log_name(), amount])
	_spawn_damage_number(amount, attacker)
		# Martyr pain conversion
	if has_status(STATUS_MARTYR):
		var stored = int(amount * 0.5)
		martyr_bonus_damage += stored
		log_msg("%s drinks deeply from the cup of wrath. (+%d stored damage)" % [get_log_name(), stored])
		# Malice counter
	if has_status(STATUS_MALICE) and attacker != null and is_alive():
		var counter_damage = max(1, attack_power)
		log_msg("%s returns the blow." % get_log_name())
		
		await get_tree().create_timer(0.15).timeout
		await play_attack_animation(attacker, 1.0, 1.0, counter_damage)

		# Reward Vritra
		if malice_source != null and malice_source.party_member:
			var will_gain = max(1, int(counter_damage * 0.5))
			malice_source.party_member.restore_will(will_gain)

			malice_source.log_msg(
				"%s feeds on the spite — restores %d AP."
				% [malice_source.get_log_name(), will_gain]
			)


	# Lifesteal: if the attacker has STATUS_LIFESTEAL, they heal on every hit
	# regardless of which function triggered take_damage.
	if attacker != null and is_instance_valid(attacker) and attacker.has_status(STATUS_LIFESTEAL):
		var heal: int = max(1, int(amount * LIFESTEAL_RATIO))
		attacker.hp = min(attacker.hp + heal, attacker.max_hp)
		attacker.emit_signal("hp_changed")
		log_msg("%s drinks %d CORP from the wound." % [attacker.get_log_name(), heal])
		if attacker.has_status(STATUS_MARTYR):
			attacker.martyr_bonus_damage = max(0, attacker.martyr_bonus_damage - heal)
			attacker.log_msg("The cup passes from %s. (-%d damage)" % [attacker.get_log_name(), heal])

	if hp <= 0:
		hp = 0
		set_actor_state(STATE_DEAD)
		log_msg("%s has fallen." % get_log_name())
		say_die()
		emit_signal("died", self)
		# Do NOT queue_free here — manager handles cleanup in _on_actor_died
		# so that any in-progress coroutines don't access freed nodes

func is_alive() -> bool:
	return hp > 0

func get_visible_parts(current_mask: int) -> Array[BodyPartData]:
	var visible : Array[BodyPartData] = []
	# Combine the global lens mask with locally broken parts
	var full_mask := current_mask | broken_parts_mask
	for part in body_parts:
		if part.is_broken:
			continue  # broken parts are gone from the target list
		if part.base_visible:
			visible.append(part)
			continue
		if (full_mask & part.required_removed_mask) == part.required_removed_mask:
			visible.append(part)
	return visible

func update_shader_visibility(mask: int):
	pass


# --- Log / chatter helpers ---

func log_msg(msg: String) -> void:
	emit_signal("battle_log", msg)

func say(msg: String) -> void:
	emit_signal("chatter", msg, self.name)

func say_random(lines: Array) -> void:
	if lines.is_empty(): return
	say(lines[randi() % lines.size()])

## Override in subclasses to speak a kill line after defeating a target.
func say_kill() -> void:
	pass

## Override in subclasses to speak a death line when this actor is defeated.
func say_die() -> void:
	pass


# --- Status effect helpers ---

func apply_status(effect_id: String, duration: int) -> void:
	# Refresh duration if already present, otherwise add
	for effect in active_effects:
		if effect["id"] == effect_id:
			effect["duration"] = max(effect["duration"], duration)
			return
	active_effects.append({"id": effect_id, "duration": duration})
	emit_signal("status_applied", effect_id)
	if _current_actor_state != null:
		_current_actor_state.on_status_changed()

## Apply a timed flat/sharp modifier. delta > 0 = buff, < 0 = debuff.
## Stored in active_effects as {id, duration, stat, delta} for tick reversion.
func apply_stat_change(stat: String, delta: int, duration: int) -> void:
	if delta == 0:
		return
	# Stack additively; each application is a separate entry so each expires independently.
	var entry := {"id": "_stat_change", "duration": duration, "stat": stat, "delta": delta}
	active_effects.append(entry)
	match stat:
		"flat":  modify_flat(delta)
		"sharp": modify_attack(delta)
	var sign_str : String = "+" if delta > 0 else ""
	log_msg("%s%d %s for %d turns." % [sign_str, delta, stat.to_upper(), duration])
	emit_signal("status_applied", "_stat_change")

func has_status(effect_id: String) -> bool:
	return active_effects.any(func(e): return e["id"] == effect_id)

func tick_status_effects() -> void:
	var to_remove := []
	for effect in active_effects:
		# "encased" has no duration -- it persists until cleared by take_turn.
		if effect["id"] == "encased":
			continue
		match effect["id"]:
			STATUS_BLEEDING:
				var bleed_dmg = max(1, max_hp / 10)
				take_damage(bleed_dmg)
		effect["duration"] -= 1
		if effect["duration"] <= 0:
			to_remove.append(effect)
	for e in to_remove:
		active_effects.erase(e)
		# Revert timed stat changes on expiry
		if e.get("id") == "_stat_change":
			match e.get("stat", ""):
				"flat":  modify_flat(-int(e.get("delta", 0)))
				"sharp": modify_attack(-int(e.get("delta", 0)))
	# Clear cover reference if STATUS_COVERED expired
	if not has_status(STATUS_COVERED):
		cover_source = null
	if not has_status(STATUS_MALICE):
		malice_source = null
	# Notify FSM that statuses may have changed (e.g. frozen expired)
	if _current_actor_state != null:
		_current_actor_state.on_status_changed()


# Called each round by battle_manager before picking the next actor.
# Adds tempo based on stat, modified by slow/freeze.
func tick_tempo() -> void:
	if has_status(STATUS_FROZEN):
		return  # no tempo gain while frozen
	var gain : float = float(tempo_stat)
	if has_status(STATUS_SLOW):
		gain *= SLOW_TEMPO_MULT
	# Small jitter breaks ties between equal-stat actors without distorting the scale.
	# Full gain is deterministic; randf_range adds at most +/-5% of one stat point.
	var martyr_bonus := 0.0

	if has_status(STATUS_MARTYR):
		martyr_bonus = martyr_tempo_bonus

	tempo_pool += gain + randf_range(-0.5, 0.5) + tempo_bonus + martyr_bonus


func reset_tempo_bonus() -> void:
	tempo_bonus = 0.0

# Called when this actor strikes a leeched target. Override for character-specific behaviour.
func on_leech_proc(_heal_amount: int) -> void:
	pass

## Returns true if struggle skills that restore will/AP should give their bonus.
## Allowed in all phases EXCEPT Al Segno transits (DS_AL_SEGNO, AL_FINE),
## where resource attrition is the challenge.
func struggle_restores_will() -> bool:
	var dr : DungeonRunState = GameController.current_dungeon_run
	if dr == null:
		return true   # outside a dungeon run (test battles etc.) — always allow
	return not dr.is_battle_reprimed_transit()

# --- Skill system ---

# Override in subclasses to return this character's available skills.
# Returns Array of SkillData. battle_manager calls this to build UI buttons.
func get_skills() -> Array:
	return []

# Dispatch a skill by command key. Override or extend in subclasses.
func use_skill(command_key: String, targets: Array, part: BodyPartData = null) -> void:
	spend_turn()

# AI turn entry point for enemies that have skills (e.g. boss enemies).
# Consults get_skills(), picks an action, and executes it.
# Falls back to take_turn(target) if no skills are available.
func enemy_take_turn(target: BattleActor) -> void:
	# Tick statuses at the start of the turn (mirrors take_turn).
	# take_turn() also calls this, so it's covered on the no-skills fallback path.
	var skills := get_skills()
	if skills.is_empty():
		await take_turn(target)
		return
	# Skills path: tick here since use_skill() won't.
	await get_tree().create_timer(0.1).timeout
	if not is_inside_tree():
		return
	set_actor_state(STATE_ACTING)
	tick_status_effects()
	active_effects = active_effects.filter(func(e): return e["id"] != "encased")
	if not is_alive() or not is_inside_tree():
		emit_signal("turn_finished")
		return
	if has_status(STATUS_FROZEN):
		log_msg("%s is frozen and cannot act." % get_log_name())
		spend_turn()
		return

	var opponents : Array = get_opponents()
	var allies    : Array = get_allies()

	var attacks  : Array = skills.filter(func(s): return s.get("key") == "attack")
	var specials : Array = skills.filter(func(s): return s.get("key") == "special")
	# Only include ally-support skills when there are living allies to use them on
	var supports : Array = skills.filter(func(s):
		if s.get("key") != "support": return false
		if s.get("ally_target", false): return not allies.is_empty()
		return true
	)

	# Build a weighted pool using per-skill ai_weight (falls back to key-based defaults)
	var pool := []
	for s in attacks:  pool.append({"skill": s, "weight": s.get("ai_weight", 3)})
	for s in specials: pool.append({"skill": s, "weight": s.get("ai_weight", 1)})
	for s in supports: pool.append({"skill": s, "weight": s.get("ai_weight", 2)})

	if pool.is_empty():
		await take_turn(target)
		return

	# Weighted random pick
	var total := 0
	for entry in pool: total += entry["weight"]
	var roll := randi() % total
	var chosen_skill : Dictionary = pool[0]["skill"]
	var acc := 0
	for entry in pool:
		acc += entry["weight"]
		if roll < acc:
			chosen_skill = entry["skill"]
			break

	var skill_name : String = chosen_skill.get("name", "")
	var key        : String = chosen_skill.get("key", "attack")
	var summary    : String = chosen_skill.get("summary", "")
	var is_aoe     : bool   = chosen_skill.get("aoe", false)
	var is_ally_t  : bool   = chosen_skill.get("ally_target", false)
	var is_enemy_t : bool   = chosen_skill.get("enemy_target", false)
	var is_struggle: bool   = chosen_skill.get("struggle", false)

	# "attack" key on non-data-driven enemies falls back to the base attack.
	# EnemyActor overrides use_skill and handles attack keys via execute_effects.
	if key == "attack" or is_struggle:
		if not (self is EnemyActor):
			await take_turn(target)
			return

	# Announce the skill before resolving targets
	emit_signal("skill_announced", self, skill_name if skill_name != "" else key, summary)
	await get_tree().create_timer(0.6).timeout

	# Determine targets for the chosen skill
	var skill_targets : Array = []
	if is_ally_t:
		# Support skill targeting an ally — pick the ally with the lowest HP ratio
		if allies.is_empty():
			await take_turn(target)
			return
		var neediest : BattleActor = allies[0]
		for a in allies:
			if float(a.hp) / float(a.max_hp) < float(neediest.hp) / float(neediest.max_hp):
				neediest = a
		skill_targets = [neediest]
	elif is_aoe:
		skill_targets = opponents
		var _mgr = get_tree().get_first_node_in_group("battle_manager")
		if _mgr:
			_mgr.focus_active_overview()
	elif is_enemy_t:
		if not opponents.is_empty():
			skill_targets = [opponents[randi() % opponents.size()]]
		else:
			await take_turn(target)
			return
	else:
		if not opponents.is_empty():
			skill_targets = [opponents[randi() % opponents.size()]]
		else:
			await take_turn(target)
			return

	await use_skill(skill_name if skill_name != "" else key, skill_targets)

# Returns all living actors on the opposing team.
func get_opponents() -> Array:
	var manager = get_tree().get_first_node_in_group("battle_manager")
	if manager == null: return []
	return manager.actors.filter(func(a): return a.team != team and a.is_alive())

# Returns all living actors on the same team (excluding self).
func get_allies() -> Array:
	var manager = get_tree().get_first_node_in_group("battle_manager")
	if manager == null: return []
	return manager.actors.filter(func(a): return a.team == team and a.is_alive() and a != self)

# Convenience: pick a random living enemy/ally from a list
func random_living(actors: Array) -> BattleActor:
	var alive = actors.filter(func(a): return a.is_alive() and a != self)
	if alive.is_empty(): return null
	return alive[randi() % alive.size()]

# Struggle attack: random target, chance to miss, no status, chance of self-damage
func struggle_attack(all_actors: Array, base_damage: int) -> void:
	var enemies = all_actors.filter(func(a): return a.team != team and a.is_alive())
	if enemies.is_empty():
		spend_turn()
		return
	var target = enemies[randi() % enemies.size()]
	if randf() < STRUGGLE_MISS_CHANCE:
		log_msg("%s lacked the will to strike true." % get_log_name())
		spend_turn()
		return
	# Randomly hit a visible body part if one exists, otherwise hit the actor directly
	var manager = get_tree().get_first_node_in_group("battle_manager")
	var visible_parts = target.get_visible_parts(manager.removed_channels if manager else 0)
	var hit_part: bool = not visible_parts.is_empty()
	if hit_part:
		var part = visible_parts[randi() % visible_parts.size()]
		log_msg("%s found the will to strike %s's %s." % [get_log_name(), target.get_log_name(), part.part_name])
		await play_attack_animation(target, 1.0, 1.0, int((base_damage) * part.damage_multiplier))
		if part.is_cognitohazard:
			perishing = true
	else:
		await play_attack_animation(target, 1.0, 1.0, base_damage)
	if randf() < STRUGGLE_SELF_CHANCE:
		var self_dmg = max(1, base_damage / 4)
		log_msg("%s struggles in vain." % get_log_name())
		take_damage(self_dmg)
	emit_signal("turn_finished")

func use_lens(channel: int):
	# Ask manager to apply lens effect
	var manager = get_tree().get_first_node_in_group("battle_manager")
	print("Lens added: ", channel)
	manager.apply_lens(channel)
	spend_turn()

func play_attack_animation(target: BattleActor, player_mult, enemy_mult, damage : int = 0) -> void:
	
	var manager = get_tree().get_first_node_in_group("battle_manager")
	if manager == null:
		return
	manager.active_cam.follow_damping = false
	manager.target_cam.follow_damping = false
	

	var original_pos = global_position
	var direction = (target.global_position - global_position).normalized()
	
	var windup_pos = original_pos - direction * 0.1
	var lunge_pos = (original_pos + direction * 0.5) - windup_pos
	
	var windup_tween := create_tween()
	windup_tween.set_trans(Tween.TRANS_QUAD)
	windup_tween.set_ease(Tween.EASE_IN_OUT)

	windup_tween.tween_property(self, "global_position", windup_pos, 0.3)
	await windup_tween.finished

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT_IN)
	

	tween.tween_property(self, "global_position", lunge_pos, 0.22)
	await tween.finished
	
	# IMPACT MOMENT
	var impact_dir = (global_position - target.global_position).normalized()
	
	
	
	
	manager.screen_shake(self, target, impact_dir, player_mult, enemy_mult)


	if is_instance_valid(target) and is_inside_tree():
		if target.is_alive():
			
			var final_damage = damage

			if has_status(STATUS_MARTYR) and martyr_bonus_damage > 0:

				

				final_damage += martyr_bonus_damage

				martyr_bonus_damage = 0

			# Lifesteal buff (Vice)
			if has_status(STATUS_LIFESTEAL):
				target.take_damage(damage * (1 - LIFESTEAL_RATIO), self)
				if not target.is_alive():
					say_kill()
				var heal = max(1, int(damage * LIFESTEAL_RATIO))
				hp = min(hp + heal, max_hp)
				log_msg("%s drinks %d CORP from the wound." % [get_log_name(), heal])
				if has_status(STATUS_MARTYR):
					martyr_bonus_damage = max(0, martyr_bonus_damage - heal)
					log_msg("The cup passes from Indra. (-%d damage)" % [heal])
				emit_signal("hp_changed")

				
			else:
				if has_status(STATUS_MARTYR) and martyr_bonus_damage > 0:
					log_msg("%s pours out the cup of wrath. (+%d damage)" % [get_log_name(), martyr_bonus_damage])
				target.take_damage(final_damage, self)
				if not target.is_alive():
					say_kill()
	

	
	var back_tween = create_tween()
	back_tween.set_trans(Tween.TRANS_QUAD)
	back_tween.set_ease(Tween.EASE_IN_OUT)

	back_tween.tween_property(self, "global_position", original_pos, 0.3)
	await back_tween.finished

	# Guard: target or self may have been freed if battle ended mid-animation
	if not is_instance_valid(target) or not is_inside_tree():
		return
	if perishing and is_inside_tree():
		print("You saw something you shouldn't have.")
		emit_signal("turn_finished")
		if damage >= hp:
			log_msg("%s understood the price all too well." % [get_log_name()])
		else:
			log_msg("%s underestimated the price of understanding." % [get_log_name()])
		take_damage(damage)
		perishing = false

	if is_inside_tree():
		await get_tree().create_timer(1.0).timeout


## Returns the follow anchor for this actor for the given camera role.
## role: "active" (left cam, tracking the acting character)
##        "target" (right cam, tracking the targeted character)
## Looks for CameraAnchors/Follow{Role} first; falls back to CameraAnchor then self.
func get_follow_anchor(role: String = "active") -> Node3D:
	var ca_group := get_node_or_null("CameraAnchors")
	if ca_group is Node3D:
		var child_name := "Follow" + role.capitalize()
		var child := ca_group.get_node_or_null(child_name)
		if child is Node3D:
			return child as Node3D
	var ca := get_node_or_null("CameraAnchor")
	if ca is Node3D:
		return ca as Node3D
	return self


## Returns the look-at anchor for this actor for the given camera role.
## Same role conventions as get_follow_anchor.
func get_look_anchor(role: String = "active") -> Node3D:
	var ca_group := get_node_or_null("CameraAnchors")
	if ca_group is Node3D:
		var child_name := "Look" + role.capitalize()
		var child := ca_group.get_node_or_null(child_name)
		if child is Node3D:
			return child as Node3D
	var ca := get_node_or_null("CameraAnchor")
	if ca is Node3D:
		return ca as Node3D
	return self


## Returns the world-space Node3D anchor for a skill's origin reticle.
## Reads anchor_path from the skill Dictionary produced by SkillData.to_dict().
## Falls back to CameraAnchor then self.
func get_skill_anchor(skill: Dictionary) -> Node3D:
	var path = skill.get("anchor_path", NodePath(""))
	if path is NodePath and not (path as NodePath).is_empty():
		var n := get_node_or_null(path as NodePath)
		if n is Node3D:
			return n as Node3D
	var ca := get_node_or_null("CameraAnchor")
	if ca is Node3D:
		return ca as Node3D
	return self


## Returns the world-space Node3D anchor for a body part's reticle.
## Resolves part.anchor_path relative to self; falls back to CameraAnchor,
## then self. Swap the target node for a BoneAttachment3D child at any time.
func get_part_anchor(part: BodyPartData) -> Node3D:
	if part != null and not part.anchor_path.is_empty():
		var n := get_node_or_null(part.anchor_path)
		if n is Node3D:
			return n as Node3D
	# Fallback: CameraAnchor sits at a sensible mid-body height
	var ca := get_node_or_null("CameraAnchor")
	if ca is Node3D:
		return ca as Node3D
	return self


func _on_part_broken(part: BodyPartData) -> void:
	log_msg("%s's %s dissolves." % [get_log_name(), part.part_name])
	if part.break_mask_bit > 0:
		broken_parts_mask |= part.break_mask_bit
	if not part.on_break_status.is_empty():
		apply_status(part.on_break_status, part.on_break_duration)
		log_msg("%s is %s." % [get_log_name(), part.on_break_status])
	if part.on_break_sharp_delta != 0:
		modify_attack(part.on_break_sharp_delta)
		var word := "ascends" if part.on_break_sharp_delta > 0 else "dims"
		log_msg("%s's SHARP %s." % [get_log_name(), word])
	if part.on_break_flat_delta != 0:
		modify_flat(part.on_break_flat_delta)
		var word := "ascends" if part.on_break_flat_delta > 0 else "dims"
		log_msg("%s's FLAT %s." % [get_log_name(), word])
	emit_signal("hp_changed")  # refresh HUD


func _spawn_damage_number(amount: int, attacker: BattleActor = null) -> void:
	if not is_inside_tree():
		return
	var scene_root := get_tree().get_first_node_in_group("battle_scene")
	if scene_root == null:
		return
	var script := load("res://UI/3D/BattleDisplay/Scripts/damage_number.gd")
	if script == null:
		return
	var attacker_pos := attacker.global_position if is_instance_valid(attacker) else global_position
	var dn : Node3D = script.new()
	scene_root.add_child(dn)
	dn._start(global_position, amount, int(team), attacker_pos)
