extends Resource
class_name CharacterData

@export var display_name : String
## Short name used in battle log messages. Falls back to display_name if empty.
@export var log_name : String = ""
@export var description : String = ""
## Colour used to identify this character in UI elements (tempo score, etc.).
@export var theme_color : Color = Color(0.88, 0.83, 0.74, 1.0)

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

## Enemy chatter lines. Populated for enemy CharacterData resources.
## EnemyActor copies these arrays at spawn time.
## chatter_attack  — said when using an attack skill
## chatter_special — said when using a special skill
## chatter_support — said when using a support skill
## chatter_hurt    — said when taking damage (while still alive)
## chatter_low_hp  — said once when HP first drops below 50%
## chatter_kill    — said after killing a player character
## chatter_die     — said when this enemy is defeated
@export var chatter_attack  : Array[String] = []
@export var chatter_special : Array[String] = []
@export var chatter_support : Array[String] = []
@export var chatter_hurt    : Array[String] = []
@export var chatter_low_hp  : Array[String] = []
@export var chatter_kill    : Array[String] = []
@export var chatter_die     : Array[String] = []
@export var chatter_turn_start : Array[String] = []

# Optional: pre-built PartyMemberData for boss enemies that use support actor scripts.
# Assign via BossBuilder so the actor has will, skill unlocks, etc.
var boss_party_member : PartyMemberData = null
