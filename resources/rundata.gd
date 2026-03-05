extends Resource
class_name RunState

@export var party_members : Array[PartyMemberData] = []
@export var inventory : Array[ItemInstance] = []

var run_flags : Dictionary = {}
var run_modifiers : Array = []
