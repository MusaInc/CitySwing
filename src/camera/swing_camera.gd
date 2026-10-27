class_name SwingCamera
extends Node3D
## Third-person action camera: critically damped trailing, velocity look-ahead,
## speed-driven FOV and distance, auto-recentering behind the direction of
## travel, sphere-cast collision avoidance. Deliberately no random shake – all
## motion feedback is smooth (FOV breathing, small roll into turns).

@export var target_path: NodePath
@export var base_fov := 68.0
@export var max_fov := 92.0
@export var fov_speed_full := 50.0
@export var near_distance := 5.2
@export var far_distance := 8.5
@export var height := 1.5
@export var look_ahead_time := 0.22
@export var look_ahead_max := 7.0
@export var follow_smooth := 0.10   # seconds (smaller = tighter)
@export var aim_smooth := 0.07
@export var recenter_delay := 0.9
@export var recenter_rate := 1.6     # rad/s at full speed
@export var default_pitch := -12.0
@export var collision_margin := 0.35

var target: Player
var cam: Camera3D
var yaw := 0.0
var pitch := deg_to_rad(-12.0)
var _focus := Vector3.ZERO
var _pos := Vector3.ZERO
var _damp_vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]  # focus, position
var _dist := 6.0
var _since_look := 10.0
var _roll := 0.0
var _fov_kick := 0.0
var _snapped := false


func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = base_fov
	cam.near = 0.15
	cam.far = 2400.0
	add_child(cam)
	cam.make_current()
	if target_path:
		set_target(get_node(target_path))


func set_target(p: Player) -> void:
	target = p
	p.view = self
	yaw = p.global_rotation.y
	snap()
	p.respawned.connect(snap)
	p.rope_snapped.connect(func(spd: float): _fov_kick = minf(_fov_kick + spd * 0.25, 4.0))


func snap() -> void:
	_snapped = true


## Look input in radians (already sensitivity-scaled). Called by touch/mouse/stick.
func add_look(delta: Vector2) -> void:
	yaw -= delta.x
	pitch = clampf(pitch - delta.y, deg_to_rad(-70.0), deg_to_rad(55.0))
	_since_look = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_look(event.relative * 0.0025 * Settings.look_sensitivity * Vector2(1, -1 if Settings.invert_y else 1))


func _process(dt: float) -> void:
	if target == null:
		return
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length() > 0.05:
		add_look(stick * dt * 2.6 * Settings.look_sensitivity)
	_since_look += dt

	var v := target.s.velocity
	var vh := Vector3(v.x, 0.0, v.z)
	var spd := v.length()
	var t := clampf(spd / fov_speed_full, 0.0, 1.0)

	# Auto-recenter yaw behind the horizontal travel direction once the player
	# stops steering the view; faster travel recenters faster.
	if _since_look > recenter_delay and vh.length() > 3.0:
		var want := atan2(-vh.x, -vh.z)
		var w := recenter_rate * clampf(vh.length() / 25.0, 0.2, 1.0) * clampf(_since_look - recenter_delay, 0.0, 1.0)
		yaw = lerp_angle(yaw, want, 1.0 - exp(-w * dt))
		# Pitch drifts to show where we're heading: down when diving, level when rising.
		var dive := clampf(-v.y / 30.0, -0.5, 1.0)
		var want_pitch := deg_to_rad(default_pitch - 14.0 * dive)
		pitch = lerp_angle(pitch, want_pitch, 1.0 - exp(-0.8 * dt))

	var ahead := (v * look_ahead_time).limit_length(look_ahead_max)
	ahead.y *= 0.4
	var focus_goal := target.global_position + Vector3.UP * height + ahead
	_dist = lerpf(_dist, lerpf(near_distance, far_distance, t), 1.0 - exp(-2.0 * dt))
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	if _snapped:
		_focus = focus_goal
		_pos = focus_goal + basis.z * _dist
		_damp_vel[0] = Vector3.ZERO
		_damp_vel[1] = Vector3.ZERO
		_snapped = false
	_focus = _smooth_damp(0, _focus, focus_goal, aim_smooth, dt)
	var pos_goal := _focus + basis.z * _dist
	_pos = _smooth_damp(1, _pos, pos_goal, follow_smooth, dt)
	# Keep the trailing distance bounded even when the damper lags at high speed.
	var off := _pos - _focus
	if off.length() > _dist * 1.25:
		_pos = _focus + off.normalized() * _dist * 1.25

	var final_pos := _avoid_walls(_focus, _pos)
	global_position = final_pos
	look_at(_focus, Vector3.UP)

	# Gentle roll into turns (rate of yaw change), capped at 4°, never shaky.
	var lateral := 0.0
	if vh.length() > 4.0:
		lateral = basis.x.dot(target.controls.move) * clampf(vh.length() / 30.0, 0.0, 1.0)
	_roll = lerpf(_roll, -lateral * deg_to_rad(4.0), 1.0 - exp(-3.0 * dt))
	rotate_object_local(Vector3.BACK, _roll)

	_fov_kick = move_toward(_fov_kick, 0.0, 6.0 * dt)
	var fov_goal := lerpf(base_fov, max_fov, t * t * (3.0 - 2.0 * t)) + _fov_kick
	cam.fov = lerpf(cam.fov, fov_goal, 1.0 - exp(-4.0 * dt))


func _avoid_walls(from: Vector3, to: Vector3) -> Vector3:
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
	if res.is_empty() or res[0] >= 1.0:
		return to
	return from + (to - from) * maxf(res[0], 0.05)


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
