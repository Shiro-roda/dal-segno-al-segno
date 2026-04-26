extends Control
## TempoScore — draws all battle actors as hollow-circle noteheads on a
## musical staff. X = tempo_pool (normalised to max expected pool),
## Y = actor row (one staff line per actor).
##
## Enemies sit below a double-barline divider, players above it.
## The active actor's note glows brighter.

const STAFF_LINES     := 4       # lines per staff section (above/below barline)
const STAFF_LINE_GAP  := 18.0    # px between staff lines
const NOTE_RADIUS     := 7.0     # px radius of the notehead circle
const NOTE_THICKNESS  := 1.8     # px stroke width of hollow circle
const GLOW_RADIUS     := 10.0    # px radius of glow halo
const GLOW_ALPHA      := 0.22
const LEFT_MARGIN     := 64.0    # px reserved for name labels
const RIGHT_MARGIN    := 20.0
const MAX_TEMPO       := 200.0   # tempo_pool floor for x-axis scaling

var _actors        : Array  = []   # Array[BattleActor]
var _active_actor  : BattleActor = null
var _font          : Font   = null

# Fallback colours if CharacterData has no theme_color set
const _FALLBACK_COLORS : Array = [
	Color(0.92, 0.76, 0.28, 1.0),   # gold
	Color(0.28, 0.72, 0.95, 1.0),   # blue
	Color(0.85, 0.35, 0.35, 1.0),   # red
	Color(0.45, 0.88, 0.55, 1.0),   # green
	Color(0.75, 0.55, 0.95, 1.0),   # purple
]


func setup(actors: Array, active: BattleActor, font: Font) -> void:
	_actors       = actors
	_active_actor = active
	_font         = font
	queue_redraw()


func refresh(actors: Array, active: BattleActor) -> void:
	_actors       = actors
	_active_actor = active
	queue_redraw()


func _draw() -> void:
	if _actors.is_empty():
		return

	var w  : float = size.x
	var h  : float = size.y
	var usable_w : float = w - LEFT_MARGIN - RIGHT_MARGIN

	# Scale x-axis to the highest pool value so no note is ever off the right edge.
	var max_pool : float = MAX_TEMPO
	for a in _actors:
		max_pool = maxf(max_pool, (a as BattleActor).tempo_pool)
	var players : Array = _actors.filter(func(a): return (a as BattleActor).team == BattleActor.Team.PLAYER)
	var enemies : Array = _actors.filter(func(a): return (a as BattleActor).team == BattleActor.Team.ENEMY)

	# Total row count: player rows + 1 (barline gap) + enemy rows
	var total_rows : int = 7 #players.size() + enemies.size()
	if total_rows == 0:
		return

	# Row height — distribute available vertical space evenly
	var row_h : float = h / float(total_rows + 1)  # +1 for the barline spacer

	# Build ordered list: players first (top), then barline gap, then enemies
	# Each entry: { actor, row_index, color }
	var entries : Array = []
	var row : int = 0
	for i in players.size():
		var a := players[i] as BattleActor
		entries.append({"actor": a, "row": row, "color": _actor_color(a, i)})
		row += 1
	while row < 3:
		entries.append({"actor": null, "row": row, "color": null})
		row += 1
	var barline_y : float = (row + 0.5) * row_h
	row += 1
	var enemy_start_idx : int = players.size()
	for i in enemies.size():
		var a := enemies[i] as BattleActor
		entries.append({"actor": a, "row": row, "color": _actor_color(a, enemy_start_idx + i)})
		row += 1
	while row < 7:
		entries.append({"actor": null, "row": row, "color": null})
		row += 1

	# ── Staff lines ──────────────────────────────────────────────────────────
	var staff_col := Color(0.30, 0.26, 0.22, 0.55)
	for entry in entries:
		var y : float = (float(entry["row"]) + 0.5) * row_h
		draw_line(Vector2(LEFT_MARGIN, y), Vector2(w - RIGHT_MARGIN, y),
			staff_col, 0.8)

	# ── Double barline dividing players from enemies ──────────────────────────
	if enemies.size() > 0 and players.size() > 0:
		var bar_col := Color(0.45, 0.38, 0.30, 0.70)
		draw_line(Vector2(LEFT_MARGIN, barline_y - 2), Vector2(w - RIGHT_MARGIN, barline_y - 2), bar_col, 1.2)
		draw_line(Vector2(LEFT_MARGIN, barline_y + 2), Vector2(w - RIGHT_MARGIN, barline_y + 2), bar_col, 1.2)

	# ── Left vertical barline ────────────────────────────────────────────────
	if entries.size() > 0:
		var top_y    : float = 0.5 * row_h
		var bottom_y : float = (float(entries.back()["row"]) + 0.5) * row_h
		draw_line(Vector2(LEFT_MARGIN, top_y), Vector2(LEFT_MARGIN, bottom_y),
			Color(0.45, 0.38, 0.30, 0.55), 1.0)

	# ── Name labels ──────────────────────────────────────────────────────────
	if _font != null:
		for entry in entries:
			var y    : float = (float(entry["row"]) + 0.5) * row_h
			if entry["actor"] != null:
				var a    := entry["actor"] as BattleActor
				var col  : Color = entry["color"]
				var dead : bool  = not a.is_alive()
				var label_col := Color(col.r, col.g, col.b, 0.4 if dead else 0.75)
				var txt  : String = a.get_log_name().substr(0, 6).to_upper()
				draw_string(_font, Vector2(4.0, y + 5.0), txt,
					HORIZONTAL_ALIGNMENT_LEFT, LEFT_MARGIN - 8, 10, label_col)

	# ── Noteheads ────────────────────────────────────────────────────────────
	for entry in entries:
		if entry["actor"] == null:
			continue
		var a    := entry["actor"] as BattleActor
		var col  : Color = entry["color"]
		var y    : float = (float(entry["row"]) + 0.5) * row_h
		var pool : float = clampf(a.tempo_pool, 0.0, max_pool)
		var x    : float = LEFT_MARGIN + (pool / max_pool) * usable_w
		var dead : bool  = not a.is_alive()
		var is_active : bool = (a == _active_actor)

		if dead:
			# Draw a small × for dead actors
			var d : float = NOTE_RADIUS * 0.7
			draw_line(Vector2(x - d, y - d), Vector2(x + d, y + d),
				Color(col.r, col.g, col.b, 0.35), 1.2)
			draw_line(Vector2(x + d, y - d), Vector2(x - d, y + d),
				Color(col.r, col.g, col.b, 0.35), 1.2)
			continue

		# Glow halo
		var glow_alpha : float = GLOW_ALPHA * (1.8 if is_active else 1.0)
		draw_circle(Vector2(x, y), GLOW_RADIUS,
			Color(col.r, col.g, col.b, glow_alpha))

		# Hollow notehead — draw as filled circle then smaller filled circle on top
		var outer_col := Color(col.r, col.g, col.b, 0.92 if is_active else 0.65)
		var inner_col := Color(0.05, 0.04, 0.04, 0.97)  # matches menu background
		draw_circle(Vector2(x, y), NOTE_RADIUS, outer_col)
		draw_circle(Vector2(x, y), NOTE_RADIUS - NOTE_THICKNESS, inner_col)

		# Stem — short vertical line above the notehead
		"var stem_len : float = row_h * 0.38
		draw_line(Vector2(x + NOTE_RADIUS, y),
			Vector2(x + NOTE_RADIUS, y - stem_len),
			outer_col, NOTE_THICKNESS)"

	# ── Tempo axis tick marks ─────────────────────────────────────────────────
	var tick_col := Color(0.35, 0.30, 0.25, 0.40)
	var tick_count : int = 4
	for i in range(1, tick_count):
		var tx : float = LEFT_MARGIN + (float(i) / tick_count) * usable_w
		if entries.size() > 0:
			var top_y    : float = 0.5 * row_h
			var bottom_y : float = (float(entries.back()["row"]) + 0.5) * row_h
			draw_line(Vector2(tx, top_y - 4), Vector2(tx, bottom_y + 4),
				tick_col, 0.6)


func _actor_color(a: BattleActor, fallback_idx: int) -> Color:
	var char_data = null
	if a.party_member != null and a.party_member.character != null:
		char_data = a.party_member.character
	elif a.theme_col:
		return a.theme_col
	if char_data != null and char_data.get("theme_color") != null:
		return char_data.theme_color
	return _FALLBACK_COLORS[fallback_idx % _FALLBACK_COLORS.size()]
