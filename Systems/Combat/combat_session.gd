class_name CombatSession
extends Node
## Real-time-with-pause combat with free movement and positioning.
##
## Every combatant has a gauge that fills over `round_seconds`, faster with a better
## initiative modifier. When it fills they take a turn: tick their conditions, pick
## an action (a queued order, a heal for a wounded ally if they're set to, their
## default action, or an enemy's choice), then wait until the target is in reach,
## walking toward it if need be, and carry it out.
## Pause (the combat_pause action) stops time so orders can be queued.
##
## All rules go through RulesEngine, so this node only decides who acts, when,
## and from where. Combatants with no body count as always in reach.

signal combat_started
signal combat_ended(victory: bool)
signal paused_changed(is_paused: bool)
signal log_line(text: String)
signal action_resolved(actor: Combatant, result: Dictionary)
## Fires for any change to a party member's orders or automatic settings.
signal order_changed(actor: Combatant)
signal target_changed(actor: Combatant)
## Fires when a turn takes the spotlight (Focus view); null when it ends.
signal turn_spotlight_changed(actor: Combatant)

## Seconds for a combatant with no initiative bonus to fill their gauge.
@export var round_seconds: float = 3.0
## Gauge speed gained per point of initiative modifier.
@export var speed_per_initiative: float = 0.05
## Start each fight paused so the player can give first orders.
@export var start_paused: bool = true
## Chance an enemy tries a Canto or special action instead of its basic attack.
@export_range(0.0, 1.0, 0.05) var enemy_special_chance: float = 0.35

@export_group("Positioning")
## Reach, in metres, for single-target Cantos whose ActionDef has no `range`.
@export var spell_range: float = 12.0
## Reach of an unarmed or ordinary melee weapon attack.
@export var default_attack_range: float = 2.2
## Reach of a weapon tagged "ranged" that has no weapon_range of its own.
@export var ranged_attack_range: float = 10.0
## Fraction of the reach a combatant walks up to before stopping.
@export_range(0.5, 1.0, 0.05) var arrive_fraction: float = 0.8
## Extra "distance" a foe counts as having for every ally already aimed at it, when
## picking who to attack. Higher spreads the party across more enemies.
@export var target_spread_penalty: float = 2.5
## A combatant keeps its current target unless another scores this much better,
## so nobody flip-flops between two foes.
@export var target_hysteresis: float = 1.5

@export_group("Spacing")
## The closest allies will stand to each other (metres, centre to centre).
@export var min_spacing: float = 1.3
## The closest anyone will stand to an opponent's centre. Keep this under the shortest
## attack range, or short-reach enemies get shoved out of reach.
@export var foe_spacing: float = 0.7
## How fast overlapping combatants are pushed apart, in metres per second.
@export var separation_speed: float = 4.0
## How hard walking combatants swerve around anyone in their path.
@export_range(0.0, 3.0, 0.1) var avoidance_strength: float = 1.2

@export_group("Unsticking")
## A combatant waiting to act that gets no closer to its target for this long counts as
## stuck: it heads straight for the target and allies make way for it.
@export var stall_seconds: float = 1.5
## Stuck for this long: it also ignores wall-avoidance and walks straight in.
@export var unstick_seconds: float = 3.0
## Print a console line whenever someone is judged stuck.
@export var debug_stalls: bool = false

@export_group("Behaviour")
## HEAL_WOUNDED acts when an ally's Corpus is below this fraction of their maximum.
@export_range(0.1, 1.0, 0.05) var heal_threshold: float = 0.5

@export_group("Turn focus")
## How fast everyone except the acting combatant moves while a turn is in the spotlight.
@export_range(0.02, 1.0, 0.01) var focus_slow_scale: float = 0.12
## How fast the acting combatant moves (1.0 = normal; lower for slow motion).
@export_range(0.1, 1.0, 0.05) var focus_actor_scale: float = 0.75
## Seconds the camera gets to arrive before the actor does anything.
@export var focus_lead_in: float = 0.6
## Seconds to hold on the result after the action lands.
@export var focus_linger: float = 0.9
## Give up on a spotlight after this long (an actor that can't reach its target).
@export var focus_timeout: float = 10.0
@export var focus_enemy_turns: bool = true

@export_group("Feedback")
## A turn isn't over until its feedback (the dice readout, animations) has finished: the
## actor's gauge stays frozen, the Focus spotlight stays put, and the fight can't end
## until then. Turn this off to let turns carry on regardless.
@export var hold_turns_for_feedback: bool = true
## Safety net: a hold that is never released is dropped after this many seconds.
@export var feedback_timeout: float = 15.0

var engine: RulesEngine
var party: Array[Combatant] = []
var enemies: Array[Combatant] = []
var active: bool = false
var paused: bool = false
## Every line logged this fight.
var history: Array[String] = []
var _spot: Combatant
var _spot_age := 0.0
var _spot_linger := 0.0
var _holds: Dictionary = {}  # int -> {"actor": Combatant, "age": float}
var _next_hold := 1
var _ending := false
var _end_victory := false

func _ready() -> void:
	add_to_group("combat_session")


func _process(delta: float) -> void:
	advance(delta)


func _physics_process(delta: float) -> void:
	if active and not paused and not _ending:
		_retarget()
		_step_movement(delta)


func _unhandled_input(event: InputEvent) -> void:
	if active and event.is_action_pressed("combat_pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()


# ----------------------------------------------------------------- flow

## Starts a fight between two groups of StatBlocks. `p_engine` defaults to Rules.engine.
## Optional body arrays line up with the block arrays by index.
func begin(party_blocks: Array, enemy_blocks: Array, p_engine: RulesEngine = null,
		party_bodies: Array = [], enemy_bodies: Array = []) -> void:
	if active:
		return
	engine = p_engine if p_engine != null else Rules.engine
	party.clear()
	enemies.clear()
	history.clear()
	for i in party_blocks.size():
		var c := Combatant.new(party_blocks[i] as StatBlock, Combatant.Side.PARTY)
		c.attack_range = attack_range_for(c.block)
		c.recall()
		if i < party_bodies.size():
			c.body = party_bodies[i] as Node3D
		party.append(c)
	for i in enemy_blocks.size():
		var c := Combatant.new(enemy_blocks[i] as StatBlock, Combatant.Side.ENEMY)
		c.attack_range = attack_range_for(c.block)
		if i < enemy_bodies.size():
			c.body = enemy_bodies[i] as Node3D
		enemies.append(c)
	# A head start for quick combatants: initiative roll spread over the first half-round.
	for c: Combatant in party + enemies:
		c.gauge = clampf(engine.roll_initiative(c.block) / 40.0, 0.0, 0.6)
	for c: Combatant in party:
		c.target = _spread_target(c, enemies)
	for c: Combatant in enemies:
		c.target = _spread_target(c, party)
	active = true
	_set_player_lock(true)
	combat_started.emit()
	say_event(&"combat_begins")
	set_paused(start_paused)


## Moves time forward. Called every frame; tests call it directly.
func advance(delta: float) -> void:
	if not active:
		return
	_tick_holds(delta)
	if _ending:
		# Someone landed the last blow: wait for its feedback to finish, then close the fight.
		if _holds.is_empty():
			_end(_end_victory)
		return
	if paused:
		return
	for c: Combatant in party + enemies:
		if not active:
			return
		if c.is_down():
			c.turn_pending = false
			continue
		if c.turn_pending:
			_try_act(c)
			continue
		# The turn isn't over until its feedback is: no gauge, no new turn.
		if is_holding(c):
			continue
		if c.gauge < 1.0:
			var speed := clampf(1.0 + c.block.initiative_mod() * speed_per_initiative, 0.5, 2.0)
			c.gauge += delta * _time_scale_for(c) / round_seconds * speed
		if c.gauge >= 1.0:
			# A full gauge waits its turn while someone else is in the spotlight.
			if _spot != null and _spot != c:
				c.gauge = 1.0
				continue
			c.gauge -= 1.0
			_begin_turn(c)
	_update_spotlight(delta)


func set_paused(value: bool) -> void:
	if not active:
		return
	paused = value
	paused_changed.emit(paused)


func toggle_pause() -> void:
	set_paused(not paused)


# ------------------------------------------------------------ player orders

## Queues an order for a party member, to be carried out when their gauge fills.
## `level` picks the Canto level (0 = its own); `target` may be null for self/group actions.
## Returns false if it isn't allowed or can't be afforded.
func queue_action(actor: Combatant, action: ActionDef, level: int = 0, target: Combatant = null) -> bool:
	if not active or actor.side != Combatant.Side.PARTY or actor.is_down():
		return false
	if not actor.block.can_cast(action):
		return false
	if actor.block.anima < engine.anima_cost_for(action, level):
		return false
	actor.order = {"action": action, "level": level, "target": target}
	order_changed.emit(actor)
	return true


func clear_order(actor: Combatant) -> void:
	if actor.has_order():
		actor.order = {}
		order_changed.emit(actor)


## Makes `action` what a party member does every turn when nothing is queued. The basic
## attack counts as "no default". Returns false if they can't use it.
func set_default_action(actor: Combatant, action: ActionDef, level: int = 0) -> bool:
	if actor.side != Combatant.Side.PARTY or actor.is_down() or not actor.block.can_cast(action):
		return false
	if action == engine.config.get_basic_attack():
		clear_default_action(actor)
		return true
	actor.default_action = action
	actor.default_level = action.resolve_level(level)
	actor.remember()
	order_changed.emit(actor)
	return true


## Back to the basic attack.
func clear_default_action(actor: Combatant) -> void:
	if actor.default_action == null:
		return
	actor.default_action = null
	actor.default_level = 0
	actor.remember()
	order_changed.emit(actor)


## Sets a party member's automatic behaviour (a Combatant.Behavior). Ignored if they
## can't do it, such as HEAL_WOUNDED with nothing that heals.
func set_behavior(actor: Combatant, new_behavior: int) -> void:
	if actor.side != Combatant.Side.PARTY or not behaviors_for(actor).has(new_behavior):
		return
	actor.behavior = new_behavior as Combatant.Behavior
	actor.remember()
	order_changed.emit(actor)


## The behaviours `actor` can use, in cycling order. Attack is always there.
func behaviors_for(actor: Combatant) -> Array[int]:
	var out: Array[int] = [Combatant.Behavior.ATTACK]
	if can_heal(actor):
		out.append(Combatant.Behavior.HEAL_WOUNDED)
	return out


## True if `actor` knows something that heals themselves or their allies.
func can_heal(actor: Combatant) -> bool:
	for action in actor.block.available_actions():
		if _heals(action):
			return true
	return false


## Sends a party member to a point. Works while paused; they move once time runs.
func order_move(actor: Combatant, point: Vector3) -> bool:
	if not active or actor.side != Combatant.Side.PARTY or actor.is_down() or actor.body == null:
		return false
	actor.move_order = true
	actor.move_goal = point
	order_changed.emit(actor)
	return true


func cancel_move(actor: Combatant) -> void:
	if actor.move_order:
		actor.move_order = false
		order_changed.emit(actor)


## Hold: don't advance on targets automatically (party only).
func set_hold(actor: Combatant, hold: bool) -> void:
	if actor.side != Combatant.Side.PARTY:
		return
	actor.hold_position = hold
	order_changed.emit(actor)


## Sets who a party member auto-attacks and aims single-target orders at.
func set_target(actor: Combatant, target: Combatant) -> void:
	if target == null or target.is_down() or target.side == actor.side:
		return
	actor.target = target
	target_changed.emit(actor)


## What `actor` can do right now, one entry per castable level:
## {action, level, label, cost, affordable}. Ordinary actions have level 0.
func options_for(actor: Combatant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for action in actor.block.available_actions():
		if action.is_canto():
			for lvl in actor.block.castable_levels(action):
				var cost := engine.anima_cost_for(action, lvl)
				out.append({"action": action, "level": lvl, "cost": cost,
						"label": "%s L%d" % [action.display_name, lvl],
						"affordable": actor.block.anima >= cost})
		else:
			var cost := engine.anima_cost_for(action)
			out.append({"action": action, "level": 0, "cost": cost,
				"label": action.display_name + (" (Cantrip)" if action.is_cantrip() else ""),
				"affordable": actor.block.anima >= cost})
	return out


# ------------------------------------------------------------------ turns

## The gauge just filled: tick conditions, decide what to do, then try to do it.
func _begin_turn(c: Combatant) -> void:
	# Judge whether they can act before conditions tick down, so a 1-round Stun
	# really costs the stunned combatant one turn.
	var can_act_now := c.block.can_act()
	for line in c.block.tick_round():
		_say(line)
	if c.is_down():
		say_event(&"downed", {"actor": c.display_name()})
		_check_end()
		return
	if not can_act_now:
		say_event(&"unable_to_act", {"actor": c.display_name()})
		return
	c.pending_plan = _plan_for(c)
	c.turn_pending = true
	_start_spotlight(c)
	_try_act(c)
	_try_act(c)


## Carries out the pending plan if the target is in reach; otherwise keeps it
## pending (the combatant walks toward the target) or, on Hold, forfeits it.
func _try_act(c: Combatant) -> void:
	# Turn focus: give the camera a moment to arrive before the actor does anything.
	if _spot == c and _spot_age < focus_lead_in:
		return
	var plan = c.pending_plan
	var action: ActionDef = plan["action"]
	var resolved := _resolve_targets(c, action, plan.get("target") as Combatant)
	var any := false
	for kind in resolved:
		if not (resolved[kind] as Array).is_empty():
			any = true
	if not any:
		c.turn_pending = false
		return
	var subject: Combatant = null
	var pick := action.first_pick()
	if pick != -1 and not (resolved.get(pick, []) as Array).is_empty():
		subject = resolved[pick][0] as Combatant
	var reach := reach_for(c, action)
	if subject != null and not _in_reach(c, subject, reach):
		if c.side == Combatant.Side.PARTY and c.hold_position and not c.move_order:
			say_event(&"holds_position", {"actor": c.display_name()})
			c.turn_pending = false
			return
		c.approach_target = subject
		c.approach_reach = reach
		return
	c.turn_pending = false
	if subject != null:
		_face(c, subject)
	_execute(c, plan, resolved)
	_check_end()


## Decides what a combatant does: {action, level, target}. A queued order comes first,
## then (party) a heal for a wounded ally if they're set to, then their default action.
func _plan_for(c: Combatant) -> Dictionary:
	if c.has_order():
		var queued := c.order
		c.order = {}
		order_changed.emit(c)
		return queued
	if c.side == Combatant.Side.ENEMY:
		return _enemy_plan(c)
	if c.behavior == Combatant.Behavior.HEAL_WOUNDED:
		var heal := _heal_plan(c)
		if not heal.is_empty():
			return heal
	return _default_plan(c)


func _basic_plan(target: Combatant) -> Dictionary:
	return {"action": engine.config.get_basic_attack(), "level": 0, "target": target}


## The party member's chosen automatic action, or a basic attack if it has none or
## they can't afford it this turn (the setting stays for the next one).
func _default_plan(c: Combatant) -> Dictionary:
	var action := c.default_action
	if action != null and c.block.can_cast(action) \
			and c.block.anima >= engine.anima_cost_for(action, c.default_level):
		return {"action": action, "level": c.default_level, "target": _auto_target(c, action)}
	return _basic_plan(c.target)


## Who an automatic action aims at: the usual target for attacks, the most wounded
## ally for single-ally actions, nobody for the rest (the session picks).
func _auto_target(c: Combatant, action: ActionDef) -> Combatant:
	match action.first_pick():
		EffectDef.Target.SINGLE_ENEMY:
			return c.target
		EffectDef.Target.SINGLE_ALLY:
			return _most_wounded(party if c.side == Combatant.Side.PARTY else enemies)
	return null


## A heal for the party if anyone is under `heal_threshold`, else an empty plan.
func _heal_plan(c: Combatant) -> Dictionary:
	var wounded: Array[Combatant] = []
	for ally in _alive(party):
		if _health_fraction(ally) < heal_threshold:
			wounded.append(ally)
	if wounded.is_empty():
		return {}
	var neediest := _most_wounded(wounded)
	var group_pick: Dictionary = {}
	var single_pick: Dictionary = {}
	var self_pick: Dictionary = {}
	for option in options_for(c):
		var action: ActionDef = option["action"]
		if not option["affordable"] or not _heals(action):
			continue
		match action.friendly_heal_target():
			EffectDef.Target.ALL_ALLIES:
				if group_pick.is_empty():
					group_pick = option
			EffectDef.Target.SINGLE_ALLY:
				if single_pick.is_empty():
					single_pick = option
			EffectDef.Target.SELF:
				if self_pick.is_empty():
					self_pick = option
	var pick: Dictionary = {}
	var aimed: Combatant = null
	if not group_pick.is_empty() and wounded.size() >= 2:
		pick = group_pick
	elif not single_pick.is_empty():
		pick = single_pick
		aimed = neediest
	elif not group_pick.is_empty():
		pick = group_pick
	elif not self_pick.is_empty() and neediest == c:
		pick = self_pick
	if pick.is_empty():
		return {}
	return {"action": pick["action"], "level": pick["level"], "target": aimed}


func _enemy_plan(c: Combatant) -> Dictionary:
	var specials: Array[Dictionary] = []
	for option in options_for(c):
		if option["action"] != engine.config.get_basic_attack() and option["affordable"]:
			specials.append(option)
	if not specials.is_empty() and engine.rng.randf() < enemy_special_chance:
		var pick: Dictionary = specials[engine.rng.randi_range(0, specials.size() - 1)]
		return {"action": pick["action"], "level": pick["level"], "target": null}
	return _basic_plan(c.target)


func _execute(c: Combatant, plan: Dictionary, resolved: Dictionary) -> void:
	var action: ActionDef = plan["action"]
	var by_kind := {}
	var watched: Array[Combatant] = []
	var was_down: Array[bool] = []
	for kind in resolved:
		var blocks: Array = []
		for t in resolved[kind]:
			var who := t as Combatant
			blocks.append(who.block)
			if not watched.has(who):
				watched.append(who)
				was_down.append(who.is_down())
		by_kind[kind] = blocks
	var result := engine.use_action(c.block, action, by_kind, int(plan.get("level", 0)))
	if not result["ok"]:
		_say(str(result["reason"]))
		# An order that can't be carried out falls back to a plain attack,
		# which still has to get into reach.
		if action != engine.config.get_basic_attack():
			c.pending_plan = _basic_plan(plan.get("target") as Combatant)
			c.turn_pending = true
		return
	for line in result["log"]:
		_say(line)
	for i in watched.size():
		if watched[i].is_down() and not was_down[i]:
			say_event(&"downed", {"actor": watched[i].display_name()})
	action_resolved.emit(c, result)


## {EffectDef.Target: Array[Combatant]} for each kind of target the action's effects use.
func _resolve_targets(c: Combatant, action: ActionDef, preferred: Combatant) -> Dictionary:
	var allies := party if c.side == Combatant.Side.PARTY else enemies
	var foes := enemies if c.side == Combatant.Side.PARTY else party
	var out := {}
	for kind in action.target_kinds():
		var list: Array[Combatant] = []
		match kind:
			EffectDef.Target.SELF:
				list.append(c)
			EffectDef.Target.SINGLE_ALLY:
				var ally := preferred
				if ally == null or ally.is_down() or not allies.has(ally):
					ally = _most_wounded(allies)
				if ally != null:
					list.append(ally)
			EffectDef.Target.ALL_ALLIES:
				list.assign(_alive(allies))
			EffectDef.Target.ALL_ENEMIES:
				list.assign(_alive(foes))
			_:
				var foe := preferred
				if foe == null or foe.is_down() or not foes.has(foe):
					foe = _nearest_alive(c, foes)
				if foe != null:
					list.append(foe)
		out[kind] = list
	return out


func _check_end() -> void:
	if not active or _ending:
		return
	var victory: bool
	if _alive(enemies).is_empty():
		victory = true
	elif _alive(party).is_empty():
		victory = false
	else:
		return
	if _holds.is_empty():
		_end(victory)
	else:
		# Let the killing blow's feedback play out first; advance() closes the fight.
		_ending = true
		_end_victory = victory


func _end(victory: bool) -> void:
	active = false
	paused = false
	_ending = false
	_holds.clear()
	_end_spotlight()
	for c: Combatant in party + enemies:
		c.turn_pending = false
		c.move_order = false
		c.moving = false
		c.stall_time = 0.0
		c.best_gap = INF
		if c.block != null:
			c.block.end_of_fight()
	paused_changed.emit(false)
	say_event(&"victory" if victory else &"defeat")
	_set_player_lock(false)
	combat_ended.emit(victory)


# ------------------------------------------------------------ positioning

## How far `action` reaches when `c` uses it, in metres.
func reach_for(c: Combatant, action: ActionDef) -> float:
	if action == engine.config.get_basic_attack():
		return c.attack_range
	if action.first_pick() == -1:
		return INF
	# Use an ActionDef `range` property if the resource has one.
	var r: Variant = action.get("max_range")
	if r != null and float(r) > 0.0:
		return float(r)
	return spell_range


func _in_reach(c: Combatant, t: Combatant, reach: float) -> bool:
	if c.body == null or t.body == null or is_inf(reach):
		return true
	return _flat_distance(c, t) <= reach


func _flat_distance(a: Combatant, b: Combatant) -> float:
	var d = a.body.global_position - b.body.global_position
	d.y = 0.0
	return d.length()


## Living foes keep their targets fresh: enemies re-pick every frame (nearest, but
## spread out and with some stickiness); party members only retarget when theirs
## has fallen, so a target the player chose stays chosen.
func _retarget() -> void:
	for c: Combatant in party + enemies:
		if c.is_down():
			continue
		var foes := enemies if c.side == Combatant.Side.PARTY else party
		if c.side == Combatant.Side.ENEMY or c.target == null or c.target.is_down():
			c.target = _spread_target(c, foes)


## Picks a foe for `c`: close ones score better, foes that allies are already aimed at
## score worse, and the current target wins unless something is clearly better.
func _spread_target(c: Combatant, foes: Array[Combatant]) -> Combatant:
	var allies := party if c.side == Combatant.Side.PARTY else enemies
	var best: Combatant = null
	var best_score := INF
	var current_score := INF
	for foe in foes:
		if foe.is_down():
			continue
		var crowd := 0
		for ally in allies:
			if ally != c and not ally.is_down() and ally.target == foe:
				crowd += 1
		var score := target_spread_penalty * crowd
		if c.body != null and foe.body != null:
			score += _flat_distance(c, foe)
		if foe == c.target:
			current_score = score
		if score < best_score:
			best = foe
			best_score = score
	if c.target != null and not c.target.is_down() and current_score <= best_score + target_hysteresis:
		return c.target
	return best


func _step_movement(delta: float) -> void:
	var everyone: Array[Combatant] = party + enemies
	var slots := _plan_slots(everyone)
	for c in everyone:
		var cd := delta * _time_scale_for(c)      # NEW
		_track_progress(c, cd)
		c.moving = false
		if c.is_down() or c.body == null:
			continue
		var goal: Variant = c.move_goal if c.move_order else slots.get(c)
		# Stuck: skip the polite slot planning and just get into reach.
		if c.stall_time > stall_seconds and not c.move_order:
			goal = _direct_goal(c)
		if goal == null:
			continue
		var pos := c.body.global_position
		var to: Vector3 = (goal as Vector3) - pos
		to.y = 0.0
		var dist := to.length()
		# A move order is done on arrival, or once someone is already standing on the spot.
		if dist < 0.15 or (c.move_order and dist < min_spacing and _crowded_at(goal as Vector3, c, everyone)):
			c.move_order = false
			continue
		# Walk the way steering says (round walls and props), then swerve round anyone
		# in the way. Stuck for long enough: straight in.
		var heading: Vector3
		if c.stall_time > unstick_seconds:
			heading = to / dist
		else:
			heading = _steer_around_others(c, Steering.direction(c.body, goal as Vector3), everyone)
		if heading == Vector3.ZERO:
			continue
		var step := minf(c.move_speed * cd, dist)
		var new_pos := pos + heading * step
		c.body.global_position = Vector3(new_pos.x, pos.y, new_pos.z)
		var yaw := atan2(-heading.x, -heading.z)  # forward is -Z
		c.body.rotation.y = lerp_angle(c.body.rotation.y, yaw, minf(1.0, 12.0 * cd))
		c.moving = true
	_separate(everyone, delta * (focus_slow_scale if _spot != null else 1.0))

## Watchdog. While `c` is waiting to act it should keep getting closer to reach; if the
## gap hasn't shrunk for a while, stall_time grows and _step_movement steps in.
func _track_progress(c: Combatant, delta: float) -> void:
	var foe := _approach_foe(c)
	var waiting := c.turn_pending and foe != null and c.body != null and not c.is_down() \
			and not c.move_order and not is_inf(c.approach_reach) \
			and not (c.side == Combatant.Side.PARTY and c.hold_position)
	if not waiting:
		c.stall_time = 0.0
		c.best_gap = INF
		return
	var gap := _flat_distance(c, foe) - c.approach_reach  # beyond reach if positive
	if gap < c.best_gap - 0.1:
		c.best_gap = gap
		c.stall_time = 0.0
		return
	c.stall_time += delta
	if debug_stalls and c.stall_time >= stall_seconds and c.stall_time - delta < stall_seconds:
		print("[combat] %s stuck: %.2f m beyond reach of %s, at (%.1f, %.1f)" % [
				c.display_name(), gap, foe.display_name(),
				c.body.global_position.x, c.body.global_position.z])


## A spot just inside reach on the straight line from the foe through `c`, ignoring
## crowding and walls. The last resort for a stuck combatant.
func _direct_goal(c: Combatant) -> Variant:
	var foe := _approach_foe(c)
	var stop := _approach_stop(c)
	if foe == null or is_inf(stop):
		return null
	var away := c.body.global_position - foe.body.global_position
	away.y = 0.0
	var dir := away.normalized() if away.length() > 0.01 else Vector3.BACK
	var spot := foe.body.global_position + dir * stop * 0.9
	spot.y = c.body.global_position.y
	return spot

## Bends `heading` away from anyone ahead of or beside `c` that it would bump into.
## The foe it is closing in on doesn't count: it is meant to get close to that one.
func _steer_around_others(c: Combatant, heading: Vector3, everyone: Array[Combatant]) -> Vector3:
	if heading == Vector3.ZERO:
		return heading
	var lateral := Vector3(-heading.z, 0.0, heading.x)  # to the right of the way we're going
	var wanted := _approach_foe(c)
	var push := Vector3.ZERO
	for o in everyone:
		if o == c or o == wanted or o.is_down() or o.body == null:
			continue
		var gap := min_spacing if o.side == c.side else foe_spacing
		var radius := gap * 1.8
		var offset := o.body.global_position - c.body.global_position
		offset.y = 0.0
		var d := offset.length()
		if d < 0.001 or d > radius:
			continue
		var toward := offset / d
		if toward.dot(heading) < -0.2:
			continue  # behind us
		var strength := (radius - d) / radius
		var side := lateral.dot(toward)
		if absf(side) < 0.15:
			# Dead ahead: pick a side by identity so two units meeting head-on part ways.
			side = 1.0 if c.get_instance_id() % 2 == 0 else -1.0
		push += -signf(side) * lateral * strength - toward * strength * 0.5
	if push == Vector3.ZERO:
		return heading
	var steered := (heading + push * avoidance_strength).normalized()
	return steered if steered != Vector3.ZERO else heading


## Pushes every overlapping pair apart, whether or not either is moving. Anyone on Hold
## stays where they are, so the other one gives way instead.
func _separate(everyone: Array[Combatant], delta: float) -> void:
	var max_push := separation_speed * delta
	for _i in 2:
		for i in everyone.size():
			var a := everyone[i]
			if a.is_down() or a.body == null:
				continue
			for j in range(i + 1, everyone.size()):
				var b := everyone[j]
				if b.is_down() or b.body == null:
					continue
				var gap := min_spacing if a.side == b.side else foe_spacing
				var away := a.body.global_position - b.body.global_position
				away.y = 0.0
				var d := away.length()
				if d >= gap:
					continue
				var a_free := not _is_pinned(a)
				var b_free := not _is_pinned(b)
				if not a_free and not b_free:
					continue
				# Exactly on top of each other: any fixed direction will do.
				var dir := away / d if d > 0.001 else Vector3.RIGHT.rotated(Vector3.UP, float(i * 7 + j))
				var overlap := gap - d
				var share_a := 0.5 if (a_free and b_free) else (1.0 if a_free else 0.0)
				_nudge(a, dir * minf(overlap * share_a, max_push))
				_nudge(b, -dir * minf(overlap * (1.0 - share_a), max_push))


## Not shoved around by other combatants: held in place by the player, or stuck and
## needing to get through (the others make way for it).
func _is_pinned(c: Combatant) -> bool:
	if c.side == Combatant.Side.PARTY and c.hold_position and not c.move_order:
		return true
	return c.stall_time > stall_seconds


## Moves `c` by `offset` unless a wall is in the way.
func _nudge(c: Combatant, offset: Vector3) -> void:
	if offset.length_squared() < 0.000001:
		return
	var from := c.body.global_position
	var to := from + offset
	if Steering.line_is_clear(c.body, from, to):
		c.body.global_position = to


## True if someone other than `c` is already standing at `point`.
func _crowded_at(point: Vector3, c: Combatant, everyone: Array[Combatant]) -> bool:
	for o in everyone:
		if o == c or o.is_down() or o.body == null:
			continue
		var d := o.body.global_position - point
		d.y = 0.0
		if d.length() < min_spacing * 0.6:
			return true
	return false


## Who `c` is closing in on: the target of its pending action, else its target.
func _approach_foe(c: Combatant) -> Combatant:
	var foe: Combatant = c.approach_target if c.turn_pending else c.target
	if foe == null or foe.is_down() or foe.body == null or foe == c:
		return null
	return foe


## How far from that foe `c` stands: just inside its reach. INF = no need to move.
func _approach_stop(c: Combatant) -> float:
	var reach: float = c.approach_reach if c.turn_pending else c.attack_range
	if is_inf(reach):
		return INF
	return reach * arrive_fraction


## Where each combatant should move this frame: {Combatant: Vector3}. Combatants who
## are fine where they are (in reach, uncrowded), on Hold, or on a move order are left
## out. Everyone closing in on the same foe gets their own spot on a ring round it, so
## the party spreads out instead of piling onto one point and blocking each other.
func _plan_slots(everyone: Array[Combatant]) -> Dictionary:
	var out := {}
	var seekers := {}  # foe -> Array[Combatant]
	var fixed: Array[Vector3] = []  # where combatants who aren't moving stand
	for c in everyone:
		if c.is_down() or c.body == null:
			continue
		var foe := _approach_foe(c)
		var holding := c.side == Combatant.Side.PARTY and c.hold_position
		if c.move_order or holding or foe == null or is_inf(_approach_stop(c)):
			fixed.append(c.body.global_position)
			continue
		if not seekers.has(foe):
			seekers[foe] = []
		(seekers[foe] as Array).append(c)
	for foe: Combatant in seekers:
		_assign_ring(foe, seekers[foe], fixed, out)
	return out


## Gives each seeker of `foe` a standing spot at its own distance from the foe, as near
## as possible to the direction it is already coming from, with at least `min_spacing`
## between everyone and no wall in the way. Those already in place choose first.
func _assign_ring(foe: Combatant, seekers: Array, fixed: Array[Vector3], out: Dictionary) -> void:
	var centre: Vector3 = foe.body.global_position
	var ordered: Array = seekers.duplicate()
	ordered.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		var a_in := _flat_distance(a, foe) <= _approach_stop(a) + 0.3
		var b_in := _flat_distance(b, foe) <= _approach_stop(b) + 0.3
		if a_in != b_in:
			return a_in
		return a.get_instance_id() < b.get_instance_id())  # fixed order, so spots don't swap
	var taken: Array[Vector3] = fixed.duplicate()
	for c: Combatant in ordered:
		var here: Vector3 = c.body.global_position
		var offset := here - centre
		offset.y = 0.0
		var reach: float = c.approach_reach if c.turn_pending else c.attack_range
		var in_reach := offset.length() <= reach
		var radius := clampf(minf(offset.length(), _approach_stop(c)), 0.5, 1000.0)
		var bearing := atan2(offset.x, offset.z) if offset.length() > 0.01 else 0.0
		var step := min_spacing / radius
		var tries := int(ceil(PI / maxf(step, 0.05)))
		var chosen := here
		var found := false
		for k in range(0, tries + 1):
			for sign_ in ([1.0, -1.0] if k > 0 else [1.0]):
				var angle: float = bearing + sign_ * k * step
				var spot := centre + Vector3(sin(angle), 0.0, cos(angle)) * radius
				spot.y = here.y
				if _spot_is_free(spot, taken) and Steering.line_is_clear(c.body, centre, spot):
					chosen = spot
					found = true
					break
			if found:
				break
		if not found and not in_reach:
			# Nowhere free: crowd in rather than stand about out of reach.
			chosen = centre + Vector3(sin(bearing), 0.0, cos(bearing)) * radius
			chosen.y = here.y
		taken.append(chosen)
		var flat := chosen - here
		flat.y = 0.0
		# Only count as "already there" if actually in reach; otherwise keep walking.
		if flat.length() > 0.25 or (not in_reach and flat.length() > 0.02):
			out[c] = chosen


func _spot_is_free(spot: Vector3, taken: Array[Vector3]) -> bool:
	for other in taken:
		var d := spot - other
		d.y = 0.0
		if d.length() < min_spacing:
			return false
	return true


func _face(c: Combatant, t: Combatant) -> void:
	if c.body == null or t.body == null or c == t:
		return
	var d = t.body.global_position - c.body.global_position
	d.y = 0.0
	if d.length() > 0.01:
		c.body.rotation.y = atan2(-d.x, -d.z)


## Reach of `block`'s basic attack: its equipped weapon's range, else the defaults.
func attack_range_for(block: StatBlock) -> float:
	var weapon := _equipped_weapon(block)
	if weapon == null:
		return default_attack_range
	if weapon.weapon_range > 0.0:
		return weapon.weapon_range
	if weapon.weapon_tags.has("ranged"):
		return ranged_attack_range
	return default_attack_range


## ASSUMPTION: StatBlock keeps the equipment it was given in a property called
## `equipment`. If this returns null for armed characters, see the note below.
func _equipped_weapon(block: StatBlock) -> ItemDef:
	var gear: Variant = block.get("equipment")
	if gear is Dictionary:
		var item: Variant = gear.get(&"weapon")
		if item is ItemDef:
			return item
	return null


# ---------------------------------------------------------------- helpers

func _say(text: String) -> void:
	if text == "":
		return
	history.append(text)
	log_line.emit(text)


## Logs one line of text from the LogText resource, so the wording is yours to write.
## Nothing is logged if that event was left blank.
func say_event(event: StringName, vars: Dictionary = {}) -> void:
	_say(engine.say(event, vars))


func _alive(group: Array[Combatant]) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c in group:
		if not c.is_down():
			out.append(c)
	return out


## The closest living member of `group` to `c`; the first one if positions are unknown.
func _nearest_alive(c: Combatant, group: Array[Combatant]) -> Combatant:
	var best: Combatant = null
	var best_d := INF
	for o in group:
		if o.is_down():
			continue
		var d := 0.0
		if c.body != null and o.body != null:
			d = _flat_distance(c, o)
		if best == null or d < best_d:
			best = o
			best_d = d
	return best


## Corpus as a fraction of the maximum, 0 to 1.
func _health_fraction(c: Combatant) -> float:
	return float(c.block.corpus) / maxf(1.0, float(c.block.max_corpus()))


## The living member with the lowest share of their Corpus left (for heals aimed at
## "an ally"); the lower absolute Corpus wins a tie.
func _most_wounded(group: Array[Combatant]) -> Combatant:
	var best: Combatant = null
	for c in _alive(group):
		if best == null:
			best = c
			continue
		var mine := _health_fraction(c)
		var theirs := _health_fraction(best)
		if mine < theirs or (is_equal_approx(mine, theirs) and c.block.corpus < best.block.corpus):
			best = c
	return best


## True if any step of `action` heals.
func _heals(action: ActionDef) -> bool:
	return action.friendly_heal_target() != -1


## Freezes or frees the exploration player (PlayerLink) while the fight runs.
func _set_player_lock(on: bool) -> void:
	var link := get_tree().get_first_node_in_group("party_link")
	if link == null:
		return
	if on and link.has_method("lock_controls"):
		link.lock_controls()
	elif not on and link.has_method("unlock_controls"):
		link.unlock_controls()

# ---------------------------------------------------------------- turn focus

func _focus_enabled() -> bool:
	CombatOptions.ensure_loaded()
	return CombatOptions.focus_turns


## Speed multiplier for `c` right now.
func _time_scale_for(c: Combatant) -> float:
	if _spot == null:
		return 1.0
	return focus_actor_scale if c == _spot else focus_slow_scale


func spotlight() -> Combatant:
	return _spot


func _start_spotlight(c: Combatant) -> void:
	if not _focus_enabled() or c.body == null:
		return
	if c.side == Combatant.Side.ENEMY and not focus_enemy_turns:
		return
	_spot = c
	_spot_age = 0.0
	_spot_linger = focus_linger
	get_tree().call_group(&"drone_camera", &"set_combat_focus", c.body)
	turn_spotlight_changed.emit(c)


func _update_spotlight(delta: float) -> void:
	if _spot == null:
		return
	if not _focus_enabled():
		_end_spotlight()
		return
	_spot_age += delta
	var acting := _spot.turn_pending and not _spot.is_down() and _spot_age < focus_timeout
	if acting or is_holding(_spot):
		_spot_linger = focus_linger  # still walking up, acting, or waiting on feedback
		return
	_spot_linger -= delta
	if _spot_linger <= 0.0:
		_end_spotlight()


func _end_spotlight() -> void:
	if _spot == null:
		return
	_spot = null
	get_tree().call_group(&"drone_camera", &"clear_combat_focus")
	turn_spotlight_changed.emit(null)


# ------------------------------------------------------------- feedback holds

## Called by anything that plays feedback for `actor`'s action (the roll display, an
## animation, a sound...) from its action_resolved handler. Until release_turn() is
## called with the returned id, the actor's turn isn't over: their gauge stays frozen,
## the Focus spotlight stays on them, and the fight can't end. Returns 0 (and does
## nothing) if hold_turns_for_feedback is off.
func hold_turn(actor: Combatant) -> int:
	if not hold_turns_for_feedback or actor == null:
		return 0
	var id := _next_hold
	_next_hold += 1
	_holds[id] = {"actor": actor, "age": 0.0}
	return id


func release_turn(id: int) -> void:
	_holds.erase(id)


## True while `actor` has feedback outstanding (or, with no argument, anyone does).
func is_holding(actor: Combatant = null) -> bool:
	if actor == null:
		return not _holds.is_empty()
	for hold: Dictionary in _holds.values():
		if hold["actor"] == actor:
			return true
	return false


## Waits until `actor`'s feedback has finished. Waits one frame first, so holds taken by
## other listeners of the same action_resolved signal are already registered.
func wait_for_feedback(actor: Combatant) -> void:
	await get_tree().process_frame
	while is_inside_tree() and is_holding(actor):
		await get_tree().process_frame


func _tick_holds(delta: float) -> void:
	for id in _holds.keys():
		var hold: Dictionary = _holds[id]
		hold["age"] = float(hold["age"]) + delta
		if float(hold["age"]) > feedback_timeout:
			push_warning("CombatSession: a feedback hold for %s was never released; dropping it." % hold["actor"].display_name())
			_holds.erase(id)
