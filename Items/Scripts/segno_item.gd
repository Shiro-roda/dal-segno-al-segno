extends ItemData
class_name SegnoItem
# The Segno — a rare consumable save point.
# When used, takes a full snapshot of the current run state.
# If the party is defeated while a Segno snapshot exists, the run is restored
# to that snapshot exactly once (the snapshot is consumed on use).

func _init() -> void:
	item_name = "Segno"
	description = ""
	item_type = ItemData.ItemType.CONSUMABLE
