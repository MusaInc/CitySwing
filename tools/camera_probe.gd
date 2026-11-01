extends Node
## Third-person camera steadiness, measured in the running game while the
## autopilot swings (main.gd adds this for --camaudit=<seconds>):
##   jerk   – RMS change of the camera's angular velocity per frame
##            (deg/s per frame): what reads as shake or twitch
##   pops   – frames where the angular velocity jumps by > 120 deg/s
##   jitter – RMS frame-to-frame motion of the hero on screen (% of height)
##   hero   – median hero height on screen (% of screen height)
##   crowd  – % of frames where a facade within 2.5 m fills a side of the view
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
	_n += 1
	if _t > secs + 2.0:
		_sizes.sort()
		print("CAM crowd %.1f %%" % (100.0 * _crowd / maxf(_n, 1)))
		print("CAM cuts %d  jerk %.1f deg/s/frame  pops %d  jitter %.2f %%/frame  hero %.1f %% of height" % [
			_cuts, sqrt(_jerk2 / maxf(_n - 2, 1)), _pops, sqrt(_jit2 / maxf(_n - 1, 1)),
			_sizes[_sizes.size() / 2] if not _sizes.is_empty() else 0.0])
		get_tree().quit()


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
