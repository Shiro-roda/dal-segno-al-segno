class_name Leveling
extends RefCounted
## Level-up rules: awarding XP, rolling random feat/Canto offers, and applying
## the player's choices to both the CharacterSheet (saved) and its StatBlock (live).
##
## Typical flow:
##   var ready := Leveling.award_xp(Rules.roster, 120)       # ids that can level
##   var offer := Leveling.build_offer(Rules.roster, id)     # show it to the player
##   offer.choose(0, some_option)                             # ...for each pick
##   Leveling.apply(offer, Rules.roster)


## Adds XP to every companion on the roster (or just the active party) and returns
## the ids of those who can now level up. The player character earns no XP.
static func award_xp(roster: PartyRoster, amount: int, active_only: bool = true) -> Array[StringName]:
	var ids: Array = roster.active if active_only else roster.sheets.keys()
	var ready: Array[StringName] = []
	for id in ids:
		var sheet := roster.get_sheet(id)
		if sheet == null or sheet.is_player:
			continue
		sheet.xp += amount
		if can_level_up(sheet):
			ready.append(id)
	return ready


static func can_level_up(sheet: CharacterSheet) -> bool:
	return sheet != null and not sheet.is_player and sheet.progression != null \
			and sheet.progression.can_level(sheet.level, sheet.xp)


## Everyone on the roster who has earned a level.
static func ready_to_level(roster: PartyRoster) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in roster.sheets:
		if can_level_up(roster.get_sheet(id)):
			out.append(id)
	return out


## Rolls the choices for `char_id`'s next level. Returns null if they can't level.
## Uses the engine's RNG unless one is given (pass a seeded one for repeatable runs).
static func build_offer(roster: PartyRoster, char_id: StringName,
		p_rng: RandomNumberGenerator = null) -> LevelUpOffer:
	var sheet := roster.get_sheet(char_id)
	if not can_level_up(sheet):
		return null
	var offer := LevelUpOffer.new()
	offer.char_id = char_id
	offer.new_level = sheet.level + 1
	_add_picks(offer, sheet, roster.engine, p_rng, sheet.progression.picks_for(offer.new_level))
	return offer


## True if this companion still owes their level-1 starting picks.
static func needs_starting_picks(sheet: CharacterSheet) -> bool:
	if sheet == null or sheet.is_player or sheet.progression == null or sheet.starting_picks_done:
		return false
	var s = sheet.progression.starting_picks()
	return int(s[LevelUpOffer.FEAT]) + int(s[LevelUpOffer.CANTO]) + int(s[LevelUpOffer.CANTRIP]) > 0


static func pending_starting(roster: PartyRoster) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in roster.sheets:
		if needs_starting_picks(roster.get_sheet(id)):
			out.append(id)
	return out


## The level-1 picks. Apply it with Leveling.apply() like any offer.
static func build_starting_offer(roster: PartyRoster, char_id: StringName,
		p_rng: RandomNumberGenerator = null) -> LevelUpOffer:
	var sheet := roster.get_sheet(char_id)
	if not needs_starting_picks(sheet):
		return null
	var offer := LevelUpOffer.new()
	offer.char_id = char_id
	offer.new_level = sheet.level
	offer.is_starting = true
	_add_picks(offer, sheet, roster.engine, p_rng, sheet.progression.starting_picks())
	return offer


static func _add_picks(offer: LevelUpOffer, sheet: CharacterSheet, engine: RulesEngine,
		p_rng: RandomNumberGenerator, counts: Dictionary) -> void:
	var rng := p_rng if p_rng != null else engine.rng
	var prog := sheet.progression
	var shown: Array = []  # never offer the same option in two picks of one offer
	for _i in int(counts.get(LevelUpOffer.FEAT, 0)):
		var options := _roll(_feat_candidates(sheet, prog, engine, offer.new_level, shown),
				_feat_weights, prog.offer_size, rng)
		if options.is_empty():
			break
		shown.append_array(options)
		offer.picks.append({"kind": LevelUpOffer.FEAT, "options": options, "chosen": null})
	for _i in int(counts.get(LevelUpOffer.CANTO, 0)):
		var options := _roll(_action_candidates(prog.canto_pool, sheet, engine, offer.new_level, shown),
				_even_weights, prog.offer_size, rng)
		if options.is_empty():
			break
		shown.append_array(options)
		offer.picks.append({"kind": LevelUpOffer.CANTO, "options": options, "chosen": null})
	for _i in int(counts.get(LevelUpOffer.CANTRIP, 0)):
		var options := _roll(_action_candidates(prog.cantrip_pool, sheet, engine, offer.new_level, shown),
				_even_weights, prog.offer_size, rng)
		if options.is_empty():
			break
		shown.append_array(options)
		offer.picks.append({"kind": LevelUpOffer.CANTRIP, "options": options, "chosen": null})
	for _i in int(counts.get(LevelUpOffer.ATTRIBUTE, 0)):
		var ids: Array = []
		for def in engine.stats_in_category(StatDef.Category.ATTRIBUTE):
			ids.append(def.id)
		if not ids.is_empty():
			offer.picks.append({"kind": LevelUpOffer.ATTRIBUTE, "options": ids, "chosen": null})


## Applies a completed offer: raises the level and records the choices on the
## sheet, then updates the live StatBlock to match and heals by what it gained.
## The character's hit die is rolled (not averaged) and the roll is stored; half of it
## goes to the player character. Pass a seeded RNG for repeatable runs.
## Returns false (and changes nothing) if the offer isn't complete.
static func apply(offer: LevelUpOffer, roster: PartyRoster, p_rng: RandomNumberGenerator = null) -> bool:
	if offer == null or not offer.is_complete():
		return false
	var sheet := roster.get_sheet(offer.char_id)
	var block := roster.get_block(offer.char_id)
	if sheet == null or block == null or sheet.progression == null:
		return false
	var prog := sheet.progression
	var max_corpus_before := block.max_corpus()
	var max_anima_before := block.max_anima()

	var corpus_roll := 0
	if offer.is_starting:
		sheet.starting_picks_done = true
	else:
		# Settle any earlier unrolled levels first, then roll this level's hit die.
		var rng := p_rng if p_rng != null else roster.engine.rng
		sheet.fill_corpus_rolls(roster.engine)
		corpus_roll = Dice.roll(block.effective_corpus_die(), rng)
		sheet.corpus_rolls.append(corpus_roll)
		block.corpus_rolls = sheet.corpus_rolls.duplicate()
		offer.corpus_roll = corpus_roll
		sheet.level = offer.new_level

	for p in offer.picks:
		match p["kind"]:
			LevelUpOffer.FEAT:
				sheet.feats.append(p["chosen"] as FeatDef)
			LevelUpOffer.CANTO, LevelUpOffer.CANTRIP:
				sheet.known_actions.append(p["chosen"] as ActionDef)
			LevelUpOffer.ATTRIBUTE:
				var key := StringName(p["chosen"])
				var base := roster.engine.config.attribute_base
				sheet.scores[key] = _score(sheet.scores, key, base) + prog.attribute_amount
				block.scores[key] = int(sheet.scores[key])

	block.level = sheet.level
	block.known_actions = sheet.known_actions.duplicate()
	block.apply_feats(sheet.feats)
	block.corpus = mini(block.corpus + maxi(0, block.max_corpus() - max_corpus_before), block.max_corpus())
	block.anima = mini(block.anima + maxi(0, block.max_anima() - max_anima_before), block.max_anima())
	if not offer.is_starting:
		_share_corpus(offer.char_id, corpus_roll, roster)
	roster.changed.emit()
	return true


## A companion's level-up gives Corpus to the player character: RulesConfig.player_corpus_share
## of the companion's hit-die roll (not the Tone modifier), rounded up, at least 1.
## The player character's own growth is never passed on.
static func _share_corpus(source_id: StringName, roll: int, roster: PartyRoster) -> void:
	var source_sheet := roster.get_sheet(source_id)
	if source_sheet == null or source_sheet.is_player:
		return
	var share := maxi(1, ceili(roll * roster.engine.config.player_corpus_share))
	for other_id in roster.sheets:
		if other_id == source_id:
			continue
		var other_sheet := roster.get_sheet(other_id)
		var other_block := roster.get_block(other_id)
		if other_sheet == null or other_block == null or not other_sheet.is_player:
			continue
		other_sheet.bonus_corpus += share
		other_block.bonus_corpus += share
		other_block.corpus = mini(other_block.corpus + share, other_block.max_corpus())


# ------------------------------------------------------------ eligibility

static func feat_eligible(feat: FeatDef, sheet: CharacterSheet, engine: RulesEngine, level: int) -> bool:
	if feat == null or level < feat.min_level:
		return false
	var owned := 0
	for f in sheet.feats:
		if f == feat:
			owned += 1
	if owned >= feat.max_stacks:
		return false
	for req in feat.required_feats:
		if not sheet.feats.has(req):
			return false
	for attr in feat.min_scores:
		if _score(sheet.scores, StringName(attr), engine.config.attribute_base) < int(feat.min_scores[attr]):
			return false
	return true


## A Canto is offered only if the character could cast it at the new level.
static func canto_eligible(action: ActionDef, sheet: CharacterSheet, engine: RulesEngine, level: int) -> bool:
	if action == null or sheet.known_actions.has(action):
		return false
	return not action.is_canto() or action.canto_level <= engine.config.max_canto_level_for(level)


# ---------------------------------------------------------------- helpers

static func _feat_candidates(sheet: CharacterSheet, prog: ProgressionDef, engine: RulesEngine,
		level: int, shown: Array) -> Array:
	var out: Array = []
	for feat in prog.feat_pool:
		if not shown.has(feat) and feat_eligible(feat, sheet, engine, level):
			out.append(feat)
	return out


static func _action_candidates(pool: Array, sheet: CharacterSheet, engine: RulesEngine,
		level: int, shown: Array) -> Array:
	var out: Array = []
	for action in pool:
		if not shown.has(action) and canto_eligible(action, sheet, engine, level):
			out.append(action)
	return out


static func _feat_weights(candidates: Array) -> Array[float]:
	var out: Array[float] = []
	for feat: FeatDef in candidates:
		out.append(feat.weight)
	return out


static func _even_weights(candidates: Array) -> Array[float]:
	var out: Array[float] = []
	for _c in candidates:
		out.append(1.0)
	return out


## Picks up to `count` distinct candidates at random, weighted.
static func _roll(candidates: Array, weigh: Callable, count: int, rng: RandomNumberGenerator) -> Array:
	var pool := candidates.duplicate()
	var weights: Array[float] = weigh.call(pool)
	var out: Array = []
	while out.size() < count and not pool.is_empty():
		var total := 0.0
		for w in weights:
			total += w
		if total <= 0.0:
			break
		var roll := rng.randf() * total
		var index := pool.size() - 1
		for i in weights.size():
			roll -= weights[i]
			if roll <= 0.0:
				index = i
				break
		out.append(pool[index])
		pool.remove_at(index)
		weights.remove_at(index)
	return out


## Scores may be saved with String or StringName keys; accept either.
static func _score(scores: Dictionary, key: StringName, fallback: int) -> int:
	if scores.has(key):
		return int(scores[key])
	if scores.has(String(key)):
		return int(scores[String(key)])
	return fallback
