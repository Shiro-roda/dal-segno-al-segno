extends AudioStreamPlayer3D

@onready var player: CharacterBody3D = %Player
@onready var flashlight: SpotLight3D = $Player/ken_model_test11/Kendall_rig_001/Skeleton3D/Head_001/Flashlight

func _ready() -> void:
	play()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:

	if (player.current_channel == 0 or 2) and flashlight.light_energy > 0:
		self.volume_db = -100.0
	elif player.current_channel == 1 or flashlight.light_energy == 0:
		self.volume_db = 50.0
