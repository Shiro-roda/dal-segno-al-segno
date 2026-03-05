extends CanvasLayer
class_name BattleHUD

@onready var player_container = $PlayerPanels
@onready var enemy_container = $EnemyPanels
@onready var target_info = $TargetInfo/TargetInfoBox

const ACTOR_PANEL = preload("res://scenes/UI/actor_panel.tscn")


var player_panels := {}
var enemy_panels := {}

func setup(actor_list : Array):
	for c in player_container.get_children():
		c.queue_free()

	for actor in actor_list:

		var panel = ACTOR_PANEL.instantiate()

		if actor.team == BattleActor.Team.PLAYER:
			player_container.add_child(panel)
			player_panels[actor] = panel
		else:
			continue

		panel.setup(actor)


func show_target(actor : BattleActor):

	target_info.show()

	target_info.get_node("NameLabel").text = actor.name
	target_info.get_node("HPBar").max_value = actor.max_hp
	target_info.get_node("HPBar").value = actor.hp
	target_info.get_node("HPText").text = "%d / %d" % [actor.hp, actor.max_hp]

func set_active_actor(actor, active:= true):

	if actor in player_panels:
		if active:
			player_panels[actor].modulate = Color(5.195, 5.195, 5.195, 1.0)
		else:
			player_panels[actor].modulate = Color.WHITE
