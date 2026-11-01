extends SceneTree
## Traffic sanity: builds the lane graph for the island (and mainland) and
## runs the cars for a few simulated minutes, headless. Reports build time,
## lanes/connectors/cars, and per sample: cars off the road (in the sea or
## on a block), overlapping cars, cars stuck > 30 s, and position jumps.
##   godot --headless -s res://tools/traffic_audit.gd -- [seconds] [mainland]

const TRACE := [828, 263]


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var secs := float(a[0]) if a.size() > 0 else 240.0
	var L := CityLayout.new().generate()
	if a.size() > 1 and a[1] == "mainland":
		L = CityLayout.new().generate_mainland(L.seed)
	var tr := Traffic.new()
	root.add_child(tr)
	var t0 := Time.get_ticks_msec()
	var meshes: Array = [ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()]
	tr.set_process(false)
	tr.layout = L
	tr.density = 1.0
	tr._rng.seed = 5
	tr.build_network()
	var t_net := Time.get_ticks_msec() - t0
	tr._spawn_cars(meshes)
	var conns := 0
	var dead := 0
	for li in tr.lane_count():
		if tr.l_next[li] >= 0:
			conns += 1
		elif not tr.l_loop[li] and (tr.l_ends[li] as Array).is_empty():
			dead += 1
	print("network %d ms: %d lanes (%d connectors), %.1f km of lane, %d open lanes with no way on, %d cars" % [
		t_net, tr.lane_count(), conns, tr.total_lane_length() / 1000.0, dead, tr.car_count()])
	var dt := 1.0 / 30.0
	var steps := int(secs / dt)
	var prev: Array = []
	for id in tr.car_count():
		prev.append(tr.car_position(id))
	var off_road := {}
	var jumps := 0
	var overlaps := 0
	var max_still := {}
	var still_since: Array = []
	still_since.resize(tr.car_count())
	still_since.fill(0.0)
	var ev_count := 0
	var ov_kinds := {}
	var t_cpu := 0
	for st in steps:
		var tt := Time.get_ticks_usec()
		tr.now += dt
		for id in tr.car_count():
			if tr.c_ev[id] <= tr.now:
				var before := "lane %d s %.1f v %.1f stop %.1f ek %d" % [tr.c_lane[id], tr.car_s(id, tr.now), tr.c_v[id], tr.c_stop[id], tr.c_ek[id]]
				tr._event(id)
				if id in TRACE and tr.now < 8.0:
					print("  t=%.2f car %d: %s -> lane %d s %.1f v %.1f stop %.1f ek %d ev %.2f" % [tr.now, id, before, tr.c_lane[id], tr.car_s(id, tr.now), tr.c_v[id], tr.c_stop[id], tr.c_ek[id], tr.c_ev[id]])
				ev_count += 1
		t_cpu += Time.get_ticks_usec() - tt
		if st % 15 != 0:
			continue
		var grid := {}
		for id in tr.car_count():
			var p := tr.car_position(id)
			if p.distance_to(prev[id]) > 14.0 * 0.5 + 3.0:
				jumps += 1
				if jumps <= 5:
					print("  jump car %d lane %d (next %d) %.1f m at t=%.1f" % [id, tr.c_lane[id], tr.l_next[tr.c_lane[id]], p.distance_to(prev[id]), tr.now])
			if p.distance_to(prev[id]) < 0.2:
				if tr.now - float(still_since[id]) > 30.0:
					max_still[id] = tr.now - float(still_since[id])
			else:
				still_since[id] = tr.now
			prev[id] = p
			if tr.l_next[tr.c_lane[id]] < 0:
				var bi := L.block_at(p.x, p.z)
				if L.is_water(p) or (bi >= 0 and L.blocks[bi]["kind"] in ["block", "park"]):
					off_road[tr.c_lane[id]] = p
			var k := Vector2i(floori(p.x / 6.0), floori(p.z / 6.0))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for o in grid.get(k + Vector2i(dx, dz), []):
						if (prev[o] as Vector3).distance_to(p) < 3.0:
							overlaps += 1
							var la := tr.c_lane[id]
							var lb := tr.c_lane[o]
							var kk := "%s/%s%s" % ["c" if tr.l_next[la] >= 0 else "L", "c" if tr.l_next[lb] >= 0 else "L", " same" if la == lb else ""]
							ov_kinds[kk] = ov_kinds.get(kk, 0) + 1
							if la == lb and ov_kinds[kk] <= 6:
								var cs: Array = tr.l_cars[la]
								print("  same-lane overlap t=%.1f lane %d (loop %d): car %d s %.1f v %.1f stop %.1f ek %d idx %d | car %d s %.1f v %.1f stop %.1f ek %d idx %d" % [tr.now, la, tr.l_loop[la],
									id, tr.car_s(id, tr.now), tr.c_v[id], tr.c_stop[id], tr.c_ek[id], cs.find(id),
									o, tr.car_s(o, tr.now), tr.c_v[o], tr.c_stop[o], tr.c_ek[o], cs.find(o)])
			if not grid.has(k):
				grid[k] = []
			grid[k].append(id)
	print(ov_kinds)
	print("simulated %.0f s: %d events (%.1f/s), CPU %.3f ms/frame" % [secs, ev_count, ev_count / secs, t_cpu / 1000.0 / steps])
	print("off-road lanes: %d %s" % [off_road.size(), str(off_road.values().slice(0, 4))])
	print("position jumps: %d, overlapping pairs (samples): %d, cars still > 30 s: %d" % [jumps, overlaps, max_still.size()])
	var waiting := 0
	for id in tr.car_count():
		if tr.c_stop[id] < Traffic.NO_STOP:
			waiting += 1
	print("stopped/stopping now: %d of %d" % [waiting, tr.car_count()])
	var kinds := {}
	for id in tr.car_count():
		if tr.c_stop[id] < Traffic.NO_STOP:
			var li := tr.c_lane[id]
			var front := tr._leader(id) < 0
			var key := "ek%d front=%s ends=%d" % [tr.c_ek[id], front, (tr.l_ends[li] as Array).size()]
			kinds[key] = kinds.get(key, 0) + 1
			if front and kinds[key] <= 3:
				var why := []
				for c in tr.l_ends[li]:
					why.append("c%d(cars %d, to %d len %.0f)" % [c, (tr.l_cars[c] as Array).size(), tr.l_next[c], tr.l_len[c]])
				print("  front car %d lane %d len %.0f s %.1f stop %.1f ev %.1f wait %.1f: %s" % [id, li, tr.l_len[li], tr.car_s(id, tr.now), tr.c_stop[id], tr.c_ev[id] - tr.now, tr.now - tr.c_wait[id], " ".join(why)])
	print(kinds)
	quit()
