# FlashlightDriver.gd
extends Node3D
@export var player_scene_name := "Player"     # root name of player scene instance
@export var flashlight_name := "Flashlight"   # name of the SpotLight3D node
@export var screen_quad_name := "ScreenQuad"  # name of the postprocess MeshInstance3D node

var spot: SpotLight3D
var mat: ShaderMaterial
var setup_done := false

func _ready():
	# Delay setup slightly to give instanced scenes time to appear
	await get_tree().process_frame
	_find_nodes()

func _find_nodes():
	# Try to find the player and flashlight
	var player = get_tree().get_root().find_child(player_scene_name, true, false)
	if player:
		spot = player.get_node_or_null(flashlight_name)
	else:
		push_warning("Player scene not found: " + player_scene_name)
		return

	var quad = get_tree().get_root().find_child(screen_quad_name, true, false)
	if quad:
		mat = quad.material_override
	else:
		push_warning("ScreenQuad not found: " + screen_quad_name)
		return

	if not mat:
		push_error("ScreenQuad has no material assigned!")
		return

	# Initialize shader parameters
	mat.set_shader_parameter("vision_mode", 0)
	mat.set_shader_parameter("hue_boost", 2.0)
	mat.set_shader_parameter("cone_range", 20.0)
	mat.set_shader_parameter("edge_softness", 0.03)

	setup_done = true
	print("✅ FlashlightDriver initialized successfully.")


func _process(_delta):
	if not setup_done:
		return
	if not spot or not mat:
		return

	var pos = spot.global_transform.origin
	var dir = -spot.global_transform.basis.z
	var angle = deg_to_rad(spot.spot_angle)

	mat.set_shader_parameter("flash_pos", pos)
	mat.set_shader_parameter("flash_dir", dir)
	mat.set_shader_parameter("flash_angle", angle)
