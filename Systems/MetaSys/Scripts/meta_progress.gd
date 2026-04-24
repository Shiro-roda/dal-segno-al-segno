extends Node
## MetaProgress — autoload singleton (add as "MetaProgress" in Project > AutoLoad).
##
## Responsibilities:
##   • Track Motif Points (spendable cross-run currency).
##   • Record which content IDs have been seen for the first time ("discoveries").
##   • Award Motif Points when new content is discovered.
##   • Track which Motif nodes in the tree have been unlocked (permanently).
##   • Track cumulative run stats (total runs, wins, rooms cleared, etc.).
##   • Persist everything to  user://saves/meta_progress.json.
##
## Discovery IDs are arbitrary strings — callers pass things like:
##   "enemy:wraith"  "phase:dal_segno"  "room:elite"  "skill:crucify"
## Any ID seen for the first time awards MOTIF_POINTS_PER_DISCOVERY points.

const SAVE_PATH              := "user://saves/meta_progress.json"
const MOTIF_POINTS_PER_DISCOVERY : int = 1
const MOTIF_POINTS_RUN_BASE  : int = 1   # flat award at run end (win or loss)
const MOTIF_POINTS_RUN_WIN   : int = 2   # bonus for winning

## Emitted whenever a brand-new content ID is first encountered.
## (id: String, label: String) — label is a human-readable display string.
signal motif_discovered(id: String, label: String)

## Emitted when Motif Points balance changes.
signal motif_points_changed(new_total: int)

## Emitted when a node in the tree is unlocked.
signal motif_unlocked(motif_id: String)

# ─────────────────────────────────────────────────────────────────────────────
# State
# ─────────────────────────────────────────────────────────────────────────────

var motif_points      : int  = 0
var total_runs        : int  = 0
var total_wins        : int  = 0
var total_rooms       : int  = 0
var total_enemies     : int  = 0

## Set of all content IDs encountered at least once.
var _discovered       : Dictionary = {}   # id -> true

## Set of all Motif tree node IDs that have been purchased/unlocked.
var _unlocked_motifs  : Dictionary = {}   # motif_id -> true

# ─────────────────────────────────────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_ensure_save_dir()
	load_progress()


func _ensure_save_dir() -> void:
	var dir := "user://saves/"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)


# ─────────────────────────────────────────────────────────────────────────────
# Discovery API  (call from dungeon/battle systems on first-encounter moments)
# ─────────────────────────────────────────────────────────────────────────────

## Notify MetaProgress that a piece of content was encountered.
## If it is the first time, award Motif Points and emit motif_discovered.
## id   — unique content key,  e.g. "enemy:pale_hussar"
## label — display-friendly name, e.g. "Pale Hussar"
func notify_encounter(id: String, label: String = "") -> void:
	if _discovered.has(id):
		return
	_discovered[id] = true
	motif_points += MOTIF_POINTS_PER_DISCOVERY
	motif_points_changed.emit(motif_points)
	var display := label if label != "" else id
	motif_discovered.emit(id, display)
	save_progress()


## Returns true if a content ID has been seen before.
func has_discovered(id: String) -> bool:
	return _discovered.has(id)


# ─────────────────────────────────────────────────────────────────────────────
# Run-end API  (call from GameControl on win/loss)
# ─────────────────────────────────────────────────────────────────────────────

## Call at the end of every run (win or loss).
## rooms_cleared — count of rooms completed this run (for stat tracking).
## enemies_defeated — count of enemies killed this run.
func on_run_ended(victory: bool, rooms_cleared: int = 0, enemies_defeated: int = 0) -> void:
	total_runs    += 1
	total_rooms   += rooms_cleared
	total_enemies += enemies_defeated
	if victory:
		total_wins  += 1

	var award : int = MOTIF_POINTS_RUN_BASE + (MOTIF_POINTS_RUN_WIN if victory else 0)
	motif_points += award
	motif_points_changed.emit(motif_points)
	save_progress()


# ─────────────────────────────────────────────────────────────────────────────
# Motif Tree API
# ─────────────────────────────────────────────────────────────────────────────

## Returns true if a tree node is already unlocked.
func is_unlocked(motif_id: String) -> bool:
	return _unlocked_motifs.has(motif_id)


## Returns true if the player can afford and has met prereqs for a node.
func can_unlock(motif_id: String) -> bool:
	if is_unlocked(motif_id):
		return false
	var node : MotifNode = MotifRegistry.get_node_by_id(motif_id)
	if node == null:
		return false
	if motif_points < node.cost:
		return false
	for req in node.requires:
		if not is_unlocked(req):
			return false
	return true


## Spend Motif Points to unlock a node. Returns true on success.
func unlock_motif(motif_id: String) -> bool:
	if not can_unlock(motif_id):
		return false
	var node : MotifNode = MotifRegistry.get_node_by_id(motif_id)
	motif_points -= node.cost
	_unlocked_motifs[motif_id] = true
	motif_points_changed.emit(motif_points)
	motif_unlocked.emit(motif_id)
	save_progress()
	return true


## Returns an Array of all unlocked motif IDs.
func get_unlocked_ids() -> Array:
	return _unlocked_motifs.keys()


# ─────────────────────────────────────────────────────────────────────────────
# Persistence
# ─────────────────────────────────────────────────────────────────────────────

func save_progress() -> void:
	var data := {
		"motif_points":     motif_points,
		"total_runs":       total_runs,
		"total_wins":       total_wins,
		"total_rooms":      total_rooms,
		"total_enemies":    total_enemies,
		"discovered":       _discovered.keys(),
		"unlocked_motifs":  _unlocked_motifs.keys(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[MetaProgress] Could not open save file for writing: %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("[MetaProgress] Could not open save file for reading.")
		return
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("[MetaProgress] Save file is malformed.")
		return

	motif_points  = parsed.get("motif_points",  0)
	total_runs    = parsed.get("total_runs",    0)
	total_wins    = parsed.get("total_wins",    0)
	total_rooms   = parsed.get("total_rooms",   0)
	total_enemies = parsed.get("total_enemies", 0)

	_discovered.clear()
	for id in parsed.get("discovered", []):
		_discovered[id] = true

	_unlocked_motifs.clear()
	for id in parsed.get("unlocked_motifs", []):
		_unlocked_motifs[id] = true
