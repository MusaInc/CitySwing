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
		var bc := CityLayout.base_center(b)
		var d := l.district(bc.x, bc.y)
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
	for k in ["clock_crown", "harbour_dome", "beacon", "cathedral_top"]:
		t.check(kinds.has(k), "landmark %s placed" % k)
	t.check(l.blocks.filter(func(bk): return bk["kind"] in ["park", "plaza"]).size() > 3,
		"parks / plazas give wide launch gaps")


func test_buildings_do_not_overlap_streets_or_each_other(t) -> void:
	# Footprints (world quads, turned lots included) never overlap each other
	# and never stand on a carriageway.
	var l := CityLayout.new().generate()
	var quads: Array = []
	for b in l.buildings:
		if b["kind"] != "normal":
			continue
		var tt: Array = b["tiers"][0]
		if not BuildingMesher._on_ground(b, tt):
			continue  # towers standing on a podium / bell towers on a roof
		var X := CityLayout.bxf(b)
		var q := PackedVector2Array()
		for c in [Vector2(tt[0] + 0.5, tt[1] + 0.5), Vector2(tt[2] - 0.5, tt[1] + 0.5), Vector2(tt[2] - 0.5, tt[3] - 0.5),
				Vector2(tt[0] + 0.5, tt[3] - 0.5)]:
			var w := X * Vector3(c.x, 0.0, c.y)
			q.append(Vector2(w.x, w.z))
		quads.append(q)
	var overlaps := 0
	for i in quads.size():
		var bi := CityLayout._bbox(quads[i])
		for j in range(i + 1, quads.size()):
			if bi.intersects(CityLayout._bbox(quads[j])) and not Geometry2D.intersect_polygons(quads[i], quads[j]).is_empty():
				overlaps += 1
	t.check(overlaps == 0, "%d overlapping building footprints" % overlaps)
	var on_road := 0
	for q in quads:
		for v in q:
			if l.roads.on_road(v):
				on_road += 1
				break
	t.check(on_road == 0, "%d buildings standing on a road" % on_road)


func test_whole_layout_repeats_exactly(t) -> void:
	# Courses, spawns and tests replay recorded flights: the city must come
	# out identical every launch (no global-RNG draws in generation).
	var a := CityLayout.new().generate()
	var b := CityLayout.new().generate()
	t.check(str(a.buildings.size()) == str(b.buildings.size()) and var_to_str(a.buildings) == var_to_str(b.buildings),
		"two generations give the same buildings")
	t.check(var_to_str(a.props) == var_to_str(b.props), "and the same props")


func test_island_has_sea_round_it(t) -> void:
	var l := CityLayout.new().generate()
	var I := l.island
	for p in [Vector2(I.end.x + 60.0, I.get_center().y), Vector2(I.get_center().x, I.position.y - 60.0),
			Vector2(I.get_center().x, I.end.y + 60.0), Vector2(I.end.x + 900.0, I.end.y + 900.0)]:
		t.check(l.is_water(Vector3(p.x, -2.0, p.y)), "sea at %s" % p)
	t.check(not l.is_water(Vector3(560, 0, -170)), "dry land in the middle")
	for b in l.buildings:
		var c := CityLayout.base_center(b)
		if b["kind"] in ["normal", "landmark"] and not Geometry2D.is_point_in_polygon(c, l.coast):
			t.check(false, "building at (%.0f, %.0f) stands off the island" % [c.x, c.y])
			return


func test_every_district_is_swingable(t) -> void:
	# Swinging needs anchors well over the street: in every district most
	# roofs (by footprint area) stand at least 45 m above their street.
	var l := CityLayout.new().generate()
	var area := {}
	var tall := {}
	for b in l.buildings:
		if b["kind"] not in ["normal", "plain"]:
			continue
		var t0: Array = b["tiers"][0]
		if b["kind"] == "normal" and not BuildingMesher._on_ground(b, t0):
			continue
		var top := BuildingMesher.tiers_top(b)
		var bc := CityLayout.base_center(b)
		for e in l.buildings:  # a tower on it counts for its roof
			var et: Array = e["tiers"][0]
			if not is_same(e, b) and e["kind"] == "normal" and absf(float(e.get("rot", 0.0)) - float(b.get("rot", 0.0))) < 1e-6 \
					and Rect2(t0[0], t0[1], t0[2] - t0[0], t0[3] - t0[1]).encloses(Rect2(et[0], et[1], et[2] - et[0], et[3] - et[1])) \
					and absf(float(et[4]) - float(b["tiers"][-1][5])) < 0.6:
				top = maxf(top, BuildingMesher.tiers_top(e))
		var d := l.district(bc.x, bc.y)
		var a: float = (t0[2] - t0[0]) * (t0[3] - t0[1])
		area[d] = area.get(d, 0.0) + a
		if top - BuildingMesher.base_of(b) >= 45.0:
			tall[d] = tall.get(d, 0.0) + a
	var line := ""
	for d in area:
		var share: float = tall.get(d, 0.0) / area[d]
		line += "%s %d%%  " % [d, roundi(share * 100.0)]
		t.check(share >= (0.4 if d == "docks" else 0.55), "%s: %d%% of roof area is 45 m+" % [d, roundi(share * 100.0)])
	t.note(line)


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


func test_road_field_matches_the_roads(t) -> void:
	# ground.gdshader draws lane paint, crossings and kerbs from the road
	# field: probe it across every road and check offset and width.
	var w := CityWorld.new()
	add_child(w)
	await get_tree().process_frame
	var R := w.layout.roads
	t.check(w.ground_mat.get_shader_parameter("road_field") != null, "the ground material has the road field")
	var bad := 0
	var probes := 0
	for r in R.roads:
		var pts: PackedVector2Array = r["pts"]
		if pts.size() < 3 or CityRoads.length_of(pts) < 80.0:
			continue
		var i := pts.size() / 2
		var d := (pts[i + 1] - pts[i]).normalized()
		var n := Vector2(-d.y, d.x)
		for off: float in [0.0, float(r["w"]) * 0.25]:
			var p := pts[i] + n * off
			var f := R.field_at(p)
			if f.w < 2.0:
				continue  # (a junction: another road owns the texel)
			probes += 1
			if absf(absf(f.x) - off) > R.field_cell or absf(absf(f.y) - float(r["w"]) * 0.5) > 0.01:
				bad += 1
	t.note("%d road-field probes" % probes)
	t.check(probes > 60, "probed most roads")
	t.check(bad <= probes / 50, "%d road-field texels disagree with their road" % bad)
	w.queue_free()
	await get_tree().process_frame


func test_street_furniture_stays_on_the_pavement(t) -> void:
	var w := CityWorld.new()
	add_child(w)
	await get_tree().process_frame
	var l := w.layout
	var normal: Array = l.buildings.filter(func(b): return b["kind"] == "normal")
	var n := 0
	var in_building := 0
	var off_block := 0
	var kinds := {}
	for key in w._furniture_by_chunk:
		for it in w._furniture_by_chunk[key]:
			n += 1
			kinds[it[0]] = kinds.get(it[0], 0) + 1
			var o: Vector3 = (it[1] as Transform3D).origin
			var p := Vector2(o.x, o.z)
			if l.block_at(p.x, p.y) < 0:
				off_block += 1
			for b in normal:
				if CityLayout.base_center(b).distance_to(p) < 60.0 and CityLayout.inside(b, Vector3(o.x, o.y + 0.5, o.z), -0.4):
					in_building += 1
					break
	t.note("%d furniture items %s" % [n, kinds])
	t.check(n > 1000 and kinds.size() == CityWorld.FURNITURE.size(), "every kind of street furniture is placed")
	t.check(off_block == 0, "%d items out on the road" % off_block)
	t.check(in_building == 0, "%d items inside a building" % in_building)
	var arr = w._furniture_arrays(w._furniture_by_chunk.keys()[0])
	t.check(arr != null and (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0, "a chunk's furniture merges into one mesh")
	w.queue_free()
	await get_tree().process_frame


func test_traffic_lod_and_tight_culling(t) -> void:
	var w := CityWorld.new()
	add_child(w)
	await get_tree().process_frame
	w.build_all_near(Vector3(386, 0, -200), 250.0)
	var near := 0
	var far := 0
	var loose := 0
	for c in w.get_children():
		for mmi in c.find_children("Traffic_*", "MultiMeshInstance3D", true, false):
			var mm: MultiMesh = mmi.multimesh
			if mm.custom_aabb.size.x > CityWorld.CHUNK + 1.0 or mm.custom_aabb.size.x < 1.0:
				loose += 1
			if mmi.name.ends_with("_far"):
				far += 1
				var tris := 0
				for s in mm.mesh.get_surface_count():
					tris += (mm.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				t.check(tris <= 24, "far car stand-in is %d triangles" % tris)
			else:
				near += 1
	t.check(near > 0 and far == near, "every car group has a far LOD (%d near, %d far)" % [near, far])
	t.check(loose == 0, "%d traffic groups without a chunk-sized culling box" % loose)
	w.queue_free()
	await get_tree().process_frame


func test_expert_swings_through_generated_city(t) -> void:
	# Several rooftop starts; judged on the median (swinging is chaotic).
	var w := CityWorld.new()
	add_child(w)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(OS.get_environment("CITY_SEED")) if OS.get_environment("CITY_SEED") != "" else 21
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
