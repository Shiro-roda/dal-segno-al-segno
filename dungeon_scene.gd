# dungeon_scene.gd
extends Node

var controller : DungeonController

func _ready():

	await get_tree().process_frame

	controller = get_tree().get_first_node_in_group("dungeon_controller")
