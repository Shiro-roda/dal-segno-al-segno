extends CanvasLayer
## BootSequence — CRT startup screen followed by a keyboard/UI reference manual.
##
## Plays on first run (or whenever show_boot() is called).
## Any keypress skips the POST phase and jumps straight to the manual.
## ESC or Enter on the manual closes it.

signal finished

# ── Constants ─────────────────────────────────────────────────────────────────
const FONT_MONO   := "res://UI/Themes/Fonts/SpaceMono-Bold.ttf"
const FONT_TERM   := "res://UI/Themes/Fonts/TerminalVector.ttf"
const C_GREEN     := Color(0.18, 1.00, 0.35, 1.0)
const C_AMBER     := Color(1.00, 0.72, 0.08, 1.0)
const C_RED       := Color(1.00, 0.22, 0.18, 1.0)
const C_DIM       := Color(0.45, 0.55, 0.45, 0.7)
const C_WHITE     := Color(0.92, 0.95, 0.92, 1.0)
const C_BG        := Color(0.012, 0.018, 0.012, 1.0)
const C_KEY_FACE  := Color(0.10, 0.13, 0.10, 1.0)
const C_KEY_LIT   := Color(0.08, 0.55, 0.22, 1.0)
const C_KEY_EDGE  := Color(0.30, 0.40, 0.30, 0.85)
const LINE_H      := 22.0
const CHAR_DELAY  := 0.0000   # seconds per character in typewriter
const LINE_DELAY  := 0.24    # pause between POST lines

# ── State ─────────────────────────────────────────────────────────────────────
enum Phase { POST, MANUAL, DONE }
var _phase        : Phase = Phase.POST
var _font_mono    : Font  = null
var _font_term    : Font  = null
var _draw_node    : Control = null
var _skip_hint    : Label   = null

# POST
var _post_lines   : Array = []   # Array of {text, color, delay_after}
var _shown_lines  : Array = []   # lines fully printed so far
var _cur_line_idx : int   = 0
var _cur_char_idx : int   = 0
var _line_timer   : float = 0.0
var _char_timer   : float = 0.0
var _post_done    : bool  = false

# Manual
var _manual_page  : int   = 0
var _manual_panel : Control = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 128
	add_to_group("boot_sequence")
	_font_mono = load(FONT_MONO) as Font
	_font_term = load(FONT_TERM) as Font
	_build_draw_node()
	_build_post_lines()
	_build_skip_hint()
	hide()


func show_boot() -> void:
	_phase         = Phase.POST
	_shown_lines   = []
	_cur_line_idx  = 0
	_cur_char_idx  = 0
	_line_timer    = 0.0
	_char_timer    = 0.0
	_post_done     = false
	_manual_page   = 0
	if is_instance_valid(_manual_panel):
		_manual_panel.queue_free()
		_manual_panel = null
	show()
	_draw_node.queue_redraw()


func _build_draw_node() -> void:
	_draw_node = Control.new()
	_draw_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_node.connect("draw", _on_draw)
	add_child(_draw_node)


func _build_skip_hint() -> void:
	_skip_hint = Label.new()
	_skip_hint.text = "[ ANY KEY ] SKIP POST"
	_skip_hint.add_theme_font_override("font", _font_mono)
	_skip_hint.add_theme_font_size_override("font_size", 11)
	_skip_hint.add_theme_color_override("font_color", C_DIM)
	_skip_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.offset_left  = -240
	_skip_hint.offset_top   = -32
	_skip_hint.offset_right = -12
	_skip_hint.offset_bottom = -10
	add_child(_skip_hint)


# ── POST line data ─────────────────────────────────────────────────────────────

func _build_post_lines() -> void:
	_post_lines = [
		_line("DALSEG SYSTEMS INC.  SEGNO/BIOS  REV 1.04C", C_WHITE, 0.0),
		_line("COPYRIGHT (C) DALSEG SYSTEMS  ALL RIGHTS RESERVED", C_DIM, 0.14),
		_line("", C_DIM, 0.0),
		_line("CPU: MORTEM-II  3.20GHz  FSB:800MHz  L2:512K", C_GREEN, 0.0),
		_line("CHECKING EXTENDED MEMORY  131072K OK", C_GREEN, 0.22),
		_line("", C_DIM, 0.04),
		_line("BIOS CHECKSUM ........... F4A8h  PASS", C_GREEN, 0.0),
		_line("CMOS CONFIG ............. 09h    PASS", C_GREEN, 0.0),
		_line("RTC: " + _rtc_string() + "                       PASS", C_GREEN, 0.0),
		_line("", C_DIM, 0.04),
		_line("DETECTING DEVICES:", C_WHITE, 0.0),
		_line("  PRIMARY DISPLAY ........ ONYX-CRT  640x960  60Hz", C_GREEN, 0.0),
		_line("  VIEWPORT SPLIT ......... 2x 638px  GAP:4px", C_GREEN, 0.0),
		_line("  PHYSICS TIMER .......... 60 ticks/sec", C_GREEN, 0.0),
		_line("  INPUT CONTROLLER ....... KBRD/MOUSE  OK", C_GREEN, 0.0),
		_line("  AUDIO DEVICE ........... SEGNO-DSP  3CH  OK", C_GREEN, 0.0),
		_line("", C_DIM, 0.04),
		_line("LOADING ENCOUNTER KERNEL:", C_WHITE, 0.0),
		_line("  TEMPO ENGINE ........... BASE 60Hz  OK", C_GREEN, 0.0),
		_line("  TEMPO SLOW MULT ........ 0.40x", C_GREEN, 0.0),
		_line("  DODGE PROBABILITY ...... 0.50", C_GREEN, 0.0),
		_line("  STRUGGLE MISS/SELF ..... 0.35 / 0.25", C_GREEN, 0.0),
		_line("  LIFESTEAL RATIO ........ 0.50", C_GREEN, 0.0),
		_line("  DEFENSE FORMULA ........ DMG^2 / (DMG + FLAT)", C_GREEN, 0.0),
		_line("", C_DIM, 0.04),
		_line("LOADING DUNGEON KERNEL:", C_WHITE, 0.0),
		_line("  SEGNO CHARGE CAP ....... 3", C_GREEN, 0.0),
		_line("  SEGNO MIN DIST ......... 4 rooms (Manhattan)", C_GREEN, 0.0),
		_line("  CEILING BONUS TABLE .... [+1,+2,+3,+2,+1, 0]", C_GREEN, 0.0),
		_line("  GUN NATIVE CLIP ........ 6 rounds", C_GREEN, 0.0),
		_line("", C_DIM, 0.04),
		_line("LOADING PROGRESSION TABLE:", C_WHITE, 0.0),
		_line("  EXP CURVE .............. [0,10,30,58,92,131...]", C_GREEN, 0.0),
		_line("  LEVEL HARD CAP ......... 99  STATIC TABLE:15", C_GREEN, 0.0),
		_line("", C_DIM, 0.12),
		_line("ALL SYSTEMS NOMINAL", C_GREEN, 0.18),
		_line("", C_DIM, 0.04),
		_line("PRESS ANY KEY TO CONTINUE _", C_WHITE, 0.0),
	]


func _rtc_string() -> String:
	# Format current system time as a BIOS RTC readout
	var t := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d  %02d:%02d:%02d" % [
		t["year"], t["month"], t["day"],
		t["hour"], t["minute"], t["second"]]


func _random_hex(n: int) -> String:
	var chars := "0123456789ABCDEF"
	var s := ""
	for i in n:
		s += chars[randi() % chars.length()]
	return s


func _line(text: String, col: Color, delay: float) -> Dictionary:
	return {"text": text, "color": col, "delay": delay}


# ── Frame update ──────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not visible:
		return
	match _phase:
		Phase.POST:
			_tick_post(delta)
		Phase.MANUAL:
			pass   # manual is event-driven


func _tick_post(delta: float) -> void:
	if _post_done:
		return
	if _cur_line_idx >= _post_lines.size():
		_post_done = true
		_skip_hint.visible = false
		return

	var line_data : Dictionary = _post_lines[_cur_line_idx]
	var full_text : String = line_data["text"]

	# Typewriter per character
	_char_timer -= delta
	if _char_timer <= 0.0:
		_char_timer = CHAR_DELAY
		if _cur_char_idx <= full_text.length():
			_cur_char_idx += 1
			_draw_node.queue_redraw()

	# Once line is fully typed, wait delay_after then advance
	if _cur_char_idx >= full_text.length():
		_line_timer -= delta
		if _line_timer <= 0.0:
			_shown_lines.append({
				"text":  full_text,
				"color": line_data["color"]
			})
			_cur_line_idx += 1
			_cur_char_idx  = 0
			_line_timer    = LINE_DELAY + float(line_data["delay"])
			_draw_node.queue_redraw()


# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match _phase:
			Phase.POST:
				if _post_done:
					_advance_post()
				else:
					_skip_post()
			Phase.MANUAL:
				if event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER or \
						event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
					_close()
				elif event.keycode == KEY_LEFT or event.keycode == KEY_A:
					_set_manual_page(max(0, _manual_page - 1))
				elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
					_set_manual_page(min(_manual_page_count() - 1, _manual_page + 1))
		get_viewport().set_input_as_handled()


func _skip_post() -> void:
	# Flush all POST lines immediately and go straight to "press any key" state
	_shown_lines = []
	for l in _post_lines:
		if l["text"] != "":
			_shown_lines.append({"text": l["text"], "color": l["color"]})
	_cur_line_idx = _post_lines.size()
	_cur_char_idx = 0
	_post_done    = true
	_skip_hint.visible = false
	_draw_node.queue_redraw()


func _advance_post() -> void:
	_phase = Phase.MANUAL
	_draw_node.queue_redraw()
	_skip_hint.visible = false
	_build_manual()


# Called when player presses a key on the final POST line ("PRESS ANY KEY")
func _input_post_advance(event: InputEvent) -> void:
	if _post_done and event is InputEventKey and event.pressed and not event.echo:
		_advance_post()


func _close() -> void:
	_phase = Phase.DONE
	hide()
	emit_signal("finished")


# ── Draw ──────────────────────────────────────────────────────────────────────

func _on_draw() -> void:
	var vp := Vector2(1280, 960)
	# Background
	_draw_node.draw_rect(Rect2(Vector2.ZERO, vp), C_BG)

	match _phase:
		Phase.POST:
			_draw_post()
		Phase.MANUAL:
			pass  # manual uses Control nodes


func _draw_post() -> void:
	var x    : float = 48.0
	var y    : float = 48.0
	var fs   : int   = 15

	# Printed lines
	for entry in _shown_lines:
		_draw_node.draw_string(_font_mono, Vector2(x, y), entry["text"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, entry["color"])
		y += LINE_H

	# Currently typing line
	if _cur_line_idx < _post_lines.size():
		var ld   : Dictionary = _post_lines[_cur_line_idx]
		var part : String     = ld["text"].substr(0, _cur_char_idx)
		# Cursor blink
		var blink : bool = int(Time.get_ticks_msec() * 0.003) % 2 == 0
		if blink:
			part += "_"
		_draw_node.draw_string(_font_mono, Vector2(x, y), part,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ld["color"])

	# Scanline overlay
	_draw_scanlines()


func _draw_scanlines() -> void:
	var vp := Vector2(1280, 960)
	var y : float = 0.0
	while y < vp.y:
		_draw_node.draw_rect(Rect2(Vector2(0, y), Vector2(vp.x, 1)),
				Color(0, 0, 0, 0.18))
		y += 3.0


# ── Manual ────────────────────────────────────────────────────────────────────

func _manual_page_count() -> int:
	return 3  # page 0=keyboard, 1=dungeon ref, 2=battle ref


func _build_manual() -> void:
	if is_instance_valid(_manual_panel):
		_manual_panel.queue_free()
	_manual_panel = Control.new()
	_manual_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_manual_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_manual_panel)
	_populate_manual_page()


func _set_manual_page(p: int) -> void:
	_manual_page = p
	if is_instance_valid(_manual_panel):
		_manual_panel.queue_free()
	_manual_panel = Control.new()
	_manual_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_manual_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_manual_panel)
	_populate_manual_page()


func _populate_manual_page() -> void:
	match _manual_page:
		0: _page_keyboard()
		1: _page_dungeon()
		2: _page_battle()


# ── Manual page helpers ───────────────────────────────────────────────────────

func _add_label(parent: Control, text: String, pos: Vector2,
		fs: int = 13, col: Color = C_GREEN, font: Font = null) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", fs)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_font_override("font", font if font else _font_mono)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)
	return lbl


func _add_header(parent: Control, text: String, y: float) -> void:
	# Horizontal rule + title
	var cr := ColorRect.new()
	cr.color = Color(C_GREEN.r, C_GREEN.g, C_GREEN.b, 0.25)
	cr.position = Vector2(40, y - 4)
	cr.size     = Vector2(1200, 1)
	parent.add_child(cr)
	_add_label(parent, text, Vector2(40, y + 4), 16, C_WHITE)


func _add_nav_bar(parent: Control) -> void:
	var pages := ["[0] KEYBOARD", "[1] DUNGEON", "[2] BATTLE"]
	var x := 40.0
	for i in pages.size():
		var col := C_GREEN if i == _manual_page else C_DIM
		_add_label(parent, pages[i], Vector2(x, 926), 12, col)
		x += 200.0
	_add_label(parent, "[ A / D  or  ARROW KEYS ] NAVIGATE    [ ESC / ENTER / SPACE ] CLOSE",
			Vector2(680, 926), 11, C_DIM)


func _nav_divider(parent: Control) -> void:
	var cr := ColorRect.new()
	cr.color   = Color(C_GREEN.r, C_GREEN.g, C_GREEN.b, 0.20)
	cr.position = Vector2(40, 916)
	cr.size     = Vector2(1200, 1)
	parent.add_child(cr)


# ── PAGE 0: KEYBOARD ──────────────────────────────────────────────────────────

const _KEY_ROWS : Array = [
	# each entry: [label, w]  — w is relative width multiplier
	[["ESC",1.4],["F1",1.0],["F2",1.0],["F3",1.0],["F4",1.0],
	 ["F5",1.0],["F6",1.0],["F7",1.0],["F8",1.0],["F9",1.0],["F10",1.0]],
	[["`",1.0],["1",1.0],["2",1.0],["3",1.0],["4",1.0],["5",1.0],
	 ["6",1.0],["7",1.0],["8",1.0],["9",1.0],["0",1.0],["-",1.0],["=",1.0],["BKSP",1.8]],
	[["TAB",1.6],["Q",1.0],["W",1.0],["E",1.0],["R",1.0],["T",1.0],
	 ["Y",1.0],["U",1.0],["I",1.0],["O",1.0],["P",1.0],["[",1.0],["]",1.0],["\\",1.4]],
	[["CAPS",1.8],["A",1.0],["S",1.0],["D",1.0],["F",1.0],["G",1.0],
	 ["H",1.0],["J",1.0],["K",1.0],["L",1.0],[";",1.0],["'",1.0],["ENTER",2.0]],
	[["SHIFT",2.4],["Z",1.0],["X",1.0],["C",1.0],["V",1.0],["B",1.0],
	 ["N",1.0],["M",1.0],[",",1.0],[".",1.0],["/",1.0],["SHIFT",2.4]],
	[["CTRL",1.6],["ALT",1.3],["SPACE",5.5],["ALT",1.3],["CTRL",1.6],
	 ["<",1.0],[">",1.0],["^",1.0],["v",1.0]],
]

# Keys that are active in a given context — label -> annotation
const _DUNGEON_KEYS : Dictionary = {
	"A": "Rotate view LEFT",
	"D": "Rotate view RIGHT",
	"TAB": "Party menu",
	"Q": "Toggle channel R",
	"W": "Toggle channel G",
	"E": "Toggle channel B",
}

const _BATTLE_KEYS : Dictionary = {
	"ESC":   "Cancel / deselect",
	"SPACE": "Confirm action",
	"ENTER": "Confirm action",
	"TAB":   "Party menu",
}

func _page_keyboard() -> void:
	var p := _manual_panel
	# BG
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	p.add_child(bg)

	_add_header(p, "SYSTEM KEYBOARD REFERENCE", 30)

	# Context labels
	_add_label(p, "ACTIVE IN DUNGEON", Vector2(700, 34), 11, C_GREEN)
	_add_label(p, "ACTIVE IN BATTLE",  Vector2(900, 34), 11, C_AMBER)

	# Draw keyboard
	_draw_keyboard(p, Vector2(60, 80))

	# Annotation table
	_draw_key_table(p, _DUNGEON_KEYS, Vector2(60, 550),  C_GREEN,  "DUNGEON")
	_draw_key_table(p, _BATTLE_KEYS,  Vector2(680, 550), C_AMBER, "BATTLE")

	_nav_divider(p)
	_add_nav_bar(p)


func _draw_keyboard(parent: Control, origin: Vector2) -> void:
	var UNIT  : float = 48.0
	var GAP   : float = 4.0
	var ROW_H : float = UNIT + GAP

	for ri in _KEY_ROWS.size():
		var row      : Array  = _KEY_ROWS[ri]
		var x        : float  = origin.x
		var y        : float  = origin.y + ri * ROW_H
		for ki in row.size():
			var entry  : Array  = row[ki]
			var klabel : String = entry[0]
			var kmult  : float  = float(entry[1])
			var kw     : float  = UNIT * kmult
			var kh     : float  = UNIT

			# Is this key relevant?
			var in_dun : bool = klabel in _DUNGEON_KEYS
			var in_bat : bool = klabel in _BATTLE_KEYS
			var face   : Color = C_KEY_LIT if (in_dun or in_bat) else C_KEY_FACE
			var edge   : Color = C_GREEN if in_dun else (C_AMBER if in_bat else C_KEY_EDGE)

			# Key body
			var cr := ColorRect.new()
			cr.position = Vector2(x + 2, y + 2)
			cr.size     = Vector2(kw - 4, kh - 4)
			cr.color    = face
			parent.add_child(cr)
			# Edge highlight (top+left 1px)
			var cr2 := ColorRect.new()
			cr2.position = Vector2(x, y)
			cr2.size     = Vector2(kw - 2, 1)
			cr2.color    = edge
			parent.add_child(cr2)
			var cr3 := ColorRect.new()
			cr3.position = Vector2(x, y)
			cr3.size     = Vector2(1, kh - 2)
			cr3.color    = edge
			parent.add_child(cr3)
			# Label
			var lbl := Label.new()
			lbl.text = klabel
			lbl.position = Vector2(x + 5, y + 6)
			lbl.add_theme_font_override("font", _font_mono)
			lbl.add_theme_font_size_override("font_size", 9)
			var text_col : Color = C_GREEN if in_dun else (C_AMBER if in_bat else C_DIM)
			lbl.add_theme_color_override("font_color", text_col)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(lbl)

			x += kw + GAP


func _draw_key_table(parent: Control, keys: Dictionary,
		origin: Vector2, col: Color, title: String) -> void:
	_add_label(parent, "-- " + title + " --", origin, 12, col)
	var y := origin.y + 22.0
	for key in keys.keys():
		_add_label(parent, "[ %-5s ]" % key, Vector2(origin.x, y), 12, col)
		_add_label(parent, keys[key],          Vector2(origin.x + 110, y), 12, C_WHITE)
		y += 19.0


# ── PAGE 1: DUNGEON REFERENCE ─────────────────────────────────────────────────

func _page_dungeon() -> void:
	var p := _manual_panel
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	p.add_child(bg)

	_add_header(p, "DUNGEON MAP  //  ROOM SYSTEM REFERENCE", 30)

	# Phase diagram
	_draw_phase_strip(p, Vector2(60, 70))

	# Room type table
	_draw_room_table(p, Vector2(60, 280))

	# Resource gloss
	_draw_resource_gloss(p, Vector2(680, 280))

	_nav_divider(p)
	_add_nav_bar(p)


func _draw_phase_strip(parent: Control, origin: Vector2) -> void:
	_add_label(parent, "DUNGEON PHASES", origin, 13, C_WHITE)
	var phases := [
		["DA CAPO",     C_GREEN,  "Build freely. Place the first Segno room."],
		["AL SEGNO",    C_AMBER,  "Find the Segno's next resting place."],
		["DS AL SEGNO", Color(1,0.4,0.4,1), "Tense phase. Only Struggle skills\nare available. No resource restore."],
	]
	var x := origin.x
	for ph in phases:
		var pname  : String = ph[0]
		var pcol   : Color  = ph[1]
		var pdesc  : String = ph[2]
		# Box
		var box := ColorRect.new()
		box.position = Vector2(x, origin.y + 24)
		box.size     = Vector2(270, 52)
		box.color    = Color(pcol.r * 0.10, pcol.g * 0.10, pcol.b * 0.10, 1.0)
		parent.add_child(box)
		var edge := ColorRect.new()
		edge.position = Vector2(x, origin.y + 24)
		edge.size     = Vector2(270, 2)
		edge.color    = pcol
		parent.add_child(edge)
		_add_label(parent, pname, Vector2(x + 8, origin.y + 28), 12, pcol)
		_add_label(parent, pdesc, Vector2(x + 8, origin.y + 46), 10, C_DIM)
		# Arrow
		if ph != phases.back():
			_add_label(parent, ">>", Vector2(x + 276, origin.y + 42), 14, C_DIM)
		x += 296.0


func _draw_room_table(parent: Control, origin: Vector2) -> void:
	_add_label(parent, "ROOM TYPES", origin, 13, C_WHITE)
	var rooms := [
		["BATTLE",    C_RED,    "Random enemy encounter. Rewards corpus,\nwill, and run resources on victory."],
		["SHOP",      C_AMBER,  "Spend accumulated blood-money on\nconsumables, relics, or stat upgrades."],
		["CHAPEL",    C_GREEN,  "Full-party corpus restore. Scales with\ndistance from last Segno."],
		["ELITE",     Color(1,0.5,0,1), "Stronger encounter. Drops rare loot\nor bonus stat upgrades."],
		["TREASURE",  Color(0.8,0.8,0.2,1), "No combat. Party levels up immediately.\nUnlocks new skills."],
		["BOSS",      C_RED,    "End-of-run encounter. Only spawns\nin AL FINE phase."],
	]
	var y := origin.y + 22.0
	for rm in rooms:
		var cr := ColorRect.new()
		cr.position = Vector2(origin.x, y - 2)
		cr.size     = Vector2(4, 32)
		cr.color    = rm[1]
		parent.add_child(cr)
		_add_label(parent, "%-10s" % rm[0], Vector2(origin.x + 12, y), 12, rm[1])
		_add_label(parent, rm[2], Vector2(origin.x + 120, y), 11, C_DIM)
		y += 40.0


func _draw_resource_gloss(parent: Control, origin: Vector2) -> void:
	_add_label(parent, "RESOURCES", origin, 13, C_WHITE)
	var res := [
		["CORPUS",   C_RED,   "Party hit points. Lost in battle, restored in chapels and with items."],
		["ANIMA",     C_AMBER, "Skill fuel. Spent to use skills.\nRestored by rest or relics."],
		["BEAT BOLTS",     Color(0.6,0.8,1,1), "Kendall's bullet stock. Spent each attack.\nResupplied in shops or via skills."],
		["REPRISE",  C_GREEN, "Reroll charges for room placement.\nLimited supply per run."],
		["ROAD TILE",C_DIM,   "Budget for room placement in AL SEGNO.\nSpent one per room placed."],
		["CUTS",    C_AMBER, "Accumulated from battles. Spent in shops."],
	]
	var y := origin.y + 22.0
	for rv in res:
		_add_label(parent, "%-10s" % rv[0], Vector2(origin.x, y), 12, rv[1])
		_add_label(parent, rv[2], Vector2(origin.x + 130, y), 10, C_DIM)
		y += 38.0


# ── PAGE 2: BATTLE REFERENCE ─────────────────────────────────────────────────

func _page_battle() -> void:
	var p := _manual_panel
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	p.add_child(bg)

	_add_header(p, "BATTLE SYSTEM  //  RETICLE REFERENCE", 30)

	_draw_tempo_diagram(p, Vector2(60, 70))
	_draw_stat_gloss(p, Vector2(60, 340))
	_draw_status_gloss(p, Vector2(680, 70))
	_draw_reticle_legend(p, Vector2(680, 480))

	_nav_divider(p)
	_add_nav_bar(p)


func _draw_tempo_diagram(parent: Control, origin: Vector2) -> void:
	_add_label(parent, "TURN ORDER  (TEMPO)", origin, 13, C_WHITE)
	var lines := [
		"Each actor accumulates TEMPO each round based on their TEMPO stat.",
		"When an actor has accumulated over 100 TEMPO (TEMPO >= 100), the actor takes their turn and loses 100-TEMPO.",
		"SLOW halves tempo gain.",
	]
	var y := origin.y + 22.0
	for ln in lines:
		_add_label(parent, ln, Vector2(origin.x, y), 11, C_DIM)
		y += 18.0

	# Fake tempo bar diagram
	y += 8.0
	_add_label(parent, "TEMPO BAR:", Vector2(origin.x, y), 11, C_WHITE)
	var bar_x := origin.x + 110
	var bw    := 480.0
	var actors := [
		["Kendall",  0.72, C_GREEN],
		["Hue",      0.55, Color(0.6,0.4,1,1)],
		["Shadow",   0.88, C_RED],
		["Shadow x2",0.31, Color(0.8,0.3,0.3,1)],
	]
	y += 2.0
	for a in actors:
		var filled := int(bw * float(a[1]))
		var barcr := ColorRect.new()
		barcr.position = Vector2(bar_x, y)
		barcr.size     = Vector2(bw, 14)
		barcr.color    = Color(0.05,0.05,0.05,1)
		parent.add_child(barcr)
		var fill := ColorRect.new()
		fill.position = Vector2(bar_x, y)
		fill.size     = Vector2(filled, 14)
		fill.color    = Color(a[2].r*0.7, a[2].g*0.7, a[2].b*0.7, 1)
		parent.add_child(fill)
		_add_label(parent, "%-12s" % a[0], Vector2(origin.x, y), 11, a[2])
		_add_label(parent, "%d%%" % int(float(a[1])*100), Vector2(bar_x + bw + 6, y), 11, C_DIM)
		y += 20.0


func _draw_stat_gloss(parent: Control, origin: Vector2) -> void:
	_add_label(parent, "COMBAT STATS", origin, 13, C_WHITE)
	var stats := [
		["SHARP",  Color(1,0.4,0.2,1), "Base attack power."],
		["FLAT",   Color(0.3,0.7,1,1), "Defense. Reduces incoming damage via SHARP^2/(SHARP+FLAT)."],
		["CORPUS", C_RED,              "Bodily integrity."],
		["ANIMA",   C_AMBER,            "Spiritual integrity."],
	]
	var y := origin.y + 22.0
	for sv in stats:
		var cr := ColorRect.new()
		cr.position = Vector2(origin.x, y - 1)
		cr.size     = Vector2(4, 18)
		cr.color    = sv[1]
		parent.add_child(cr)
		_add_label(parent, "%-6s" % sv[0], Vector2(origin.x + 10, y), 12, sv[1])
		_add_label(parent, sv[2], Vector2(origin.x + 80, y), 11, C_DIM)
		y += 26.0


func _draw_status_gloss(parent: Control, origin: Vector2) -> void:
	_add_label(parent, "STATUS EFFECTS", origin, 13, C_WHITE)
	var statuses := [
		["BLEEDING",   C_RED,               "Takes damage each turn (10% max CORPUS)."],
		["SLOW",       Color(0.5,0.5,1,1),  "TEMPO gain reduced to 40%."],
		["DODGING",    Color(0.4,1,0.6,1),  "50% chance to evade any incoming attack."],
		["SHIELD",     Color(0.8,0.8,0.3,1),"Temporary HP buffer absorbs damage first."],
		["COVERED",    Color(0.6,0.4,1,1),  "Damage redirected to covering ally."],
		["VICE",  C_AMBER,             "Actor heals 50% of damage dealt."],
		["MALICE",     Color(1,0.3,0.5,1),  "Actor counterattacks on taking damage."],
		["MARTYR",     Color(1,0.6,0.2,1),  "Converts damage taken into bonus offense."],
		["ENCASED",    Color(0.6,0.6,0.7,1),"Reduces incoming damage 40%. Breaks on acting."],
	]
	var y := origin.y + 22.0
	for sv in statuses:
		_add_label(parent, "%-12s" % sv[0], Vector2(origin.x, y), 11, sv[1])
		_add_label(parent, sv[2], Vector2(origin.x + 140, y), 11, C_DIM)
		y += 22.0


func _draw_reticle_legend(parent: Control, origin: Vector2) -> void:
	_add_label(parent, "AUGMENTED UNREALITY RETICLE", origin, 13, C_WHITE)
	var entries := [
		[C_GREEN, "Skill reticles appear in the left viewport — click to select, click target to confirm."],
		[C_AMBER, "Enemy reticles track your opponents in the right viewport. Click to target."],
		[Color(0.6,0.4,1,1), "Ally reticles appear only when a support skill is selected."],
		[C_DIM,   "Part reticles appear after selecting an enemy — target specific body parts."],
		[C_WHITE, "Corner brackets converge on spawn. Brighter when selected."],
		[C_DIM,   "Detail panel shows SHARP / FLAT / active status effects (requires the use of AUGUR)."],
	]
	var y := origin.y + 22.0
	for ev in entries:
		var cr := ColorRect.new()
		cr.position = Vector2(origin.x, y + 3)
		cr.size     = Vector2(10, 10)
		cr.color    = ev[0]
		parent.add_child(cr)
		_add_label(parent, ev[1], Vector2(origin.x + 18, y), 11, C_DIM)
		y += 22.0
