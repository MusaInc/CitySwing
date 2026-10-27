class_name RouteFollower
extends RefCounted
## Feeds the autopilot one street waypoint at a time (course recording/replay).

var wps: Array
var i := 0


func _init(waypoints: Array = []) -> void:
	wps = waypoints


func goal(p: Node3D) -> Vector3:
	var w: Vector3 = wps[i]
	if i < wps.size() - 1 and Vector2(p.global_position.x - w.x, p.global_position.z - w.z).length() < 38.0:
		i += 1
	return wps[i]


func done(p: Node3D) -> bool:
	var w: Vector3 = wps[-1]
	return i == wps.size() - 1 and Vector2(p.global_position.x - w.x, p.global_position.z - w.z).length() < 30.0
