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
## A limp body hit the ground (falling, thrown off a wall or by a vehicle):
## speed into the ground and where. Each bounce of the same crash fires again.
signal slammed(speed: float, point: Vector3)
## Hit by a vehicle ("car" / "train") – a knockout follows.
signal struck(kind: String, speed: float)
signal launched
signal stepped_up(height: float)
## Any contact with a wall or obstacle worth a visible reaction (visual only):
## speed into the surface and its normal.
signal bumped(speed: float, normal: Vector3)
## Ran into a wall on foot too slowly to run up it: the body is bounced back
## off it and staggers (the stick is ignored for STAGGER_TIME).
signal staggered(speed: float, normal: Vector3)
## Let go inside the sweet spot (see SwingParams "Release"). streak counts
## consecutive perfect releases without touching the ground.
signal perfect_release(streak: int)
## A player hit a facade at speed and is running on it (wall_run) / pushed
## off it back into the air / scrambled over a roof edge.
signal wall_run_started(normal: Vector3)
signal wall_run_launched
signal wall_topped

enum Line { IDLE, FLYING, ATTACHED }

const HAND_OFFSET := Vector3(0.0, 0.7, 0.0)
const BUILDINGS_MASK := 1 | (1 << 1)
const GRAPPLE_LAYER := 1 << 1
const MAX_WRAPS := 4
const STEP_MAX := 0.35  # kerbs, stairs and rooftop lips climbed while running
## In the air, a ledge whose walkable top is at most this far above the feet
## is mantled (roof edges, parapets, low roof plant) instead of stopping you.
const MANTLE_MAX := 2.0
## Wall hit on foot: at least this fast into the wall (and mostly head-on)
## knocks the body back a step; one stagger per STAGGER_COOL.
const STAGGER_SPEED := 4.5
const STAGGER_TIME := 0.42
const STAGGER_COOL := 1.4
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
## A scripted move (HomeSystem: window grab/climb/vault) is placing the body:
## the physics step is skipped while it does.
var scripted := false

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
var _bounces := 0  # ground bounces this crash (a limp body bounces twice, smaller each time)
## What knocked you out last: "wall", "car", "train".
var ko_cause := "wall"
## Velocity of the moving floor under the body (a train), zero otherwise.
var carry_velocity := Vector3.ZERO
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
## Gadgets (see Gadgets): off unless a player's gadget is running.
var glide := false       # off the web: slow sink, a little forward carry
const GLIDE_SINK := 3.5  # m/s
const GLIDE_GRAVITY := 0.18
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
## From a respawn until the first web is let go: wall knockouts become wall
## runs for human players (see _resolve_contacts).
var _first_swing_grace := false
var _launch_pending := false
## Touch finger still holding SWING with no target yet: fire as soon as one appears.
var _armed_touch := -1
var _prev_pos := Vector3.ZERO
var _bump_cool := 0.0
## Ground height at (x, z) (the city sets CityLayout.ground_y); flat 0 if unset.
var ground_fn: Callable
var stagger_t := 0.0  # > 0 while staggering back off a wall (no stick)
var _stagger_cool := 0.0
## Long reach (humans only): the higher you are and the faster you fall, the
## further a web reaches (m added to grapple_range), so a long drop off a
## supertall still finds a facade to catch. Bots and recorded courses keep
## the plain range.
## Wall running (players only): hit a facade at speed and the feet carry
## on over its surface – up it head-on, along it at an angle – for about a
## second, then push off back into the air with the speed kept. Not a climb:
## the run decelerates and always ends in a launch (JUMP: a bigger one).
## Near a roof edge the hands catch it and scramble over (_top_out).
var wall_run := false
var wall_normal := Vector3.ZERO
## 0 straight up the wall .. 1 running along it (animation, camera).
var wall_run_along := 0.0
## > 0 for a moment after a wall run (the camera holds its heading).
var wall_hold := 0.0
var _wr_t := 0.0
var _wr_up := 0.0
var _wr_side := Vector3.ZERO
var _wr_lost := 0.0
var _wr_cool := 0.0
var reach_extra := 0.0
const REACH_MAX_EXTRA := 50.0
var _rp: SwingParams  # params with the extended reach (see p_eff)


func _ready() -> void:
	if params == null:
		var settings := get_node_or_null("/root/Settings")
		params = settings.swing_params() if settings else load("res://config/swing_params.tres")
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 1) | (1 << 3) | CityWorld.PROPS_LAYER
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
	if hand.distance_to(point) > p_eff().grapple_range:
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
	# Response curve: most of the stick's travel is a walk-to-jog range, so
	# walking is easy to hold; only full deflection sprints.
	mv = mv.normalized() * pow(mv.length(), 2.8) if mv.length() > 0.001 else Vector2.ZERO
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


## The params in force this tick: `params`, or a copy with the long reach
## (and a rope that long allowed) while reach_extra is on or a long web is
## still attached.
func p_eff() -> SwingParams:
	var long_rope := s.attached and s.rope_length > params.max_rope_length
	if reach_extra < 0.5 and not long_rope:
		return params
	if _rp == null:
		_rp = params.duplicate()
	_rp.grapple_range = params.grapple_range + reach_extra
	_rp.max_rope_length = maxf(params.max_rope_length + reach_extra, s.rope_length if s.attached else 0.0)
	return _rp


func _update_reach(dt: float) -> void:
	var want := 0.0
	if controls.human and not is_on_floor() and not stunned:
		var h := height_above_ground()
		var fall := -s.velocity.y
		want = REACH_MAX_EXTRA * clampf(0.45 * clampf((h - 45.0) / 180.0, 0.0, 1.0)
			+ 0.75 * clampf((fall - 9.0) / 26.0, 0.0, 1.0), 0.0, 1.0)
	# Grows quickly as you drop, eases back once you're caught.
	reach_extra = move_toward(reach_extra, want, dt * (60.0 if want > reach_extra else 25.0))
	if reach_extra < 0.5 and not (s.attached and s.rope_length > params.max_rope_length):
		_rp = null  # (fresh copy next time: picks up any tuning edits)


## Height above the street / pavement below (the terrain isn't flat).
func height_above_ground() -> float:
	if ground_fn.is_valid():
		return global_position.y - float(ground_fn.call(global_position.x, global_position.z))
	return global_position.y


func _physics_process(dt: float) -> void:
	RenderingServer.global_shader_parameter_set(&"player_pos", global_position)  # pedestrians step aside
	if scripted:
		controls.jump = Input.is_action_just_pressed("jump") if bot == null else false
		return
	# Stun first: input read while stunned must never be applied after recovery.
	if stunned:
		_update_stun(dt)
	var inp := _read_input(dt)
	var move: Vector3 = inp.get("move", Vector3.ZERO)
	stagger_t = maxf(stagger_t - dt, 0.0)
	_stagger_cool = maxf(_stagger_cool - dt, 0.0)
	if stagger_t > 0.0:
		move = Vector3.ZERO  # knocked back: the legs catch the body first
	_move_smooth = _move_smooth.lerp(move, 1.0 - exp(-dt / MOVE_SMOOTH))
	controls.move = _move_smooth
	# Human steering turns the travel; bots/courses keep the raw model (a
	# review script can opt in with `human_steer` to move like a player).
	controls.turn_assist = bot == null or bot.get("human_steer") == true
	controls.human = controls.turn_assist
	targeting.human_assist = controls.human
	# Trains are solid (ride them!) for people only: bots and recorded
	# courses must not depend on where a train happens to be.
	set_collision_mask_value(6, controls.human)
	controls.reel = auto_tighten()
	controls.jump = inp.get("jump", false)
	controls.gravity_scale = 1.0
	if _from_swing and not s.attached and absf(s.velocity.y) < params.apex_window:
		# Hang at the top of the flight: time to pick the next anchor.
		var k := absf(s.velocity.y) / params.apex_window
		controls.gravity_scale = lerpf(params.apex_gravity_scale, 1.0, k * k)
	if glide and not s.attached and not is_on_floor():
		controls.gravity_scale = GLIDE_GRAVITY
		s.velocity.y = maxf(s.velocity.y, -GLIDE_SINK)
	aim_dir = inp.get("aim", aim_dir)
	if inp.get("respawn", false):
		respawn()
		return
	_update_reach(dt)
	var pe := p_eff()

	var origin := hand_position()
	targeting.update(get_world_3d().direct_space_state, origin, aim_dir, s.velocity, pe,
		is_on_floor(), [get_rid()], _move_smooth, reach_extra > 12.0)
	if line_state == Line.IDLE or line_state == Line.ATTACHED:
		targeting.refresh_pick(get_world_3d().direct_space_state, _launch_state(), pe, [get_rid()], dt)

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
			if wall_run:
				# Springing off a wall run: the run's speed carries on.
				_end_wall_run(true)
			wall_kicked.emit()
		elif line_state != Line.ATTACHED:
			trick.emit()  # purely visual acrobatics; no physics effect
		controls.jump = false

	_update_wall_run(dt, move)

	# Integrate the model from the body's real position.
	s.position = global_position
	s.grounded = is_on_floor() and not _launch_pending
	_launch_pending = false
	var start := global_position
	SwingPhysics.step(s, controls, p_eff(), dt)
	if s.snap_speed > 2.0:
		rope_snapped.emit(s.snap_speed)
	floor_snap_length = 0.0 if (s.attached or s.velocity.y > 0.5) else 0.4
	velocity = (s.position - start) / dt
	if s.grounded and not s.attached and s.velocity.y < 0.5:
		_try_step_up(velocity * dt)
	elif not s.grounded and not s.attached and not stunned:
		_try_mantle(velocity * dt)
	move_and_slide()
	# Riding something that moves (a train): the model's velocity is relative
	# to it while aboard. Landing on it takes its velocity off yours; leaving
	# it (jumping, running off, a web) keeps its speed on top of yours.
	var prev_carry := carry_velocity
	carry_velocity = get_platform_velocity() if is_on_floor() else Vector3.ZERO
	carry_velocity.y = 0.0
	if carry_velocity.length_squared() < 0.01:
		carry_velocity = Vector3.ZERO
	if prev_carry == Vector3.ZERO and carry_velocity != Vector3.ZERO:
		# (Forgiving: you catch the train's speed and at most a short skid
		# is left over, so a drop onto a roof sticks instead of throwing you
		# off the back.)
		var rel := s.velocity - carry_velocity
		var vy := s.velocity.y
		rel.y = 0.0
		s.velocity = rel.limit_length(4.0)
		s.velocity.y = vy
	elif prev_carry != Vector3.ZERO and carry_velocity == Vector3.ZERO:
		s.velocity += prev_carry
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


## Airborne and moving into a ledge (a roof edge with its cornice and
## parapet, a low roof hut) whose walkable top is within MANTLE_MAX of the
## feet: lift onto it and keep the horizontal momentum, rather than hitting
## the lip as a wall and sliding off or stalling just short of the roof.
## Probes a little ahead of the motion so the lip is met before contact.
## Facades (no top in reach) are walls as before.
func _try_mantle(motion: Vector3) -> void:
	var vh := Vector3(s.velocity.x, 0.0, s.velocity.z)
	if vh.length() < 2.0 or s.velocity.y > 7.0:
		return
	var probe := vh.normalized() * maxf(Vector3(motion.x, 0.0, motion.z).length(), 0.3)
	if not test_move(global_transform, probe):
		return
	var lift := 0.0
	var clear := false
	for i in range(1, 11):
		lift = minf(i * 0.2, MANTLE_MAX)
		if test_move(global_transform, Vector3.UP * lift):
			return  # no headroom (under a cornice, a skybridge)
		if not test_move(global_transform.translated(Vector3.UP * lift), probe):
			clear = true
			break
		if lift >= MANTLE_MAX:
			break
	if not clear:
		return
	var over := global_transform.translated(Vector3.UP * lift).translated(probe)
	var hit := KinematicCollision3D.new()
	if not test_move(over, Vector3.DOWN * (lift + 0.1), hit) or hit.get_normal().y < 0.7:
		return
	var rise := over.origin.y + hit.get_travel().y - global_position.y
	if rise < 0.05:
		return
	global_position = over.origin + hit.get_travel() + Vector3.UP * 0.01
	s.position = global_position
	s.velocity.y = maxf(s.velocity.y, 0.0)
	velocity = Vector3(s.velocity.x, 0.0, s.velocity.z) * 0.0  # this tick's motion was the mantle
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
		if into > 1.5 and n.y < 0.6 and _bump_cool <= 0.0 and not wall_run:
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
		if stunned:
			_slam(maxf(-pre_hit.y, speed_in), pre_hit)
			was_on_floor = on_floor
			return
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
			_slam(maxf(-pre_hit.y, speed_in), pre_hit)
	elif on_floor:
		on_street = floor_street
	# Players: a facade hit at speed (not a head-on knockout) becomes a wall
	# run that keeps the momentum, as long as the stick isn't pulling away.
	if controls.human and not stunned and not wall_run and _wr_cool <= 0.0 and wall_n != Vector3.ZERO \
			and absf(wall_n.y) < 0.3 and worst_into >= params.wall_run_min_speed \
			and not (worst_into >= params.wall_run_max_speed and wall_ratio >= params.wall_glance_ratio) \
			and controls.move.length() > 0.3 \
			and controls.move.normalized().dot(Vector3(wall_n.x, 0.0, wall_n.z).normalized()) < 0.2:
		_start_wall_run(wall_n, pre_hit, worst_into)
		was_on_floor = on_floor
		return
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
	elif facade and worst_into >= params.wall_run_max_speed and not (_first_swing_grace and controls.human):
		# Head-on and fast: knocked out. (Not on a player's first web after a
		# spawn: holding SWING from a standstill must never end in a knockout;
		# that hit becomes the wall run below.)
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
	elif wall_n != Vector3.ZERO and was_on_floor and not stunned and worst_into >= STAGGER_SPEED \
			and wall_ratio > 0.55 and _stagger_cool <= 0.0 and line_state != Line.ATTACHED:
		# On foot, head-on into a wall: knocked back a step off it.
		var out := Vector3(wall_n.x, 0.0, wall_n.z).normalized()
		var along := s.velocity - out * s.velocity.dot(out)
		along.y = 0.0
		s.velocity = along * 0.35 + out * clampf(worst_into * 0.28, 1.6, 3.4)
		s.velocity.y = maxf(s.velocity.y, 1.6)
		stagger_t = STAGGER_TIME
		_stagger_cool = STAGGER_COOL
		staggered.emit(worst_into, wall_n)
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
			s.velocity += fwd * 8.0
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
			st.velocity += fwd * 8.0
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
		line_target = targeting.best_flyable(get_world_3d().direct_space_state, s, p_eff(), [get_rid()])
		if bot != null and bot.has_method("choose_anchor"):
			line_target = bot.choose_anchor(self, line_target)  # title-screen pilot
	else:
		line_target = origin + aim_dir.normalized() * p_eff().grapple_range * 0.8
	grapple_fired.emit(line_target, line_will_hit)


func _advance_line(dt: float, _origin: Vector3) -> void:
	if line_state != Line.FLYING:
		return
	var to := line_target - line_tip
	var step := params.line_speed * dt
	# A web is a straight line from the hand: if the body has moved so that
	# something now stands between the hand and the tip's next position, the
	# web sticks to what it meets (or misses) – it never passes through it.
	var hand := hand_position()
	var next := line_tip + to.normalized() * minf(step, to.length())
	var q := PhysicsRayQueryParameters3D.create(hand, next, BUILDINGS_MASK | (1 << 3), [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and (hit["position"] as Vector3).distance_to(line_target) > 0.6:
		var col: Object = hit["collider"]
		var grappleable := col is CollisionObject3D and ((col as CollisionObject3D).collision_layer & GRAPPLE_LAYER) != 0
		line_tip = hit["position"]
		if line_will_hit and grappleable and hand.distance_to(line_tip) <= p_eff().grapple_range \
				and SwingPhysics.attach(s, line_tip, _range_tolerant()):
			line_target = line_tip
			wraps.clear()
			_attach_length = s.rope_length
			line_state = Line.ATTACHED
			attached.emit(line_target)
		else:
			line_state = Line.IDLE
			web_owner = ""
			grapple_missed.emit()
		return
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
	var pe := p_eff()
	if s.position.distance_to(line_target) <= pe.grapple_range:
		return pe
	var p: SwingParams = pe.duplicate()
	p.grapple_range *= 1.1
	return p


func _let_go() -> void:
	if line_state == Line.ATTACHED:
		var perfect := is_perfect_release()
		var fling := controls.human and s.taut and not stunned and s.velocity.y > 0.0 and s.velocity.length() > 10.0 \
			and s.velocity.length() < params.flow_cruise_speed
		SwingPhysics.release(s)
		if fling:
			# Players: letting go on the way up throws you on out of the arc.
			s.velocity *= params.flow_release_boost
			s.velocity.y += params.flow_release_lift
		if perfect:
			s.velocity *= params.perfect_release_boost
			s.velocity.y += params.perfect_release_lift
		swings += 1
		_first_swing_grace = false
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


func _start_wall_run(n: Vector3, pre: Vector3, into: float) -> void:
	if line_state != Line.IDLE:
		_let_go()
	wall_normal = Vector3(n.x, 0.0, n.z).normalized()
	var side := pre - wall_normal * pre.dot(wall_normal)
	side.y = 0.0
	# The speed going into the wall turns upward (a head-on hit runs up it),
	# the speed along it carries on (a glancing one runs across it).
	_wr_side = side * 0.92
	_wr_up = clampf(into * 0.7 + maxf(pre.y, 0.0) * 0.5, 7.0, 17.0)
	wall_run_along = clampf(_wr_side.length() / maxf(_wr_side.length() + _wr_up, 0.1), 0.0, 1.0)
	_wr_t = 0.0
	_wr_lost = 0.0
	wall_run = true
	wall_hold = 0.8
	wall_run_started.emit(wall_normal)


## Push off the wall back into the air: along-speed kept, out and up.
## JUMP (strong) throws further and higher than running out of wall.
func _end_wall_run(strong: bool) -> void:
	if not wall_run:
		return
	wall_run = false
	_wr_cool = 0.45
	var out := params.wall_run_launch_out * (1.4 if strong else 1.0)
	var lift := params.wall_run_launch_up * (1.35 if strong else 1.0)
	s.velocity = _wr_side + wall_normal * out
	s.velocity.y = maxf(_wr_up, 0.0) * 0.6 + lift
	_from_swing = true  # apex hang time to line up the next web
	wall_run_launched.emit()


## Wall runs in progress, and the ledge scramble. Bots and courses never
## wall-run.
func _update_wall_run(dt: float, move: Vector3) -> void:
	_wr_cool = maxf(_wr_cool - dt, 0.0)
	wall_hold = maxf(wall_hold - dt, 0.0)
	if not controls.human or stunned or line_state == Line.ATTACHED:
		wall_run = false
		return
	var n := Vector3.ZERO
	if is_on_wall():
		var wn := get_wall_normal()
		if absf(wn.y) < 0.3:
			n = Vector3(wn.x, 0.0, wn.z).normalized()
	if not wall_run:
		# Scramble: slow, in the air at a wall with its top just above.
		if n != Vector3.ZERO and not is_on_floor() and s.velocity.y < 5.0 and move.length() > 0.4 \
				and move.dot(-n) > 0.45:
			wall_normal = n
			_top_out()
		return
	wall_hold = 0.8
	_wr_t += dt
	if n != Vector3.ZERO:
		wall_normal = wall_normal.slerp(n, 0.3).normalized()
		_wr_lost = 0.0
	else:
		# Off the top (scramble over the lip), or past the wall's end.
		if _top_out():
			wall_run = false
			_wr_cool = 0.3
			return
		_wr_lost += dt
		if _wr_lost > 0.12:
			_end_wall_run(false)
			return
	if is_on_ceiling() or _wr_t > params.wall_run_time or move.length() > 0.3 and move.dot(wall_normal) > 0.5:
		_end_wall_run(false)  # out of run (or steering away): push off
		return
	_wr_up -= params.wall_run_up_decel * dt
	_wr_side = _wr_side.move_toward(Vector3.ZERO, params.wall_run_side_decel * dt)
	if _wr_up < -2.0 and _wr_side.length() < 4.0:
		_end_wall_run(false)
		return
	wall_run_along = lerpf(wall_run_along, clampf(_wr_side.length() / maxf(_wr_side.length() + absf(_wr_up), 0.1), 0.0, 1.0), 1.0 - exp(-6.0 * dt))
	s.velocity = _wr_side - wall_normal * 2.0
	s.velocity.y = _wr_up + params.gravity * dt  # the step's gravity takes this back off
	_launch_pending = true  # off the ground: no ground move this tick


## Climbing past the top edge of a wall: find the roof just over the lip
## (feet up to 5 m higher, up to a metre in) and scramble onto it. A cornice
## overhanging the top is reached round: out from the wall first (≤1.5 m).
func _top_out() -> bool:
	for out: float in [0.0, 0.5, 1.0, 1.5]:
		var base := global_transform
		if out > 0.0:
			if test_move(base, wall_normal * out):
				return false
			base = base.translated(wall_normal * out)
		var inward := -wall_normal * (0.9 + out)
		for i in range(1, 14):
			var lift := i * 0.4
			if test_move(base, Vector3.UP * lift):
				break  # no headroom here: try further out
			var up_xf := base.translated(Vector3.UP * lift)
			if test_move(up_xf, inward):
				continue
			var over := up_xf.translated(inward)
			var hit := KinematicCollision3D.new()
			if not test_move(over, Vector3.DOWN * (lift + 0.5), hit) or hit.get_normal().y < 0.7:
				return false
			var rise := over.origin.y + hit.get_travel().y - global_position.y
			global_position = over.origin + hit.get_travel() + Vector3.UP * 0.02
			s.position = global_position
			s.velocity = -wall_normal * 4.5 + _wr_side * 0.5
			velocity = Vector3.ZERO
			wall_topped.emit()
			if rise > 0.05:
				stepped_up.emit(rise)
			return true
	return false


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
	return SwingPhysics.auto_tighten(s, params, _attach_length, controls.human)


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
	_bounces = 0
	stun_started.emit(impact_speed)


## A limp body meets the ground: it lands flat with a thud, bounces once or
## twice (smaller each time) and skids out its speed along the ground,
## instead of stopping dead on the spot. (The bounce is for people only:
## bots and recorded courses keep the plain model.)
func _slam(into: float, pre: Vector3) -> void:
	if into < 4.0:
		return
	slammed.emit(into, global_position + Vector3.DOWN * 0.9)
	if not controls.human or _bounces >= 2 or into < 7.0:
		return
	_bounces += 1
	var vh := Vector3(pre.x, 0.0, pre.z)
	s.velocity = vh * (0.72 if _bounces == 1 else 0.55)
	s.velocity.y = clampf(into * 0.16, 1.8, 5.5) / _bounces
	_launch_pending = true  # off the floor next step


## Hit by a vehicle moving at `vel` (people only; see VehicleHits). The body
## is thrown along with it and up, limp: a knockout.
func hit_by(kind: String, vel: Vector3) -> void:
	if stunned or scripted or not controls.human:
		return
	var spd := vel.length()
	var dir := Vector3(vel.x, 0.0, vel.z).normalized()
	if dir.length_squared() < 0.5:
		return
	_let_go()
	ko_cause = kind
	ko_normal = dir
	ko_velocity = s.velocity
	s.velocity = dir * (spd * 1.15 + 2.0) + Vector3.UP * clampf(3.0 + spd * 0.3, 4.0, 9.0)
	velocity = s.velocity
	_launch_pending = true
	chain = 0
	perfect_streak = 0
	knocked_out = true
	struck.emit(kind, spd)
	knockout.emit(spd, dir)
	stun(spd * 1.6)


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
	ko_cause = "wall"
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
	scripted = false
	_armed_touch = -1
	_launch_pending = false
	stunned = false
	knocked_out = false
	_grapple_held = true  # require a fresh press
	wall_run = false
	wall_hold = 0.0
	_wr_cool = 0.0
	_first_swing_grace = true
	global_position = at if at is Vector3 else last_safe_position
	s.velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	_move_smooth = Vector3.ZERO
	stagger_t = 0.0
	_stagger_cool = 0.0
	reach_extra = 0.0
	_rp = null
	carry_velocity = Vector3.ZERO
	s.position = global_position
	was_on_floor = false
	chain = 0
	perfect_streak = 0
	_from_swing = false
	respawned.emit()


## A gadget's push (jet boots): added to the velocity, and off the ground.
func boost(v: Vector3) -> void:
	if line_state != Line.IDLE:
		_let_go()
	s.velocity += v
	_launch_pending = true


func reset_stats() -> void:
	distance_travelled = 0.0
	swings = 0
	chain = 0
	best_chain = 0
	perfects = 0
	top_speed = 0.0
