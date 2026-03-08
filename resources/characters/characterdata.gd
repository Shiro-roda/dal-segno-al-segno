extends Resource
class_name CharacterData

@export var display_name : String
@export var base_max_hp : int
@export var base_attack : int
@export var base_max_will : int = 0  # 0 means this character uses ammo, not will
@export var tempo: int = 10
@export var body_parts : Array[BodyPartData]
@export var battle_scene : PackedScene
