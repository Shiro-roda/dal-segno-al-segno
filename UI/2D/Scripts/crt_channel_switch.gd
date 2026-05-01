extends Node2D
## CRT channel-switch flash overlay (Node2D — must be parented to a CanvasLayer).
## Phase 1 (cut):    bright horizontal scan bar sweeps top→bottom + heavy static.
## Phase 2 (settle): static dissolves out.
## Self-destructs on completion.  Call play(viewport_size) after adding to tree.

const SCAN_DURATION   : float = 0.08
const SETTLE_DURATION : float = 0.18
const SCAN_BAR_H      : float = 0.18   # fraction of screen height
const STATIC_LINES    : int   = 80

var _t     : float = 0.0
var _phase : int   = 0      # 0 = scan, 1 = settle
var _rng   := RandomNumberGenerator.new()
var _vp    : Vector2 = Vector2(1280, 720)

func _ready() -> void:
	set_process(false)   # enabled by play()

func play(vp_size: Vector2) -> void:
	_vp = vp_size
	_rng.randomize()
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	var dur : float = SCAN_DURATION if _phase == 0 else SETTLE_DURATION
	if _t >= dur:
		_t -= dur
		_phase += 1
		if _phase >= 2:
			queue_free()
			return
	queue_redraw()

func _draw() -> void:
	var w : float = _vp.x
	var h : float = _vp.y
	var dur : float = SCAN_DURATION if _phase == 0 else SETTLE_DURATION
	var p   : float = clampf(_t / dur, 0.0, 1.0)

	if _phase == 0:
		# Static fill (fades slightly as bar passes)
		_draw_static(w, h, 1.0 - p * 0.35)
		# Scan bar sweeping top → bottom
		var bar_y : float = (p - SCAN_BAR_H * 0.5) * h
		var bar_h : float = SCAN_BAR_H * h
		draw_rect(Rect2(0.0, bar_y, w, bar_h),
			Color(1.0, 1.0, 1.0, 0.90 * (1.0 - p * 0.3)))
		# Hard leading edge
		draw_rect(Rect2(0.0, bar_y, w, 3.0), Color(1.0, 1.0, 1.0, 1.0))
	else:
		# Static dissolves out
		_draw_static(w, h, (1.0 - p) * 0.55)

func _draw_static(w: float, h: float, alpha: float) -> void:
	if alpha <= 0.01:
		return
	_rng.seed = Time.get_ticks_msec() / 16   # stable per ~60fps frame
	for _i in STATIC_LINES:
		var y   : float = _rng.randf() * h
		var lh  : float = _rng.randf_range(1.0, 6.0)
		var bri : float = _rng.randf_range(0.55, 1.0)
		var a   : float = alpha * _rng.randf_range(0.4, 1.0)
		draw_rect(Rect2(0.0, y, w, lh), Color(bri, bri, bri, a))
	# Dark vignette so static doesn't blow out the frame
	draw_rect(Rect2(0.0, 0.0, w, h), Color(0.0, 0.0, 0.0, alpha * 0.35))
