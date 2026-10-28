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
##  * Swing framing: big arcs get a wider shot and the view lifts toward the
##    line; the camera dips with the down-swing and looks up out of a
##    release toward the next anchor (biased a little toward the web pick).
##  * Feel: landings dip the view, catching a web gives a small tug, a
##    gentle bank (max 4°) leans into sustained turns at speed.

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
var _punch := 0.0  # 1 → 0 after a perfect release; FOV snaps out fast, eases back
var _snapped := false
var _bump := 0.0           # landing / catch impulse (m, spring-damped)
var _bump_v := 0.0
var _tug := 0.0            # web-catch pull-back (m, spring-damped)
var _tug_v := 0.0
var _roll := 0.0
var _prev_heading := 0.0
var _turn_rate := 0.0
var _lift := 0.0           # smoothed framing lift toward the line
var _pick_bias := Vector3.ZERO
var _crane := 0.0          # 0..1 lift over the shoulder when squeezed
var _shake := 0.0          # metres of positional shake (decays)
var _shake_t := 0.0
var _body: Node3D          # the character, hidden if the lens gets inside it
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
	_body = p.get_node_or_null("Rig")
	p.view = self
	snap()
	p.respawned.connect(snap)
	p.rope_snapped.connect(func(spd: float): _fov_kick = minf(_fov_kick + spd * 0.2, 3.0))
	# Perfect release: a quick widening punch that sells the burst of speed.
	p.perfect_release.connect(func(_n): _fov_kick = minf(_fov_kick + 7.0, 10.0); _punch = 1.0)
	p.landed.connect(func(spd: float, _street: bool): _bump_v -= clampf(spd * 0.09, 0.0, 2.6))
	p.attached.connect(func(_a: Vector3): _tug_v += clampf(target.speed() * 0.04, 0.4, 1.6))


## A jolt (knockouts): decaying, low-frequency shake plus a FOV punch-in.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)
	_fov_kick -= amount * 6.0


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
	if not grounded:
		if target.s.attached:
			# Ride the arc: tip down into the down-swing, level out climbing.
			want_pitch -= deg_to_rad(5.0) * clampf(-v.y / 20.0, 0.0, 1.0)
		else:
			# Flying out of a release: look up toward where the next web goes.
			want_pitch += deg_to_rad(9.0) * clampf(v.y / 18.0, 0.0, 1.0)
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
	var lift_goal := 0.0
	if target.s.attached and target.s.taut:
		# Long lines swing big arcs: frame more of them.
		var rope := target.s.rope_length
		want_dist += clampf((rope - 15.0) * 0.06, 0.0, 2.2)
		lift_goal = clampf(rope * 0.04, 0.0, 1.4)
	_lift = lerpf(_lift, lift_goal, 1.0 - exp(-2.5 * dt))
	_dist = lerpf(_dist, want_dist * distance_scale, 1.0 - exp(-2.0 * dt))
	_height = lerpf(_height, (1.4 if grounded else 1.6) * minf(distance_scale * 1.2, 1.0), 1.0 - exp(-3.0 * dt))
	var ahead := (vh * 0.12).limit_length(minf(3.5, _dist * 0.35))
	# In flight, lean the framing a little toward the web you'd get next.
	var bias_goal := Vector3.ZERO
	var tg := target.targeting
	if not grounded and not target.s.attached and tg.pick_ok:
		var to_pick := tg.pick - target.global_position
		bias_goal = Vector3(to_pick.x, 0.0, to_pick.z).limit_length(1.5) * 0.6
	_pick_bias = _pick_bias.lerp(bias_goal, 1.0 - exp(-2.0 * dt))
	# Impulses: spring-damped, so they settle without wobble.
	_bump_v += (-_bump * 140.0 - _bump_v * 17.0) * dt
	_bump += _bump_v * dt
	_tug_v += (-_tug * 90.0 - _tug_v * 14.0) * dt
	_tug += _tug_v * dt
	var focus_goal := target.global_position + Vector3.UP * (_height + _lift) + ahead + _pick_bias
	var basis := Basis.from_euler(Vector3(clampf(pitch + look_pitch, deg_to_rad(-70.0), deg_to_rad(50.0)), yaw + look_yaw, 0.0))
	if _snapped:
		_bump = 0.0
		_bump_v = 0.0
		_tug = 0.0
		_tug_v = 0.0
		_roll = 0.0
		_crane = 0.0
		_prev_heading = _heading
		_turn_rate = 0.0
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
	var shaken := _focus + Vector3.UP * _bump * 0.5
	# The focus leads/lags the body; hugging a facade it can end up inside the
	# wall, and every wall check from there passes. Keep it on the body's side.
	shaken = _ray_clear(target.global_position + Vector3.UP * 0.6, shaken)
	var cam_goal := _pos + Vector3.UP * _bump + (_pos - _focus).normalized() * _tug
	var placed := _avoid_walls(shaken, cam_goal, dt)
	# A wall right behind would push the lens into the body: crane up and
	# look over the shoulder instead (the crane is collision-checked too).
	var squeeze := clampf((2.4 - placed.distance_to(shaken)) / 2.0, 0.0, 1.0)
	_crane = lerpf(_crane, squeeze, 1.0 - exp(-(10.0 if squeeze > _crane else 2.5) * dt))
	if _crane > 0.01:
		var up := _ray_clear(placed, placed + Vector3.UP * 2.2 * _crane)
		placed = up
	if _shake > 0.002:
		# Real time, so the shake still reads while the game is in slow motion.
		var rt := dt / maxf(Engine.time_scale, 0.05)
		_shake_t += rt
		var n := Vector3(sin(_shake_t * 37.0), sin(_shake_t * 29.0 + 1.3), sin(_shake_t * 41.0 + 2.1))
		placed += n * _shake
		shaken += n * _shake * 0.35
		_shake *= exp(-4.5 * rt)
	global_position = placed
	look_at(shaken + Vector3.DOWN * 0.4 * _crane, Vector3.UP)
	# Never film the inside of the character.
	if _body:
		_body.visible = global_position.distance_to(target.global_position + Vector3.UP * 0.3) > 0.85
	# Bank into sustained turns at speed (never during reversals).
	_turn_rate = lerpf(_turn_rate, wrapf(_heading - _prev_heading, -PI, PI) / maxf(dt, 1e-4), 1.0 - exp(-3.0 * dt))
	_prev_heading = _heading
	var roll_goal := clampf(-_turn_rate * vh.length() * 0.004, -deg_to_rad(4.0), deg_to_rad(4.0)) if not grounded else 0.0
	_roll = lerpf(_roll, roll_goal, 1.0 - exp(-2.5 * dt))
	rotate_object_local(Vector3.FORWARD, _roll)

	_fov_kick = move_toward(_fov_kick, 0.0, 5.0 * dt / maxf(Engine.time_scale, 0.05))
	_punch = move_toward(_punch, 0.0, dt * 2.5)
	var fov_goal := lerpf(base_fov, max_fov, t * t * (3.0 - 2.0 * t)) + _fov_kick
	cam.fov = lerpf(cam.fov, fov_goal, 1.0 - exp(-(3.0 + 9.0 * _punch) * dt))


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
		if not space.intersect_point(pq).is_empty() and _push_out(space, pq.position, from) == Vector3.INF:
			_col_dist = allowed  # can't slide along the face: cut in
	else:
		_col_dist = lerpf(_col_dist, allowed, 1.0 - exp(-3.0 * dt))
	var out := from + dir * minf(_col_dist, full)
	# The sweep ignores walls the sphere starts against (grazing a facade):
	# a lens that ends up inside a box is pushed out through its nearest side
	# (a few cm, so no visible jump).
	var pushed := _push_out(space, out, from)
	return pushed if pushed != Vector3.INF else _ray_clear(from, out)


## `p` moved just outside the box it is in, through a side facing `fallback_from`
## (the focus); INF if that isn't possible (not a box, or round a corner).
func _push_out(space: PhysicsDirectSpaceState3D, p: Vector3, fallback_from: Vector3) -> Vector3:
	var pq := PhysicsPointQueryParameters3D.new()
	pq.collision_mask = 1 | (1 << 1)
	for attempt in 3:
		pq.position = p
		var hits := space.intersect_point(pq, 1)
		if hits.is_empty():
			return p
		var col = hits[0]["collider"]
		var owner_id: int = col.shape_find_owner(hits[0]["shape"]) if col is CollisionObject3D else -1
		var cs = col.shape_owner_get_owner(owner_id) if owner_id >= 0 else null
		if not (cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D):
			return Vector3.INF
		var xf := (cs as CollisionShape3D).global_transform
		var ext: Vector3 = ((cs as CollisionShape3D).shape as BoxShape3D).size * 0.5
		var local := xf.affine_inverse() * p
		var lf := xf.affine_inverse() * fallback_from
		var best_axis := -1
		var best_d := INF
		for a in 3:
			# Only through a side the focus is outside of: going round a corner
			# would put the building between the lens and the hero.
			if absf(lf[a]) <= ext[a] or signf(lf[a]) != signf(local[a]):
				continue
			var d := ext[a] - absf(local[a])
			if d < best_d:
				best_d = d
				best_axis = a
		if best_axis < 0:
			return Vector3.INF
		local[best_axis] = signf(local[best_axis]) * (ext[best_axis] + 0.08)
		p = xf * local
	return Vector3.INF


## The furthest point from `from` toward `to` that is clear of buildings.
func _ray_clear(from: Vector3, to: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | (1 << 1))
	q.exclude = [target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return to
	return from + (hit.position - from) * 0.8


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
