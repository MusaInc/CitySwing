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
			var arm := -(rig.bones["upper_arm_r"] as Node3D).global_basis.y
			var to_anchor := (player.s.anchor - (rig.bones["upper_arm_r"] as Node3D).global_position).normalized()
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
			if not q.is_finite() or (b != "upper_arm_r" and q.get_angle() > 3.0):
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


func test_crash_ragdolls_then_recovers(t) -> void:
	# Fly into the tower's south face hard, off the rope.
	player.respawn(Vector3(0, 40, -10))
	await get_tree().physics_frame
	player.s.velocity = Vector3(0, 0, -40)
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
	func drive(_p, _dt) -> Dictionary:
		return {"move": Vector3.ZERO, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}
