class_name DungeonRoom
extends Node3D
## Root script of every dungeon room scene: the scene a Bass Clef TileDef points at in
## its `scene` field. Each room is its own enclosed scene, loaded alone, so make it as
## large on the inside as you like. Easiest start: inherit Systems/World/Rooms/room_base.tscn.
##
## On load it reads the run (GameController.day_cycle) and the cell it stands for, then:
##   - seals every RoomDoor that has no standing room behind it
##   - turns the day's living remnants here into one CombatEncounter
##   - adds a RoomExit if this is the exit tile's room and the scene has none
##   - puts the party where it belongs: at the Segno on the first arrival, otherwise
##     at the door they came through
##
## Optional nodes by name:
##   SegnoSpawn      Node3D  where the party appears when the Segno is in this room.
##                           Default: the room's origin.
##   EncounterPoint  Node3D  where the fight happens. Its Marker3D children become the
##                           enemies' standing spots. Default: the room's origin.
##
## Run a room scene on its own (F6) to try it out: with no expedition under way every
## door stays open, nothing spawns, and the player starts at its own spawn point.

## The fight triggers when the party walks into a box this big around the encounter point.
@export var encounter_trigger_size := Vector3(12.0, 3.0, 12.0)
## Distance from the room's origin to its walls (x for east/west, y for north/south).
## Only used to place a default door where a room has none on a side that needs one.
@export var room_half_size := Vector2(12.5, 12.5)
## Add a RoomExit to the exit tile's room if the scene doesn't have its own.
@export var auto_exit := true
## One debug label with day, carried loot and remnants left.
@export var debug_overlay := true

var day: DayCycle
## The grid cell this room stands for.
var cell := DayCycle.ORIGIN

var _doors: Array[RoomDoor] = []
var _encounters: Array[CombatEncounter] = []
var _label: Label


func _ready() -> void:
	add_to_group("dungeon_room")
	for node in get_tree().get_nodes_in_group("room_door"):
		if is_ancestor_of(node):
			var door := node as RoomDoor
			door.room = self
			_doors.append(door)
	_fix_door_sides()
	day = GameController.day_cycle
	if day == null or day.phase != DayCycle.Phase.EXPEDITION:
		return  # opened on its own: leave everything as authored
	cell = GameController.bass_cell
	_seal_doors()
	_spawn_encounters()
	_ensure_exit()
	_build_overlay()
	_place_party.call_deferred()


## False while a fight is running; doors and the exit wait.
func can_leave() -> bool:
	return not is_fighting()


func is_fighting() -> bool:
	for e in _encounters:
		if is_instance_valid(e) and e.session != null and e.session.active:
			return true
	return false


# ------------------------------------------------------------------- doors

## A RoomDoor's `side` defaults to NORTH, so a door dropped into a wall and never set
## would pass for the north door and open or seal the wrong wall. Where a door sits is the
## truth: if its position says a different wall than its `side`, trust the position.
func _fix_door_sides() -> void:
	for door in _doors:
		var offset := door.global_position - global_position
		if Vector2(offset.x, offset.z).length() < 1.0:
			continue  # at the room's centre: nothing to infer from
		var actual: int
		if absf(offset.x) > absf(offset.z):
			actual = DayCycle.Side.EAST if offset.x > 0.0 else DayCycle.Side.WEST
		else:
			actual = DayCycle.Side.SOUTH if offset.z > 0.0 else DayCycle.Side.NORTH
		if int(door.side) != actual:
			push_warning("DungeonRoom '%s': door '%s' is on the %s wall but says %s. Using the wall." % [
					name, door.name, DayCycle.Side.keys()[actual], DayCycle.Side.keys()[int(door.side)]])
			door.side = actual as DayCycle.Side


func _seal_doors() -> void:
	var open := day.open_sides(cell)
	_add_missing_doors(open)
	for door in _doors:
		door.set_sealed(not open.has(int(door.side)))


## A neighbouring room with no door facing it would be unreachable, so any side that
## needs a door and doesn't have one gets a default doorway on the wall line given by
## `room_half_size`. Author a RoomDoor of your own on that side to place it properly.
func _add_missing_doors(open: Array[int]) -> void:
	for side in open:
		var has_door := false
		for door in _doors:
			if int(door.side) == side:
				has_door = true
				break
		if has_door:
			continue
		push_warning("DungeonRoom '%s': no RoomDoor on side %s, but a room lies that way. Added a default one." % [
				name, DayCycle.Side.keys()[side]])
		var door := RoomDoor.new()
		door.name = "AutoDoor%s" % DayCycle.Side.keys()[side].capitalize()
		door.side = side as DayCycle.Side
		add_child(door)
		match side:
			DayCycle.Side.NORTH:
				door.position = Vector3(0.0, 0.0, -room_half_size.y)
			DayCycle.Side.SOUTH:
				door.position = Vector3(0.0, 0.0, room_half_size.y)
			DayCycle.Side.EAST:
				door.position = Vector3(room_half_size.x, 0.0, 0.0)
				door.rotation_degrees.y = 90.0
			DayCycle.Side.WEST:
				door.position = Vector3(-room_half_size.x, 0.0, 0.0)
				door.rotation_degrees.y = 90.0
		door.room = self
		_doors.append(door)


# --------------------------------------------------------------- encounters

## Everything still alive here fights as one encounter.
func _spawn_encounters() -> void:
	var list: Array[EnemyTemplate] = []
	var ids: Array[int] = []
	for s: Dictionary in day.spawns:
		if bool(s["alive"]) and s["pos"] == cell:
			var scaled := (s["template"] as EnemyTemplate).duplicate() as EnemyTemplate
			scaled.level = int(s["level"])
			list.append(scaled)
			ids.append(int(s["id"]))
	if list.is_empty():
		return
	var encounter := CombatEncounter.new()
	encounter.name = "Encounter"
	encounter.enemies = list
	encounter.auto_shape_size = encounter_trigger_size
	var point := get_node_or_null("EncounterPoint") as Node3D
	if point != null:
		for child in point.get_children():
			if child is Marker3D:
				var spot := Marker3D.new()
				spot.position = (child as Marker3D).position
				encounter.add_child(spot)
	add_child(encounter)
	encounter.global_position = point.global_position if point != null else global_position
	encounter.finished.connect(_on_encounter_finished.bind(ids))
	encounter.xp_awarded.connect(_on_xp_awarded)
	_encounters.append(encounter)


func _on_encounter_finished(victory: bool, ids: Array) -> void:
	if victory:
		for id in ids:
			day.record_kill(int(id))
	else:
		# CombatEncounter already sends the game back to the start screen.
		day.defeat()
	_update_overlay()


## Level-ups are spent in the party menu (TAB), not forced on the player. Characters set
## to pick automatically (CharacterSheet.auto_pick_recommended) level up right here from
## their recommended picks; for everyone else this only says who has earned one.
func _on_xp_awarded(_amount: int, ready_ids: Array) -> void:
	var names: Array[String] = []
	var auto_names: Array[String] = []
	for id in ready_ids:
		var sheet := Rules.roster.get_sheet(id)
		if sheet == null or not Leveling.can_level_up(sheet):
			continue
		var who := sheet.display_name if sheet.display_name != "" else String(id)
		if sheet.auto_pick_recommended \
				and Leveling.auto_resolve(Rules.roster, Leveling.build_offer(Rules.roster, id)):
			auto_names.append("%s (level %d)" % [who, sheet.level])
		else:
			names.append(who)
	if not auto_names.is_empty():
		Notice.show_text(self, "Levelled up: %s." % ", ".join(auto_names))
	if not names.is_empty():
		Notice.show_text(self, "%s can level up. Open the party menu (TAB)." % ", ".join(names))


# --------------------------------------------------------------------- exit

func _ensure_exit() -> void:
	var tile := day.tile_at(cell, TileDef.Clef.BASS)
	if not auto_exit or tile == null or not tile.def.is_exit:
		return
	for node in get_tree().get_nodes_in_group("room_exit"):
		if is_ancestor_of(node):
			return  # the scene brings its own
	var exit_zone := RoomExit.new()
	exit_zone.name = "RoomExit"
	add_child(exit_zone)
	exit_zone.global_position = global_position


# ------------------------------------------------------------------ arrival

func _place_party() -> void:
	var link := _party_link()
	if link != null:
		link.teleport_to(_arrival_point())


## Through a door: the matching door on the opposite side. Otherwise (the Segno
## spawn): SegnoSpawn, or the origin.
func _arrival_point() -> Vector3:
	var side := GameController.arrival_side
	if side >= 0:
		for door in _doors:
			if int(door.side) == side:
				return door.arrival_point()
	var spawn := get_node_or_null("SegnoSpawn") as Node3D
	if spawn != null:
		return spawn.global_position
	return global_position + Vector3(0.0, 0.1, 0.0)


## The PlayerLink in this room. The previous room may still be queued for deletion,
## so asking the group for "the first" one could return its ghost.
func _party_link() -> PlayerLink:
	for node in get_tree().get_nodes_in_group("party_link"):
		if is_ancestor_of(node):
			return node as PlayerLink
	return null


# ------------------------------------------------------------ debug overlay

func _build_overlay() -> void:
	if not debug_overlay:
		return
	var layer := CanvasLayer.new()
	layer.layer = 10
	_label = Label.new()
	_label.position = Vector2(12, 12)
	layer.add_child(_label)
	add_child(layer)
	_update_overlay()


func _update_overlay() -> void:
	if _label == null or day == null:
		return
	var carried: Array[String] = []
	for key in day.carried_loot:
		carried.append("%s %d" % [key, int(day.carried_loot[key])])
	_label.text = "Day %d  room (%d, %d)\nCarried: %s\nRemnants left: %d" % [
			day.day, cell.x, cell.y, ", ".join(carried) if not carried.is_empty() else "-",
			day.remaining()]
