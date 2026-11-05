extends Node
## World pass: the City Loop through the middle of the city, the
## hills and mountains round the bay, the power lines, Westbank's natural
## coast, and the airborne mantle over roof edges.

var _layout: CityLayout


func _lay() -> CityLayout:
	if _layout == null:
		_layout = CityLayout.new().generate()
	return _layout


func _line(name: String) -> Dictionary:
	for ln in _lay().rail.lines:
		if ln["name"] == name:
			return ln
	return {}


func test_city_loop_runs_through_the_middle(t) -> void:
	var ln := _line("city")
	t.check(not ln.is_empty(), "the City Loop exists")
	if ln.is_empty():
		return
	var pts: PackedVector3Array = ln["pts"]
	var to_cbd := INF
	for p in pts:
		to_cbd = minf(to_cbd, Vector2(p.x, p.z).distance_to(CityLayout.CBD_CENTER))
	t.check(to_cbd < 150.0, "through the business district (%.0f m from its centre)" % to_cbd)
	t.check((ln["stations"] as Array).size() >= 5, "%d stations" % (ln["stations"] as Array).size())
	# The deck (5.6 m wide, train on top) is clear of every building.
	var grid := _lay()._building_grid()
	var blocked := 0
	for i in range(0, pts.size(), 3):
		var p := pts[i]
		for b in grid.get(Vector2i(floori(p.x / 50.0), floori(p.z / 50.0)), []):
			if b["kind"] in ["normal", "landmark"] and CityLayout.inside(b, p + Vector3.UP * 2.0, RailNetwork.HALF + 0.5, 0.0):
				blocked += 1
				break
	t.check(blocked == 0, "no building in the way of the trains (%d samples blocked)" % blocked)
	# Over the strait on its own bridge, well clear of the water.
	var low := INF
	for p in pts:
		if p.x < -40.0 and p.x > CityLayout.FAR_SHORE + 20.0:
			low = minf(low, p.y)
	t.check(low > 15.0 and low < INF, "the rail bridge carries it high over the strait (%.1f m)" % low)


func test_hills_ring_the_bay_and_leave_the_city_at_sea_level(t) -> void:
	# The island and Westbank are inside the bay: no hinterland under them.
	for p: Vector2 in [Vector2(560, -170), Vector2(900, 400), Vector2(-800, 0), Vector2(100, -600)]:
		t.check(Hinterland.height_at(p.x, p.y) < -5.0, "open water / city at %s" % p)
	var west := -INF
	for z in range(-1200, 1300, 100):
		west = maxf(west, Hinterland.height_at(-3600.0, float(z)))
	t.check(west > 700.0, "mountains in the west (%.0f m)" % west)
	t.check(Hinterland.height_at(3800.0, 0.0) < 0.0, "open sea to the east")
	var north := -INF
	for x in range(-1500, 1500, 100):
		north = maxf(north, Hinterland.height_at(float(x), -2600.0))
	t.check(north > 150.0, "hills along the north (%.0f m)" % north)


func test_power_lines_stand_on_the_hills(t) -> void:
	var count := 0
	var wet := 0
	for route: Array in PowerLines.routes():
		for p: Vector3 in route:
			if p.y > 2.0:
				count += 1
			else:
				wet += 1
	t.check(count >= 20, "%d pylons on land" % count)
	t.check(wet < count / 4, "few route points in the water (skipped: %d)" % wet)


func test_westbank_is_not_a_rectangle(t) -> void:
	var ml := CityLayout.new().generate_mainland(1207)
	var area := CityRoads._area(ml.coast)
	var box := CityLayout._bbox(ml.coast)
	var fill := area / (box.size.x * box.size.y)
	t.check(fill < 0.8, "Westbank's outline fills %.0f%% of its bounding box (a rectangle would be ~100%%)" % (fill * 100.0))
	t.check(ml.buildings.size() > 250, "still a city (%d buildings)" % ml.buildings.size())


func test_mantle_onto_a_roof_from_the_air(t) -> void:
	var world := CityWorld.new()
	add_child(world)
	var player := Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	add_child(player)
	await get_tree().physics_frame
	# A roof edge: fly at it from outside, feet just under the parapet top.
	var tried := 0
	var made := 0
	for b in world.layout.buildings:
		if tried >= 6:
			break
		if b["kind"] != "normal" or b.has("apt") or b["tiers"].size() != 1 or b.get("roof_blocked", false):
			continue
		var tr: Array = b["tiers"][-1]
		if tr[2] - tr[0] < 20.0 or tr[3] - tr[1] < 20.0 or tr[5] - BuildingMesher.base_of(b) < 40.0:
			continue
		var X := CityLayout.bxf(b)
		var roof := BuildingMesher.roof_y(b)
		var zc: float = (tr[1] + tr[3]) * 0.5
		var start := X * Vector3(float(tr[2]) + 2.2, roof - 0.15, zc)
		var inward := (X.basis * Vector3.LEFT).normalized()
		# Is it really an edge: open air outside it, and above the roof (no
		# taller neighbour standing against this face)?
		if world.layout.ground_y(start.x, start.z) > start.y - 10.0:
			continue
		world.build_all_near(start, 150.0)  # (feature collision – signs, fire escapes – streams with the chunk)
		await get_tree().physics_frame
		var above := PhysicsRayQueryParameters3D.create(start + Vector3.UP * 2.8, start + Vector3.UP * 2.8 + inward * 5.0)
		if not world.get_world_3d().direct_space_state.intersect_ray(above).is_empty():
			continue
		tried += 1
		player.respawn(start + Vector3.UP * 0.9)
		player.s.velocity = inward * 9.0 + Vector3.UP * 0.5
		var on_roof := false
		for i in 50:
			await get_tree().physics_frame
			if player.is_on_floor() and player.global_position.y > roof:
				on_roof = true
				break
		if on_roof:
			made += 1
	t.check(tried >= 3, "found roof edges to try (%d)" % tried)
	t.check(made == tried, "flying into a roof edge just below its lip lands you on the roof (%d/%d)" % [made, tried])
	# A facade is still a wall: no climbing it.
	var b0: Dictionary = {}
	for b in world.layout.buildings:
		if b["kind"] == "normal" and float(b["tiers"][-1][5]) - BuildingMesher.base_of(b) > 80.0 and not b.has("apt"):
			b0 = b
			break
	var tr0: Array = b0["tiers"][0]
	var X0 := CityLayout.bxf(b0)
	var mid := X0 * Vector3(float(tr0[2]) + 2.0, BuildingMesher.base_of(b0) + 30.0, (float(tr0[1]) + float(tr0[3])) * 0.5)
	player.respawn(mid)
	var y0 := player.global_position.y
	player.s.velocity = (X0.basis * Vector3.LEFT).normalized() * 6.0
	var peak := y0
	for i in 30:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	t.check(peak - y0 < 0.5, "a facade 30 m up is not mantled (rose %.2f m)" % (peak - y0))
	player.queue_free()
	world.queue_free()
	await get_tree().process_frame
