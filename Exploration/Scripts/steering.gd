class_name Steering
extends RefCounted
## "Which way do I walk to get there?" for followers and combatants. Call from
## _physics_process only (it queries the physics space).
##
## 1. If the room has a baked navigation mesh (a NavigationRegion3D), follow its path.
##    Nothing needs a navmesh to work, but rooms with pillars or interior walls move
##    much better with one.
## 2. Either way, feel ahead with short rays against the world (physics layer 1) and
##    turn away from anything solid, so units slide around walls and crates.

## Physics layer 1 is the world: floors, walls, props.
const WALL_MASK := 1
const FEELER_HEIGHT := 0.6
const FEELER_LENGTH := 1.6
## Angles to try, in order, when the straight line is blocked (radians).
const TURNS: Array[float] = [0.0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9]


## A flat unit vector from `body` towards `goal`, bent around obstacles. Zero if it is
## already there.
static func direction(body: Node3D, goal: Vector3, wall_mask := WALL_MASK) -> Vector3:
	var from := body.global_position
	var aim := _path_point(body, from, goal)
	var dir := aim - from
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	var to_goal := goal - from
	to_goal.y = 0.0
	return _clear_direction(body, from, dir.normalized(), minf(FEELER_LENGTH, to_goal.length() + 0.3), wall_mask)


## True if nothing solid lies on the straight line between the two points.
static func line_is_clear(body: Node3D, from: Vector3, to: Vector3, wall_mask := WALL_MASK) -> bool:
	var space := body.get_world_3d().direct_space_state
	var lift := Vector3.UP * FEELER_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from + lift, to + lift, wall_mask)
	return space.intersect_ray(query).is_empty()


## The next point to head for: along the navigation mesh when the room has one,
## otherwise the goal itself.
static func _path_point(body: Node3D, from: Vector3, goal: Vector3) -> Vector3:
	var map := body.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0 \
			or NavigationServer3D.map_get_regions(map).is_empty():
		return goal
	var path := NavigationServer3D.map_get_path(map, from, goal, true)
	for point in path:
		var flat := point - from
		flat.y = 0.0
		if flat.length() > 0.4:
			return point
	return goal


static func _clear_direction(body: Node3D, from: Vector3, dir: Vector3, look: float,
		wall_mask: int) -> Vector3:
	var space := body.get_world_3d().direct_space_state
	var origin := from + Vector3.UP * FEELER_HEIGHT
	for turn in TURNS:
		var candidate := dir.rotated(Vector3.UP, turn)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + candidate * look, wall_mask)
		if space.intersect_ray(query).is_empty():
			return candidate
	return dir
