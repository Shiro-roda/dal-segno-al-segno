class_name GrantBonusPicks
extends Mechanic
## Choosing the feat grants extra picks drawn from a list wider than the character's own pool.
## Virtuoso: kind = canto, count = 1, pool_folder = your Cantos folder.

## LevelUpOffer.CANTO or LevelUpOffer.CANTRIP.
@export var kind: StringName = &"canto"
## Picks granted each time the feat is chosen (a stacked feat grants again).
@export var count: int = 1
## Every ActionDef in this folder is a candidate. Not recursive.
@export_dir var pool_folder: String = ""
## Extra candidates, in addition to the folder.
@export var pool: Array[ActionDef] = []
## Candidates carrying any of these tags are never offered, in addition to the
## enemy-only tag, which is always excluded.
@export var exclude_tags: PackedStringArray = PackedStringArray()

## Actions only enemies may use (Banality). Never offered to the player's party.
const ENEMY_TAG := "enemy"


func on_chosen(sheet: CharacterSheet) -> void:
	for _i in count:
		sheet.bonus_picks.append(self)


## Everything the character could take right now.
func build_options(sheet: CharacterSheet, engine: RulesEngine) -> Array:
	var out: Array = []
	for action in _candidates():
		if Leveling.canto_eligible(action, sheet, engine, sheet.level):
			out.append(action)
	return out


func _candidates() -> Array:
	var found: Array = []
	for action in pool:
		_consider(action, found)
	if pool_folder != "":
		for file in DirAccess.get_files_at(pool_folder):
			var name := file.trim_suffix(".remap")  # exported builds rename resources
			if name.ends_with(".tres") or name.ends_with(".res"):
				_consider(load(pool_folder.path_join(name)) as ActionDef, found)
	return found


func _consider(action: ActionDef, found: Array) -> void:
	if action == null or found.has(action):
		return
	if kind == &"canto" and not action.is_canto():
		return
	if kind == &"cantrip" and not action.is_cantrip():
		return
	for tag in action.tags:
		if tag == ENEMY_TAG or exclude_tags.has(tag):
			return
	found.append(action)
