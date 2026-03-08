extends CanvasLayer
class_name BattleHUD

@onready var player_container = $PlayerPanels
@onready var target_info = $TargetInfo/TargetInfoBox
@onready var _queue_panel: PanelContainer = $TurnQueue
@onready var _queue_vbox: VBoxContainer = $BattleLog/HBoxContainer/TurnQueue
@onready var vbox: VBoxContainer = $BattleLog/HBoxContainer/Log


const ACTOR_PANEL = preload("res://scenes/UI/actor_panel.tscn")

const LOG_MAX_LINES    = 5
const CHATTER_DURATION = 3.0   # seconds a voice line stays visible
const QUEUE_STEPS      = 8     # how many acts ahead to project

var player_panels := {}
var enemy_panels := {}

# Log node refs — created at runtime if not found in scene
var _log_panel   : PanelContainer
var _log_label   : RichTextLabel
var _chatter_label : Label
var _chatter_timer : SceneTreeTimer
var _log_lines   : Array = []

# Turn order queue strip

var _queue_labels : Array = []


func _ready_log() -> void:
	# Only build once — guard against multiple setup() calls
	if _log_label != null:
		return

	# Find or create the panel
	_log_panel = get_node_or_null("BattleLog")
	if _log_panel == null:
		_log_panel = PanelContainer.new()
		_log_panel.name = "BattleLog"
		add_child(_log_panel)



	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_log_panel.add_child(vbox)

	_chatter_label = Label.new()
	_chatter_label.name = "ChatterLabel"
	_chatter_label.add_theme_font_size_override("font_size", 14)
	_chatter_label.modulate = Color(1.0, 0.9, 0.5, 1.0)  # warm yellow
	_chatter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_chatter_label.text = ""
	vbox.add_child(_chatter_label)

	_log_label = RichTextLabel.new()
	_log_label.name = "LogLabel"
	_log_label.bbcode_enabled = false
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.scroll_active = false
	_log_label.add_theme_font_size_override("normal_font_size", 14)
	
	_log_label.text = ""
	vbox.add_child(_log_label)


func _ready_queue() -> void:
	if not _queue_labels.is_empty():
		return  # already built

	_queue_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_queue_vbox.add_theme_constant_override("separation", 2)

	for i in range(QUEUE_STEPS):
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.clip_text = true
		_queue_vbox.add_child(lbl)
		_queue_labels.append(lbl)


func refresh_queue(manager) -> void:
	if _queue_labels.is_empty():
		return
	var queue : Array = manager.get_projected_queue(QUEUE_STEPS)
	var active = manager.active_player_actor
	for i in range(_queue_labels.size()):
		var lbl : Label = _queue_labels[i]
		if i < queue.size():
			var entry : Dictionary = queue[i]
			var actor : BattleActor = entry["actor"]
			var tempo : float = entry["tempo"]
			# Two-line format: name on top, tempo value below
			lbl.text = actor.name + "\n" + str(int(tempo))
			if actor == active and i == 0:
				lbl.modulate = Color(1.0, 0.95, 0.3, 1.0)   # gold - acting now
			elif actor.team == BattleActor.Team.PLAYER:
				lbl.modulate = Color(0.75, 0.95, 1.0, 1.0)  # pale blue - ally
			else:
				lbl.modulate = Color(1.0, 0.55, 0.55, 1.0)  # pale red - enemy
		else:
			lbl.text = ""


func push_log(msg: String) -> void:
	_log_lines.append(msg)
	if _log_lines.size() > LOG_MAX_LINES:
		_log_lines = _log_lines.slice(_log_lines.size() - LOG_MAX_LINES)
	if _log_label:
		_log_label.text = "\n".join(_log_lines)


func push_chatter(msg: String) -> void:
	if _chatter_label == null:
		return
	_chatter_label.text = msg
	if _chatter_timer != null:
		# just reset by overwriting — the old await will expire harmlessly
		pass
	_chatter_timer = get_tree().create_timer(CHATTER_DURATION)
	await _chatter_timer.timeout
	if _chatter_label and _chatter_label.text == msg:
		_chatter_label.text = ""

func setup(actor_list : Array):
	_ready_log()
	_ready_queue()

	for c in player_container.get_children():
		c.queue_free()

	for actor in actor_list:
		# Wire battle log and chatter signals for every actor
		if actor.has_signal("battle_log") and not actor.battle_log.is_connected(push_log):
			actor.battle_log.connect(push_log)
		if actor.has_signal("chatter") and not actor.chatter.is_connected(push_chatter):
			actor.chatter.connect(push_chatter)

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
