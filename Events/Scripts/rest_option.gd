extends Resource
class_name RestOption

# Option name shown as the button label (e.g. "Rest", "Pray", "Scavenge")
@export var option_name : String = ""

# Flavour description shown beneath the name on the card
@export var description : String = ""

# Effect type: "hp", "will", "ammo", "segno"
# "segno" grants the party one Segno consumable item.
@export var type : String = "hp"

# Fixed value to restore. Set to -1 to use the standard random roll instead.
@export var val_override : int = -1
