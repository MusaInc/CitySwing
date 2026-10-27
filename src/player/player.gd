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
signal respawned
signal wall_kicked
signal trick
signal stun_started(speed: float)
signal stun_ended

enum Line { IDLE, FLYING, ATTACHED }

const HAND_OFFSET := Vector3(0.0, 0.7, 0.0)
const BUILDINGS_MASK := 1 | (1 << 1)
const GRAPPLE_LAYER := 1 << 1
const MAX_WRAPS := 4
## Input smoothing time constant: the body can't redirect itself instantly.
const MOVE_SMOOTH := 0.09

@export var params: SwingParams

var s := SwingPhysics.State.new()
var controls := SwingPhysics.Controls.new()
var targeting := GrappleTargeting.new()
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
var top_speed := 0.0

var _grapple_held := false
var _move_smooth := Vector3.ZERO


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
	return ray_target(from, dir, from.distance_to(hand_position()) + params.grapple_range + 5.0)


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
	web_owner = "touch"
	web_touch_id = touch_id
	line_state = Line.FLYING
	line_tip = hand_position()
	line_will_hit = true
	line_target = point
	grapple_fired.emit(point, true)


## Releases the web if `touch_id` owns it (or unconditionally with -2).
func release_web(touch_id := -2) -> void:
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
		"reel": Input.get_action_strength("reel_in") - Input.get_action_strength("reel_out"),
		"jump": Input.is_action_just_pressed("jump"),
		"respawn": Input.is_action_just_pressed("respawn"),
	}


func _physics_process(dt: float) -> void:
	# Stun first: input read while stunned must never be applied after recovery.
	if stunned:
		_update_stun(dt)
	var inp := _read_input(dt)
	var move: Vector3 = inp.get("move", Vector3.ZERO)
	_move_smooth = _move_smooth.lerp(move, 1.0 - exp(-dt / MOVE_SMOOTH))
	controls.move = _move_smooth
	controls.reel = inp.get("reel", 0.0)
	controls.jump = inp.get("jump", false)
	aim_dir = inp.get("aim", aim_dir)
	if inp.get("respawn", false):
		respawn()
		return

	var origin := hand_position()
	targeting.update(get_world_3d().direct_space_state, origin, aim_dir, s.velocity, params,
		is_on_floor(), [get_rid()])

	# Assisted grapple (button/autopilot). Touch webs are driven by fire_at/release_web.
	# While stunned the hand stays clenched on the line: input can't release it.
	if not stunned:
		var held: bool = inp.get("grapple", false)
		if held and not _grapple_held and line_state == Line.IDLE:
			_fire(origin)
		elif not held and _grapple_held and web_owner == "action":
			_let_go()
		_grapple_held = held
	_advance_line(dt, origin)

	if controls.jump and not is_on_floor():
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
	s.grounded = is_on_floor()
	var start := global_position
	SwingPhysics.step(s, controls, params, dt)
	if s.snap_speed > 2.0:
		rope_snapped.emit(s.snap_speed)
	floor_snap_length = 0.0 if (s.attached or s.velocity.y > 0.5) else 0.4
	velocity = (s.position - start) / dt
	move_and_slide()
	_resolve_contacts(dt)
	if s.attached:
		_update_wraps()

	var moved := global_position - start
	distance_travelled += Vector3(moved.x, 0.0, moved.z).length()
	top_speed = maxf(top_speed, s.velocity.length())
	if is_on_floor():
		air_time = 0.0
	else:
		air_time += dt
	if global_position.y < params.kill_plane_y:
		respawn()


func _resolve_contacts(dt: float) -> void:
	var worst_into := 0.0
	var floor_street := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		var into := -s.velocity.dot(n)
		if into > 0.0:
			s.velocity += n * into
			if n.y < 0.6:
				worst_into = maxf(worst_into, into)
			elif not was_on_floor:
				worst_into = maxf(worst_into, into * 0.5)
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
		landed.emit(speed_in, floor_street)
		chain = 0
		if not floor_street:
			last_safe_position = global_position + Vector3.UP * 0.2
		if speed_in > params.ragdoll_fall_speed:
			stun(speed_in)
	elif on_floor:
		on_street = floor_street
	if worst_into > params.hard_impact_speed:
		impact.emit(worst_into)
		if worst_into > params.ragdoll_impact_speed:
			stun(worst_into)
	was_on_floor = on_floor


# ------------------------------------------------------------- rope wrap
## Real ropes catch on corners. If a building now blocks the straight line to
## the pivot, the corner becomes the new pivot (remaining length shortens);
## when the two segments straighten out again the rope unwraps.
func _update_wraps() -> void:
	var space := get_world_3d().direct_space_state
	var pos := global_position
	if not wraps.is_empty():
		var prev: Vector3 = wraps[-1]["anchor"]
		var a := (s.anchor - prev).normalized()
		var b := (pos - s.anchor).normalized()
		if a.dot(b) > 0.998 or _clear(space, pos, prev):
			# Segments collinear (or the corner no longer touches): unwrap.
			s.rope_length += s.anchor.distance_to(prev)
			s.anchor = prev
			wraps.pop_back()
			return
	if wraps.size() >= MAX_WRAPS:
		return
	var to := s.anchor - pos
	var q := PhysicsRayQueryParameters3D.create(pos, s.anchor - to.normalized() * 0.6, BUILDINGS_MASK, [get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var corner: Vector3 = hit["position"] + (hit["normal"] as Vector3) * 0.2
	var seg := s.anchor.distance_to(corner)
	if seg < 1.0 or s.rope_length - seg < params.min_rope_length:
		return
	wraps.append({"anchor": s.anchor})
	s.anchor = corner
	s.rope_length -= seg
	rope_wrapped.emit(corner)


static func _clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b - (b - a).normalized() * 0.6, BUILDINGS_MASK)
	return space.intersect_ray(q).is_empty()


# ------------------------------------------------------------ line life
func _fire(origin: Vector3) -> void:
	if line_state != Line.IDLE or stunned:
		return
	web_owner = "action"
	web_touch_id = -1
	line_state = Line.FLYING
	line_tip = origin
	line_will_hit = targeting.has_target
	if line_will_hit:
		s.position = global_position
		line_target = targeting.best_flyable(get_world_3d().direct_space_state, s, params, [get_rid()])
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
		SwingPhysics.release(s)
		swings += 1
		chain += 1
		best_chain = maxi(best_chain, chain)
		released.emit(s.velocity)
	line_state = Line.IDLE
	web_owner = ""
	web_touch_id = -1
	wraps.clear()


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


## Recovery is decided here (gameplay), not by the visual rig: dangling from
## the web the body shakes it off after 0.9 s; otherwise it gets up once it has
## come to rest on something; if wedged somewhere it respawns.
func _update_stun(dt: float) -> void:
	_stun_time += dt
	if is_on_floor() and speed() < 2.0:
		_settle_time += dt
	else:
		_settle_time = 0.0
	if (line_state == Line.ATTACHED and _stun_time > 0.9) or (_stun_time > 1.2 and _settle_time > 0.6):
		recover()
	elif _stun_time > 6.0:
		respawn()


func recover() -> void:
	if stunned:
		stunned = false
		stun_ended.emit()


func respawn(at: Variant = null) -> void:
	_let_go()
	stunned = false
	_grapple_held = true  # require a fresh press
	global_position = at if at is Vector3 else last_safe_position
	s.velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	_move_smooth = Vector3.ZERO
	s.position = global_position
	was_on_floor = false
	chain = 0
	respawned.emit()


func reset_stats() -> void:
	distance_travelled = 0.0
	swings = 0
	chain = 0
	best_chain = 0
	top_speed = 0.0
