## BattleNotes — hierarchical note-row battle menu.
##
## Notes are organised into NoteRow groups. Each row is a horizontal list of
## NoteBtn nodes laid out HBox-style on a staff. Selecting a note optionally
## expands a child NoteRow to its right; a second press on an already-selected
## leaf note confirms the full selection path.
##
## The caller builds a tree of NoteItem dicts and passes the root level to
## open(). BattleNotes emits item_confirmed(path) where path is an Array of
## NoteItem dicts from root to the confirmed leaf.
##
## NoteItem structure:
##   {
##     "label":    String,
##     "shape":    NoteShape,   # visual only — independent of depth
##     "color":    Color,
##     "detail":   String,      # shown in info card (optional)
##     "children": Array,       # Array[NoteItem] — empty = leaf
##     "data":     Variant,     # arbitrary payload
##   }

class_name BattleNotes
extends CanvasLayer

# ── Signals ─────────────────────────────────────────────────────────────────
signal item_confirmed(path: Array)
signal cancelled

# ── Note shapes (visual only) ───────────────────────────────────────────
enum NoteShape {
	WHOLE,      # hollow oval, no stem
	HALF,       # hollow oval + stem
	QUARTER,    # filled oval + stem
	SIXTEENTH,  # filled oval + stem + beam flags
	DIAMOND,    # filled diamond, no stem
}

# ── Palette ──────────────────────────────────────────────────────────────────
const FONT_PATH := "res://assets/Fonts/TerminalVector.ttf"
const C_ACCENT  := Color(0.52, 0.42, 0.28, 1.0)

# ── Timing ───────────────────────────────────────────────────────────────────
const SLIDE_TIME := 0.22
const MORPH_TIME := 0.18
const FADE_TIME  := 0.10

# ── Panel geometry ────────────────────────────────────────────────────────────
const PANEL_W_FRAC := 0.60
const PANEL_Y      := 760.0
const PANEL_H      := 200.0

# ── Staff geometry ───────────────────────────────────────────────────────────
const STAFF_TOP := 62.0
const LINE_SPC  := 13.0
const STAFF_MID := STAFF_TOP + 2.0 * LINE_SPC
const STAFF_BOT := STAFF_TOP + 4.0 * LINE_SPC

# ── Note geometry ────────────────────────────────────────────────────────────
const HEAD_RX    := 14.0
const HEAD_RY    :=  9.0
const STEM_TIP_Y := STAFF_TOP - 18.0
const BEAM_H     :=  5.0
const BEAM_GAP   :=  3.5
const NOTE_W     := 48.0
const NOTE_TOP   := STEM_TIP_Y - 6.0
const HEAD_CY    := STAFF_MID - NOTE_TOP
const NOTE_STEP  := 64.0
const FIRST_X    := 52.0
const BAR_SLOTS  := 4

# ── State ───────────────────────────────────────────────────────────────────
var _panel     : Control = null
var _row_stack : Array   = []  # [{row, sel_idx, sel_item}]
var _info_card : Control = null
var _sel_path  : Array   = []

# ══════════════════════════════════════════════════════════════════════════════
# Public API
# ══════════════════════════════════════════════════════════════════════════════

func open(items: Array) -> void:
	close(true)
	_panel = _StaffPanel.new()
	var vp : Vector2 = get_viewport().get_visible_rect().size
	_panel.custom_minimum_size = Vector2(vp.x * PANEL_W_FRAC, PANEL_H)
	_panel.size                = Vector2(vp.x * PANEL_W_FRAC, PANEL_H)
	_panel.position            = Vector2(-vp.x * PANEL_W_FRAC, PANEL_Y)
	add_child(_panel)
	var tw := _panel.create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "position:x", 0.0, SLIDE_TIME)
	await tw.finished
	await _push_row(items, FIRST_X)

func close(silent: bool = false) -> void:
	_dismiss_info_card()
	if is_instance_valid(_panel):
		_panel.queue_free()
		_panel = null
	_row_stack.clear()
	_sel_path.clear()
	if not silent:
		cancelled.emit()

# ══════════════════════════════════════════════════════════════════════════════
# Row management
# ══════════════════════════════════════════════════════════════════════════════

func _push_row(items: Array, start_cx: float) -> void:
	if not is_instance_valid(_panel): return
	var row := _NoteRow.new(_panel, start_cx)
	for item in items:
		row.add_note(item)
	_row_stack.push_back({ "row": row, "sel_idx": -1, "sel_item": {} })
	await row.animate_in(self)
	var depth := _row_stack.size() - 1
	for i in row.notes.size():
		var item : Dictionary = items[i]
		var ci   := i
		row.notes[i].pressed.connect(func(): _on_note_pressed(depth, ci, item))

func _collapse_to_depth(keep_depth: int) -> void:
	while _row_stack.size() > keep_depth + 1:
		var entry : Dictionary = _row_stack.pop_back()
		var row   : _NoteRow   = entry["row"]
		if is_instance_valid(row):
			await _fade_row(row)
	if _row_stack.size() > keep_depth:
		var top_entry : Dictionary = _row_stack[keep_depth]
		var top_row   : _NoteRow   = top_entry["row"]
		if is_instance_valid(top_row): top_row.reset_all()
		top_entry["sel_idx"]  = -1
		top_entry["sel_item"] = {}

func _fade_row(row: _NoteRow) -> void:
	if not is_instance_valid(row): return
	var tw := row.create_tween()
	tw.tween_property(row, "modulate:a", 0.0, FADE_TIME)
	await tw.finished
	if is_instance_valid(row): row.queue_free()

# ══════════════════════════════════════════════════════════════════════════════
# Note press handler
# ══════════════════════════════════════════════════════════════════════════════

func _on_note_pressed(depth: int, idx: int, item: Dictionary) -> void:
	if depth >= _row_stack.size(): return
	var entry : Dictionary = _row_stack[depth]
	var row   : _NoteRow   = entry["row"]
	if not is_instance_valid(row): return

	var already_selected : bool = (entry["sel_idx"] == idx)

	# Second press on already-selected leaf → confirm
	if already_selected and item.get("children", []).is_empty():
		_sel_path.resize(depth + 1)
		_sel_path[depth] = item
		close(true)
		item_confirmed.emit(_sel_path.duplicate())
		return

	# Different note pressed — collapse any deeper rows
	if not already_selected and _row_stack.size() > depth + 1:
		await _collapse_to_depth(depth)
		_dismiss_info_card()

	entry["sel_idx"]  = idx
	entry["sel_item"] = item
	_sel_path.resize(depth + 1)
	_sel_path[depth] = item

	row.set_all_dim(true)
	row.notes[idx].set_dim(false)
	row.notes[idx].morph_to(item.get("shape", NoteShape.QUARTER), MORPH_TIME)

	var children : Array = item.get("children", [])
	if children.is_empty():
		_spawn_info_card(item.get("label", ""), item.get("detail", ""),
				row.note_cx(idx))
		return

	await get_tree().create_timer(MORPH_TIME + 0.02).timeout
	await _push_row(children, row.note_cx(idx) + NOTE_STEP)

# ══════════════════════════════════════════════════════════════════════════════
# Info card
# ══════════════════════════════════════════════════════════════════════════════

func _spawn_info_card(title: String, detail: String, note_cx: float) -> void:
	_dismiss_info_card()
	if not is_instance_valid(_panel): return
	_info_card = _InfoCard.new(title, detail)
	var cx : float = minf(note_cx + HEAD_RX + 6.0, _panel.size.x - _InfoCard.CW - 4.0)
	_info_card.position = Vector2(cx, 4.0)
	_panel.add_child(_info_card)

func _dismiss_info_card() -> void:
	if is_instance_valid(_info_card):
		_info_card.queue_free()
		_info_card = null

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(_panel): return
	if not (event is InputEventMouseButton and event.pressed): return
	if not Rect2(_panel.global_position, _panel.size).has_point(event.position):
		close()

# ══════════════════════════════════════════════════════════════════════════════
# _NoteRow — horizontal HBox of notes, all children of _panel
# ══════════════════════════════════════════════════════════════════════════════

class _NoteRow extends Control:
	const _NS        := 64.0
	const _NW        := 48.0
	const _NOTE_TOP  := 38.0   # STEM_TIP_Y(44) - 6
	const _BEAM_Y    := 44.0   # STEM_TIP_Y
	const _BEAM_H    :=  5.0
	const _BEAM_GAP  :=  3.5
	const _HEAD_RX   := 14.0
	const _STEM_OX   := 13.0

	var notes    : Array   = []
	var first_cx : float   = 0.0
	var _panel   : Control = null
	var _beams   : Array   = []

	func _init(panel: Control, fcx: float) -> void:
		_panel   = panel
		first_cx = fcx
		panel.add_child(self)
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func add_note(item: Dictionary) -> void:
		var n := _NoteBtn.new(
			item.get("shape", 0),
			item.get("color", Color(0.52, 0.42, 0.28, 1.0)),
			item.get("label", ""))
		n.custom_minimum_size = Vector2(_NW, 100.0)
		n.size                = Vector2(_NW, 100.0)
		n.position            = Vector2(_panel.size.x + 20.0, _NOTE_TOP)
		n.modulate.a          = 0.0
		_panel.add_child(n)
		notes.append(n)

	func note_cx(i: int) -> float:
		return first_cx + i * _NS

	func animate_in(outer: Node) -> void:
		for j in notes.size():
			var n    : _NoteBtn = notes[j]
			var dest : float    = note_cx(j) - _NW * 0.5
			if j == 0:
				var tw := outer.create_tween().set_parallel(true)
				tw.tween_property(n, "modulate:a", 1.0, 0.08)
				tw.tween_property(n, "position:x", dest, 0.15)\
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				await tw.finished
			else:
				await _pull_in(outer, j, dest, n)

	func _pull_in(outer: Node, j: int, dest_x: float, n: _NoteBtn) -> void:
		if not is_instance_valid(_panel): return
		var bx0 : float = note_cx(j - 1) + _STEM_OX
		var bx1 : float = note_cx(j) - _HEAD_RX
		n.position   = Vector2(bx1 + _NW * 0.5, _NOTE_TOP)
		n.modulate.a = 0.0
		var seg := _BeamSeg.new(bx0, bx0, n.note_color, _BEAM_Y, _BEAM_H, _BEAM_GAP)
		_panel.add_child(seg)
		_beams.append(seg)
		var tw := outer.create_tween().set_parallel(true)
		tw.tween_method(func(v: float) -> void:
			if is_instance_valid(seg): seg.right_x = v; seg.queue_redraw(),
			bx0, bx1, 0.12)
		tw.tween_property(n, "position:x", dest_x, 0.12).set_trans(Tween.TRANS_LINEAR)
		tw.tween_property(n, "modulate:a", 1.0, 0.07)
		await tw.finished

	func set_all_dim(d: bool) -> void:
		for n in notes:
			if is_instance_valid(n): n.set_dim(d)

	func reset_all() -> void:
		for n in notes:
			if is_instance_valid(n):
				n.set_dim(false)
				n.restore_shape()

	func free_beams() -> void:
		for b in _beams:
			if is_instance_valid(b): b.queue_free()
		_beams.clear()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			free_beams()
			for n in notes:
				if is_instance_valid(n): n.queue_free()
			notes.clear()

# ══════════════════════════════════════════════════════════════════════════════
# _NoteBtn — procedurally drawn note button
# Shapes: WHOLE(0) HALF(1) QUARTER(2) SIXTEENTH(3) DIAMOND(4)
# ══════════════════════════════════════════════════════════════════════════════

class _NoteBtn extends Control:
	const _FONT := "res://assets/Fonts/TerminalVector.ttf"
	const _HCY  := 50.0
	const _HRX  := 14.0
	const _HRY  :=  9.0
	const _SXO  := 12.0
	const _SLEN := 40.0
	const _NW   := 48.0

	var _orig_shape : int
	var shape       : int
	var note_color  : Color
	var label_text  : String
	var stem_frac   : float = 0.0
	var flag_frac   : float = 0.0
	var _selected   : bool  = false

	signal pressed

	func _init(s: int, col: Color, lbl: String) -> void:
		_orig_shape = s; shape = s; note_color = col; label_text = lbl
		match s:
			1, 2, 3: stem_frac = 1.0
		if s == 3: flag_frac = 1.0

	func _ready() -> void:
		var btn := Button.new()
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.flat = true
		var e := StyleBoxEmpty.new()
		for k in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(k, e)
		btn.pressed.connect(func(): pressed.emit())
		add_child(btn)

	func set_dim(dimmed: bool) -> void:
		create_tween().set_trans(Tween.TRANS_SINE)\
			.tween_property(self, "modulate:a", 0.25 if dimmed else 1.0, 0.10)
		_selected = not dimmed; queue_redraw()

	func morph_to(new_shape: int, dur: float) -> void:
		shape = new_shape; stem_frac = 0.0; flag_frac = 0.0; queue_redraw()
		if not (new_shape == 1 or new_shape == 2 or new_shape == 3): return
		create_tween().tween_method(func(v: float) -> void:
			stem_frac = v
			if new_shape == 3: flag_frac = v
			queue_redraw(), 0.0, 1.0, dur)

	func restore_shape() -> void:
		shape = _orig_shape
		match _orig_shape:
			1, 2, 3: stem_frac = 1.0
			_:       stem_frac = 0.0
		flag_frac = 1.0 if _orig_shape == 3 else 0.0
		_selected = false; queue_redraw()

	func _draw() -> void:
		var cx := _NW * 0.5; var col := note_color
		if _selected:
			draw_circle(Vector2(cx, _HCY), _HRX + 8.0, Color(col.r, col.g, col.b, 0.15))
		match shape:
			0:  # WHOLE
				_oval(cx, _HCY, _HRX, _HRY, col)
				_oval(cx, _HCY, _HRX * 0.42, _HRY * 0.46, Color(0.08, 0.07, 0.06, 1.0))
			1:  # HALF
				_oval(cx, _HCY, _HRX, _HRY, col)
				_oval(cx, _HCY, _HRX * 0.42, _HRY * 0.46, Color(0.08, 0.07, 0.06, 1.0))
				_stem(cx, col)
			2:  # QUARTER
				_oval(cx, _HCY, _HRX, _HRY, col); _hilit(cx, col); _stem(cx, col)
			3:  # SIXTEENTH
				_oval(cx, _HCY, _HRX, _HRY, col); _hilit(cx, col)
				_stem(cx, col); _flags(cx, col)
			4:  # DIAMOND
				_diamond(cx, _HCY, col)
		if _selected:
			draw_arc(Vector2(cx, _HCY), _HRX + 6.0, 0.0, TAU, 28, col.lightened(0.30), 1.6)
		var font : Font = (load(_FONT) as Font) if ResourceLoader.exists(_FONT) \
				else ThemeDB.fallback_font
		var fsize := 9
		var lw := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		draw_string(font, Vector2(cx - lw * 0.5, size.y - 2.0),
				label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize,
				Color(0.88, 0.83, 0.74, 0.88))

	func _oval(cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 25:
			var a : float = TAU * i / 24.0 - 0.28
			pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry * 0.70))
		draw_colored_polygon(pts, col)

	func _hilit(cx: float, col: Color) -> void:
		var lc := Color(minf(col.r*1.7,1.0), minf(col.g*1.7,1.0), minf(col.b*1.7,1.0), 0.45)
		draw_line(Vector2(cx-_HRX*0.38, _HCY-_HRY*0.44),
				  Vector2(cx+_HRX*0.08, _HCY-_HRY*0.62), lc, 1.2)

	func _stem(cx: float, col: Color) -> void:
		if stem_frac < 0.001: return
		var sx := cx + _SXO; var base_y := _HCY - _HRY * 0.55
		draw_line(Vector2(sx, base_y), Vector2(sx, base_y - _SLEN * stem_frac), col, 2.5)

	func _flags(cx: float, col: Color) -> void:
		if flag_frac < 0.001: return
		var sx := cx + _SXO; var ty := _HCY - _HRY * 0.55 - _SLEN; var fl := 16.0 * flag_frac
		draw_polyline(PackedVector2Array([
			Vector2(sx, ty), Vector2(sx+fl, ty+6.0), Vector2(sx+fl*0.6, ty+14.0)]), col, 2.2)
		draw_polyline(PackedVector2Array([
			Vector2(sx, ty+8.0), Vector2(sx+fl, ty+14.0), Vector2(sx+fl*0.6, ty+22.0)]), col, 2.2)

	func _diamond(cx: float, cy: float, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx, cy-_HRX*0.75), Vector2(cx+_HRX, cy),
			Vector2(cx, cy+_HRX*0.75), Vector2(cx-_HRX, cy)]), col)
		var lc := Color(minf(col.r*1.6,1.0), minf(col.g*1.6,1.0), minf(col.b*1.6,1.0), 0.40)
		draw_line(Vector2(cx-_HRX, cy), Vector2(cx, cy-_HRX*0.75), lc, 1.2)


# ══════════════════════════════════════════════════════════════════════════════
# _BeamSeg — horizontal bar growing rightward between stem tips
# ══════════════════════════════════════════════════════════════════════════════

class _BeamSeg extends Control:
	var left_x : float; var right_x : float
	var _col   : Color; var _y0 : float; var _bh : float; var _bg : float
	func _init(lx:float,rx:float,col:Color,y0:float,bh:float,bg:float) -> void:
		left_x=lx; right_x=rx; _col=col; _y0=y0; _bh=bh; _bg=bg
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if right_x <= left_x: return
		draw_rect(Rect2(left_x, _y0, right_x - left_x, _bh), _col)

# ══════════════════════════════════════════════════════════════════════════════
# _StaffPanel — dark BG, scan lines, 5-line staff, time sig, barlines
# ══════════════════════════════════════════════════════════════════════════════

class _StaffPanel extends Control:
	const _BG   := Color(0.08,0.07,0.06,0.98)
	const _ACC  := Color(0.52,0.42,0.28,1.0)
	const _BDR  := Color(0.35,0.28,0.22,1.0)
	const _GRID := Color(0.12,0.10,0.09,1.0)
	const _LINE := Color(0.34,0.26,0.18,0.90)
	const _ST   := 62.0; const _SPC := 13.0
	const _FX   := 52.0; const _NS  := 64.0; const _BS := 4
	func _draw() -> void:
		var w := size.x; var h := size.y
		draw_rect(Rect2(0,0,w,h), _BG)
		draw_line(Vector2(0,0), Vector2(w,0), _ACC, 2.0)
		draw_line(Vector2(w-1,0), Vector2(w-1,h), _BDR, 1.0)
		for y in range(2,int(h),4):
			draw_line(Vector2(0,y), Vector2(w,y), _GRID, 0.7)
		var ty := _ST; var by := _ST + 4.0*_SPC
		for li in 5:
			draw_line(Vector2(8,_ST+li*_SPC), Vector2(w-6,_ST+li*_SPC), _LINE, 1.2)
		draw_line(Vector2(10,ty), Vector2(10,by), _ACC, 3.5)
		draw_line(Vector2(16,ty), Vector2(16,by), _BDR, 1.2)
		var bx : float = _FX + (_BS-0.5)*_NS
		while bx < w-8.0:
			draw_line(Vector2(bx,ty), Vector2(bx,by), _BDR, 1.2); bx += float(_BS)*_NS
		var font : Font = load("res://assets/Fonts/TerminalVector.ttf") \
				if ResourceLoader.exists("res://assets/Fonts/TerminalVector.ttf") \
				else ThemeDB.fallback_font
		draw_string(font, Vector2(19,_ST+_SPC*1.5), "4", HORIZONTAL_ALIGNMENT_LEFT,-1,10,_BDR)
		draw_string(font, Vector2(19,_ST+_SPC*3.3), "4", HORIZONTAL_ALIGNMENT_LEFT,-1,10,_BDR)

# ══════════════════════════════════════════════════════════════════════════════
# _InfoCard — small floating title+detail label
# ══════════════════════════════════════════════════════════════════════════════

class _InfoCard extends Control:
	const CW    := 140.0; const CH := 32.0
	const _FONT := "res://assets/Fonts/TerminalVector.ttf"
	const _BG   := Color(0.08,0.07,0.06,0.96)
	const _BDR  := Color(0.35,0.28,0.22,1.0)
	const _TXT  := Color(0.88,0.83,0.74,1.0)
	const _DIM  := Color(0.45,0.40,0.35,1.0)
	var _t : String; var _d : String
	func _init(t: String, d: String) -> void:
		_t=t; _d=d
		custom_minimum_size = Vector2(CW,CH); size = Vector2(CW,CH)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var s := StyleBoxFlat.new()
		s.bg_color=_BG; s.border_color=_BDR
		s.set_border_width_all(2); s.set_corner_radius_all(3)
		s.draw(get_canvas_item(), Rect2(0,0,CW,CH))
		var font : Font = (load(_FONT) as Font) if ResourceLoader.exists(_FONT) \
				else ThemeDB.fallback_font
		draw_string(font, Vector2(6,14), _t.to_upper(), HORIZONTAL_ALIGNMENT_LEFT,-1,10,_TXT)
		if _d != "":
			draw_string(font, Vector2(6,26), _d, HORIZONTAL_ALIGNMENT_LEFT,-1,8,_DIM)
