extends Resource
class_name PartyMemberData

@export var character : CharacterData

var current_hp : int
var bonus_attack : int = 0
var bonus_max_hp : int = 0
var temporary_traits : Array
var equipment : Dictionary # slot_name -> ItemInstance
var status_effects : Array
