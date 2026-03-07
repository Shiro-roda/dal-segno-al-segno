extends Node

func _ready():
	var run = RunState.new()

	# Create dummy party for now
	var member = PartyMemberData.new()
	member.character = preload("res://resources/characters/kendall.tres")
	member.current_hp = member.character.base_max_hp

<<<<<<< Updated upstream
<<<<<<< Updated upstream
	run.party_members.append(member)
	run.party_members.append(member)
	run.party_members.append(member)

	GameController.start_new_run(run)

	# For testing, immediately start battle
	var encounter = preload("res://resources/encounters/test_encounter.tres")
	GameController.start_battle(encounter)
=======
	controller = get_tree().get_first_node_in_group("dungeon_controller")
>>>>>>> Stashed changes
=======
	controller = get_tree().get_first_node_in_group("dungeon_controller")
>>>>>>> Stashed changes
