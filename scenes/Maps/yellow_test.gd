extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	RenderingServer.global_shader_parameter_set("level_filter", Vector3(1.0, 1.0, 0.0))
