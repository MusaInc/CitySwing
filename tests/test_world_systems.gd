extends Node
## The world beyond the island's streets: the mainland (Westbank) and the
## bridge's approach, the railways and their moving trains, and the
## day/night + weather atmosphere.


func test_mainland_is_a_real_district(t) -> void:
	var m := CityLayout.new().generate_mainland(1207)
	var counts := {}
	var parks := 0
	for b in m.buildings:
		var bc := CityLayout.base_center(b)
		counts[m.district(bc.x, bc.y)] = counts.get(m.district(bc.x, bc.y), 0) + 1
		t.check(bc.x < CityLayout.FAR_SHORE, "mainland buildings stay west of the strait")
		if bc.x >= CityLayout.FAR_SHORE:
			break
	for blk in m.blocks:
		if blk["kind"] == "park":
			parks += 1
	t.note("mainland: %d buildings %s, %d parks, %d props, %d lanes" % [m.buildings.size(), counts, parks, m.props.size(),
		m.lanes.size()])
	t.check(m.buildings.size() > 300, "a full district of buildings")
	for d in ["waterfront", "midtown", "suburb"]:
		t.check(counts.get(d, 0) > 5, "mainland district %s populated" % d)
	t.check(parks >= 2, "parks on the mainland")
	t.check(not m.lanes.is_empty(), "mainland traffic lanes")
	var lamps := m.props.filter(func(p): return p[0] == "streetlight").size()
	t.check(lamps > 100, "street lighting on the mainland (%d)" % lamps)


func test_water_and_ground_cover_both_lands(t) -> void:
	var l := CityLayout.new().generate()
	l.mainland = CityLayout.new().generate_mainland(l.seed)
	t.check(l.is_water(Vector3(-200.0, 0.0, 100.0)), "the strait is water")
	t.check(not l.is_water(Vector3(-800.0, 0.0, 100.0)), "the mainland is land")
	t.check(l.is_water(Vector3(-1600.0, 0.0, 0.0)), "sea beyond the mainland")
	t.check(not l.is_water(Vector3(400.0, 0.0, -100.0)), "the island is land")
	# The approach viaduct meets the bridge deck and comes down onto the hill.
	t.check(absf(CityLayout.approach_y(CityLayout.FAR_SHORE - 2.0) - CityLayout.BRIDGE_DECK) < 0.01,
		"approach starts at deck height")
	var land_y := l.ground_y(CityLayout.APPROACH_END - 4.0, CityLayout.BRIDGE_Z)
	t.check(absf(CityLayout.approach_y(CityLayout.APPROACH_END) - land_y) < 1.0,
		"approach lands on the hill's road (%.2f vs %.2f)" % [CityLayout.approach_y(CityLayout.APPROACH_END), land_y])
	t.check(l.ground_y(-1000.0, 260.0) > 8.0, "the mainland rises inland")


func test_rail_lines(t) -> void:
	var l := CityLayout.new().generate()
	var names := {}
	for line in l.rail.lines:
		names[line["name"]] = line
	t.check(names.has("loop") and names.has("valley"), "loop and valley lines")
	var loop: Dictionary = names.get("loop", {})
	if loop.is_empty():
		return
	var pts: PackedVector3Array = loop["pts"]
	var total := pts.size() * RailNetwork.STEP
	t.note("loop line %.0f m, %d stations" % [total, loop["stations"].size()])
	t.check(total > 3000.0, "the loop goes right round the island")
	t.check(loop["stations"].size() == 4, "four loop stations")
	var worst_grade := 0.0
	var worst_turn := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var c := pts[(i + 2) % pts.size()]
		worst_grade = maxf(worst_grade, absf(b.y - a.y) / Vector2(b.x - a.x, b.z - a.z).length())
		var d0 := Vector2(b.x - a.x, b.z - a.z)
		var d1 := Vector2(c.x - b.x, c.z - b.z)
		worst_turn = maxf(worst_turn, absf(d0.angle_to(d1)))
	t.note("steepest grade %.1f%%, sharpest turn %.1f° per 2 m" % [worst_grade * 100.0, rad_to_deg(worst_turn)])
	t.check(worst_grade < 0.12, "grades a train can climb")
	t.check(rad_to_deg(worst_turn) < 6.0, "no kinks in the track (min radius ~20 m)")
	# Clear of buildings: the deck never passes through a tower.
	var hits := 0
	for i in range(0, pts.size(), 5):
		var p := pts[i]
		for b in l.buildings:
			if b["kind"] == "invisible":
				continue  # (the waterfront viaduct's own deck)
			if CityLayout.inside(b, p + Vector3.UP * 2.0, 0.3):
				hits += 1
				break
		if hits > 0:
			break
	t.check(hits == 0, "the loop line runs clear of buildings")


func test_trains_run_and_stop_at_stations(t) -> void:
	var l := CityLayout.new().generate()
	var trains := Trains.new()
	add_child(trains)
	var car := BoxMesh.new()
	trains.setup(l.rail.lines, car, car)
	t.check(trains._trains.size() == 5, "two loop trains, a valley shuttle and two Cross-City trains (%d)" % trains._trains.size())
	var s0: Array = []
	for tr in trains._trains:
		s0.append(tr["cars"][0].global_position)
	for i in 1200:  # 20 s (they start with a station dwell)
		trains._clock += 1.0 / 60.0
		trains._place_all()
	var moved := 0
	for i in trains._trains.size():
		if (trains._trains[i]["cars"][0] as Node3D).global_position.distance_to(s0[i]) > 5.0:
			moved += 1
	t.check(moved >= 3, "trains move (%d of %d after 20 s)" % [moved, trains._trains.size()])
	# Cars stay coupled: neighbours ~CAR_PITCH apart.
	var tr0: Dictionary = trains._trains[0]
	var gap := (tr0["cars"][0] as Node3D).global_position.distance_to((tr0["cars"][1] as Node3D).global_position)
	t.check(absf(gap - Trains.CAR_PITCH) < 1.5, "cars coupled (%.2f m)" % gap)
	# Full cycle: every train dwells at a station at some point.
	var cyc: float = tr0["cycle"]
	var stopped := false
	var s := 0.0
	while s < cyc:
		trains._clock = s
		trains._place_all()
		if float(tr0["v"]) == 0.0:
			stopped = true
			break
		s += 1.0
	t.check(stopped, "trains stop at stations (cycle %.0f s)" % cyc)
	# A Cross-City train calls at every station along the line, not just the ends.
	for tr in trains._trains:
		if tr["line"]["name"] != "cross":
			continue
		var called := {}
		var c2: float = tr["cycle"]
		var tt := 0.0
		while tt < c2:
			trains._clock = tt
			trains._place_all()
			if float(tr["v"]) == 0.0:
				for st: float in tr["line"]["stations"]:
					if absf(float(tr["s"]) - st) < 3.0:
						called[st] = true
			tt += 0.5
		t.check(called.size() == (tr["line"]["stations"] as Array).size(),
			"a Cross-City train calls at all %d stations (%d)" % [(tr["line"]["stations"] as Array).size(), called.size()])
		break
	trains.queue_free()


func test_day_night_and_weather(t) -> void:
	var noon := Atmosphere.sun_angles(12.0)
	var midnight := Atmosphere.sun_angles(0.0)
	var dusk := Atmosphere.sun_angles(18.5)
	t.check(noon.x > 60.0, "high sun at noon (%.0f°)" % noon.x)
	t.check(midnight.x < -30.0, "sun well down at midnight")
	t.check(absf(dusk.x) < 1.0, "sunset about 18:30")
	t.check(absf(Atmosphere.sun_angles(Atmosphere.DEFAULT_HOUR).y - Atmosphere.SUN_ROT.y) < 0.01,
		"default hour keeps the golden-hour sun direction")
	# Continuous through the night (no jump at dusk/dawn).
	var prev := Atmosphere.sun_angles(0.0).x
	var worst := 0.0
	var h := 0.05
	while h < 24.0:
		var e := Atmosphere.sun_angles(h).x
		worst = maxf(worst, absf(e - prev))
		prev = e
		h += 0.05
	t.check(worst < 1.5, "sun moves smoothly round the clock")
	var a := Atmosphere.new()
	add_child(a)
	a.hour = 23.0
	a.set_weather("storm", true)
	a._apply(0.016, true)
	t.check(a.night > 0.95, "night at 23:00")
	t.check(float(a.w["rain"]) > 0.9 and a.wetness > 0.9, "a storm is wet")
	t.check(a.rain_fx.visible, "rain drawn in a storm")
	a.set_weather("clear", false)
	for i in 300:
		a._apply(0.5, false)
	t.check(float(a.w["rain"]) < 0.01 and not a.rain_fx.visible, "rain stops after the storm")
	t.check(a.wetness < 0.9 and a.wetness > 0.0, "streets dry slowly (%.2f)" % a.wetness)
	a.queue_free()


func test_player_rides_the_train(t) -> void:
	# A straight test line, a shuttle part-way through its run.
	var pts := PackedVector3Array()
	for i in 400:
		pts.append(Vector3(i * RailNetwork.STEP, 10.0, 0.0))
	var line := {"name": "test", "pts": pts, "loop": false, "tracks": [0.0], "stations": [24.0, 770.0], "cars": 3}
	var trains := Trains.new()
	add_child(trains)
	trains.setup([line], BoxMesh.new(), BoxMesh.new())
	trains._clock = Trains.DWELL + 30.0  # well under way
	trains._place_all()
	await get_tree().physics_frame
	var car: AnimatableBody3D = trains._trains[0]["cars"][1]
	var p := Player.new()
	p.params = load("res://config/swing_params.tres").duplicate()
	add_child(p)
	p.global_position = car.global_position + Vector3(0.0, 3.95 + 1.0, 0.0)
	for i in 30:  # land on the roof first
		await get_tree().physics_frame
	var car0 := car.global_position
	var p0 := p.global_position
	for i in 120:
		await get_tree().physics_frame
	var car_dx := car.global_position.x - car0.x
	var p_dx := p.global_position.x - p0.x
	t.note("car moved %.1f m, rider %.1f m, rider %.2f m above the roof" % [car_dx, p_dx,
		p.global_position.y - car.global_position.y - 3.95])
	t.check(car_dx > 10.0, "the train moved")
	t.check(absf(p_dx - car_dx) < 0.5, "the rider was carried with it")
	t.check(p.global_position.y > car.global_position.y + 3.5, "the rider is still on the roof")
	p.queue_free()
	trains.queue_free()
