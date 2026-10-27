class_name GrappleTargeting
extends RefCounted
## Finds the best attach point on real building collision geometry by fanning
## rays around the aim heading. Only bodies on the "grappleable" physics layer
## (layer 2) are candidates, so streets, props and the player never qualify.

const GRAPPLE_MASK := 1 << 1
const ELEVATIONS := [30.0, 42.0, 55.0, 68.0, 80.0]
const YAWS := [-42.0, -24.0, -9.0, 0.0, 9.0, 24.0, 42.0]

var has_target := false
var point := Vector3.ZERO
var normal := Vector3.ZERO
var score := 0.0


## `aim` is the camera's forward vector; `travel` is the player's velocity.
func update(space: PhysicsDirectSpaceState3D, origin: Vector3, aim: Vector3, travel: Vector3,
		p: SwingParams, grounded: bool, exclude: Array[RID]) -> void:
	has_target = false
	score = -INF
	var heading := Vector3(aim.x, 0.0, aim.z)
	if heading.length_squared() < 0.0001:
		heading = Vector3.FORWARD
	heading = heading.normalized()
	var travel_h := Vector3(travel.x, 0.0, travel.z)
	var speed := travel_h.length()
	# Aim pitch nudges which elevation band is preferred (look up = steeper anchors).
	var aim_pitch := rad_to_deg(asin(clampf(aim.normalized().y, -1.0, 1.0)))
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = GRAPPLE_MASK
	q.exclude = exclude
	for el in ELEVATIONS:
		for yw in YAWS:
			var dir := heading.rotated(Vector3.UP, deg_to_rad(yw))
			var e := deg_to_rad(el)
			dir = (dir * cos(e) + Vector3.UP * sin(e)).normalized()
			q.from = origin
			q.to = origin + dir * p.grapple_range
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var pt: Vector3 = hit["position"]
			var rise := pt.y - origin.y
			if rise < (0.5 if grounded else p.min_anchor_height):
				continue
			var dist := origin.distance_to(pt)
			if dist < 6.0:
				continue
			var s := _score(dir, heading, travel_h, speed, rise, dist, el, aim_pitch, p)
			# A wall facing you puts the bottom of the arc against that wall – the
			# swing ends in a collision. Side walls along the route swing cleanly.
			var n: Vector3 = hit["normal"]
			var travel_dir := travel_h / speed if speed > 3.0 else heading
			s -= 1.6 * maxf(0.0, Vector3(n.x, 0.0, n.z).dot(-travel_dir))
			# The lowest point of the swing must clear the ground below.
			var bottom := pt.y - dist
			if bottom < 2.0:
				s -= (2.0 - bottom) * 0.04
			if s > score:
				score = s
				has_target = true
				point = pt
				normal = hit["normal"]


static func _score(dir: Vector3, heading: Vector3, travel_h: Vector3, speed: float, rise: float,
		dist: float, el: float, aim_pitch: float, p: SwingParams) -> float:
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var s := 2.0 * flat.dot(heading)
	if speed > 3.0:
		s += 1.2 * flat.dot(travel_h / speed)
	# Long ropes give long, fast arcs; very long ones are hard to control.
	s += 1.0 - absf(dist - p.grapple_range * 0.55) / p.grapple_range
	# Prefer the elevation band closest to where the camera is pointing (+35°).
	s -= absf(el - clampf(aim_pitch + 50.0, 30.0, 80.0)) / 60.0
	s += clampf(rise / 30.0, 0.0, 1.0) * 0.5
	return s
