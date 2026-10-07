extends Node
## Self-test for the leveling system. Run leveling_selftest.tscn and look for "ALL PASSED".

const STATS_DIR := "res://Systems/Rules/Data/Stats"

var _failures := 0
var _checks := 0
var _engine: RulesEngine


func _ready() -> void:
	_engine = RulesEngine.new(null, 4242)
	_engine.load_stat_defs(STATS_DIR)

	print("[leveling] xp")
	_test_xp()
	print("[leveling] schedule")
	_test_pick_schedule()
	print("[leveling] feat eligibility")
	_test_feat_eligibility()
	print("[leveling] offers")
	_test_offers()
	print("[leveling] canto gating")
	_test_canto_gating()
	print("[leveling] apply")
	_test_apply()
	print("[leveling] rolled corpus")
	_test_rolled_corpus()
	print("[leveling] player track")
	_test_player_track()
	print("[leveling] shared corpus")
	_test_shared_corpus()

	print("[leveling] %d checks, %d failures." % [_checks, _failures])
	if _failures == 0:
		print("[leveling] ALL PASSED")


# ------------------------------------------------------------------ cases

func _test_xp() -> void:
	var p := ProgressionDef.new()
	p.max_level = 3
	p.xp_thresholds = PackedInt32Array([100, 250])
	_expect(not p.can_level(1, 99), "99 xp isn't enough for level 2")
	_expect(p.can_level(1, 100), "100 xp reaches level 2")
	_expect(not p.can_level(2, 249), "249 xp isn't enough for level 3")
	_expect(p.can_level(2, 250), "250 xp reaches level 3")
	_expect(not p.can_level(3, 99999), "max_level is a hard cap")
	_expect(p.xp_for_level(1) == 0 and p.xp_for_level(3) == 250 and p.xp_for_level(4) == -1,
			"xp_for_level reads the table and reports unreachable levels")


func _test_pick_schedule() -> void:
	var p := ProgressionDef.new()
	p.first_pick_level = 2
	p.feat_every = 1
	p.canto_every = 2
	p.attribute_every = 3
	var l2 := p.picks_for(2)
	_expect(l2[&"feat"] == 1 and l2[&"canto"] == 1 and l2[&"attribute"] == 1, "level 2 grants one of each")
	var l3 := p.picks_for(3)
	_expect(l3[&"feat"] == 1 and l3[&"canto"] == 0 and l3[&"attribute"] == 0, "level 3 grants only a feat")
	var l4 := p.picks_for(4)
	_expect(l4[&"canto"] == 1 and l4[&"attribute"] == 0, "level 4 grants a Canto")
	_expect(p.picks_for(5)[&"attribute"] == 1, "attribute picks repeat every 3 levels")
	_expect(p.picks_for(1)[&"feat"] == 0, "nothing before first_pick_level")
	p.canto_every = 0
	_expect(p.picks_for(2)[&"canto"] == 0, "canto_every 0 means never")


func _test_feat_eligibility() -> void:
	var sheet := _sheet(&"tester", ProgressionDef.new())
	var base := _feat(&"base")
	var gated := _feat(&"gated")
	gated.min_level = 5
	var chained := _feat(&"chained")
	chained.required_feats = [base]
	var strong := _feat(&"strong")
	strong.min_scores = {"volume": 16}
	var stacking := _feat(&"stacking")
	stacking.max_stacks = 2

	_expect(Leveling.feat_eligible(base, sheet, _engine, 2), "a plain feat is eligible")
	_expect(not Leveling.feat_eligible(gated, sheet, _engine, 4), "min_level blocks a feat")
	_expect(Leveling.feat_eligible(gated, sheet, _engine, 5), "min_level is inclusive")
	_expect(not Leveling.feat_eligible(chained, sheet, _engine, 2), "a missing prerequisite blocks a feat")
	sheet.feats.append(base)
	_expect(Leveling.feat_eligible(chained, sheet, _engine, 2), "an owned prerequisite unlocks it")
	_expect(not Leveling.feat_eligible(base, sheet, _engine, 2), "a single-stack feat can't be taken twice")
	_expect(not Leveling.feat_eligible(strong, sheet, _engine, 2), "min_scores blocks a weak character")
	sheet.scores[&"volume"] = 16
	_expect(Leveling.feat_eligible(strong, sheet, _engine, 2), "min_scores passes at the threshold")
	sheet.feats.append(stacking)
	_expect(Leveling.feat_eligible(stacking, sheet, _engine, 2), "a 2-stack feat can be taken again")
	sheet.feats.append(stacking)
	_expect(not Leveling.feat_eligible(stacking, sheet, _engine, 2), "and not a third time")


func _test_offers() -> void:
	var prog := ProgressionDef.new()
	prog.offer_size = 3
	prog.feat_every = 1
	prog.canto_every = 0
	for n in 6:
		prog.feat_pool.append(_feat(StringName("f%d" % n)))
	var roster := _roster(prog)
	var sheet := roster.get_sheet(&"tester")
	sheet.xp = 100

	var offer := Leveling.build_offer(roster, &"tester")
	_expect(offer != null and offer.picks.size() == 1, "one feat pick at level 2")
	var options: Array = offer.picks[0]["options"]
	_expect(options.size() == 3, "the pick offers offer_size options (got %d)" % options.size())
	var unique := {}
	for o in options:
		unique[o] = true
	_expect(unique.size() == options.size(), "no option is repeated within a pick")

	var a := Leveling.build_offer(roster, &"tester", _rng(7))
	var b := Leveling.build_offer(roster, &"tester", _rng(7))
	_expect(a.picks[0]["options"] == b.picks[0]["options"], "the same seed rolls the same offer")

	var small := ProgressionDef.new()
	small.feat_pool = [_feat(&"only")]
	var roster2 := _roster(small)
	roster2.get_sheet(&"tester").xp = 100
	var short := Leveling.build_offer(roster2, &"tester")
	_expect((short.picks[0]["options"] as Array).size() == 1, "a small pool offers what it has")

	var empty := ProgressionDef.new()
	var roster3 := _roster(empty)
	roster3.get_sheet(&"tester").xp = 100
	_expect(Leveling.build_offer(roster3, &"tester").is_empty(), "an empty pool yields no picks")
	_expect(Leveling.build_offer(roster, &"nobody") == null, "an unknown character yields no offer")
	sheet.xp = 0
	_expect(Leveling.build_offer(roster, &"tester") == null, "no offer without enough xp")

	var weighted := ProgressionDef.new()
	weighted.offer_size = 1
	var common := _feat(&"common")
	var never := _feat(&"never")
	never.weight = 0.0
	weighted.feat_pool = [never, common]
	var roster4 := _roster(weighted)
	roster4.get_sheet(&"tester").xp = 100
	var seen_never := false
	for s in 30:
		var o := Leveling.build_offer(roster4, &"tester", _rng(s))
		if (o.picks[0]["options"] as Array).has(never):
			seen_never = true
	_expect(not seen_never, "a weight of 0 is never offered")


func _test_canto_gating() -> void:
	var prog := ProgressionDef.new()
	prog.feat_every = 0
	prog.canto_every = 1
	prog.offer_size = 5
	var low := _spell(&"low", 1)
	var mid := _spell(&"mid", 2)
	prog.canto_pool = [low, mid]
	var roster := _roster(prog)
	roster.get_sheet(&"tester").xp = 100
	var offer := Leveling.build_offer(roster, &"tester")
	var options: Array = offer.picks[0]["options"]
	_expect(options.has(low) and not options.has(mid), "a Canto above the unlocked level isn't offered")
	roster.get_sheet(&"tester").known_actions.append(low)
	var again := Leveling.build_offer(roster, &"tester")
	_expect(again.is_empty(), "a Canto already known isn't offered again")


func _test_apply() -> void:
	var prog := ProgressionDef.new()
	prog.feat_every = 1
	prog.canto_every = 1
	prog.attribute_every = 1
	prog.attribute_amount = 2
	var tough := _feat(&"tough")
	tough.modifiers = {"defense": 1}
	prog.feat_pool = [tough]
	var low := _spell(&"low", 1)
	prog.canto_pool = [low]
	var roster := _roster(prog)
	var sheet := roster.get_sheet(&"tester")
	var block := roster.get_block(&"tester")
	sheet.xp = 100
	var corpus_before := block.max_corpus()

	var offer := Leveling.build_offer(roster, &"tester")
	_expect(offer.picks.size() == 3, "feat, Canto and attribute picks at level 2")
	_expect(not Leveling.apply(offer, roster), "an incomplete offer isn't applied")
	_expect(sheet.level == 1, "and nothing changes")
	_expect(not offer.choose(0, &"bogus"), "choosing something not offered is rejected")
	offer.choose(0, tough)
	offer.choose(1, low)
	offer.choose(2, &"volume")
	var volume_before := block.score(&"volume")
	_expect(Leveling.apply(offer, roster), "a complete offer applies")
	_expect(sheet.level == 2 and block.level == 2, "the sheet and the live block both reach level 2")
	_expect(sheet.feats.has(tough) and block.feats.has(tough), "the feat is recorded")
	_expect(block.modifier_bonus(&"defense") == 1, "the feat's modifier is active")
	_expect(sheet.known_actions.has(low) and block.known_actions.has(low), "the Canto is learned")
	_expect(block.score(&"volume") == volume_before + 2, "the attribute rose by attribute_amount")
	_expect(block.max_corpus() > corpus_before, "max Corpus grew")
	_expect(block.corpus == block.max_corpus(), "the gain was healed")
	_expect(not Leveling.can_level_up(sheet), "xp is spent against the next threshold")

	var granting := _feat(&"granting")
	granting.granted_actions = [_spell(&"granted", 1)]
	block.apply_feats([granting])
	_expect(block.available_actions().has(granting.granted_actions[0]), "feats can grant actions")


## Corpus comes from stored hit-die rolls, not the average.
func _test_rolled_corpus() -> void:
	var b := _block()
	var mod := b.total_mod(&"tone")
	var die := b.effective_corpus_die()
	var level_one := b.max_corpus()

	b.level = 4
	b.corpus_rolls = [die, 1, 5]
	var expected := level_one + maxi(1, die + mod) + maxi(1, 1 + mod) + maxi(1, 5 + mod)
	_expect(b.max_corpus() == expected, "stored rolls are used, not the average (got %d, want %d)" % [b.max_corpus(), expected])

	b.corpus_rolls = [die, die, die]
	var high := b.max_corpus()
	b.corpus_rolls = [1, 1, 1]
	_expect(high > b.max_corpus(), "different rolls give different Corpus")

	b.corpus_rolls = []
	var avg := b.corpus_average_gain()
	_expect(b.max_corpus() == level_one + 3 * maxi(1, avg + mod), "levels with no stored roll count as the average")

	# A roll never gives less than 1 Corpus, even with a bad Tone modifier.
	b.scores[&"tone"] = 2
	b.corpus_rolls = [1, 1, 1]
	var floor_check := b.max_corpus()
	b.level = 1
	_expect(floor_check >= b.max_corpus() + 3, "each level gives at least 1 Corpus")

	# A sheet authored above level 1 rolls once, then keeps its rolls.
	var sheet := _sheet(&"vet", null)
	sheet.level = 5
	var built := sheet.build_block(_engine)
	_expect(sheet.corpus_rolls.size() == 4, "building a level 5 sheet stores 4 rolls (got %d)" % sheet.corpus_rolls.size())
	var all_in_range := true
	for r in sheet.corpus_rolls:
		all_in_range = all_in_range and r >= 1 and r <= sheet.corpus_die
	_expect(all_in_range, "every stored roll is on the die")
	var stored := sheet.corpus_rolls.duplicate()
	_expect(sheet.build_block(_engine).max_corpus() == built.max_corpus(), "rebuilding gives the same Corpus")
	_expect(sheet.corpus_rolls == stored, "rolls are fixed once made")


func _test_player_track() -> void:
	var prog := ProgressionDef.new()
	prog.feat_every = 2
	prog.canto_every = 0
	prog.attribute_every = 3
	prog.feat_pool = [_feat(&"a"), _feat(&"b")]
	prog.canto_pool = [_spell(&"never_offered", 1)]
	var roster := _roster(prog)
	roster.get_sheet(&"tester").xp = 100
	var offer := Leveling.build_offer(roster, &"tester")
	var kinds: Array[StringName] = []
	for p in offer.picks:
		kinds.append(p["kind"])
	_expect(kinds.has(LevelUpOffer.FEAT) and kinds.has(LevelUpOffer.ATTRIBUTE) and not kinds.has(LevelUpOffer.CANTO),
			"a feat-and-attribute progression never offers Cantos (got %s)" % str(kinds))
	offer.auto_choose(_rng(3))
	_expect(offer.is_complete(), "auto_choose fills every pick")
	_expect(Leveling.apply(offer, roster), "and it applies")


## The player character earns no XP and gains Corpus only when a companion levels up:
## RulesConfig.player_corpus_share of that companion's hit-die roll, rounded up.
func _test_shared_corpus() -> void:
	var companion_prog := ProgressionDef.new()
	companion_prog.canto_every = 0
	companion_prog.feat_pool = [_feat(&"x")]

	var roster := PartyRoster.new(_engine)
	var hero_sheet := _sheet(&"hero", null)
	hero_sheet.is_player = true
	var friend_sheet := _sheet(&"friend", companion_prog)
	friend_sheet.corpus_die = 8
	roster.recruit(hero_sheet)
	roster.recruit(friend_sheet)
	var hero := roster.get_block(&"hero")
	var friend := roster.get_block(&"friend")

	# The player earns no XP, so awarding it can never make them level.
	var ready_ids := Leveling.award_xp(roster, 100)
	_expect(hero_sheet.xp == 0, "the player character earns no XP")
	_expect(friend_sheet.xp == 100, "companions do")
	_expect(ready_ids.has(&"friend") and not ready_ids.has(&"hero"), "only the companion is ready to level")
	_expect(not Leveling.can_level_up(hero_sheet), "the player character can't level up")
	_expect(Leveling.build_offer(roster, &"hero") == null, "and gets no level-up offer")

	var hero_before := hero.max_corpus()
	var friend_before := friend.max_corpus()
	hero.corpus = hero_before - 5
	var offer := Leveling.build_offer(roster, &"friend", _rng(9))
	offer.auto_choose(_rng(9))
	_expect(Leveling.apply(offer, roster, _rng(9)), "the companion levels up")
	_expect(friend.level == 2, "the companion is now level 2")

	# The hit die is rolled, the roll is stored, and it is not the average.
	var roll := offer.corpus_roll
	_expect(roll >= 1 and roll <= 8, "the d8 roll is on the die (got %d)" % roll)
	_expect(friend_sheet.corpus_rolls == [roll], "the roll is stored on the sheet")
	_expect(friend.corpus_rolls == [roll], "and on the live block")
	_expect(friend.max_corpus() == friend_before + maxi(1, roll + friend.total_mod(&"tone")),
			"the companion gains the roll plus Tone (got +%d)" % (friend.max_corpus() - friend_before))

	# The player gains half of the roll (not the Tone modifier), rounded up.
	var share := maxi(1, ceili(roll * 0.5))
	_expect(hero.max_corpus() == hero_before + share, "the player gains half the roll, rounded up (roll %d, got +%d)" % [roll, hero.max_corpus() - hero_before])
	_expect(hero_sheet.bonus_corpus == share, "the gain is stored on the sheet")
	_expect(hero.level == 1, "the player character's own level is unchanged")
	_expect(hero.corpus == hero_before - 5 + share, "the Corpus gained is healed")

	# Different seeds give different rolls, so the result really is rolled.
	var seen := {}
	for s in 40:
		var probe := PartyRoster.new(_engine)
		var probe_sheet := _sheet(&"probe", companion_prog)
		probe_sheet.xp = 100
		probe.recruit(probe_sheet)
		var probe_offer := Leveling.build_offer(probe, &"probe", _rng(s))
		probe_offer.auto_choose(_rng(s))
		Leveling.apply(probe_offer, probe, _rng(s))
		seen[probe_offer.corpus_roll] = true
	_expect(seen.size() > 3, "level-up rolls vary across seeds (saw %d distinct)" % seen.size())

	# Another companion level adds a second roll and a second share.
	friend_sheet.xp = 1000
	var offer2 := Leveling.build_offer(roster, &"friend", _rng(5))
	offer2.auto_choose(_rng(5))
	_expect(Leveling.apply(offer2, roster, _rng(5)), "the companion levels again")
	_expect(friend_sheet.corpus_rolls.size() == 2, "two rolls are stored by level 3")
	var share2 := maxi(1, ceili(offer2.corpus_roll * 0.5))
	_expect(hero_sheet.bonus_corpus == share + share2, "the player's gains accumulate")

	# The player character's own state survives rebuilding from the sheet.
	roster.sync_to_sheets()
	_expect(hero_sheet.build_block(_engine).max_corpus() == hero.max_corpus(), "the bonus survives rebuilding from the sheet")
	_expect(friend_sheet.build_block(_engine).max_corpus() == friend.max_corpus(), "rolled Corpus survives rebuilding from the sheet")


# ---------------------------------------------------------------- helpers

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _sheet(id: StringName, prog: ProgressionDef) -> CharacterSheet:
	var s := CharacterSheet.new()
	s.id = id
	s.display_name = String(id)
	s.progression = prog
	s.scores = {&"volume": 12, &"tempo": 10, &"tone": 12, &"attachment": 14}
	return s


func _roster(prog: ProgressionDef) -> PartyRoster:
	var roster := PartyRoster.new(_engine)
	roster.recruit(_sheet(&"tester", prog))
	return roster


func _block() -> StatBlock:
	var b := StatBlock.new(_engine, "Block", 1)
	b.scores = {&"volume": 12, &"tempo": 10, &"tone": 12}
	return b


func _feat(id: StringName) -> FeatDef:
	var f := FeatDef.new()
	f.id = id
	f.display_name = String(id)
	return f


func _spell(id: StringName, level: int) -> ActionDef:
	var spell := ActionDef.new()
	spell.id = id
	spell.display_name = String(id)
	spell.canto_level = level
	spell.max_canto_level = level
	return spell


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("[leveling] FAIL: ", message)
