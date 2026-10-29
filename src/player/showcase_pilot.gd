class_name ShowcasePilot
extends SwingBot
## Title-screen autopilot: the expert bot, flown for the camera. It tours a
## loop of the four inner avenues (turning at the corners), keeps to the
## middle of the street, aims high for long arcs, and picks each web by how
## well its predicted swing stays inside the avenue – no wall-hugging, no
## bumps. Only the title screen uses it, so the tests' expert is unchanged.

const LOOK_AHEAD := 70.0   # m along the avenue to steer toward
const TURN_AT := 22.0      # m before a corner to switch to the next avenue
const SETBACK := 4.7       # m from the kerb line to the facades (pavement)
const MARGIN := 7.0        # m kept clear of the facades

var _loop: Array[Vector2] = []  # corners, travelled in order
var _half: Array[float] = []    # half-width of the avenue leading to each corner
var _seg := 0
var _bad := 0.0  # s the current shot has looked wrong (see needs_cut)


func _init(world: Node) -> void:
	super(SwingBot.Style.EXPERT, Vector3.FORWARD)
	_build_loop(world.layout)
	goal_fn = _goal


## Corner loop: the outermost wide avenues that aren't at the map's edge.
func _build_loop(layout: CityLayout) -> void:
	var xs := _inner_avenues(layout.x_streets, CityLayout.MIN_X, CityLayout.MAX_X)
	var zs := _inner_avenues(layout.z_streets, CityLayout.MIN_Z, CityLayout.MAX_Z)
	if xs.size() < 2 or zs.size() < 2:
		return
	var x0: Array = xs[0]
	var x1: Array = xs[-1]
	var z0: Array = zs[0]
	var z1: Array = zs[-1]
	# Down the east avenue, west along the north one, up the west, east along the south.
	_loop = [Vector2(x1[0], z0[0]), Vector2(x0[0], z0[0]), Vector2(x0[0], z1[0]), Vector2(x1[0], z1[0])]
	_half = [x1[1] * 0.5, z0[1] * 0.5, x0[1] * 0.5, z1[1] * 0.5]


static func _inner_avenues(streets: Array, lo: float, hi: float) -> Array:
	var out := []
	for s in streets:
		if s[1] > 20.0 and s[0] - lo > 100.0 and hi - s[0] > 100.0:
			out.append(s)
	return out


## A mid-air start part-way down a random leg: [position, velocity]. The
## title screen drops the hero straight into a swing here.
func entry(rng: RandomNumberGenerator) -> Array:
	if _loop.is_empty():
		return [Vector3(0, 50, 0), Vector3.ZERO]
	_seg = rng.randi() % _loop.size()
	var l := _leg(_seg)
	var a: Vector2 = l[0]
	var b: Vector2 = l[1]
	var g := a.lerp(b, rng.randf_range(0.15, 0.5))
	var along := (b - a).normalized()
	return [Vector3(g.x, 48.0, g.y), Vector3(along.x, -0.15, along.y).normalized() * 20.0]


## Starts on the leg nearest the hero.
func start_near(pos: Vector3) -> void:
	var best := INF
	for i in _loop.size():
		var d := _dist_to_leg(Vector2(pos.x, pos.z), i)
		if d < best:
			best = d
			_seg = i


func _leg(i: int) -> Array:
	return [_loop[(i - 1 + _loop.size()) % _loop.size()], _loop[i]]


func _dist_to_leg(p: Vector2, i: int) -> float:
	var l := _leg(i)
	return Geometry2D.get_closest_point_to_segment(p, l[0], l[1]).distance_to(p)


func _goal(p: Node3D) -> Vector3:
	if _loop.is_empty():
		return p.global_position + Vector3.FORWARD * LOOK_AHEAD
	var pos := Vector2(p.global_position.x, p.global_position.z)
	var l := _leg(_seg)
	if pos.distance_to(l[1]) < TURN_AT + _half[_seg]:
		_seg = (_seg + 1) % _loop.size()
		l = _leg(_seg)
	var a: Vector2 = l[0]
	var b: Vector2 = l[1]
	var along := (b - a).normalized()
	var off := absf((pos - a).dot(Vector2(-along.y, along.x)))
	var ahead := LOOK_AHEAD if off < _half[_seg] else 30.0  # off the avenue: head back in
	var t := clampf((pos - a).dot(along) + ahead, 0.0, a.distance_to(b))
	var g := a + along * t
	return Vector3(g.x, 0.0, g.y)


## True once the flight has looked wrong for a moment – stalled or pinned on
## a wall, wandered off the avenue, knocked out, or down on the street – so
## the title screen cuts to a fresh entry instead of showing it.
func needs_cut(p: Player, dt: float) -> bool:
	if _loop.is_empty():
		return false
	var wrong := p.stunned or p.knocked_out or (p.global_position.y < 3.0 and p.is_on_floor()) \
		or (not p.is_on_floor() and p.s.velocity.length() < 5.0) \
		or absf(_lateral(p.global_position)) > _half[_seg] + SETBACK + 8.0
	_bad = _bad + dt if wrong else maxf(_bad - dt * 0.5, 0.0)
	if _bad > 1.2:
		_bad = 0.0
		return true
	return false


## For SwingCamera.rail: the centre line of the avenue being flown, at pos.
func rail(pos: Vector3) -> Array:
	if _loop.is_empty():
		return []
	var l := _leg(_seg)
	var a: Vector2 = l[0]
	var b: Vector2 = l[1]
	var c := Geometry2D.get_closest_point_to_segment(Vector2(pos.x, pos.z), a, b)
	var d := (b - a).normalized()
	return [Vector3(c.x, pos.y, c.y), Vector3(d.x, 0.0, d.y)]


## Signed distance from the current avenue's centre line (+ = right of travel).
func _lateral(at: Vector3) -> float:
	var l := _leg(_seg)
	var along: Vector2 = (l[1] - l[0]).normalized()
	var off := Vector2(at.x, at.z) - (l[0] as Vector2)
	return off.dot(Vector2(-along.y, along.x))


func drive(p: Player, dt: float) -> Dictionary:
	var out := super(p, dt)
	if p.is_on_floor():
		return out
	# A hard hit coming no matter what: always take the wall-kick save (an
	# acrobatic flip off the wall) rather than a knockout.
	var hit := _wall_ahead(p)
	if hit and hit[1] < p.params.wall_save_window * 0.8:
		out["jump"] = true
	if _loop.is_empty():
		return out
	# Ease back toward the middle of the avenue, and look high for anchors:
	# long ropes from high up swing down the street instead of across it.
	var l := _leg(_seg)
	var along: Vector2 = (l[1] - l[0]).normalized()
	var side := Vector3(-along.y, 0.0, along.x)
	var fwd := Vector3(along.x, 0.0, along.y)
	var lat := _lateral(p.global_position)
	var move: Vector3 = out["move"]
	if move.length_squared() > 0.01:
		out["move"] = (move.normalized() - side * clampf(lat / _half[_seg], -1.0, 1.0) * 0.8).normalized()
	out["aim"] = (fwd + Vector3.UP * 0.55).normalized()
	# Drifting toward a facade in free flight (the swing's sideways speed
	# carries on after the release): web back in before reaching it.
	var v_lat := p.s.velocity.dot(side)
	var wall := _half[_seg] + SETBACK
	if p.line_state == Player.Line.IDLE and signf(v_lat) == signf(lat) and p.targeting.has_target \
			and absf(lat + v_lat * 0.8) > wall - 3.0:
		_hold = _repress(true)
		out["grapple"] = _hold
	return out


func _room() -> float:
	return _half[_seg] + SETBACK - MARGIN


## Called by Player when a web is fired: of the targeting's candidates, the
## one whose predicted swing keeps furthest inside the avenue while carrying
## the most speed along it. Falls back to the default pick.
func choose_anchor(p: Player, fallback: Vector3) -> Vector3:
	if _loop.is_empty():
		return fallback
	var space := p.get_world_3d().direct_space_state
	var from := p._launch_state()
	var l := _leg(_seg)
	var along: Vector2 = (l[1] - l[0]).normalized()
	var fwd := Vector3(along.x, 0.0, along.y)
	var room := _room()
	var pos_lat := _lateral(p.global_position)
	var best := -INF
	var pick := fallback
	var tried: Array[Vector3] = []
	for c in p.targeting.candidates():
		if tried.size() >= 12:
			break
		var pt: Vector3 = c[1]
		var near := false
		for q in tried:
			if q.distance_to(pt) < 6.0:
				near = true
				break
		if near:
			continue
		tried.append(pt)
		var r := GrappleTargeting.predict_swing(space, from, pt, p.params, [p.get_rid()], fwd)
		if not r["clear"]:
			continue
		var worst := 0.0
		for q in (r["path"] as PackedVector3Array):
			worst = maxf(worst, absf(_lateral(q)) - room)
		var exit_v: Vector3 = r["exit_v"]
		var sc := exit_v.dot(fwd) / 25.0 + clampf(exit_v.y / 25.0, -0.3, 0.5) - maxf(worst, 0.0) * 0.3 \
			+ float(c[0]) * 0.5
		# Past the facade line means into a side street or the next block.
		if worst > MARGIN - 1.0:
			sc -= 4.0
		if absf(_lateral(pt)) > _half[_seg] + SETBACK + 1.5:
			sc -= 1.5  # not on this avenue's facades
		# Off-centre: prefer the far side's facade to swing back across.
		var a_lat := _lateral(pt)
		if absf(pos_lat) > 3.0 and signf(a_lat) == signf(pos_lat):
			sc -= 0.4 * absf(pos_lat) / maxf(room, 1.0)
		if r["landed"]:
			sc -= 0.6
		elif not r["released"]:
			sc -= 0.8
		if r["min_y"] < 10.0:
			sc -= (10.0 - r["min_y"]) * 0.05
		if sc > best:
			best = sc
			pick = pt
	if OS.has_environment("PILOT_TRACE"):
		print("  choose: tried %d best %.2f pick_lat %.1f fallback_lat %.1f pos_lat %.1f seg %d" % [tried.size(), best,
			_lateral(pick), _lateral(fallback), _lateral(p.global_position), _seg])
	return pick
