class_name CombatSession
extends Node
## Real-time-with-pause combat, fought in place (no movement).
##
## Every combatant has a gauge that fills over `round_seconds`, faster with a better
## initiative modifier. When it fills they take a turn: tick their conditions, then
## carry out their queued order, or auto-attack (party) / pick an action (enemies).
## Pause (the combat_pause action) stops time so orders can be queued.
##
## All rules go through RulesEngine, so this node only decides who acts and when.
## The HUD and the encounter trigger talk to it through its signals and methods.

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


func _unhandled_input(event: InputEvent) -> void:
	if active and event.is_action_pressed("combat_pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()


# ----------------------------------------------------------------- flow

## Starts a fight between two groups of StatBlocks. `p_engine` defaults to Rules.engine.
func begin(party_blocks: Array, enemy_blocks: Array, p_engine: RulesEngine = null) -> void:
	if active:
		return
	engine = p_engine if p_engine != null else Rules.engine
	party.clear()
	enemies.clear()
	history.clear()
	for b: StatBlock in party_blocks:
		party.append(Combatant.new(b, Combatant.Side.PARTY))
	for b: StatBlock in enemy_blocks:
		enemies.append(Combatant.new(b, Combatant.Side.ENEMY))
	# A head start for quick combatants: initiative roll spread over the first half-round.
	for c: Combatant in party + enemies:
		c.gauge = clampf(engine.roll_initiative(c.block) / 40.0, 0.0, 0.6)
	for c: Combatant in party:
		c.target = _first_alive(enemies)
	for c: Combatant in enemies:
		c.target = _first_alive(party)
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
			continue
		var speed := clampf(1.0 + c.block.initiative_mod() * speed_per_initiative, 0.5, 2.0)
		c.gauge += delta / round_seconds * speed
		if c.gauge >= 1.0:
			c.gauge -= 1.0
			_take_turn(c)


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

func _take_turn(c: Combatant) -> void:
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
	_execute(c, _plan_for(c))
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
	return _basic_plan(null)


func _execute(c: Combatant, plan: Dictionary) -> void:
	var action: ActionDef = plan["action"]
	var targets := _resolve_targets(c, action, plan.get("target") as Combatant)
	if targets.is_empty():
		return
	var blocks: Array = []
	for t in targets:
		blocks.append(t.block)
	var result := engine.use_action(c.block, action, blocks, int(plan.get("level", 0)))
	if not result["ok"]:
		_say(str(result["reason"]))
		# An order that can't be carried out falls back to a plain attack.
		if action != engine.config.get_basic_attack():
			_execute(c, _basic_plan(plan.get("target") as Combatant))
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
				foe = _random_alive(foes) if c.side == Combatant.Side.ENEMY else _first_alive(foes)
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
	paused_changed.emit(false)
	_say("Victory!" if victory else "The party has fallen.")
	_set_player_lock(false)
	combat_ended.emit(victory)


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


func _first_alive(group: Array[Combatant]) -> Combatant:
	for c in group:
		if not c.is_down():
			return c
	return null


func _random_alive(group: Array[Combatant]) -> Combatant:
	var living := _alive(group)
	if living.is_empty():
		return null
	return living[engine.rng.randi_range(0, living.size() - 1)]


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
