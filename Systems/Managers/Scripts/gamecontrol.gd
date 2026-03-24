extends Node
class_name GameControl

static var current_run : RunState
static var current_dungeon_run : DungeonRunState

## Set to true once the player has completed the tutorial battle.
## Persists for the session; reset only on a full game restart.
static var tutorial_complete : bool = false

var dungeon_layer
var battle_layer
var event_layer
var world_layer

var battle_manager
var dungeon_controller



func _ready():

	await _wait_for_layers()

	dungeon_layer.visible = true
	battle_layer.visible = false
	event_layer.visible = false

	await _wait_for_controllers()

	_show_start_screen()


func _wait_for_layers():

	while dungeon_layer == null or battle_layer == null or event_layer == null or world_layer == null:

		await get_tree().process_frame

		dungeon_layer = get_tree().get_first_node_in_group("dungeon_layer")
		battle_layer = get_tree().get_first_node_in_group("battle_layer")
		event_layer = get_tree().get_first_node_in_group("event_layer")
		world_layer = get_tree().get_first_node_in_group("world_layer")


func _wait_for_controllers():

	while dungeon_controller == null:
		await get_tree().process_frame
		dungeon_controller = get_tree().get_first_node_in_group("dungeon_controller")


func start_new_game():
	_begin_game_flow()


func _show_start_screen() -> void:
	clear_layer(event_layer)
	var screen := preload("res://UI/2D/Scenes/start_screen.tscn").instantiate()
	event_layer.add_child(screen)
	dungeon_layer.visible = false
	battle_layer.visible  = false
	world_layer.visible   = false
	event_layer.visible   = true
	screen.play_intro.connect(func():
		clear_layer(event_layer)
		event_layer.visible = false
		_start_intro_scene())
	screen.skip_intro.connect(func():
		clear_layer(event_layer)
		event_layer.visible = false
		_begin_game_flow())


## Load the intro level into the world layer.
func _start_intro_scene() -> void:
	load_world_scene("res://Environments/Levels/Scenes/white_test.tscn")


## Returns the SubViewport inside WorldLayer.
func _get_world_viewport() -> SubViewport:
	return world_layer.get_node("SubViewportContainer/SubViewport") as SubViewport


## Load a world level scene into the SubViewport inside WorldLayer.
## The SubViewport has its own camera context — no conflict with the dungeon camera.
func load_world_scene(scene_path: String) -> void:
	var vp := _get_world_viewport()
	for c in vp.get_children(): c.queue_free()
	var level := (load(scene_path) as PackedScene).instantiate()
	vp.add_child(level)
	dungeon_layer.visible = false
	battle_layer.visible  = false
	event_layer.visible   = false
	world_layer.visible   = true


## Suppress or restore the dungeon map's camera so it doesn't fight
## with cameras inside world-layer level scenes.
func _set_dungeon_camera_active(active: bool) -> void:
	var map := get_tree().get_first_node_in_group("dungeon_map_3d")
	if map == null:
		return
	var cam := map.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if cam:
		cam.current = active
		cam.set_process(active)
		cam.set_physics_process(active)
	var host := map.get_node_or_null("CameraPivot/Camera3D/PhantomCameraHost")
	if host:
		host.set_process(active)
		host.set_physics_process(active)


## Load world level scene into the world layer.
## Build the run and proceed to tutorial or companion select.
func _begin_game_flow() -> void:
	var vp := _get_world_viewport()
	for c in vp.get_children(): c.queue_free()
	world_layer.visible = false
	var run := RunState.new()
	var member := PartyMemberData.new()
	member.init_from_character(preload("res://Characters/Resources/Party/kendall.tres"))
	run.party_members.append(member)
	run.available_supports = [
		preload("res://Characters/Resources/Party/hue.tres"),
		preload("res://Characters/Resources/Party/indra.tres"),
		preload("res://Characters/Resources/Party/vritra.tres"),
	]
	start_new_run(run)
	if not tutorial_complete:
		_start_tutorial_battle(run)
		return
	var select_scene := preload("res://Events/Scenes/companion_select.tscn")
	var dungeon_data  := preload("res://Dungeons/Resources/test_dungeon.tres")
	_start_companion_select(select_scene, dungeon_data)


func _start_tutorial_battle(run: RunState) -> void:
	dungeon_layer.visible = false
	event_layer.visible = false
	battle_layer.visible = true
	_set_dungeon_map_visible(false)
	clear_layer(battle_layer)

	var battle_scene := preload("res://GameRoots/Scenes/battle_scene.tscn").instantiate()
	battle_layer.add_child(battle_scene)

	var manager := battle_scene.get_node("BattleManager")
	var context := BattleContext.new()
	context.encounter = preload("res://Encounters/Resources/Tutorial/tutorial.tres")
	context.run_state  = run
	manager.start_battle_with_context(context)

	manager.battle_finished.connect(_on_tutorial_battle_finished)


func _on_tutorial_battle_finished(_victory: bool, _exp: Dictionary = {}, _lvl: Dictionary = {}) -> void:
	tutorial_complete = true
	AudioManagerAuto.reset_ambience()
	AudioManagerAuto.fade_out_bgm()
	clear_layer(battle_layer)
	battle_layer.visible = false

	var select_scene := preload("res://Events/Scenes/companion_select.tscn")
	var dungeon_data  := preload("res://Dungeons/Resources/test_dungeon.tres")
	_start_companion_select(select_scene, dungeon_data)


func _start_companion_select(select_scene: PackedScene, dungeon_data: DungeonData) -> void:
	clear_layer(event_layer)
	var select := select_scene.instantiate()
	event_layer.add_child(select)
	dungeon_layer.visible = false
	battle_layer.visible = false
	world_layer.visible = false
	event_layer.visible = true
	select.event_finished.connect(func():
		clear_layer(event_layer)
		event_layer.visible = false
		start_dungeon(dungeon_data)
	)


func start_new_run(run : RunState):
	current_run = run


func _set_dungeon_map_visible(visible: bool):
	var map_3d = get_tree().get_first_node_in_group("dungeon_map_3d")
	if map_3d:
		map_3d.visible = visible
		var host = map_3d.get_node_or_null("CameraPivot/Camera3D/PhantomCameraHost")
		if host:
			host.set_process(visible)
			host.set_physics_process(visible)
		var cam = map_3d.get_node_or_null("CameraPivot/Camera3D")
		if cam:
			cam.current = visible


func _reset_channel_shader() -> void:
	# Restore full RGB when leaving the dungeon.
	var mesh := get_tree().root.get_node_or_null("GameRoot/TVOverlay/MeshInstance2D")
	if mesh:
		var mat := mesh.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("channel_strength", Vector3(1.0, 1.0, 1.0))
	var map := get_tree().get_first_node_in_group("dungeon_map_3d")
	if map and map.has_method("reset_channels"):
		map.reset_channels()


func start_battle(encounter, dungeon_run_state: DungeonRunState = null):

	_reset_channel_shader()
	dungeon_layer.visible = false
	event_layer.visible = false
	battle_layer.visible = true
	_set_dungeon_map_visible(false)

	clear_layer(battle_layer)

	var battle_scene = preload("res://GameRoots/Scenes/battle_scene.tscn").instantiate()

	battle_layer.add_child(battle_scene)

	var manager = battle_scene.get_node("BattleManager")

	var context = BattleContext.new()
	context.encounter = encounter
	context.run_state = current_run
	context.dungeon_run_state = dungeon_run_state

	manager.start_battle_with_context(context)

	manager.battle_finished.connect(_on_battle_finished)


func _on_battle_finished(victory, exp_per_member: Dictionary = {}, level_up_events: Dictionary = {}):

	clear_layer(battle_layer)
	battle_layer.visible = false

	AudioManagerAuto.reset_ambience()
	AudioManagerAuto.fade_out_bgm()

	var results_scene := preload("res://UI/2D/Scenes/battle_results.tscn")
	var results := results_scene.instantiate()
	clear_layer(event_layer)
	event_layer.visible = true
	dungeon_layer.visible = false
	event_layer.add_child(results)
	# Build reward choices (victory only).
	var reward_choices : Array = []
	if victory:
		reward_choices = _make_battle_rewards()

	results.setup(victory, current_run.party_members, exp_per_member, level_up_events, reward_choices)

	# Apply chosen reward immediately when picked.
	results.reward_chosen.connect(func(reward: Dictionary):
		_apply_battle_reward(reward)
	)

	var _vic: bool = victory
	results.results_dismissed.connect(func():
		clear_layer(event_layer)
		if not _vic:
			var dc = get_tree().get_first_node_in_group("dungeon_controller")
			if dc:
				dc.on_party_defeated()
			else:
				_begin_game_flow()
			return
		event_layer.visible = false
		dungeon_layer.visible = true
		_set_dungeon_map_visible(true)
		var resume_tween = create_tween()
		resume_tween.tween_callback(AudioManagerAuto.resume_dungeon_track).set_delay(0.7)
		var dc = get_tree().get_first_node_in_group("dungeon_controller")
		dc.on_room_completed()
	)


func clear_layer(layer):
	for child in layer.get_children():
		child.queue_free()


func start_event(event_scene: PackedScene):

	clear_layer(event_layer)

	var event = event_scene.instantiate()

	event_layer.add_child(event)

	dungeon_layer.visible = false
	battle_layer.visible = false
	event_layer.visible = true

	event.event_finished.connect(_on_event_finished)


func _on_event_finished():

	clear_layer(event_layer)
	event_layer.visible = false
	dungeon_layer.visible = true
	_set_dungeon_map_visible(true)

	var dc = get_tree().get_first_node_in_group("dungeon_controller")
	dc.on_room_completed()


func start_world(scene: PackedScene):

	clear_layer(world_layer)

	dungeon_layer.visible = false
	battle_layer.visible = false
	event_layer.visible = false
	world_layer.visible = true
	_set_dungeon_map_visible(false)

	var world = scene.instantiate()
	world_layer.add_child(world)

	# Make the scene's Camera3D current immediately so get_viewport().get_camera_3d()
	# returns a valid camera on the first PhantomCamera process tick.
	var cam := _find_first_camera(world)
	if cam:
		cam.make_current()


func _find_first_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node
	for child in node.get_children():
		var result := _find_first_camera(child)
		if result:
			return result
	return null


func _collect_phantom_hosts(node: Node, result: Array) -> void:
	# PhantomCameraHost is a scripted class — check via is_class or script name.
	if node.get_script() != null:
		var sn : String = node.get_script().get_global_name()
		if sn == "PhantomCameraHost":
			result.append(node)
	for child in node.get_children():
		_collect_phantom_hosts(child, result)


func start_dungeon(dungeon_data: DungeonData):
	dungeon_layer.visible = true
	world_layer.visible = false
	_set_dungeon_map_visible(true)
	dungeon_controller.start_dungeon(current_run, dungeon_data)


## dungeon_run_state is passed so boss battles during AL_FINE
## also get access to the phase for the struggle reticle feature.
func start_boss_battle(encounter: EncounterData, dungeon_run_state: DungeonRunState = null) -> void:
	dungeon_layer.visible = false
	event_layer.visible = false
	battle_layer.visible = true
	_set_dungeon_map_visible(false)

	clear_layer(battle_layer)
	var battle_scene = preload("res://GameRoots/Scenes/battle_scene.tscn").instantiate()
	battle_layer.add_child(battle_scene)

	var manager = battle_scene.get_node("BattleManager")
	var context = BattleContext.new()
	context.encounter = encounter
	context.run_state = current_run
	context.dungeon_run_state = dungeon_run_state
	manager.start_battle_with_context(context)
	manager.battle_finished.connect(_on_boss_battle_finished)


func _on_boss_battle_finished(victory: bool, exp_per_member: Dictionary = {}, level_up_events: Dictionary = {}):
	clear_layer(battle_layer)
	battle_layer.visible = false
	AudioManagerAuto.reset_ambience()
	AudioManagerAuto.fade_out_bgm()

	var results_scene := preload("res://UI/2D/Scenes/battle_results.tscn")
	var results := results_scene.instantiate()
	clear_layer(event_layer)
	event_layer.visible = true
	dungeon_layer.visible = false
	event_layer.add_child(results)
	results.setup(victory, current_run.party_members, exp_per_member, level_up_events)

	if victory:
		results.results_dismissed.connect(func():
			clear_layer(event_layer)
			start_win_screen()
		)
	else:
		results.results_dismissed.connect(func():
			clear_layer(event_layer)
			start_new_game()
		)


func start_win_screen() -> void:
	clear_layer(event_layer)
	event_layer.visible = true
	dungeon_layer.visible = false
	battle_layer.visible = false
	_set_dungeon_map_visible(false)
	var win_scene := preload("res://UI/2D/Scenes/win_screen.tscn")
	var win := win_scene.instantiate()
	event_layer.add_child(win)


## Build 3 reward options for post-battle pick.
## One entry per type is generated, then 3 distinct types are drawn.
## This guarantees no two choices offer the same kind of reward.
func _make_battle_rewards() -> Array:
	var dr  : DungeonRunState = current_dungeon_run
	var tense : bool = dr != null and dr.is_battle_reprimed_transit()
	var run := current_run

	var pool : Array  # one entry per type, amount randomised
	if tense:
		# AL_SEGNO: permanent / building rewards — no consumable top-ups.
		var rerolls : int = randi_range(1, 2)
		var tiles   : int = randi_range(1, 2)
		var gold    : int = randi_range(20, 45)
		pool = [
			{"label": "Reprise\n+%d Reprise%s" % [rerolls, "s" if rerolls > 1 else ""],
				"type": "reprise",  "amount": rerolls},
			{"label": "Salvage\n+%d Tie%s" % [tiles, "s" if tiles > 1 else ""],
				"type": "tie",      "amount": tiles},
			{"label": "Big Cut\n+%d\u20b5" % gold,
				"type": "cuts",    "amount": gold},
		]
	else:
		# DAL_SEGNO: sustain rewards — corpus, cuts, beat bolts.
		var hp_amt  : int = randi_range(3, 8)
		var gold    : int = randi_range(10, 25)
		var bb_amt  : int = max(1, randi_range(run.gun_clip / 2, run.gun_clip))
		pool = [
			{"label": "Corpus\n+%d CORP each" % hp_amt,
				"type": "corpus", "amount": hp_amt},
			{"label": "Small Cut\n+%d\u20b5" % gold,
				"type": "cuts",   "amount": gold},
			{"label": "Beat Bolts\n+%d BB" % bb_amt,
				"type": "bb",     "amount": bb_amt},
		]
	# All types are already distinct — just shuffle and return all 3.
	pool.shuffle()
	return pool


func _apply_battle_reward(reward: Dictionary) -> void:
	var run := current_run
	match reward.get("type", ""):
		"corpus":
			var amt : int = reward.get("amount", 3)
			for m in run.party_members:
				if m.current_hp > 0:
					var max_hp : int = m.character.base_max_hp + m.bonus_max_hp
					m.current_hp = min(m.current_hp + amt, max_hp)
		"bb":
			run.excess_ammo += reward.get("amount", 1)
		"reprise":
			run.reroll_charges += reward.get("amount", 1)
		"tie":
			run.road_tiles_remaining += reward.get("amount", 1)
		"cuts":
			run.money += reward.get("amount", 0)
