extends Node3D

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var head_ken: MeshInstance3D = $Kendall_rig_001/Skeleton3D/Head_001
@onready var flashlight: SpotLight3D = $Kendall_rig_001/Skeleton3D/Head_001/Flashlight



func play_anim(name: String):
	if anim.current_animation != name:
		anim.play(name)
