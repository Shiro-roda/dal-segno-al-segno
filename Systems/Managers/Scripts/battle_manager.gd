extends Node


signal battle_finished(victory: bool, exp_per_member: Dictionary, level_up_events: Dictionary)
signal battle_fled  # emitted instead of battle_finished when the party uses Emergency Exit
signal battle_manager_ready
signal player_skill_used(actor: BattleActor, command_key: String)
signal player_turn_started(actor: BattleActor)
signal reticle_opened

## True when the run is in a tense transit phase (DS_AL_SEGNO or AL_FINE).
## Used by the reticle to decide whether to show struggle alternatives.
func is_tense_phase() -> bool:
	if context == null or context.dungeon_run_state == null:
		return false
	return context.dungeon_run_state.is_battle_reprimed_transit()

var current_state : Node = null
var battle_ending := false
var _next_turn_running := false
var _last_enemy_tempo_cost : float = 0.0  # set by _on_enemy_skill_announced, read in handle_enemy_turn
var _deaths_pending : int = 0  # incremented while a death animation plays
var _first_player_turn := true  # true until the first player turn of a battle completes its cam intro


var context : BattleContext
var battlefield_root : Node3D

var actors : Array[BattleActor] = []
var _exp_this_battle : int = 0  # accumulated exp from kills
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
var free_shot_pending := false
var support_targeting := false
var selected_attack_skips_targeting := false
var selected_is_struggle := false

## Last confirmed action per character name. Keyed by actor.name.
## Each entry: {command, target (weakref), body_part, is_struggle, filter}
var _last_actions : Dictionary = {}

func grant_free_shot() -> void:
	free_shot_pending = true

## Returns true if the active actor has a repeatable last action available.
func can_repeat_action() -> bool:
	if active_player_actor == null or input_locked:
		return false
	var la : Dictionary = _last_actions.get(active_player_actor.name, {})
	if la.is_empty():
		return false
	var cmd : String = la["command"]
	# Command must still be available
	var available_keys : Array = active_player_actor.get_skills().map(func(s): return s["key"])
	if cmd not in available_keys:
		return false
	# Target must still be alive if the command needs one
	if cmd in ["attack", "special"] and not la["is_struggle"]:
		var wr = la["target"]
		if wr == null:
			return false
		var tgt = wr.get_ref()
		if not is_instance_valid(tgt) or not (tgt as BattleActor).is_alive():
			return false
	return true

## Immediately replay the actor's last confirmed action, bypassing the targeting UI.
func repeat_last_action() -> void:
	if not can_repeat_action():
		return
	var la : Dictionary = _last_actions[active_player_actor.name]
	selected_command          = la["command"]
	selected_is_struggle      = la["is_struggle"]
	selected_filter           = la["filter"]
	selected_body_part        = la["body_part"]
	selected_attack_skips_targeting = la["is_struggle"]
	var wr = la["target"]
	selected_target = wr.get_ref() as BattleActor if wr != null else null
	_on_confirm_pressed()

func delay_actor_turn(actor: BattleActor) -> void:
	# Drain the actor's tempo pool so they act much later
	actor.tempo_pool -= TEMPO_COST_ATTACK * 2.0
	print(actor.name, " is delayed — tempo drained.")


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

var ca_mesh: MeshInstance2D
var ca_mesh_mat: ShaderMaterial

var ca_defaults := {}


@onready var active_cam: PhantomCamera3D = $"../CameraRig/active_cam"
@onready var target_cam: PhantomCamera3D = $"../CameraRig/target_cam"
@onready var player_cam : Camera3D = $"../HBoxContainer/Left_Container/Left/PlayerActorCam"
@onready var enemy_cam  : Camera3D = $"../HBoxContainer/Right_Container/Right/TargetCam"



@onready var idle_orbit_pivot: Node3D = $"../CameraRig/IdleOrbitPivot"
@onready var idle_orbiter: Node3D = $"../CameraRig/IdleOrbitPivot/IdleOrbiter"
@onready var overview_anchor: Node3D = $"../CameraRig/OverviewAnchor"
@onready var ground_center_anchor: Node3D = $"../CameraRig/GroundCenterAnchor"
@onready var player_overview_anchor: Node3D = $"../CameraRig/PlayerOverviewAnchor"
@onready var player_ground_center_anchor: Node3D = $"../CameraRig/PlayerGroundCenterAnchor"
@onready var enemy_overview_anchor: Node3D = $"../CameraRig/EnemyOverviewAnchor"
@onready var enemy_ground_center_anchor: Node3D = $"../CameraRig/EnemyGroundCenterAnchor"




@onready var battle_ui = get_parent().get_node("BattleUI")

@onready var reticle_ui = get_parent().get_node_or_null("BattleReticleUI")
@onready var battle_hud       : BattleHUD          = $"../BattleHUD"
@onready var dialogue_box = $"../DialogueLayer"
@onready var battle_menu = get_parent().get_node_or_null("BattleMenu")




@onready var states = $States

func _ready():
	get_parent().add_to_group("battle_scene")
	await get_tree().process_frame
	ca_mesh = get_tree().root.get_node("GameRoot/TVOverlay/MeshInstance2D")

	add_to_group("battle_manager")
	if ca_defaults.is_empty():
		ca_mesh.material = ca_mesh.material.duplicate()
		ca_mesh_mat = ca_mesh.material
	else:
		# Re-assign the duplicate so ca_mesh_mat points to the live material
		ca_mesh.material = ca_mesh.material.duplicate()
		ca_mesh_mat = ca_mesh.material
		# Carry user's current ca_strength preference into the fresh duplicate
		ca_mesh_mat.set_shader_parameter("ca_strength", ca_defaults.get("ca_strength", 2.5))
	# Always re-cache from current material so user slider changes are preserved
	cache_ca_defaults()
	
	active_cam.set_follow_target(active_anchor)
	active_cam.set_look_at_target(active_look_anchor)
	target_cam.set_follow_target(target_anchor)
	target_cam.set_look_at_target(target_look_anchor)

	active_cam.set_priority(10)
	target_cam.set_priority(10)
	
	battle_ui.command_selected.connect(_on_command_selected)
	battle_ui.target_selected.connect(_on_target_selected)
	battle_ui.body_part_selected.connect(_on_body_part_selected)
	battle_ui.filter_selected.connect(_on_filter_selected)
	battle_ui.confirm_pressed.connect(_on_confirm_pressed)
	battle_ui.cancel_pressed.connect(_on_cancel_pressed)


	if is_instance_valid(reticle_ui):
		reticle_ui.skill_selected.connect(_on_reticle_skill_chosen)
		reticle_ui.target_selected.connect(_on_radial_target_chosen)
		reticle_ui.focus_requested.connect(_on_reticle_focus_requested)
		reticle_ui.part_selected.connect(_on_radial_part_chosen)
		reticle_ui.confirmed.connect(_on_radial_confirmed)
		reticle_ui.cancelled.connect(_on_reticle_cancelled)
		reticle_ui.filter_selected.connect(_on_radial_filter_chosen)
		reticle_ui.repeat_action.connect(repeat_last_action)

	if is_instance_valid(battle_menu):
		battle_menu.item_used.connect(_on_battle_menu_item_used)
		battle_menu.skill_chosen.connect(_on_battle_menu_skill_chosen)
		battle_menu.closed.connect(_on_battle_menu_closed)

	call_deferred("emit_signal", "battle_manager_ready")


func _unhandled_input(event: InputEvent) -> void:
	# Open the battle menu when the player presses open_menu during their turn,
	# but only if input isn't locked and we're in the command selection stage.
	if event.is_action_pressed("open_menu") \
			and not input_locked \
			and input_stage == InputStage.COMMAND \
			and is_instance_valid(battle_menu):
		battle_menu.open_for_turn(active_player_actor, actors, context.run_state, removed_channels)
		battle_menu.refresh_log(battle_hud._log_lines)
		get_viewport().set_input_as_handled()
	

func _process(delta):

	if active_anchor_source:
		active_anchor.global_position = active_anchor_source.global_position

	if target_anchor_source:
		target_anchor.global_position = target_anchor_source.global_position

	if active_look_source:
		active_look_anchor.global_position = active_look_source.global_position

	if target_look_source:
		target_look_anchor.global_position = target_look_source.global_position


	if (active_shake_strength > 0.1) or (target_shake_strength > 0.1):
		active_cam.follow_damping = false
		target_cam.follow_damping = false
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
			active_anchor.global_position += active_offset
		if target_anchor:
			target_anchor.global_position += target_offset

		active_shake_strength = lerp(active_shake_strength, 0.0, delta * shake_decay)
		target_shake_strength = lerp(target_shake_strength, 0.0, delta * shake_decay)
	else:
		active_cam.follow_damping = true
		target_cam.follow_damping = true





func change_state(state_name: String):
	var next = states.get_node_or_null(state_name)
	if next == null:
		push_error("BattleManager.change_state: node '%s' not found under $States" % state_name)
		return
	if current_state:
		current_state.exit()
	current_state = next
	current_state.enter(self)





func start_battle_with_context(battle_context : BattleContext):

	print("STARTING BATTLE")

	context = battle_context
	_exp_this_battle = 0
	
	removed_channels = context.encounter.forced_removed_channels
	if is_instance_valid(reticle_ui):
		reticle_ui.reticle_theme = context.encounter.reticle_theme


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

	# Centre idle_orbit_pivot on the battlefield, then park both cameras overhead.
	var first_player = actors.filter(func(a): return a.team == BattleActor.Team.PLAYER)
	var first_enemy  = actors.filter(func(a): return a.team == BattleActor.Team.ENEMY)
	var battlefield_center := Vector3.ZERO
	if first_player.size() > 0 and first_player[0].camera_anchor:
		battlefield_center = first_player[0].camera_anchor.global_position
	if first_enemy.size() > 0 and first_enemy[0].camera_anchor:
		battlefield_center = (battlefield_center + first_enemy[0].camera_anchor.global_position) * 0.5
	idle_orbit_pivot.global_position = battlefield_center
	# Snap both scene anchors to battlefield center before any camera setup.

	_first_player_turn = true
	# Target cam: orbit/overview toggle (starts in overview via focus_overview).
	focus_overview()
	# Active cam: parked on overview so _intro_active_cam can glide it in later.
	_park_active_cam_on_overview()

	battle_hud.setup(actors)
	battle_hud.refresh_queue(self)
	# Mirror battle_log signals to battle_menu so its log stays in sync.
	if is_instance_valid(battle_menu):
		for actor in actors:
			if actor.has_signal("battle_log") and not actor.battle_log.is_connected(battle_menu.push_log):
				actor.battle_log.connect(battle_menu.push_log)





	removed_channels = context.encounter.forced_removed_channels
	if removed_channels:
		update_enemy_visibility()

	build_turn_queue()
	current_index = 0
	# Hand off to the battle-level FSM. BattleIntroState plays the splash/dialogue
	# then transitions to BattleTurn, which drives next_turn() from there.
	change_state("BattleIntroState")

func spawn_players():
	var player_slots = battlefield_root.get_node("PlayerSlots").get_children()

	var slot_index = 0
	for i in range(context.run_state.party_members.size()):
		if slot_index >= player_slots.size():
			break

		var member_data = context.run_state.party_members[i]
		if member_data.current_hp <= 0:
			continue  # skip dead characters

		var char_data = member_data.character

		var actor = char_data.battle_scene.instantiate()
		
		actor.name         = char_data.display_name
		actor.display_name = char_data.display_name
		actor.log_name     = char_data.get_log_name()
		actor.team = BattleActor.Team.PLAYER
		actor.max_hp = member_data.character.base_max_hp + member_data.bonus_max_hp
		actor.hp = member_data.current_hp
		actor.attack_power = member_data.character.base_attack + member_data.bonus_attack
		actor.flat_defense = member_data.character.base_flat_defense + member_data.bonus_flat_defense
		actor.tempo_stat = char_data.tempo
		actor.body_parts = char_data.body_parts
		actor.party_member = member_data
		actor.run_state = context.run_state
		player_slots[slot_index].add_child(actor)
		slot_index += 1

		actors.append(actor)
		actor.died.connect(_on_actor_died)
		actor.turn_finished.connect(_on_turn_finished)
		actor.hp_changed.connect(func(): _on_hp_changed(actor))


func spawn_enemies():
	var enemy_slots = battlefield_root.get_node("EnemySlots").get_children()

	for i in range(context.encounter.enemies.size()):
		var char_data = context.encounter.enemies[i]

		var actor : BattleActor = char_data.battle_scene.instantiate()
		
		actor.name         = char_data.display_name
		actor.display_name = char_data.display_name
		actor.log_name     = char_data.get_log_name()
		actor.character_data = char_data
		actor.team = BattleActor.Team.ENEMY
		actor.max_hp = char_data.base_max_hp
		actor.attack_power = char_data.base_attack
		actor.flat_defense = char_data.base_flat_defense
		actor.hp = actor.max_hp
		actor.tempo_stat = char_data.tempo
		actor.body_parts = char_data.body_parts
		actor.theme_col = char_data.theme_color

		# Assign party_member so will rings and skill costs work.
		if char_data.boss_party_member != null:
			actor.party_member = char_data.boss_party_member
		elif char_data.base_max_will > 0:
			# Regular enemy with will — synthesise a minimal PartyMemberData.
			var pm := PartyMemberData.new()
			pm.character = char_data
			pm.max_will  = char_data.base_max_will
			pm.will      = char_data.base_max_will
			actor.party_member = pm

		# Copy skill loadout from CharacterData into EnemyActor if applicable.
		if actor is EnemyActor and not char_data.skills.is_empty():
			actor.skills = char_data.skills.duplicate()

		# Copy chatter lines from CharacterData into EnemyActor.
		if actor is EnemyActor:
			actor.chatter_attack  = Array(char_data.chatter_attack)
			actor.chatter_special = Array(char_data.chatter_special)
			actor.chatter_support = Array(char_data.chatter_support)
			actor.chatter_hurt    = Array(char_data.chatter_hurt)
			actor.chatter_low_hp  = Array(char_data.chatter_low_hp)
			actor.chatter_kill    = Array(char_data.chatter_kill)
			actor.chatter_die     = Array(char_data.chatter_die)

		enemy_slots[i].add_child(actor)

		actors.append(actor)
		# Motif discovery: first time encountering this enemy type.
		MetaProgress.notify_encounter(
			"enemy:" + char_data.display_name.to_lower().replace(" ", "_"),
			char_data.display_name)
		actor.died.connect(_on_actor_died)
		# Enemies do NOT connect to _on_turn_finished.
		# Their turn flow is driven by handle_enemy_turn's await, not the signal.
		actor.skill_announced.connect(_on_enemy_skill_announced)
		actor.hp_changed.connect(func(): _on_hp_changed(actor))




func setup_battlefield():
	battlefield_root = context.encounter.battlefield_scene.instantiate()
	get_tree().get_first_node_in_group("battle_layer").add_child(battlefield_root)




# Default action tempo costs - subtracted from tempo_pool when an actor acts.
# Costs are large relative to tempo_stat (~10-15) so acting creates real debt.
# A stat difference of 2-3 produces occasional double-turns; bonuses are scarce.
const TEMPO_COST_ATTACK  = 100
const TEMPO_COST_SPECIAL = 180
const TEMPO_COST_SUPPORT = 150
const TEMPO_COST_DEFAULT = 100

func build_turn_queue():
	# Seed with a random offset in [0, tempo_stat) so starting order is shuffled
	# while still respecting speed — faster actors are still more likely to go first.
	for actor in actors:
		actor.tempo_pool = randf_range(0.0, float(actor.tempo_stat))

func _pick_next_actor() -> BattleActor:
	var living = actors.filter(func(a): return a.is_alive())
	if living.is_empty(): return null
	living.sort_custom(func(a, b): return a.tempo_pool > b.tempo_pool)
	while living[0].tempo_pool < 100:
		for actor in living:
			actor.tick_tempo()
		living.sort_custom(func(a, b): return a.tempo_pool > b.tempo_pool)
	return living[0]


func next_turn():
	if battle_ending:
		return
	if not is_inside_tree():
		return
	if _next_turn_running:
		print("next_turn: RE-ENTRANT CALL — ignoring")
		return
	_next_turn_running = true
	# Wait for any in-progress death animations before advancing
	while _deaths_pending > 0 and not battle_ending:
		if not is_inside_tree():
			_next_turn_running = false
			return
		await get_tree().process_frame
	if check_victory():
		_next_turn_running = false
		return

	var actor = _pick_next_actor()
	if actor == null:
		_next_turn_running = false
		return

	print("Turn: ", actor.name, " TP: ", actor.tempo_pool, " HP: ", actor.hp)

	_next_turn_running = false
	if actor.team == BattleActor.Team.PLAYER:
		input_locked = false
		battle_hud.set_active_actor(actor)
		await handle_player_turn(actor)
	else:
		await handle_enemy_turn(actor)

func handle_player_turn(actor: BattleActor) -> void:

	active_player_actor = actor

	await get_tree().process_frame

	actor.set_actor_state(BattleActor.STATE_ACTIVE)
	if _first_player_turn:
		_first_player_turn = false
		_intro_active_cam(actor)  # fire-and-forget: glides in, then restores damping
	else:
		focus_actor(actor)
	print("handle_player_turn: active_anchor_source=", active_anchor_source, " pos=", active_anchor.global_position)

	input_stage = InputStage.COMMAND
	update_ui_state()
	emit_signal("player_turn_started", actor)





func handle_enemy_turn(actor: BattleActor) -> void:
	if is_instance_valid(reticle_ui): reticle_ui.set_skills_visible(false)
	await get_tree().process_frame
	var target = choose_target(actor)
	if target == null:
		if not check_victory():
			next_turn()
		return
	battle_hud.show_target(actor)
	await get_tree().process_frame
	focus_target(actor)
	focus_actor(target)
	# Use enemy_take_turn for skill-aware AI (boss enemies), plain take_turn otherwise
	if actor.get_skills().is_empty():
		await actor.take_turn(target)
	else:
		await actor.enemy_take_turn(target)
	# Guard: battle may have ended during the enemy's animation
	if battle_ending or not is_inside_tree():
		return
	# Return the enemy to IDLE so can_be_targeted() works on subsequent player turns.
	if is_instance_valid(actor) and actor.current_actor_state_name != BattleActor.STATE_DEAD:
		actor.set_actor_state(BattleActor.STATE_IDLE)
	# Deduct tempo cost and reset bonus for enemy
	# Use the per-skill override recorded during skill_announced, or default to TEMPO_COST_ATTACK.
	if is_instance_valid(actor):
		var cost : float = _last_enemy_tempo_cost if _last_enemy_tempo_cost > 0 else TEMPO_COST_ATTACK
		_last_enemy_tempo_cost = 0
		actor.tempo_pool -= cost
		actor.reset_tempo_bonus()
	else:
		pass  # actor freed mid-animation (killed during their own turn)
	battle_hud.refresh_queue(self)
	if is_instance_valid(reticle_ui): reticle_ui.set_skills_visible(true)
	next_turn()











func await_actor_turn(actor: BattleActor, action: Callable) -> void:
	var finished = false

	var on_finish = func():
		finished = true

	actor.turn_finished.connect(on_finish, CONNECT_ONE_SHOT)

	# await the callable so coroutines (use_skill, use_lens, etc.) run to completion
	await action.call()

	while not finished and not battle_ending:
		if not is_inside_tree():
			return
		await get_tree().process_frame


func _on_enemy_skill_announced(actor: BattleActor, skill_name: String, skill_summary: String) -> void:
	# Capture per-skill tempo cost from the SkillData if available.
	# EnemyActor.get_skills() returns Dicts; search for matching name.
	if actor.has_method("get_skills"):
		for sd in actor.get_skills():
			if sd.get("name", "") == skill_name and sd.get("tempo_cost", 0) > 0:
				_last_enemy_tempo_cost = float(sd["tempo_cost"])
				break
	# Show the announcement banner in the HUD.
	if is_instance_valid(battle_hud):
		battle_hud.announce_enemy_skill(actor.get_log_name(), skill_name, skill_summary)

func _on_turn_finished():
	battle_hud.set_active_actor(active_player_actor, false)
	# Deduct tempo cost from whoever just acted
	var cost = _tempo_cost_for_command(selected_command)
	if active_player_actor != null and is_instance_valid(active_player_actor):
		active_player_actor.tempo_pool -= cost
		active_player_actor.reset_tempo_bonus()
		# Return actor to IDLE so enemies can target them on their turn.
		if active_player_actor.current_actor_state_name != BattleActor.STATE_DEAD:
			active_player_actor.set_actor_state(BattleActor.STATE_IDLE)
	battle_hud.refresh_queue(self)
	next_turn()

func _tempo_cost_for_command(cmd: String) -> float:
	match cmd:
		"attack": return TEMPO_COST_ATTACK
		"special": return TEMPO_COST_SPECIAL
		"support": return TEMPO_COST_SUPPORT
		"item":    return TEMPO_COST_DEFAULT
		_: return TEMPO_COST_DEFAULT


func _on_battle_menu_skill_chosen(actor: BattleActor, skill: Dictionary, target: BattleActor, part: BodyPartData) -> void:
	# Route the chosen skill through the existing turn machinery.
	selected_command       = skill.get("key", "attack")
	selected_target        = target
	selected_body_part     = part
	var aoe     : bool = skill.get("aoe",     false)
	var struggle: bool = skill.get("struggle", false)
	selected_attack_skips_targeting = aoe or struggle
	selected_is_struggle            = struggle
	input_locked = true
	input_stage  = InputStage.DONE
	emit_signal("player_skill_used", actor, selected_command)
	match selected_command:
		"attack":
			if struggle:
				await_actor_turn(actor, func(): actor.struggle_attack(actors, actor.attack_power))
			else:
				var is_ammo_user : bool = actor.party_member == null or not actor.party_member.has_will()
				if is_ammo_user:
					var ammo_cost : int = skill.get("ammo_cost", 1)
					if not context.run_state.spend_ammo(ammo_cost):
						input_locked = false
						input_stage  = InputStage.COMMAND
						return
				await_actor_turn(actor, func(): actor.take_turn(target, part))
		"special":
			var is_ammo_user : bool = actor.party_member == null or not actor.party_member.has_will()
			if is_ammo_user and skill.has("_filter_channel"):
				# Kendall's Unveil — apply a lens channel
				var chan : int = skill["_filter_channel"]
				await_actor_turn(actor, func(): actor.use_lens(chan))
			else:
				await_actor_turn(actor, func(): actor.use_skill("special", [target] if target else [], part))
		"support":
			var support_targets : Array = actors if aoe else ([target] if target else actors)
			await_actor_turn(actor, func(): actor.use_skill("support", support_targets))
		_:
			await_actor_turn(actor, func(): actor.use_skill(selected_command, [target] if target else [], part))


func _on_battle_menu_item_used(_actor: BattleActor, _inst: ItemInstance, _target) -> void:
	# Item use no longer spends the turn — the menu stays open and the player
	# must still choose a skill action. This handler is kept for signal compatibility.
	pass


func _on_battle_menu_closed() -> void:
	# No action taken — return focus to the reticle without consuming the turn.
	if is_instance_valid(reticle_ui):
		reticle_ui.set_skills_visible(true)


# Returns an Array of {actor: BattleActor, tempo: float} dicts showing projected turn order.
# Simulates tempo ticks on shadow pools - never mutates real actors.
func get_projected_queue(steps: int = 8) -> Array:
	var living = actors.filter(func(a): return a.is_alive())
	if living.is_empty():
		return []

	# Shadow pools: dict actor -> simulated tempo_pool
	var pools : Dictionary = {}
	for a in living:
		pools[a] = a.tempo_pool

	var result : Array = []
	for _i in range(steps):
		# Mirror _pick_next_actor: keep ticking until someone reaches 100
		var top : BattleActor = living[0]
		for a in living:
			if pools[a] > pools[top]:
				top = a
		while pools[top] < 100.0:
			for a in living:
				if a.has_status(BattleActor.STATUS_FROZEN):
					continue
				var gain = float(a.tempo_stat)
				if a.has_status(BattleActor.STATUS_SLOW):
					gain *= BattleActor.SLOW_TEMPO_MULT
				pools[a] += gain
			top = living[0]
			for a in living:
				if pools[a] > pools[top]:
					top = a
		result.append({"actor": top, "tempo": pools[top]})
		pools[top] -= TEMPO_COST_ATTACK

	return result



func _on_actor_died(actor: BattleActor):
	if actor.team == BattleActor.Team.ENEMY:
		var cd : CharacterData = actor.character_data
		if cd != null:
			_exp_this_battle += cd.exp_yield
			var run := context.run_state
			if run != null and not run.defeated_enemies.has(cd.display_name):
				run.defeated_enemies[cd.display_name] = cd
		else:
			# Fallback: search by display_name for actors without character_data set.
			for fallback_cd in context.encounter.enemies:
				if fallback_cd.get_log_name() == actor.log_name:
					_exp_this_battle += fallback_cd.exp_yield
					var run := context.run_state
					if run != null and not run.defeated_enemies.has(fallback_cd.display_name):
						run.defeated_enemies[fallback_cd.display_name] = fallback_cd
					break
	actors.erase(actor)
	# Notify the reticle immediately so the dead actor's box disappears
	if is_instance_valid(reticle_ui):
		reticle_ui.notify_actor_died(actor)
	_deaths_pending += 1
	_run_death_animation(actor)


func _run_death_animation(actor: BattleActor) -> void:
	var death_script := load("res://Characters/Scripts/death_animator.gd")
	if death_script and is_instance_valid(actor):
		await death_script.play(actor)
	if is_instance_valid(actor):
		actor.queue_free()
	_deaths_pending -= 1



func choose_target(actor: BattleActor) -> BattleActor:
	var possible_targets = actors.filter(func(a):
		return a.team != actor.team and a.can_be_targeted()
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
	change_state("BattleEnd")

	# Close the reticle immediately so stale enemy boxes don't linger
	# and can't emit signals into a battle that's already ending.
	if is_instance_valid(reticle_ui):
		reticle_ui.close(true)

	reset_ca_material()
	battle_hud.reset_augur_panel()
	save_party_state()

	# Restore all AP and BB after every victory except during AL_SEGNO and AL_FINE,
	# where resource attrition is the primary challenge.
	if victory:
		var dr : DungeonRunState = GameController.current_dungeon_run
		var tense : bool = dr != null and dr.is_battle_reprimed_transit()
		if not tense:
			# DAL_SEGNO / DA_CAPO / AL_CODA: free full restore of AP and BB.
			for member in context.run_state.party_members:
				if member.has_will():
					member.will = member.max_will
			context.run_state.ammo = context.run_state.gun_clip
		else:
			# AL_SEGNO / AL_FINE: AP and BB do NOT refill automatically.
			# The excess ammo pool is drawn on to reload the gun clip.
			context.run_state.reload_from_excess()

	# Award exp randomly distributed among surviving party members (victory only)
	var exp_per_member  : Dictionary = {}  # display_name -> int exp share
	var level_up_events : Dictionary = {}  # display_name -> Array of event dicts
	if victory and _exp_this_battle > 0:
		var survivors : Array = context.run_state.party_members.filter(
			func(m): return m.current_hp > 0)
		if not survivors.is_empty():
			var weights : Array = []
			var total_w : float = 0.0
			for _s in survivors:
				var w := randf_range(0.5, 1.5)
				weights.append(w)
				total_w += w
			var remaining := _exp_this_battle
			for i in survivors.size():
				var share : int
				if i == survivors.size() - 1:
					share = remaining
				else:
					share = max(1, int(float(_exp_this_battle) * weights[i] / total_w))
					remaining -= share
				var member: PartyMemberData = survivors[i]
				var dr : DungeonRunState = GameController.current_dungeon_run
				# Al Segno phases: no level cap — grind freely.
				# Safe phases (DA_CAPO, GRAND_PAUSE, DAL_SEGNO): cap at segno_level_ceiling.
				var in_al_segno : bool = dr != null and dr.is_battle_reprimed_transit()
				if in_al_segno:
					var events = member.add_exp(share)
					exp_per_member[member.character.display_name] = share
					if not events.is_empty():
						level_up_events[member.character.display_name] = events
				else:
					var ceiling : int = dr.segno_level_ceiling if dr != null \
						else 3
					if member.level >= ceiling:
						exp_per_member[member.character.display_name] = 0
					else:
						var events = member.add_exp_capped(share, ceiling)
						exp_per_member[member.character.display_name] = share
						if not events.is_empty():
							level_up_events[member.character.display_name] = events

	if battlefield_root:
		battlefield_root.queue_free()

	actors.clear()
	turn_queue.clear()

	await get_tree().process_frame

	emit_signal("battle_finished", victory, exp_per_member, level_up_events)

	battle_ending = false


## Called when the party uses an Emergency Exit item.
## Ends the battle immediately without victory, death, or XP.
## Party HP is preserved at current values.
func flee_battle() -> void:
	if battle_ending:
		return
	battle_ending = true
	change_state("BattleEnd")
	if is_instance_valid(reticle_ui):
		reticle_ui.close(true)
	reset_ca_material()
	battle_hud.reset_augur_panel()
	save_party_state()
	if battlefield_root:
		battlefield_root.queue_free()
	actors.clear()
	turn_queue.clear()
	await get_tree().process_frame
	# Emit flee signal so gamecontrol returns to dungeon without game-over
	emit_signal("battle_fled")
	battle_ending = false


func save_party_state():
	# First zero out everyone — actors that died were queue_freed and won't appear below
	for member in context.run_state.party_members:
		member.set_hp(0)

	# Overwrite with actual HP for actors still alive
	for actor in actors:
		if actor.team == BattleActor.Team.PLAYER and is_instance_valid(actor) and actor.party_member:
			actor.party_member.set_hp(actor.hp)



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

func screen_shake(source: BattleActor, target: BattleActor, dir: Vector3, active_strength: float, target_strength: float):

	active_shake_strength = active_strength
	target_shake_strength = target_strength
	active_base_follow_position = active_anchor.global_position
	target_base_follow_position = target_anchor.global_position


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
	selected_attack_skips_targeting = false
	selected_is_struggle = false
	
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
	ca_defaults["ca_strength"] = ca_mesh_mat.get_shader_parameter("ca_strength")

func follow_anchor(anchor: Node3D, source: Node3D):

	if anchor == active_anchor:
		active_anchor_source = source

	elif anchor == target_anchor:
		target_anchor_source = source

	elif anchor == active_look_anchor:
		active_look_source = source

	elif anchor == target_look_anchor:
		target_look_source = source

	# Snap the anchor immediately so PhantomCamera reads the correct position
	# on the same frame it's assigned, rather than waiting for _process().
	if source != null and is_instance_valid(source):
		anchor.global_position = source.global_position


func focus_actor(actor: BattleActor):
	if actor == null:
		return
	follow_anchor(active_anchor, actor.get_follow_anchor("active"))
	follow_anchor(active_look_anchor, actor.get_look_anchor("active"))
	# Restore normal damping — guards against the intro/overview glide leaving slow values active.
	if is_instance_valid(active_cam):
		active_cam.set_follow_damping_value(ACTIVE_CAM_NORMAL_DAMPING)
		active_cam.set_look_at_damping(false)


## Authored follow-damping value for active_cam (matches the scene file).
const ACTIVE_CAM_NORMAL_DAMPING := Vector3(0.2, 0.2, 0.2)
## Slow follow-damping used for the intro glide at the start of the first player turn.
const ACTIVE_CAM_INTRO_DAMPING := Vector3(0.5, 0.5, 0.5)
## Matching slow look-at damping for the intro glide (active_cam has no look damping normally).
const ACTIVE_CAM_INTRO_LOOK_DAMPING := 0.5
## How long to wait for the slow glide to arrive before restoring normal damping.
const ACTIVE_CAM_INTRO_DURATION := 4.0

## Authored damping values for target_cam (match the scene file).
const TARGET_CAM_NORMAL_DAMPING := Vector3(0.35, 0.35, 0.35)
const TARGET_CAM_NORMAL_LOOK_DAMPING := 0.157
## Intro damping for target_cam — same slow values as the active cam intro.
const TARGET_CAM_INTRO_DAMPING := Vector3(0.5, 0.5, 0.5)
const TARGET_CAM_INTRO_LOOK_DAMPING := 0.5

## Parks the active cam on the player-side overview anchors without
## touching the target cam or the toggle button state.
## Called once at battle start so the cam has a position to glide from.
func _park_active_cam_on_overview() -> void:
	follow_anchor(active_anchor, player_overview_anchor)
	follow_anchor(active_look_anchor, player_ground_center_anchor)


## Called once per battle, from handle_player_turn on the very first player turn.
## Enables slow follow + look damping so the cam glides from the overview
## position down to the actor, then restores normal values (look damping off).
func _intro_active_cam(actor: BattleActor) -> void:
	active_cam.set_follow_damping_value(ACTIVE_CAM_INTRO_DAMPING)
	active_cam.set_look_at_damping(true)
	active_cam.set_look_at_damping_value(ACTIVE_CAM_INTRO_LOOK_DAMPING)
	focus_actor(actor)
	await get_tree().create_timer(ACTIVE_CAM_INTRO_DURATION).timeout
	if is_instance_valid(active_cam):
		active_cam.set_follow_damping_value(ACTIVE_CAM_NORMAL_DAMPING)
		active_cam.set_look_at_damping(false)

func focus_target(actor: BattleActor):
	if actor == null:
		return
	follow_anchor(target_anchor, actor.get_follow_anchor("target"))
	follow_anchor(target_look_anchor, actor.get_look_anchor("target"))
	# Restore normal target cam damping — guards against overview/intro glide leaving slow values.
	if is_instance_valid(target_cam):
		target_cam.set_follow_damping_value(TARGET_CAM_NORMAL_DAMPING)
		target_cam.set_look_at_damping(true)
		target_cam.set_look_at_damping_value(TARGET_CAM_NORMAL_LOOK_DAMPING)


func focus_idle_orbit():

	target_cam.set_follow_offset(Vector3.ZERO)
	target_cam.set_look_at_offset(Vector3.ZERO)

	follow_anchor(target_anchor, idle_orbiter)
	follow_anchor(target_look_anchor, idle_orbit_pivot)
	if is_instance_valid(battle_hud):
		battle_hud.sync_overview_button(false)


## Switch only the active_cam (left viewport) to the player-side overhead overview.
## Used when an enemy performs an AOE so the player can see the whole field.
## Applies slow damping for the glide in, then restores normal damping.
func focus_active_overview() -> void:
	active_cam.set_follow_damping_value(ACTIVE_CAM_INTRO_DAMPING)
	active_cam.set_look_at_damping(true)
	active_cam.set_look_at_damping_value(ACTIVE_CAM_INTRO_LOOK_DAMPING)
	follow_anchor(active_anchor, player_overview_anchor)
	follow_anchor(active_look_anchor, player_ground_center_anchor)
	await get_tree().create_timer(ACTIVE_CAM_INTRO_DURATION).timeout
	if is_instance_valid(active_cam):
		active_cam.set_follow_damping_value(ACTIVE_CAM_NORMAL_DAMPING)
		active_cam.set_look_at_damping(false)


## Switch only the target_cam (right viewport) to the enemy-side overhead overview.
## Used when the player confirms an AOE skill.
func focus_target_overview() -> void:
	follow_anchor(target_anchor, enemy_overview_anchor)
	follow_anchor(target_look_anchor, enemy_ground_center_anchor)


## Point the target_cam to the enemy-side overhead overview anchor.
## The active_cam is deliberately left untouched — the toggle button
## only controls the target (right) viewport idle state.
## enemy_overview_anchor (high up, enemy side) is the follow target.
## enemy_ground_center_anchor (enemy side, y=0) is the look-at target.
## Both must be positioned before this is called.
func focus_overview() -> void:
	follow_anchor(target_anchor, enemy_overview_anchor)
	follow_anchor(target_look_anchor, enemy_ground_center_anchor)
	if is_instance_valid(battle_hud):
		battle_hud.sync_overview_button(true)


func update_ui_state():
	if input_locked:
		return


	match input_stage:

		InputStage.COMMAND:
			if active_player_actor:
				focus_actor(active_player_actor)
			focus_idle_orbit()
			battle_ui.hide()  # hide legacy panel during radial
			_open_radial_for_actor(active_player_actor)

		InputStage.TARGET:
			if is_instance_valid(reticle_ui):
				# Let the reticle handle targeting — switch it to the right target set
				reticle_ui.set_support_targeting(support_targeting)
			else:
				# Legacy fallback
				battle_ui.show()
				var targets: Array
				if support_targeting:
					targets = actors.filter(func(a): return a.team == active_player_actor.team and a.can_be_targeted())
				else:
					targets = actors.filter(func(a): return a.team != active_player_actor.team and a.can_be_targeted())
				battle_ui.show_targets(targets)
				battle_ui.set_confirm_enabled(false)

		InputStage.PART:
			var parts = selected_target.get_visible_parts(removed_channels)
			battle_ui.show_body_part_targets(parts)
			battle_ui.set_confirm_enabled(false)

		InputStage.FILTER:
			focus_idle_orbit()
			if is_instance_valid(reticle_ui):
				reticle_ui.show_filter_options(removed_channels)
			else:
				battle_ui.show()
				battle_ui.show_filter_options()
				battle_ui.set_confirm_enabled(false)

		InputStage.CONFIRM:
			battle_ui.show()
			if selected_attack_skips_targeting:
				battle_ui.clear_targets()
				focus_idle_orbit()
			battle_ui.set_confirm_enabled(true)


func _on_confirm_pressed():
	if input_locked:
		return
	input_locked = true
	input_stage = InputStage.DONE
	if is_instance_valid(active_player_actor):
		active_player_actor.set_actor_state(BattleActor.STATE_ACTING)
	emit_signal("player_skill_used", active_player_actor, selected_command)
	# Save this action so it can be repeated next turn.
	if active_player_actor != null:
		_last_actions[active_player_actor.name] = {
			"command":     selected_command,
			"target":      weakref(selected_target) if selected_target != null else null,
			"body_part":   selected_body_part,
			"is_struggle": selected_is_struggle,
			"filter":      selected_filter,
		}
	# Motif discovery: first time using each character+skill combination.
	if active_player_actor != null and active_player_actor.party_member != null:
		var char_name : String = active_player_actor.name.to_lower().replace(" ", "_")
		MetaProgress.notify_encounter(
			"skill:" + char_name + ":" + selected_command,
			active_player_actor.name + " — " + selected_command.capitalize())

	var is_ammo_user = active_player_actor.party_member == null or not active_player_actor.party_member.has_will()

	# AOE skill confirmed — switch target viewport to overhead so the whole field is visible.
	if selected_attack_skips_targeting and not selected_is_struggle:
		focus_target_overview()

	match selected_command:
		"attack":
			if selected_is_struggle:
				# Struggle (e.g. Pistol Whip): random target, no ammo cost
				await_actor_turn(active_player_actor, func():
					active_player_actor.struggle_attack(actors, active_player_actor.attack_power)
				)
			else:
				if is_ammo_user:
					var ammo_cost = 1
					if not free_shot_pending and not context.run_state.spend_ammo(ammo_cost):
						print("Not enough ammo!")
						input_locked = false
						input_stage = InputStage.COMMAND
						update_ui_state()
						return
					free_shot_pending = false
				await_actor_turn(active_player_actor, func():
					active_player_actor.take_turn(selected_target, selected_body_part)
				)

		"special":
			if is_ammo_user:  # Kendall: Change Lens — costs ally will, not ammo
				await_actor_turn(active_player_actor, func():
					active_player_actor.use_lens(selected_filter)
				)
			else:
				var _special_targets = [selected_target] if selected_target != null else []
				var _special_part = selected_body_part
				await_actor_turn(active_player_actor, func():
					active_player_actor.use_skill("special", _special_targets, _special_part)
				)

		"support":
			var _sk = active_player_actor.get_skills().filter(func(s): return s["key"] == "support")
			var _is_aoe_sup = not _sk.is_empty() and _sk[0].get("aoe", false)
			var _support_targets = actors if _is_aoe_sup else ([selected_target] if selected_target != null else actors)
			await_actor_turn(active_player_actor, func():
				active_player_actor.use_skill("support", _support_targets)
			)
	



# ── Radial UI signal handlers ─────────────────────────────────────────────────

# skill_chosen fires when a skill is selected (and confirmed for AoE).
# For skills needing a target the radial handles target selection and fires
# both skill_chosen + target_chosen together.
func _on_radial_skill_chosen(skill_key: String, skill_dict: Dictionary = {}) -> void:
	# Set selected_command and all derived flags exactly as _on_command_selected
	# does, but WITHOUT calling update_ui_state — the radial owns the UI here.
	selected_command = skill_key
	# Prefer reading flags directly from the provided dict (struggle box passes
	# the full dict so we don't misread it via the actor's live skill list).
	var sd : Dictionary
	if not skill_dict.is_empty():
		sd = skill_dict
	else:
		var actor_skills = active_player_actor.get_skills() if active_player_actor else []
		var matches = actor_skills.filter(func(s): return s["key"] == skill_key)
		sd = matches[0] if not matches.is_empty() else {}
	var is_aoe      = sd.get("aoe", false)
	var is_struggle = sd.get("struggle", false)
	selected_attack_skips_targeting = is_aoe or is_struggle
	selected_is_struggle            = is_struggle
	if is_aoe or is_struggle:
		selected_target    = null
		selected_body_part = null


func _on_reticle_focus_requested(target: BattleActor) -> void:
	if target.team == BattleActor.Team.PLAYER:
		battle_hud.show_target(target)
		focus_actor(target)
	elif target.team == BattleActor.Team.ENEMY:
		if input_stage == InputStage.TARGET:
			focus_target(target)
		battle_hud.show_target(target)
	


func _on_radial_target_chosen(target: BattleActor) -> void:
	selected_target = target
	if support_targeting:
		focus_actor(target)
	elif target.team == BattleActor.Team.ENEMY:
		focus_target(target)
	battle_hud.show_target(selected_target)
	if support_targeting:
		# Ally target selected for support skill — go straight to confirm
		support_targeting = false
		input_stage = InputStage.CONFIRM
		_on_confirm_pressed()
	else:
		support_targeting = false


func _on_radial_part_chosen(part: BodyPartData) -> void:
	selected_body_part = part


func _on_radial_filter_chosen(channel: int) -> void:
	selected_filter = channel
	input_stage = InputStage.CONFIRM
	_on_confirm_pressed()


func _on_radial_confirmed() -> void:
	if battle_ending:
		return
	input_stage = InputStage.CONFIRM
	_on_confirm_pressed()

func _on_radial_cancelled() -> void:
	if battle_ending:
		return
	# Radial dismissed without selection — stay on COMMAND, just re-open radial
	if input_stage == InputStage.COMMAND:
		_open_radial_for_actor(active_player_actor)

# Open the radial skill ring for a player actor.
# Centred in the left viewport (active character side).
func _on_reticle_skill_chosen(skill: Dictionary) -> void:
	if battle_ending:
		return
	var skill_key := str(skill.get("key", ""))
	_on_radial_skill_chosen(skill_key, skill)
	# Derive support_targeting from skill flags, same logic as _on_command_selected.
	var is_aoe         := bool(skill.get("aoe", false))
	var is_struggle := bool(skill.get("struggle", false))
	var is_ally_target := bool(skill.get("ally_target", false))
	var is_enemy_target := bool(skill.get("enemy_target", false))
	
	match skill_key:
		"support":
			if is_aoe:
				support_targeting = true
			elif is_ally_target:
				support_targeting = true
			else:
				support_targeting = false  # default: ally
		"special":
			support_targeting = is_ally_target
			# Kendall's Unveil: ammo user with a special routes to FILTER (channel picker)
			var _is_ammo_user := active_player_actor != null and \
				(active_player_actor.party_member == null or \
				 not active_player_actor.party_member.has_will())
			if _is_ammo_user:
				input_stage = InputStage.FILTER
				if is_instance_valid(reticle_ui):
					reticle_ui.set_support_targeting(false)
				update_ui_state()
				return
		_:
			support_targeting = false
	print(support_targeting)
	if is_aoe or is_struggle:
		input_stage = InputStage.CONFIRM
	else:
		input_stage = InputStage.TARGET
	if is_instance_valid(reticle_ui):
		reticle_ui.set_support_targeting(support_targeting)
	update_ui_state()


func _on_reticle_cancelled() -> void:
	if battle_ending:
		return
	reset_selection()
	input_stage = InputStage.COMMAND
	if is_instance_valid(reticle_ui):
		reticle_ui.set_support_targeting(false)
	focus_idle_orbit()
	focus_actor(active_player_actor)


func _open_radial_for_actor(actor: BattleActor) -> void:
	if actor == null:
		return
	var skills  := actor.get_skills()
	var enemies := actors.filter(func(a): return a.team != actor.team and a.can_be_targeted())
	var allies  := actors.filter(func(a): return a.team == actor.team and a.can_be_targeted())

	# Open reticle UI (new system)
	if is_instance_valid(reticle_ui):
		reticle_ui.open(actor, skills, enemies, allies, removed_channels, player_cam, enemy_cam, is_tense_phase(), can_repeat_action())
		emit_signal("reticle_opened")



func _on_cancel_pressed():
	match input_stage:
		InputStage.TARGET:
			support_targeting = false  # always clear when stepping back from target
			input_stage = InputStage.COMMAND

		InputStage.PART:
			# With the reticle, PART is internal reticle state — reset it rather
			# than stepping back to TARGET which would re-trigger update_ui_state.
			if is_instance_valid(reticle_ui):
				reticle_ui.reset_selection()
			else:
				input_stage = InputStage.TARGET

		InputStage.FILTER:
			input_stage = InputStage.COMMAND

		InputStage.CONFIRM:
			match selected_command:
				"attack":
					if selected_attack_skips_targeting:
						input_stage = InputStage.COMMAND
					else:
						input_stage = InputStage.PART
				"special":
					var _is_ammo_user = active_player_actor.party_member == null \
							or not active_player_actor.party_member.has_will()
					if _is_ammo_user:
						input_stage = InputStage.COMMAND  # Change Lens: back to command
					else:
						input_stage = InputStage.PART  # all other specials: back to parts
				"support":  input_stage = InputStage.COMMAND
				_:          input_stage = InputStage.COMMAND

	update_ui_state()


func _on_command_selected(command):
	selected_command = command
	# Read skill flags: aoe = hits all enemies, struggle = random target (both skip targeting UI)
	var skills = active_player_actor.get_skills() if active_player_actor else []
	var skill_data = skills.filter(func(s): return s["key"] == command)
	var is_aoe      = not skill_data.is_empty() and skill_data[0].get("aoe", false)
	var is_struggle = not skill_data.is_empty() and skill_data[0].get("struggle", false)
	selected_attack_skips_targeting = is_aoe or is_struggle
	selected_is_struggle = is_struggle

	match command:
		"attack":
			if selected_attack_skips_targeting:
				selected_target = null
				selected_body_part = null
				input_stage = InputStage.CONFIRM
			else:
				input_stage = InputStage.TARGET
		"special":
			var _is_ammo_user = active_player_actor.party_member == null or not active_player_actor.party_member.has_will()
			if _is_ammo_user:
				input_stage = InputStage.FILTER  # Kendall: choose lens channel
			else:
				var _is_ally_special = not skill_data.is_empty() and skill_data[0].get("ally_target", false)
				support_targeting = _is_ally_special
				selected_body_part = null
				input_stage = InputStage.TARGET
		"support":
			var _is_aoe_support    = not skill_data.is_empty() and skill_data[0].get("aoe", false)
			var _is_ally_target    = not skill_data.is_empty() and skill_data[0].get("ally_target", false)
			var _is_enemy_target   = not skill_data.is_empty() and skill_data[0].get("enemy_target", false)
			if _is_aoe_support:
				# No targeting needed (Augur, Evade, Galvanize, Martyr, Waste)
				support_targeting = true
				input_stage = InputStage.CONFIRM
			elif _is_ally_target:
				# Pick an ally (Shelter, Embrace)
				support_targeting = true
				input_stage = InputStage.TARGET
			elif not _is_enemy_target:
				support_targeting = true
				input_stage = InputStage.TARGET
			elif _is_enemy_target:
				support_targeting = false
				input_stage = InputStage.TARGET
			else:
				# Fallback: pick an ally
				support_targeting = true
				input_stage = InputStage.TARGET
		_:
			input_stage = InputStage.CONFIRM

	update_ui_state()


func _on_target_selected(target):
	selected_target = target
	if target.team == BattleActor.Team.PLAYER:
		focus_actor(target)
	else:
		focus_target(target)

	if support_targeting:
		support_targeting = false
		input_stage = InputStage.CONFIRM
	elif target.team == BattleActor.Team.ENEMY:
		battle_hud.show_target(selected_target)
		input_stage = InputStage.PART
	else:
		_on_cancel_pressed()

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
