class_name Player
extends CharacterBody3D
## Bridges the pure SwingPhysics model with engine collision. Each tick:
## read input → update the web line → integrate model → move_and_slide
## against real geometry → feed contact normals back into the model's velocity
## → wrap/unwrap the rope around building corners.
##
## Two ways to fire a web:
##  * Precise (touch, mouse): screen_target() casts the camera ray through the
##    touched pixel; fire_at() shoots the line at that exact collision point.
##    Invalid targets are rejected with a reason – never redirected elsewhere.
##  * Assisted (controller/keyboard "grapple" action, autopilot): the ray-fan
##    in GrappleTargeting picks a point.

signal grapple_fired(target: Vector3, will_hit: bool)
signal attached(anchor: Vector3)
signal released(velocity: Vector3)
signal grapple_missed
signal web_rejected(point: Vector3, reason: String)
signal landed(speed: float, on_street: bool)
signal impact(speed: float)
signal rope_snapped(speed: float)
signal rope_wrapped(corner: Vector3)
signal web_cut(at: Vector3)
signal respawned
signal wall_kicked
signal trick
signal stun_started(speed: float)
## Head-on wall hit: knocked out (stun_started follows). normal = the wall's.
signal knockout(speed: float, normal: Vector3)
## JUMP pressed just before a knockout-speed wall hit: kicked off it instead.
signal wall_saved(speed: float)
signal stun_ended
signal launched
signal stepped_up(height: float)
## Any contact with a wall or obstacle worth a visible reaction (visual only):
## speed into the surface and its normal.
signal bumped(speed: float, normal: Vector3)
## Let go inside the sweet spot (see SwingParams "Release"). streak counts
## consecutive perfect releases without touching the ground.
signal perfect_release(streak: int)

enum Line { IDLE, FLYING, ATTACHED }

const HAND_OFFSET := Vector3(0.0, 0.7, 0.0)
const BUILDINGS_MASK := 1 | (1 << 1)
const GRAPPLE_LAYER := 1 << 1
const MAX_WRAPS := 4
const STEP_MAX := 0.35  # kerbs, stairs and rooftop lips climbed while running
## Input smoothing time constant: the body can't redirect itself instantly.
const MOVE_SMOOTH := 0.09

@export var params: SwingParams

var s := SwingPhysics.State.new()
var controls := SwingPhysics.Controls.new()
var targeting := GrappleTargeting.new()
var land_impact := 0.0  # vertical speed (m/s) at the last touchdown, for the animation
## Node providing the view basis for camera-relative input (the SwingCamera).
var view: Node3D
## Optional autopilot (tests / attract mode): object with drive(player, dt) -> Dictionary.
var bot: Object = null
var input_enabled := true

var line_state := Line.IDLE
var line_tip := Vector3.ZERO
var line_target := Vector3.ZERO
var line_will_hit := false
var aim_dir := Vector3.FORWARD
## Who owns the current web: "action" (button/autopilot) or "touch".
var web_owner := ""
## Touch index holding the web (touch-owned webs release when *that* finger lifts).
var web_touch_id := -1
## Earlier pivots when the rope has wrapped round corners: [{anchor, length}], oldest first.
var wraps: Array = []

var stunned := false
var knocked_out := false
var ko_normal := Vector3.ZERO
var ko_velocity := Vector3.ZERO  # velocity just before the hit
var _kick_window := 0.0
var _stun_time := 0.0
var _settle_time := 0.0
var spawn_transform := Transform3D.IDENTITY
var last_safe_position := Vector3.ZERO
var on_street := false
var was_on_floor := false
var air_time := 0.0

# Run statistics (reset by game modes).
var distance_travelled := 0.0
var swings := 0
var chain := 0
var best_chain := 0
var perfect_streak := 0
var perfects := 0
var _from_swing := false  # in flight after letting go of a web (apex hang applies)
var top_speed := 0.0

var _grapple_held := false
var _move_smooth := Vector3.ZERO
var _attach_length := 0.0
## Set by a ground launch: the web zips the body up before swinging normally.
var _zip := false
var _launch_pending := false
## Touch finger still holding SWING with no target yet: fire as soon as one appears.
var _armed_touch := -1
var _prev_pos := Vector3.ZERO
var _bump_cool := 0.0


func _ready() -> void:
	if params == null:
		var settings := get_node_or_null("/root/Settings")
		params = settings.swing_params() if settings else load("res://config/swing_params.tres")
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 1) | (1 << 3)
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	safe_margin = 0.02
	if get_node_or_null("Shape") == null:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.8
		shape.shape = cap
		add_child(shape)
	spawn_transform = global_transform
	last_safe_position = global_position
	s.position = global_position


func speed() -> float:
	return s.velocity.length()


func hand_position() -> Vector3:
	return global_position + HAND_OFFSET


## The real attachment point (first anchor), even while wrapped round corners.
func rope_anchor() -> Vector3:
	return wraps[0]["anchor"] if not wraps.is_empty() else s.anchor


## Rope polyline from the hand back to the original anchor (for drawing).
func rope_points() -> PackedVector3Array:
	var pts := PackedVector3Array([hand_position(), s.anchor])
	for i in range(wraps.size() - 1, -1, -1):
		pts.append(wraps[i]["anchor"])
	return pts


# ------------------------------------------------------- precise targeting
## Casts the camera ray through `screen_pos` and validates the first surface it
## meets. Returns {ok, point, normal, reason}. Reasons: "sky", "street",
## "too far", "blocked". The point is always the surface actually under the
## finger; nothing is ever substituted.
func screen_target(cam: Camera3D, screen_pos: Vector2) -> Dictionary:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	# Cast far: a distant visible tower must be reported "too far", not "sky".
	return ray_target(from, dir, 2500.0)


func ray_target(from: Vector3, dir: Vector3, length: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * length, BUILDINGS_MASK | (1 << 3), [get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {"ok": false, "reason": "sky", "point": from + dir * minf(length, 80.0), "normal": -dir}
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var col: Object = hit["collider"]
	if not (col is CollisionObject3D and ((col as CollisionObject3D).collision_layer & GRAPPLE_LAYER)):
		return {"ok": false, "reason": "street", "point": point, "normal": normal}
	var hand := hand_position()
	if hand.distance_to(point) > params.grapple_range:
		return {"ok": false, "reason": "too far", "point": point, "normal": normal}
	# Line of sight from the launcher: the web can't pass through another building.
	var to_point := point - hand
	var los := PhysicsRayQueryParameters3D.create(hand, point - to_point.normalized() * 0.25, BUILDINGS_MASK, [get_rid()])
	if not space.intersect_ray(los).is_empty():
		return {"ok": false, "reason": "blocked", "point": point, "normal": normal}
	return {"ok": true, "reason": "", "point": point, "normal": normal}


## Fires the line at an exact, already validated world point. Re-firing while
## attached swaps to the new anchor (immediate reattachment).
func fire_at(point: Vector3, touch_id := -1) -> void:
	if stunned:
		return
	if line_state != Line.IDLE:
		_let_go()
	_armed_touch = -1
	_ground_launch()
	web_owner = "touch"
	web_touch_id = touch_id
	line_state = Line.FLYING
	line_tip = hand_position()
	line_will_hit = true
	line_target = point
	grapple_fired.emit(point, true)


## Releases the web if `touch_id` owns it (or unconditionally with -2).
func release_web(touch_id := -2) -> void:
	if touch_id == _armed_touch or touch_id == -2:
		_armed_touch = -1
	if touch_id != -2 and touch_id != web_touch_id:
		return
	_let_go()


# ------------------------------------------------------------------ input
func _read_input(dt: float) -> Dictionary:
	if stunned:
		if bot != null:
			bot.drive(self, dt)  # keep the autopilot's view of the world current
		return {"move": Vector3.ZERO, "aim": aim_dir, "grapple": false, "reel": 0.0, "jump": false}
	if bot != null:
		return bot.drive(self, dt)
	if not input_enabled:
		return {"move": Vector3.ZERO, "aim": aim_dir, "grapple": false, "reel": 0.0, "jump": false}
	var mv := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	# Response curve: the first half of the stick is a walk-to-jog range, so
	# walking is easy to hold; full deflection still sprints.
	mv = mv.normalized() * pow(mv.length(), 2.0) if mv.length() > 0.001 else Vector2.ZERO
	var basis := view.global_transform.basis if view else global_transform.basis
	var fwd := -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	return {
		"move": (right * mv.x + fwd * mv.y).limit_length(1.0),
		"aim": -basis.z,
		"grapple": Input.is_action_pressed("grapple"),
		"jump": Input.is_action_just_pressed("jump"),
		"respawn": Input.is_action_just_pressed("respawn"),
	}


func _physics_process(dt: float) -> void:
	RenderingServer.global_shader_parameter_set(&"player_pos", global_position)  # pedestrians step aside
	# Stun first: input read while stunned must never be applied after recovery.
	if stunned:
		_update_stun(dt)
	var inp := _read_input(dt)
	var move: Vector3 = inp.get("move", Vector3.ZERO)
	_move_smooth = _move_smooth.lerp(move, 1.0 - exp(-dt / MOVE_SMOOTH))
	controls.move = _move_smooth
	# Human steering turns the travel; bots/courses keep the raw model (a
	# review script can opt in with `human_steer` to move like a player).
	controls.turn_assist = bot == null or bot.get("human_steer") == true
	controls.human = controls.turn_assist
	controls.reel = auto_tighten()
	controls.jump = inp.get("jump", false)
	controls.gravity_scale = 1.0
	if _from_swing and not s.attached and absf(s.velocity.y) < params.apex_window:
		# Hang at the top of the flight: time to pick the next anchor.
		var k := absf(s.velocity.y) / params.apex_window
		controls.gravity_scale = lerpf(params.apex_gravity_scale, 1.0, k * k)
	aim_dir = inp.get("aim", aim_dir)
	if inp.get("respawn", false):
		respawn()
		return

	var origin := hand_position()
	targeting.update(get_world_3d().direct_space_state, origin, aim_dir, s.velocity, params,
		is_on_floor(), [get_rid()], _move_smooth)
	if line_state == Line.IDLE or line_state == Line.ATTACHED:
		targeting.refresh_pick(get_world_3d().direct_space_state, _launch_state(), params, [get_rid()], dt)

	# Assisted grapple (button/autopilot). Touch webs are driven by fire_at/release_web.
	# While stunned the hand stays clenched on the line: input can't release it.
	if not stunned:
		var held: bool = inp.get("grapple", false)
		if held and not _grapple_held and line_state == Line.IDLE:
			_fire(origin)
		elif not held and _grapple_held and web_owner == "action":
			_let_go()
		_grapple_held = held
	if _armed_touch != -1 and targeting.has_target and not stunned:
		var id := _armed_touch
		_armed_touch = -1
		if line_state != Line.IDLE:
			_let_go()
		_fire(origin)
		web_owner = "touch"
		web_touch_id = id
	_advance_line(dt, origin)

	_kick_window = maxf(_kick_window - dt, 0.0)
	if controls.jump and not is_on_floor():
		_kick_window = params.wall_save_window  # a wall in the next instant: kick off it
		if is_on_wall():
			var n := get_wall_normal()
			s.velocity += Vector3(n.x, 0.0, n.z).normalized() * params.wall_kick_speed
			s.velocity.y = maxf(s.velocity.y, 0.0) + params.wall_kick_up
			wall_kicked.emit()
		elif line_state != Line.ATTACHED:
			trick.emit()  # purely visual acrobatics; no physics effect
		controls.jump = false

	# Integrate the model from the body's real position.
	s.position = global_position
	s.grounded = is_on_floor() and not _launch_pending
	_launch_pending = false
	var start := global_position
	SwingPhysics.step(s, controls, params, dt)
	if s.snap_speed > 2.0:
		rope_snapped.emit(s.snap_speed)
	floor_snap_length = 0.0 if (s.attached or s.velocity.y > 0.5) else 0.4
	velocity = (s.position - start) / dt
	if s.grounded and not s.attached and s.velocity.y < 0.5:
		_try_step_up(velocity * dt)
	move_and_slide()
	_resolve_contacts(dt)
	if s.attached and params.rope_wrapping:
		_update_wraps()
	else:
		_prev_pos = global_position

	var moved := global_position - start
	distance_travelled += Vector3(moved.x, 0.0, moved.z).length()
	top_speed = maxf(top_speed, s.velocity.length())
	if is_on_floor():
		air_time = 0.0
	else:
		air_time += dt
	if global_position.y < params.kill_plane_y:
		respawn()


## A running body blocked by something no taller than STEP_MAX steps onto
## it instead of stopping dead: up, across, back down onto a walkable top.
## The horizontal motion is consumed here; move_and_slide then only settles
## the body on the new floor. Taller obstacles are walls, as before.
func _try_step_up(motion: Vector3) -> void:
	var h := Vector3(motion.x, 0.0, motion.z)
	if h.length() < 1e-4 or not test_move(global_transform, h):
		return
	var up := Vector3.UP * STEP_MAX
	if test_move(global_transform, up):
		return
	var raised := global_transform.translated(up)
	var ahead := h.normalized() * maxf(h.length(), 0.08)  # enough to clear the edge
	if test_move(raised, ahead):
		return
	var over := raised.translated(ahead)
	var hit := KinematicCollision3D.new()
	if not test_move(over, Vector3.DOWN * (STEP_MAX + 0.05), hit) or hit.get_normal().y < 0.7:
		return
	var rise := over.origin.y + hit.get_travel().y - global_position.y
	if rise < 0.02:
		return
	global_position = over.origin + hit.get_travel()
	velocity = Vector3(0.0, minf(velocity.y, 0.0), 0.0)
	stepped_up.emit(rise)


func _resolve_contacts(dt: float) -> void:
	_bump_cool = maxf(_bump_cool - dt, 0.0)
	var pre_hit := s.velocity
	var worst_into := 0.0
	var wall_n := Vector3.ZERO  # normal of the hardest wall hit this tick
	var wall_ratio := 0.0       # its share of the speed going into the wall (1 = head-on)
	var floor_street := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		var into := -s.velocity.dot(n)
		if into > 0.0:
			var pre_speed := s.velocity.length()
			s.velocity += n * into
			if n.y < 0.6:
				if into > worst_into:
					wall_n = n
					wall_ratio = into / maxf(pre_speed, 0.001)
				worst_into = maxf(worst_into, into)
			elif not was_on_floor:
				worst_into = maxf(worst_into, into * 0.5)
		if into > 1.5 and n.y < 0.6 and _bump_cool <= 0.0:
			bumped.emit(into, n)
			_bump_cool = 0.15
		if absf(n.y) < 0.6:
			# Scraping along a facade bleeds speed (no frictionless wall-surfing).
			var vn := n * s.velocity.dot(n)
			s.velocity = vn + (s.velocity - vn) * maxf(0.0, 1.0 - params.wall_friction * dt)
		var col := c.get_collider()
		if n.y > 0.6 and col is Node and (col as Node).is_in_group("street"):
			floor_street = true
	var on_floor := is_on_floor()
	if on_floor and not was_on_floor:
		on_street = floor_street
		var land_speed := -get_real_velocity().y
		var speed_in := maxf(land_speed, worst_into)
		# The animation wants the true vertical impact (speed_in is softened
		# for the stun rules).
		land_impact = maxf(-pre_hit.y, speed_in)
		landed.emit(speed_in, floor_street)
		chain = 0
		perfect_streak = 0
		_from_swing = false
		if not floor_street:
			last_safe_position = global_position + Vector3.UP * 0.2
		if speed_in > params.ragdoll_fall_speed:
			stun(speed_in)
	elif on_floor:
		on_street = floor_street
	var facade := wall_n != Vector3.ZERO and worst_into > params.hard_impact_speed and not stunned
	if facade and wall_ratio < params.wall_glance_ratio:
		# A glancing hit is a wall tap, not a crash: kick off the facade and
		# keep flowing (and keep the chain).
		var out := Vector3(wall_n.x, 0.0, wall_n.z).normalized()
		s.velocity += out * worst_into * params.wall_glance_bounce
		s.velocity.y = maxf(s.velocity.y, 0.0) + params.wall_kick_up * 0.6
		wall_kicked.emit()
		trick.emit()
	elif facade and worst_into >= params.wall_run_max_speed and _kick_window > 0.0:
		# Head-on and fast, but JUMP was timed: plant the feet and spring off
		# the facade, keeping most of the speed along it.
		_kick_window = 0.0
		if line_state == Line.ATTACHED:
			_let_go()
		var out := Vector3(wall_n.x, 0.0, wall_n.z).normalized()
		var along := pre_hit - out * pre_hit.dot(out)
		along.y = 0.0
		s.velocity = along * 0.8 + out * minf(worst_into * 0.45, 16.0)
		s.velocity.y = maxf(pre_hit.y, 0.0) * 0.5 + params.wall_kick_up
		impact.emit(params.hard_impact_speed)
		wall_kicked.emit()
		wall_saved.emit(worst_into)
		trick.emit()
	elif facade and worst_into >= params.wall_run_max_speed:
		# Head-on and fast: knocked out.
		impact.emit(worst_into)
		_knockout(worst_into, wall_n, pre_hit)
	elif facade:
		# Head-on, but slow enough: hit the facade feet-first and run up it.
		# Horizontal momentum is gone (that's the cost); the chain survives.
		if line_state == Line.ATTACHED:
			_let_go()
		var out := Vector3(wall_n.x, 0.0, wall_n.z).normalized()
		var along := s.velocity - out * s.velocity.dot(out)
		along.y = 0.0
		s.velocity = along * 0.5 + out * 2.0
		s.velocity.y = clampf(worst_into * params.wall_run_up, 10.0, 22.0)
		impact.emit(params.hard_impact_speed)  # a firm thud, no ragdoll
		wall_kicked.emit()
	elif worst_into > params.hard_impact_speed:
		impact.emit(worst_into)
		if worst_into > params.ragdoll_impact_speed:
			stun(worst_into)
	was_on_floor = on_floor


# ------------------------------------------------------------- rope wrap
## Real ropes catch on corners. If a building now blocks the straight line to
## the pivot, the corner becomes the new pivot (remaining length shortens);
## once the straight line to the earlier pivot is clear again, it unwraps.
func _update_wraps() -> void:
	var space := get_world_3d().direct_space_state
	var pos := global_position
	if not wraps.is_empty():
		var prev: Vector3 = wraps[-1]["anchor"]
		# (A new pivot lies on the straight line, so "collinear" can't be the
		# test.) The rope unwraps once the straight line to the earlier anchor
		# no longer meets the building.
		if _clear(space, pos, prev):
			s.rope_length += s.anchor.distance_to(prev)
			s.anchor = prev
			wraps.pop_back()
			return
	if wraps.size() >= MAX_WRAPS or _clear(space, pos, s.anchor):
		_prev_pos = pos
		return
	# The rope has just met an edge. Find when it first touched (binary search
	# between last tick's clear position and this one) so the new pivot sits
	# on the corner itself, not partway along a face.
	var lo := 0.0
	var hi := 1.0
	if _clear(space, _prev_pos, s.anchor):
		for i in 7:
			var mid := (lo + hi) * 0.5
			if _clear(space, _prev_pos.lerp(pos, mid), s.anchor):
				lo = mid
			else:
				hi = mid
	var touch := _prev_pos.lerp(pos, hi)
	_prev_pos = pos
	var to := s.anchor - touch
	var q := PhysicsRayQueryParameters3D.create(touch, s.anchor - to.normalized() * 0.6, BUILDINGS_MASK, [get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var hn: Vector3 = hit["normal"]
	if absf((s.anchor - (hit["position"] as Vector3)).dot(hn)) < 0.3:
		return  # the rope lying along the very wall it's stuck to – not a corner
	var corner: Vector3 = hit["position"] + hn * 0.15
	var seg := s.anchor.distance_to(corner)
	if seg < 1.0:
		return
	if s.rope_length - seg < params.wrap_cut_length:
		# Caught tight on an edge with almost no line left: the web cuts against
		# it and the body flies on with its momentum.
		web_cut.emit(corner)
		_let_go()
		return
	wraps.append({"anchor": s.anchor})
	s.anchor = corner
	s.rope_length -= seg
	rope_wrapped.emit(corner)


static func _clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b - (b - a).normalized() * 0.6, BUILDINGS_MASK)
	return space.intersect_ray(q).is_empty()


# ------------------------------------------------------------ line life
## Touch SWING: an assisted web owned by finger `touch_id`. Pressing while
## already swinging re-attaches. Returns whether there was a target.
func assist_fire(touch_id: int) -> bool:
	if stunned:
		return false
	if not targeting.has_target:
		# Nothing to catch yet (e.g. top of a tall roof): stay armed while the
		# finger is down and fire the moment a target comes into reach.
		_armed_touch = touch_id
		if line_state == Line.IDLE:
			_ground_launch()
		return false
	if line_state != Line.IDLE:
		_let_go()
	_armed_touch = -1
	_fire(hand_position())
	web_owner = "touch"
	web_touch_id = touch_id
	return line_will_hit


## Firing from the ground: jump as the web goes out, so the line catches the
## body in the air and winches it up into a swing (street or rooftop alike).
func _ground_launch() -> void:
	if is_on_floor() and not stunned:
		# Leap up and forward along the view, so a launch off a roof clears the edge.
		var fwd := Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
		if fwd.length_squared() > 0.5 and Vector3(s.velocity.x, 0, s.velocity.z).length() < 6.0:
			s.velocity += fwd * 6.0
		s.velocity.y = maxf(s.velocity.y, params.jump_speed)
		s.grounded = false
		_launch_pending = true
		_zip = true
		launched.emit()


## The state a web fired now would start from: on the ground, firing also
## launches (see _ground_launch), so the swing starts from that jump.
func _launch_state() -> SwingPhysics.State:
	var st := SwingPhysics.State.new()
	st.position = global_position
	st.velocity = s.velocity
	if is_on_floor() and not stunned:
		var fwd := Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
		if fwd.length_squared() > 0.5 and Vector3(st.velocity.x, 0, st.velocity.z).length() < 6.0:
			st.velocity += fwd * 6.0
		st.velocity.y = maxf(st.velocity.y, params.jump_speed)
	return st


func _fire(origin: Vector3) -> void:
	if line_state != Line.IDLE or stunned:
		return
	_ground_launch()
	web_owner = "action"
	web_touch_id = -1
	line_state = Line.FLYING
	line_tip = origin
	line_will_hit = targeting.has_target
	if line_will_hit:
		s.position = global_position
		line_target = targeting.best_flyable(get_world_3d().direct_space_state, s, params, [get_rid()])
		if bot != null and bot.has_method("choose_anchor"):
			line_target = bot.choose_anchor(self, line_target)  # title-screen pilot
	else:
		line_target = origin + aim_dir.normalized() * params.grapple_range * 0.8
	grapple_fired.emit(line_target, line_will_hit)


func _advance_line(dt: float, _origin: Vector3) -> void:
	if line_state != Line.FLYING:
		return
	var to := line_target - line_tip
	var step := params.line_speed * dt
	if to.length() > step:
		line_tip += to.normalized() * step
		return
	line_tip = line_target
	if line_will_hit and SwingPhysics.attach(s, line_target, _range_tolerant()):
		wraps.clear()
		_attach_length = s.rope_length
		line_state = Line.ATTACHED
		attached.emit(line_target)
	else:
		line_state = Line.IDLE
		web_owner = ""
		grapple_missed.emit()


## The anchor may drift slightly out of range while the line travels; allow 10%.
func _range_tolerant() -> SwingParams:
	if s.position.distance_to(line_target) <= params.grapple_range:
		return params
	var p: SwingParams = params.duplicate()
	p.grapple_range *= 1.1
	return p


func _let_go() -> void:
	if line_state == Line.ATTACHED:
		var perfect := is_perfect_release()
		SwingPhysics.release(s)
		if perfect:
			s.velocity *= params.perfect_release_boost
			s.velocity.y += params.perfect_release_lift
		swings += 1
		chain += 1
		best_chain = maxi(best_chain, chain)
		_from_swing = true
		released.emit(s.velocity)
		if perfect:
			perfect_streak += 1
			perfects += 1
			perfect_release.emit(perfect_streak)
	line_state = Line.IDLE
	web_owner = ""
	web_touch_id = -1
	wraps.clear()
	_zip = false


## True when letting go now would be a perfect release: taut, rising,
## heading forward-and-up inside the sweet spot, at speed.
func is_perfect_release() -> bool:
	if not (s.attached and s.taut) or stunned:
		return false
	var v := s.velocity
	var spd := v.length()
	if spd < params.perfect_release_min_speed:
		return false
	var up := rad_to_deg(asin(clampf(v.y / spd, -1.0, 1.0)))
	return up >= params.perfect_release_min_deg and up <= params.perfect_release_max_deg


## How hard the web pulls itself in this tick (see SwingPhysics.auto_tighten).
func auto_tighten() -> float:
	if stunned:
		return 0.0
	if _zip and s.attached:
		# Launched from the ground: winch hard until the line is down to its
		# shortest pull, including while initially slack. Waiting for tautness
		# leaves the jumper falling back to the street before the rope catches.
		if s.rope_length > _attach_length * params.auto_tighten_min_fraction + 0.5:
			return 2.0
		_zip = false
	return SwingPhysics.auto_tighten(s, params, _attach_length)


# ----------------------------------------------------------- stun / reset
## A hard crash: the body goes limp (the rig ragdolls) and input is frozen;
## physics carries on untouched. On the rope, the clenched hand keeps hold and
## the body dangles; in free flight it tumbles. recover() is called by the rig.
func stun(impact_speed: float) -> void:
	if stunned:
		return
	if line_state == Line.FLYING:
		_let_go()
	stunned = true
	_stun_time = 0.0
	_settle_time = 0.0
	stun_started.emit(impact_speed)


## Head-on into a wall: the web lets go and the body bounces off the facade
## limp (the rig's ragdoll takes the hit), drops, and stays down for at least
## knockout_time.
func _knockout(into: float, wall_n: Vector3, pre: Vector3) -> void:
	_let_go()
	var out := Vector3(wall_n.x, 0.0, wall_n.z).normalized()
	ko_normal = out
	ko_velocity = pre
	var along := pre - out * pre.dot(out)
	along.y = 0.0
	s.velocity = along * 0.3 + out * minf(into * 0.16, 7.0) + Vector3.UP * minf(pre.y, 2.0)
	chain = 0
	perfect_streak = 0
	knocked_out = true
	knockout.emit(into, out)
	stun(into)


## Recovery is decided here (gameplay), not by the visual rig: dangling from
## the web the body shakes it off after 0.9 s; otherwise it gets up once it has
## come to rest on something; if wedged somewhere it respawns.
func _update_stun(dt: float) -> void:
	_stun_time += dt
	if is_on_floor() and speed() < 2.0:
		_settle_time += dt
	else:
		_settle_time = 0.0
	var down := params.knockout_time if knocked_out else 1.2
	if (line_state == Line.ATTACHED and _stun_time > 0.9 and not knocked_out) or (_stun_time > down and _settle_time > 0.6):
		recover()
	elif _stun_time > 8.0:
		respawn()


func recover() -> void:
	knocked_out = false
	if stunned:
		stunned = false
		stun_ended.emit()


func respawn(at: Variant = null) -> void:
	_let_go()
	_armed_touch = -1
	_launch_pending = false
	stunned = false
	knocked_out = false
	_grapple_held = true  # require a fresh press
	global_position = at if at is Vector3 else last_safe_position
	s.velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	_move_smooth = Vector3.ZERO
	s.position = global_position
	was_on_floor = false
	chain = 0
	perfect_streak = 0
	_from_swing = false
	respawned.emit()


func reset_stats() -> void:
	distance_travelled = 0.0
	swings = 0
	chain = 0
	best_chain = 0
	perfects = 0
	top_speed = 0.0
