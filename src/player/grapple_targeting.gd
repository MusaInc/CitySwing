class_name GrappleTargeting
extends RefCounted
## Finds the best attach point on real building collision geometry by fanning
## rays around the aim heading. Only bodies on the "grappleable" physics layer
## (layer 2) are candidates, so streets, props and the player never qualify.
##
## Steering: while the left stick is pushed, the fan turns toward the stick
## direction, so the stick picks where the next web goes.
## Choosing: the best-ranked candidates are flown through with the real
## SwingPhysics model (the arc, then a short flight after a release at the
## top of the up-swing). Swings that hit a building or the street are out;
## the rest are ranked by the speed they carry out of the arc in the wanted
## direction and the height they keep. `pick` is that choice (refreshed a few
## times a second, so the reticle shows the web you will actually get) and
## `pick_path` the predicted body path for the HUD preview.

const GRAPPLE_MASK := 1 << 1
const ELEVATIONS := [30.0, 42.0, 55.0, 68.0, 80.0]
const YAWS := [-42.0, -24.0, -9.0, 0.0, 9.0, 24.0, 42.0]

var has_target := false
var point := Vector3.ZERO
var normal := Vector3.ZERO
var score := 0.0
var _candidates: Array = []  # [score, point, normal], best first
## Predicted best swing (see header). pick_ok = a pick exists.
var pick_ok := false
var pick := Vector3.ZERO
var pick_gain := 0.0          # exit speed along the wanted direction (m/s)
var pick_path := PackedVector3Array()
var heading := Vector3.FORWARD  # the wanted direction (horizontal, unit)
var _pick_age := INF

## Thin things worth swinging from that the ray fan would mostly miss (crane
## jibs, bridge cables): [from, to] segments set by the world. Each update
## offers the best point on nearby lines as an extra candidate.
static var anchor_lines: Array = []
const LINE_BONUS := 0.35  # cranes and cables are the fun anchors: nudge toward them

const PREDICT_TOP := 6           # candidates flown through per evaluation
const PICK_REFRESH := 0.12       # s between evaluations
const STREET_CLEARANCE := 10.0   # m: arcs bottoming out lower than this rank down


## `aim` is the camera's forward vector; `travel` is the player's velocity.
## `steer` is the stick direction in world space (zero when not pushed).
func update(space: PhysicsDirectSpaceState3D, origin: Vector3, aim: Vector3, travel: Vector3,
		p: SwingParams, grounded: bool, exclude: Array[RID], steer := Vector3.ZERO) -> void:
	has_target = false
	score = -INF
	heading = Vector3(aim.x, 0.0, aim.z)
	if heading.length_squared() < 0.0001:
		heading = Vector3.FORWARD
	heading = heading.normalized()
	var st := Vector3(steer.x, 0.0, steer.z)
	if st.length() > 0.25:
		# The stick wins: fully at full deflection.
		heading = heading.slerp(st.normalized(), clampf((st.length() - 0.25) / 0.5, 0.0, 1.0)).normalized()
	var travel_h := Vector3(travel.x, 0.0, travel.z)
	var speed := travel_h.length()
	# Aim pitch nudges which elevation band is preferred (look up = steeper anchors).
	var aim_pitch := rad_to_deg(asin(clampf(aim.normalized().y, -1.0, 1.0)))
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = GRAPPLE_MASK
	q.exclude = exclude
	var candidates: Array = []
	_scan(space, origin, heading, travel_h, speed, aim_pitch, p, grounded, q, ELEVATIONS, YAWS, candidates)
	if not anchor_lines.is_empty():
		_scan_lines(space, origin, heading, travel_h, speed, aim_pitch, p, grounded, q, candidates)
	# (Tried: a ±65–90° side fan when nothing ahead qualifies. Novices flew
	# further, but skilled runs grabbed orbiting side webs and hit the street
	# 3× as often. Steering covers it: push the stick toward the tower.)
	candidates.sort_custom(func(a, b): return a[0] > b[0])
	_candidates = candidates
	if not candidates.is_empty():
		score = candidates[0][0]
		has_target = true
		point = candidates[0][1]
		normal = candidates[0][2]


func _scan(space: PhysicsDirectSpaceState3D, origin: Vector3, heading: Vector3, travel_h: Vector3, speed: float,
		aim_pitch: float, p: SwingParams, grounded: bool, q: PhysicsRayQueryParameters3D, elevations: Array,
		yaws: Array, candidates: Array) -> void:
	for el in elevations:
		for yw in yaws:
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
			if grounded:
				# From the ground, a high, steep anchor lifts you; a far shallow
				# one just drags you along the street.
				s += clampf(rise / 35.0, 0.0, 1.0) * 1.5 + (0.6 if el >= 55.0 else 0.0)
			# A wall facing you puts the bottom of the arc against that wall – the
			# swing ends in a collision. Side walls along the route swing cleanly.
			var n: Vector3 = hit["normal"]
			var travel_dir := travel_h / speed if speed > 3.0 else heading
			s -= 1.6 * maxf(0.0, Vector3(n.x, 0.0, n.z).dot(-travel_dir))
			# The lowest point of the swing must clear the ground below.
			var bottom := pt.y - dist
			if bottom < 2.0:
				s -= (2.0 - bottom) * 0.04
			candidates.append([s, pt, hit["normal"]])


## Candidates on `anchor_lines`: for each line in range, the points closest
## to two ideal web directions (45° and 65° up along the heading), kept if
## in reach, ahead, and in plain sight (the line's own box may block the last
## few metres).
func _scan_lines(space: PhysicsDirectSpaceState3D, origin: Vector3, heading: Vector3, travel_h: Vector3,
		speed: float, aim_pitch: float, p: SwingParams, grounded: bool, q: PhysicsRayQueryParameters3D,
		candidates: Array) -> void:
	var reach := p.grapple_range
	for line in anchor_lines:
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		# Cheap reject: the segment's box is out of reach.
		if origin.x < minf(a.x, b.x) - reach or origin.x > maxf(a.x, b.x) + reach \
				or origin.z < minf(a.z, b.z) - reach or origin.z > maxf(a.z, b.z) + reach \
				or origin.y > maxf(a.y, b.y) or origin.y < minf(a.y, b.y) - reach:
			continue
		for el: float in [45.0, 65.0]:
			var e := deg_to_rad(el)
			var dir := (heading * cos(e) + Vector3.UP * sin(e)).normalized()
			var pt := _closest_on_segment_to_ray(a, b, origin, dir)
			var off := pt - origin
			var dist := off.length()
			var rise := off.y
			if dist < 8.0 or dist > reach or rise < (0.5 if grounded else p.min_anchor_height):
				continue
			var flat := Vector3(off.x, 0.0, off.z)
			if flat.length() > 1.0 and flat.normalized().dot(heading) < 0.72:
				continue  # more than ~44° off the heading: the fan's limit
			q.from = origin
			q.to = pt
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and (hit["position"] as Vector3).distance_to(pt) > 3.5:
				continue
			var d := off / dist
			var s := _score(d, heading, travel_h, speed, rise, dist, rad_to_deg(asin(d.y)), aim_pitch, p) + LINE_BONUS
			if grounded:
				s += clampf(rise / 35.0, 0.0, 1.0) * 1.5
			if pt.y - dist < 2.0:
				s -= (2.0 - (pt.y - dist)) * 0.04
			candidates.append([s, pt, Vector3.DOWN])


static func _closest_on_segment_to_ray(a: Vector3, b: Vector3, o: Vector3, d: Vector3) -> Vector3:
	var u := b - a
	var w := a - o
	var uu := u.dot(u)
	var ud := u.dot(d)
	var dd := d.dot(d)
	var uw := u.dot(w)
	var dw := d.dot(w)
	var den := uu * dd - ud * ud
	var t := 0.0 if den < 0.000001 else clampf((ud * dw - dd * uw) / den, 0.0, 1.0)
	return a + u * t


## Re-evaluates `pick` when it is stale (call every tick; cheap otherwise).
func refresh_pick(space: PhysicsDirectSpaceState3D, from_state: SwingPhysics.State, p: SwingParams,
		exclude: Array[RID], dt: float, force := false) -> void:
	_pick_age += dt
	if not has_target:
		pick_ok = false
		pick_path.clear()
		return
	if not force and _pick_age < PICK_REFRESH:
		return
	_pick_age = 0.0
	var best := -INF
	pick_ok = false
	# Fly the best-ranked candidates, but spread out: neighbours on the same
	# wall usually share a fate, so one per few metres.
	var tried: Array[Vector3] = []
	for i in _candidates.size():
		if tried.size() >= PREDICT_TOP:
			break
		var pt: Vector3 = _candidates[i][1]
		var near := false
		for q in tried:
			if q.distance_to(pt) < 6.0:
				near = true
				break
		if near:
			continue
		tried.append(pt)
		var r := predict_swing(space, from_state, pt, p, exclude, heading)
		if not r["clear"]:
			continue
		var exit_v: Vector3 = r["exit_v"]
		var gain := exit_v.dot(heading)
		# Ranking: momentum carried out along the wanted direction, height
		# kept, then the static score (aim agreement, rope length, …).
		var sc: float = gain / 25.0 + clampf(exit_v.y / 25.0, -0.3, 0.5) \
			+ clampf(r["min_y"] - from_state.position.y + 10.0, -10.0, 10.0) * 0.02 + _candidates[i][0]
		if r["landed"]:
			sc -= 0.4  # ends on a roof: safe, but the flow stops
		elif not r["released"]:
			sc -= 0.8  # never came back up inside the window: a plunge, not a swing
		sc -= maxf(0.0, STREET_CLEARANCE - r["min_y"]) * 0.0  # skimming the street
		if sc > best:
			best = sc
			pick_ok = true
			pick = pt
			pick_gain = gain
			pick_path = r["path"]
	if not pick_ok:
		pick_path.clear()


## At the moment of firing: the predicted best swing (fresh), falling back
## to the top-ranked point if every candidate's swing hits something.
## (Tried: falling back to the swing that stays clear longest – worse.)
func best_flyable(space: PhysicsDirectSpaceState3D, from_state: SwingPhysics.State, p: SwingParams,
		exclude: Array[RID]) -> Vector3:
	refresh_pick(space, from_state, p, exclude, 0.0, true)
	return pick if pick_ok else point


static func predict_swing_clear(space: PhysicsDirectSpaceState3D, from_state: SwingPhysics.State, anchor: Vector3,
		p: SwingParams, exclude: Array[RID]) -> bool:
	return predict_swing(space, from_state, anchor, p, exclude, Vector3.ZERO)["clear"]


## Flies a swing from `anchor` with the real model: through the bottom of the
## arc, a release once it has been rising for 0.35 s, then 0.6 s of free
## flight (window scaled to the rope's swing period). clear = no building or street on the way; exit_v = velocity at the
## release; min_y = lowest point; path = sampled body positions.
static func predict_swing(space: PhysicsDirectSpaceState3D, from_state: SwingPhysics.State, anchor: Vector3,
		p: SwingParams, exclude: Array[RID], _heading: Vector3) -> Dictionary:
	var out := {"clear": false, "released": false, "landed": false, "exit_v": Vector3.ZERO, "min_y": from_state.position.y,
		"path": PackedVector3Array()}
	var s := SwingPhysics.State.new()
	s.position = from_state.position
	s.velocity = from_state.velocity
	if not SwingPhysics.attach(s, anchor, p):
		return out
	var c := SwingPhysics.Controls.new()
	var attach_length := s.rope_length
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1 | GRAPPLE_MASK | (1 << 3)
	q.exclude = exclude
	var dt := 1.0 / 30.0
	var rising := 0.0
	var passed_bottom := false
	var released := -1.0
	var prev_vy := s.velocity.y
	var path: PackedVector3Array = out["path"]
	path.append(s.position)
	# Long ropes swing slowly: cover at least a quarter period (to the bottom
	# of the arc) with margin, plus the flight after the release.
	var quarter := PI * 0.5 * sqrt(attach_length / maxf(p.gravity, 1.0))
	var steps := int(clampf(quarter * 1.5 + 0.8, 2.6, 4.5) / dt)
	for i in steps:
		var a := s.position
		if released < 0.0:
			c.reel = SwingPhysics.auto_tighten(s, p, attach_length)  # same pull as the real player
		SwingPhysics.step(s, c, p, dt)
		var dir := s.position - a
		q.from = a
		q.to = s.position + dir.normalized() * 0.4  # body radius
		# (Street contact is caught by the ray – the street is in the mask – so a
		# launch from street level isn't rejected just for starting low.)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			out["path"] = path
			# Touching down on a rooftop is a landing, not a crash; facades
			# and the street are crashes.
			var col = hit.get("collider")
			var street: bool = col is CollisionObject3D and ((col as CollisionObject3D).collision_layer & (1 << 3)) != 0
			if (hit.normal as Vector3).y > 0.6 and not street:
				out["clear"] = true
				out["landed"] = true
				if not out["released"]:
					out["exit_v"] = s.velocity
			return out
		if i % 2 == 0:
			path.append(s.position)
		out["min_y"] = minf(out["min_y"], s.position.y)
		if released >= 0.0:
			released += dt
			if released > 0.6:
				out["clear"] = true
				break
			continue
		# The bottom of the arc: the body stops falling and starts to climb
		# (also true of sideways swings that orbit a tower corner).
		passed_bottom = passed_bottom or (prev_vy <= 0.0 and s.velocity.y > 0.0)
		prev_vy = s.velocity.y
		if passed_bottom and s.velocity.y > 0.0:
			rising += dt
			if rising > 0.35:
				out["exit_v"] = s.velocity
				out["released"] = true
				SwingPhysics.release(s)
				released = 0.0
	# Collisions return early: reaching here means nothing was hit.
	out["clear"] = true
	if released < 0.0:
		out["exit_v"] = s.velocity  # still on the line at the end of the window
	out["path"] = path
	return out


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
