extends Node
## The homes as places worth owning: five interiors that differ in plan,
## materials and things (not recolours), the window band kept clear for
## entries and exits, the penthouse mezzanine you can climb to, the progress
## board, and the "rested" coin bonus for coming home.


func _homes() -> Array:
	return CityLayout.new().generate().apartments.homes


func test_every_home_is_its_own_place(t) -> void:
	var homes := _homes()
	t.check(homes.size() == 5, "five homes")
	var floors := {}
	var signatures := {}
	for h in homes:
		var I := HomeInteriors.new()
		I.h = h
		var root := I._build(StandardMaterial3D.new())
		var tier: int = h["tier"]
		floors[int(HomeInteriors.PALETTE[tier][3])] = true
		var kinds := {}
		for c in root.get_children():
			kinds[String(c.name).rstrip("0123456789")] = kinds.get(String(c.name).rstrip("0123456789"), 0) + 1
		t.check(kinds.has("Glow"), "%s has lamps that glow" % h["id"])
		t.check(root.find_children("*", "HomeBoard", true, false).size() == 1, "%s has a progress board" % h["id"])
		t.check(I.walls_fx.size() >= 1, "%s has a feature wall finish (%d)" % [h["id"], I.walls_fx.size()])
		t.check(I.m.verts.size() > 3000, "%s is furnished (%d vertices)" % [h["id"], I.m.verts.size()])
		signatures[[I.walls_fx.map(func(f): return f[6]), I.assets.map(func(a): return a[0]), I.pools.size()]] = true
		root.free()
	t.check(floors.size() == 5, "five different floor finishes")
	t.check(signatures.size() == 5, "no two homes share their walls + furniture + features")


func test_window_band_stays_clear(t) -> void:
	# Window entries land up to ~1.1 m in anywhere across the opening, and the
	# hero runs out from the spawn spot: no furniture collision in that band.
	for h in _homes():
		var I := HomeInteriors.new()
		I.h = h
		var root := I._build(StandardMaterial3D.new())
		var a := I.P(I.ox0() - 0.3, 0.0, 0.25)
		var b := I.P(I.ox1() + 0.3, 2.6, 1.9)
		var band := AABB(a.min(b), (b - a).abs())
		var hits := 0
		for bx: AABB in I.col_boxes:
			if bx.intersects(band):
				hits += 1
		t.check(hits == 0, "%s: nothing solid within 2.6 m of the opening (%d boxes)" % [h["id"], hits])
		root.free()


func test_penthouse_mezzanine_is_climbable(t) -> void:
	var pent: Dictionary = _homes().filter(func(h): return h["id"] == "penthouse")[0]
	var I := HomeInteriors.new()
	I.h = pent
	var root := I._build(StandardMaterial3D.new())
	var floor_y := float(pent["y0"])
	var tops: Array = []
	for bx: AABB in I.col_boxes:
		tops.append(snappedf(bx.end.y - floor_y, 0.01))
	tops.sort()
	var deck := tops.filter(func(y): return y > 2.8 and y < 3.1)
	t.check(not deck.is_empty(), "a walkable mezzanine deck about 2.95 m up")
	# Stairs: tops rising in steps no taller than the player can climb.
	var rises: Array = tops.filter(func(y): return y > 0.2 and y <= 2.75)
	var stairs := 0
	var last := 0.0
	for y in rises:
		if y - last <= Player.STEP_MAX + 0.001 and y > last:
			stairs += 1
			last = y
	t.check(last >= 2.69, "stair treads reach the deck in steps ≤ %.2f m (%d treads, top %.2f)" % [Player.STEP_MAX, stairs, last])
	t.check(I.pools.size() == 1, "a plunge pool")
	root.free()


func test_board_shows_progress(t) -> void:
	var txt := HomeBoard.board_text({"rep": 400, "jobs_done": 12, "jobs_crime": 3, "tokens": [1, 2, 3],
		"best_chain": 41, "top_speed_ms": 40.0, "total_distance_m": 12345.0}, 4)
	t.check(txt.begins_with("HALL OF FAME"), "the penthouse board is the Hall of Fame")
	t.check(txt.contains("COURIER") and txt.contains("12 contracts") and txt.contains("3 / %d tokens" % Progress.TOKEN_TOTAL),
		"rank, contracts and tokens on the board")
	t.check(txt.contains("×41") and txt.contains("144 km/h") and txt.contains("12.3 km"), "records on the board")


func test_rested_bonus_lifts_the_multiplier(t) -> void:
	var c := CoinMeter.new()
	add_child(c)
	c.active = true
	t.check(not c.rested(0), "the starter home doesn't change the multiplier")
	t.check(c.rested(4) and is_equal_approx(c.multiplier(), 3.0), "the penthouse rests you to ×3")
	t.check(not c.rested(2) and is_equal_approx(c.multiplier(), 3.0), "a lesser home never lowers it")
	c.level = 6
	t.check(not c.rested(4), "already higher: no change")
	c.active = false
	c.level = 0
	t.check(not c.rested(4), "outside a run, nothing happens")
	c.queue_free()
