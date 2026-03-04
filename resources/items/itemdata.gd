extends Resource
class_name ItemData

@export var item_name : String
@export var description : String
@export var item_type : ItemType
@export var effect : ItemEffectData

enum ItemType {
	CONSUMABLE,
	EQUIPMENT,
	PASSIVE
}
