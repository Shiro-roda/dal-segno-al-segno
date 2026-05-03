extends Node
## Autoload singleton — the sole authority for applying, ticking, and resolving conditions.
##
## Actor scripts call:
##   ConditionRunner.apply(holder, "bleeding", source, 3)
##   ConditionRunner.remove(holder, "bleeding")
##   ConditionRunner.has_condition(holder, "bleeding")
##   ConditionRunner.resolve("damage", ctx)
##   ConditionRunner.ctx_new(source, target, value, tags)
##
## Structural events committed by resolve():
##   "damage"  → flat-defense math → hp subtraction → hp_changed → "kill" chain if hp<=0
##   "heal"    → hp addition clamped to max_hp → hp_changed
##   "kill"    → actor set to dead state → died signal
##
## Any other event name is semantic-only: hooks fire, ctx may be mutated,
## but resolve() does not commit anything extra.

# ── Internal state ─────────────────────────────────────────────────────────────

# Cached reference to BattleEventBus autoload (resolved in _ready to avoid parse-time issues).
var _bus : Node = null

func _ready() -> void:
	_bus = get_node("/root/BattleEventBus")

## { holder_id → Array[{data: ConditionData, duration: int, source: BattleActor,
##                       callables: Dictionary<hook_index, Callable>}] }
var _active : Dictionary = {}

# Preloaded condition registry — populated lazily from Resources/Conditions/*.tres
var _registry : Dictionary = {}   # condition_id → ConditionData
var _registry_loaded : bool = false

# ── Public API ─────────────────────────────────────────────────────────────────

## Create a BattleEventContext. Convenience for formula strings and actor scripts.
func ctx_new(source: BattleActor, target: BattleActor, value: float,
		tags: Array = []) -> BattleEventContext:
	var c := BattleEventContext.new()
	c.source = source
	c.target = target
	c.value  = value
	for tag in tags:
		c.tags.append(tag)
	return c


## Apply a condition to holder. Refreshes duration if already present.
## source is the actor that applied it (for hook context). duration=-1 → default.
func apply(holder: BattleActor, condition_id: String,
		source: BattleActor = null, duration: int = -1) -> void:
	_ensure_registry()
	if not _registry.has(condition_id):
		push_warning("ConditionRunner.apply: unknown condition '%s'" % condition_id)
		# Fall back to legacy stub so nothing breaks during migration
		holder.apply_status(condition_id, duration if duration > 0 else 2)
		return

	var data : ConditionData = _registry[condition_id]
	var dur  : int = duration if duration >= 0 else data.default_duration

	var holder_id := holder.get_instance_id()
	if not _active.has(holder_id):
		_active[holder_id] = []

	# Refresh duration if already active
	for entry in _active[holder_id]:
		if entry["data"].condition_id == condition_id:
			entry["duration"] = max(entry["duration"], dur)
			return

	# New application
	var callables : Dictionary = {}
	var entry := {
		"data":      data,
		"duration":  dur,
		"source":    source,
		"callables": callables,
	}
	_active[holder_id].append(entry)

	# Connect signal hooks
	for i in data.signal_hooks.size():
		var hook : ConditionSignalHook = data.signal_hooks[i]
		if hook.listen_for == "":
			continue
		var cb : Callable = _make_hook_callable(holder, source, hook)
		callables[i] = cb
		_bus.event.connect(cb)

	# Run on_apply
	if data.on_apply_formula != "":
		_eval_formula(data.on_apply_formula, holder, source, null)

	# Mirror to legacy active_effects so HUD / has_status() still works during migration
	holder.apply_status(condition_id, dur)


## Remove a condition from holder immediately.
func remove(holder: BattleActor, condition_id: String) -> void:
	var holder_id := holder.get_instance_id()
	if not _active.has(holder_id):
		return
	var to_remove := []
	for entry in _active[holder_id]:
		if entry["data"].condition_id == condition_id:
			to_remove.append(entry)
	for entry in to_remove:
		_disconnect_entry(entry)
		var data : ConditionData = entry["data"]
		if data.on_remove_formula != "":
			_eval_formula(data.on_remove_formula, holder, entry["source"], null)
		_active[holder_id].erase(entry)
	# Mirror to legacy
	holder.active_effects = holder.active_effects.filter(
			func(e): return e["id"] != condition_id)


## Returns true if holder currently has this condition.
func has_condition(holder: BattleActor, condition_id: String) -> bool:
	var holder_id := holder.get_instance_id()
	if not _active.has(holder_id):
		return false
	for entry in _active[holder_id]:
		if entry["data"].condition_id == condition_id:
			return true
	return false


## Tick all conditions on holder (call once per actor turn, before action).
func tick(holder: BattleActor) -> void:
	var holder_id := holder.get_instance_id()
	if not _active.has(holder_id):
		return
	var expired := []
	for entry in _active[holder_id]:
		var data : ConditionData = entry["data"]
		# Run tick formula
		if data.on_tick_formula != "":
			_eval_formula(data.on_tick_formula, holder, entry["source"], null)
		# Decrement duration (0 = permanent)
		if entry["duration"] > 0:
			entry["duration"] -= 1
			if entry["duration"] <= 0:
				expired.append(entry)
	for entry in expired:
		_disconnect_entry(entry)
		var data : ConditionData = entry["data"]
		if data.on_remove_formula != "":
			_eval_formula(data.on_remove_formula, holder, entry["source"], null)
		_active[holder_id].erase(entry)
		# Mirror expiry to legacy
		holder.active_effects = holder.active_effects.filter(
				func(e): return e["id"] != data.condition_id)


## The central resolution path. Fires BattleEventBus.event synchronously,
## then commits structural consequences unless ctx.cancelled is true.
##
## Structural events: "damage", "heal", "kill"
## Semantic events: anything else — hooks fire, no automatic commit.
func resolve(event_name: String, ctx: BattleEventContext) -> void:
	# Fire hooks
	_bus.event.emit(event_name, ctx)

	if ctx.cancelled:
		return

	match event_name:
		"damage":
			var t : BattleActor = ctx.target
			if not is_instance_valid(t) or not t.is_alive():
				return
			# Flat defense: Sharp² / (Sharp + Flat), minimum 1.
			var flat : int = t.effective_flat()
			if flat > 0 and not ("true_damage" in ctx.tags):
				ctx.value = max(1.0, float(ctx.value * ctx.value) / float(ctx.value + flat))
			var dmg : int = max(1, int(ctx.value))
			t.hp -= dmg
			t.emit_signal("hp_changed")
			if ctx.source != null:
				t._spawn_damage_number(dmg, ctx.source)
			t.log_msg("%s takes %d damage." % [t.get_log_name(), dmg])
			if t.hp <= 0:
				t.hp = 0
				resolve("kill", ctx_new(ctx.source, t, 0.0, []))

		"heal":
			var t : BattleActor = ctx.target
			if not is_instance_valid(t) or not t.is_alive():
				return
			t.hp = mini(t.hp + int(ctx.value), t.max_hp)
			t.emit_signal("hp_changed")
			t.log_msg("%s recovers %d CORP." % [t.get_log_name(), ctx.value])

		"kill":
			var t : BattleActor = ctx.target
			if not is_instance_valid(t):
				return
			t.hp = 0
			t.set_actor_state(t.STATE_DEAD)
			t.log_msg("%s has fallen." % t.get_log_name())
			t.say_die()
			t.emit_signal("died", t)

		# Semantic events — hooks already ran, nothing more to commit.
		_:
			pass


# ── Internal helpers ───────────────────────────────────────────────────────────

func _make_hook_callable(holder: BattleActor, source: BattleActor,
		hook: ConditionSignalHook) -> Callable:
	return func(event_name: String, ctx: BattleEventContext) -> void:
		if event_name != hook.listen_for:
			return
		# Evaluate guard
		if hook.guard != "":
			var passed = _eval_formula(hook.guard, holder, source, ctx)
			if not passed:
				return
		# Evaluate main formula
		if hook.formula != "":
			_eval_formula(hook.formula, holder, source, ctx)
		# Optional follow-up emit
		if hook.then_emit != "":
			var emit_ctx : BattleEventContext
			if hook.emit_ctx_transform != "":
				emit_ctx = _eval_formula(hook.emit_ctx_transform, holder, source, ctx)
			else:
				emit_ctx = ctx
			_bus.event.emit(hook.then_emit, emit_ctx)


func _disconnect_entry(entry: Dictionary) -> void:
	for i in entry["callables"]:
		var cb : Callable = entry["callables"][i]
		if _bus.event.is_connected(cb):
			_bus.event.disconnect(cb)
	entry["callables"].clear()


## Evaluate a formula string with standard bindings.
## Bound names: a=holder, src=source, ctx=BattleEventContext (may be null), CR=ConditionRunner.
## Returns the value of the last expression (useful for guard formulas).
func _eval_formula(formula: String, holder: BattleActor,
		source: BattleActor, ctx: BattleEventContext):
	# Build a minimal expression. GDScript's Expression class handles this.
	var expr := Expression.new()
	var names  : PackedStringArray = ["a", "src", "ctx", "CR"]
	var values : Array             = [holder, source, ctx, self]
	var err := expr.parse(formula, names)
	if err != OK:
		push_error("ConditionRunner formula parse error in '%s': %s" % [formula, expr.get_error_text()])
		return null
	var result = expr.execute(values, holder, true)
	if expr.has_execute_failed():
		push_error("ConditionRunner formula execute error in '%s': %s" % [formula, expr.get_error_text()])
		return null
	return result


func _ensure_registry() -> void:
	if _registry_loaded:
		return
	_registry_loaded = true
	var dir := DirAccess.open("res://Systems/SkillSys/Resources/Conditions")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres") or fname.ends_with(".res"):
			var res = load("res://Systems/SkillSys/Resources/Conditions/" + fname)
			if res is ConditionData and res.condition_id != "":
				_registry[res.condition_id] = res
		fname = dir.get_next()
	dir.list_dir_end()


## Called by BattleActor._ready() (or BattleManager) when an actor leaves the
## battle so its hook callables are cleaned up.
func unregister_actor(holder: BattleActor) -> void:
	var holder_id := holder.get_instance_id()
	if not _active.has(holder_id):
		return
	for entry in _active[holder_id]:
		_disconnect_entry(entry)
	_active.erase(holder_id)
