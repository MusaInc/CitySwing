extends Node
## Third-person camera steadiness, measured in the running game while the
## autopilot swings (main.gd adds this for --camaudit=<seconds>):
##   jerk   – RMS change of the camera's angular velocity per frame
##            (deg/s per frame): what reads as shake or twitch
##   pops   – frames where the angular velocity jumps by > 120 deg/s
##   jitter – RMS frame-to-frame motion of the hero on screen (% of height)
##   hero   – median hero height on screen (% of screen height)
##   crowd  – % of frames where a facade within 2.5 m fills a side of the view
##   block  – mean % of the view covered by geometry closer than 9 m (a 9×5
##            ray grid), and % of frames where that is over a third
##   roll   – mean / 95th-percentile horizon tilt (deg)
##   hidden – % of frames where a building is between the lens and the hero
##   place  – median hero screen position (x, y in % of the view) and the
##            90th-percentile distance from that spot (% of height): how
##            steadily the hero holds one place in the frame
##   speed  – median hero speed (km/h) and FOV, so a calmer camera can be
##            checked against the sense of speed
##   godot --fixed-fps 60 -- --mode=free --bot=expert --seed=N --nohud --camaudit=30

var cam: Camera3D
var player: Node3D
var secs := 30.0
var _t := 0.0
var _n := 0
var _prev_q := Quaternion.IDENTITY
var _prev_w := Vector3.ZERO
var _prev_s := Vector2.ZERO
var _jerk2 := 0.0
var _jit2 := 0.0
var _pops := 0
var _cuts := 0
var _sizes: Array[float] = []
var _crowd := 0
var _block_sum := 0.0
var _block_big := 0
var _rolls: Array[float] = []
var _hidden := 0
var _px: Array[float] = []
var _py: Array[float] = []
var _speeds: Array[float] = []
var _fovs: Array[float] = []


func _process(dt: float) -> void:
	_t += dt
	if _t < 2.0:
		return  # let the spawn settle
	var q := cam.global_transform.basis.get_rotation_quaternion()
	if _n > 0:
		var dq := _prev_q.inverse() * q
		var wv := dq.get_axis() * dq.get_angle() / dt if dq.get_angle() > 1e-6 else Vector3.ZERO
		if _n > 1:
			var dw := rad_to_deg((wv - _prev_w).length())
			if dw > 1500.0:
				_cuts += 1  # a deliberate cut (respawn, snap): not shake
			else:
				_jerk2 += dw * dw
				if dw > 120.0:
					_pops += 1
		_prev_w = wv
	_prev_q = q
	var h := cam.get_viewport().get_visible_rect().size.y
	if not cam.is_position_behind(player.global_position):
		var a := cam.unproject_position(player.global_position + Vector3.UP * 0.9)
		var b := cam.unproject_position(player.global_position - Vector3.UP * 0.9)
		_sizes.append((a - b).length() / h * 100.0)
		var sp := cam.unproject_position(player.global_position)
		if _n > 0:
			_jit2 += ((sp - _prev_s) / h * 100.0).length_squared()
		_prev_s = sp
	if _crowded():
		_crowd += 1
	var bl := _blocked()
	_block_sum += bl
	if bl > 0.334:
		_block_big += 1
	var right := cam.global_transform.basis.x
	_rolls.append(absf(rad_to_deg(asin(clampf(right.y, -1.0, 1.0)))))
	if _hero_hidden():
		_hidden += 1
	if not cam.is_position_behind(player.global_position):
		var vs := cam.get_viewport().get_visible_rect().size
		var hp := cam.unproject_position(player.global_position + Vector3.UP * 0.3)
		_px.append(hp.x / vs.x * 100.0)
		_py.append(hp.y / vs.y * 100.0)
	var pv = player.get("s")
	if pv != null:
		_speeds.append((pv.velocity as Vector3).length() * 3.6)
	_fovs.append(cam.fov)
	_n += 1
	if _t > secs + 2.0:
		_sizes.sort()
		print("CAM crowd %.1f %%" % (100.0 * _crowd / maxf(_n, 1)))
		print("CAM cuts %d  jerk %.1f deg/s/frame  pops %d  jitter %.2f %%/frame  hero %.1f %% of height" % [
			_cuts, sqrt(_jerk2 / maxf(_n - 2, 1)), _pops, sqrt(_jit2 / maxf(_n - 1, 1)),
			_sizes[_sizes.size() / 2] if not _sizes.is_empty() else 0.0])
		var n := maxf(_n, 1)
		_rolls.sort()
		print("CAM block %.1f %% of view, %.1f %% of frames over a third" % [100.0 * _block_sum / n, 100.0 * _block_big / n])
		print("CAM roll mean %.2f deg  p95 %.2f deg" % [_mean(_rolls), _pct(_rolls, 0.95)])
		print("CAM hidden %.1f %%" % (100.0 * _hidden / n))
		var mx := _pct(_px.duplicate(), 0.5)
		var my := _pct(_py.duplicate(), 0.5)
		var spread: Array[float] = []
		var vs := cam.get_viewport().get_visible_rect().size
		for i in _px.size():
			spread.append(Vector2((_px[i] - mx) * vs.x / vs.y, _py[i] - my).length())
		print("CAM place x %.1f y %.1f  p90 spread %.1f %%" % [mx, my, _pct(spread, 0.9)])
		print("CAM speed median %.0f km/h  p90 %.0f  fov median %.1f" % [_pct(_speeds.duplicate(), 0.5), _pct(_speeds.duplicate(), 0.9), _pct(_fovs.duplicate(), 0.5)])
		get_tree().quit()


func _pct(a: Array[float], q: float) -> float:
	if a.is_empty():
		return 0.0
	a.sort()
	return a[clampi(int(q * (a.size() - 1)), 0, a.size() - 1)]


func _mean(a: Array[float]) -> float:
	var t := 0.0
	for x in a:
		t += x
	return t / maxf(a.size(), 1)


## Share of a 9×5 grid of view rays that hit geometry within 9 m: how much of
## the screen is a facade right in front of the lens.
func _blocked() -> float:
	var space := cam.get_world_3d().direct_space_state
	var vs := cam.get_viewport().get_visible_rect().size
	var o := cam.global_position
	var hits := 0
	for gx in 9:
		for gy in 5:
			var sp := Vector2((gx + 0.5) / 9.0 * vs.x, (gy + 0.5) / 5.0 * vs.y)
			var d := cam.project_ray_normal(sp)
			var q := PhysicsRayQueryParameters3D.create(o, o + d * 9.0, 1 | (1 << 1))
			q.exclude = [player.get_rid()]
			var h := space.intersect_ray(q)
			# Walls only: the street under a running hero isn't "in the way".
			if not h.is_empty() and absf((h["normal"] as Vector3).y) < 0.7:
				hits += 1
	return hits / 45.0


func _hero_hidden() -> bool:
	var space := cam.get_world_3d().direct_space_state
	var to := player.global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, to, 1 | (1 << 1))
	q.exclude = [player.get_rid()]
	return not space.intersect_ray(q).is_empty()


## A wall right beside the lens fills half the frame: rays along the left and
## right thirds of the view hit something within 2.5 m.
func _crowded() -> bool:
	var space := cam.get_world_3d().direct_space_state
	var b := cam.global_transform.basis
	var o := cam.global_position
	for side: float in [-1.0, 1.0]:
		var d := (-b.z + b.x * side * 0.55).normalized()
		var q := PhysicsRayQueryParameters3D.create(o, o + d * 2.5, 1 | (1 << 1))
		if not space.intersect_ray(q).is_empty():
			return true
	return false
