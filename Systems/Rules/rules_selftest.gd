extends Node
## Self-test for the rules core. Run rules_selftest.tscn and read the output.

const STATS_DIR := "res://Systems/Rules/Data/Stats"

var _failures := 0
var _checks := 0


func _ready() -> void:
	var engine := RulesEngine.new(null, 12345)
	var loaded := engine.load_stat_defs(STATS_DIR)
	# Attributes and skills are yours to define, so only require that some load.
	_expect(loaded > 0, "loaded stat definitions (got %d)" % loaded)

	# Modifier formula
	_expect(engine.ability_mod(10) == 0, "mod(10) == 0")
	_expect(engine.ability_mod(8) == -1, "mod(8) == -1")
	_expect(engine.ability_mod(15) == 2, "mod(15) == 2")

	# Dice
	var p := Dice.parse("2d6+3")
	_expect(p["count"] == 2 and p["sides"] == 6 and p["bonus"] == 3, "parse 2d6+3")
	_expect(Dice.parse("d8")["count"] == 1, "parse d8")
	_expect(Dice.parse("1d4-1")["bonus"] == -1, "parse 1d4-1")
	for _i in 200:
		var r := Dice.roll_expr("2d6+3", engine.rng)
		_expect(r["total"] >= 5 and r["total"] <= 15, "2d6+3 in range")

	# Advantage resolution
	_expect(engine.resolve_mode(RulesEngine.RollMode.NORMAL) == 0, "normal")
	_expect(engine.resolve_mode(RulesEngine.RollMode.ADVANTAGE, 0, 1) == 0, "adv + dis cancel")
	_expect(engine.resolve_mode(RulesEngine.RollMode.DISADVANTAGE) == -1, "disadvantage")

	# Multi-attribute skills and saves (defined in code for the test)
	engine.register_stat(_derived(&"test_skill", StatDef.Category.SKILL, [&"volume", &"tempo"]))
	engine.register_stat(_derived(&"test_save", StatDef.Category.SAVE, [&"tone", &"delusion"]))
	engine.register_stat(_derived(&"test_neg", StatDef.Category.SKILL, [&"aversion", &"tempo"]))
	engine.register_stat(_derived(&"test_solo", StatDef.Category.SKILL, [&"attachment"]))

	# Characters
	var hero := StatBlock.new(engine, "Kendall", 3)
	hero.scores = {&"volume": 12, &"tempo": 16, &"tone": 12, &"aversion": 8, &"attachment": 14, &"delusion": 10}
	hero.skill_ranks = {&"test_skill": 1}
	hero.refill()
	var brute := StatBlock.new(engine, "Brute", 2)
	brute.scores = {&"volume": 16, &"tempo": 10, &"tone": 14, &"aversion": 10, &"attachment": 10, &"delusion": 8}
	brute.refill()
	print("[rules] %s: Corpus %d, Anima %d, Defense %d" % [hero.display_name, hero.corpus, hero.anima, hero.defense()])
	print("[rules] %s: Corpus %d, Anima %d, Defense %d" % [brute.display_name, brute.corpus, brute.anima, brute.defense()])
	_expect(hero.defense() == 13, "hero defense 10 + tempo mod 3 = 13 (got %d)" % hero.defense())
	_expect(hero.corpus == hero.max_corpus(), "hero starts at full Corpus")
	_expect(hero.max_anima() == 5, "hero max Anima 2 + 1 (level 3) + 2 (attachment 14) = 5 (got %d)" % hero.max_anima())
	# volume mod 1 -> ceil(1/2)=1, tempo mod 3 -> ceil(3/2)=2, +1 rank
	_expect(hero.total_mod(&"test_skill") == 4, "two-attribute skill = 1 + 2 + 1 rank (got %d)" % hero.total_mod(&"test_skill"))
	# tone mod 1 -> 1, delusion mod 0 -> 0
	_expect(hero.total_mod(&"test_save") == 1, "two-attribute save = 1 + 0 (got %d)" % hero.total_mod(&"test_save"))
	# aversion mod -1 -> ceil(-0.5)=0, tempo mod 3 -> 2
	_expect(hero.total_mod(&"test_neg") == 2, "negative half rounds up toward zero: 0 + 2 (got %d)" % hero.total_mod(&"test_neg"))
	# a single governing attribute contributes its full modifier
	_expect(hero.total_mod(&"test_solo") == 2, "single attribute = full modifier (got %d)" % hero.total_mod(&"test_solo"))

	# Checks, attacks, saves
	var chk := engine.check(hero, &"test_skill", 12)
	print("[rules] ", chk.describe())
	_expect(chk.bonus == 4, "check bonus = 4 (got %d)" % chk.bonus)
	_expect(chk.total == chk.natural + chk.bonus, "total = natural + bonus")

	var atk := engine.attack(hero, &"tempo", brute)
	print("[rules] ", atk.describe())
	_expect(atk.target == brute.defense(), "attack targets defense")

	# Disadvantage via condition: advantage_on only matches listed stats
	var attack_action := engine.config.get_basic_attack()
	_expect(attack_action != null, "built-in Attack action exists")
	# Throwaway Cantos built in code, so the test needs no authored data.
	var lash := _test_spell(&"test_lash", 1, 3)
	var haze := _test_spell(&"test_haze", 3, 0)

	var res := engine.use_action(hero, attack_action, [brute])
	for line in res["log"]:
		print("[rules] ", line)
	_expect(res["ok"], "Attack resolves")

	var anima_before := hero.anima
	res = engine.use_action(hero, lash, [brute])
	for line in res["log"]:
		print("[rules] ", line)
	_expect(hero.anima == anima_before - 1, "A spell spends 1 Anima Portion")

	# Out of Anima
	hero.anima = 0
	res = engine.use_action(hero, haze, [brute])
	_expect(not res["ok"], "cannot cast without Anima Portions")

	# Conditions
	var bleeding := ConditionDef.new()
	bleeding.id = &"bleeding"
	bleeding.display_name = "Bleeding"
	bleeding.duration_rounds = 3
	bleeding.tick_damage = "1d4"
	var stunned := ConditionDef.new()
	stunned.id = &"stunned"
	stunned.display_name = "Stunned"
	stunned.duration_rounds = 1
	stunned.blocks_actions = true
	brute.corpus = brute.max_corpus()
	brute.add_condition(bleeding)
	for line in brute.tick_round():
		print("[rules] ", line)
	_expect(brute.corpus < brute.max_corpus(), "bleeding deals damage on tick")
	brute.add_condition(stunned)
	_expect(not brute.can_act(), "stunned blocks actions")
	brute.tick_round()
	_expect(brute.can_act(), "stun expires after 1 round")
	_expect(not brute.has_condition(&"stunned"), "stunned removed")

	# Healing and damage clamp
	brute.take_damage(9999)
	_expect(brute.corpus == 0 and brute.is_down(), "Corpus clamps at 0")
	_expect(not brute.can_act(), "downed actors cannot act")

	# Dialogic-style access through the Rules autoload: Dialogic evaluates conditions
	# with Expression, passing autoload nodes by name, so test exactly that path.
	var rules_node := get_node_or_null("/root/Rules")
	_expect(rules_node != null, "Rules autoload is present")
	if rules_node != null:
		rules_node.register_actor("pc", hero)
		rules_node.engine.register_stat(_derived(&"test_skill", StatDef.Category.SKILL, [&"volume", &"tempo"]))
		var expr := Expression.new()
		_expect(expr.parse('Rules.check("test_skill", 5)', ["Rules"]) == OK, "expression parses")
		var outcome: Variant = expr.execute([rules_node], self)
		_expect(not expr.has_execute_failed(), "expression executes")
		_expect(typeof(outcome) == TYPE_BOOL, "Rules.check returns a bool")
		_expect(rules_node.last_roll_text != "", "last roll text recorded")
		print("[rules] Dialogic path: ", rules_node.last_roll_text)
		_expect(rules_node.mod("test_skill") == 4, "Rules.mod matches StatBlock")
		# Unknown stat and unknown actor fail safely.
		_expect(rules_node.check("nope", 5) == false, "unknown stat returns false")
		_expect(rules_node.check("tempo", 5, "ghost") == false, "unknown actor returns false")

	_test_roster(engine)
	_test_new_rules(engine)

	print("[rules] %d checks, %d failures." % [_checks, _failures])
	if _failures == 0:
		print("[rules] ALL PASSED")


func _sheet(char_id: StringName, scores: Dictionary) -> CharacterSheet:
	var sheet := CharacterSheet.new()
	sheet.id = char_id
	sheet.display_name = String(char_id).capitalize()
	sheet.level = 2
	sheet.scores = scores
	return sheet


func _test_roster(engine: RulesEngine) -> void:
	var sword := ItemDef.new()
	sword.id = &"test_blade"
	sword.display_name = "Test Blade"
	sword.slot = &"weapon"
	sword.modifiers = {&"volume": 2, &"damage": 1}
	var strike := _test_spell(&"granted", 1, 0)
	sword.granted_actions = [strike]

	var roster := PartyRoster.new(engine)
	var sheet := _sheet(&"tester", {&"volume": 10, &"tempo": 12})
	var block := roster.recruit(sheet)
	_expect(block.score(&"tone") == 10, "missing attributes default to base")
	_expect(block.total_mod(&"tempo") == 1, "sheet scores apply")
	_expect(block.corpus == block.max_corpus(), "new character starts at full Corpus")
	_expect(roster.is_active(&"tester"), "recruit joins the active party")

	# Equipment
	_expect(block.total_mod(&"volume") == 0, "volume mod before equipping")
	var previous := roster.equip(&"tester", sword)
	_expect(previous == null, "nothing replaced in an empty slot")
	_expect(block.total_mod(&"volume") == 2, "equipped item modifies the stat")
	_expect(block.modifier_bonus(&"damage") == 1, "pseudo-stat modifier from item")
	_expect(block.available_actions().has(strike), "item grants its action")
	var removed := roster.unequip(&"tester", &"weapon")
	_expect(removed == sword, "unequip returns the item")
	_expect(block.total_mod(&"volume") == 0, "modifiers removed on unequip")
	_expect(not block.available_actions().has(strike), "granted action removed on unequip")

	# Party size cap and validation
	for n in 4:
		roster.recruit(_sheet(StringName("extra%d" % n), {}))
	_expect(roster.active.size() == engine.config.party_size, "active party capped at %d" % engine.config.party_size)
	_expect(roster.blocks.size() == 5, "everyone is on the roster")
	_expect(not roster.set_active([&"tester", &"ghost"]), "set_active rejects unknown ids")
	_expect(not roster.set_active([&"tester", &"tester"]), "set_active rejects duplicates")
	_expect(not roster.set_active([&"tester", &"extra0", &"extra1", &"extra2"]), "set_active rejects oversize party")
	_expect(roster.set_active([&"extra3", &"tester"]), "set_active accepts a valid party")
	_expect(roster.active_blocks().size() == 2, "active_blocks matches")

	# Persistence round trip
	block.take_damage(5)
	var hurt := block.corpus
	roster.sync_to_sheets()
	_expect(sheet.current_corpus == hurt, "sync_to_sheets stores Corpus")
	var roster2 := PartyRoster.new(engine)
	_expect(roster2.recruit(sheet).corpus == hurt, "rebuilt block restores Corpus")
	roster.rest_all()
	_expect(block.corpus == block.max_corpus(), "rest refills Corpus")

	# Through the autoload
	var rules_node := get_node_or_null("/root/Rules")
	if rules_node != null:
		var pc: StatBlock = rules_node.recruit(_sheet(&"kendall", {&"tempo": 16}), true, true)
		_expect(rules_node.get_actor("pc") == pc, "Rules.recruit registers the player as pc")
		_expect(rules_node.get_actor("kendall") == pc, "Rules.recruit registers by sheet id")
		_expect(rules_node.mod("tempo", "kendall") == 3, "Rules.mod by actor id")


## A minimal Canto, built in code for tests only. Deals 1d6, plus 1d6 per level
## cast above `level`.
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


## Corpus dice, weapon dice and Cantos.
func _test_new_rules(engine: RulesEngine) -> void:
	# --- Corpus die: a full die at level 1, the average each level after ---
	var fighter := StatBlock.new(engine, "Fighter", 3)
	fighter.scores = {&"tone": 12, &"volume": 12, &"tempo": 10}
	_expect(fighter.max_corpus() == 31, "default d8 at level 3 = 10 + 9 + 2*6 = 31 (got %d)" % fighter.max_corpus())
	fighter.corpus_die = 12
	_expect(fighter.max_corpus() == 39, "d12 at level 3 = 10 + 13 + 2*8 = 39 (got %d)" % fighter.max_corpus())
	fighter.corpus_die = 6
	_expect(fighter.max_corpus() == 27, "d6 at level 3 = 10 + 7 + 2*5 = 27 (got %d)" % fighter.max_corpus())
	var newcomer := StatBlock.new(engine, "Newcomer", 1)
	newcomer.scores = {&"tone": 10}
	newcomer.corpus_die = 10
	_expect(newcomer.max_corpus() == 20, "level 1 gets a full die: 10 + 10 (got %d)" % newcomer.max_corpus())
	var die_sheet := CharacterSheet.new()
	die_sheet.corpus_die = 12
	_expect(die_sheet.build_block(engine).corpus_die == 12, "a sheet's Corpus die reaches its block")

	# --- Weapon dice belong to the weapon ---
	var blade := ItemDef.new()
	blade.id = &"test_blade"
	blade.display_name = "Test Blade"
	blade.slot = &"weapon"
	blade.damage_dice = "1d8"
	blade.damage_type = &"red"
	var wielder := StatBlock.new(engine, "Wielder", 3)
	wielder.scores = {&"volume": 12, &"tempo": 10, &"tone": 12, &"attachment": 16}
	wielder.refill()
	var dummy := StatBlock.new(engine, "Dummy", 5)
	dummy.scores = {&"tone": 20, &"tempo": 10}
	dummy.corpus_die = 12
	dummy.refill()
	_expect(wielder.weapon().display_name == engine.config.unarmed_name, "nothing equipped means unarmed")
	_expect(wielder.available_actions().has(engine.config.get_basic_attack()), "everyone has the Attack action")
	wielder.apply_equipment({&"weapon": blade})
	_expect(wielder.weapon() == blade, "the equipped weapon is the one used")
	var attack_action := engine.config.get_basic_attack()
	var low := 999
	var high := 0
	for _i in 200:
		dummy.corpus = dummy.max_corpus()
		engine.use_action(wielder, attack_action, [dummy])
		var hit_for := dummy.max_corpus() - dummy.corpus
		if hit_for > 0:
			low = mini(low, hit_for)
			high = maxi(high, hit_for)
	_expect(high > 0, "the weapon attack hits sometimes")
	# Volume 12 gives +1. 1d8+1 is 2..9; a crit doubles the dice: 2d8+1 is 3..17.
	_expect(low >= 2 and high <= 17, "weapon damage stays within its dice (got %d..%d)" % [low, high])
	_expect(high > low, "weapon damage varies, so its dice are really rolled")

	# --- Cantos: three levels, some upcastable, some simply higher level ---
	var lash := _test_spell(&"c_lash", 1, 3)
	var gale := _test_spell(&"c_gale", 3, 0)
	_expect(str(lash.castable_levels()) == "[1, 2, 3]", "an upcastable Canto casts at 1, 2 or 3")
	_expect(str(gale.castable_levels()) == "[3]", "a level-3 Canto casts only at 3")
	_expect(lash.can_upcast() and not gale.can_upcast(), "only some Cantos can be upcast")
	_expect(engine.config.canto_level_count() == 3, "three Canto levels")
	_expect(engine.anima_cost_for(lash, 1) == 1 and engine.anima_cost_for(lash, 2) == 2
			and engine.anima_cost_for(lash, 3) == 3, "cost follows the level it is cast at")
	_expect(engine.anima_cost_for(gale, 1) == 3, "a fixed-level Canto ignores a lower request")
	_expect(engine.anima_cost_for(lash, 9) == 3, "a request above the cap is limited")
	_expect(engine.anima_cost_for(attack_action) == 0, "ordinary actions use their own cost")

	# Level 10 has every Canto level unlocked (gates are 1 / 5 / 10 by default).
	var caster := StatBlock.new(engine, "Caster", 10)
	caster.scores = {&"attachment": 16, &"tone": 12, &"volume": 10}
	caster.refill()
	dummy.corpus = dummy.max_corpus()
	var start_anima := caster.anima
	var start_corpus := dummy.corpus
	var cast := engine.use_action(caster, lash, [dummy], 3)
	_expect(cast["ok"] and cast["level"] == 3, "upcast to level 3 succeeds")
	_expect(caster.anima == start_anima - 3, "upcasting spends the higher level's cost")
	var upcast_dealt := start_corpus - dummy.corpus
	_expect(upcast_dealt >= 3 and upcast_dealt <= 18, "level 3 upcast rolls 3d6 (got %d)" % upcast_dealt)

	dummy.corpus = dummy.max_corpus()
	start_corpus = dummy.corpus
	cast = engine.use_action(caster, lash, [dummy])
	_expect(cast["level"] == 1, "with no level asked, a Canto casts at its own level")
	var base_dealt := start_corpus - dummy.corpus
	_expect(base_dealt >= 1 and base_dealt <= 6, "level 1 rolls 1d6 (got %d)" % base_dealt)

	cast = engine.use_action(caster, gale, [dummy], 1)
	_expect(cast["level"] == 3, "a fixed level-3 Canto can't be cast lower")
	caster.anima = 2
	cast = engine.use_action(caster, gale, [dummy])
	_expect(not cast["ok"], "a level-3 Canto needs 3 Anima Portions")

	# --- Character-level gates for Cantos ---
	_expect(engine.config.max_canto_level_for(4) == 1, "level 4 has only level 1 Cantos")
	_expect(engine.config.max_canto_level_for(5) == 2, "level 5 unlocks level 2 Cantos")
	_expect(engine.config.max_canto_level_for(9) == 2, "level 9 still has level 2")
	_expect(engine.config.max_canto_level_for(10) == 3, "level 10 unlocks level 3 Cantos")

	var novice := StatBlock.new(engine, "Novice", 4)
	novice.scores = {&"attachment": 18, &"tone": 12}
	novice.refill()
	_expect(novice.can_cast(lash), "a level-1 Canto is castable from the start")
	_expect(not novice.can_cast(gale), "a level-3 Canto is locked at level 4")
	_expect(str(novice.castable_levels(lash)) == "[1]", "upcast range is held at level 1 (got %s)" % str(novice.castable_levels(lash)))
	var before_locked := novice.anima
	cast = engine.use_action(novice, gale, [dummy])
	_expect(not cast["ok"], "a locked Canto fails")
	_expect(novice.anima == before_locked, "a locked Canto costs no Anima Portions")
	cast = engine.use_action(novice, lash, [dummy], 3)
	_expect(cast["ok"] and cast["level"] == 1, "an upcast is held at the unlocked level")

	var adept := StatBlock.new(engine, "Adept", 7)
	adept.scores = {&"attachment": 18, &"tone": 12}
	adept.refill()
	_expect(str(adept.castable_levels(lash)) == "[1, 2]", "level 7 can cast level 1 and 2 (got %s)" % str(adept.castable_levels(lash)))
	cast = engine.use_action(adept, lash, [dummy], 3)
	_expect(cast["ok"] and cast["level"] == 2, "level 7 upcast to 3 lands at level 2")


func _derived(id: StringName, category: StatDef.Category, governing: Array[StringName]) -> StatDef:
	var def := StatDef.new()
	def.id = id
	def.display_name = String(id)
	def.category = category
	def.governing_stats = governing
	return def


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("[rules] FAIL: ", message)
