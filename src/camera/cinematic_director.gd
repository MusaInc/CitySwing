class_name CinematicDirector
extends Node
## Title-screen cinematography: cycles nine composed 12 s shots of the real game
## (real city, lighting and hero, flown by the ShowcasePilot) behind the menu.
##
##   1 Golden hour   – chase from the side at sunset, towers lit warm.
##   2 Urban canyon  – a camera low in the street ahead; the hero dives in
##                     over it and swings away (a moment of slow motion).
##   3 Skyline       – long lens from high up and far off: the hero crosses
##                     the city's scale.
##   4 Momentum      – close three-quarter front: hoodie, cords and web line
##                     at speed, slowed a little.
##   5 Rooftops      – morning, just over the roofline, looking out along the
##                     travel to the skyline and the sea.
##   Orbit (a slow arc round the hero), Blue hour (dusk chase over the lit
##   streets), Crane (rises from the street to above the roofs), Drone (high
##   overhead down the avenue).
## Each shot sets its own time of day, starts the hero on a chosen avenue leg
## and hands SwingCamera a transform each frame (camera.cine). The subject is
## kept left of centre, clear of the menu's top-right controls. Cuts dip
## through Night Ink (main's curtain). Leaving the title restores the clock,
## weather and time scale.

const SHOT_LEN := 12.0  # long, unhurried shots
## Scenic flights (2026-11-05): each shot flies a stretch of a real Time Trial
## route – the expert autopilot following the route's waypoints, entered from
## the recorded flight at sample k (config/courses.json) – that
## tools/title_shots.gd has flown for real several times and found clean (no
## crash, never on the street, never stalled, high over the city). "cam" is
## the camera move, "hour" the light. Routes: canyon = the Central Spine
## 150 m up through the towers, waterfront = down the Grand Diagonal to the
## clock towers and the strait, grand_tour = round the skyscraper ring.
const SHOTS := [
	{"name": "skyline", "course": "canyon", "k": 45, "hour": 18.3, "slow": 1.0},
	{"name": "rooftops", "course": "waterfront", "k": 200, "hour": 17.9, "slow": 1.0},
	{"name": "orbit", "course": "grand_tour", "k": 200, "hour": 17.2, "slow": 1.0},
	{"name": "golden", "course": "waterfront", "k": 45, "hour": 18.5, "slow": 1.0},
	{"name": "crane", "course": "canyon", "k": 45, "hour": 8.8, "slow": 1.0},
	{"name": "bluehour", "course": "grand_tour", "k": 330, "hour": 20.3, "slow": 1.0},
	{"name": "momentum", "course": "grand_tour", "k": 70, "hour": 17.6, "slow": 0.7},
	{"name": "drone", "course": "waterfront", "k": 200, "hour": 10.2, "slow": 1.0},
	{"name": "canyon", "course": "canyon", "k": 215, "hour": 15.6, "slow": 0.6},
]

var main: Node
var player: Player
var camera: SwingCamera
var pilot: ShowcasePilot
var atmosphere: Atmosphere
var dip: Callable            # main._dip(change, out, in)
var shot := -1
var shot_t := 0.0
var _saved := {}
var _fwd := Vector3.FORWARD
var _fov := 60.0
var _off := Vector3.ZERO
var _look_off := Vector3.ZERO
var _side := 1.0
var _fresh_offset := true
var _fresh := true
var _cutting := false
var _follower: RouteFollower
var _bad_t := 0.0
var _courses := {}


# ------------------------------------------------------------- shop studio
## The shop: the hero stands on a quiet rooftop (a real one, picked once:
## high, open, near the business district) in soft late-afternoon light,
## idling, while an orbit camera frames whatever category is being browsed.
## The hero sits right of centre (the wardrobe is on the left).
const SHOP_FRAME := {
	"full": [1.0, 3.6], "suit": [1.3, 2.1], "pants": [0.62, 2.3], "shoes": [-0.02, 1.35],
	"gloves": [1.0, 1.6], "web": [1.05, 1.7], "head": [1.62, 1.25], "face": [1.66, 1.1], "gadget": [1.0, 3.4],
}
var in_shop := false
var shop_focus := "full"
var shop_yaw := 0.0
var shop_zoom := 1.0
var _shop_spot := {}
var _shop_h := 1.0
var _shop_d := 3.6
var _shop_yaw_s := 0.0


class _Stand:
	extends RefCounted
	func drive(_p, _dt) -> Dictionary:
		return {"move": Vector3.ZERO, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}


func enter_shop() -> void:
	in_shop = true
	shot = -1
	Engine.time_scale = 1.0
	if _shop_spot.is_empty():
		_shop_spot = _pick_shop_roof()
	atmosphere.hour = 16.9
	atmosphere.set_weather("clear", true)
	var p: Vector3 = _shop_spot.get("position", player.global_position)
	if main and main.world.has_method("build_all_near"):
		main.world.build_all_near(p, 420.0)
	player.bot = _Stand.new()
	player.respawn(p)
	player.s.velocity = Vector3.ZERO
	var face: Vector3 = _shop_spot.get("face", Vector3.FORWARD)
	(main.rig as CharacterRig).set_facing(face)
	(main.rig as CharacterRig).idle_actions = false  # no glancing away mid try-on
	reset_shop_view()
	_shop_yaw_s = shop_yaw
	_fresh = true
	_fresh_offset = true
	camera.cine = shop_xf
	camera.snap()


func exit_shop() -> void:
	in_shop = false
	(main.rig as CharacterRig).idle_actions = true
	player.bot = pilot
	camera.cine = camera_xf
	cut_to(maxi(shot, 0))


func reset_shop_view() -> void:
	shop_yaw = 0.35
	shop_zoom = 1.0


## A roof for the studio: from the real rooftop spawns, the one nearest the
## business district between 55 and 110 m up; the hero faces the open side.
func _pick_shop_roof() -> Dictionary:
	if main == null or not main.world.has_method("rooftop_spawns"):
		return {}
	var best := {}
	var bd := INF
	for sp in main.world.rooftop_spawns():
		var h: float = sp["height"]
		if h < 55.0 or h > 110.0:
			continue
		var p: Vector3 = sp["position"]
		var d := Vector2(p.x, p.z).distance_to(CityLayout.CBD_CENTER)
		if d < bd:
			bd = d
			best = sp.duplicate()
	if best.is_empty():
		return {}
	# Face the way with the most open air (the camera then looks back at the
	# hero with the city behind).
	var p: Vector3 = best["position"]
	var space := player.get_world_3d().direct_space_state
	var far := -1.0
	for i in 8:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.UP * 1.5 + dir * 80.0, 1 | (1 << 1))
		var hit := space.intersect_ray(q)
		var dd := 80.0 if hit.is_empty() else p.distance_to(hit.position)
		if dd > far:
			far = dd
			best["face"] = dir
	return best


func shop_xf(dt: float) -> Array:
	var fr: Array = SHOP_FRAME.get(shop_focus, SHOP_FRAME["full"])
	var k := 1.0 - exp(-4.0 * dt)
	_shop_h = lerpf(_shop_h, fr[0], k)
	_shop_d = lerpf(_shop_d, float(fr[1]) * shop_zoom, k)
	_shop_yaw_s = lerp_angle(_shop_yaw_s, shop_yaw, 1.0 - exp(-10.0 * dt))
	var feet := player.global_position + Vector3.DOWN * 0.9
	var aim := feet + Vector3.UP * _shop_h
	var face: Vector3 = _shop_spot.get("face", Vector3.FORWARD)
	var dir := face.rotated(Vector3.UP, _shop_yaw_s)
	var pitch := lerpf(0.42, -0.05, clampf((_shop_h - 0.08) / 1.2, 0.0, 1.0))  # look down at the feet, level at the head
	var pos := aim + (dir + Vector3.UP * (pitch + 0.08)).normalized() * _shop_d
	pos = _clear(aim, pos)
	var xf := Transform3D(Basis.looking_at((aim - pos).normalized(), Vector3.UP), pos)
	var vp := player.get_viewport().get_visible_rect().size
	var width := 2.0 * _shop_d * tan(deg_to_rad(40.0) * 0.5) * (vp.x / maxf(vp.y, 1.0))
	var want := -width * 0.21  # hero right of centre, clear of the wardrobe
	camera.cam.h_offset = want if _fresh_offset else lerpf(camera.cam.h_offset, want, 1.0 - exp(-5.0 * dt))
	_fresh_offset = false
	return [xf, 40.0]


func begin() -> void:
	_saved = {"hour": atmosphere.hour, "live": atmosphere.live, "weather": atmosphere.weather}
	atmosphere.live = false
	camera.cine = camera_xf
	cut_to(0)


func end() -> void:
	camera.cine = Callable()
	camera.cam.h_offset = 0.0
	Engine.time_scale = 1.0
	if not _saved.is_empty():
		atmosphere.hour = _saved["hour"]
		atmosphere.live = _saved["live"]
		atmosphere.set_weather(_saved["weather"], true)
	queue_free()


## Starts shot i now (call while the screen is covered).
func cut_to(i: int) -> void:
	shot = posmod(i, SHOTS.size())
	shot_t = 0.0
	var s: Dictionary = SHOTS[shot]
	if not atmosphere.fixed_hour:
		atmosphere.hour = s["hour"]
	atmosphere.set_weather("clear", true)
	var e := _course_entry(s)
	if e.is_empty():
		# (No recorded routes: the avenue tour.)
		player.bot = pilot
		e = pilot.entry_on(0, 0.12, 52.0, 22.0)
	player.respawn(e[0])
	player.s.velocity = e[1]
	_bad_t = 0.0
	_fwd = Vector3(e[1].x, 0.0, e[1].z).normalized()
	_side = _open_side(e[0], _fwd)
	_fresh_offset = true
	_fresh = true
	camera.snap()
	_cutting = false


## Spawns into shot s's scenic flight: [position, velocity] (and sets the
## autopilot on the route), or [] if the route isn't available.
func _course_entry(s: Dictionary) -> Array:
	if _courses.is_empty():
		_courses = CourseBuilder._load_all()
	var id: String = s.get("course", "")
	if not _courses.has(id) or main == null or not main.world.get("layout"):
		return []
	var path: Array = _courses[id]["path"]
	var wps: Array = CourseBuilder.route(id, main.world.layout)["waypoints"]
	var k: int = clampi(int(s["k"]), 1, path.size() - 2)
	var e := _entry(path, wps, k)
	if main.world.has_method("build_all_near"):
		main.world.build_all_near(e[0], 420.0)
	_follower = RouteFollower.new(wps)
	_follower.i = e[2]
	var bot := SwingBot.new(SwingBot.Style.EXPERT, Vector3.FORWARD)
	bot.goal_fn = _follower.goal
	player.bot = bot
	return [e[0], e[1]]


## Same entry as tools/title_shots.gd: the recorded position at sample k, its
## velocity (samples 0.1 s apart) and the next waypoint ahead.
static func _entry(path: Array, wps: Array, k: int) -> Array:
	var a: Array = path[k]
	var p := Vector3(a[0], a[1], a[2])
	var n: Array = path[k + 1]
	var b: Array = path[k - 1]
	var v := (Vector3(n[0], n[1], n[2]) - Vector3(b[0], b[1], b[2])) / 0.2
	var wi := 0
	var best := INF
	for i in wps.size():
		var w: Vector3 = wps[i]
		var d := Vector2(w.x - p.x, w.z - p.z).length()
		if d < best and Vector2(w.x - p.x, w.z - p.z).dot(Vector2(v.x, v.z)) > 0.0:
			best = d
			wi = i
	return [p, v, wi]


## A live flight can still go wrong (the title's world isn't the validator's):
## knocked out, down on the street, stalled or at the end of the route – cut
## away before it shows.
func _flight_bad(dt: float) -> bool:
	if _follower == null or player.bot is ShowcasePilot:
		return pilot.needs_cut(player, dt) if pilot else false
	var wrong := player.stunned or player.knocked_out \
		or (player.is_on_floor() and player.height_above_ground() < 3.0) \
		or (not player.is_on_floor() and player.s.velocity.length() < 5.0) \
		or player.height_above_ground() < 4.0 or _follower.done(player)
	_bad_t = _bad_t + dt if wrong else maxf(_bad_t - dt * 0.5, 0.0)
	return _bad_t > 0.5


func _westmost_leg() -> int:
	var best := 0
	var bd := INF
	for i in pilot.leg_count():
		var d := pilot.leg_dir(i)
		if d.x < bd:
			bd = d.x
			best = i
	return best


func _process(dt: float) -> void:
	if shot < 0:
		return
	var rdt := dt / maxf(Engine.time_scale, 0.05)  # shots are timed in real time
	shot_t += rdt
	var s: Dictionary = SHOTS[shot]
	# Slow motion: eased in and out over the middle of the shot.
	var slow: float = s["slow"]
	if slow < 1.0:
		var k := smoothstep(2.0, 3.2, shot_t) * (1.0 - smoothstep(7.5, 8.8, shot_t))
		Engine.time_scale = lerpf(1.0, slow, k)
	else:
		Engine.time_scale = 1.0
	var bad := _flight_bad(dt)
	if not _cutting and (shot_t > SHOT_LEN or (bad and shot_t > 1.0)):
		_cutting = true
		Engine.time_scale = 1.0
		if dip.is_valid():
			dip.call(cut_to.bind(shot + 1), 0.35, 0.5)
		else:
			cut_to(shot + 1)


## For SwingCamera.cine: [Transform3D, fov].
## Trail camera: most moves hang the lens off the hero's own recent flight
## path (where they were `delay` seconds ago, raised/offset a little). That
## space is open air by construction – the hero just flew through it – so the
## camera never ends up inside a tower or staring at a facade, and it looks
## ahead down the corridor the hero is flying into: the view.
const CAM := {
	# metres back along the flight path, lift m, side m, lead s, fov
	"chase": [6.0, 0.7, 0.9, 0.18, 58.0],
	"wide": [13.0, 1.6, 1.6, 0.25, 60.0],
	"high": [12.0, 6.5, 2.0, 0.3, 58.0],
	"telephoto": [30.0, 2.0, 2.5, 0.2, 28.0],
	"low": [7.0, -3.0, 1.2, 0.25, 64.0],
}
## Pitch limits per move (radians): views keep the horizon in frame instead
## of staring down into the street.
const PITCH := {"chase": [-0.2, 0.25], "wide": [-0.16, 0.22], "high": [-0.42, 0.1], "telephoto": [-0.12, 0.18],
	"low": [0.0, 0.65]}
const STYLE := {"skyline": "wide", "rooftops": "wide", "orbit": "chase", "crane": "high", "bluehour": "wide",
	"momentum": "chase", "drone": "high", "canyon": "low"}
var _trail: Array = []   # [t, position] (real time), newest last
var _trail_t := 0.0


## The point `dist` metres back along the hero's recent flight path.
func _trail_back(dist: float) -> Vector3:
	var left := dist
	var prev: Vector3 = player.global_position
	for i in range(_trail.size() - 1, -1, -1):
		var q: Vector3 = _trail[i][1]
		var seg := prev.distance_to(q)
		if seg >= left and seg > 0.001:
			return prev.lerp(q, left / seg)
		left -= seg
		prev = q
	# Not enough history yet (just cut): back along the travel.
	var v := player.s.velocity
	return prev - (v.normalized() if v.length() > 0.5 else _fwd) * left


func camera_xf(dt: float) -> Array:
	var rdt := dt / maxf(Engine.time_scale, 0.05)
	_trail_t += rdt
	if _fresh:
		_trail.clear()
	_trail.append([_trail_t, player.global_position])
	while _trail.size() > 2 and _trail_t - float(_trail[0][0]) > 4.0:
		_trail.pop_front()
	var h := player.global_position + Vector3.UP * 0.6
	var v := player.s.velocity
	var vh := Vector3(v.x, 0.0, v.z)
	if vh.length() > 2.0:
		_fwd = _fwd.slerp(vh.normalized(), 1.0 - exp(-1.2 * dt)).normalized()
	var f := _fwd
	var r := f.cross(Vector3.UP).normalized()
	var name: String = SHOTS[shot]["name"]
	var pos: Vector3
	var look: Vector3
	var fov: float
	if name == "golden":
		# Classic side-on chase at sunset, on the open side of the street.
		pos = h - f * 6.0 + r * _side * 3.2 + Vector3.UP * 1.0
		look = h + f * 5.0
		fov = 58.0
	else:
		var c: Array = CAM[STYLE.get(name, "chase")]
		var back := _trail_back(float(c[0]))
		pos = back + Vector3.UP * float(c[1]) + r * _side * float(c[2])
		look = h + v * float(c[3])
		fov = float(c[4])
	if _fresh:
		_off = pos - h
		_look_off = look - h
		_fov = fov
		_fresh = false
	_off = _off.lerp(pos - h, 1.0 - exp(-3.0 * dt))
	_look_off = _look_off.lerp(look - h, 1.0 - exp(-3.5 * dt))
	_fov = lerpf(_fov, fov, 1.0 - exp(-2.0 * dt))
	var cam_pos := _clear(h, h + _off)
	var dir := (h + _look_off - cam_pos).normalized()
	var lim: Array = PITCH.get(STYLE.get(name, ""), [-0.3, 0.3])
	var pitch := clampf(asin(clampf(dir.y, -1.0, 1.0)), float(lim[0]), float(lim[1]))
	var flat := Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.01 else _fwd
	dir = (flat * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), cam_pos)
	# Composition: the hero a little left of centre (clear of the menu at
	# top-right), whatever the distance and lens.
	var d := maxf((h - cam_pos).dot(-xf.basis.z), 1.0)
	var vp := player.get_viewport().get_visible_rect().size
	var width := 2.0 * d * tan(deg_to_rad(_fov) * 0.5) * (vp.x / maxf(vp.y, 1.0))
	camera.cam.h_offset = lerpf(camera.cam.h_offset, width * 0.16, 1.0 - exp(-4.0 * dt)) if not _fresh_offset else width * 0.16
	_fresh_offset = false
	return [xf, _fov]


## +1 / -1: which side of the travel has more open air (picked at each cut).
func _open_side(at: Vector3, f: Vector3) -> float:
	var r := f.cross(Vector3.UP).normalized()
	var space := player.get_world_3d().direct_space_state
	var room := {}
	for sg: float in [1.0, -1.0]:
		var q := PhysicsRayQueryParameters3D.create(at, at + r * sg * 40.0, 1 | (1 << 1))
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		room[sg] = 40.0 if hit.is_empty() else at.distance_to(hit.position)
	return 1.0 if room[1.0] >= room[-1.0] else -1.0


## Pulls the camera in front of anything between it and the hero (and up
## out of the street furniture for the low shot).
func _clear(from: Vector3, to: Vector3) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | (1 << 1))
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return to
	return from + (hit.position - from) * 0.85
