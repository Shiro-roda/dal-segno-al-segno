class_name CombatEnemyRow
extends VBoxContainer
## One enemy's name button and health bar. Layout lives in combat_enemy_row.tscn.

signal pressed

@export var target_marker := "> "

@onready var _button: Button = %SelectButton
@onready var _bar: ProgressBar = %HealthBar


func _ready() -> void:
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(func(): pressed.emit())


func show_state(display_name: String, is_targeted: bool, corpus: int, corpus_max: int, is_down: bool) -> void:
	_button.text = (target_marker if is_targeted else "") + display_name
	_button.disabled = is_down
	_bar.max_value = corpus_max
	_bar.value = corpus
