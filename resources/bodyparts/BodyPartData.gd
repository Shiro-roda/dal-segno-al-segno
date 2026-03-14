extends Resource
class_name BodyPartData

@export var part_name : String
@export var required_removed_mask : int = 0
@export var base_visible : bool = false
@export var damage_multiplier : float = 1.0
@export var is_cognitohazard : bool = false

var already_seen : bool = false
var encased      : bool = false


func apply_status(effect_id: String, _duration: int = 0) -> void:
	if effect_id == "encased":
		encased = true


func clear_encased() -> void:
	encased = false
