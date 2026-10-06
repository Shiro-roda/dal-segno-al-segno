class_name PlayerLink
extends Node
## Component for the player (child of the CharacterBody3D), in the same spirit
## as CameraLink. Adds, without touching player.gd:
##   - joins groups "party_leader" (the body) and "party_link" (this node)
##   - places the player at the spawn point GameController.pending_spawn names
##   - interaction: nearest Interactable in front, on the "interact" action
##   - locks the player's controls while a Dialogic timeline runs
##   - records a breadcrumb trail that PartyFollowers walk along

signal interaction_available(target: Interactable)
signal interaction_cleared

@export var interact_radius := 1.1
@export var interact_reach := 1.0
@export var trail_step := 0.15
@export var trail_max_points := 400

var body: CharacterBody3D

var _locks := 0
var _trail: Array[Vector3] = []
var _nearby: Array[Interactable] = []


func _ready() -> void:
	body = get_parent() as CharacterBody3D
	if body == null:
		push_warning("PlayerLink must be a child of a CharacterBody3D.")
		return
	add_to_group("party_link")
	body.add_to_group("party_leader")
	_build_interact_area()
	_place_at_spawn()
	_trail.push_front(body.global_position)
	_connect_dialogic()


# ── Control locking (dialogue, menus, cutscenes) ─────────────────────────────
func lock_controls() -> void:
	_locks += 1
	if body != null:
		body.set("controls_enabled", false)


func unlock_controls() -> void:
	_locks = maxi(_locks - 1, 0)
	if _locks == 0 and body != null:
		body.set("controls_enabled", true)


func is_locked() -> bool:
	return _locks > 0


# ── Breadcrumb trail for followers (newest first) ────────────────────────────
func _physics_process(_delta: float) -> void:
	if body == null:
		return
	if _trail.is_empty() or body.global_position.distance_to(_trail[0]) >= trail_step:
		_trail.push_front(body.global_position)
		if _trail.size() > trail_max_points:
			_trail.pop_back()


## Position `distance` metres back along the path the player has walked.
func get_trail_point(distance: float) -> Vector3:
	var remaining := distance
	var prev := body.global_position
	for p in _trail:
		var seg := prev.distance_to(p)
		if seg > 0.0 and seg >= remaining:
			return prev.lerp(p, remaining / seg)
		remaining -= seg
		prev = p
	return prev


# ── Interaction ──────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if is_locked() or not event.is_action_pressed("interact"):
		return
	var target := _closest_interactable()
	if target != null:
		target.interact(body)
		get_viewport().set_input_as_handled()


func _closest_interactable() -> Interactable:
	var best: Interactable = null
	var best_d := INF
	for i in _nearby:
		if not is_instance_valid(i):
			continue
		var d := body.global_position.distance_squared_to(i.global_position)
		if d < best_d:
			best_d = d
			best = i
	return best


func _on_area_entered(area: Area3D) -> void:
	if area is Interactable and not _nearby.has(area):
		_nearby.append(area)
		interaction_available.emit(area)


func _on_area_exited(area: Area3D) -> void:
	if area is Interactable:
		_nearby.erase(area)
		if _closest_interactable() == null:
			interaction_cleared.emit()


func _build_interact_area() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = interact_radius
	var shape := CollisionShape3D.new()
	shape.shape = sphere
	shape.position = Vector3(0.0, 1.0, -interact_reach)  # forward is -Z
	var area := Area3D.new()
	area.name = "InteractArea"
	area.collision_layer = 0
	area.collision_mask = 1 << 2  # Interactables live on layer 3
	area.add_child(shape)
	area.area_entered.connect(_on_area_entered)
	area.area_exited.connect(_on_area_exited)
	# The parent is still setting up its children during our _ready.
	body.add_child.call_deferred(area)


# ── Spawning ─────────────────────────────────────────────────────────────────
func _place_at_spawn() -> void:
	var wanted: StringName = GameController.pending_spawn
	if wanted == &"":
		wanted = &"default"
	var points := get_tree().get_nodes_in_group("spawn_point")
	var chosen: Node3D = null
	for n in points:
		if n is Node3D and n.name == wanted:
			chosen = n
			break
	if chosen == null and wanted == &"default" and not points.is_empty():
		chosen = points[0] as Node3D
	if chosen != null:
		body.global_position = chosen.global_position
		body.global_rotation.y = chosen.global_rotation.y
	GameController.pending_spawn = &""


# ── Dialogic ─────────────────────────────────────────────────────────────────
func _connect_dialogic() -> void:
	var dialogic := get_node_or_null("/root/Dialogic")
	if dialogic == null:
		return
	if dialogic.has_signal("timeline_started"):
		dialogic.connect("timeline_started", lock_controls)
	if dialogic.has_signal("timeline_ended"):
		dialogic.connect("timeline_ended", unlock_controls)
