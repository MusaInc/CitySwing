class_name HomeSystem
extends Node
## Living in the homes (Apartments): wake up inside, leave through the
## window, come back through it.
##
##  * Spawn: inside the selected home, facing the open window (the camera
##    behind, looking out over the city).
##  * Leaving: it's a real opening – run out of it (the off-ledge dive takes
##    over) or JUMP near it for an extra push out into the air.
##  * Returning: approaching an owned home's window from outside, airborne,
##    moving toward the facade, inside a funnel round the opening (a couple of
##    metres out, from below the sill to just above it) and slower than
##    GRAB_MAX:
##      - fast and square on (≥ VAULT_MIN, mostly toward the wall, at sill
##        height): a vault straight through into the room;
##      - otherwise: catch the sill, hang a beat, pull up and climb in.
##    JUMP while hanging lets go and drops away. Faster than GRAB_MAX you
##    just hit (or miss) the building as usual – no magnet, no teleport.
## The moves are short scripted paths (the Player's physics pauses, the rig
## plays hang/climb/vault poses) ending with the hero on the floor inside.

signal entered_home(id: String)

const GRAB_MAX := 24.0
const VAULT_MIN := 9.0
const GRAB_T := 0.16
const HANG_T := 0.24
const CLIMB_T := 0.62
const VAULT_T := 0.4

var player: Player
var rig: CharacterRig
var camera: SwingCamera
var layout: CityLayout
var homes: Array = []
var owned := func(_id: String) -> bool: return true
var state := ""          # "", "grab", "hang", "climb", "vault"; read by tests / HUD
var home: Dictionary = {}
var _t := 0.0
var _from := Vector3.ZERO
var _hang := Vector3.ZERO
var _top := Vector3.ZERO
var _in := Vector3.ZERO
var _cool := 0.0
var _jump_was := false


func setup(p_player: Player, p_rig: CharacterRig, p_layout: CityLayout) -> void:
	player = p_player
	rig = p_rig
	layout = p_layout
	homes = layout.apartments.homes if layout and layout.apartments else []


func home_by_id(id: String) -> Dictionary:
	for h in homes:
		if h["id"] == id:
			return h
	return {}


## Puts the hero in the home, on the floor, facing the window.
func spawn_in(h: Dictionary, world: Node, camera: SwingCamera) -> void:
	var p := Apartments.spawn_point(h)
	if world.has_method("build_all_near"):
		# The view must be there when you look out: the higher the floor, the
		# further you see (the penthouse sees most of the city).
		world.build_all_near(p, 420.0 + Apartments.floor_height(h) * 2.2)
	player.respawn(p)
	player.last_safe_position = p
	var n := Apartments.outward(h)
	rig.set_facing(n)
	if camera:
		camera.face(atan2(-n.x, -n.z))
		camera.look_down = _tilt(h)
		camera.pitch = camera.base_pitch - camera.look_down
	_cool = 0.8


## Indoor look-down: the higher the floor, the further below the city.
func _tilt(h: Dictionary) -> float:
	return deg_to_rad(clampf(4.0 + (Apartments.floor_height(h) - 20.0) / 300.0 * 16.0, 4.0, 20.0))


## Which home the hero is standing in (id) or "".
func inside() -> String:
	var p := player.global_position
	for h in homes:
		var f := Apartments.to_face(h, p)
		if f.x > float(h["a0"]) and f.x < float(h["a1"]) and f.y < 0.0 and f.y > -float(h["depth"]) \
				and f.z > float(h["y0"]) - 0.2 and f.z < float(h["y1"]):
			return h["id"]
	return ""


func _physics_process(dt: float) -> void:
	if player == null:
		return
	_cool = maxf(_cool - dt, 0.0)
	if camera:
		# Indoors at a home: tilt the view down so the city fills the window.
		var id := inside() if state == "" else ""
		camera.look_down = _tilt(home_by_id(id)) if id != "" else 0.0
	if state != "":
		_run(dt)
		return
	if _cool > 0.0 or player.stunned or player.knocked_out or player.bot != null:
		return
	if player.is_on_floor():
		_leap_assist()
		return
	for h in homes:
		if owned.call(h["id"]) and _try_enter(h):
			return


## JUMP near the window from inside: an extra push out into the open air.
func _leap_assist() -> void:
	var jumping := player.controls.jump
	if jumping and not _jump_was:
		var id := inside()
		if id != "":
			var h := home_by_id(id)
			var f := Apartments.to_face(h, player.global_position)
			if f.y > -2.6:
				player.boost(Apartments.outward(h) * 5.0 + Vector3.UP * 1.0)
	_jump_was = jumping


func _try_enter(h: Dictionary) -> bool:
	var wc := Apartments.window_center(h)
	var p := player.global_position
	if p.distance_squared_to(wc) > 49.0:
		return false
	var feet := p + Vector3.DOWN * 0.9
	var f := Apartments.to_face(h, feet)
	var oa0: float = h["oa0"]
	var oa1: float = h["oa1"]
	var oy0: float = h["oy0"]
	var dy := f.z - oy0
	if f.y < -0.3 or f.y > 2.4 or f.x < oa0 - 0.4 or f.x > oa1 + 0.4 or dy < -2.0 or dy > 1.2:
		return false
	var v := player.s.velocity
	var n := Apartments.outward(h)
	var toward := -v.dot(n)
	var spd := v.length()
	if spd >= GRAB_MAX:
		return false  # far too fast: you meet the building the normal way
	if toward < 0.5 and not (spd < 4.0 and f.y < 1.2):
		return false
	home = h
	var a := clampf(f.x, oa0 + 0.5, oa1 - 0.5)
	_in = Apartments.face_point(h, a, -1.1, float(h["y0"])) + Vector3.UP * 0.95
	_from = p
	player.release_web()
	player.scripted = true
	rig.set_facing(-n)
	_t = 0.0
	if spd >= VAULT_MIN and toward > 0.6 * spd and dy > -0.7:
		state = "vault"
		_top = Apartments.face_point(h, a, 0.2, oy0) + Vector3.UP * 1.25
	else:
		state = "grab"
		_hang = Apartments.face_point(h, a, 0.42, oy0) + Vector3.DOWN * 1.05
		_top = Apartments.face_point(h, a, 0.25, oy0) + Vector3.UP * 0.92
	rig.ledge_mode = state
	rig.ledge_u = 0.0
	return true


func _run(dt: float) -> void:
	_t += dt
	var prev := player.global_position
	var pos := prev
	match state:
		"grab":
			var u := smoothstep(0.0, 1.0, _t / GRAB_T)
			pos = _from.lerp(_hang, u)
			if _t >= GRAB_T:
				_next("hang")
		"hang":
			pos = _hang
			if player.controls.jump:
				_drop()
				return
			if _t >= HANG_T:
				_next("climb")
		"climb":
			var u := clampf(_t / CLIMB_T, 0.0, 1.0)
			if u < 0.58:
				var k := smoothstep(0.0, 1.0, u / 0.58)
				pos = _hang.lerp(_top, k)
			else:
				var k := smoothstep(0.0, 1.0, (u - 0.58) / 0.42)
				pos = _top.lerp(_in, k)
			if u >= 1.0:
				_finish(1.5)
				return
		"vault":
			var u := clampf(_t / VAULT_T, 0.0, 1.0)
			# Quadratic arc from where the swing left off, over the sill, in.
			var a := _from.lerp(_top, u)
			var b := _top.lerp(_in, u)
			pos = a.lerp(b, u)
			if u >= 1.0:
				_finish(4.0)
				return
	rig.ledge_mode = state
	rig.ledge_u = _progress()
	player.global_position = pos
	player.s.position = pos
	player.s.velocity = (pos - prev) / maxf(dt, 1e-4)


func _progress() -> float:
	match state:
		"grab":
			return clampf(_t / GRAB_T, 0.0, 1.0)
		"hang":
			return clampf(_t / HANG_T, 0.0, 1.0)
		"climb":
			return clampf(_t / CLIMB_T, 0.0, 1.0)
		"vault":
			return clampf(_t / VAULT_T, 0.0, 1.0)
	return 0.0


func _next(s: String) -> void:
	state = s
	_t = 0.0


func _drop() -> void:
	var n := Apartments.outward(home)
	state = ""
	rig.ledge_mode = ""
	player.scripted = false
	player.s.velocity = n * 3.0 + Vector3.DOWN * 1.0
	_cool = 1.0


func _finish(carry: float) -> void:
	var n := Apartments.outward(home)
	state = ""
	rig.ledge_mode = ""
	player.global_position = _in
	player.s.position = _in
	player.s.velocity = -n * carry
	player.scripted = false
	player.last_safe_position = _in
	_cool = 0.8
	entered_home.emit(home["id"])
