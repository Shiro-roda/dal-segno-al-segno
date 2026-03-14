extends CanvasLayer

signal command_selected(command)
signal target_selected(target_actor)
signal body_part_selected(part)
signal filter_selected(channel)
signal confirm_pressed
signal cancel_pressed


@onready var command_container: VBoxContainer = $Panel/HBoxContainer/VBoxContainer
@onready var target_container: VBoxContainer = $Panel/HBoxContainer/VBoxContainer2/TargetContainer
@onready var confirm_button: Button = $Panel/HBoxContainer/VBoxContainer2/ConfirmButton
@onready var cancel_button: Button = $Panel/HBoxContainer/VBoxContainer2/CancelButton

var current_targets : Array = []

func _ready():
	hide()


func show_commands(actor: BattleActor = null):
	show()
	target_container.hide()
	for child in command_container.get_children():
		child.queue_free()
	if actor == null:
		return
	var skills = actor.get_skills()
	# Sort: attack first, then support, then special
	var order = {"attack": 0, "support": 1, "special": 2}
	skills.sort_custom(func(a, b):
		return order.get(a["key"], 3) < order.get(b["key"], 3)
	)
	for skill in skills:
		var btn = Button.new()
		btn.text = skill["name"]
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var key = skill["key"]
		btn.pressed.connect(func(): emit_signal("command_selected", key))
		command_container.add_child(btn)

func hide_commands():
	hide()

func hide_target_container():
	target_container.hide()










func clear_targets():
	for child in target_container.get_children():
		child.queue_free()
	target_container.hide()

func show_targets(targets: Array):
	current_targets = targets
	target_container.show()

	# Clear old buttons
	for child in target_container.get_children():
		child.queue_free()

	for target in targets:
		var btn = Button.new()
		btn.text = target.name
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func(): _on_target_pressed(target))
		target_container.add_child(btn)

func show_body_part_targets(parts: Array):
	target_container.show()

	# Clear old buttons
	for child in target_container.get_children():
		child.queue_free()

	for part in parts:
		var btn = Button.new()
		btn.text = part.part_name
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func(): _on_body_part_pressed(part))
		target_container.add_child(btn)

func show_filter_options():
	target_container.show()

	for child in target_container.get_children():
		child.queue_free()

	var r_btn = Button.new()
	r_btn.text = "Remove R"
	r_btn.pressed.connect(func(): _on_filter_pressed(1))
	target_container.add_child(r_btn)

	var g_btn = Button.new()
	g_btn.text = "Remove G"
	g_btn.pressed.connect(func(): _on_filter_pressed(2))
	target_container.add_child(g_btn)

	var b_btn = Button.new()
	b_btn.text = "Remove B"
	b_btn.pressed.connect(func(): _on_filter_pressed(4))
	target_container.add_child(b_btn)


func _on_target_pressed(target):
	emit_signal("target_selected", target)

func _on_body_part_pressed(part):
	emit_signal("body_part_selected", part)

func _on_filter_pressed(channel):
	emit_signal("filter_selected", channel)
