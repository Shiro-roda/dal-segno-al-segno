class_name RoomFeatures
extends RefCounted
## Applies the room features tracked by DayCycle (short rest, hazards, shops) to the
## party. DayCycle owns the state (what was used, what is on the shelves); this owns what
## happens to characters and the bag. Pure logic: no scenes, no UI.
##
## Every function returns a report Dictionary with `ok` or `triggered` so a UI can show it.


## Takes a short rest at the room on `pos`. Everyone in the active party gets
## RestDef.anima_fraction of their max Anima back (rounded up). `spend` maps character
## id -> hit dice to spend there; each die heals its roll plus the Corpus stat modifier
## (at least 1). Dice stop being spent once the character is at full Corpus, and
## characters who are down can't spend any.
## Returns {ok, reason, anima: {id: restored}, healing: {id: healed}, dice_spent: {id: n}}.
static func short_rest(cycle: DayCycle, pos: Vector2i, roster: PartyRoster,
		spend: Dictionary = {}) -> Dictionary:
	var check := cycle.can_short_rest(pos)
	if not check["ok"]:
		return {"ok": false, "reason": check["reason"]}
	var def := cycle.use_short_rest(pos)
	var report := {"ok": true, "reason": "", "anima": {}, "healing": {}, "dice_spent": {}}
	var engine := roster.engine
	for char_id in roster.active:
		var block := roster.get_block(char_id)
		if block == null:
			continue
		report["anima"][char_id] = block.restore_anima(ceili(block.max_anima() * def.anima_fraction))
		if not def.allow_hit_dice or block.is_down():
			continue
		var want := int(spend.get(char_id, 0))
		var healed := 0
		var used := 0
		for _i in want:
			if block.corpus + healed >= block.max_corpus():
				break
			if cycle.spend_hit_dice(char_id, block.level, 1) == 0:
				break
			used += 1
			var roll := Dice.roll(block.effective_corpus_die(), engine.rng)
			healed += maxi(1, roll + block.total_mod(engine.config.corpus_stat))
		if used > 0:
			report["healing"][char_id] = block.heal(healed)
			report["dice_spent"][char_id] = used
	roster.changed.emit()
	return report


## The party walks into the room on `pos`. If it holds a hazard that hasn't gone off
## today, it does: see resolve_hazard. Returns {triggered: false} otherwise.
static func enter_room(cycle: DayCycle, pos: Vector2i, roster: PartyRoster) -> Dictionary:
	var def := cycle.trigger_hazard(pos)
	if def == null:
		return {"triggered": false}
	var report := resolve_hazard(def, roster)
	report["bonus_blueprints"] = def.bonus_blueprints
	return report


## Each active character who isn't down makes the save and takes the damage, reduced or
## negated on a success. A failed save applies the condition. Without `lethal`, nobody
## drops below 1 Corpus.
## Returns {triggered: true, results: [{id, saved, damage, roll}]}.
static func resolve_hazard(def: HazardDef, roster: PartyRoster) -> Dictionary:
	var engine := roster.engine
	var results: Array[Dictionary] = []
	for char_id in roster.active:
		var block := roster.get_block(char_id)
		if block == null or block.is_down():
			continue
		var roll := engine.save(block, def.save_stat, def.save_dc)
		var amount := int(Dice.roll_expr(def.damage, engine.rng)["total"])
		if roll.success:
			match def.on_save:
				EffectDef.OnSave.NEGATES:
					amount = 0
				EffectDef.OnSave.HALF:
					amount = floori(amount / 2.0)
		var event := DamageEvent.new()
		event.target = block
		event.amount = amount
		event.damage_type = def.damage_type
		var dealt := block.receive_damage(event)
		if not def.lethal and block.corpus < 1:
			block.corpus = 1
		if not roll.success and def.condition != null:
			block.add_condition(def.condition, "hazard")
		results.append({"id": char_id, "saved": roll.success, "damage": dealt, "roll": roll})
	roster.changed.emit()
	return {"triggered": true, "results": results}


## Buys shelf `index` of the shop on `pos` and puts the item in the party's bag.
## Returns {ok, reason, item}.
static func buy(cycle: DayCycle, pos: Vector2i, index: int, roster: PartyRoster) -> Dictionary:
	var check := cycle.can_buy(pos, index)
	if not check["ok"]:
		return {"ok": false, "reason": check["reason"], "item": null}
	var item := cycle.buy(pos, index)
	roster.inventory.add(item)
	return {"ok": true, "reason": "", "item": item}
