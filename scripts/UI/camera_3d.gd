extends Camera3D

@export var target_path: NodePath
@export var smoothing_speed: float = 5.0

var target: Node3D

func _ready() -> void:
	target = get_node_or_null(target_path)

func _process(delta: float) -> void:
	if target:
		# Smoothly interpolate position
		global_position = global_position.lerp(target.global_position, smoothing_speed * delta)
