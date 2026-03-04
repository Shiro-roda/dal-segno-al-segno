extends CanvasLayer

signal command_selected(command)
signal target_selected(target_actor)
signal body_part_selected(part)
signal filter_selected(channel)
signal confirm_pressed
signal cancel_pressed


@onready var attack_button: Button = $Panel/HBoxContainer/VBoxContainer/AttackButton
@onready var target_container: VBoxContainer = $Panel/HBoxContainer/VBoxContainer2/TargetContainer
@onready var change_lens_button: Button = $Panel/HBoxContainer/VBoxContainer/ChangeButton
@onready var confirm_button: Button = $Panel/HBoxContainer/VBoxContainer2/ConfirmButton
@onready var cancel_button: Button = $Panel/HBoxContainer/VBoxContainer2/CancelButton


var current_targets : Array = []

func _ready():
	
	attack_button.pressed.connect(_on_attack_pressed)
	change_lens_button.pressed.connect(_on_change_lens_pressed)
	confirm_button.pressed.connect(func(): emit_signal("confirm_pressed"))
	cancel_button.pressed.connect(func(): emit_signal("cancel_pressed"))


	hide()

func show_commands():
	show()
	target_container.hide()

func hide_commands():
	hide()

func hide_target_container():
	target_container.hide()


func set_confirm_enabled(enabled: bool):
	confirm_button.disabled = not enabled

func set_back_enabled(enabled: bool):
	cancel_button.disabled = not enabled

func set_lens_enabled(enabled: bool):
	change_lens_button.disabled = not enabled



func show_targets(targets: Array):
	current_targets = targets
	target_container.show()

	# Clear old buttons
	for child in target_container.get_children():
		child.queue_free()

	for target in targets:
		var btn = Button.new()
		btn.text = target.name
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


func _on_attack_pressed():
	emit_signal("command_selected", "attack")

func _on_target_pressed(target):
	emit_signal("target_selected", target)

func _on_body_part_pressed(part):
	emit_signal("body_part_selected", part)

func _on_change_lens_pressed():
	emit_signal("command_selected", "lens")

func _on_filter_pressed(channel):
	emit_signal("filter_selected", channel)
