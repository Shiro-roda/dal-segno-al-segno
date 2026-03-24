extends Area3D
class_name WorldTrigger
# Auto-fires when the player walks into the area.
# Use for: battle triggers, scene transitions, cutscene starts.
#
# For a tutorial battle: set trigger_type = BATTLE and assign encounter.

signal triggered

enum TriggerType {
	DIALOGUE,    # play dialogue then emit triggered
	BATTLE,      # start a battle via GameController
	EVENT,       # start an event scene via GameController
	TRANSITION,  # load a new world scene via GameController
	GAME_START,  # build run + tutorial/companion-select flow (intro scene use)
	CUSTOM,      # just emit triggered, world scene handles it
}

@export var trigger_type   : TriggerType = TriggerType.CUSTOM
@export var dialogue       : EncounterDialogue
@export var encounter      : EncounterData
@export var event_scene    : PackedScene
@export var world_scene    : PackedScene
@export var one_shot       : bool = true

var _used : bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if one_shot and _used:
		return
	_used = true
	_fire()


func _fire() -> void:
	var gc = GameController

	match trigger_type:
		TriggerType.DIALOGUE:
			var box = get_tree().get_first_node_in_group("world_dialogue")
			if box and dialogue != null:
				var run = gc.current_run if gc else null
				await box.play_lines(dialogue, run)
			emit_signal("triggered")

		TriggerType.BATTLE:
			if gc and encounter != null:
				emit_signal("triggered")
				gc.start_battle(encounter)

		TriggerType.EVENT:
			if gc and event_scene != null:
				emit_signal("triggered")
				gc.start_event(event_scene)

		TriggerType.TRANSITION:
			if gc and world_scene != null:
				emit_signal("triggered")
				gc.start_world(world_scene)

		TriggerType.GAME_START:
			emit_signal("triggered")
			gc._begin_game_flow()

		TriggerType.CUSTOM:
			emit_signal("triggered")
