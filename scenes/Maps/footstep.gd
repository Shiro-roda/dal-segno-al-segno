extends AudioStreamPlayer3D

@onready var player: CharacterBody3D = $"../../../Player"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if player.ken_model.anim.current_animation == "Action_003":
		if playing == false:
			playing = true
