# BattleUI — legacy panel stub.
# The radial UI (BattleRadialUI) handles all input now.
# This node is kept for signal compatibility with battle_manager.
extends CanvasLayer

signal command_selected(command)
signal target_selected(target_actor)
signal body_part_selected(part)
signal filter_selected(channel)
signal confirm_pressed
signal cancel_pressed

var current_targets : Array = []

func _ready():
	hide()

# All methods below are stubs — the radial UI handles everything.
func show_commands(_actor = null): pass
func hide_commands(): hide()
func hide_target_container(): pass
func hide_confirmation(): pass
func clear_targets(): pass
func show_targets(_targets: Array): pass
func show_body_part_targets(_parts: Array): pass
func show_filter_options(): pass
func set_confirm_enabled(_enabled: bool): pass
