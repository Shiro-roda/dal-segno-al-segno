extends Node
## Self-test for CombatSession. Run combat_selftest.tscn and look for "ALL PASSED".

const STATS_DIR := "res://Systems/Rules/Data/Stats"

var _failures := 0
var _checks := 0
var _engine: RulesEngine


func _ready() -> void:
	_engine = RulesEngine.new(null, 4242)
	_engine.load_stat_defs(STATS_DIR)

	print("[combat] pause")
	_test_pause_and_gauges()
	print("[combat] victory")
	_test_victory()
	print("[combat] defeat")
	_test_defeat()
	print("[combat] orders")
	_test_orders()
	print("[combat] stun")
	_test_stun_costs_a_turn()
	print("[combat] options")
	_test_options()
	print("[combat] targeting")
	_test_targeting()

	print("[combat] %d checks, %d failures." % [_checks, _failures])
	if _failures == 0:
		print("[combat] ALL PASSED")


# ------------------------------------------------------------------ cases

func _test_pause_and_gauges() -> void:
	var s := _session()
	var hero := _block("Hero", 3)
	var husk := _block("Husk", 1)
	var pauses: Array[bool] = []
	s.paused_changed.connect(func(p: bool): pauses.append(p))
	s.begin([hero], [husk], _engine)
	_expect(s.active and s.paused, "combat starts active and paused")
	_expect(s.party.size() == 1 and s.enemies.size() == 1, "one combatant per side")
	var before := s.party[0].gauge
	s.advance(1.0)
	_expect(is_equal_approx(s.party[0].gauge, before), "no time passes while paused")
	s.set_paused(false)
	s.advance(0.3)
	_expect(s.party[0].gauge > before, "gauges fill once unpaused")
	s.toggle_pause()
	_expect(s.paused, "toggle_pause pauses")
	_expect(pauses == [true, false, true], "paused_changed fires on each change (got %s)" % str(pauses))
	s.queue_free()


func _test_victory() -> void:
	var s := _session()
	var hero := _block("Hero", 3)
	var husk := _block("Husk", 1)
	husk.corpus = 3
	var results: Array[bool] = []
	s.combat_ended.connect(func(v: bool): results.append(v))
	s.begin([hero], [husk], _engine)
	s.set_paused(false)
	_run(s)
	_expect(not s.active, "combat ends")
	_expect(results == [true], "reports a victory (got %s)" % str(results))
	_expect(husk.is_down(), "the enemy is down")
	_expect(s.history.has("Victory!"), "victory is logged")
	s.queue_free()


func _test_defeat() -> void:
	var s := _session()
	var hero := _block("Hero", 1)
	hero.corpus = 1
	var brute := _block("Brute", 3)
	brute.scores[&"volume"] = 20
	var results: Array[bool] = []
	s.combat_ended.connect(func(v: bool): results.append(v))
	s.begin([hero], [brute], _engine)
	s.set_paused(false)
	_run(s)
	_expect(results == [false], "reports a defeat (got %s)" % str(results))
	_expect(hero.is_down(), "the hero is down")
	s.queue_free()


func _test_orders() -> void:
	var s := _session()
	var hero := _block("Hero", 3)
	var lash := _test_spell(&"lash", 1, 3)
	hero.known_actions = [lash]
	var husk := _block("Husk", 1)
	husk.corpus = 200
	s.begin([hero], [husk], _engine)
	var h := s.party[0]
	var e := s.enemies[0]

	_expect(s.queue_action(h, lash, 1, e), "a Canto can be queued")
	_expect(h.has_order(), "the order is stored")
	var start_anima := hero.anima
	s.set_paused(false)
	var guard := 0
	while h.has_order() and guard < 400:
		s.advance(0.05)
		guard += 1
	_expect(not h.has_order(), "the order is consumed on the hero's turn")
	_expect(hero.anima == start_anima - 1, "casting spent 1 Anima Portion (%d -> %d)" % [start_anima, hero.anima])
	_expect(s.history.any(func(l: String): return l.contains("lash")), "the cast was logged")

	# An order that became unaffordable falls back to a plain attack.
	s.set_paused(true)
	s.queue_action(h, lash, 1, e)
	hero.anima = 0
	var logged_before := s.history.size()
	s.set_paused(false)
	guard = 0
	while h.has_order() and guard < 400:
		s.advance(0.05)
		guard += 1
	_expect(hero.anima == 0, "no Anima was spent on the failed order")
	_expect(s.history.size() > logged_before, "the failed order still did something")

	# Orders are validated up front.
	_expect(not s.queue_action(h, lash, 1, e), "can't queue a Canto with no Anima Portions")
	_expect(not s.queue_action(s.enemies[0], lash, 1, h), "enemies can't be given player orders")
	s.clear_order(h)
	s.queue_free()


func _test_stun_costs_a_turn() -> void:
	var s := _session()
	var hero := _block("Hero", 3)
	var husk := _block("Husk", 1)
	husk.corpus = 500
	var stunned := ConditionDef.new()
	stunned.id = &"stunned"
	stunned.display_name = "Stunned"
	stunned.duration_rounds = 1
	stunned.blocks_actions = true
	husk.add_condition(stunned)
	s.begin([hero], [husk], _engine)
	s.set_paused(false)
	var guard := 0
	while not s.history.any(func(l: String): return l.contains("unable to act")) and guard < 400:
		s.advance(0.05)
		guard += 1
	_expect(s.history.any(func(l: String): return l.contains("Husk is unable to act")), "a 1-round Stun skips one turn")
	_expect(not husk.has_condition(&"stunned"), "the Stun wears off afterwards")
	s.queue_free()


func _test_options() -> void:
	var s := _session()
	var lash := _test_spell(&"lash", 1, 3)
	var gale := _test_spell(&"gale", 3, 0)
	var novice := _block("Novice", 3)
	novice.known_actions = [lash, gale]
	var master := _block("Master", 10)
	master.scores[&"attachment"] = 18
	master.known_actions = [lash, gale]
	master.refill()
	s.begin([novice, master], [_block("Husk", 1)], _engine)
	var low: Array[String] = []
	for o in s.options_for(s.party[0]):
		low.append(o["label"])
	_expect(low.has("lash L1") and not low.has("lash L2") and not low.has("gale L3"),
			"a level 3 character only sees level 1 Cantos (got %s)" % str(low))
	var high: Array[String] = []
	var costs: Array[int] = []
	for o in s.options_for(s.party[1]):
		high.append(o["label"])
		if o["action"] == lash:
			costs.append(o["cost"])
	_expect(high.has("lash L1") and high.has("lash L2") and high.has("lash L3") and high.has("gale L3"),
			"a level 10 character sees every level (got %s)" % str(high))
	_expect(costs == [1, 2, 3], "costs rise with the level (got %s)" % str(costs))
	_expect(not s.queue_action(s.party[0], gale, 0, s.enemies[0]), "a locked Canto can't be queued")
	s.queue_free()


func _test_targeting() -> void:
	var s := _session()
	var hero := _block("Hero", 3)
	var a := _block("Husk A", 1)
	var b := _block("Husk B", 1)
	s.begin([hero], [a, b], _engine)
	var h := s.party[0]
	_expect(h.target == s.enemies[0], "the default target is the first enemy")
	s.set_target(h, s.enemies[1])
	_expect(h.target == s.enemies[1], "set_target changes the target")
	s.set_target(h, s.party[0])
	_expect(h.target == s.enemies[1], "can't target your own side")
	s.enemies[1].block.take_damage(9999)
	s.set_paused(false)
	var ok := false
	for _i in 200:
		s.advance(0.05)
		if s.history.any(func(l: String): return l.contains("Husk A")):
			ok = true
			break
	_expect(ok, "a dead target is replaced by a living one")
	s.queue_free()


# ---------------------------------------------------------------- helpers

func _session() -> CombatSession:
	var s := CombatSession.new()
	add_child(s)
	s.set_process(false)  # the tests step time themselves
	return s


func _run(s: CombatSession, max_steps: int = 6000) -> void:
	var steps := 0
	while s.active and steps < max_steps:
		s.advance(0.05)
		steps += 1


func _block(display_name: String, level: int) -> StatBlock:
	var b := StatBlock.new(_engine, display_name, level)
	b.scores = {&"volume": 12, &"tempo": 10, &"tone": 12, &"attachment": 14}
	b.refill()
	return b


func _test_spell(id: StringName, level: int, max_level: int) -> ActionDef:
	var spell := ActionDef.new()
	spell.id = id
	spell.display_name = String(id)
	spell.canto_level = level
	spell.max_canto_level = max_level
	spell.roll = ActionDef.Roll.SAVE
	spell.save_stat = &"tone"
	spell.dc_stat = &"attachment"
	var fx := EffectDef.new()
	fx.kind = EffectDef.Kind.DAMAGE
	fx.dice = "1d6"
	fx.upcast_dice = "1d6"
	spell.effects = [fx]
	return spell


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("[combat] FAIL: ", message)
