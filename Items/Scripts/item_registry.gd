extends Node
## Global registry of all ConsumableData instances.
## Avoids needing individual .tres files for each item.

# Corpus restores
var MEAT        : ConsumableData  # small single
var BIG_MEAT    : ConsumableData  # large single
var JERKY       : ConsumableData  # small, usable in battle
var FEAST       : ConsumableData  # large party-wide
# AP restores
var CANDY       : ConsumableData  # small single
var SWEET       : ConsumableData  # large single
var HARD_CANDY  : ConsumableData  # small, usable in battle
var BONBON      : ConsumableData  # party-wide AP
# Utility
var FLOOR_MAP   : ConsumableData  # +2 road tiles
var PRIMER      : ConsumableData  # +2 rerolls
# Revival
var SMELLING_SALTS : ConsumableData  # revive one fallen member with partial HP


func _ready() -> void:
	# Corpus
	MEAT       = _make("Meat",
		"Restores 5 CORP to one living party member.",
		"corpus", 5, false, true)
	BIG_MEAT   = _make("Big Meat",
		"Restores 15 CORP to one living party member.",
		"corpus", 15, false, true)
	JERKY      = _make("Jerky",
		"Restores 4 CORP mid-battle.",
		"corpus", 4, true, true)
	FEAST      = _make("Feast",
		"Restores 8 CORP to every living party member.",
		"corpus_all", 8, false, true)
	# AP
	CANDY      = _make("Candy",
		"Restores 3 AP to one party member who has AP.",
		"will", 3, false, true)
	SWEET      = _make("Sweet",
		"Restores 8 AP to one party member who has AP.",
		"will", 8, false, true)
	HARD_CANDY = _make("Hard Candy",
		"Restores 2 AP mid-battle.",
		"will", 2, true, true)
	BONBON     = _make("Bonbon",
		"Restores 4 AP to every party member who has AP.",
		"will_all", 4, false, true)
	# Utility
	FLOOR_MAP  = _make("Floor Map",
		"Grants +2 Ties.",
		"tie", 2, false, true)
	PRIMER     = _make("Primer",
		"Grants +2 Revisions.",
		"reprise", 2, false, true)
	SMELLING_SALTS = _make("Smelling Salts",
		"Revives one fallen party member with 1 CORP.",
		"revive", 1, true, true)


func _make(name: String, desc: String, effect: String,
		amount: int, in_battle: bool, in_dungeon: bool) -> ConsumableData:
	var d := ConsumableData.new()
	d.item_name        = name
	d.description      = desc
	d.item_type        = ItemData.ItemType.CONSUMABLE
	d.effect_type      = effect
	d.effect_amount    = amount
	d.usable_in_battle  = in_battle
	d.usable_in_dungeon = in_dungeon
	return d


## Add one stack of a consumable to the run's inventory.
## Stacks with existing entries of the same item.
func add_to_inventory(run: RunState, data: ConsumableData, count: int = 1) -> void:
	for inst in run.inventory:
		if inst.item_data == data:
			inst.stacks += count
			return
	var inst := ItemInstance.new()
	inst.item_data = data
	inst.stacks    = count
	run.inventory.append(inst)


## Use one stack on a specific party member (or whole party for non-targeted types).
## Returns true if used successfully.
func use_item(run: RunState, inst: ItemInstance,
		target: PartyMemberData = null) -> bool:
	if inst == null or inst.item_data == null:
		return false
	var data := inst.item_data as ConsumableData
	if data == null:
		return false
	# Context guard: check battle layer visibility.
	var battle_layer = Engine.get_main_loop().root.get_node_or_null("GameRoot/BattleLayer")
	var in_battle : bool = battle_layer != null and (battle_layer as CanvasLayer).visible
	if in_battle and not data.usable_in_battle:
		return false
	if not in_battle and not data.usable_in_dungeon:
		return false
	_apply_effect(run, data, target)
	inst.stacks -= 1
	if inst.stacks <= 0:
		run.inventory.erase(inst)
	return true


func _apply_effect(run: RunState, data: ConsumableData,
		target: PartyMemberData = null) -> void:
	match data.effect_type:
		"corpus":
			# Single-target: use target if provided, else first living member.
			var members := [target] if target != null else run.party_members
			for m in members:
				if (m as PartyMemberData).current_hp > 0:
					var cap : int = m.character.base_max_hp + m.bonus_max_hp
					m.current_hp = mini(m.current_hp + data.effect_amount, cap)
					_sync_actor_hp(m)
		"corpus_all":
			for m in run.party_members:
				if (m as PartyMemberData).current_hp > 0:
					var cap : int = m.character.base_max_hp + m.bonus_max_hp
					m.current_hp = mini(m.current_hp + data.effect_amount, cap)
					_sync_actor_hp(m)
		"will":
			var members := [target] if target != null else run.party_members
			for m in members:
				if (m as PartyMemberData).has_will():
					m.restore_will(data.effect_amount)
		"will_all":
			for m in run.party_members:
				if (m as PartyMemberData).has_will():
					m.restore_will(data.effect_amount)
		"revive":
			var members := [target] if target != null else run.party_members
			for m in members:
				if (m as PartyMemberData).current_hp <= 0:
					m.current_hp = data.effect_amount
					_sync_actor_hp(m)
					break  # single target only
		"reprise":
			run.reroll_charges += data.effect_amount
		"tie":
			run.road_tiles_remaining += data.effect_amount


## If a battle is currently active, find the BattleActor whose party_member
## matches `member` and sync its hp to match current_hp, then emit hp_changed.
func _sync_actor_hp(member: PartyMemberData) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var manager = tree.get_first_node_in_group("battle_manager")
	if manager == null:
		return
	for actor in manager.actors:
		if actor.party_member == member:
			actor.hp = member.current_hp
			actor.emit_signal("hp_changed")
			return
