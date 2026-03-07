@ -1,733 +1,770 @@
extends Node


signal battle_finished(victory: bool)
signal battle_manager_ready

var current_state : Node = null
var battle_ending := false


var context : BattleContext
var battlefield_root : Node3D

var actors : Array[BattleActor] = []
var turn_queue : Array[BattleActor] = []
var current_index : int = 0


var active_player_actor : BattleActor
var enemy_player_actor : BattleActor
@onready var active_anchor: Node3D = $"../CameraRig/ActiveAnchor"
@onready var active_look_anchor: Node3D = $"../CameraRig/ActiveLookAnchor"
@onready var target_anchor: Node3D = $"../CameraRig/TargetAnchor"
@onready var target_look_anchor: Node3D = $"../CameraRig/TargetLookAnchor"

var active_anchor_source : Node3D = null
var target_anchor_source : Node3D = null
var active_look_source : Node3D = null
var target_look_source : Node3D = null


var selected_command : String = ""
var selected_target : BattleActor = null
var selected_body_part : BodyPartData = null
var selected_filter : int = -1
var input_locked := false


var shake_time := 0.0
var active_shake_strength := 0.0
var target_shake_strength := 0.0
var shake_decay := 8.0
var active_base_follow_position := Vector3.ZERO
var target_base_follow_position := Vector3.ZERO





enum InputStage {
	COMMAND,
	TARGET,
	PART,
	FILTER,
	CONFIRM,
	DONE
}


var input_stage : InputStage = InputStage.COMMAND



enum Channel {
	R = 1,
	G = 2,
	B = 4
}

var removed_channels : int = 0

@onready var ca_mesh: MeshInstance2D = $"../BattleUI/MeshInstance2D"
@onready var ca_mesh_mat: ShaderMaterial = ca_mesh.material

var ca_defaults := {}


@onready var active_cam: PhantomCamera3D = $"../CameraRig/active_cam"
@onready var target_cam: PhantomCamera3D = $"../CameraRig/target_cam"



@onready var idle_orbit_pivot: Node3D = $"../CameraRig/IdleOrbitPivot"
@onready var idle_orbiter: Node3D = $"../CameraRig/IdleOrbitPivot/IdleOrbiter"




@onready var battle_ui = get_parent().get_node("BattleUI")
@onready var battle_hud: BattleHUD = $"../BattleHUD"



@onready var states = $States

func _ready():
	await get_tree().process_frame
	

	add_to_group("battle_manager")
	if ca_defaults.is_empty():
		ca_mesh.material = ca_mesh.material.duplicate()
		ca_mesh_mat = ca_mesh.material
		cache_ca_defaults()
	else:
		reset_ca_material()
	
	active_cam.set_follow_target(active_anchor)
	target_cam.set_follow_target(target_anchor)

	target_cam.set_look_at_target(target_look_anchor)
	
	battle_ui.command_selected.connect(_on_command_selected)
	battle_ui.target_selected.connect(_on_target_selected)
	battle_ui.body_part_selected.connect(_on_body_part_selected)
	battle_ui.filter_selected.connect(_on_filter_selected)
	battle_ui.confirm_pressed.connect(_on_confirm_pressed)
	battle_ui.cancel_pressed.connect(_on_cancel_pressed)
	
	emit_signal("battle_manager_ready")
	

func _process(delta):


	if active_anchor_source:
		active_anchor.global_position = active_anchor_source.global_position

	if target_anchor_source:
		target_anchor.global_position = target_anchor_source.global_position

	if active_look_source:
		active_look_anchor.global_position = active_look_source.global_position

	if target_look_source:
		target_look_anchor.global_position = target_look_source.global_position


	if shake_time > 0:

		shake_time -= delta

		var active_offset = Vector3(
			randf_range(-active_shake_strength, active_shake_strength),
			randf_range(-active_shake_strength * 0.3, active_shake_strength * 0.3),
			randf_range(-active_shake_strength * 0.3, active_shake_strength * 0.3)
		)
		
		var target_offset = Vector3(
			randf_range(-target_shake_strength, target_shake_strength),
			randf_range(-target_shake_strength * 0.3, target_shake_strength * 0.3),
			randf_range(-target_shake_strength * 0.3, target_shake_strength * 0.3)
		)
		if active_anchor:
			active_anchor.position = active_base_follow_position + active_offset
		if target_anchor:
			target_anchor.position = target_base_follow_position + target_offset
		active_shake_strength = lerp(active_shake_strength, 0.0, delta * shake_decay)
		target_shake_strength = lerp(target_shake_strength, 0.0, delta * shake_decay)

		var target_offset = Vector3(
			randf_range(-target_shake_strength, target_shake_strength),
			randf_range(-target_shake_strength * 0.3, target_shake_strength * 0.3),
			randf_range(-target_shake_strength * 0.3, target_shake_strength * 0.3)
		)

		active_anchor.position += active_offset
		target_anchor.position += target_offset

		active_shake_strength = lerp(active_shake_strength, 0.0, delta * shake_decay)
		target_shake_strength = lerp(target_shake_strength, 0.0, delta * shake_decay)






func change_state(state_name: String):
	if current_state:
		current_state.exit()
	current_state = states.get_node(state_name)
	current_state.enter(self)





func start_battle_with_context(battle_context : BattleContext):

	print("STARTING BATTLE")

	context = battle_context
	
	removed_channels = context.encounter.forced_removed_channels


	# ✅ START MUSIC HERE
	var track = context.encounter.override_music

	if track:
		AudioManagerAuto.play_battle_track(track)
	"else:
		AudioManagerAuto.play_battle_track(
			context.run_state.current_dungeon.default_battle_track
		)"


	AudioManagerAuto.ambience_player.play()


	setup_battlefield()
	spawn_players()
	spawn_enemies()
	print("Players:", context.run_state.party_members.size())
	print("Enemies:", context.encounter.enemies.size())
	print(context.run_state.party_members)
	print(battlefield_root.get_children())

	battle_hud.setup(actors)





	removed_channels = context.encounter.forced_removed_channels
	if removed_channels:
		update_enemy_visibility()

	build_turn_queue()

	current_index = 0
	next_turn()

func spawn_players():
	var player_slots = battlefield_root.get_node("PlayerSlots").get_children()

	for i in range(context.run_state.party_members.size()):

		var member_data = context.run_state.party_members[i]
		var char_data = member_data.character

		var actor = char_data.battle_scene.instantiate()
		
		actor.name = char_data.display_name
		actor.team = BattleActor.Team.PLAYER
		actor.max_hp = member_data.character.base_max_hp + member_data.bonus_max_hp
		actor.hp = member_data.current_hp
		actor.attack_power = member_data.character.base_attack + member_data.bonus_attack
		
		actor.body_parts = char_data.body_parts
		actor.party_member = member_data
		player_slots[i].add_child(actor)

		actors.append(actor)
		actor.died.connect(_on_actor_died)
		actor.turn_finished.connect(_on_turn_finished)
		actor.hp_changed.connect(_on_hp_changed)
	

func spawn_enemies():
	var enemy_slots = battlefield_root.get_node("EnemySlots").get_children()

	for i in range(context.encounter.enemies.size()):
		var char_data = context.encounter.enemies[i]

		var actor : BattleActor = char_data.battle_scene.instantiate()
		
		actor.name = char_data.display_name
		actor.team = BattleActor.Team.ENEMY
		actor.max_hp = char_data.base_max_hp
		actor.attack_power = char_data.base_attack
		actor.hp = actor.max_hp
		actor.body_parts = char_data.body_parts
		

		enemy_slots[i].add_child(actor)

		actors.append(actor)
		actor.died.connect(_on_actor_died)
		actor.turn_finished.connect(_on_turn_finished)
		actor.hp_changed.connect(_on_hp_changed)




func setup_battlefield():
	battlefield_root = context.encounter.battlefield_scene.instantiate()
	get_tree().get_first_node_in_group("battle_layer").add_child(battlefield_root)




func build_turn_queue():
	turn_queue.clear()

	var players = actors.filter(func(a):
		return a.team == BattleActor.Team.PLAYER
	)

	var enemies = actors.filter(func(a):
		return a.team == BattleActor.Team.ENEMY
	)
	

	turn_queue.append_array(players)
	turn_queue.append_array(enemies)

func next_turn():

	if battle_ending:
		return

	if not is_inside_tree():
		return


	print("Turn: ", current_index)

	if check_victory():
		return

	if turn_queue.is_empty():
		return

	if current_index >= turn_queue.size():
		current_index = 0

	var actor = turn_queue[current_index]

	if not actor.is_alive():
		current_index += 1
		next_turn()
		return

	print("Turn: ", actor.name, " HP: ", actor.hp)

	if actor.team == BattleActor.Team.PLAYER:
		input_locked = false
		battle_hud.set_active_actor(actor)
		await handle_player_turn(actor)
	else:
		await handle_enemy_turn(actor)

func handle_player_turn(actor: BattleActor) -> void:

	active_player_actor = actor

	focus_actor(actor)

	await get_tree().process_frame

	input_stage = InputStage.COMMAND
	battle_ui.show_commands()

	update_ui_state()





func handle_enemy_turn(actor: BattleActor) -> void:

	await get_tree().process_frame

	var target = choose_target(actor)
	if target == null:
		return
	battle_hud.show_target(actor)
	
	
	await get_tree().process_frame
	focus_target(actor)
	focus_actor(target)

	target_cam.set_follow_damping_value(Vector3(.25, .25, .15))
	target_cam.set_follow_offset(Vector3(-1.25, 0, .55))
	target_cam.set_look_at_offset(Vector3(0, 0, -.2))

	await actor.take_turn(target)











func await_actor_turn(actor: BattleActor, action: Callable) -> void:
	var finished = false
	
	var on_finish = func():
		finished = true
	
	actor.turn_finished.connect(on_finish, CONNECT_ONE_SHOT)
	
	action.call()
	
	while not finished and not battle_ending:
		if not is_inside_tree():
			return
		await get_tree().process_frame


func _on_turn_finished():
	battle_hud.target_info.hide()
	battle_hud.set_active_actor(active_player_actor, false)
	current_index += 1
	next_turn()



func _on_actor_died(actor: BattleActor):
	turn_queue.erase(actor)
	actors.erase(actor)



func choose_target(actor: BattleActor) -> BattleActor:
	var possible_targets = actors.filter(func(a):
		return a.team != actor.team and a.is_alive()
	)

	if possible_targets.is_empty():
		return null

	return possible_targets.pick_random()



func check_victory() -> bool:
	var players_alive = actors.any(func(a):
		return a.team == BattleActor.Team.PLAYER and a.is_alive()
	)

	var enemies_alive = actors.any(func(a):
		return a.team == BattleActor.Team.ENEMY and a.is_alive()
	)

	if not players_alive:
		end_battle(false)
		return true

	if not enemies_alive:
		end_battle(true)
		return true

	return false

func end_battle(victory: bool):

	if battle_ending:
		return

	battle_ending = true

	save_party_state()

	if battlefield_root:
		battlefield_root.queue_free()

	actors.clear()
	turn_queue.clear()
	current_index = 0

	await get_tree().process_frame

	emit_signal("battle_finished", victory)

	battle_ending = false





func save_party_state():
	var party_data = context.run_state.party_members

	var player_actors = actors.filter(func(a):
		return a.team == BattleActor.Team.PLAYER
	)

	for i in min(player_actors.size(), context.run_state.party_members.size()):
		context.run_state.party_members[i].current_hp = player_actors[i].hp



func apply_lens(channel: int):
	if removed_channels & channel != 0:
		return
	
	if count_bits(removed_channels) >= 2:
		print("Already using 2 filters.")
		return
	
	removed_channels |= channel
	
	AudioManagerAuto.update_color_layers(removed_channels)
	AudioManagerAuto.set_glitch_intensity(1.5, 0.22)
	animate_channel_removal()
	update_enemy_visibility()

func animate_channel_removal():

	var strength := Vector3(1, 1, 1)

	if removed_channels & Channel.R:
		strength.x = 0
	if removed_channels & Channel.G:
		strength.y = 0
	if removed_channels & Channel.B:
		strength.z = 0

	
	ca_mesh_mat.set_shader_parameter("tear_intensity", 2.0)
	
	await get_tree().process_frame
	

	var tween := create_tween()

	# Violent burst
	ca_mesh_mat.set_shader_parameter("glitch_intensity", 1.0)
	ca_mesh_mat.set_shader_parameter("noise_strength", 0.6)
	ca_mesh_mat.set_shader_parameter("tear_intensity", 1.0)
	ca_mesh_mat.set_shader_parameter("block_glitch", 0.8)
	
	tween.set_trans(Tween.TRANS_EXPO)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	
	
	tween.tween_property(
		ca_mesh_mat,
		"shader_parameter/channel_strength",
		strength,
		0.25
	)
	

	tween.tween_property(
		ca_mesh_mat,
		"shader_parameter/glitch_intensity",
		0.0,
		0.47
	)

	tween.parallel().tween_property(
		ca_mesh_mat,
		"shader_parameter/noise_strength",
		0.0,
		0.38
	)

	tween.parallel().tween_property(
		ca_mesh_mat,
		"shader_parameter/tear_intensity",
		0.0,
		0.53
	)

	tween.parallel().tween_property(
		ca_mesh_mat,
		"shader_parameter/block_glitch",
		0.0,
		0.44
	)

func screen_shake(source: BattleActor, target: BattleActor, dir: Vector3, active_strength: float, target_strength: float, duration: float):

	shake_time = duration
	active_shake_strength = active_strength
	target_shake_strength = target_strength


	AudioManagerAuto.duck_bgm(-8.0, 0.4)
	AudioManagerAuto.set_glitch_intensity(0.2, 0.15)

func count_bits(value: int) -> int:
	var count := 0
	while value > 0:
		count += value & 1
		value >>= 1
	return count

func update_enemy_visibility():
	for actor in actors:
		if actor.team == BattleActor.Team.ENEMY:
			actor.update_shader_visibility(removed_channels)

	ca_mesh_mat.set_shader_parameter("removed_mask", removed_channels)


func reset_selection():
	selected_command = ""
	selected_target = null
	selected_body_part = null

	
	battle_ui.hide_target_container()
	battle_ui.hide_confirmation()

func reset_ca_material():

	for key in ca_defaults:
		ca_mesh_mat.set_shader_parameter(key, ca_defaults[key])


func cache_ca_defaults():

	ca_defaults["removed_mask"] = ca_mesh_mat.get_shader_parameter("removed_mask")
	ca_defaults["channel_strength"] = ca_mesh_mat.get_shader_parameter("channel_strength")
	ca_defaults["glitch_intensity"] = ca_mesh_mat.get_shader_parameter("glitch_intensity")
	ca_defaults["noise_strength"] = ca_mesh_mat.get_shader_parameter("noise_strength")
	ca_defaults["tear_intensity"] = ca_mesh_mat.get_shader_parameter("tear_intensity")
	ca_defaults["block_glitch"] = ca_mesh_mat.get_shader_parameter("block_glitch")

func follow_anchor(anchor: Node3D, source: Node3D):

	if anchor == active_anchor:
		active_anchor_source = source

	elif anchor == target_anchor:
		target_anchor_source = source

	elif anchor == active_look_anchor:
		active_look_source = source

	elif anchor == target_look_anchor:
		target_look_source = source


func focus_actor(actor: BattleActor):

	if actor == null:
		return

	follow_anchor(active_anchor, actor.camera_anchor)
	follow_anchor(active_look_anchor, actor.camera_anchor)

func focus_target(actor: BattleActor):

	if actor == null:
		return

	follow_anchor(target_anchor, actor.camera_anchor)
	follow_anchor(target_look_anchor, actor.camera_anchor)


func focus_idle_orbit():

	target_cam.set_follow_offset(Vector3.ZERO)
	target_cam.set_look_at_offset(Vector3.ZERO)

	follow_anchor(target_anchor, idle_orbiter)
	follow_anchor(target_look_anchor, idle_orbit_pivot)


func update_ui_state():
	if input_locked:
		return

	battle_ui.set_back_enabled(input_stage != InputStage.COMMAND)

	match input_stage:

		InputStage.COMMAND:
			focus_idle_orbit()
			battle_ui.show_commands()
			battle_ui.set_lens_enabled(count_bits(removed_channels) < 2)
			battle_ui.set_confirm_enabled(false)

		InputStage.TARGET:
			var targets = actors.filter(func(a):
				return a.team != active_player_actor.team and a.is_alive()
			)
			battle_ui.show_targets(targets)
			battle_ui.set_confirm_enabled(false)

		InputStage.PART:
			var parts = selected_target.get_visible_parts(removed_channels)
			battle_ui.show_body_part_targets(parts)
			battle_ui.set_confirm_enabled(false)

		InputStage.FILTER:
			focus_idle_orbit()
			battle_ui.show_filter_options()
			battle_ui.set_confirm_enabled(false)

		InputStage.CONFIRM:
			battle_ui.set_confirm_enabled(true)


func _on_confirm_pressed():
	if input_locked:
		return
	input_locked = true
	input_stage = InputStage.DONE

	match selected_command:
		"attack":
			await_actor_turn(active_player_actor, func():
				active_player_actor.take_turn(selected_target, selected_body_part)
			)
			
		"lens":
			await_actor_turn(active_player_actor, func():
				active_player_actor.use_lens(selected_filter)
			)
	



func _on_cancel_pressed():
	match input_stage:
		InputStage.TARGET:
			input_stage = InputStage.COMMAND

		InputStage.PART:
			input_stage = InputStage.TARGET

		InputStage.FILTER:
			input_stage = InputStage.COMMAND

		InputStage.CONFIRM:
			if selected_command == "attack":
				input_stage = InputStage.PART
			else:
				input_stage = InputStage.FILTER

	update_ui_state()


func _on_command_selected(command):
	selected_command = command

	if command == "attack":
		input_stage = InputStage.TARGET

	elif command == "lens":
		input_stage = InputStage.FILTER

	update_ui_state()


func _on_target_selected(target):

	selected_target = target

	target_cam.set_follow_damping_value(Vector3(.25, .25, .15))
	target_cam.set_follow_offset(Vector3(-1.25, 0, .55))
	target_cam.set_look_at_offset(Vector3(0, 0, -.2))

	focus_target(target)

	battle_hud.show_target(selected_target)

	input_stage = InputStage.PART
	update_ui_state()




func _on_body_part_selected(part):
	selected_body_part = part
	input_stage = InputStage.CONFIRM
	update_ui_state()


func _on_filter_selected(channel):
	selected_filter = channel
	input_stage = InputStage.CONFIRM
	update_ui_state()

func _on_hp_changed(actor: BattleActor):
	if actor.team == BattleActor.Team.ENEMY:
		battle_hud.show_target(actor)
