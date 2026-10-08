class_name Notice
extends CanvasLayer
## A short message at the top of the screen that fades away by itself. It never takes
## input or freezes anything, so it is safe to raise in the middle of play.
##
##   Notice.show_text(self, "Hue can level up. Open the party menu (TAB).")

const DEFAULT_SECONDS := 5.0

var _text := ""
var _seconds := DEFAULT_SECONDS


## Shows `text` for `seconds`. `from_node` only supplies the scene tree; the notice is
## parented to the tree's root so it survives a room change underneath it.
static func show_text(from_node: Node, text: String, seconds: float = DEFAULT_SECONDS) -> Notice:
	var notice := Notice.new()
	notice._text = text
	notice._seconds = seconds
	from_node.get_tree().root.add_child(notice)
	return notice


func _ready() -> void:
	layer = 110  # over the HUD and plan screen, under the party menu (120)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var colors := ThemeManager.palette

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.position.y = 24.0
	var box := StyleBoxFlat.new()
	var base: Color = colors.get("bg", Color.BLACK)
	box.bg_color = Color(base.r, base.g, base.b, 0.92)
	box.border_color = colors.get("secondary", Color.WHITE)
	box.set_border_width_all(2)
	box.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", box)
	root.add_child(panel)

	var label := Label.new()
	label.text = _text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

	var tween := create_tween()
	tween.tween_interval(maxf(_seconds - 0.6, 0.0))
	tween.tween_property(root, "modulate:a", 0.0, 0.6)
	tween.tween_callback(queue_free)
