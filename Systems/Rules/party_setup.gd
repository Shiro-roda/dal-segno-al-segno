class_name PartySetup
extends RefCounted
## Builds the roster from CharacterSheet resources.
##
## For testing, recruit_all() puts every sheet in a folder on the roster, with the
## player character (the sheet that sets is_player) first so they lead the active
## party. In the real game, call Rules.recruit() as characters join instead.

const DEFAULT_DIR := "res://Characters/Resources"


## Wipes the roster and every registered actor. Call before starting a new run.
static func reset() -> void:
	Rules.roster = PartyRoster.new(Rules.engine)
	Rules.actors.clear()


## Every CharacterSheet in `dir_path`, sorted by file name.
static func load_sheets(dir_path: String = DEFAULT_DIR) -> Array[CharacterSheet]:
	var out: Array[CharacterSheet] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("PartySetup: can't open %s." % dir_path)
		return out
	var files := Array(dir.get_files())
	files.sort()
	for f: String in files:
		# Exported builds list resources as "name.tres.remap".
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var sheet := load(dir_path.path_join(file)) as CharacterSheet
		if sheet != null:
			out.append(sheet)
	return out


## Resets the roster, then recruits every sheet in the folder. Returns how many.
static func recruit_all(dir_path: String = DEFAULT_DIR) -> int:
	var sheets := load_sheets(dir_path)
	if sheets.is_empty():
		push_warning("PartySetup: no CharacterSheets found in %s." % dir_path)
		return 0
	var player: CharacterSheet = null
	for s in sheets:
		if s.is_player:
			player = s
			break
	if player == null:
		player = sheets[0]
		push_warning("PartySetup: no sheet sets is_player; using '%s' as the player." % player.id)
	reset()
	Rules.recruit(fresh_copy(player), true, true)
	for s in sheets:
		if s != player:
			Rules.recruit(fresh_copy(s), true, false)
	return sheets.size()


## A copy whose lists and dictionaries are its own. A loaded resource is shared
## and cached, so recruiting it directly would let a level-up in one run leak
## into the next. The resources inside (items, feats, actions) stay shared.
static func fresh_copy(sheet: CharacterSheet) -> CharacterSheet:
	var copy := sheet.duplicate() as CharacterSheet
	copy.scores = sheet.scores.duplicate()
	copy.skill_ranks = sheet.skill_ranks.duplicate()
	copy.known_actions = sheet.known_actions.duplicate()
	copy.feats = sheet.feats.duplicate()
	copy.equipment = sheet.equipment.duplicate()
	return copy
