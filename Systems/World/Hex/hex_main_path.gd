class_name HexMainPath
extends RefCounted
## Scores a road network against the Segno. The hex-world counterpart of MainPath.
##
## The MAIN PATH is the longest simple walk (no vertex visited twice) along roads that
## starts at the Segno's vertex and ends at the exit's. If several qualify the longest
## always wins; a shorter spine is never chosen to dodge penalties. Its length in STEPS
## counts roads, not rooms, so a bare junction on the way still lengthens it.
##
## A LOOP is a place where the network rejoins the main path: a chord (a road between two
## path vertices that are not consecutive) or a group of off-path vertices that meets the
## path in more than one place (each extra meeting is one loop). Side branches that never
## rejoin are free.
##
## Pure logic over a graph: Vector3i vertex -> Array of the vertices a road leads to, as
## HexWorld.road_graph() returns it. Nothing here knows the grid is hexagonal.

var _graph: Dictionary
var _goal := HexGrid.NONE
var _best: Array[Vector3i] = []
var _current: Array[Vector3i] = []
var _visited := {}
var _steps := 0
var _limit := 0
var _capped := false


## {found: bool, path: Array[Vector3i] (Segno first, exit last), steps: int, loops: int,
## capped: bool, on_path: {Vector3i: true}}. `capped` means the search ran out of its step
## budget, so the path is the best found rather than proven longest.
static func find(graph: Dictionary, start: Vector3i, goal: Vector3i, step_limit := 200000) -> Dictionary:
	var search := HexMainPath.new()
	return search._run(graph, start, goal, step_limit)


## Everything reachable from `start` along roads, as a set (includes `start`).
static func reachable(graph: Dictionary, start: Vector3i) -> Dictionary:
	var seen := {}
	if not graph.has(start):
		return seen
	seen[start] = true
	var queue: Array[Vector3i] = [start]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_back()
		for nxt: Vector3i in graph.get(cur, []):
			if not seen.has(nxt):
				seen[nxt] = true
				queue.append(nxt)
	return seen


## How many loops `path` has within `graph` (see the class comment).
static func count_loops(graph: Dictionary, path: Array) -> int:
	var index := {}
	for i in path.size():
		index[path[i]] = i
	var loops := 0
	# Chords: a road between path vertices that are not neighbours along the path. Only
	# count it from the earlier end so each road is counted once.
	for i in path.size():
		for nxt: Vector3i in graph.get(path[i], []):
			var j: int = index.get(nxt, -1)
			if j > i + 1:
				loops += 1
	# Off-path groups that meet the path in several places.
	var seen := {}
	for vertex: Vector3i in graph:
		if index.has(vertex) or seen.has(vertex):
			continue
		var touches := {}
		var queue: Array[Vector3i] = [vertex]
		seen[vertex] = true
		while not queue.is_empty():
			var cur: Vector3i = queue.pop_back()
			for nxt: Vector3i in graph.get(cur, []):
				if index.has(nxt):
					touches[index[nxt]] = true
				elif not seen.has(nxt):
					seen[nxt] = true
					queue.append(nxt)
		loops += maxi(0, touches.size() - 1)
	return loops


## The bonus multiplier (added to 1.0) for rooms on the main path: it grows with the
## path's length in steps and shrinks per loop, never below zero.
static func bonus(steps: int, loops: int, per_step: float, loop_penalty: float) -> float:
	return maxf(0.0, per_step * steps - loop_penalty * loops)


# ------------------------------------------------------------------- search

func _run(graph: Dictionary, start: Vector3i, goal: Vector3i, step_limit: int) -> Dictionary:
	var out := {"found": false, "path": [], "steps": 0, "loops": 0, "capped": false, "on_path": {}}
	if not graph.has(start) or not graph.has(goal):
		return out
	_graph = graph
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
	for vertex in _best:
		on_path[vertex] = true
	out["found"] = true
	out["path"] = _best.duplicate()
	out["steps"] = _best.size() - 1
	out["loops"] = count_loops(graph, _best)
	out["on_path"] = on_path
	return out


func _dfs(vertex: Vector3i) -> void:
	if _steps >= _limit:
		_capped = true
		return
	_steps += 1
	_current.append(vertex)
	_visited[vertex] = true
	if vertex == _goal:
		if _current.size() > _best.size():
			_best = _current.duplicate()
	else:
		# Even using every vertex still reachable, can this walk beat the best so far?
		var room := _room_left(vertex)
		if room >= 0 and _current.size() + room > _best.size():
			for nxt: Vector3i in _graph.get(vertex, []):
				if not _visited.has(nxt):
					_dfs(nxt)
	_current.pop_back()
	_visited.erase(vertex)


## Unvisited vertices reachable from `from` without passing through the goal, or -1 if
## the goal can no longer be reached at all.
func _room_left(from: Vector3i) -> int:
	var seen := {from: true}
	var queue: Array[Vector3i] = [from]
	var count := 0
	var goal_seen := false
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_back()
		for nxt: Vector3i in _graph.get(cur, []):
			if _visited.has(nxt) or seen.has(nxt):
				continue
			seen[nxt] = true
			count += 1
			if nxt == _goal:
				goal_seen = true
			else:
				queue.append(nxt)
	return count if goal_seen else -1
