class_name RoomRest
extends Interactable
## The thing the player interacts with to take a short rest in a rest room. DungeonRoom
## adds one at the room's origin when the tile has a RestDef and the scene has none. A
## RoomRest placed in the scene works too: it finds the DungeonRoom it sits in.
##
## Interacting rests the whole active party: Anima comes back, and every character spends
## as many of their daily hit dice as they need, up to full Corpus. Nothing here asks the
## player to choose dice yet.

var room: DungeonRoom


func _ready() -> void:
	super._ready()
	room = _find_room()
	if room != null and room.day != null:
		var tile := room.day.tile_at(room.cell, TileDef.Clef.BASS)
		if tile != null and tile.def.rest != null and tile.def.rest.prompt != "":
			prompt = tile.def.rest.prompt
	interacted.connect(_on_interacted)


func _on_interacted(_who: Node3D) -> void:
	if room == null or room.day == null:
		return
	var roster := Rules.roster
	var spend := {}
	for id in roster.active:
		spend[id] = room.day.hit_dice_left(id, roster.get_block(id).level)
	var report := RoomFeatures.short_rest(room.day, room.cell, roster, spend)
	if not bool(report["ok"]):
		Notice.show_text(self, String(report["reason"]))
		return
	for id in roster.active:
		var sheet := roster.get_sheet(id)
		var who := sheet.display_name if sheet != null and sheet.display_name != "" else String(id)
		Notice.show_text(self, "%s: Anima +%d, Corpus +%d (%d hit dice spent)." % [
				who, int(report["anima"].get(id, 0)), int(report["healing"].get(id, 0)),
				int(report["dice_spent"].get(id, 0))])


func _find_room() -> DungeonRoom:
	var node := get_parent()
	while node != null:
		if node is DungeonRoom:
			return node as DungeonRoom
		node = node.get_parent()
	return null
