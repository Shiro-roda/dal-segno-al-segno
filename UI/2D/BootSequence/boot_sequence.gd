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
# Colours — refreshed from ThemeManager on ready and on theme change.
var C_GREEN        := Color.WHITE
var C_AMBER        := Color.WHITE
var C_RED          := Color.WHITE
var C_DIM          := Color.WHITE
var C_WHITE        := Color.WHITE
var C_BG           := Color.BLACK
var C_KEY_FACE     := Color.BLACK
var C_KEY_LIT_DUN  := Color.BLACK
var C_KEY_LIT_BAT  := Color.BLACK
var C_KEY_EDGE     := Color.BLACK
const LINE_H      := 22.0
const CHAR_DELAY  := 0.0   # seconds per character in typewriter
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
	_refresh_palette()
	ThemeManager.theme_changed.connect(_on_theme_changed)
	_build_draw_node()
	_build_post_lines()
	_build_skip_hint()
	hide()


func _refresh_palette() -> void:
	var p := ThemeManager.palette
	C_GREEN       = p.primary
	C_AMBER       = p.secondary
	C_RED         = p.alert
	C_DIM         = p.dim
	C_WHITE       = p.text
	C_BG          = p.bg
	C_KEY_FACE    = p.key_face
	C_KEY_LIT_DUN = p.key_lit_primary
	C_KEY_LIT_BAT = p.key_lit_secondary
	C_KEY_EDGE    = p.key_edge


func _on_theme_changed(_id: int) -> void:
	_refresh_palette()
	# Rebuild post lines so colour references in them are fresh
	_build_post_lines()
	if _draw_node:
		_draw_node.queue_redraw()


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


## Jump directly to the manual (skipping the POST sequence).
## Call this from the main menu or party menu "MANUAL" buttons.
func show_manual(start_page: int = 0) -> void:
	_phase        = Phase.MANUAL
	_manual_page  = start_page
	_post_done    = true
	if is_instance_valid(_manual_panel):
		_manual_panel.queue_free()
		_manual_panel = null
	if is_instance_valid(_skip_hint):
		_skip_hint.visible = false
	show()
	_draw_node.queue_redraw()
	_build_manual()


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
	var hex_serial := _random_hex(4) + "-" + _random_hex(4) + "-" + _random_hex(8)
	var hex_bios   := _random_hex(4) + "h"
	var hex_cmos   := _random_hex(2) + "h"
	_post_lines = [
		_line("OURO BORO SYSTEMS  OUROBOY SECURITY UNIT  BIOS REV 1.04C", C_WHITE, 0.0),
		_line("(C) OURO BORO SYSTEMS INC.  ALL RIGHTS RESERVED", C_DIM, 0.10),
		_line("UNIT S/N: " + hex_serial, C_DIM, 0.18),
		_line(" ", C_DIM, 0.0),
		_line("CPU: NOUS-V  3.20GHz  FSB:800MHz  L2:512K", C_GREEN, 0.0),
		_line("MEMORY TEST ........ 131072K", C_GREEN, 0.0),
		_line("EXTENDED MEMORY .... 131072K OK", C_GREEN, 0.28),
		_line(" ", C_DIM, 0.04),
		_line("BIOS CHECKSUM ...... " + hex_bios + "  PASS", C_GREEN, 0.0),
		_line("CMOS CONFIG ........ " + hex_cmos + "    PASS", C_GREEN, 0.0),
		_line("RTC: " + _rtc_string() + "             PASS", C_GREEN, 0.04),
		_line(" ", C_DIM, 0.0),
		_line("PERIPHERAL ENUMERATION:", C_WHITE, 0.0),
		_line("  DISPLAY .......... ONYX-CRT  640x960  PHOSPHOR-G", C_GREEN, 0.0),
		_line("  STORAGE .......... FERRO-CELL 512K  WEAR:LOW", C_GREEN, 0.0),
		_line("  INPUT MATRIX ..... TACTILE ARRAY  84-KEY  OK", C_GREEN, 0.0),
		_line("  AUDIO ............ OBS-DSP  3CH MONO  OK", C_GREEN, 0.0),
		_line("  COMM ANTENNA ..... PASSIVE  NO CARRIER", C_GREEN, 0.0),
		
		_line("SYNESTHESIA ENGINE INIT:", C_WHITE, 0.0),
		_line("  BIOMETRIC OCULAR    CORPA-SCAN SUBSYSTEM  OK", C_GREEN, 0.0),
		_line("  NEURAL MESH PORT .. DENDRITE I/F REV 2  STANDBY", C_GREEN, 0.0),
		_line("  ENV HAZARD MON .... PARTICULATE / RAD / GAS  OK", C_GREEN, 0.0),
		_line("  PROXIMITY ALERT ... SONAR MESH  3.0m RADIUS  OK", C_GREEN, 0.0),
		
		_line("STRUCTURAL SURVEY DAEMON:", C_WHITE, 0.0),
		_line("  ZONE REGISTRY ....  LOADING KNOWN SECTORS", C_GREEN, 0.0),
		_line("  TOPOLOGY CACHE .... PARTIAL  (UNCHARTED REGIONS FLAGGED)", C_AMBER, 0.0),
		_line("  ARCHITECT SIGNATURE ... NOT FOUND (EXPECTED)", C_DIM, 0.0),
		_line("  FAULTLINE TETHER ...... DISRUPTED  CHECK ANCHOR POINTS", C_AMBER, 0.10),
		
		_line("SECURITY SUBSYSTEM:", C_WHITE, 1.5),
		_line("  CIPHER ENGINE ..... ONYX-CRYPT  256-bit  OK", C_GREEN, 0.0),
		_line("  ANIMUS CONTAMINANT LOCK ........ BIOMETRIC COMPROMISED (SEEK IMMEDIATE MEDICAL ASSISTANCE/EUTHANASIA)", C_RED, 0.0),
		_line("  INTRUSION LOG ..... 1 EVENT(S) SINCE LAST BOOT, 1 EVENT(S) PRIOR (2 INTRUDERS FOUND)", C_AMBER, 0.0),
		_line("  SAFEGUARD MODE .... CUSTOM(ADMIN OVERRIDE)", C_RED, 0.0),
		_line(" ", C_DIM, 0.04),
		_line("  WARNING: MUNICIPAL AUTHORITY SIGNATURE  --  NO RESPONSE (LOCAL OYARSE NOT FOUND, ANCILLARY ELDIRA ABSENT)", C_AMBER, 1.56),
		_line("  WARNING: BIOMASS ENCROACHMENT DETECTED IN CACHE", C_AMBER, 0.0),
		_line("  SYSTEM MESSAGE: have fun loser", C_RED, 0.56),
		_line(" ", C_DIM, 0.04),
		_line("ALL CRITICAL SYSTEMS OPERATIONAL(QUERY RETURNED VARIABLE RESULTS)", C_AMBER, 0.22),
		_line(" ", C_DIM, 0.04),
		_line("PRESS ANY KEY TO CONTINUE TO PROVISIONARY MANUAL_", C_WHITE, 0.0),
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
		_char_timer = 0.0#CHAR_DELAY
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


# Wrapping text block — uses RichTextLabel so wrapping works in a plain Control.
func _add_wrapped(parent: Control, text: String, pos: Vector2,
		width: float, height: float, fs: int = 11, col: Color = C_DIM) -> void:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = false
	rtl.scroll_active = false
	rtl.fit_content = false
	rtl.text = text
	rtl.position = pos
	rtl.size = Vector2(width, height)
	rtl.add_theme_font_override("normal_font", _font_mono)
	rtl.add_theme_font_size_override("normal_font_size", fs)
	rtl.add_theme_color_override("default_color", col)
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rtl)


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
	 ["\u2190",1.0],["\u2193",1.0],["\u2191",1.0],["\u2192",1.0]],
]

# Keys that are active in a given context — label -> annotation
const _DUNGEON_KEYS : Dictionary = {
	"A": "Rotate view LEFT",
	"D": "Rotate view RIGHT",
	"\u2190": "Move LEFT",
	"\u2192": "Move RIGHT",
	"\u2191": "Move FORWARD",
	"\u2193": "Move BACKWARD",
	"TAB": "Systems Menu",
	"Q": "Toggle channel R",
	"W": "Toggle channel G",
	"E": "Toggle channel B",
}

const _BATTLE_KEYS : Dictionary = {
	"ESC":   "Cancel / deselect",
	"TAB":   "Arrangement View Toggle",
	"\u2190": "Cycle LEFT",
	"\u2192": "Cycle RIGHT",
	"\u2191": "Cycle FORWARD",
	"\u2193": "Move BACKWARD",
	"SPACE": "Confirm Selection",
	"ENTER": "Confirm Selection",
}

func _page_keyboard() -> void:
	var p := _manual_panel
	# BG
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	p.add_child(bg)

	_add_header(p, "OPTIONAL SYSTEM KEYBOARD REFERENCE", 30)

	# Context labels
	_add_label(p, "ACTIVE IN DUNGEON", Vector2(700, 34), 11, C_GREEN)
	_add_label(p, "ACTIVE IN BATTLE",  Vector2(900, 34), 11, C_RED)

	# Draw keyboard
	_draw_keyboard(p, Vector2(60, 80))

	# Annotation table
	_draw_key_table(p, _DUNGEON_KEYS, Vector2(60, 550),  C_GREEN,  "DUNGEON")
	_draw_key_table(p, _BATTLE_KEYS,  Vector2(680, 550), C_RED, "BATTLE")
	# Mouse / pointer entries that can't light up on the keyboard diagram
	_draw_mouse_table(p, Vector2(60, 760))

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
			var face   : Color = C_AMBER if (in_bat and in_dun) else C_RED if in_bat else C_KEY_LIT_DUN if in_dun else C_KEY_FACE
			var edge   : Color = C_AMBER if (in_bat and in_dun) else C_GREEN if in_dun else (C_RED if in_bat else C_KEY_EDGE)

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
			var text_col : Color = C_BG if (in_bat and in_dun) else C_WHITE if (in_bat or in_dun) else C_DIM
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


func _draw_mouse_table(parent: Control, origin: Vector2) -> void:
	_add_label(parent, "-- CURSOR (DUNGEON) --", Vector2(origin.x, origin.y + 10), 12, C_GREEN)
	var entries := [
		["LMB", "Select available room space / move to a previously built room"],
		["RMB", "Inspect room details"],
	]
	var y := origin.y + 32.0
	for e in entries:
		_add_label(parent, "[ %-5s ]" % e[0], Vector2(origin.x, y), 12, C_GREEN)
		_add_label(parent, e[1], Vector2(origin.x + 110, y), 12, C_WHITE)
		y += 19.0


# ── PAGE 1: DUNGEON REFERENCE ─────────────────────────────────────────────────

func _page_dungeon() -> void:
	var p := _manual_panel
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	p.add_child(bg)

	_add_header(p, "ENVIRONMENTAL COMPOSITION SYSTEM REFERENCE", 30)

	_draw_phase_strip(p, Vector2(60, 70))
	_draw_resource_gloss(p, Vector2(60, 590))

	_nav_divider(p)
	_add_nav_bar(p)


func _draw_phase_strip(parent: Control, origin: Vector2) -> void:
	_add_label(parent, "COMPOSITION PHASES", origin, 16, C_WHITE)
	var phases := [
		["DA CAPO  /  DA CAPO AL SEGNO", C_GREEN,
			"Compose freely and familiarize yourself with your environment. Assemble portions of the Segno at three separate chapels, then place the first Segno room. It will spawn once you return to the Atrium."],
		["DAL SEGNO", C_AMBER,
			"Continue to explore and grow. Once expanding past the minimum radius (visible by toggling the B channel), you will be able to return to the previous Segno room and move it to the frontier to save your progress."],
		["DS AL SEGNO", Color(1.0, 0.4, 0.4, 1.0),
			"Carry the Segno to a new Segno room. All previous encounters are reprimed, and the level cap on your experience is lifted. No AP or BB restore, so you will need to prepare items and stock up on BB."],
	]
	var CARD_W   : float = 1160.0
	var CARD_H   : float = 150.0
	var CARD_GAP : float = 10.0
	var cy : float = origin.y + 24.0
	for ph in phases:
		var pname : String = ph[0]
		var pcol  : Color  = ph[1]
		var pdesc : String = ph[2]
		var box := ColorRect.new()
		box.position = Vector2(origin.x, cy)
		box.size     = Vector2(CARD_W, CARD_H)
		box.color    = Color(pcol.r * 0.07, pcol.g * 0.07, pcol.b * 0.07, 1.0)
		parent.add_child(box)
		var bar := ColorRect.new()
		bar.position = Vector2(origin.x, cy)
		bar.size     = Vector2(3, CARD_H)
		bar.color    = pcol
		parent.add_child(bar)
		_add_label(parent, pname, Vector2(origin.x + 16, cy + 10), 18, pcol)
		_add_wrapped(parent, pdesc,
				Vector2(origin.x + 16, cy + 36), CARD_W - 32, CARD_H - 44, 16, C_WHITE)
		cy += CARD_H + CARD_GAP


func _draw_resource_gloss(parent: Control, origin: Vector2) -> void:
	_add_label(parent, "RESOURCES", origin, 16, C_WHITE)
	var res := [
		["REVISIONS \u21ba", C_WHITE, "Reroll charges for composition selection."],
		["TIES \u2312",      C_WHITE, "Empty rooms to serve as bridges; can be connected to all adjacent spaces."],
		["CUTS \u20b5",      C_AMBER, "Currency optionally accumulated from combat encounters. May be spent in shop rooms for a variety of items and resources."],
	]
	var ry := origin.y + 42.0
	for rv in res:
		_add_label(parent, rv[0], Vector2(origin.x, ry), 17, rv[1])
		_add_wrapped(parent, rv[2],
				Vector2(origin.x + 160, ry), 900.0, 38.0, 14, C_DIM)
		ry += 62.0



# ── PAGE 2: BATTLE REFERENCE ─────────────────────────────────────────────────

func _page_battle() -> void:
	var p := _manual_panel
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	p.add_child(bg)

	_add_header(p, "COMBAT MANUAL  //  AUGMENTED UNREALITY RETICLES", 30)

	# Left column
	_draw_tempo_diagram(p, Vector2(60, 70))
	_draw_skill_types(p, Vector2(60, 300))

	# Right column
	_draw_stat_gloss(p, Vector2(700, 70))
	_draw_reticle_legend(p, Vector2(700, 420))

	_nav_divider(p)
	_add_nav_bar(p)


func _draw_tempo_diagram(parent: Control, origin: Vector2) -> void:
	_add_label(parent, "TURN ORDER  (TEMPO)", origin, 15, C_WHITE)
	var lines := [
		"Each combatant accumulates TEMPO equal to their BPM stat each tick, until one or more combatants have over 100.",
		"Combatants take their turns in descending order until none possess 100+ TEMPO, and ticks resume.",
	]
	var y := origin.y + 22.0
	for ln in lines:
		_add_wrapped(parent, ln, Vector2(origin.x, y), 560.0, 62.0, 13, C_WHITE)
		y += 36.0

	# Tempo bar diagram
	y += 8.0
	_add_label(parent, "TEMPO SCORES:", Vector2(origin.x, y), 13, C_WHITE)
	var bar_x := origin.x + 110
	var bw    := 400.0
	var actors := [
		["Ally 1",    0.34, C_GREEN],
		["Ally 2",    0.72, C_GREEN],
		["Hostile 1", 0.15, C_RED],
		["Hostile 2", 0.94, C_RED],
	]
	y += 18.0
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
		_add_label(parent, "%-8s" % a[0], Vector2(origin.x, y - 1), 11, a[2])
		_add_label(parent, "%d%%" % int(float(a[1])*100), Vector2(bar_x + bw + 6, y - 1), 14, C_WHITE)
		y += 20.0


func _draw_stat_gloss(parent: Control, origin: Vector2) -> void:
	_add_label(parent, "COMBAT STATS", origin, 15, C_WHITE)
	var stats := [
		["SHARP",  C_WHITE, "Base combat power."],
		["FLAT",   C_WHITE, "Resistance. Reduces incoming damage at a rate of \nSHARP^2/(SHARP+FLAT)."],
		["CORPUS", C_RED,              "Bodily integrity."],
		["ANIMA",   Color(0.3,0.7,1,1),            "Spiritual integrity. Required for semimaterial entities to use their abilities, else they must fight through inferior or self-destructive means."],
		["BEAT BOLTS", C_AMBER,       "Ammunition for your anti-immaterial firearm."] 
	]
	var y := origin.y + 42.0
	for sv in stats:
		var cr := ColorRect.new()
		cr.position = Vector2(origin.x, y + 2)
		cr.size     = Vector2(4, 18)
		cr.color    = sv[1]
		parent.add_child(cr)
		_add_label(parent, "%-11s" % sv[0], Vector2(origin.x + 10, y), 14, sv[1])
		_add_wrapped(parent, sv[2], Vector2(origin.x + 110, y), 490.0, 58.0, 13, C_DIM)
		y += 64.0


func _draw_skill_types(parent: Control, origin: Vector2) -> void:
	_add_label(parent, "SKILL TYPES", origin, 14, C_WHITE)
	var types := [
		["ATTACK", C_GREEN,  "Basic attack. Usually costs 2 AP, or 1 BB for firearm users. -100 TEMPO"],
		["SUPPORT",     C_AMBER,  "Assists one's allies through healing, positive status effects, or stat increases. Usually costs 1 AP -150 TEMPO"],
		["SPECIAL", C_RED,    "Especially powerful techniques that vary from soul to soul. Usually costs 3 AP. -180 TEMPO"],
	]
	var CARD_W : float = 560.0
	var CARD_H : float = 78.0
	var GAP    : float = 10.0
	var cy : float = origin.y + 22.0
	for st in types:
		var sname : String = st[0]
		var scol  : Color  = st[1]
		var sdesc : String = st[2]
		var box := ColorRect.new()
		box.position = Vector2(origin.x, cy)
		box.size     = Vector2(CARD_W, CARD_H)
		box.color    = Color(scol.r * 0.07, scol.g * 0.07, scol.b * 0.07, 1.0)
		parent.add_child(box)
		var bar := ColorRect.new()
		bar.position = Vector2(origin.x, cy)
		bar.size     = Vector2(3, CARD_H)
		bar.color    = scol
		parent.add_child(bar)
		_add_label(parent, sname, Vector2(origin.x + 14, cy + 8), 12, scol)
		_add_wrapped(parent, sdesc,
				Vector2(origin.x + 14, cy + 30), CARD_W - 20, CARD_H - 36, 14, C_WHITE)
		cy += CARD_H + GAP


func _draw_reticle_legend(parent: Control, origin: Vector2) -> void:
	_add_label(parent, "AUGMENTED UNREALITY RETICLE", origin, 16, C_WHITE)
	var entries := [
		[C_WHITE, "Skill reticles appear in the left viewport — click to select, click target to confirm."],
		[C_RED, "Enemy reticles track your opponents in the right viewport. Click to target."],
		[C_GREEN, "Ally reticles become targetable when a support skill is selected."],
		[C_AMBER,   "Part reticles appear after selecting an enemy — target specific body parts."],
		[C_DIM,   "Detail panel shows stats and active status effects (requires the use of AUGUR)."],
	]
	var y := origin.y + 22.0
	for ev in entries:
		var cr := ColorRect.new()
		cr.position = Vector2(origin.x, y + 6)
		cr.size     = Vector2(10, 10)
		cr.color    = ev[0]
		parent.add_child(cr)
		_add_wrapped(parent, ev[1], Vector2(origin.x + 18, y), 520.0, 46.0, 14, C_DIM)
		y += 40.0
