extends Node3D

@onready var anim: AnimationPlayer = $AnimationPlayer


func play_anim(name: String):
	if anim.current_animation != name:
		anim.play(name)
