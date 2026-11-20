class_name StreetPursuit
extends Node3D
## Emergent police chase (Musa shared foundation: NEVER STOP's driving AI in
## the open-world games). Every so often, out of view a short way from the
## player, a getaway car bolts down the road graph with police units on its
## tail – beacons, sirens, real Car physics (the AI drives through the same
## throttle/brake/steer as a player, so it skids, clips kerbs and crashes).
##
## Nothing about it is scripted to the player: you can watch it go past,
## follow it, or end it yourself – ram it in a car (WorldState) or drop onto
## it from a swing (CitySwing). `ended` says how it finished.
##
## Source of truth: WorldState src/shared/street_pursuit.gd. Synced to the
## other games by tools/shared/sync.py (see docs/SHARED.md); don't fork it.
##
## The host game wires it up:
##   pursuit.setup(net, focus_fn, camera_fn)   # RoadNet, () -> Vector3, () -> Camera3D
##   pursuit.enabled = <player is outdoors and playing>
##   pursuit.ended.connect(...)                 # reward / toast
## Collision is streamed near the player in every game, so a chase only
## starts where there is ground under all its cars, and is cleared once it
## gets too far away.

signal started(at: Vector3)
## reason: "takedown" (the player stopped it), "busted" (the police did),
## "crashed" (it wrecked itself), "escaped" (got away / too far)
signal ended(reason: String, at: Vector3)

const SPAWN_MIN := 120.0
const SPAWN_MAX := 200.0
const CLEAR_DIST := 300.0       # m from the player: everything goes (collision is streamed near the player)
const TRAIL_STEP := 3.0         # m between recorded suspect positions
const DIRECT_RANGE := 34.0      # police switch from the trail to the car itself
const GROUND_MASK := 1 | (1 << 3)

var net: RoadNet
var focus_fn := Callable()      # () -> Vector3: the player
var camera_fn := Callable()     # () -> Camera3D (or null)
## () -> bool: whether touching the getaway car stops it right now (e.g. only
## from a vehicle in WorldState; always when swinging in CitySwing).
var can_takedown := Callable()
var enabled := true
## Seconds between chases (random in range); the first comes sooner.
var interval := Vector2(75.0, 150.0)
var police_count := 2
var suspect_speed := 27.0       # m/s cap (~97 km/h: a city chase)
var police_speed := 28.5        # only a touch quicker: they close in slowly

## Captures/debug: a camera that follows the chase, and a log line every 2 s.
var debug_cam := false
var debug_log := false
var _cam: Camera3D
var _log_t := 0.0

var state := "idle"             # idle, chase, over
var suspect: Car
var police: Array[Car] = []
var reason := ""

var _drivers := {}              # Car -> AIDriver
var _force := false
var _air := {}                  # Car -> seconds with no ground under it
var _rng := RandomNumberGenerator.new()
var _next := 35.0
var _life := 0.0
var _over_t := 0.0
var _caught_t := 0.0
var _trail := PackedVector3Array()
var _route_lane := -1
var _sirens: Array[AudioStreamPlayer3D] = []
var _think := 0.0


func _ready() -> void:
	_rng.randomize()
	process_physics_priority = -5   # drivers before the cars they drive


func setup(p_net: RoadNet, p_focus: Callable, p_camera := Callable()) -> void:
	net = p_net
	focus_fn = p_focus
	camera_fn = p_camera


func active() -> bool:
	return state != "idle"


## Where the getaway car is (for markers), or INF.
func suspect_pos() -> Vector3:
	return suspect.global_position if is_instance_valid(suspect) else Vector3.INF


## Starts a chase now if a spot can be found (captures, tests, debug).
func force_start() -> bool:
	if state != "idle":
		return true
	_force = not _try_start(true)   # (keeps trying every 2 s until it can)
	if _force and debug_log:
		print("PURSUIT no spot yet near ", focus_fn.call())
	return not _force


func _physics_process(dt: float) -> void:
	if net == null or not focus_fn.is_valid():
		return
	var fp: Vector3 = focus_fn.call()
	match state:
		"idle":
			if _force:
				_next = minf(_next, 2.0)
			elif not enabled:
				return
			_next -= dt
			if _next <= 0.0:
				if _try_start(_force):
					_force = false
				else:
					_next = 2.0 if _force else 6.0   # try again shortly somewhere else
		"chase":
			_life += dt
			_chase(dt, fp)
		"over":
			_over_t += dt
			_settle(dt)
			var far := not is_instance_valid(suspect) or suspect.global_position.distance_to(fp) > CLEAR_DIST
			if far or (_over_t > 25.0 and not _seen(suspect.global_position)) or _over_t > 60.0:
				clear()


func _process(dt: float) -> void:
	if debug_log and state != "idle":
		_log_t -= dt
		if _log_t <= 0.0:
			_log_t = 2.0
			var line := "PURSUIT %s t=%.0f" % [state, _life]
			if is_instance_valid(suspect):
				line += " suspect=(%.0f,%.0f) %.0fkm/h hp=%.2f" % [suspect.global_position.x, suspect.global_position.z, suspect.speed * 3.6, suspect.health]
			for c in police:
				if is_instance_valid(c) and is_instance_valid(suspect):
					line += " cop d=%.0f %.0fkm/h" % [c.global_position.distance_to(suspect.global_position), c.speed * 3.6]
			print(line)
	if not debug_cam:
		return
	if state == "idle" or not is_instance_valid(suspect):
		return
	if _cam == null:
		_cam = Camera3D.new()
		_cam.far = 4000.0
		add_child(_cam)
		_cam.global_position = suspect.global_position + Vector3(0, 8, 0)
	_cam.make_current()
	var fwd := -suspect.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var want := suspect.global_position - fwd * 13.0 + Vector3.UP * 5.5 + suspect.global_basis.x * 4.0
	_cam.global_position = _cam.global_position.lerp(want, 1.0 - exp(-3.0 * dt))
	_cam.look_at(suspect.global_position + fwd * 6.0 + Vector3.UP, Vector3.UP)


# ------------------------------------------------------------------ start

func _try_start(forced: bool) -> bool:
	var fp: Vector3 = focus_fn.call()
	var space := get_world_3d().direct_space_state
	# The chase comes TO the player: its route runs down the road graph
	# toward them (NEVER STOP's flow field), past them, then anywhere.
	var field := net.flow_field(fp)
	for attempt in 16:
		var ang := _rng.randf() * TAU
		var d := _rng.randf_range(SPAWN_MIN, SPAWN_MAX) * (0.75 if forced else 1.0)
		var q := fp + Vector3(cos(ang) * d, 0.0, sin(ang) * d)
		var n := net.nearest(q, Vector3.ZERO, 30.0, -1, true)
		if n.is_empty():
			continue
		var lane: int = n["lane"]
		var s: float = n["s"]
		var gap := 24.0
		if s < gap * police_count + 4.0 or s > float(net.lane_len[lane]) - 30.0:
			continue
		var spots: Array = [net.lane_point(lane, s)]
		for i in police_count:
			spots.append(net.lane_point(lane, s - gap * (i + 1)))
		var ok := true
		for p: Vector3 in spots:
			if (not forced and _seen(p)) or not _ground(space, p):
				ok = false
				break
		if not ok:
			continue
		var route := net.route(field, lane, s, 520.0)
		var end := route[route.size() - 1] if route.size() > 0 else Vector3.INF
		if route.size() < 20 or Vector2(end.x - fp.x, end.z - fp.z).length() > 60.0:
			continue
		_begin(spots, net.lane_dir(lane, s), route)
		return true
	return false


func _begin(spots: Array, dir: Vector3, route: PackedVector3Array) -> void:
	var yaw := atan2(-dir.x, -dir.z)
	var bodies := ["civ_sedan", "civ_compact", "civ_suv", "civ_taxi"]
	suspect = _make_car(CarCatalog.civ_spec(String(bodies[_rng.randi() % bodies.size()]), _rng), "civilian")
	suspect.place(Transform3D(Basis(Vector3.UP, yaw), (spots[0] as Vector3) + Vector3.UP * 0.4), dir * 16.0)
	var sd := AIDriver.new(suspect)
	sd.skill = 0.93
	sd.speed_cap = suspect_speed
	sd.set_path(route)
	_drivers[suspect] = sd
	var kinds := ["patrol", "interceptor"]
	for i in police_count:
		var kind: String = kinds[i % kinds.size()] if CarCatalog.POLICE.has(kinds[i % kinds.size()]) else "patrol"
		var c := _make_car(CarCatalog.police_spec(kind), "police")
		c.place(Transform3D(Basis(Vector3.UP, yaw), (spots[i + 1] as Vector3) + Vector3.UP * 0.4), dir * 16.0)
		if c.visual and c.visual.has_method("set_siren"):
			c.visual.set_siren(true)
			if i == 0 and c.visual.has_method("set_beacon_lights"):
				c.visual.set_beacon_lights(true)
		var pd := AIDriver.new(c)
		pd.skill = 0.9
		pd.speed_cap = police_speed
		pd.set_path(route)
		_drivers[c] = pd
		police.append(c)
		_add_siren(c, i)
	_trail = PackedVector3Array([spots[min(2, spots.size() - 1)], spots[1], spots[0]])
	_life = 0.0
	_caught_t = 0.0
	reason = ""
	state = "chase"
	started.emit(spots[0])


func _make_car(spec: Dictionary, role: String) -> Car:
	var c := Car.new()
	c.setup(spec, role)
	c.name = "Pursuit_%s" % role
	add_child(c)
	var v := CarVisual.new()
	c.add_child(v)
	v.setup(c)
	c.visual = v
	return c


func _add_siren(c: Car, i: int) -> void:
	var path := "res://assets/audio/siren_wail.wav" if i % 2 == 0 else "res://assets/audio/siren_yelp.wav"
	if not ResourceLoader.exists(path):
		return
	var st := load(path) as AudioStreamWAV
	if st == null:
		return
	st = st.duplicate()
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_end = st.data.size() / (2 * (2 if st.stereo else 1))
	var a := AudioStreamPlayer3D.new()
	a.stream = st
	a.unit_size = 14.0
	a.max_distance = 420.0
	a.volume_db = -4.0
	a.pitch_scale = 1.0 + 0.04 * i
	if AudioServer.get_bus_index("SFX") >= 0:
		a.bus = "SFX"
	c.add_child(a)
	a.position = Vector3(0, 1.4, 0)
	a.play(_rng.randf() * 2.0)
	_sirens.append(a)


# ------------------------------------------------------------------ chase

func _chase(dt: float, fp: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	if not is_instance_valid(suspect):
		clear()
		return
	var sp := suspect.global_position
	# Recorded trail: the police follow the road the suspect really took.
	if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(sp) > TRAIL_STEP:
		_trail.append(sp)
		if _trail.size() > 260:
			_trail = _trail.slice(_trail.size() - 200)
	var sd: AIDriver = _drivers[suspect]
	if sd.remaining() < 25:
		var n := net.nearest(sp, -suspect.global_basis.z, 20.0)
		if not n.is_empty():
			sd.set_path(net.wander(int(n["lane"]), float(n["s"]), 420.0, _rng, 0.45))
	sd.update(dt, space)
	_think -= dt
	var rethink := _think <= 0.0
	if rethink:
		_think = 0.5
	var closest := INF
	for c in police:
		if not is_instance_valid(c):
			continue
		var pd: AIDriver = _drivers[c]
		var d := c.global_position.distance_to(sp)
		closest = minf(closest, d)
		if d < DIRECT_RANGE:
			pd.direct_target = sp
			pd.direct_vel = suspect.linear_velocity
			pd.ram = d < 14.0 and _life > 20.0
		else:
			pd.direct_target = Vector3.INF
			pd.ram = false
			if rethink:
				pd.set_path(_trail_from(c.global_position))
		pd.update(dt, space)
	# Endings.
	if (fp - sp).length() < _touch_radius() and suspect.speed > 2.0 \
			and (not can_takedown.is_valid() or bool(can_takedown.call())):
		_takedown()
		return
	if suspect.disabled:
		_finish("crashed")
		return
	if _lost(suspect):
		_finish("crashed")
		clear()
		return
	for c in police:
		if _lost(c) or c.global_position.distance_to(sp) > 160.0:
			# (A unit that left the road for good drops out quietly.)
			if debug_log:
				print("PURSUIT unit lost water=%s y=%.1f" % [c.in_water, c.global_position.y])
			police.erase(c)
			_drivers.erase(c)
			c.queue_free()
			break
	_caught_t = _caught_t + dt if (closest < 9.0 and suspect.speed < 4.0) else maxf(_caught_t - dt, 0.0)
	if _caught_t > 2.5 and _life > 25.0:
		_finish("busted")
		return
	if sp.distance_to(fp) > CLEAR_DIST or _life > 240.0:
		_finish("escaped")
		clear()


## How close the player has to get to the getaway car to stop it: a car's
## half length plus the player's reach (on foot / swinging this is landing
## on it; in a car it's the bodies touching).
func _touch_radius() -> float:
	return 3.4


## Stops the getaway car on the spot (a ram, a hero landing on it).
func _takedown() -> void:
	if not is_instance_valid(suspect):
		return
	var v := suspect.linear_velocity
	suspect.apply_central_impulse(-v * suspect.mass * 0.55)
	suspect.apply_torque_impulse(Vector3.UP * suspect.mass * _rng.randf_range(-2.5, 2.5))
	suspect.health = minf(suspect.health, 0.25)
	_finish("takedown")


func _finish(why: String) -> void:
	if debug_log:
		print("PURSUIT end %s t=%.0f water=%s y=%.1f" % [why, _life, suspect.in_water if is_instance_valid(suspect) else false,
			suspect.global_position.y if is_instance_valid(suspect) else 0.0])
	reason = why
	state = "over"
	_over_t = 0.0
	if is_instance_valid(suspect):
		suspect.disabled = true
		(_drivers[suspect] as AIDriver).brake_hold = true
	ended.emit(why, suspect_pos())


## After the chase: the suspect stays put, the police pull up round it,
## beacons on, sirens off after a moment.
func _settle(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	var sp := suspect_pos()
	for c in police:
		if not is_instance_valid(c):
			continue
		var pd: AIDriver = _drivers[c]
		if sp == Vector3.INF or c.global_position.distance_to(sp) < 11.0:
			pd.brake_hold = true
		else:
			pd.direct_target = sp
			pd.ram = false
		pd.update(dt, space)
	if is_instance_valid(suspect):
		(_drivers[suspect] as AIDriver).update(dt, space)
	if _over_t > 4.0:
		for a in _sirens:
			if is_instance_valid(a):
				a.volume_db = lerpf(a.volume_db, -60.0, 1.0 - exp(-1.5 * dt))


func clear() -> void:
	for c in [suspect] + police:
		if is_instance_valid(c):
			c.queue_free()
	suspect = null
	police.clear()
	_drivers.clear()
	_air.clear()
	_sirens.clear()
	_trail = PackedVector3Array()
	state = "idle"
	_next = _rng.randf_range(interval.x, interval.y)


# ---------------------------------------------------------------- helpers

func _trail_from(p: Vector3) -> PackedVector3Array:
	var best := 0
	var bd := INF
	for i in _trail.size():
		var d := _trail[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return _trail.slice(best)


func _seen(p: Vector3) -> bool:
	var cam: Camera3D = camera_fn.call() if camera_fn.is_valid() else get_viewport().get_camera_3d()
	if cam == null:
		return false
	if cam.global_position.distance_to(p) < 45.0:
		return true
	return cam.is_position_in_frustum(p + Vector3.UP)


## Real road under p: a hit within 1.5 m of the lane height (not the seabed
## or a lower street seen through a deck whose collision isn't streamed in).
func _ground(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 8.0, GROUND_MASK)
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and absf((hit["position"] as Vector3).y - p.y) < 1.5


## Off the road for good: in the water, or nothing under it for a while
## (fell off a deck, out past the streamed-in collision).
func _lost(c: Car) -> bool:
	if not is_instance_valid(c):
		return true
	if c.in_water:
		return true
	var space := get_world_3d().direct_space_state
	var p := c.global_position
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 4.0, GROUND_MASK)
	q.exclude = [c.get_rid()]
	var t: float = _air.get(c, 0.0)
	t = 0.0 if not space.intersect_ray(q).is_empty() else t + get_physics_process_delta_time()
	_air[c] = t
	return t > 1.5
