extends Area3D
class_name NpcInteractable
# Place this as an Area3D in any world scene.
# Give it a CollisionShape3D child for the interaction radius.
# Set dialogue and/or on_interact_event in the Inspector.
#
# When the player enters the area, a prompt appears.
# When the player presses ui_accept, dialogue plays (if set),
# then on_interacted is emitted so the world scene can react.

signal on_interacted

# Dialogue to play when the player interacts. Optional.
@export var dialogue : EncounterDialogue

# If set, GameController.start_event() is called after dialogue finishes.
@export var event_scene : PackedScene

# Label shown above the NPC when the player is nearby. Set to "" to hide.
@export var prompt_text : String = "[ talk ]"

# Whether this NPC can only be interacted with once per session.
@export var one_shot : bool = false

var _player_nearby : bool = false
var _used          : bool = false
var _prompt_label  : Label3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_prompt()


func _build_prompt() -> void:
	if prompt_text == "":
		return
	_prompt_label = Label3D.new()
	_prompt_label.text = prompt_text
	_prompt_label.font_size = 32
	_prompt_label.modulate = Color(0.88, 0.83, 0.74, 0.0)  # start invisible
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.position = Vector3(0, 1.8, 0)
	_prompt_label.no_depth_test = true
	add_child(_prompt_label)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_nearby = true
	if _prompt_label and not (_used and one_shot):
		_prompt_label.modulate.a = 1.0


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_nearby = false
	if _prompt_label:
		_prompt_label.modulate.a = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not _player_nearby:
		return
	if one_shot and _used:
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_interact()


func _interact() -> void:
	if one_shot:
		_used = true
		if _prompt_label:
			_prompt_label.modulate.a = 0.0

	# Find the WorldDialogueBox in the scene (if any) and play dialogue
	if dialogue != null:
		var box = get_tree().get_first_node_in_group("world_dialogue")
		if box:
			# Pass run_state if GameController has one
			var gc = get_tree().get_first_node_in_group("game_controller")
			var run = gc.current_run if gc else null
			await box.play_lines(dialogue, run)

	emit_signal("on_interacted")

	if event_scene != null:
		var gc = get_tree().get_first_node_in_group("game_controller")
		if gc:
			gc.start_event(event_scene)
