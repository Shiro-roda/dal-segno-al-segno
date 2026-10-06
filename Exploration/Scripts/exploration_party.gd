class_name ExplorationParty
extends Node3D
## Spawns followers for the active roster (Rules.roster). The first active
## character is the player-controlled leader (the Player scene in the level);
## everyone after them follows along the leader's trail. Rebuilds whenever the
## roster changes.
##
## Followers use CharacterSheet.model_scene, or a placeholder when it's empty.

const FOLLOWER_SCENE := preload("res://Exploration/Scenes/party_follower.tscn")
const FALLBACK_MODEL := preload("res://Exploration/Scenes/placeholder_model.tscn")

@export var follow_spacing := 1.4
## Test levels only: recruit three placeholder characters if the roster is empty.
@export var seed_test_roster := false

var _followers: Array[PartyFollower] = []


func _ready() -> void:
	if seed_test_roster and Rules.roster.active.is_empty():
		_seed_test_roster()
	Rules.roster.changed.connect(rebuild)
	rebuild()


func _exit_tree() -> void:
	if Rules.roster.changed.is_connected(rebuild):
		Rules.roster.changed.disconnect(rebuild)


func rebuild() -> void:
	for f in _followers:
		if is_instance_valid(f):
			f.queue_free()
	_followers.clear()

	var ids := Rules.roster.active
	for i in range(1, ids.size()):
		var sheet := Rules.roster.get_sheet(ids[i])
		var f := FOLLOWER_SCENE.instantiate() as PartyFollower
		f.character_id = ids[i]
		f.model_scene = sheet.model_scene if sheet != null and sheet.model_scene != null else FALLBACK_MODEL
		f.follow_distance = follow_spacing * i
		add_child(f)
		_followers.append(f)


func _seed_test_roster() -> void:
	var entries := [[&"kendall", "Kendall"], [&"hue", "Hue"], [&"indra", "Indra"]]
	for entry in entries:
		var sheet := CharacterSheet.new()
		sheet.id = entry[0]
		sheet.display_name = entry[1]
		Rules.recruit(sheet, true, entry[0] == &"kendall")
