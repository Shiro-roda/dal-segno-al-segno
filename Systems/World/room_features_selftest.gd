extends Node
## Self-test for the party side of room features (short rest, hazards, shops).
## Run room_features_selftest.tscn and look for "ALL PASSED".

const STATS_DIR := "res://Systems/Rules/Data/Stats"
const CUTS := &"cuts"

var _failures := 0
var _checks := 0
var _engine: RulesEngine


func _ready() -> void:
	_engine = RulesEngine.new(null, 4242)
	_engine.load_stat_defs(STATS_DIR)
	_test_short_rest()
	_test_hazard()
	_test_shop()
	print("[features] %d checks, %d failures." % [_checks, _failures])
	if _failures == 0:
		print("[features] ALL PASSED")


# --------------------------------------------------------------- short rest

func _test_short_rest() -> void:
	var roster := _roster()
	var cycle := _cycle(_tile(&"rest_room", func(t: TileDef) -> void: t.rest = RestDef.new()))
	var pos := Vector2i(1, 0)
	var hero := roster.get_block(&"hero")
	var friend := roster.get_block(&"friend")
	hero.corpus = 1
	hero.anima = 0

	var refused := RoomFeatures.short_rest(cycle, Vector2i(0, 1), roster)
	_expect(not refused["ok"], "no rest room, no rest")

	cycle.start_expedition()
	var report := RoomFeatures.short_rest(cycle, pos, roster, {&"hero": 5})
	_expect(report["ok"], "the party can rest in a rest room")
	_expect(hero.anima == mini(hero.max_anima(), ceili(hero.max_anima() * 0.5)),
			"half of max Anima comes back, rounded up")
	_expect(int(report["dice_spent"].get(&"hero", 0)) == 1, "a level 1 character has one hit die a day")
	var most := hero.effective_corpus_die() + hero.total_mod(_engine.config.corpus_stat)
	var healed := int(report["healing"].get(&"hero", 0))
	_expect(healed >= 1 and healed <= maxi(1, most), "a hit die heals its roll plus the Corpus modifier (%d)" % healed)
	_expect(hero.corpus == 1 + healed, "Corpus goes up by what was healed")
	_expect(not RoomFeatures.short_rest(cycle, pos, roster)["ok"], "the room is used up for the day")

	# Full Corpus spends no dice.
	hero.refill()
	friend.refill()
	var cycle2 := _cycle(_tile(&"rest_room", func(t: TileDef) -> void: t.rest = RestDef.new()))
	cycle2.start_expedition()
	var full := RoomFeatures.short_rest(cycle2, pos, roster, {&"hero": 1, &"friend": 1})
	_expect(full["dice_spent"].is_empty(), "no dice are spent at full Corpus")

	# A downed character can't spend any.
	var cycle3 := _cycle(_tile(&"rest_room", func(t: TileDef) -> void: t.rest = RestDef.new()))
	cycle3.start_expedition()
	friend.corpus = 0
	var downed := RoomFeatures.short_rest(cycle3, pos, roster, {&"friend": 1})
	_expect(not downed["dice_spent"].has(&"friend") and friend.corpus == 0, "a downed character can't spend hit dice")

	# Anima only.
	var cycle4 := _cycle(_tile(&"rest_room", func(t: TileDef) -> void:
		t.rest = RestDef.new()
		t.rest.allow_hit_dice = false))
	cycle4.start_expedition()
	hero.corpus = 1
	var plain := RoomFeatures.short_rest(cycle4, pos, roster, {&"hero": 1})
	_expect(plain["ok"] and hero.corpus == 1 and plain["dice_spent"].is_empty(), "allow_hit_dice = false restores Anima only")


# ------------------------------------------------------------------ hazards

func _test_hazard() -> void:
	var roster := _roster()
	var hero := roster.get_block(&"hero")
	var pos := Vector2i(1, 0)
	roster.get_block(&"friend").corpus = 1000  # soaks up the damage so only the hero is in question

	var def := HazardDef.new()
	def.save_dc = 999
	def.damage = "5"
	def.bonus_blueprints = 2
	var cycle := _cycle(_tile(&"trap", func(t: TileDef) -> void: t.hazard = def))
	cycle.start_expedition()

	hero.corpus = 3
	var report := RoomFeatures.enter_room(cycle, pos, roster)
	_expect(report["triggered"] and report["bonus_blueprints"] == 2, "walking into a hazard room sets it off")
	var first: Dictionary = report["results"][0]
	_expect(not first["saved"], "a DC nobody can reach is failed")
	_expect(hero.corpus == 1, "a hazard that isn't lethal leaves 1 Corpus")
	_expect(not RoomFeatures.enter_room(cycle, pos, roster)["triggered"], "it only goes off once a day")
	_expect(not RoomFeatures.enter_room(cycle, Vector2i(0, 1), roster)["triggered"], "a room with no hazard does nothing")

	def.lethal = true
	hero.corpus = 3
	RoomFeatures.resolve_hazard(def, roster)
	_expect(hero.is_down(), "a lethal hazard can knock a character out")
	_expect(RoomFeatures.resolve_hazard(def, roster)["results"].size() == roster.active.size() - 1,
			"characters who are already down are skipped")

	def.lethal = false
	def.save_dc = -999
	def.damage = "10"
	def.on_save = EffectDef.OnSave.HALF
	hero.corpus = hero.max_corpus()
	var before := hero.corpus
	var halved: Dictionary = RoomFeatures.resolve_hazard(def, roster)["results"][0]
	_expect(halved["saved"] and before - hero.corpus == 5, "a save halves the damage (%d)" % (before - hero.corpus))
	def.on_save = EffectDef.OnSave.NEGATES
	before = hero.corpus
	RoomFeatures.resolve_hazard(def, roster)
	_expect(hero.corpus == before, "a save can negate it")

	var sting := ConditionDef.new()
	sting.id = &"hazard_test"
	sting.display_name = "hazard_test"
	sting.duration_rounds = 3
	def.condition = sting
	def.save_dc = 999
	def.damage = "0"
	RoomFeatures.resolve_hazard(def, roster)
	_expect(hero.has_condition(&"hazard_test"), "a failed save applies the condition")
	hero.remove_condition(&"hazard_test")
	def.save_dc = -999
	RoomFeatures.resolve_hazard(def, roster)
	_expect(not hero.has_condition(&"hazard_test"), "a successful save doesn't")


# -------------------------------------------------------------------- shops

func _test_shop() -> void:
	var roster := _roster()
	var item := ItemDef.new()
	item.id = &"wares"
	var offer := ShopOffer.new()
	offer.item = item
	offer.price = {CUTS: 4}
	var cycle := _cycle(null, func(c: DayCycle) -> void:
		var stall := TileDef.new()
		stall.id = &"stall"
		stall.category = TileDef.Category.VILLAGE
		stall.shop = ShopDef.new()
		stall.shop.offers = [offer]
		c.place_tile(Vector2i(1, 0), stall))
	var pos := Vector2i(1, 0)
	_expect(not cycle.shop_offers(pos).is_empty(), "the shop is stocked")
	var bought := RoomFeatures.buy(cycle, pos, 0, roster)
	_expect(bought["ok"] and bought["item"] == item, "buying succeeds")
	_expect(roster.inventory.count(item) == 1, "the item goes into the party's bag")
	_expect(cycle.stock[CUTS] == 6, "and the price is paid")
	var again := RoomFeatures.buy(cycle, pos, 0, roster)
	_expect(not again["ok"] and roster.inventory.count(item) == 1, "a sold-out shelf adds nothing to the bag")


# ---------------------------------------------------------------- helpers

## A run with `feature_tile` (if any) built at (1, 0) on the Bass Clef, and anything
## else `extra` does, ready to plan or send out.
func _cycle(feature_tile: TileDef, extra: Callable = Callable()) -> DayCycle:
	var gate := TileDef.new()
	gate.id = &"gate"
	gate.role = TileDef.Role.EXIT
	var config := WorldConfig.new()
	config.require_blueprints = false
	config.require_segno = false
	config.starting_resources = {CUTS: 10}
	var cycle := DayCycle.new(gate, config, WorldPersistent.new(), 3)
	cycle.begin_run()
	if feature_tile != null:
		cycle.place_tile(Vector2i(1, 0), feature_tile)
	if extra.is_valid():
		extra.call(cycle)
	return cycle


func _tile(id: StringName, setup: Callable) -> TileDef:
	var def := TileDef.new()
	def.id = id
	def.display_name = String(id)
	def.category = TileDef.Category.DUNGEON
	setup.call(def)
	return def


func _roster() -> PartyRoster:
	var roster := PartyRoster.new(_engine)
	roster.recruit(_sheet(&"hero"))
	roster.recruit(_sheet(&"friend"))
	return roster


func _sheet(id: StringName) -> CharacterSheet:
	var s := CharacterSheet.new()
	s.id = id
	s.display_name = String(id)
	s.progression = ProgressionDef.new()
	s.scores = {&"volume": 12, &"tempo": 10, &"tone": 12, &"attachment": 14}
	return s


func _expect(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		return
	_failures += 1
	push_error("[features] FAIL: " + message)
	print("[features] FAIL: ", message)
