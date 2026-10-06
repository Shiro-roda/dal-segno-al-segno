class_name CombatSession
extends Node
## Real-time-with-pause combat with free movement and positioning.
##
## Every combatant has a gauge that fills over `round_seconds`, faster with a better
## initiative modifier. When it fills they take a turn: tick their conditions, pick
## an action (a queued order, an auto-attack, or an enemy's choice), then wait
## until the target is in reach, walking toward it if need be, and carry it out.
## Pause (the combat_pause action) stops time so orders can be queued.
##
## All rules go through RulesEngine, so this node only decides who acts, when,
## and from where. Combatants with no body count as always in reach.

signal combat_started
signal combat_ended(victory: bool)
signal paused_changed(is_paused: bool)
signal log_line(text: String)
signal action_resolved(actor: Combatant, result: Dictionary)
signal order_changed(actor: Combatant)
signal target_changed(actor: Combatant)

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
## Combatants closer than this get pushed apart.
@export var separation_radius: float = 0.9
## Fraction of the reach a combatant walks up to before stopping.
@export_range(0.5, 1.0, 0.05) var arrive_fraction: float = 0.9

var engine: RulesEngine
var party: Array[Combatant] = []
var enemies: Array[Combatant] = []
var active: bool = false
var paused: bool = false
## Every line logged this fight.
var history: Array[String] = []


func _ready() -> void:
	add_to_group("combat_session")


func _process(delta: float) -> void:
	advance(delta)


func _physics_process(delta: float) -> void:
	if active and not paused:
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
		if i < party_bodies.size():
			c.body = party_bodies[i] as Node3D
		party.append(c)
	for i in enemy_blocks.size():
		var c := Combatant.new(enemy_blocks[i] as StatBlock, Combatant.Side.ENEMY)
		if i < enemy_bodies.size():
			c.body = enemy_bodies[i] as Node3D
		enemies.append(c)
	# A head start for quick combatants: initiative roll spread over the first half-round.
	for c: Combatant in party + enemies:
		c.gauge = clampf(engine.roll_initiative(c.block) / 40.0, 0.0, 0.6)
	for c: Combatant in party:
		c.target = _nearest_alive(c, enemies)
	for c: Combatant in enemies:
		c.target = _nearest_alive(c, party)
	active = true
	_set_player_lock(true)
	combat_started.emit()
	_say("Combat begins.")
	set_paused(start_paused)


## Moves time forward. Called every frame; tests call it directly.
func advance(delta: float) -> void:
	if not active or paused:
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
		var speed := clampf(1.0 + c.block.initiative_mod() * speed_per_initiative, 0.5, 2.0)
		c.gauge += delta / round_seconds * speed
		if c.gauge >= 1.0:
			c.gauge -= 1.0
			_begin_turn(c)


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
					"label": action.display_name,
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
		_check_end()
		return
	if not can_act_now:
		_say("%s is unable to act." % c.display_name())
		return
	c.pending_plan = _plan_for(c)
	c.turn_pending = true
	_try_act(c)


## Carries out the pending plan if the target is in reach; otherwise keeps it
## pending (the combatant walks toward the target) or, on Hold, forfeits it.
func _try_act(c: Combatant) -> void:
	var plan = c.pending_plan
	var action: ActionDef = plan["action"]
	var targets := _resolve_targets(c, action, plan.get("target") as Combatant)
	if targets.is_empty():
		c.turn_pending = false
		return
	var reach := reach_for(c, action)
	if not _in_reach(c, targets[0], reach):
		if c.side == Combatant.Side.PARTY and c.hold_position and not c.move_order:
			_say("%s holds position; the target is out of reach." % c.display_name())
			c.turn_pending = false
			return
		c.approach_target = targets[0]
		c.approach_reach = reach
		return
	c.turn_pending = false
	_face(c, targets[0])
	_execute(c, plan, targets)
	_check_end()


## Decides what a combatant does: {action, level, target}.
func _plan_for(c: Combatant) -> Dictionary:
	if c.has_order():
		var queued := c.order
		c.order = {}
		order_changed.emit(c)
		return queued
	if c.side == Combatant.Side.ENEMY:
		return _enemy_plan(c)
	return _basic_plan(c.target)


func _basic_plan(target: Combatant) -> Dictionary:
	return {"action": engine.config.get_basic_attack(), "level": 0, "target": target}


func _enemy_plan(c: Combatant) -> Dictionary:
	var specials: Array[Dictionary] = []
	for option in options_for(c):
		if option["action"] != engine.config.get_basic_attack() and option["affordable"]:
			specials.append(option)
	if not specials.is_empty() and engine.rng.randf() < enemy_special_chance:
		var pick: Dictionary = specials[engine.rng.randi_range(0, specials.size() - 1)]
		return {"action": pick["action"], "level": pick["level"], "target": null}
	return _basic_plan(c.target)


func _execute(c: Combatant, plan: Dictionary, targets: Array[Combatant]) -> void:
	var action: ActionDef = plan["action"]
	var blocks: Array = []
	for t in targets:
		blocks.append(t.block)
	var result := engine.use_action(c.block, action, blocks, int(plan.get("level", 0)))
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
	action_resolved.emit(c, result)


func _resolve_targets(c: Combatant, action: ActionDef, preferred: Combatant) -> Array[Combatant]:
	var allies := party if c.side == Combatant.Side.PARTY else enemies
	var foes := enemies if c.side == Combatant.Side.PARTY else party
	var out: Array[Combatant] = []
	match action.target:
		ActionDef.Target.SELF:
			out.append(c)
		ActionDef.Target.SINGLE_ALLY:
			var ally := preferred
			if ally == null or ally.is_down() or not allies.has(ally):
				ally = _weakest(allies)
			if ally != null:
				out.append(ally)
		ActionDef.Target.ALL_ALLIES:
			out.assign(_alive(allies))
		ActionDef.Target.ALL_ENEMIES:
			out.assign(_alive(foes))
		_:
			var foe := preferred
			if foe == null or foe.is_down() or not foes.has(foe):
				foe = _nearest_alive(c, foes)
			if foe != null:
				out.append(foe)
	return out


func _check_end() -> void:
	if not active:
		return
	if _alive(enemies).is_empty():
		_end(true)
	elif _alive(party).is_empty():
		_end(false)


func _end(victory: bool) -> void:
	active = false
	paused = false
	for c: Combatant in party + enemies:
		c.turn_pending = false
		c.move_order = false
		c.moving = false
	paused_changed.emit(false)
	_say("Victory!" if victory else "The party has fallen.")
	_set_player_lock(false)
	combat_ended.emit(victory)


# ------------------------------------------------------------ positioning

## How far `action` reaches when `c` uses it, in metres.
func reach_for(c: Combatant, action: ActionDef) -> float:
	if action == engine.config.get_basic_attack():
		return c.attack_range
	match action.target:
		ActionDef.Target.SELF, ActionDef.Target.ALL_ALLIES, ActionDef.Target.ALL_ENEMIES:
			return INF
	# Use an ActionDef `range` property if the resource has one.
	var r: Variant = action.get("range")
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


## Living foes keep their targets fresh: enemies always hunt the nearest
## party member; party members only retarget when theirs has fallen.
func _retarget() -> void:
	for c: Combatant in party + enemies:
		if c.is_down():
			continue
		var foes := enemies if c.side == Combatant.Side.PARTY else party
		if c.side == Combatant.Side.ENEMY or c.target == null or c.target.is_down():
			c.target = _nearest_alive(c, foes)


func _step_movement(delta: float) -> void:
	var everyone: Array[Combatant] = party + enemies
	for c in everyone:
		c.moving = false
		if c.is_down() or c.body == null:
			continue
		var goal: Variant = _goal_for(c)
		if goal == null:
			continue
		var pos = c.body.global_position
		var to: Vector3 = (goal as Vector3) - pos
		to.y = 0.0
		var dist := to.length()
		if dist < 0.05:
			c.move_order = false
			continue
		var step := minf(c.move_speed * delta, dist)
		var new_pos = pos + to / dist * step
		# Don't stack on top of each other.
		for o in everyone:
			if o == c or o.is_down() or o.body == null:
				continue
			var away = new_pos - o.body.global_position
			away.y = 0.0
			var d = away.length()
			if d > 0.001 and d < separation_radius:
				new_pos += away / d * (separation_radius - d) * 0.5
		c.body.global_position = Vector3(new_pos.x, pos.y, new_pos.z)
		var yaw := atan2(-to.x, -to.z)  # forward is -Z
		c.body.rotation.y = lerp_angle(c.body.rotation.y, yaw, minf(1.0, 12.0 * delta))
		c.moving = true


## Where `c` wants to be: an explicit move order, else just inside reach of its target.
func _goal_for(c: Combatant) -> Variant:
	if c.move_order:
		return c.move_goal
	if c.side == Combatant.Side.PARTY and c.hold_position:
		return null
	var foe: Combatant = c.approach_target if c.turn_pending else c.target
	var reach: float = c.approach_reach if c.turn_pending else c.attack_range
	if foe == null or foe.is_down() or foe.body == null or is_inf(reach):
		return null
	var to_foe = foe.body.global_position - c.body.global_position
	to_foe.y = 0.0
	var stop := reach * arrive_fraction
	if to_foe.length() <= stop:
		return null
	return foe.body.global_position - to_foe.normalized() * stop


func _face(c: Combatant, t: Combatant) -> void:
	if c.body == null or t.body == null or c == t:
		return
	var d = t.body.global_position - c.body.global_position
	d.y = 0.0
	if d.length() > 0.01:
		c.body.rotation.y = atan2(-d.x, -d.z)


# ---------------------------------------------------------------- helpers

func _say(text: String) -> void:
	if text == "":
		return
	history.append(text)
	log_line.emit(text)


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


## The living member with the lowest Corpus (for heals aimed at "an ally").
func _weakest(group: Array[Combatant]) -> Combatant:
	var best: Combatant = null
	for c in _alive(group):
		if best == null or c.block.corpus < best.block.corpus:
			best = c
	return best


## Freezes or frees the exploration player (PlayerLink) while the fight runs.
func _set_player_lock(on: bool) -> void:
	var link := get_tree().get_first_node_in_group("party_link")
	if link == null:
		return
	if on and link.has_method("lock_controls"):
		link.lock_controls()
	elif not on and link.has_method("unlock_controls"):
		link.unlock_controls()
