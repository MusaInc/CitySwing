class_name SwingCamera
extends Node3D
## Stable third-person follow camera: sits behind the player, faces the
## direction of travel, lags slightly during swings – and never orbits, flips
## or swings off on its own.
##  * Yaw follows the smoothed horizontal travel heading, rate-limited
##    (max 120°/s). It holds when standing or moving mostly vertically.
##  * Heading reversals (e.g. the back-swing of a pendulum) are ignored unless
##    they persist for over a second – no 180° spins.
##  * Pitch is fixed with a gentle, rate-limited tilt for dives.
##  * Near the street it tilts up so the buildings to swing from are in view.
##  * No manual camera on touch. (Controller stick / mouse can still offset the
##    view; it eases back behind the player 0.8 s after the input stops.)
##  * Critically damped position follow, speed-based FOV, sphere-cast
##    collision that pulls in smoothly and never leaves the camera in a wall.

@export var base_fov := 70.0
@export var max_fov := 90.0
@export var fov_speed_full := 50.0
@export var follow_smooth := 0.12
@export var aim_smooth := 0.08
@export var yaw_follow_rate := 2.6        # 1/s, exponential approach to the travel heading
@export var max_yaw_speed := deg_to_rad(120.0)
@export var reversal_hold := 1.0          # s a >110° heading change must persist before following
@export var recenter_delay := 0.8
@export var base_pitch := deg_to_rad(-12.0)
@export var collision_margin := 0.35

var target: Player
var cam: Camera3D
var yaw := 0.0
var pitch := deg_to_rad(-12.0)
## Manual look offset (radians); decays back to zero after recenter_delay.
var look_yaw := 0.0
var look_pitch := 0.0
var _focus := Vector3.ZERO
var _pos := Vector3.ZERO
var _damp_vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _dist := 6.0
var _height := 1.6
var _since_look := 10.0
var _reverse_time := 0.0
var _heading := 0.0       # filtered travel heading
var _col_dist := -1.0
var _fov_kick := 0.0
var _snapped := false
## Overrides for close-up captures (--closeup).
var distance_scale := 1.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = base_fov
	cam.near = 0.15
	cam.far = 2400.0
	add_child(cam)
	cam.make_current()


func set_target(p: Player) -> void:
	target = p
	p.view = self
	snap()
	p.respawned.connect(snap)
	p.rope_snapped.connect(func(spd: float): _fov_kick = minf(_fov_kick + spd * 0.2, 3.0))


func snap() -> void:
	_snapped = true


## Point the camera along a heading (spawns).
func face(heading_yaw: float) -> void:
	yaw = heading_yaw
	_heading = heading_yaw
	look_yaw = 0.0
	look_pitch = 0.0
	pitch = base_pitch
	snap()


## Look input in radians (already sensitivity-scaled). Called by touch/mouse/stick.
func add_look(delta: Vector2) -> void:
	look_yaw = clampf(look_yaw - delta.x, -PI * 0.9, PI * 0.9)
	look_pitch = clampf(look_pitch - delta.y, deg_to_rad(-50.0), deg_to_rad(50.0))
	_since_look = 0.0


## Effective view yaw (follow yaw + manual offset).
func view_yaw() -> float:
	return yaw + look_yaw


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_look(event.relative * 0.0025 * Settings.look_sensitivity * Vector2(1, -1 if Settings.invert_y else 1))


func _process(dt: float) -> void:
	if target == null:
		return
	dt = minf(dt, 0.1)
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length() > 0.05:
		add_look(stick * dt * 2.6 * Settings.look_sensitivity)
	_since_look += dt

	var v := target.s.velocity
	var vh := Vector3(v.x, 0.0, v.z)
	var spd := v.length()
	var t := clampf(spd / fov_speed_full, 0.0, 1.0)
	var grounded := target.is_on_floor() and not target.s.attached

	# --- yaw: follow the travel heading, smoothly and without flips ----------
	if vh.length() > 3.0 and vh.length() > absf(v.y) * 0.35:
		var travel := atan2(-vh.x, -vh.z)
		var diff := wrapf(travel - _heading, -PI, PI)
		if absf(diff) > deg_to_rad(110.0):
			_reverse_time += dt  # a back-swing, or a real turnaround?
		else:
			_reverse_time = 0.0
		if absf(diff) <= deg_to_rad(110.0) or _reverse_time > reversal_hold:
			_heading = wrapf(_heading + diff * (1.0 - exp(-4.0 * dt)), -PI, PI)
	var ydiff := wrapf(_heading - yaw, -PI, PI)
	var step := ydiff * (1.0 - exp(-yaw_follow_rate * dt))
	yaw = wrapf(yaw + clampf(step, -max_yaw_speed * dt, max_yaw_speed * dt), -PI, PI)

	# --- pitch: fixed, gently tilted down in dives --------------------------
	var dive := clampf(-v.y / 35.0, 0.0, 1.0) if not grounded else 0.0
	var want_pitch := base_pitch - deg_to_rad(12.0) * dive
	if target.global_position.y < 15.0 and not target.s.attached:
		# Down at street level: look up at the facades you can swing from.
		want_pitch = deg_to_rad(6.0)
	pitch = move_toward(pitch, want_pitch, deg_to_rad(25.0) * dt)

	# Manual look eases back to centre once the player lets go.
	if _since_look > recenter_delay:
		var k := 1.0 - exp(-3.0 * dt)
		look_yaw = lerpf(look_yaw, 0.0, k)
		look_pitch = lerpf(look_pitch, 0.0, k)

	# --- distance / framing ---------------------------------------------------
	var want_dist := lerpf(5.4, 8.0, t) if not grounded else lerpf(4.8, 5.8, clampf(vh.length() / 11.0, 0.0, 1.0))
	_dist = lerpf(_dist, want_dist * distance_scale, 1.0 - exp(-2.0 * dt))
	_height = lerpf(_height, (1.4 if grounded else 1.6) * minf(distance_scale * 1.2, 1.0), 1.0 - exp(-3.0 * dt))
	var ahead := (vh * 0.12).limit_length(minf(3.5, _dist * 0.35))
	var focus_goal := target.global_position + Vector3.UP * _height + ahead
	var basis := Basis.from_euler(Vector3(clampf(pitch + look_pitch, deg_to_rad(-70.0), deg_to_rad(50.0)), yaw + look_yaw, 0.0))
	if _snapped:
		_focus = focus_goal
		_pos = focus_goal + basis.z * _dist
		_damp_vel[0] = Vector3.ZERO
		_damp_vel[1] = Vector3.ZERO
		_col_dist = -1.0
		_snapped = false
	_focus = _smooth_damp(0, _focus, focus_goal, aim_smooth, dt)
	_pos = _smooth_damp(1, _pos, _focus + basis.z * _dist, follow_smooth, dt)
	var off := _pos - _focus
	if off.length() > _dist * 1.2:
		_pos = _focus + off.normalized() * _dist * 1.2
	global_position = _avoid_walls(_focus, _pos, dt)
	look_at(_focus, Vector3.UP)

	_fov_kick = move_toward(_fov_kick, 0.0, 5.0 * dt)
	var fov_goal := lerpf(base_fov, max_fov, t * t * (3.0 - 2.0 * t)) + _fov_kick
	cam.fov = lerpf(cam.fov, fov_goal, 1.0 - exp(-3.0 * dt))


func _avoid_walls(from: Vector3, to: Vector3, dt: float) -> Vector3:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = collision_margin
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), from)
	q.motion = to - from
	q.collision_mask = 1 | (1 << 1)
	q.exclude = [target.get_rid()]
	var res := space.cast_motion(q)
	var full := (to - from).length()
	if full < 0.001:
		return to
	var allowed := full if res.is_empty() or res[0] >= 1.0 else full * maxf(res[0], 0.05)
	if _col_dist < 0.0:
		_col_dist = allowed
	# Pull in quickly (≈0.15 s) and ease back out slowly – no pops either way.
	# Only if the camera would otherwise sit inside a building does it jump.
	var dir := (to - from).normalized()
	if allowed < _col_dist:
		_col_dist = lerpf(_col_dist, allowed, 1.0 - exp(-10.0 * dt))
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = from + dir * minf(_col_dist, full)
		pq.collision_mask = 1 | (1 << 1)
		if not space.intersect_point(pq).is_empty():
			_col_dist = allowed
	else:
		_col_dist = lerpf(_col_dist, allowed, 1.0 - exp(-3.0 * dt))
	return from + dir * minf(_col_dist, full)


## Unity-style critically damped spring (Game Programming Gems 4).
func _smooth_damp(slot: int, cur: Vector3, goal: Vector3, smooth: float, dt: float) -> Vector3:
	var vel := _damp_vel[slot]
	var omega := 2.0 / maxf(smooth, 0.0001)
	var x := omega * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := cur - goal
	var temp := (vel + omega * change) * dt
	vel.x = (vel.x - omega * temp.x) * e
	vel.y = (vel.y - omega * temp.y) * e
	vel.z = (vel.z - omega * temp.z) * e
	_damp_vel[slot] = vel
	return goal + (change + temp) * e
