extends AudioStreamPlayer3D
@onready var player: CharacterBody3D = $"."


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if player.current_channel == 1 or 2:
		volume_db = -80.0
	elif player.current_channel == 2 or player.flashlight.light_energy == 0:
		volume_db = 0.0
