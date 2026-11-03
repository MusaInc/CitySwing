extends Node
## Random rooftop spawns in the real generated city, and camera behaviour.

var world: CityWorld


func setup() -> void:
	if world == null:
		world = CityWorld.new()
		add_child(world)
		await get_tree().physics_frame


func test_random_rooftops_are_valid_and_varied(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var space := get_viewport().world_3d.direct_space_state
	var seen := {}
	var bad: Array[String] = []
	var last := Vector3.INF
	var repeats := 0
	for i in 40:
		var spot := world.random_rooftop(rng, last)
		var p: Vector3 = spot["position"]
		if last != Vector3.INF and p.distance_to(last) < 150.0:
			repeats += 1
		last = p
		seen[p.snapped(Vector3.ONE)] = true
		# Standing on a building roof (grappleable layer), feet just above it.
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 5.0, 1 << 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or absf((p.y - 0.95) - (hit["position"] as Vector3).y) > 0.1:
			bad.append("not on a roof at %s" % p)
			continue
		if spot["height"] < 50.0 or spot["height"] > 150.0:
			bad.append("height %.0f" % spot["height"])
		# Edge clearance: 4 m of roof in every direction.
		for d in [Vector3(4, 0, 0), Vector3(-4, 0, 0), Vector3(0, 0, 4), Vector3(0, 0, -4)]:
			var e := PhysicsRayQueryParameters3D.create(p + d + Vector3.UP * 0.5, p + d + Vector3.DOWN * 3.0, 1 << 1)
			if space.intersect_ray(e).is_empty():
				bad.append("edge within 4 m at %s" % p)
		# Prop clearance.
		for pr in world.layout.props:
			if pr[0] in CityWorld.PROP_CLEARANCE:
				var o: Vector3 = pr[1].origin
				if absf(o.y - spot["height"]) < 1.0 and Vector2(o.x - p.x, o.z - p.z).length() < CityWorld.PROP_CLEARANCE[pr[0]] - 0.01:
					bad.append("%s too close at %s" % [pr[0], p])
		if is_nan(spot["yaw"]):
			bad.append("no heading")
	t.note("%d candidate roofs; 40 picks gave %d distinct spots, %d consecutive repeats" % [
		world.rooftop_spawns().size(), seen.size(), repeats])
	t.check(bad.is_empty(), "every spawn valid: %s" % [bad.slice(0, 4)])
	t.check(seen.size() >= 25, "spawns vary")
	t.check(repeats == 0, "consecutive runs start somewhere different")


func test_player_stands_on_spawn_roof(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var p := Player.new()
	p.params = load("res://config/swing_params.tres").duplicate()
	add_child(p)
	p.bot = _Idle.new()
	var ok := 0
	var spot := {}
	for i in 6:
		spot = world.random_rooftop(rng)
		p.respawn(spot["position"])
		for f in 45:
			await get_tree().physics_frame
		var settled: bool = p.is_on_floor() and not p.on_street and absf(p.global_position.y - spot["position"].y) < 0.2
		if settled:
			ok += 1
		else:
			t.note("spawn %s ended at %s floor=%s" % [spot["position"], p.global_position, p.is_on_floor()])
	t.check(ok == 6, "standing naturally on the roof every time (%d/6)" % ok)
	# Walk, run and jump from the rooftop, along the spawn heading (the roof's
	# clear run-up; lots are turned to their streets, so not always north).
	var start := p.global_position
	var run := _Run.new()
	# Across the roof: the first of 8 headings with roof under it 6 m ahead
	# (the spawn heading itself points off the edge, at the swing route).
	var space := get_viewport().world_3d.direct_space_state
	for k in 8:
		var d := Vector3.FORWARD.rotated(Vector3.UP, float(spot.get("yaw", 0.0)) + PI + k * TAU / 8.0)
		var q := PhysicsRayQueryParameters3D.create(start + d * 6.0 + Vector3.UP, start + d * 6.0 + Vector3.DOWN * 3.0)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and absf((hit["position"] as Vector3).y - (start.y - 0.95)) < 0.5:
			run.dir = d
			break
	p.bot = run
	var jumped := false
	for f in 60:
		await get_tree().physics_frame
		jumped = jumped or p.global_position.y > start.y + 0.8
	t.note("spot %s; roof run from %s yaw %.0f° to %s (floor=%s)" % [(spot["position"] as Vector3).snapped(Vector3.ONE * 0.1), start.snapped(Vector3.ONE * 0.1), rad_to_deg(float(spot.get("yaw", 0.0))),
		p.global_position.snapped(Vector3.ONE * 0.1), p.is_on_floor()])
	t.check(Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length() > 4.0, "can run on the roof")
	t.check(jumped, "can jump on the roof")
	p.queue_free()


func test_holding_swing_on_a_fresh_spawn_never_knocks_you_out(t) -> void:
	# A new player's first move: stand on the spawn roof and hold the touch
	# SWING button, no stick. The spawn heading is chosen so that held swing
	# (zip-up, rope wrapping, roof skims included) misses every wall at
	# knockout speed. Was 11 of 24 before the check flew the held swing.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var kos := 0
	var last := Vector3.INF
	for i in 10:
		var spot := world.random_rooftop(rng, last)
		last = spot["position"]
		var p := Player.new()
		p.params = load("res://config/swing_params.tres").duplicate()
		add_child(p)
		var bot := _Aim.new()
		bot.aim = CityWorld.spawn_aim(spot["yaw"])
		p.bot = bot
		p.respawn(spot["position"])
		for f in 60:
			await get_tree().physics_frame
			if f > 3 and p.is_on_floor():
				break
		var ko := [false]
		p.knockout.connect(func(_s, _n): ko[0] = true)
		p.assist_fire(7)
		for f in 300:
			await get_tree().physics_frame
			if ko[0]:
				break
		if ko[0]:
			kos += 1
			t.note("knocked out from %s facing %.0f°" % [spot["position"].snapped(Vector3.ONE), rad_to_deg(spot["yaw"])])
		p.queue_free()
		await get_tree().physics_frame
	t.check(kos == 0, "no knockouts holding SWING from 10 spawns (%d)" % kos)


func test_camera_is_a_stable_follow_camera(t) -> void:
	# 30 s of real swinging from each of four rooftops: the camera stays
	# behind the direction of travel, turns smoothly, never flips or orbits,
	# never clips or snaps. Autopilot runs are chaotic (one start ranges
	# ~70–99% behind travel), so the travel bar is on the mean of the four.
	var runs: Array = []
	for sd in [2, 3, 4, 5]:
		runs.append(await _camera_run(sd))
	var behind := 0.0
	for r in runs:
		t.note("camera seed %d: max turn %.1f°/frame, %d flips, behind travel %.0f%% of %d moving frames, hero on screen %.0f%%, %d snaps, %d inside, fov %.0f→%.0f" % [
			r["seed"], rad_to_deg(r["max_turn"]), r["flips"], 100.0 * r["behind"], r["moving"], 100.0 * r["visible"],
			r["snaps"], r["inside"], r["fov_rest"], r["fov_fast"]])
		behind += r["behind"] / runs.size()
		t.check(r["max_turn"] <= deg_to_rad(2.1), "yaw turns at most ~120°/s – no sudden rotations")
		t.check(r["flips"] == 0, "no camera flips")
		t.check(r["visible"] > 0.97, "player always in view")
		# The taller city has 2–7 m gaps between towers: wall-sliding down
		# one, the lens can only cut in (one cut seen in 4 runs).
		t.check(r["snaps"] <= 1 and r["inside"] == 0, "no snapping or clipping")
	t.note("mean behind travel %.0f%%" % (behind * 100.0))
	t.check(behind > 0.8, "camera sits behind the direction of travel")
	t.check(runs.any(func(r): return r["fov_fast"] > r["fov_rest"] + 8.0), "FOV opens up at speed")


func _camera_run(sd: int) -> Dictionary:
	var p := Player.new()
	p.params = load("res://config/swing_params.tres").duplicate()
	add_child(p)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var spot := world.random_rooftop(rng)
	p.respawn(spot["position"])
	var bot := SwingBot.new(SwingBot.Style.EXPERT, Vector3.FORWARD)
	bot.goal_fn = world.bot_goal
	p.bot = bot
	var cam := SwingCamera.new()
	add_child(cam)
	cam.set_target(p)
	cam.face(spot["yaw"])
	world.set_viewer(cam)
	var space := get_viewport().world_3d.direct_space_state
	var respawned := [false]
	p.respawned.connect(func(): respawned[0] = true)
	var prev_cam := Vector3.INF
	var prev_player := p.global_position
	var prev_yaw := cam.yaw
	var snaps := 0
	var inside := 0
	var max_turn := 0.0
	var behind := 0
	var moving := 0
	var flips := 0
	var fov_rest := 0.0
	var fov_fast := 0.0
	var visible := 0
	for i in 60 * 30:
		await get_tree().physics_frame
		await get_tree().process_frame
		var c := cam.cam.global_position
		if respawned[0]:
			respawned[0] = false
		elif prev_cam != Vector3.INF and c.distance_to(prev_cam) > p.global_position.distance_to(prev_player) + 1.5:
			snaps += 1
		prev_cam = c
		prev_player = p.global_position
		var turn := absf(wrapf(cam.yaw - prev_yaw, -PI, PI))
		max_turn = maxf(max_turn, turn)
		if turn > deg_to_rad(20.0):
			flips += 1
		prev_yaw = cam.yaw
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = c
		pq.collision_mask = 3
		if not space.intersect_point(pq).is_empty():
			inside += 1
		var vh := Vector3(p.s.velocity.x, 0, p.s.velocity.z)
		if vh.length() > 10.0 and absf(p.s.velocity.y) < vh.length():
			moving += 1
			var fwd := -cam.cam.global_basis.z
			if Vector2(fwd.x, fwd.z).normalized().dot(Vector2(vh.x, vh.z).normalized()) > cos(deg_to_rad(45.0)):
				behind += 1
		# The hero stays in frame.
		if not cam.cam.is_position_behind(p.global_position):
			var sp := cam.cam.unproject_position(p.global_position)
			var vs := get_viewport().get_visible_rect().size
			if sp.x > 0 and sp.x < vs.x and sp.y > 0 and sp.y < vs.y:
				visible += 1
		if i < 20:
			fov_rest = cam.cam.fov
		if p.speed() > 35.0:
			fov_fast = maxf(fov_fast, cam.cam.fov)
	var frames := 60 * 30
	p.queue_free()
	cam.queue_free()
	await get_tree().process_frame
	return {"seed": sd, "max_turn": max_turn, "flips": flips, "behind": float(behind) / maxf(moving, 1), "moving": moving,
		"visible": float(visible) / frames, "snaps": snaps, "inside": inside, "fov_rest": fov_rest, "fov_fast": fov_fast}


func test_spawn_and_reattach_transitions_are_smooth(t) -> void:
	# Respawn snaps by design; after that the camera must glide, including
	# through a mid-swing reattachment.
	var p := Player.new()
	p.params = load("res://config/swing_params.tres").duplicate()
	add_child(p)
	p.bot = _Idle.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var spot := world.random_rooftop(rng)
	p.respawn(spot["position"])
	var cam := SwingCamera.new()
	add_child(cam)
	cam.set_target(p)
	cam.face(spot["yaw"])
	await get_tree().process_frame
	await get_tree().process_frame  # camera has placed itself
	var max_step := 0.0
	var prev := cam.cam.global_position
	var fired := 0
	for i in 240:
		if i == 30 or i == 90:
			# Like a player: tap the first visible valid building pixel.
			var done := false
			for y in range(60, 400, 30):
				for x in range(200, 1100, 60):
					var r := p.screen_target(cam.cam, Vector2(x, y))
					if r["ok"]:
						p.fire_at(r["point"], i)
						fired += 1
						done = true
						break
				if done:
					break
		await get_tree().physics_frame
		await get_tree().process_frame
		var c := cam.cam.global_position
		max_step = maxf(max_step, c.distance_to(prev) - p.speed() / 60.0)
		prev = c
	t.note("max camera step beyond player motion: %.2f m (%d webs fired)" % [max_step, fired])
	t.check(fired >= 1, "webs were fired (standing → swinging → reattach)")
	t.check(max_step < 1.0, "camera glides through state changes")
	p.queue_free()
	cam.queue_free()


func test_swing_launches_cleanly_from_the_street_and_rooftops(t) -> void:
	# Stand on the street at several avenue spots (and on rooftops), hold SWING:
	# the player must jump, catch a web and get back up into the air.
	var p := Player.new()
	p.params = load("res://config/swing_params.tres").duplicate()
	add_child(p)
	p.bot = _Idle.new()
	var spots: Array = []  # [position, heading, on_street]
	# On the Central Spine boulevard between its junctions (not out in a
	# roundabout's open circle), facing along it (north), ~130 m apart.
	var all: Array = world.layout.roads.along("spine", 10.0, 200.0)
	var spine: Array = []
	for i in all.size() - 1:
		var q0: Vector2 = all[i]
		var clear: bool = world.layout.roads.roundabouts.all(func(rb): return (rb["c"] as Vector2).distance_to(q0) > 70.0)
		if clear and world.layout.roads.field_at(q0).w > 8.0 \
				and (spine.is_empty() or (spine[-1][0] as Vector2).distance_to(q0) > 130.0):
			spine.append([q0, all[i + 1]])
	for k in mini(5, spine.size()):
		var q: Vector2 = spine[k][0]
		var nxt: Vector2 = spine[k][1]
		var fwd := Vector3(q.x - nxt.x, 0.0, q.y - nxt.y).normalized()  # (the spine runs north → south)
		# The City Loop's viaduct runs down the spine's median now: stand
		# by the kerb, clear of its deck (a swing straight up
		# under an elevated railway meets the railway).
		var side := Vector2(-fwd.z, fwd.x) * 12.0
		var sq := q + side
		spots.append([Vector3(sq.x, world.layout.ground_y(sq.x, sq.y) + 1.2, sq.y), fwd, true])
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	for k in 3:
		var r := world.random_rooftop(rng)
		spots.append([r["position"], Vector3.FORWARD.rotated(Vector3.UP, r["yaw"]), false])
	var ok := 0
	for entry in spots:
		var spot: Vector3 = entry[0]
		var heading: Vector3 = entry[1]
		p.respawn(spot)
		for f in 20:
			await get_tree().physics_frame
		var ground_y := p.global_position.y
		# Face along the avenue / the roof's route, as the camera does.
		p.aim_dir = (heading + Vector3.UP * 0.2).normalized()
		p.targeting.update(get_viewport().world_3d.direct_space_state, p.hand_position(), p.aim_dir,
			Vector3.ZERO, p.params, true, [p.get_rid()])
		var fired := p.assist_fire(1)
		var chosen := p.line_target
		var top := ground_y
		var attached := false
		var start := p.global_position
		for f in 180:
			await get_tree().physics_frame
			top = maxf(top, p.global_position.y)
			attached = attached or p.line_state == Player.Line.ATTACHED
		var rose := top - ground_y
		var travelled := Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
		var airborne := not p.is_on_floor() or p.line_state == Player.Line.ATTACHED
		# Street: must climb well clear of it. Rooftop: must swing off the roof.
		var good: bool = (rose > 12.0) if entry[2] else (travelled > 15.0 and not p.on_street)
		# A roof with no initial target arms the touch and catches one after takeoff.
		if attached and airborne and good:
			ok += 1
		else:
			t.note("launch from %s: fired=%s attached=%s rose %.1f m travelled %.0f m airborne=%s target=%s rope=%.1f" % [spot.snapped(Vector3.ONE), fired, attached, rose, travelled, airborne, chosen.snapped(Vector3.ONE), p.s.rope_length])
		p.release_web()
	t.note("clean launches: %d/%d" % [ok, spots.size()])
	t.check(ok >= spots.size() - 1, "holding SWING on the ground gets the player swinging again")
	p.queue_free()
	await get_tree().process_frame


class _Idle:
	extends RefCounted
	func drive(_p, _dt) -> Dictionary:
		return {"move": Vector3.ZERO, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}


class _Run:
	extends RefCounted
	var f := 0
	var dir := Vector3.FORWARD
	func drive(_p, _dt) -> Dictionary:
		f += 1
		return {"move": dir, "aim": dir, "grapple": false, "reel": 0.0, "jump": f == 25}


class _Aim:
	extends RefCounted
	var aim := Vector3.FORWARD
	var human_steer := true
	func drive(_p, _dt) -> Dictionary:
		return {"move": Vector3.ZERO, "aim": aim, "grapple": false, "reel": 0.0, "jump": false}
