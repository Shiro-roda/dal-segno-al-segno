# dungeon_scene.gd
extends Node

var controller : DungeonController

func _ready():

	await get_tree().process_frame

	while controller == null:

		await get_tree().process_frame
		controller = get_tree().get_first_node_in_group("dungeon_controller")



	if GameController.current_run == null:

		var run = RunState.new()

		var member = PartyMemberData.new()
		member.character = preload("res://resources/characters/kendall.tres")
		member.current_hp = member.character.base_max_hp

		run.party_members.append(member)
		member = PartyMemberData.new()
		member.character = preload("res://resources/characters/kendall.tres")
		member.current_hp = member.character.base_max_hp
		run.party_members.append(member)
		member = PartyMemberData.new()
		member.character = preload("res://resources/characters/kendall.tres")
		member.current_hp = member.character.base_max_hp
		run.party_members.append(member)

		GameController.start_new_run(run)

		var dungeon_data = preload("res://resources/dungeons/test_dungeon.tres")

		await get_tree().process_frame
	
		


		
		
		if controller:
			controller.start_dungeon(run, dungeon_data)
