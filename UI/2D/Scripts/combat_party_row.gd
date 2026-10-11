class_name CombatPartyRow
extends PanelContainer
## One party member's panel. The layout is in combat_party_row.tscn; this only fills it in.

signal selected

@export var selected_marker := "* "
@export var anima_format := "Anima %d/%d"

@onready var _select: Button = %SelectButton
@onready var _corpus: ProgressBar = %CorpusBar
@onready var _anima: Label = %AnimaLabel
@onready var _gauge: ProgressBar = %GaugeBar
@onready var _order: Label = %OrderLabel


func _ready() -> void:
	# Otherwise a clicked button keeps focus and Space presses it instead of pausing.
	_select.focus_mode = Control.FOCUS_NONE
	_select.pressed.connect(func(): selected.emit())


func show_state(number: int, display_name: String, is_selected: bool, corpus: int, corpus_max: int,
		anima: int, anima_max: int, gauge: float, order_text: String) -> void:
	_select.text = "%s%d. %s" % [selected_marker if is_selected else "", number, display_name]
	_corpus.max_value = corpus_max
	_corpus.value = corpus
	_anima.text = anima_format % [anima, anima_max]
	_gauge.value = gauge
	_order.text = order_text
