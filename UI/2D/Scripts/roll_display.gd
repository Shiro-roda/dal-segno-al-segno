class_name RollDisplay
extends Control
## A terminal readout of every number rolled on a combatant's turn, stacked down the
## top-right of the combat screen. The attack and save rolls, then the damage, healing
## and anima dice, play one at a time in the order they were rolled, top to bottom.
## Each panel switches on like a CRT, types out its text, and its digits spin through
## 0-9 and lock in left to right with a flicker, a colour-fringe and a burst of static.
##
## CombatHUD creates one and calls bind(). It listens to CombatSession.action_resolved and
## reads the `readout` list that RulesEngine.use_action() puts in every result. The rolls
## are already settled by then; this only plays them back, so it never touches the rules
## RNG. Each batch also takes a hold on the actor's turn (CombatSession.hold_turn), so the
## turn isn't over until the numbers have landed. Everything is drawn here, with colours
## from the active UI palette.

const TURN_ON := 0.28
const HEADER_LEAD := 0.12
const FADE_OUT := 0.25
const LAND_POP := 0.22
const HEADER_H := 30.0
const ROW_GAP := 8.0
const CRIT_COLOR := Color(1.0, 0.86, 0.3)
const FUMBLE_COLOR := Color(0.85, 0.22, 0.2)
const ANIMA_COLOR := Color(0.3, 0.55, 1.0)
const SAVE_COLOR := Color(0.35, 0.85, 1.0)
const FRINGE_RED := Color(1.0, 0.2, 0.25)
const FRINGE_CYAN := Color(0.2, 0.9, 1.0)

@export_group("Timing")
## Seconds before the first digit of a roll locks in.
@export var spin_time := 0.6
## Extra seconds for each further digit.
@export var digit_stagger := 0.14
## How often a spinning digit changes.
@export var tick_seconds := 0.04
## Pause between one roll landing and the next one starting.
@export var row_pause := 0.12
## How long a finished turn stays up.
@export var hold_time := 1.8
## When another turn is waiting, a finished one leaves after this long.
@export var min_hold_time := 0.7
## How long after the last roll lands the actor's turn is released. The panels stay up
## for hold_time regardless; this only decides when the turn counts as over.
@export var turn_release_delay := 0.5

@export_group("Behaviour")
## Play the biggest number first, instead of the order the rolls were made.
@export var sort_by_value := false
@export var include_enemy_turns := true

@export_group("Look")
## How dark the scanlines are (0 = none).
@export_range(0.0, 1.0, 0.01) var scanline_strength := 0.22
## Strength of the phosphor glow around lit text.
@export_range(0.0, 2.0, 0.05) var glow_strength := 1.0
## Pixels of red/cyan colour fringing on the digits.
@export_range(0.0, 4.0, 0.1) var aberration := 1.6
## How much the whole display flickers (0 = steady).
@export_range(0.0, 0.3, 0.01) var flicker := 0.06
## Characters per second when text is typed out.
@export var type_speed := 55.0

@export_group("Layout")
## Gap between the stack and the top-right corner of the screen.
@export var edge_margin := Vector2(28.0, 24.0)

var _batches: Array[DisplayBatch] = []
var _t := 0.0
var _flick := 1.0
var _rng := RandomNumberGenerator.new()
var _session: Variant = null
var _row_h := 64.0
var _panel_w := 360.0
var _list_top := 54.0


## One number to show.
class DisplayRow extends RefCounted:
	var kind: StringName = &"attack"
	var value := 0
	var who := ""
	var against := ""
	var detail := ""
	var outcome: StringName = &""
	var crit := false
	var fumble := false
	var negative := false
	var digits := PackedInt32Array()
	var shown := PackedInt32Array()
	var next_tick := PackedFloat32Array()
	var lock_times := PackedFloat32Array()
	var last_lock := 0.0
	var started := false
	var landed := false
	var placed := false
	var age := 0.0
	var y := 0.0
	var fade := 1.0
	var shake := 0.0
	var seed_angle := 0.0


## Everything one action rolled: shown together under one header.
class DisplayBatch extends RefCounted:
	var actor_name := ""
	var action_name := ""
	var enemy := false
	var rows: Array[DisplayRow] = []
	var next_row := 0
	var gap := 0.0
	var hold := 0.0
	var age := 0.0
	var fade := 1.0
	var retiring := false
	var hold_id := 0
	var released := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()


func _exit_tree() -> void:
	for batch in _batches:
		_release(batch)


func bind(session: CombatSession) -> void:
	_session = session
	session.action_resolved.connect(_on_action_resolved)


## True once nothing is left to show, so the HUD can close.
func is_idle() -> bool:
	return _batches.is_empty()


# ------------------------------------------------------------------ intake

func _on_action_resolved(actor: Combatant, result: Dictionary) -> void:
	if actor.side == Combatant.Side.ENEMY and not include_enemy_turns:
		return
	var readout: Array = result.get("readout", [])
	if readout.is_empty():
		return
	var batch := DisplayBatch.new()
	batch.actor_name = actor.display_name()
	batch.action_name = String(result.get("action", ""))
	batch.enemy = actor.side == Combatant.Side.ENEMY
	for entry: Dictionary in readout:
		batch.rows.append(_make_row(entry))
	if sort_by_value:
		batch.rows.sort_custom(func(a: DisplayRow, b: DisplayRow) -> bool:
			return a.value > b.value)
	# The actor's turn isn't over until these numbers have landed.
	if _session != null and is_instance_valid(_session):
		batch.hold_id = (_session as CombatSession).hold_turn(actor)
	_batches.append(batch)


func _make_row(entry: Dictionary) -> DisplayRow:
	var row := DisplayRow.new()
	row.kind = StringName(entry.get("kind", "attack"))
	row.value = int(entry.get("value", 0))
	row.who = String(entry.get("who", ""))
	row.against = String(entry.get("against", ""))
	row.detail = String(entry.get("detail", ""))
	row.outcome = StringName(entry.get("outcome", ""))
	row.crit = bool(entry.get("crit", false))
	row.fumble = bool(entry.get("fumble", false))
	row.negative = row.value < 0
	var digits_text := str(absi(row.value))
	for i in digits_text.length():
		var digit := int(digits_text.substr(i, 1))
		row.digits.append(digit)
		row.shown.append(digit)
		row.next_tick.append(0.0)
		row.lock_times.append(0.0)
	row.seed_angle = _rng.randf() * TAU
	return row


func _release(batch: DisplayBatch) -> void:
	if batch.released:
		return
	batch.released = true
	if _session != null and is_instance_valid(_session):
		(_session as CombatSession).release_turn(batch.hold_id)


# ------------------------------------------------------------------ timing

func _process(delta: float) -> void:
	_t += delta
	if _batches.is_empty():
		return
	_metrics()
	var dt := delta * _speed()
	var front := _batches[0]
	_step_batch(front, dt)
	if front.retiring and front.fade <= 0.0:
		_release(front)
		_batches.pop_front()
	queue_redraw()


## Plays faster when turns are piling up, so the display never falls far behind.
func _speed() -> float:
	return minf(1.0 + 0.75 * maxf(0.0, _batches.size() - 2.0), 3.0)


func _metrics() -> void:
	_row_h = clampf(size.y * 0.075, 46.0, 84.0)
	_panel_w = clampf(_row_h * 5.8, 270.0, maxf(size.x * 0.45, 270.0))
	_list_top = edge_margin.y + HEADER_H


## How many rows fit before the stack would reach the action menu at mid-screen.
func _max_rows() -> int:
	return clampi(int((size.y * 0.5 - _list_top) / (_row_h + ROW_GAP)), 3, 8)


func _step_batch(batch: DisplayBatch, dt: float) -> void:
	batch.age += dt
	if batch.retiring:
		_release(batch)
		batch.fade -= dt / FADE_OUT
		return
	if batch.next_row < batch.rows.size():
		batch.gap -= dt
		if batch.gap <= 0.0 and batch.age >= HEADER_LEAD:
			_start_row(batch, batch.rows[batch.next_row])
			batch.next_row += 1
	var all_landed := batch.next_row >= batch.rows.size()
	var started: Array[DisplayRow] = []
	for row in batch.rows:
		if not row.started:
			continue
		_step_row(row, dt)
		started.append(row)
		if not row.landed:
			all_landed = false
	_arrange(started, dt)
	if all_landed:
		batch.hold += dt
		if batch.hold >= turn_release_delay:
			_release(batch)
		if batch.hold >= hold_time or (_batches.size() > 1 and batch.hold >= min_hold_time):
			batch.retiring = true


func _start_row(batch: DisplayBatch, row: DisplayRow) -> void:
	row.started = true
	for i in row.digits.size():
		row.lock_times[i] = spin_time + i * digit_stagger
		row.shown[i] = _rng.randi_range(0, 9)
		row.next_tick[i] = _rng.randf() * tick_seconds
	row.last_lock = spin_time + (row.digits.size() - 1) * digit_stagger
	batch.gap = row.last_lock + row_pause


func _step_row(row: DisplayRow, dt: float) -> void:
	row.age += dt
	row.shake = maxf(0.0, row.shake - dt * 3.0)
	for i in row.digits.size():
		if row.age >= row.lock_times[i]:
			row.shown[i] = row.digits[i]
			continue
		row.next_tick[i] -= dt
		if row.next_tick[i] <= 0.0:
			row.next_tick[i] = tick_seconds
			row.shown[i] = _other_digit(row.shown[i])
	if not row.landed and row.age >= row.last_lock:
		row.landed = true
		if row.crit or row.fumble:
			row.shake = 1.0


## Stacks the started rows from the top. If there are more than fit, the oldest fade out
## and the rest slide up.
func _arrange(started: Array[DisplayRow], dt: float) -> void:
	var hidden := maxi(0, started.size() - _max_rows())
	var slot := 0
	for i in started.size():
		var row := started[i]
		if i < hidden:
			row.fade = maxf(0.0, row.fade - dt / 0.2)
			continue
		var goal := _list_top + slot * (_row_h + ROW_GAP)
		if not row.placed:
			row.placed = true
			row.y = goal
		else:
			row.y = lerpf(row.y, goal, 1.0 - exp(-dt * 14.0))
		slot += 1


func _other_digit(previous: int) -> int:
	var digit := _rng.randi_range(0, 9)
	if digit == previous:
		digit = (digit + _rng.randi_range(1, 9)) % 10
	return digit


# -------------------------------------------------------------------- draw

func _draw() -> void:
	if _batches.is_empty():
		return
	_flick = 1.0 - flicker * (0.5 + 0.5 * sin(_t * 53.0) * sin(_t * 7.3))
	var batch := _batches[0]
	var font := _font()
	_draw_header(batch, font)
	for row in batch.rows:
		if row.started and row.fade > 0.0:
			_draw_row(row, batch, font)


## The CRT screen: glow, dark glass, a faint phosphor tint, a gloss on the upper half,
## scanlines, a slow rolling bar, a periodic specular sheen, darkened edges, and an outline.
func _crt_panel(rect: Rect2, accent: Color, alpha: float, phase: float) -> void:
	var bg := MenuStyle.pal("bg", Color.BLACK)
	draw_rect(rect.grow(3.0), _mul(accent, 0.10 * alpha * glow_strength), false, 3.0)
	draw_rect(rect, _mul(bg.darkened(0.2), 0.9 * alpha))
	draw_rect(rect, _mul(accent, 0.05 * alpha))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.45)),
			_mul(Color.WHITE, 0.035 * alpha))
	var lines := PackedVector2Array()
	var ly := rect.position.y + 1.0
	while ly < rect.end.y:
		lines.append(Vector2(rect.position.x, ly))
		lines.append(Vector2(rect.end.x, ly))
		ly += 3.0
	if not lines.is_empty():
		draw_multiline(lines, Color(0.0, 0.0, 0.0, scanline_strength * alpha), 1.0)
	if rect.size.y > 12.0:
		var bar_y := rect.position.y + fposmod(_t * 0.45 + phase, 1.0) * (rect.size.y - 5.0)
		draw_rect(Rect2(rect.position.x, bar_y, rect.size.x, 5.0),
				_mul(accent.lightened(0.5), 0.07 * alpha))
		var band := 26.0
		var skew := rect.size.y * 0.35
		var sheen_x := rect.position.x + (fposmod(_t * 0.28 + phase, 1.6) - 0.3) * rect.size.x
		if sheen_x > rect.position.x + skew and sheen_x + band < rect.end.x:
			draw_colored_polygon(PackedVector2Array([
					Vector2(sheen_x, rect.position.y), Vector2(sheen_x + band, rect.position.y),
					Vector2(sheen_x + band - skew, rect.end.y), Vector2(sheen_x - skew, rect.end.y)]),
					_mul(Color.WHITE, 0.06 * alpha))
	for i in 3:
		var edge := 0.16 * float(3 - i) / 3.0 * alpha
		draw_rect(Rect2(rect.position.x + i * 5.0, rect.position.y, 5.0, rect.size.y),
				Color(0.0, 0.0, 0.0, edge))
		draw_rect(Rect2(rect.end.x - (i + 1) * 5.0, rect.position.y, 5.0, rect.size.y),
				Color(0.0, 0.0, 0.0, edge))
	draw_rect(rect, _mul(accent, 0.45 * alpha), false, 1.0)


## L-shaped brackets in the four corners of `rect`.
func _brackets(rect: Rect2, length: float, colour: Color, width: float) -> void:
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var bl := Vector2(rect.position.x, rect.end.y)
	var br := rect.end
	draw_polyline(PackedVector2Array([tl + Vector2(0, length), tl, tl + Vector2(length, 0)]), colour, width)
	draw_polyline(PackedVector2Array([tr + Vector2(-length, 0), tr, tr + Vector2(0, length)]), colour, width)
	draw_polyline(PackedVector2Array([bl + Vector2(0, -length), bl, bl + Vector2(length, 0)]), colour, width)
	draw_polyline(PackedVector2Array([br + Vector2(-length, 0), br, br + Vector2(0, -length)]), colour, width)


## "> KENDALL :: FIREBALL_", a terminal title strip above the stack.
func _draw_header(batch: DisplayBatch, font: Font) -> void:
	var on := clampf(batch.age / TURN_ON, 0.0, 1.0)
	var alpha := batch.fade * _flick
	var accent := MenuStyle.pal("alert") if batch.enemy else MenuStyle.pal("primary")
	var font_size := 13
	var full := "> " + batch.actor_name.to_upper()
	if batch.action_name != "":
		full += " :: " + batch.action_name.to_upper()
	var text_w := font.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var full_w := text_w + 52.0
	var full_h := HEADER_H - 6.0
	var width_k := _ease_out(clampf(on / 0.5, 0.0, 1.0))
	var height_k := _ease_out(clampf((on - 0.3) / 0.7, 0.0, 1.0)) * _ease_out(batch.fade)
	var w := full_w * width_k
	var h := maxf(2.0, full_h * height_k)
	var x1 := size.x - edge_margin.x
	var rect := Rect2(x1 - w, edge_margin.y + (full_h - h) * 0.5, w, h)
	if on < 1.0:
		draw_rect(rect, _mul(Color.WHITE, (1.0 - height_k) * 0.5 * alpha))
	_crt_panel(rect, accent, alpha, 0.0)
	if height_k < 0.9:
		return
	var mid := edge_margin.y + full_h * 0.5
	var blink := 1.0 if fposmod(_t, 1.0) < 0.6 else 0.25
	draw_circle(Vector2(rect.position.x + 12.0, mid), 3.0, _mul(MenuStyle.pal("alert"), blink * alpha))
	var typed := _typed(full, batch.age - 0.1)
	var text_pos := Vector2(rect.position.x + 24.0, edge_margin.y + full_h - 7.0)
	draw_string(font, text_pos, typed, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _mul(accent, alpha))
	if typed.length() < full.length() or fposmod(_t, 0.8) < 0.5:
		var cursor_x := font.get_string_size(typed, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, text_pos + Vector2(cursor_x, 0.0), "_", HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size, _mul(accent.lightened(0.4), alpha))


func _draw_row(row: DisplayRow, batch: DisplayBatch, font: Font) -> void:
	var h := _row_h
	var w := _panel_w
	var close := row.fade * batch.fade
	var on := clampf(row.age / TURN_ON, 0.0, 1.0)
	var width_k := _ease_out(clampf(on / 0.45, 0.0, 1.0))
	var height_k := _ease_out(clampf((on - 0.35) / 0.65, 0.0, 1.0)) * _ease_out(close)
	var alpha := close * _flick
	var content := clampf((on - 0.7) / 0.3, 0.0, 1.0) * alpha
	var since_land := row.age - row.last_lock
	var accent := _accent(row)
	if row.landed and row.crit:
		accent = CRIT_COLOR
	elif row.landed and row.fumble:
		accent = FUMBLE_COLOR
	var shake := Vector2.ZERO
	if row.shake > 0.0:
		shake = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * row.shake * 5.0
	var x1 := size.x - edge_margin.x + shake.x
	var x0 := x1 - w
	var y := row.y + shake.y

	# The screen powers on as a bright line that widens, then opens upward and downward.
	var panel_w := w * width_k
	var panel_h := maxf(2.0, h * height_k)
	var rect := Rect2(x0 + (w - panel_w) * 0.5, y + (h - panel_h) * 0.5, panel_w, panel_h)
	if on < 1.0:
		draw_rect(rect, _mul(Color.WHITE, (1.0 - height_k) * 0.55 * alpha))
	_crt_panel(rect, accent, alpha, row.seed_angle)
	if content <= 0.01:
		return
	var pulse := 0.5 + 0.5 * sin(_t * 9.0)
	draw_rect(Rect2(rect.position, Vector2(3.0, rect.size.y)), _mul(accent, alpha))
	var bracket_w := 2.0 + (2.0 * pulse if row.landed and row.crit else 0.0)
	_brackets(rect.grow(1.0), 9.0, _mul(accent, 0.95 * alpha), bracket_w)
	if row.landed and since_land < 0.3:
		draw_rect(rect, _mul(Color.WHITE, (1.0 - since_land / 0.3) * 0.3 * alpha))

	# Words on the left.
	var small := int(clampf(h * 0.22, 11.0, 16.0))
	var tiny := maxi(10, small - 2)
	var text_x := x0 + 30.0
	var text_w := w * 0.46
	draw_string(font, Vector2(x0 + 12.0, y + h * 0.36), "=" if row.landed else ">",
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, _mul(accent, content))
	var kind_text := _kind_label(row)
	draw_string(font, Vector2(text_x, y + h * 0.36), kind_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, _mul(accent, content))
	if row.landed:
		var verdict := _verdict(row)
		if verdict != "":
			var kind_w := font.get_string_size(kind_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
			var ramp := clampf(since_land / 0.12, 0.0, 1.0)
			var verdict_alpha := content * ramp
			if row.crit:
				verdict_alpha *= 0.65 + 0.35 * sin(_t * 14.0)
			draw_string(font, Vector2(text_x + kind_w + 12.0, y + h * 0.36), "[%s]" % verdict,
					HORIZONTAL_ALIGNMENT_LEFT, -1, small, _mul(_verdict_color(row), verdict_alpha))
	_draw_typed(font, Vector2(text_x, y + h * 0.64),
			_fit(font, _subject_line(row), text_w, tiny), row.age - TURN_ON * 0.7, tiny,
			_mul(MenuStyle.pal("text"), 0.75 * content))
	if row.landed and row.detail != "":
		_draw_typed(font, Vector2(text_x, y + h * 0.86), _fit(font, row.detail, text_w, tiny),
				since_land, tiny, _mul(MenuStyle.pal("dim"), content))

	# The number, right-aligned, one lit cell per digit. A leading minus sign counts as a
	# cell that is already set.
	var minus := 1 if row.negative else 0
	var cells := row.digits.size() + minus
	var font_size := int(h * 0.74)
	var advance := font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var room := w * 0.5 - 12.0
	if advance * cells > room:
		font_size = int(font_size * room / (advance * cells))
		advance = font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var right := x1 - 14.0
	var left := right - advance * cells
	var base_y := y + h * 0.5 + font_size * 0.35
	var colour := _digit_color(row, pulse)
	for c in cells:
		var cell_x := left + c * advance
		var housing := Rect2(cell_x + 1.0, base_y - font_size * 0.86, advance - 2.0, font_size)
		draw_rect(housing, Color(0.0, 0.0, 0.0, 0.42 * content))
		draw_rect(Rect2(housing.position, Vector2(housing.size.x, housing.size.y * 0.5)),
				_mul(Color.WHITE, 0.03 * content))
		draw_rect(housing, _mul(accent, 0.28 * content), false, 1.0)
		var di := c - minus
		if di < 0:
			_draw_cell(font, "-", cell_x, base_y, advance, font_size, colour, accent,
					row.age, content, row.seed_angle)
		else:
			_draw_cell(font, str(row.shown[di]), cell_x, base_y, advance, font_size, colour,
					accent, row.age - row.lock_times[di], content, row.seed_angle + di)
	if row.landed and row.kind == &"attack" and row.outcome == &"miss":
		var strike := clampf(since_land / 0.15, 0.0, 1.0)
		var mid_y := y + h * 0.5
		draw_line(Vector2(left - 6.0, mid_y), Vector2(left - 6.0 + (right - left + 10.0) * strike, mid_y),
				_mul(MenuStyle.pal("alert"), 0.85 * content), 3.0)


## One digit. While `t_lock` is negative it is still spinning: a jittering digit with a
## colour fringe and its two neighbours, faint, like a blurred reel. Once locked it pops
## in, flickers, flashes white, settles into a glowing fringe, and throws off glitch lines.
func _draw_cell(font: Font, ch: String, cell_x: float, base_y: float, advance: float,
		font_size: int, colour: Color, accent: Color, t_lock: float, alpha: float, seed_value: float) -> void:
	if t_lock < 0.0:
		var jitter := (_hash(seed_value + floorf(_t * 30.0)) - 0.5) * 2.0
		var lift := font_size * 0.24
		var digit := int(ch)
		var reel := _mul(accent.lightened(0.35), alpha)
		var px := cell_x + jitter
		draw_string(font, Vector2(px, base_y - lift), str((digit + 9) % 10),
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _mul(reel, 0.2))
		draw_string(font, Vector2(px, base_y + lift), str((digit + 1) % 10),
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _mul(reel, 0.2))
		draw_string(font, Vector2(px - aberration, base_y), ch,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _mul(FRINGE_RED, 0.35 * alpha))
		draw_string(font, Vector2(px + aberration, base_y), ch,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _mul(FRINGE_CYAN, 0.35 * alpha))
		draw_string(font, Vector2(px, base_y), ch,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _mul(reel, 0.95))
		return
	var k := clampf(t_lock / 0.35, 0.0, 1.0)
	var pop := 1.0 + 0.35 * pow(1.0 - clampf(t_lock / LAND_POP, 0.0, 1.0), 2.0)
	var flash := clampf(t_lock / 0.3, 0.0, 1.0)
	var lit := alpha * (1.0 - (1.0 - k) * 0.55 * (0.5 + 0.5 * sin(t_lock * 95.0)))
	var centre := Vector2(cell_x + advance * 0.5, base_y - font_size * 0.35)
	var origin := Vector2(-advance * 0.5, font_size * 0.35)
	var split := aberration * (0.35 + (1.0 - k))
	draw_set_transform(centre, 0.0, Vector2(pop, pop))
	draw_string_outline(font, origin, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 10,
			_mul(accent, 0.22 * lit * glow_strength))
	draw_string_outline(font, origin, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5,
			_mul(accent, 0.3 * lit * glow_strength))
	draw_string(font, origin + Vector2(-split, 0.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			_mul(FRINGE_RED, 0.4 * lit))
	draw_string(font, origin + Vector2(split, 0.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			_mul(FRINGE_CYAN, 0.4 * lit))
	draw_string(font, origin, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			_mul(Color.WHITE.lerp(colour, flash), lit))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if t_lock < 0.3:
		for n in 5:
			var gy := base_y - font_size * 0.8 + _hash(seed_value + n * 3.1) * font_size * 0.9
			var gl := 6.0 + _hash(seed_value + n * 7.7) * advance * 1.4
			var dir := -1.0 if _hash(seed_value + n * 1.3) < 0.5 else 1.0
			var gx := centre.x + dir * advance * 0.5
			draw_line(Vector2(gx, gy), Vector2(gx + dir * gl * (1.0 - k), gy),
					_mul(accent.lightened(0.4), (1.0 - k) * alpha), 2.0)


# ----------------------------------------------------------------- helpers

## Text typed out character by character as `t` runs, with an underscore cursor while it
## is still arriving.
func _draw_typed(font: Font, pos: Vector2, text: String, t: float, font_size: int, colour: Color) -> void:
	var typed := _typed(text, t)
	draw_string(font, pos, typed, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
	if typed.length() < text.length() and t > 0.0:
		var cursor_x := font.get_string_size(typed, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, pos + Vector2(cursor_x, 0.0), "_", HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size, colour)


func _typed(text: String, t: float) -> String:
	if type_speed <= 0.0:
		return text
	return text.substr(0, mini(int(maxf(t, 0.0) * type_speed), text.length()))


func _accent(row: DisplayRow) -> Color:
	match row.kind:
		&"damage":
			return MenuStyle.pal("alert")
		&"heal":
			return MenuStyle.pal("primary")
		&"anima":
			return ANIMA_COLOR
		&"save":
			return SAVE_COLOR
	return MenuStyle.pal("secondary")


## Colour of the digits once set: bright, tinted by the roll's colour; gold and shimmering
## for a critical, red for a fumble, and dimmed for a miss.
func _digit_color(row: DisplayRow, pulse: float) -> Color:
	var base := MenuStyle.pal("text").lerp(_accent(row), 0.35)
	if row.crit:
		return CRIT_COLOR.lerp(Color.WHITE, 0.35 * pulse)
	if row.fumble:
		return FUMBLE_COLOR
	if row.kind == &"attack" and row.outcome == &"miss":
		return _mul(base, 0.55)
	return base


func _kind_label(row: DisplayRow) -> String:
	match row.kind:
		&"damage":
			return "DAMAGE"
		&"heal":
			return "HEAL"
		&"anima":
			return "ANIMA"
		&"save":
			return "SAVE"
	return "ATTACK"


func _verdict(row: DisplayRow) -> String:
	if row.crit:
		return "CRIT"
	if row.fumble:
		return "CRIT MISS"
	match row.outcome:
		&"hit":
			return "HIT"
		&"miss":
			return "MISS"
		&"saved":
			return "SAVED"
		&"failed":
			return "FAILED"
	return ""


func _verdict_color(row: DisplayRow) -> Color:
	if row.crit:
		return CRIT_COLOR
	if row.fumble:
		return FUMBLE_COLOR
	match row.outcome:
		&"hit":
			return MenuStyle.pal("primary")
		&"miss":
			return MenuStyle.pal("alert")
		&"saved":
			return SAVE_COLOR
		&"failed":
			return MenuStyle.pal("secondary")
	return MenuStyle.pal("text")


func _subject_line(row: DisplayRow) -> String:
	match row.kind:
		&"save":
			return "%s saves" % row.who
		&"damage", &"heal", &"anima":
			return "to %s" % row.against
	return "vs %s" % row.against


func _font() -> Font:
	var mono := ThemeManager.mono_font()
	return mono if mono != null else ThemeDB.fallback_font


## Shortens `text` with an ellipsis until it fits `max_width`.
func _fit(font: Font, text: String, max_width: float, font_size: int) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var cut := text
	while cut.length() > 1 and font.get_string_size(cut + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		cut = cut.substr(0, cut.length() - 1)
	return cut + "..."


## A repeatable pseudo-random number in 0-1 from a float, for jitter that doesn't change
## from one draw to the next within a frame.
static func _hash(value: float) -> float:
	return fposmod(sin(value * 12.9898) * 43758.5453, 1.0)


static func _mul(colour: Color, factor: float) -> Color:
	return Color(colour.r, colour.g, colour.b, colour.a * factor)


static func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)
