extends Control
class_name ActorPanel

var actor : BattleActor

@onready var name_label: Label = $ActorPanelVBox/NameLabel
@onready var hp_bar: TextureProgressBar = $ActorPanelVBox/HPBar
@onready var hp_text: Label = $ActorPanelVBox/HPText




func setup(a : BattleActor):
	actor = a
	name_label.text = actor.name
	hp_bar.max_value = actor.max_hp

	update_display(a)

	actor.hp_changed.connect(update_display)
	actor.died.connect(_on_died)

func update_display(actor: BattleActor):
	hp_bar.value = actor.hp
	hp_text.text = "%d / %d" % [actor.hp, actor.max_hp]

func _on_died(_a):
	modulate.a = 0.4
