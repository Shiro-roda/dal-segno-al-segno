class_name MainPath
extends RefCounted
## Scores a Bass Clef layout against the Segno.
##
## The MAIN PATH is the longest simple (no repeated tile) walk over standing tiles that
## starts at the Segno and ends at the exit. If several qualify the longest always wins;
## a shorter spine is never chosen to dodge penalties.
##
## A LOOP is a place where the layout rejoins the main path: a chord (two non-consecutive
## path tiles that touch) or a group of off-path tiles that touches the path in more than
## one place (each extra touch is one loop). Side branches that never rejoin are free.
##
## Pure logic: cells are a set {Vector2i: true} of standing tiles.

const NEIGHBOURS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

var _cells: Dictionary
var _goal: Vector2i
var _best: Array[Vector2i] = []
var _current: Array[Vector2i] = []
var _visited := {}
var _steps := 0
var _limit := 0
var _capped := false


## {found: bool, path: Array[Vector2i] (Segno first, exit last), steps: int, loops: int,
## capped: bool, on_path: {Vector2i: true}}. `capped` means the search ran out of its step
## budget, so the path is the best found rather than proven longest.
static func find(cells: Dictionary, start: Vector2i, goal: Vector2i, step_limit := 200000) -> Dictionary:
	var search := MainPath.new()
	return search._run(cells, start, goal, step_limit)


## Everything reachable from `start` over standing tiles, as a set (includes `start`).
static func reachable(cells: Dictionary, start: Vector2i) -> Dictionary:
	var seen := {}
	if not cells.has(start):
		return seen
	seen[start] = true
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for step in NEIGHBOURS:
			var nxt := cur + step
			if cells.has(nxt) and not seen.has(nxt):
				seen[nxt] = true
				queue.append(nxt)
	return seen


## How many loops `path` has within `cells` (see the class comment).
static func count_loops(cells: Dictionary, path: Array) -> int:
	var index := {}
	for i in path.size():
		index[path[i]] = i
	var loops := 0
	# Chords: touching tiles that are not neighbours along the path. Only look right and
	# down so each pair is counted once.
	for i in path.size():
		var here: Vector2i = path[i]
		for step in [Vector2i(1, 0), Vector2i(0, 1)]:
			var j: int = index.get(here + step, -1)
			if j >= 0 and absi(j - i) > 1:
				loops += 1
	# Off-path groups that touch the path in several places.
	var seen := {}
	for cell: Vector2i in cells:
		if index.has(cell) or seen.has(cell):
			continue
		var touches := {}
		var queue: Array[Vector2i] = [cell]
		seen[cell] = true
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_back()
			for step in NEIGHBOURS:
				var nxt := cur + step
				if index.has(nxt):
					touches[index[nxt]] = true
				elif cells.has(nxt) and not seen.has(nxt):
					seen[nxt] = true
					queue.append(nxt)
		loops += maxi(0, touches.size() - 1)
	return loops


## The bonus multiplier (added to 1.0) for rooms on the main path: it grows with the
## path's length in steps and shrinks per loop, never below zero.
static func bonus(steps: int, loops: int, per_step: float, loop_penalty: float) -> float:
	return maxf(0.0, per_step * steps - loop_penalty * loops)


# ------------------------------------------------------------------- search

func _run(cells: Dictionary, start: Vector2i, goal: Vector2i, step_limit: int) -> Dictionary:
	var out := {"found": false, "path": [], "steps": 0, "loops": 0, "capped": false, "on_path": {}}
	if not cells.has(start) or not cells.has(goal):
		return out
	_cells = cells
	_goal = goal
	_limit = maxi(1, step_limit)
	if start == goal:
		out["found"] = true
		out["path"] = [start]
		out["on_path"] = {start: true}
		return out
	_dfs(start)
	out["capped"] = _capped
	if _best.is_empty():
		return out
	var on_path := {}
	for cell in _best:
		on_path[cell] = true
	out["found"] = true
	out["path"] = _best.duplicate()
	out["steps"] = _best.size() - 1
	out["loops"] = count_loops(cells, _best)
	out["on_path"] = on_path
	return out


func _dfs(cell: Vector2i) -> void:
	if _steps >= _limit:
		_capped = true
		return
	_steps += 1
	_current.append(cell)
	_visited[cell] = true
	if cell == _goal:
		if _current.size() > _best.size():
			_best = _current.duplicate()
	else:
		# Even using every tile still reachable, can this walk beat the best so far?
		var room := _room_left(cell)
		if room >= 0 and _current.size() + room > _best.size():
			for step in NEIGHBOURS:
				var nxt := cell + step
				if _cells.has(nxt) and not _visited.has(nxt):
					_dfs(nxt)
	_current.pop_back()
	_visited.erase(cell)


## Unvisited tiles reachable from `from` without passing through the goal, or -1 if the
## goal can no longer be reached at all.
func _room_left(from: Vector2i) -> int:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	var count := 0
	var goal_seen := false
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for step in NEIGHBOURS:
			var nxt := cur + step
			if not _cells.has(nxt) or _visited.has(nxt) or seen.has(nxt):
				continue
			seen[nxt] = true
			count += 1
			if nxt == _goal:
				goal_seen = true
			else:
				queue.append(nxt)
	return count if goal_seen else -1
