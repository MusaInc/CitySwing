extends RefCounted
## Unit tests for the pure traversal model (no scene, no engine physics).

const DT := 1.0 / 60.0


func _params(drag := false) -> SwingParams:
	var p := SwingParams.new()
	if not drag:
		p.air_drag = 0.0
		p.linear_drag = 0.0
	p.max_fall_speed = 1000.0
	return p


func _pendulum(p: SwingParams, length: float, angle_deg: float) -> SwingPhysics.State:
	var s := SwingPhysics.State.new()
	var a := deg_to_rad(angle_deg)
	s.anchor = Vector3(0, 100, 0)
	s.position = s.anchor + Vector3(sin(a) * length, -cos(a) * length, 0)
	SwingPhysics.attach(s, s.anchor, p)
	s.taut = true
	return s


func test_free_fall_matches_kinematics(t) -> void:
	var p := _params()
	var s := SwingPhysics.State.new()
	s.position = Vector3(0, 500, 0)
	var c := SwingPhysics.Controls.new()
	for i in 60:
		SwingPhysics.step(s, c, p, DT)
	t.near(s.velocity.y, -p.gravity, 0.01, "v after 1 s")
	t.near(s.position.y, 500.0 - 0.5 * p.gravity, 0.15, "y after 1 s")


func test_small_angle_pendulum_period(t) -> void:
	var p := _params()
	var L := 20.0
	var s := _pendulum(p, L, 10.0)
	var c := SwingPhysics.Controls.new()
	var crossings: Array[float] = []
	var prev_x := s.position.x
	var time := 0.0
	while crossings.size() < 3 and time < 30.0:
		SwingPhysics.step(s, c, p, DT)
		time += DT
		if prev_x > 0.0 and s.position.x <= 0.0:
			crossings.append(time - DT * s.position.x / (s.position.x - prev_x))
		prev_x = s.position.x
	var expected := TAU * sqrt(L / p.gravity) * (1.0 + pow(deg_to_rad(10.0), 2) / 16.0)
	if t.check(crossings.size() == 3, "pendulum should oscillate"):
		t.near((crossings[2] - crossings[0]) / 2.0, expected, expected * 0.015, "period")


func test_large_swing_conserves_energy_without_drag(t) -> void:
	var p := _params()
	var s := _pendulum(p, 35.0, 75.0)
	var c := SwingPhysics.Controls.new()
	var e0 := SwingPhysics.energy(s, p)
	var worst := 0.0
	for i in 60 * 20:
		SwingPhysics.step(s, c, p, DT)
		worst = maxf(worst, absf(SwingPhysics.energy(s, p) - e0) / absf(e0 - p.gravity * (s.anchor.y - 35.0)))
	t.note("worst relative energy error over 20 s: %.4f%%" % (worst * 100.0))
	t.check(worst < 0.01, "energy drift should stay under 1% of swing energy")


func test_rope_never_stretches(t) -> void:
	var p := _params()
	var s := _pendulum(p, 30.0, 80.0)
	s.velocity = Vector3(0, 0, 25)  # conical, chaotic-ish motion
	var c := SwingPhysics.Controls.new()
	c.move = Vector3(1, 0, 0)
	var worst := 0.0
	for i in 600:
		SwingPhysics.step(s, c, p, DT)
		worst = maxf(worst, s.position.distance_to(s.anchor) - s.rope_length)
	t.check(worst < 0.001, "rope stretched by %.4f m" % worst)


func test_downswing_accelerates_naturally(t) -> void:
	var p := _params()
	var s := _pendulum(p, 30.0, 70.0)
	var c := SwingPhysics.Controls.new()
	var max_speed := 0.0
	for i in 120:
		SwingPhysics.step(s, c, p, DT)
		max_speed = maxf(max_speed, s.velocity.length())
	# Ideal: v = sqrt(2 g L (1 - cos θ)) at the bottom.
	var ideal := sqrt(2.0 * p.gravity * 30.0 * (1.0 - cos(deg_to_rad(70.0))))
	t.check(max_speed > ideal * 0.99 and max_speed <= ideal * 1.01,
		"bottom speed %.2f vs ideal %.2f" % [max_speed, ideal])


func test_slack_rope_is_free_fall(t) -> void:
	var p := _params()
	var s := SwingPhysics.State.new()
	s.position = Vector3(0, 0, 0)
	SwingPhysics.attach(s, Vector3(0, 20, 0), p)
	s.rope_length = 20.0
	s.velocity = Vector3(0, 10, 0)  # moving towards the anchor: rope slack
	var c := SwingPhysics.Controls.new()
	for i in 30:
		SwingPhysics.step(s, c, p, DT)
	t.near(s.velocity.y, 10.0 - p.gravity * 0.5, 0.01, "slack rope must not pull")
	t.check(not s.taut, "rope should be slack")


func test_slack_snap_is_inelastic(t) -> void:
	var p := _params()
	var s := SwingPhysics.State.new()
	s.position = Vector3(0, 0, 0)
	SwingPhysics.attach(s, Vector3(0, 20, 0), p)
	s.position = Vector3(0, 15, 0)  # 5 m of slack below the anchor
	var c := SwingPhysics.Controls.new()
	var snapped := false
	for i in 120:
		SwingPhysics.step(s, c, p, DT)
		snapped = snapped or s.snap_speed > 0.0
	t.check(snapped, "rope should snap taut when falling past its length")
	t.check(s.position.distance_to(s.anchor) <= 20.0001, "held by rope")
	t.check(absf(s.velocity.y) < 1.0, "no bounce after the jerk (vy=%.2f)" % s.velocity.y)


func test_release_preserves_velocity_exactly(t) -> void:
	var p := _params(true)
	var s := _pendulum(p, 30.0, 60.0)
	var c := SwingPhysics.Controls.new()
	for i in 50:
		SwingPhysics.step(s, c, p, DT)
	var v := s.velocity
	SwingPhysics.release(s)
	t.check(s.velocity == v, "release must not alter velocity")
	t.check(not s.attached, "detached")
	SwingPhysics.step(s, c, p, DT)
	var expected_vy := v.y - p.gravity * DT
	t.near(s.velocity.y, expected_vy, 0.05, "ballistic after release")


func test_reel_in_conserves_angular_momentum(t) -> void:
	var p := _params()
	p.gravity = 0.0  # isolate the rope: pure orbital motion
	var s := SwingPhysics.State.new()
	s.anchor = Vector3.ZERO
	s.position = Vector3(30, 0, 0)
	SwingPhysics.attach(s, s.anchor, p)
	s.taut = true
	s.velocity = Vector3(0, 0, 8)
	var c := SwingPhysics.Controls.new()
	var l0 := s.rope_length * s.velocity.length()
	c.reel = 1.0
	for i in 60:
		SwingPhysics.step(s, c, p, DT)
	var vt := s.velocity - s.position.normalized() * s.velocity.dot(s.position.normalized())
	var l1 := s.position.length() * vt.length()
	t.check(s.rope_length < 22.0, "rope reeled in (now %.1f)" % s.rope_length)
	t.near(l1, l0, l0 * 0.03, "angular momentum r·v_t")
	t.check(vt.length() > 10.0, "tangential speed increased by reeling")


func test_reel_pumping_adds_energy(t) -> void:
	# The skill move: reel in through the bottom, reel out at the ends.
	var p := _params(true)
	var passive := _pendulum(p, 30.0, 40.0)
	var pumped := _pendulum(p, 30.0, 40.0)
	var none := SwingPhysics.Controls.new()
	var c := SwingPhysics.Controls.new()
	for i in 60 * 12:
		SwingPhysics.step(passive, none, p, DT)
		var ang := (pumped.position - pumped.anchor).normalized().angle_to(Vector3.DOWN)
		# Shorten through the bottom (work against tension), lengthen near the
		# apex where the rope is almost unloaded.
		if ang < deg_to_rad(20.0):
			c.reel = 1.0
		elif pumped.velocity.length() < 5.0 and pumped.rope_length < 30.0:
			c.reel = -1.0
		else:
			c.reel = 0.0
		SwingPhysics.step(pumped, c, p, DT)
	var e_passive := SwingPhysics.energy(passive, p)
	var e_pumped := SwingPhysics.energy(pumped, p)
	t.note("energy passive %.0f vs pumped %.0f" % [e_passive, e_pumped])
	t.check(e_pumped > e_passive + 50.0, "well-timed reeling should out-gain a passive swing")


func test_drag_bleeds_energy_and_caps_speed(t) -> void:
	var p := _params(true)
	var s := SwingPhysics.State.new()
	s.position = Vector3(0, 10000, 0)
	var c := SwingPhysics.Controls.new()
	for i in 60 * 30:
		SwingPhysics.step(s, c, p, DT)
	var terminal := sqrt(p.gravity / p.air_drag)
	t.check(-s.velocity.y < terminal + 0.5, "terminal velocity respected (%.1f)" % -s.velocity.y)


func test_air_steering_has_limited_authority(t) -> void:
	var p := _params()
	var s := SwingPhysics.State.new()
	s.position = Vector3(0, 500, 0)
	s.velocity = Vector3(0, 0, 30)
	var c := SwingPhysics.Controls.new()
	c.move = Vector3(1, 0, 0)
	for i in 60:
		SwingPhysics.step(s, c, p, DT)
	t.check(s.velocity.x <= p.air_steer_accel * 1.0 + 0.01, "lateral dv bounded by accel·t (%.2f)" % s.velocity.x)
	t.near(s.velocity.z, 30.0, 0.001, "forward speed untouched by sideways steer")
	# Pushing forward cannot accelerate beyond the steer speed limit.
	c.move = Vector3(0, 0, 1)
	var vz := s.velocity.z
	for i in 120:
		SwingPhysics.step(s, c, p, DT)
	t.near(s.velocity.z, vz, 0.001, "no free thrust above air_steer_speed_limit")


func test_swing_steering_is_tangential(t) -> void:
	var p := _params()
	var s := _pendulum(p, 25.0, 0.0)
	var c := SwingPhysics.Controls.new()
	c.move = Vector3(0, 0, 1)
	for i in 60:
		SwingPhysics.step(s, c, p, DT)
	t.check(s.velocity.z > 1.0, "kick moves the swing")
	t.check(s.position.distance_to(s.anchor) <= 25.0001, "still on the rope")
	t.check(s.velocity.length() < p.swing_steer_accel * (1.0 + p.swing_pump_bonus) + 0.1, "kick is bounded")


func test_ground_run_and_jump(t) -> void:
	var p := _params()
	var s := SwingPhysics.State.new()
	s.grounded = true
	var c := SwingPhysics.Controls.new()
	c.move = Vector3(1, 0, 0)
	for i in 60:
		SwingPhysics.step(s, c, p, DT)
	t.near(s.velocity.x, p.run_speed, 0.01, "reaches run speed")
	c.jump = true
	SwingPhysics.step(s, c, p, DT)
	t.check(s.velocity.y > p.jump_speed * 0.9 and not s.grounded, "jump leaves the ground")


func test_overspeed_landing_keeps_flow(t) -> void:
	var p := _params()
	var s := SwingPhysics.State.new()
	s.grounded = true
	s.velocity = Vector3(30, 0, 0)
	var c := SwingPhysics.Controls.new()
	c.move = Vector3(1, 0, 0)
	SwingPhysics.step(s, c, p, 0.25)
	t.check(s.velocity.x > 25.0, "holding forward keeps most landing speed")
	c.move = Vector3.ZERO
	for i in 120:
		SwingPhysics.step(s, c, p, DT)
	t.check(s.velocity.length() < 0.5, "releasing the stick brakes to a stop")


func test_params_resource_loads(t) -> void:
	var p: SwingParams = load("res://config/swing_params.tres")
	t.check(p != null and p.gravity > 0.0, "config/swing_params.tres loads as SwingParams")


func test_attach_rejects_out_of_range(t) -> void:
	var p := _params()
	var s := SwingPhysics.State.new()
	t.check(not SwingPhysics.attach(s, Vector3(0, p.grapple_range + 1.0, 0), p), "too far")
	t.check(SwingPhysics.attach(s, Vector3(0, 30, 0), p), "in range")
	t.near(s.rope_length, 30.0, 0.001, "rope length = distance on attach")


func test_jump_is_high(t) -> void:
	var p := _params()
	var s := SwingPhysics.State.new()
	s.grounded = true
	var c := SwingPhysics.Controls.new()
	c.jump = true
	SwingPhysics.step(s, c, p, DT)
	c.jump = false
	var top := 0.0
	for i in 120:
		SwingPhysics.step(s, c, p, DT)
		top = maxf(top, s.position.y)
	t.note("jump apex %.1f m" % top)
	t.check(top > 6.0, "a powerful jump: apex above 6 m")


func test_auto_tighten_pumps_each_swing(t) -> void:
	# No input at all: the web tightens through the bottom of the arc and the
	# swing gains energy (angular momentum conserved – real work, no boost).
	var p := _params(true)
	var plain := _pendulum(p, 40.0, 45.0)
	var auto := _pendulum(p, 40.0, 45.0)
	var none := SwingPhysics.Controls.new()
	var c := SwingPhysics.Controls.new()
	var min_len := 40.0
	for i in 60 * 6:
		SwingPhysics.step(plain, none, p, DT)
		c.reel = SwingPhysics.auto_tighten(auto, p, 40.0)
		SwingPhysics.step(auto, c, p, DT)
		min_len = minf(min_len, auto.rope_length)
	var e_plain := SwingPhysics.energy(plain, p)
	var e_auto := SwingPhysics.energy(auto, p)
	t.note("energy without pull %.0f, with automatic pull %.0f; shortest line %.1f m" % [e_plain, e_auto, min_len])
	t.check(e_auto > e_plain + 40.0, "automatic pull pumps energy into the swing")
	t.check(min_len >= 40.0 * p.auto_tighten_min_fraction - 0.2, "never shorter than the minimum fraction")


func test_auto_tighten_keeps_the_arc_off_the_street(t) -> void:
	var p := _params()
	var s := SwingPhysics.State.new()
	s.anchor = Vector3(0, 40, 0)
	s.position = Vector3(30, 30, 0)  # 31.6 m line: the arc would bottom out at 8.4… then lower with momentum
	SwingPhysics.attach(s, s.anchor, p)
	s.rope_length = 38.0
	s.taut = true
	var c := SwingPhysics.Controls.new()
	var lowest := INF
	for i in 120:
		c.reel = SwingPhysics.auto_tighten(s, p, 38.0)
		SwingPhysics.step(s, c, p, DT)
		lowest = minf(lowest, s.position.y)
	t.note("lowest point %.1f m (clearance %.0f m)" % [lowest, p.swing_ground_clearance])
	t.check(lowest > 2.0, "the line winches in before the body reaches the street")


func test_running_turns_carry_momentum_and_reversals_brake(t) -> void:
	# A sprinter can't snap 90° or reverse on the spot: the heading swings
	# round over a few frames at full speed, and a reversal brakes first.
	var p := _params()
	var c := SwingPhysics.Controls.new()
	var v := Vector3(0, 0, -p.run_speed)
	c.move = Vector3.RIGHT
	var turned_at := -1.0
	for i in 60:
		v = SwingPhysics._ground_move(v, c, p, DT)
		if turned_at < 0.0 and Vector3(v.x, 0, v.z).normalized().dot(Vector3.RIGHT) > 0.97:
			turned_at = (i + 1) * DT
	var after_3 := Vector3(0, 0, -p.run_speed)
	for i in 3:
		after_3 = SwingPhysics._ground_move(after_3, c, p, DT)
	t.note("90° turn at %.0f m/s: lined up after %.2f s, %.0f° after 3 frames" % [
		p.run_speed, turned_at, rad_to_deg(Vector3.FORWARD.angle_to(Vector3(after_3.x, 0, after_3.z)))])
	t.check(turned_at > 0.15 and turned_at < 0.4, "a 90° turn at sprint takes a moment, not a frame")
	t.check(Vector3(v.x, 0, v.z).length() > p.run_speed * 0.95, "and keeps the speed")
	v = Vector3(0, 0, -p.run_speed)
	c.move = Vector3.BACK
	for i in 6:
		v = SwingPhysics._ground_move(v, c, p, DT)
	t.check(v.z < -2.0, "reversing brakes first (still moving forward after 0.1 s: %.1f m/s)" % -v.z)
	for i in 60:
		v = SwingPhysics._ground_move(v, c, p, DT)
	t.check(v.z > p.run_speed * 0.9, "then runs the other way")


func test_human_steering_turns_a_corner_in_the_air(t) -> void:
	# Full sideways stick at 25 m/s: the assist turns the travel (keeping
	# speed) fast enough to take a street corner; without it (the bots) the
	# raw model is unchanged and barely turns.
	var p := _params()
	var times := []
	for assist in [true, false]:
		var s := SwingPhysics.State.new()
		s.position = Vector3(0, 500, 0)
		s.velocity = Vector3(0, 0, -25)
		var c := SwingPhysics.Controls.new()
		c.turn_assist = assist
		c.move = Vector3.LEFT
		var at := -1.0
		for i in 240:
			SwingPhysics.step(s, c, p, DT)
			# 75°: the stick is camera-relative in play, so the turn doesn't ease
			# off like it does toward this fixed direction (tools/steer_test.gd).
			if at < 0.0 and Vector3.FORWARD.angle_to(Vector3(s.velocity.x, 0, s.velocity.z)) > deg_to_rad(75.0):
				at = (i + 1) * DT
		times.append(at)
		if assist:
			t.check(Vector3(s.velocity.x, 0, s.velocity.z).length() > 22.0, "the assisted turn keeps its speed")
	t.note("75° in the air at 25 m/s: assisted %.2f s, raw %s" % [times[0], "never" if times[1] < 0 else "%.2f s" % times[1]])
	t.check(times[0] > 0.0 and times[0] < 1.6, "assisted: a corner in well under 2 s")
	t.check(times[1] < 0.0 or times[1] > 3.0, "raw model (bots): unchanged, slow")
