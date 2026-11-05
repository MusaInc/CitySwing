extends Node
## Character pose, spring stability, ragdoll and recovery, and isolation of the
## animated body from the gameplay physics.

var world: Node3D
var player: Player
var rig: CharacterRig


func setup() -> void:
	world = Node3D.new()
	add_child(world)
	PrototypeWorld.add_box(world, Vector3(0, -0.5, 0), Vector3(600, 1, 600), Color.GRAY, false, true)
	PrototypeWorld.add_box(world, Vector3(0, 40, -40), Vector3(16, 80, 16), Color.WHITE)
	PrototypeWorld.add_box(world, Vector3(0, 15, 30), Vector3(30, 30, 30), Color.WHITE)  # a roof to land on
	player = Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	add_child(player)
	player.bot = _Idle.new()
	rig = CharacterRig.new()
	player.add_child(rig)
	rig.set_player(player)
	await get_tree().physics_frame


func teardown() -> void:
	player.queue_free()
	world.queue_free()
	await get_tree().process_frame


func _up_of(bone: String) -> Vector3:
	return (rig.bones[bone] as Node3D).global_basis.y.normalized()


func test_hangs_along_the_rope_and_reaches_for_the_anchor(t) -> void:
	player.respawn(Vector3(0, 40, -20))
	await get_tree().physics_frame
	player.fire_at(Vector3(0, 70, -32.0), 1)
	var worst_body := 0.0
	var worst_arm := 0.0
	var samples := 0
	for i in 150:
		await get_tree().process_frame
		if i > 40 and player.line_state == Player.Line.ATTACHED and player.s.taut:
			var rope := (player.s.anchor - player.global_position).normalized()
			worst_body = maxf(worst_body, rad_to_deg(_up_of("chest").angle_to(rope)))
			var ua := "upper_arm_" + String(rig.web_side)  # (either hand can hold the web)
			var arm := -(rig.bones[ua] as Node3D).global_basis.y
			var to_anchor := (player.s.anchor - (rig.bones[ua] as Node3D).global_position).normalized()
			worst_arm = maxf(worst_arm, rad_to_deg(arm.angle_to(to_anchor)))
			samples += 1
	t.note("swinging: worst torso-vs-rope %.0f°, worst web-arm-vs-anchor %.0f° over %d frames" % [worst_body, worst_arm, samples])
	t.check(samples > 50, "swing sampled")
	t.check(worst_body < 40.0, "torso hangs along the line of tension")
	t.check(worst_arm < 25.0, "web arm points up the line")


func test_fast_dive_stretches_out_head_first(t) -> void:
	player.respawn(Vector3(0, 300, 200))
	player.s.velocity = Vector3(0, -35, -20)
	for i in 50:
		await get_tree().process_frame
		player.s.velocity = Vector3(0, -35, -20)  # hold the dive for the pose
	var along := rad_to_deg(rig.global_basis.y.angle_to(player.s.velocity.normalized()))
	t.note("dive: body axis vs velocity %.0f°" % along)
	t.check(along < 45.0, "body extends along the dive direction")


func test_springs_stay_stable_and_bounded(t) -> void:
	player.respawn(Vector3(0, 40, -20))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var bad := 0
	for i in 400:
		if i % 40 == 0:
			if player.line_state == Player.Line.IDLE:
				player.fire_at(Vector3(rng.randf_range(-7, 7), 70, -32.0), 1)
			else:
				player.release_web()
			player.s.velocity += Vector3(rng.randf_range(-20, 20), rng.randf_range(-10, 20), rng.randf_range(-20, 20))
		await get_tree().process_frame
		for b in rig.bones:
			var q: Quaternion = (rig.bones[b] as Node3D).quaternion
			# q and -q are the same rotation: measure the shortest angle.
			var ang := 2.0 * acos(clampf(absf(q.w), 0.0, 1.0))
			if not q.is_finite() or (b != "upper_arm_" + String(rig.web_side) and ang > 3.0):  # (the web arm reaches straight up)
				bad += 1
	t.check(bad == 0, "no NaN or extreme joint angles (%d bad samples)" % bad)


func test_animation_never_affects_physics(t) -> void:
	# Two players at once (players never collide with each other), identical
	# scripted inputs; only one has a rig. Their trajectories must match exactly.
	var bare := Player.new()
	bare.params = player.params.duplicate()
	add_child(bare)
	bare.bot = _Idle.new()
	for p in [player, bare]:
		p.respawn(Vector3(0, 40, -20))
	await get_tree().physics_frame
	for p in [player, bare]:
		p.fire_at(Vector3(0, 70, -32.0), 1)
	for i in 120:
		await get_tree().physics_frame
	for p in [player, bare]:
		p.release_web()
	for i in 30:
		await get_tree().physics_frame
	t.check(player.global_position.is_equal_approx(bare.global_position),
		"rig does not change the physics (%s vs %s)" % [player.global_position, bare.global_position])
	bare.queue_free()


func test_slow_head_on_wall_hit_becomes_a_wall_run(t) -> void:
	# Survivable head-on hit (between hard_impact_speed and wall_run_max_speed).
	player.respawn(Vector3(0, 40, -24))
	await get_tree().physics_frame
	player.s.velocity = Vector3(0, 2, -19)
	var top := 0.0
	var stunned := false
	var hit_y := 0.0
	for i in 150:  # the face is ~8 m away: hit after ~0.4 s, then the run up
		await get_tree().physics_frame
		if hit_y == 0.0 and player.global_position.z < -30.5:
			hit_y = player.global_position.y
		top = maxf(top, player.global_position.y)
		stunned = stunned or player.stunned
	t.check(not stunned, "no knockout at 19 m/s head-on")
	t.note("wall run peak %.1f m above the hit" % (top - hit_y))
	t.check(top > hit_y + 2.0, "runs up the facade")


## Shared: fly head-on into the tower face at `speed`, optionally pressing
## JUMP `jump_before` seconds before contact. Returns what happened.
func _wall_hit(speed: float, jump_before := -1.0) -> Dictionary:
	var drive := _Idle.new()
	player.bot = drive
	player.respawn(Vector3(0, 40, -20))
	await get_tree().physics_frame
	player.s.velocity = Vector3(0, 1, -speed)
	var res := {"ko": false, "saved": false, "bounce_z": 0.0, "down": 0.0, "ragdoll": false, "head_out": 0.0}
	var on_ko := func(_s, _n): res["ko"] = true
	var on_save := func(_s): res["saved"] = true
	player.knockout.connect(on_ko)
	player.wall_saved.connect(on_save)
	var hit_at := 12.0 / speed  # face at z = -32
	var t := 0.0
	var head0 := INF
	for i in 60 * 6:
		drive.jump = jump_before >= 0.0 and absf(t - (hit_at - jump_before)) < 0.5 / 60.0
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if res["ko"] and res["bounce_z"] == 0.0:
			res["bounce_z"] = player.s.velocity.z
		if rig.ragdolling:
			res["ragdoll"] = true
			# Head relative to the pelvis, along the wall normal (+z here).
			var rel: float = (rig.ragdoll.pos["head"] as Vector3).z - (rig.ragdoll.pos["pelvis"] as Vector3).z
			if head0 == INF:
				head0 = rel
			res["head_out"] = maxf(res["head_out"], rel - head0)
		if player.stunned:
			res["down"] += 1.0 / 60.0
		elif res["down"] > 0.0:
			break
	player.knockout.disconnect(on_ko)
	player.wall_saved.disconnect(on_save)
	player.bot = _Idle.new()
	return res


func test_fast_head_on_wall_hit_knocks_you_out(t) -> void:
	var r := await _wall_hit(35.0)
	t.note("knockout at 35 m/s: bounced %.1f m/s off the wall, head thrown %.2f m back relative to the hips, down %.1f s" % [
		r["bounce_z"], r["head_out"], r["down"]])
	t.check(r["ko"] and r["ragdoll"], "knocked out: the body goes limp")
	t.check(r["bounce_z"] > 1.0, "bounces off the facade, not stuck to it")
	t.check(r["head_out"] > 0.15, "the head snaps back off the impact (whiplash)")
	t.check(r["down"] >= player.params.knockout_time, "stays down at least knockout_time")


func test_timed_jump_kicks_off_instead(t) -> void:
	var early := await _wall_hit(35.0, 0.5)   # too early: the window has closed
	var timed := await _wall_hit(35.0, 0.1)
	t.note("JUMP 0.5 s early: ko=%s; 0.1 s before: saved=%s ko=%s" % [early["ko"], timed["saved"], timed["ko"]])
	t.check(early["ko"] and not early["saved"], "jumping too early does not save you")
	t.check(timed["saved"] and not timed["ko"], "JUMP just before the wall kicks off it")


func test_knockout_hit_stop_restores_time(t) -> void:
	var fx := ImpactFx.new()
	add_child(fx)
	fx.knockout(35.0)
	t.check(Engine.time_scale < 0.1, "the hit freezes the action")
	var slow_seen := false
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 2500 and Engine.time_scale < 1.0:
		await get_tree().process_frame
		slow_seen = slow_seen or (Engine.time_scale > 0.2 and Engine.time_scale < 0.5)
	var took := (Time.get_ticks_msec() - start) / 1000.0
	t.note("hit-stop + slow motion lasted %.2f s of real time" % took)
	t.check(slow_seen, "then plays out in slow motion")
	t.check(Engine.time_scale == 1.0 and took < 1.6, "and returns to full speed")
	fx.knockout(35.0)
	fx.cancel()
	t.check(Engine.time_scale == 1.0, "cancel restores time at once (respawn / pause)")
	fx.queue_free()


func test_crash_ragdolls_then_recovers(t) -> void:
	# Fly into the tower's south face very hard, off the rope.
	player.respawn(Vector3(0, 40, -10))
	await get_tree().physics_frame
	player.s.velocity = Vector3(0, 0, -player.params.wall_run_max_speed - 8.0)
	var ragdolled := false
	var worst := 0.0
	for i in 60:
		await get_tree().physics_frame
		if rig.ragdolling:
			ragdolled = true
			worst = maxf(worst, rig.ragdoll.max_stretch())
	t.check(ragdolled and player.stunned, "hard impact goes limp")
	t.check(player.line_state == Player.Line.IDLE, "nothing to hold in free flight")
	var recovered_at := -1.0
	for i in 60 * 8:
		await get_tree().physics_frame
		if rig.ragdolling:
			worst = maxf(worst, rig.ragdoll.max_stretch())
		if not player.stunned:
			recovered_at = i / 60.0
			break
	t.note("ragdoll worst link stretch %.1f%%, recovered %.1f s after the fall started" % [worst * 100.0, recovered_at])
	t.check(worst < 0.08, "limbs never stretch more than 8%")
	t.check(recovered_at > 0.0, "gets back up (or respawns) after settling")
	t.check(not rig.ragdolling, "rig back to animated control")


func test_crash_on_the_rope_keeps_the_web(t) -> void:
	player.respawn(Vector3(0, 50, -26))
	await get_tree().physics_frame
	player.fire_at(Vector3(0, 79.9, -32.0), 2)  # anchor on the roof edge above
	for i in 20:
		await get_tree().physics_frame
	player.stun(30.0)
	await get_tree().physics_frame
	t.check(player.line_state == Player.Line.ATTACHED, "clenched hand keeps the web through the crash")
	for i in 70:
		await get_tree().physics_frame
	t.check(not player.stunned, "dangling body shakes it off within ~1 s")


class _Idle:
	extends RefCounted
	var jump := false
	func drive(_p, _dt) -> Dictionary:
		return {"move": Vector3.ZERO, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": jump}


## Hoodie secondary motion: the fabric trails the motion through the air,
## stays within its bounds, and settles (not frozen, not drifting) standing.
func test_clothing_trails_motion_and_settles(t) -> void:
	player.respawn(Vector3(0, 60, 60))
	await get_tree().physics_frame
	player.s.velocity = Vector3(0, -2, -24)  # flying fast toward -z
	var trail := 0.0
	var worst := 0.0
	for i in 30:
		player.s.velocity.z = -24.0
		await get_tree().process_frame
		trail = rig.cloth.z
		worst = maxf(worst, rig.cloth.length())
	t.check(trail > 0.05, "hem streams back against the flight (cloth.z %.3f m)" % trail)
	t.check(worst <= CharacterRig.CLOTH_MAX * 1.15 + 1e-3, "cloth offset bounded (%.3f m)" % worst)
	# Standing on the ground: it settles to a small breeze offset.
	player.respawn(Vector3(20, 1.0, -120))
	for i in 180:
		await get_tree().process_frame
	t.check(rig.cloth.length() < 0.05, "standing, the hoodie hangs (cloth %.3f m)" % rig.cloth.length())
	t.note("flying trail %.3f m, standing %.3f m" % [trail, rig.cloth.length()])


## Standing still the hero keeps living: idle actions come by themselves
## within ~15 s and breathing follows exertion.
func test_idle_has_life(t) -> void:
	player.respawn(Vector3(20, 1.0, -120))
	rig.exert = 0.0
	var seen := {}
	for i in 60 * 16:
		await get_tree().process_frame
		if rig.idle_action != "":
			seen[rig.idle_action] = true
	t.check(seen.size() >= 1, "idle actions played: %s" % str(seen.keys()))
	t.note("idle actions in 16 s: %s" % str(seen.keys()))


## Landing moving sideways to the facing: an off-balance catch, not a
## frozen pose; landing straight on doesn't trigger it.
func test_sideways_landing_stumbles(t) -> void:
	player.respawn(Vector3(20, 4.5, -120))
	await get_tree().physics_frame
	player.s.velocity = Vector3(9, 0, 0)
	var seen := 0.0
	for i in 90:
		if not player.is_on_floor():
			rig.set_facing(Vector3.FORWARD)  # the body still twisted the other way
		await get_tree().process_frame
		seen = maxf(seen, rig.stumble_t)
	t.check(seen > 0.0, "sideways landing → stumble (%.2f s)" % seen)
	player.respawn(Vector3(20, 4.5, -120))
	await get_tree().physics_frame
	player.s.velocity = Vector3(0, 0, -9)
	rig.set_facing(Vector3.FORWARD)
	seen = 0.0
	for i in 90:
		await get_tree().process_frame
		seen = maxf(seen, rig.stumble_t)
	t.check(seen == 0.0, "landing straight on → no stumble")
