extends Node
## City generation tests: determinism, sanity of the plan, collision coverage,
## streaming behaviour and a real traversal run through the generated city.


func test_layout_is_deterministic(t) -> void:
	var a := CityLayout.new().generate(42)
	var b := CityLayout.new().generate(42)
	var c := CityLayout.new().generate(43)
	t.check(a.buildings.size() == b.buildings.size(), "same seed, same building count")
	t.check(str(a.buildings[100]["tiers"]) == str(b.buildings[100]["tiers"]), "same seed, same geometry")
	t.check(str(a.buildings[100]["tiers"]) != str(c.buildings[100]["tiers"]), "different seed, different city")


func test_layout_has_districts_landmarks_and_swing_heights(t) -> void:
	var l := CityLayout.new().generate()
	var counts := {}
	var tall := 0
	var low := 0
	for b in l.buildings:
		var tt: Array = b["tiers"][0]
		var d := l.district((tt[0] + tt[2]) * 0.5, (tt[1] + tt[3]) * 0.5)
		counts[d] = counts.get(d, 0) + 1
		var h: float = b["tiers"][-1][5]
		if h > 100.0:
			tall += 1
		elif h < 35.0:
			low += 1
	t.note("districts %s, >100 m: %d, <35 m: %d, props %d, lanes %d" % [counts, tall, low, l.props.size(), l.lanes.size()])
	for d in ["waterfront", "cbd", "midtown", "docks", "georgian"]:
		t.check(counts.get(d, 0) > 5, "district %s populated" % d)
	t.check(tall >= 25, "a skyline of 100 m+ towers to swing from")
	t.check(low >= 80, "low-rise technical terrain exists")
	var kinds := {}
	for lm in l.landmarks:
		kinds[lm[0]] = true
	for k in ["clock_crown", "harbour_dome", "beacon", "cathedral_top", "viaduct"]:
		t.check(kinds.has(k), "landmark %s placed" % k)
	t.check(l.parks.size() > 3, "parks / plazas give wide launch gaps")


func test_buildings_do_not_overlap_streets_or_each_other(t) -> void:
	var l := CityLayout.new().generate()
	var rects: Array = []
	for b in l.buildings:
		if b["kind"] != "normal":
			continue
		var tt: Array = b["tiers"][0]
		rects.append(Rect2(tt[0], tt[1], tt[2] - tt[0], tt[3] - tt[1]))
	var overlaps := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).grow(-0.5).intersects(rects[j].grow(-0.5)):
				overlaps += 1
	t.check(overlaps == 0, "%d overlapping building footprints" % overlaps)
	var in_street := 0
	for r in rects:
		for s in l.x_streets:
			if absf(r.get_center().x - s[0]) < s[1] * 0.5:
				in_street += 1
	t.check(in_street == 0, "%d buildings centred in a street" % in_street)


func test_world_builds_collision_and_streams(t) -> void:
	var w := CityWorld.new()
	add_child(w)
	var spawn := w.spawn_point()
	t.check(spawn.y > 50.0, "spawn on a rooftop (y=%.0f)" % spawn.y)
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(spawn + Vector3.UP * 5.0, spawn + Vector3.DOWN * 20.0, 1 << 1)
	t.check(not space.intersect_ray(q).is_empty(), "spawn roof is grappleable collision")
	var viewer := Node3D.new()
	add_child(viewer)
	viewer.global_position = spawn
	# Generation is threaded: wait on the result (up to 3 s of real time), not
	# a frame count – headless frames are so fast that a busy machine could
	# starve the workers for all of them.
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while frames < 60 or (w.loaded_chunk_count() < 8 and Time.get_ticks_msec() - t0 < 3000):
		w.update_streaming(viewer.global_position, 8)
		await get_tree().process_frame
		frames += 1
	var near := w.loaded_chunk_count()
	t.note("chunks loaded around spawn: %d, mean gen %.1f ms" % [near, w.gen_ms_total / maxf(w.chunks_built, 1)])
	t.check(near >= 8, "chunks stream in around the viewer")
	viewer.global_position = Vector3(5000, 0, 5000)
	w.update_streaming(viewer.global_position, 8)
	await get_tree().process_frame
	t.check(w.loaded_chunk_count() == 0, "chunks unload when the viewer leaves")
	viewer.queue_free()
	w.queue_free()
	await get_tree().process_frame


func test_expert_swings_through_generated_city(t) -> void:
	# Several rooftop starts; judged on the median (swinging is chaotic).
	var w := CityWorld.new()
	add_child(w)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var dists: Array[float] = []
	var touches: Array[int] = []
	var swings: Array[int] = []
	for k in 3:
		var p := Player.new()
		p.params = load("res://config/swing_params.tres").duplicate()
		add_child(p)
		var spot := w.random_rooftop(rng) if k > 0 else {"position": w.spawn_point()}
		p.respawn(spot["position"])
		var bot := SwingBot.new(SwingBot.Style.EXPERT, Vector3.FORWARD)
		bot.goal_fn = w.bot_goal
		p.bot = bot
		var street := [0]
		p.landed.connect(func(_s, st): if st: street[0] += 1)
		var start := p.global_position
		var far := 0.0
		for i in 60 * 45:
			await get_tree().physics_frame
			far = maxf(far, Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length())
		t.note("city run %d: %.0f m from start, %d swings, best chain %d, top %.0f km/h, street touches %d" % [
			k, far, p.swings, p.best_chain, p.top_speed * 3.6, street[0]])
		dists.append(far)
		touches.append(street[0])
		swings.append(p.swings)
		p.queue_free()
		await get_tree().process_frame
	var raw_d := dists.duplicate()
	var raw_t := touches.duplicate()
	dists.sort()
	touches.sort()
	swings.sort()
	t.check(dists[1] > 300.0, "median run covers real distance through the city (%.0f m)" % dists[1])
	t.check(swings[1] >= 8, "median run chains swings on generated geometry")
	# Per distance: runs got much longer once walls became lethal and the
	# autopilot learned to read them, so a fixed count would punish distance.
	var rates: Array[float] = []
	for k in raw_t.size():
		rates.append(100.0 * raw_t[k] / maxf(raw_d[k], 1.0))
	rates.sort()
	t.check(rates[1] <= 1.0, "median run rarely touches the street (%.2f per 100 m)" % rates[1])
	w.queue_free()
	await get_tree().process_frame
