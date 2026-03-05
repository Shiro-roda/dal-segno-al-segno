extends Node

func _ready():

	# --- Create Run ---
	var run = RunState.new()

	var member = PartyMemberData.new()
	member.character = preload("res://resources/characters/kendall.tres")
	member.current_hp = member.character.base_max_hp

	run.party_members.append(member)
	run.party_members.append(member)
	run.party_members.append(member)

	GameController.start_new_run(run)

	# --- Create Dungeon ---
	var dungeon_data = preload("res://resources/dungeons/test_dungeon.tres")

	var controller : DungeonController = $DungeonController
	controller.start_dungeon(run, dungeon_data)
