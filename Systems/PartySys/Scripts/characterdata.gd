extends Resource
class_name CharacterData

@export var display_name : String
## Short name used in battle log messages. Falls back to display_name if empty.
@export var log_name : String = ""
@export var description : String = ""

func get_log_name() -> String:
	return log_name if log_name != "" else display_name
@export var base_max_hp : int
@export var base_attack : int
@export var base_flat_defense : int = 0
@export var base_max_will : int = 0  # 0 means this character uses ammo, not will
@export var tempo: int = 10
@export var exp_yield : int = 3  # exp granted to each surviving party member on kill
@export var body_parts : Array[BodyPartData]
@export var battle_scene : PackedScene
## Optional skill loadout for data-driven enemies (used by EnemyActor).
@export var skills : Array[SkillData] = []

# Optional: pre-built PartyMemberData for boss enemies that use support actor scripts.
# Assign via BossBuilder so the actor has will, skill unlocks, etc.
var boss_party_member : PartyMemberData = null
