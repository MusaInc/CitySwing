class_name CinematicDirector
extends Node
## Title-screen cinematography: cycles five composed shots of the real game
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
## Each shot sets its own time of day, starts the hero on a chosen avenue leg
## and hands SwingCamera a transform each frame (camera.cine). The subject is
## kept left of centre, clear of the menu's top-right controls. Cuts dip
## through Night Ink (main's curtain). Leaving the title restores the clock,
## weather and time scale.

const SHOT_LEN := 7.5
const SHOTS := [
	{"name": "golden", "hour": 18.35, "leg": 0, "frac": 0.12, "h": 52.0, "speed": 22.0, "slow": 1.0},
	{"name": "canyon", "hour": 15.2, "leg": 2, "frac": 0.08, "h": 60.0, "speed": 18.0, "slow": 0.55},
	{"name": "skyline", "hour": 16.6, "leg": 1, "frac": 0.1, "h": 70.0, "speed": 22.0, "slow": 1.0},
	{"name": "momentum", "hour": 17.4, "leg": 0, "frac": 0.45, "h": 50.0, "speed": 24.0, "slow": 0.7},
	{"name": "rooftops", "hour": 10.4, "leg": -1, "frac": 0.12, "h": 44.0, "speed": 20.0, "slow": 1.0},
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
	var leg: int = s["leg"]
	if leg < 0:
		leg = _westmost_leg()
	var e := pilot.entry_on(leg, s["frac"], s["h"], s["speed"])
	player.respawn(e[0])
	player.s.velocity = e[1]
	_fwd = Vector3(e[1].x, 0.0, e[1].z).normalized()
	_side = _open_side(e[0], _fwd)
	_fresh_offset = true
	_fresh = true
	camera.snap()
	_cutting = false


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
		var k := smoothstep(1.6, 2.6, shot_t) * (1.0 - smoothstep(4.6, 5.6, shot_t))
		Engine.time_scale = lerpf(1.0, slow, k)
	else:
		Engine.time_scale = 1.0
	var bad := pilot.needs_cut(player, dt)
	if not _cutting and (shot_t > SHOT_LEN or (bad and shot_t > 1.5)):
		_cutting = true
		Engine.time_scale = 1.0
		if dip.is_valid():
			dip.call(cut_to.bind(shot + 1), 0.35, 0.5)
		else:
			cut_to(shot + 1)


## For SwingCamera.cine: [Transform3D, fov]. The camera's offset from the
## hero is what's smoothed (not its absolute position), so at 25 m/s it
## doesn't fall metres behind; the side is chosen at each cut (the open side
## of the street) and never flips mid-shot.
func camera_xf(dt: float) -> Array:
	var h := player.global_position + Vector3.UP * 0.6
	var v := player.s.velocity
	var vh := Vector3(v.x, 0.0, v.z)
	if vh.length() > 2.0:
		_fwd = _fwd.slerp(vh.normalized(), 1.0 - exp(-1.2 * dt)).normalized()
	var f := _fwd
	var r := f.cross(Vector3.UP).normalized()
	var sd := r * _side
	var up := Vector3.UP
	var off: Vector3
	var look: Vector3
	var fov := 60.0
	match SHOTS[shot]["name"]:
		"golden":
			off = -f * 6.0 + sd * 3.2 + up * 1.0
			look = f * 5.0
			fov = 58.0
		"canyon":
			# Below and ahead, looking up past the hero at the towers closing
			# in overhead.
			off = f * 5.5 + sd * 2.2 - up * 3.8
			look = f * 1.0 + up * 1.5
			fov = 70.0
		"skyline":
			off = -f * 46.0 + sd * 26.0 + up * 16.0
			look = f * 8.0
			fov = 17.0
		"momentum":
			off = -f * 3.4 + sd * 2.1 + up * 0.7
			look = f * 2.0 + up * 0.2
			fov = 50.0
		_:
			off = -f * 7.5 + sd * 3.5 + up * 3.2
			look = f * 30.0 - up * 3.0
			fov = 62.0
	if _fresh:
		_off = off
		_look_off = look
		_fov = fov
		_fresh = false
	_off = _off.lerp(off, 1.0 - exp(-2.5 * dt))
	_look_off = _look_off.lerp(look, 1.0 - exp(-4.0 * dt))
	_fov = lerpf(_fov, fov, 1.0 - exp(-2.0 * dt))
	var pos := _clear(h, h + _off)
	var xf := Transform3D(Basis.looking_at((h + _look_off - pos).normalized(), Vector3.UP), pos)
	# Composition: shift the lens so the hero sits ~22% of the frame left of
	# centre (clear of the menu at top-right), whatever the distance and lens.
	var d := maxf((h - pos).dot(-xf.basis.z), 1.0)
	var vp := player.get_viewport().get_visible_rect().size
	var width := 2.0 * d * tan(deg_to_rad(_fov) * 0.5) * (vp.x / maxf(vp.y, 1.0))
	camera.cam.h_offset = lerpf(camera.cam.h_offset, width * 0.22, 1.0 - exp(-4.0 * dt)) if not _fresh_offset else width * 0.22
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
