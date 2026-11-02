extends Node
## Homes (Apartments + HomeSystem): real rooms in real buildings; spawning in
## one, running out of the window, catching the sill and climbing back in,
## vaulting in, refusing reckless entries; ownership and purchases.

var world: CityWorld
var player: Player
var rig: CharacterRig
var hs: HomeSystem


func setup() -> void:
	world = CityWorld.new()
	add_child(world)
	player = Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	add_child(player)
	rig = CharacterRig.new()
	player.add_child(rig)
	rig.set_player(player)
	hs = HomeSystem.new()
	add_child(hs)
	hs.setup(player, rig, world.layout)
	await get_tree().physics_frame


func teardown() -> void:
	hs.queue_free()
	player.queue_free()
	world.queue_free()
	await get_tree().process_frame


class _Drive:
	extends RefCounted
	var move := Vector3.ZERO
	var jump := false
	func drive(_p, _dt) -> Dictionary:
		var j := jump
		jump = false
		return {"move": move, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": j}


func test_five_homes_in_real_buildings_with_views(t) -> void:
	var homes: Array = world.layout.apartments.homes
	t.check(homes.size() == 5, "five homes placed (%d)" % homes.size())
	var last := -1.0
	var tallest := 0.0
	for b in world.layout.buildings:
		var top: Array = b["tiers"][-1]
		var fits := minf(float(top[2]) - float(top[0]), float(top[3]) - float(top[1])) >= float(Apartments.TIERS[4]["d"]) + 3.0 \
			and maxf(float(top[2]) - float(top[0]), float(top[3]) - float(top[1])) >= float(Apartments.TIERS[4]["w"]) + 3.0
		if b["kind"] == "normal" and fits:
			tallest = maxf(tallest, float(top[5]) - BuildingMesher.base_of(b))
	for h in homes:
		var fh := Apartments.floor_height(h)
		t.check(fh > last, "%s higher than the tier below (%.0f m)" % [h["id"], fh])
		last = fh
		# Inside its building's tier, with the room cut out of the collision.
		var t_: Array = h["b"]["tiers"][h["t"]]
		var room := Apartments.room_box(h)
		t.check(room.position.y >= float(t_[4]) and room.end.y <= float(t_[5]), "%s room inside its tier" % h["id"])
		var cut := true
		for bx in BuildingMesher.collision_boxes(h["b"]):
			if bx.grow(-0.05).intersects(room.grow(-0.35)):
				cut = false
		t.check(cut, "%s: no building collision inside the room" % h["id"])
	var pent: Dictionary = homes[-1]
	t.check(Apartments.floor_height(pent) > 250.0 and float(pent["b"]["tiers"][-1][5]) - BuildingMesher.base_of(pent["b"]) >= tallest - 40.0,
		"the penthouse is near the top of one of the tallest towers that can hold it (%.0f m up, tallest %.0f m)" % [Apartments.floor_height(pent), tallest])
	t.note("homes: %s" % ", ".join(homes.map(func(h): return "%s %.0f m" % [h["id"], Apartments.floor_height(h)])))


func test_spawn_inside_and_run_out_of_the_window(t) -> void:
	var h := hs.home_by_id("starter")
	hs.spawn_in(h, world, null)
	var d := _Drive.new()
	player.bot = d
	for i in 60:
		await get_tree().physics_frame
	t.check(hs.inside() == "starter", "still standing in the bedsit after a second")
	t.check(player.is_on_floor(), "on the floor, not falling")
	# Run at the window.
	d.move = Apartments.outward(h)
	var out := false
	for i in 240:
		await get_tree().physics_frame
		if Apartments.to_face(h, player.global_position).y > 1.0 and player.global_position.y < float(h["y0"]) - 1.0:
			out = true
			break
	t.check(out, "ran out of the window and dropped into the air")
	player.bot = null


func test_catch_the_sill_and_climb_in(t) -> void:
	var h := hs.home_by_id("city")
	var n := Apartments.outward(h)
	var a := (float(h["oa0"]) + float(h["oa1"])) * 0.5
	# Coming in slowly from 1.6 m out, a little below the sill.
	player.respawn(Apartments.face_point(h, a, 1.6, float(h["oy0"]) - 0.6) + Vector3.UP * 0.9)
	player.s.velocity = -n * 4.0 + Vector3.UP * 1.0
	var seen := {}
	for i in 120:
		await get_tree().physics_frame
		if hs.state != "":
			seen[hs.state] = true
	t.check(seen.has("grab") and seen.has("hang") and seen.has("climb"), "grab → hang → climb (%s)" % str(seen.keys()))
	t.check(hs.inside() == "city", "ends up inside the flat")
	for i in 30:
		await get_tree().physics_frame
	t.check(player.is_on_floor() and not player.scripted, "standing on the floor, in control")


func test_vault_in_fast_and_refuse_reckless_entry(t) -> void:
	var h := hs.home_by_id("loft")
	var n := Apartments.outward(h)
	var a := (float(h["oa0"]) + float(h["oa1"])) * 0.5
	player.respawn(Apartments.face_point(h, a, 2.2, float(h["oy0"]) + 0.3) + Vector3.UP * 0.9)
	player.s.velocity = -n * 13.0
	var vaulted := false
	for i in 60:
		await get_tree().physics_frame
		vaulted = vaulted or hs.state == "vault"
	t.check(vaulted and hs.inside() == "loft", "a fast square approach vaults straight in")
	# Far too fast: no entry (the building is met the usual way).
	player.respawn(Apartments.face_point(h, a, 2.2, float(h["oy0"]) + 0.3) + Vector3.UP * 0.9)
	player.s.velocity = -n * 30.0
	var entered := false
	for i in 20:
		await get_tree().physics_frame
		entered = entered or hs.state != ""
	t.check(not entered, "30 m/s: no magnet, no teleport")
	# Flying past (along the facade, not toward it): no entry.
	player.respawn(Apartments.face_point(h, a - 3.0, 1.5, float(h["oy0"]) + 0.3) + Vector3.UP * 0.9)
	player.s.velocity = Apartments.along_dir(h) * 12.0
	entered = false
	for i in 20:
		await get_tree().physics_frame
		entered = entered or hs.state != ""
	t.check(not entered, "skimming past the window doesn't pull you in")


func test_ownership_and_purchases(t) -> void:
	var sd := get_node("/root/SaveData")
	var before: Dictionary = sd.data.duplicate(true)
	sd.data["homes"] = []
	sd.data["home"] = "starter"
	sd.data["coins"] = 2000
	t.check(Homes.owns("starter") and not Homes.owns("city"), "starter owned from the start")
	t.check(not Homes.buy("loft"), "can't buy what you can't afford")
	t.check(Homes.buy("city") and Homes.owns("city") and Homes.selected() == "city", "buy → owned and home")
	t.check(int(sd.data["coins"]) == 2000 - Homes.price("city"), "paid with coins")
	t.check(Homes.select("starter") and Homes.selected() == "starter", "switch home back")
	t.check(not Homes.select("penthouse"), "can't live in a home you don't own")
	sd.data = before
	sd.save()


func test_every_home_spawn_and_window_corridor(t) -> void:
	for h in hs.homes:
		hs.spawn_in(h, world, null)
		for i in 30:
			await get_tree().physics_frame
		t.check(hs.inside() == h["id"] and player.is_on_floor(), "%s stable grounded spawn" % h["id"])
		var n := Apartments.outward(h)
		var a := Apartments.spawn_point(h)
		var q := PhysicsRayQueryParameters3D.create(a, Apartments.window_center(h) + n * 3.0 + Vector3.UP * 0.95, player.collision_mask)
		q.exclude = [player.get_rid()]
		t.check(player.get_world_3d().direct_space_state.intersect_ray(q).is_empty(), "%s clear window exit" % h["id"])


func test_respawn_cancels_window_transition(t) -> void:
	var h := hs.home_by_id("city")
	var a := (float(h["oa0"]) + float(h["oa1"])) * 0.5
	player.respawn(Apartments.face_point(h, a, 1.6, float(h["oy0"]) + 0.3) + Vector3.UP * 0.9)
	player.s.velocity = -Apartments.outward(h) * 13.0
	t.check(hs._try_enter(h), "vault began")
	hs.spawn_in(hs.home_by_id("starter"), world, null)
	for i in 45:
		await get_tree().physics_frame
	t.check(hs.state == "" and not player.scripted and hs.inside() == "starter", "respawn cancels old window path")


func test_vault_speeds_remain_inside_window_clearance(t) -> void:
	for h in hs.homes:
		world.build_all_near(Apartments.window_center(h), 80.0)
		for speed: float in [9.0, 16.0, 23.0]:
			var a := (float(h["oa0"]) + float(h["oa1"])) * 0.5
			player.respawn(Apartments.face_point(h, a, 2.0, float(h["oy0"]) + 1.2))
			player.s.velocity = -Apartments.outward(h) * speed
			t.check(hs._try_enter(h), "%s %.0f m/s starts entry" % [h["id"], speed])
			var shape := CapsuleShape3D.new()
			shape.radius = 0.28
			shape.height = 1.7
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shape
			q.collision_mask = 1 | CityWorld.HUMAN_LAYER
			q.exclude = [player.get_rid()]
			var clear := true
			for i in 30:
				await get_tree().physics_frame
				q.transform = Transform3D(Basis.IDENTITY, player.global_position)
				clear = clear and player.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()
				if hs.state == "":
					break
			t.check(clear and hs.inside() == h["id"], "%s %.0f m/s capsule clears frame and lands inside" % [h["id"], speed])


## Steers like a player (turn assist on), as the review tools do.
class _Walk:
	extends RefCounted
	var move := Vector3.ZERO
	var human_steer := true
	func drive(_p, _dt) -> Dictionary:
		return {"move": move, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}


func test_indoor_camera_keeps_the_hero_in_view(t) -> void:
	# Walk each home's route (tools/home_cam_probe.gd: into the bedrooms and
	# bathrooms, up the penthouse stairs and along the mezzanine) behind the
	# real follow camera: the lens never leaves the room and the hero is
	# hidden behind walls or furniture for at most ~2% of frames.
	var routes: Dictionary = preload("res://tools/home_cam_probe.gd").ROUTES
	var probe = preload("res://tools/home_cam_probe.gd").new()
	var cam := SwingCamera.new()
	add_child(cam)
	cam.set_target(player)
	hs.camera = cam
	for h in hs.homes:
		world.build_all_near(Apartments.window_center(h), 120.0)
		hs.spawn_in(h, world, cam)
		var d := _Walk.new()
		player.bot = d
		for i in 10:
			await get_tree().process_frame
		var frames := 0
		var outside := 0
		var hidden := 0
		var reached := 0
		var top := 0.0
		for wp: Array in routes[h["id"]]:
			var goal := Apartments.face_point(h, float(h["a0"]) + float(wp[0]), -float(wp[1]), float(h["y0"]))
			for i in 420:
				var to := goal - player.global_position
				to.y = 0.0
				if to.length() < 0.5:
					reached += 1
					break
				d.move = to.normalized() * (0.55 if to.length() < 2.0 else 1.0)
				await get_tree().process_frame
				frames += 1
				top = maxf(top, player.global_position.y - float(h["y0"]))
				var f := Apartments.to_face(h, cam.global_position)
				if not (f.x > float(h["a0"]) and f.x < float(h["a1"]) and f.y < 0.0 and f.y > -float(h["depth"])
						and f.z > float(h["y0"]) and f.z < float(h["y1"])) and not probe.in_opening(h, f):
					outside += 1
				var q := PhysicsRayQueryParameters3D.create(cam.global_position, player.global_position + Vector3.UP * 0.4,
					1 | CityWorld.HUMAN_LAYER)
				q.exclude = [player.get_rid()]
				var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
				if not hit.is_empty() and not probe._thin(hit):
					hidden += 1
		d.move = Vector3.ZERO
		player.bot = null
		var n: int = routes[h["id"]].size()
		t.check(reached == n, "%s: walked the whole route (%d/%d waypoints)" % [h["id"], reached, n])
		t.check(outside == 0, "%s: lens stays in the room (%d of %d frames outside)" % [h["id"], outside, frames])
		t.check(hidden <= frames / 50, "%s: hero in view (%d of %d frames hidden)" % [h["id"], hidden, frames])
		if h["id"] == "penthouse":
			t.check(top > HomeInteriors.MEZZ + 0.5, "penthouse: climbed the stairs to the mezzanine (%.2f m)" % top)
	probe.free()
	hs.camera = null
	cam.queue_free()
