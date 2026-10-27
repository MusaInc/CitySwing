class_name SwingCamera
extends Node3D
## Third-person action camera.
##  * Critically damped trailing; distance, height and pitch blend between
##    standing / airborne / swinging states (no snapping).
##  * Velocity look-ahead capped by distance so the hero never leaves frame.
##  * Speed-driven FOV, small FOV kick on rope snaps, gentle roll into turns.
##  * While swinging, pitches so the anchor stays on screen even when it is
##    almost straight overhead.
##  * Auto-recentres behind the direction of travel after manual look input.
##  * Sphere-cast collision: pulls in quickly, eases back out slowly.
## No random shake anywhere.

@export var base_fov := 70.0
@export var max_fov := 94.0
@export var fov_speed_full := 50.0
@export var look_ahead_time := 0.22
@export var look_ahead_max := 7.0
@export var follow_smooth := 0.10
@export var aim_smooth := 0.08
@export var recenter_delay := 1.6
@export var recenter_rate := 1.6
@export var collision_margin := 0.35

var target: Player
var cam: Camera3D
var yaw := 0.0
var pitch := deg_to_rad(-10.0)
var _focus := Vector3.ZERO
var _pos := Vector3.ZERO
var _damp_vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _dist := 6.0
var _height := 1.5
var _since_look := 10.0
var _roll := 0.0
var _fov_kick := 0.0
var _anchor_bias := Vector3.ZERO
var _col_dist := -1.0
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
	p.rope_snapped.connect(func(spd: float): _fov_kick = minf(_fov_kick + spd * 0.25, 4.0))


func snap() -> void:
	_snapped = true


## Point the camera along a heading (spawns).
func face(heading_yaw: float) -> void:
	yaw = heading_yaw
	pitch = deg_to_rad(-8.0)
	_since_look = 0.0
	snap()


## Look input in radians (already sensitivity-scaled). Called by touch/mouse/stick.
func add_look(delta: Vector2) -> void:
	yaw -= delta.x
	pitch = clampf(pitch - delta.y, deg_to_rad(-70.0), deg_to_rad(60.0))
	_since_look = 0.0


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
	var swinging := target.line_state == Player.Line.ATTACHED
	var grounded := target.is_on_floor() and not swinging

	# Auto-recentre yaw behind the travel direction once the player stops
	# steering the view; faster travel recentres faster.
	if _since_look > recenter_delay and vh.length() > 3.0:
		var want := atan2(-vh.x, -vh.z)
		var w := recenter_rate * clampf(vh.length() / 25.0, 0.2, 1.0) * clampf(_since_look - recenter_delay, 0.0, 1.0)
		yaw = lerp_angle(yaw, want, 1.0 - exp(-w * dt))
		var dive := clampf(-v.y / 30.0, -0.5, 1.0)
		var want_pitch := deg_to_rad(-9.0 - 14.0 * dive)
		if swinging:
			want_pitch = _anchor_pitch(deg_to_rad(-2.0 - 6.0 * dive))
		pitch = lerp_angle(pitch, want_pitch, 1.0 - exp(-0.9 * dt))
	elif swinging and _since_look > 0.4:
		# Even while looking around, don't let the anchor slide off the top.
		pitch = lerp_angle(pitch, maxf(pitch, _anchor_pitch(pitch)), 1.0 - exp(-1.5 * dt))

	# State framing: closer and lower when standing, pulled out with speed.
	var want_dist := lerpf(5.2, 8.6, t) if not grounded else lerpf(4.6, 6.0, clampf(vh.length() / 11.0, 0.0, 1.0))
	var want_height := 1.35 if grounded else 1.6
	_dist = lerpf(_dist, want_dist * distance_scale, 1.0 - exp(-2.2 * dt))
	_height = lerpf(_height, want_height * minf(distance_scale * 1.2, 1.0), 1.0 - exp(-3.0 * dt))

	var ahead := (v * look_ahead_time).limit_length(minf(look_ahead_max, _dist * 0.45))
	ahead.y *= 0.4
	var focus_goal := target.global_position + Vector3.UP * _height + ahead
	if swinging:
		_anchor_bias = _anchor_bias.lerp((target.s.anchor - target.global_position).normalized() * 1.6, 1.0 - exp(-3.0 * dt))
	else:
		_anchor_bias = _anchor_bias.lerp(Vector3.ZERO, 1.0 - exp(-2.0 * dt))
	focus_goal += _anchor_bias
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	if _snapped:
		_focus = focus_goal
		_pos = focus_goal + basis.z * _dist
		_damp_vel[0] = Vector3.ZERO
		_damp_vel[1] = Vector3.ZERO
		_col_dist = -1.0
		_snapped = false
	_focus = _smooth_damp(0, _focus, focus_goal, aim_smooth, dt)
	var pos_goal := _focus + basis.z * _dist
	_pos = _smooth_damp(1, _pos, pos_goal, follow_smooth, dt)
	var off := _pos - _focus
	if off.length() > _dist * 1.25:
		_pos = _focus + off.normalized() * _dist * 1.25

	global_position = _avoid_walls(_focus, _pos, dt)
	look_at(_focus, Vector3.UP)

	# Gentle roll into turns, capped at 4°, never shaky.
	var lateral := 0.0
	if vh.length() > 4.0:
		lateral = basis.x.dot(target.controls.move) * clampf(vh.length() / 30.0, 0.0, 1.0)
	_roll = lerpf(_roll, -lateral * deg_to_rad(4.0), 1.0 - exp(-3.0 * dt))
	rotate_object_local(Vector3.BACK, _roll)

	_fov_kick = move_toward(_fov_kick, 0.0, 6.0 * dt)
	var fov_goal := lerpf(base_fov, max_fov, t * t * (3.0 - 2.0 * t)) + _fov_kick
	cam.fov = lerpf(cam.fov, fov_goal, 1.0 - exp(-4.0 * dt))


## Pitch that keeps the anchor inside the upper part of the view.
func _anchor_pitch(default_pitch: float) -> float:
	var to_anchor := target.s.anchor - global_position
	var elev := atan2(to_anchor.y, Vector2(to_anchor.x, to_anchor.z).length())
	var half_fov := deg_to_rad(cam.fov * 0.5) * 0.78
	return maxf(default_pitch, elev - half_fov)


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
	# Pull in immediately (never clip), ease back out (no popping).
	_col_dist = allowed if allowed < _col_dist else lerpf(_col_dist, allowed, 1.0 - exp(-3.0 * dt))
	return from + (to - from).normalized() * minf(_col_dist, full)


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
