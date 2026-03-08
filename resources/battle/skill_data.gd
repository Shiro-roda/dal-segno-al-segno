extends Resource
class_name SkillData

@export var skill_name : String = ""
@export var command_key : String = ""   # used to route in battle_manager
@export var description : String = ""
@export var will_cost : int = 0         # 0 = free / uses ammo instead
@export var ammo_cost : int = 0
