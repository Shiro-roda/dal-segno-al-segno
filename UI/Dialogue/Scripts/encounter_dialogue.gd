extends Resource
class_name EncounterDialogue

# Ordered list of lines to display. Lines with failing conditions are skipped.
@export var lines : Array[DialogueLine] = []
