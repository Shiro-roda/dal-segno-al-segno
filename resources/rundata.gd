extends Resource
class_name RunState

@export var party_members : Array[PartyMemberData] = []
@export var inventory : Array[ItemInstance] = []

# The one support currently active in the party.
# Set during the companion-select event at dungeon start.
var active_support : CharacterData = null

# Supports not yet recruited. Populated by gamecontrol before dungeon start.
# Each entry is a CharacterData resource.
var available_supports : Array = []

var ammo : int = 8
var max_ammo : int = 16

var run_flags : Dictionary = {}
var run_modifiers : Array = []

func spend_ammo(amount: int) -> bool:
	if ammo < amount:
		return false
	ammo -= amount
	return true

func restore_ammo(amount: int) -> void:
	ammo = min(ammo + amount, max_ammo)
