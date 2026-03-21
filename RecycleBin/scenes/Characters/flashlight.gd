@tool
extends SpotLight3D

func _process(_delta):
	RenderingServer.global_shader_parameter_set("flash_pos", global_position)
	RenderingServer.global_shader_parameter_set("flash_dir", -global_basis.z)
	RenderingServer.global_shader_parameter_set("flash_angle", deg_to_rad(spot_angle))
