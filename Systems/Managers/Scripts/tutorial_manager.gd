extends Node
## TutorialManager — orchestrates the 4-step tutorial battle.
## Add as a child of BattleScene. It connects to BattleManager signals
## and drives the tutorial step-by-step.
##
## Steps:
##   0 = waiting for Kendall to Shoot
##   1 = dummy ally spawned, waiting for Kendall to use Augur
##   2 = Unveil unlocked, waiting for Kendall to use Unveil then Shoot a part
##   3 = done

# ── References ─────────────────────────────────────────────────────────────────
@onready var _manager    : Node   = get_parent().get_node("BattleManager")
@onready var _dialogue   : Node   = get_parent().get_node("DialogueLayer")
@onready var _reticle    : Node   = get_parent().get_node_or_null("BattleReticleUI")

# ── State ──────────────────────────────────────────────────────────────────────
var _step              : int  = 0
var _augur_used        : bool = false
var _unveil_used       : bool = false
var _dummy_spawned     : bool = false

# Dummy ally CharacterData resource — a shadow repurposed as a silent companion
const DUMMY_SCENE := preload("res://Characters/Scenes/BattleActors/PartyActors/hue_bactor.tscn")

# ── Dialogue helpers ───────────────────────────────────────────────────────────
func _make_line(speaker: String, text: String) -> DialogueLine:
	var l := DialogueLine.new()
	l.speaker = speaker
	l.text    = text
	l.typewriter = false
	return l

func _make_dialogue(lines: Array) -> EncounterDialogue:
	var d := EncounterDialogue.new()
	for l in lines:
		d.lines.append(l)
	return d

func _say(lines: Array) -> void:
	var d := _make_dialogue(lines)
	await _dialogue.play_lines(d, null)


# ── Boot ───────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Wait for the manager to finish setup, then check if this is a tutorial battle.
	await _manager.battle_manager_ready
	if _manager.context == null or not _manager.context.encounter.is_tutorial:
		set_process(false)
		return
	_manager.player_skill_used.connect(_on_skill_used)
	_manager.reticle_opened.connect(_apply_skill_lock)
	# Lock will be applied on first reticle_opened signal


# ── Skill lock ────────────────────────────────────────────────────────────────
## Tells the reticle which command keys are currently selectable.
func _apply_skill_lock() -> void:
	if _reticle == null or not _reticle.has_method("set_allowed_commands"):
		return
	match _step:
		0: _reticle.set_allowed_commands(["attack"])
		1: _reticle.set_allowed_commands(["support"])
		2: _reticle.set_allowed_commands(["special", "attack"])
		_: _reticle.set_allowed_commands([])  # empty = all allowed


# ── Signal handlers ───────────────────────────────────────────────────────────
func _on_skill_used(actor: BattleActor, command_key: String) -> void:
	if actor == null or actor.team != BattleActor.Team.PLAYER:
		return
	if actor.name != "Kendall":
		return

	match _step:
		0:
			if command_key == "attack":
				await _complete_step_0()
		1:
			if command_key == "support":
				_augur_used = true
				await _complete_step_1()
		2:
			if command_key == "special":
				_unveil_used = true
				await _on_unveil_used()
			elif command_key == "attack" and _unveil_used:
				await _complete_step_2()


# ── Step completions ──────────────────────────────────────────────────────────
func _complete_step_0() -> void:
	# Wait a beat for the attack animation to finish.
	await get_tree().create_timer(2.2, false).timeout

	# Spawn dummy ally
	_spawn_dummy_ally()
	await get_tree().process_frame

	# Unlock Augur on Kendall's party_member
	var kendall := _get_kendall()
	if kendall and kendall.party_member:
		if "Augur" not in kendall.party_member.skill_unlocks:
			kendall.party_member.skill_unlocks.append("Augur")

	_step = 1
	await _say([
		_make_line("Augur", "Portentious signs only you can see are all around you, and your companions may benefit from your discernment."),
	])
	_apply_skill_lock()
	if is_instance_valid(_reticle):
		_manager._open_radial_for_actor(_manager.active_player_actor)


func _complete_step_1() -> void:
	# Wait for augur animation
	await get_tree().create_timer(0.5, false).timeout

	# Unlock Unveil
	var kendall := _get_kendall()
	if kendall and kendall.party_member:
		if "Unveil" not in kendall.party_member.skill_unlocks:
			kendall.party_member.skill_unlocks.append("Unveil")

	_step = 2
	await _say([
		_make_line("Unveil", "Strip away the pretenses of perception itself to expose your foe's most intimate and fragile disfigurements."),
	])
	_apply_skill_lock()
	if is_instance_valid(_reticle):
		_manager._open_radial_for_actor(_manager.active_player_actor)


func _on_unveil_used() -> void:
	# Unveil used — now allow attack, prompt them to target a part
	await get_tree().create_timer(1.0, false).timeout
	await _say([
		_make_line("Shoot again.", "Understand that the price of understanding may be more than you can afford."),
	])


func _complete_step_2() -> void:
	_step = 3
	_apply_skill_lock()
	var kendall = _get_kendall()
	kendall.party_member.skill_unlocks.resize(0)
	# Tutorial complete — no further intervention needed


# ── Helpers ───────────────────────────────────────────────────────────────────
func _get_kendall() -> BattleActor:
	for actor in _manager.actors:
		if is_instance_valid(actor) and actor.name == "Kendall":
			return actor
	return null


func _spawn_dummy_ally() -> void:
	if _dummy_spawned:
		return
	_dummy_spawned = true

	var battlefield : Node3D = _manager.battlefield_root
	if battlefield == null:
		return

	# Find an empty player slot
	var slots_root := battlefield.get_node_or_null("PlayerSlots")
	if slots_root == null:
		return
	var slots := slots_root.get_children()
	var empty_slot : Node3D = null
	for slot in slots:
		# A slot is empty if no actor is positioned at its world position
		var occupied := false
		for actor in _manager.actors:
			if actor.team == BattleActor.Team.PLAYER and \
					actor.global_position.distance_to(slot.global_position) < 0.5:
				occupied = true
				break
		if not occupied:
			empty_slot = slot
			break
	if empty_slot == null:
		return

	var dummy : Node3D = DUMMY_SCENE.instantiate()
	dummy.name = "DummyShadow"
	dummy.display_name = "Ally"
	dummy.team = BattleActor.Team.PLAYER
	dummy.max_hp = 10
	dummy.hp = 10
	dummy.attack_power = 0
	dummy.flat_defense = 0
	dummy.bpm = 0
	dummy.tempo_pool = -9999.0  # never acts
	dummy.global_position = empty_slot.global_position

	# Give it a party_member so will ring shows
	var pm := PartyMemberData.new()
	pm.max_will = 4
	pm.will = 4
	dummy.party_member = pm

	battlefield.add_child(dummy)
	_manager.actors.append(dummy)
	# Refresh the reticle so the new ally appears in the box list.
	await get_tree().process_frame
	_manager.update_ui_state()
