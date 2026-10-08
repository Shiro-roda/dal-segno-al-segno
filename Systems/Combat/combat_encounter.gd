class_name CombatEncounter
extends Area3D
## A fight waiting in the level. When the player walks in (or start() is called)
## it builds the party and enemy StatBlocks, spawns enemy bodies, hands the party
## bodies to a CombatSession, shows a CombatHUD, and cleans up afterwards.
##
## Optional Marker3D children choose where enemies stand, in order.

signal finished(victory: bool)
## XP was handed out after a win. `ready` lists the companions who can now level up.
signal xp_awarded(amount: int, ready: Array)

@export var enemies: Array[EnemyTemplate] = []
@export var auto_trigger := true
## Victory removes the encounter for good.
@export var one_shot := true
@export var enemy_spacing := 1.6
## Used when there's no CollisionShape3D child.
@export var auto_shape_size := Vector3(6.0, 2.0, 6.0)

var session: CombatSession

var _hud: CombatHUD
var _enemy_nodes: Array[Node3D] = []
var _templates: Array[EnemyTemplate] = []
var _done := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 1  # the player body is on layer 2
	body_entered.connect(_on_body_entered)
	if find_children("*", "CollisionShape3D", false, false).is_empty():
		var box := BoxShape3D.new()
		box.size = auto_shape_size
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position.y = 1.0
		add_child(shape)


func _on_body_entered(body: Node3D) -> void:
	if auto_trigger and body.is_in_group("party_leader"):
		start()


func start() -> void:
	if _done or (session != null and session.active):
		return
	_templates.clear()
	for t in enemies:
		if t != null:
			_templates.append(t)
	var party_blocks := _party_blocks()
	if party_blocks.is_empty() or _templates.is_empty():
		push_warning("CombatEncounter '%s': needs a party and at least one enemy." % name)
		return

	var enemy_blocks: Array = []
	for t in _templates:
		enemy_blocks.append(t.build_block(Rules.engine))
	_spawn_models()

	_set_followers_controlled(true)
	session = CombatSession.new()
	add_child(session)
	session.combat_ended.connect(_on_combat_ended)
	session.action_resolved.connect(_on_action_resolved)
	session.begin(party_blocks, enemy_blocks, Rules.engine, _party_bodies(), _enemy_nodes)
	for i in mini(session.enemies.size(), _templates.size()):
		var e := session.enemies[i]
		if _templates[i].attack_range > 0.0:
			e.attack_range = _templates[i].attack_range
		e.move_speed = _templates[i].move_speed

	_hud = CombatHUD.new()
	add_child(_hud)
	_hud.bind(session)


# ── party ────────────────────────────────────────────────────────────────────
func _party_blocks() -> Array:
	var out: Array = []
	for id in Rules.roster.active:
		var b := _block_for(id)
		if b == null:
			push_error("CombatEncounter: couldn't get a StatBlock for '%s'. Fix _block_for()." % id)
		else:
			out.append(b)
	return out


## ASSUMPTION: I don't remember how Rules/PartyRoster hands back the StatBlock that
## Rules.recruit() built. This tries a few likely method names. Open rules.gd,
## find recruit(), see where it stores the block, and replace this body with
## one direct call.
func _block_for(id: StringName) -> StatBlock:
	for source in [Rules.roster, Rules]:
		for method in ["get_block", "get_character", "get_stat_block"]:
			if source.has_method(method):
				var found: Variant = source.call(method, id)
				if found is StatBlock:
					return found
	return null


## The bodies for each active party member, in roster order. The first is the
## player; the rest are followers matched by character_id.
func _party_bodies() -> Array:
	var followers := {}
	for f in get_tree().get_nodes_in_group("party_follower"):
		followers[(f as PartyFollower).character_id] = f
	var out: Array = []
	var ids := Rules.roster.active
	for i in ids.size():
		if i == 0:
			out.append(get_tree().get_first_node_in_group("party_leader"))
		else:
			out.append(followers.get(ids[i]))
	return out


## While a fight runs, combat moves the followers, not the trail.
func _set_followers_controlled(on: bool) -> void:
	for f in get_tree().get_nodes_in_group("party_follower"):
		(f as PartyFollower).combat_controlled = on


# ── enemy bodies ─────────────────────────────────────────────────────────────
func _spawn_models() -> void:
	_enemy_nodes.clear()
	var markers := find_children("*", "Marker3D", false, false)
	var player := get_tree().get_first_node_in_group("party_leader") as Node3D
	for i in _templates.size():
		var node: Node3D = null
		var scene := _templates[i].model_scene
		if scene != null:
			node = scene.instantiate() as Node3D
		if node == null:
			node = _placeholder_body()
		add_child(node)
		if i < markers.size():
			node.global_position = (markers[i] as Node3D).global_position
		else:
			node.position = Vector3((i - (_templates.size() - 1) * 0.5) * enemy_spacing, 0.0, 0.0)
		if player != null:
			var look := Vector3(player.global_position.x, node.global_position.y, player.global_position.z)
			if node.global_position.distance_to(look) > 0.01:
				node.look_at(look, Vector3.UP)  # models face -Z
		_enemy_nodes.append(node)


## Every enemy needs a body to be positioned, so models are optional but bodies aren't.
func _placeholder_body() -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = CapsuleMesh.new()
	mesh.position.y = 1.0
	root.add_child(mesh)
	return root


func _on_action_resolved(_actor: Combatant, _result: Dictionary) -> void:
	for i in mini(session.enemies.size(), _enemy_nodes.size()):
		var n := _enemy_nodes[i]
		if n != null and is_instance_valid(n) and session.enemies[i].is_down():
			n.visible = false  # swap for a death animation later


# ── outcome ──────────────────────────────────────────────────────────────────
func _on_combat_ended(victory: bool) -> void:
	_set_followers_controlled(false)
	for n in _enemy_nodes:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_enemy_nodes.clear()
	if victory:
		var xp := 0
		for t in _templates:
			xp += t.xp_value
		if xp > 0:
			var lvready := Leveling.award_xp(Rules.roster, xp)
			session.say_event(&"xp_gained", {"amount": xp})
			xp_awarded.emit(xp, lvready)
		_done = one_shot
	else:
		# Placeholder: a real game-over flow goes here.
		GameController.show_start_screen.call_deferred()
	finished.emit(victory)
