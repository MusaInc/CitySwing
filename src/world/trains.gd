class_name Trains
extends Node3D
## Moving trains on RailNetwork lines. Each car is an AnimatableBody3D moved
## along the line's samples every physics tick (bogie points on the track, so
## cars swing round curves and pitch on grades); players can land on a train
## and ride it (CharacterBody3D platform velocity). Timetable: accelerate,
## cruise, brake into each station, dwell, go – a pure function of the clock,
## so it never drifts. Loop Line: one train each way; Valley Line: a shuttle.
##
## Collision is on TRAIN_LAYER, which only human players collide with (bots
## and recorded courses are unaffected by where the trains happen to be).

const TRAIN_LAYER := CityWorld.HUMAN_LAYER
const CAR_LEN := 17.6
const CAR_PITCH := 18.0          # car + gap
const BOGIE := 6.2               # bogie centres from the car's centre
const V_MAX := 19.0              # m/s cruise (~68 km/h)
const ACCEL := 0.85              # m/s² (and braking)
const DWELL := 14.0              # s at each station

var _trains: Array = []          # {line, dir, offset, t, legs, cycle, cars: [AnimatableBody3D], audio}
var _car_mesh: Mesh
var _cab_mesh: Mesh
var _window_mat: BaseMaterial3D
var _lamp_mat: BaseMaterial3D
var _clock := 0.0


func setup(lines: Array, car_mesh: Mesh, cab_mesh: Mesh) -> void:
	if car_mesh == null or cab_mesh == null:
		return
	_car_mesh = car_mesh.duplicate()
	_cab_mesh = cab_mesh.duplicate()
	# Shared window/lamp materials across both meshes (lit at night).
	for m: Mesh in [_car_mesh, _cab_mesh]:
		for i in m.get_surface_count():
			var sm := m.surface_get_material(i) as BaseMaterial3D
			if sm == null:
				continue
			if sm.resource_name == "train_window":
				if _window_mat == null:
					_window_mat = sm.duplicate()
				m.surface_set_material(i, _window_mat)
			elif sm.resource_name == "lamp":
				if _lamp_mat == null:
					_lamp_mat = sm.duplicate()
				m.surface_set_material(i, _lamp_mat)
	set_night(0.0)
	var stream: AudioStream = load("res://assets/audio/train_loop.wav") if ResourceLoader.exists(
		"res://assets/audio/train_loop.wav") else null
	if stream is AudioStreamWAV:
		var w := stream as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = int(w.get_length() * w.mix_rate)
	for line in lines:
		if line["loop"]:
			_add_train(line, 1, line["tracks"][0], 0.0, stream)
			_add_train(line, -1, -float(line["tracks"][0]), 0.5, stream)
		else:
			_add_train(line, 1, line["tracks"][0], 0.0, stream)
			if (line["tracks"] as Array).size() > 1:
				_add_train(line, 1, line["tracks"][1], 0.5, stream)  # the other track, half a cycle on
	_place_all()


## Lamps on (0 = day, 1 = night): lit saloon windows and bright headlights.
func set_night(n: float) -> void:
	if _window_mat:
		_window_mat.emission_energy_multiplier = lerpf(0.0, 1.6, n)
	if _lamp_mat:
		_lamp_mat.emission_energy_multiplier = lerpf(0.6, 5.0, n)


func _add_train(line: Dictionary, dir: int, offset: float, phase: float, stream: AudioStream) -> void:
	var pts: PackedVector3Array = line["pts"]
	var total := (pts.size() if line["loop"] else pts.size() - 1) * RailNetwork.STEP
	var st: Array = line["stations"].duplicate()
	st.sort()
	# Legs in travel order: [from s, signed distance, duration].
	var legs: Array = []
	if line["loop"]:
		var n := st.size()
		for i in n:
			if dir > 0:
				var a: float = st[i]
				var b: float = st[(i + 1) % n]
				legs.append([a, fposmod(b - a, total)])
			else:
				var a: float = st[(n - i) % n]
				var b: float = st[(n - i - 1 + n) % n]
				legs.append([a, -fposmod(a - b, total)])
	else:
		# End to end through every station, then back.
		for i in st.size() - 1:
			legs.append([st[i], float(st[i + 1]) - float(st[i])])
		for i in range(st.size() - 1, 0, -1):
			legs.append([st[i], float(st[i - 1]) - float(st[i])])
	var cycle := 0.0
	for leg in legs:
		leg.append(_leg_time(absf(leg[1])))
		cycle += float(leg[2]) + DWELL
	var tr := {"line": line, "dir": dir, "offset": offset, "legs": legs, "cycle": cycle, "phase": phase * cycle,
		"total": total, "cars": [], "s": 0.0, "v": 0.0}
	var n_cars: int = line["cars"]
	for k in n_cars:
		var body := AnimatableBody3D.new()
		body.name = "%s_%d_car%d" % [line["name"], _trains.size(), k]
		body.sync_to_physics = false  # (moved in _physics_process already)
		body.collision_layer = TRAIN_LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.9, 2.95, CAR_LEN - 0.2)
		cs.shape = box
		cs.position = Vector3(0.0, 2.45, 0.0)
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var cab := k == 0 or k == n_cars - 1
		mi.mesh = _cab_mesh if cab else _car_mesh
		if k == n_cars - 1:
			mi.rotation.y = PI  # the rear cab faces backwards
		mi.visibility_range_end = 1100.0
		body.add_child(mi)
		add_child(body)
		tr["cars"].append(body)
	if stream:
		var au := AudioStreamPlayer3D.new()
		au.stream = stream
		au.bus = "SFX"
		au.unit_size = 22.0
		au.max_distance = 320.0
		au.volume_db = -80.0
		tr["cars"][n_cars / 2].add_child(au)
		au.play()
		tr["audio"] = au
	_trains.append(tr)


## Time to cover d metres from rest to rest (trapezoid speed profile).
static func _leg_time(d: float) -> float:
	var d_ramp := V_MAX * V_MAX / ACCEL  # accelerate + brake distance
	if d >= d_ramp:
		return d / V_MAX + V_MAX / ACCEL
	return 2.0 * sqrt(d / ACCEL)


## Distance covered after time t of a leg of length d (and the speed then).
static func _leg_pos(d: float, T: float, t: float) -> Vector2:
	var vp := minf(V_MAX, sqrt(ACCEL * d))
	var ta := vp / ACCEL
	if t <= ta:
		return Vector2(0.5 * ACCEL * t * t, ACCEL * t)
	if t >= T - ta:
		var r := maxf(T - t, 0.0)
		return Vector2(d - 0.5 * ACCEL * r * r, ACCEL * r)
	return Vector2(0.5 * ACCEL * ta * ta + vp * (t - ta), vp)


func _physics_process(dt: float) -> void:
	_clock += dt
	_place_all()


func _place_all() -> void:
	for tr in _trains:
		var t := fposmod(_clock + float(tr["phase"]), float(tr["cycle"]))
		var s := 0.0
		var v := 0.0
		for leg in tr["legs"]:
			var T: float = leg[2]
			if t < DWELL:
				s = leg[0]
				break
			t -= DWELL
			if t < T:
				var sv := _leg_pos(absf(leg[1]), T, t)
				s = float(leg[0]) + sv.x * signf(leg[1])
				v = sv.y
				break
			t -= T
		tr["s"] = s
		tr["v"] = v
		_place(tr, s)
		var au: AudioStreamPlayer3D = tr.get("audio")
		if au:
			var k := clampf(v / V_MAX, 0.0, 1.0)
			au.volume_db = linear_to_db(maxf(0.12 + 0.88 * k, 0.001)) - 2.0
			au.pitch_scale = 0.7 + 0.4 * k


## Cars laid out round the train's middle at s (cabs at both ends, so a
## shuttle reversing needs no shuffle).
func _place(tr: Dictionary, s: float) -> void:
	var line: Dictionary = tr["line"]
	var pts: PackedVector3Array = line["pts"]
	var loop: bool = line["loop"]
	var cars: Array = tr["cars"]
	var n := cars.size()
	var off: float = tr["offset"]
	var fwd: int = tr["dir"]
	for k in n:
		var sc := s + fwd * ((n - 1) * 0.5 - k) * CAR_PITCH
		var pf := _track_point(pts, loop, sc + fwd * BOGIE, off)
		var pr := _track_point(pts, loop, sc - fwd * BOGIE, off)
		var f := pf - pr
		if f.length_squared() < 1e-6:
			continue
		var xf := Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), (pf + pr) * 0.5)
		(cars[k] as AnimatableBody3D).global_transform = xf


static func _track_point(pts: PackedVector3Array, loop: bool, s: float, off: float) -> Vector3:
	var n := pts.size()
	var f := s / RailNetwork.STEP
	if loop:
		f = fposmod(f, float(n))
	else:
		f = clampf(f, 0.0, float(n - 1) - 0.001)
	var i := int(f)
	var j := (i + 1) % n
	var p := pts[i].lerp(pts[j], f - i)
	var d := pts[j] - pts[i]
	var left := Vector3(-d.z, 0.0, d.x).normalized()
	# (Blend the side vector over the next sample too, so it doesn't step.)
	var k2 := (j + 1) % n if loop else mini(j + 1, n - 1)
	var d2 := pts[k2] - pts[j]
	if d2.length_squared() > 1e-6:
		left = left.lerp(Vector3(-d2.z, 0.0, d2.x).normalized(), f - i).normalized()
	return p + left * off
