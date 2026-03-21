extends Node

signal event_finished

func _ready():
	print("Event started!")

	await get_tree().create_timer(2.0).timeout

	emit_signal("event_finished")
