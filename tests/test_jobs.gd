extends Node
## Contracts (src/core/contracts.gd) and the Free Swing JobBoard: rank
## ladder, contract generation on the real city, risk vs reward, heat and
## pursuit, payouts and fines, and a contract run end to end in the scene.


func _save() -> Node:
	return get_node("/root/SaveData")


func test_rank_ladder_opens_tiers(t) -> void:
	t.check(Contracts.rank_for(0) == 0 and Contracts.rank_name(0) == "Rookie", "a new player is a Rookie")
	t.check(Contracts.max_tier(0) == 1, "Rookies get tier-1 work")
	var last := -1
	for i in Contracts.RANK_REP.size():
		var r := Contracts.rank_for(Contracts.RANK_REP[i])
		t.check(r == i and r > last, "%s from %d rep" % [Contracts.RANKS[i], Contracts.RANK_REP[i]])
		last = r
	t.check(Contracts.max_tier(1000000) == 5, "tiers top out at 5")
	t.check(is_equal_approx(Contracts.rank_progress(Contracts.RANK_REP[1] / 2), 0.5), "progress bar is halfway between ranks")


func test_contracts_on_the_real_city(t) -> void:
	var layout := CityLayout.new().generate()
	var spots := JobBoard.spots_for(layout)
	var rescue: Array = spots[0].map(func(r): return r[0])
	var vantage: Array = spots[1]
	t.check(rescue.size() >= 20, "gondola spots on facades (%d)" % rescue.size())
	t.check(vantage.size() >= 15, "survey points over the skyline (%d)" % vantage.size())
	# Rooftop spots as the world provides them (top-centre of tall roofs, standing height).
	var roofs: Array = []
	for b in layout.buildings:
		var h: float = b["tiers"][-1][5] - BuildingMesher.base_of(b)
		if b["kind"] == "normal" and h > 50.0 and h < 150.0:
			roofs.append({"position": CityLayout.top_center(b) + Vector3.UP * 0.95})
	var grid := TokenField._tier_grid(layout)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var from := Vector3(560, 60, -120)  # the business district
	for type in Contracts.TYPES:
		var made := 0
		for tier in [1, 3, 5]:
			var c := Contracts.make(rng, type, tier, from, roofs, rescue, vantage)
			if c.is_empty():
				continue
			made += 1
			var pts: Array = [c["start"]] + c["stops"]
			var clear := true
			for i in pts.size():
				var p: Vector3 = pts[i]
				var kind: String = c["start_kind"] if i == 0 else c["stop_kinds"][i - 1]
				# Fly-through points must be in open air (a rescue gondola hangs on its
				# facade by design); landing spots stand on a roof.
				if kind == "pass" and not (type == "rescue" and i == 0) and TokenField._blocked(grid, p):
					clear = false
			t.check(clear, "%s t%d: fly-through points are in open air" % [type, tier])
			t.check(int(c["pay"]) > 0 and float(c["time"]) > 20.0 and int(c["rep"]) > 0, "%s t%d has pay, time, rep" % [type, tier])
			t.check(float(c["time"]) * 30.0 > Contracts.path_length(c), "%s t%d is possible at 108 km/h" % [type, tier])
		t.check(made >= 2, "%s contracts can be made in the city (%d/3)" % [type, made])


func test_risk_pays_more_than_safe_work(t) -> void:
	for d in [300.0, 700.0, 1100.0]:
		var safe := Contracts.pay_for("delivery", d, 3)
		var risky := Contracts.pay_for("hotdrop", d, 3)
		t.check(risky >= safe * 1.8, "underworld pays far more over %d m (%d vs %d)" % [d, risky, safe])
	t.check(Contracts.pay_for("delivery", 800.0, 5) > Contracts.pay_for("delivery", 800.0, 1), "higher tiers pay more")
	t.check(Contracts.time_for("express", 800.0) < Contracts.time_for("delivery", 800.0), "express is tighter")
	t.check(Contracts.rep_for("heist", 2) > Contracts.rep_for("delivery", 2), "risk earns more reputation")


func test_heat_builds_when_seen_and_cools_when_lost(t) -> void:
	var h := 0.0
	var secs := 0.0
	while h < 1.0 and secs < 60.0:
		h = Contracts.heat_step(h, true, false, 1, 0.1)
		secs += 0.1
	t.check(secs > 3.5 and secs < 7.0, "a drone on your shoulder busts you in ~5 s (%.1f s)" % secs)
	var street := 0.0
	var ss := 0.0
	while street < 1.0 and ss < 60.0:
		street = Contracts.heat_step(street, true, true, 1, 0.1)
		ss += 0.1
	t.check(ss < secs * 0.7, "much faster on the street (%.1f s)" % ss)
	var c := 0.8
	for i in 50:
		c = Contracts.heat_step(c, false, false, 3, 0.1)
	t.check(c < 0.5, "out of sight, heat cools (0.8 → %.2f in 5 s)" % c)
	# Outrunnable: the fastest drone is slower than a good swing line.
	t.check(Contracts.drone_speed(5) < 30.0, "drones top out at %.0f km/h – a fast line loses them" % (Contracts.drone_speed(5) * 3.6))


func test_objectives_need_the_right_move(t) -> void:
	var roof := Vector3(0, 80, 0)
	t.check(Contracts.reached("land", roof, roof + Vector3(3, 0, 0), roof + Vector3(4, 0, 2), true), "landing near the marker counts")
	t.check(not Contracts.reached("land", roof, roof + Vector3(3, 6, 0), roof + Vector3(4, 6, 2), false), "flying over it doesn't")
	t.check(not Contracts.reached("land", roof, roof + Vector3(30, 0, 0), roof + Vector3(30, 0, 1), true), "landing on the wrong roof doesn't")
	var ring := Vector3(0, 50, 0)
	t.check(Contracts.reached("pass", ring, ring + Vector3(-20, 2, 0), ring + Vector3(20, 2, 0), false), "a fly-through counts on the segment")
	t.check(not Contracts.reached("pass", ring, ring + Vector3(-20, 15, 0), ring + Vector3(20, 15, 0), false), "15 m off doesn't")


func test_payouts_bonus_and_fines(t) -> void:
	var ex := {"type": "express", "pay": 400, "rep": 30, "time": 60.0, "legal": true, "fine": 0}
	var clean := Contracts.settle(ex, "done", 30.0, 0)
	t.check(clean["coins"] == 500 and clean["bonus"] == 100, "express: half the time left pays +25%% (%d)" % clean["coins"])
	var bruised := Contracts.settle(ex, "done", 0.0, 2)
	t.check(bruised["coins"] == 240, "two knockouts cut a fragile parcel by 40%% (%d)" % bruised["coins"])
	var wrecked := Contracts.settle(ex, "done", 0.0, 9)
	t.check(wrecked["coins"] == int(400 * Contracts.EXPRESS_FLOOR), "never below the floor")
	var hot := {"type": "hotdrop", "pay": 900, "rep": 44, "time": 90.0, "legal": false, "fine": 315}
	t.check(Contracts.settle(hot, "busted", 10.0, 0)["coins"] == -315, "busted: fined")
	t.check(Contracts.settle(hot, "late", 0.0, 0)["coins"] == 0, "late: no pay, no fine")
	t.check(Contracts.settle(hot, "late", 0.0, 0)["rep"] == 0, "late: no reputation")
	# The save: a fine never takes you below zero, and the counters add up.
	var sd := _save()
	var before: Dictionary = sd.data.duplicate(true)
	sd.data["coins"] = 100
	var paid: int = sd.record_job(false, "busted", -315, 0)
	t.check(paid == -100 and int(sd.data["coins"]) == 0, "a fine takes what you hold, not more (%d)" % paid)
	sd.data["rep"] = 0
	sd.record_job(true, "done", 250, 30)
	t.check(int(sd.data["coins"]) == 250 and int(sd.data["rep"]) == 30, "pay and rep are banked")
	t.check(int(sd.data["jobs_done"]) == int(before.get("jobs_done", 0)) + 1, "jobs_done counts")
	sd.data = before
	sd.save()


func test_old_saves_load_without_contract_fields(t) -> void:
	var sd := _save()
	var before: Dictionary = sd.data.duplicate(true)
	var path := "user://test_old_save.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"coins": 1234, "homes": ["city"], "home": "city", "owned": ["hood_red"]}))
	f.close()
	var old_path: String = sd.path
	sd.use_file(path)
	t.check(int(sd.data["coins"]) == 1234 and "city" in sd.data["homes"], "purchases and coins survive")
	t.check(int(sd.data["rep"]) == 0 and int(sd.data["jobs_done"]) == 0, "contract fields default to zero")
	sd.use_file(old_path)
	sd.data = before
	sd.save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_job_board_runs_a_contract_in_the_city(t) -> void:
	var sd := _save()
	var before: Dictionary = sd.data.duplicate(true)
	sd.data["coins"] = 0
	sd.data["rep"] = 0
	var world := CityWorld.new()
	add_child(world)
	var player := Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	add_child(player)
	var hud := Hud.new()
	add_child(hud)
	hud.player = player
	var spot: Dictionary = world.rooftop_spawns()[0]
	player.respawn(spot["position"])
	await get_tree().physics_frame
	var jobs := JobBoard.new()
	world.add_child(jobs)
	jobs.setup(player, hud, null, world, 5)
	var legal := jobs.offers.filter(func(c): return c["legal"])
	t.check(legal.size() == JobBoard.LEGAL_OFFERS and jobs.offers.size() == JobBoard.LEGAL_OFFERS + JobBoard.CRIME_OFFERS,
		"3 legal and 2 underworld offers around you (%d/%d)" % [legal.size(), jobs.offers.size()])
	t.check(jobs.markers().size() == jobs.offers.size(), "every offer is on the minimap")
	# A rooftop job: take it by landing on its roof, finish by landing on the drop.
	var c: Dictionary = {}
	for o in jobs.offers:
		if o["start_kind"] == "land":
			c = o
			break
	if c.is_empty():
		t.check(false, "no landing offer to run")
	else:
		jobs.track(c["id"])
		t.check(jobs.objective() == c["start"], "tracking points the route at the pickup")
		player.respawn(c["start"])
		for i in 20:
			await get_tree().physics_frame
		t.check(not jobs.active.is_empty() and jobs.active["id"] == c["id"], "landing on the beacon roof takes the job")
		t.check(jobs.offers.size() == 4, "the taken offer leaves the board")
		if c["heat"]:
			t.check(jobs._drones.size() == int(c["drones"]), "underworld work brings %d drone(s)" % int(c["drones"]))
		var drop: Vector3 = c["stops"][0]
		player.respawn(drop)
		for i in 20:
			await get_tree().physics_frame
		t.check(jobs.active.is_empty() and jobs.toast.get("outcome", "") == "done", "landing on the drop roof completes it")
		t.check(int(sd.data["coins"]) >= int(c["pay"]) and int(sd.data["rep"]) == int(c["rep"]),
			"paid %d coins and %d rep" % [int(sd.data["coins"]), int(sd.data["rep"])])
		t.check(jobs._drones.is_empty(), "drones leave when the job ends")
		t.check(jobs.offers.size() == 5, "the board refills")
	# Running out of time fails without pay.
	var o2: Dictionary = jobs.offers[0]
	jobs._begin(o2)
	var coins_before := int(sd.data["coins"])
	jobs.time_left = 0.05
	for i in 6:
		await get_tree().physics_frame
	t.check(jobs.active.is_empty() and jobs.toast.get("outcome", "") == "late", "the clock running out fails the job")
	t.check(int(sd.data["coins"]) == coins_before, "no pay for a late job")
	jobs.queue_free()
	hud.queue_free()
	player.queue_free()
	world.queue_free()
	await get_tree().process_frame
	sd.data = before
	sd.save()


func test_drones_chase_and_spot(t) -> void:
	var world := CityWorld.new()
	add_child(world)
	var player := Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	add_child(player)
	var hud := Hud.new()
	add_child(hud)
	hud.player = player
	var spot: Dictionary = world.rooftop_spawns()[3]
	player.respawn(spot["position"])
	await get_tree().physics_frame
	var jobs := JobBoard.new()
	world.add_child(jobs)
	jobs.setup(player, hud, null, world, 9)
	var crime: Dictionary = jobs.offers.filter(func(c): return not c["legal"])[0]
	jobs._begin(crime)
	var d0: float = (jobs._drones[0] as Node3D).global_position.distance_to(player.global_position)
	var peak := 0.0
	for i in 660:
		await get_tree().physics_frame
		jobs.time_left = 100.0
		peak = maxf(peak, jobs.heat)
		if jobs.active.is_empty():
			break
	var reached := jobs.active.is_empty() or (jobs._drones[0] as Node3D).global_position.distance_to(player.global_position) < 20.0
	t.check(d0 > 50.0, "drones arrive from a distance (%.0f m)" % d0)
	t.check(reached, "they close in on a player standing still")
	t.check(peak > 0.6, "standing still in view, heat climbs (peak %.2f)" % peak)
	jobs.queue_free()
	hud.queue_free()
	player.queue_free()
	world.queue_free()
	await get_tree().process_frame
