extends SceneTree
## Player-feel probe: plays the real game with HUMAN input (stick + the SWING
## action, no autopilot) and measures what the flow layer is for.
##   godot --headless --fixed-fps 60 -s res://tools/flow_probe.gd -- [--runs=N] [--secs=S] [--plain]
##  * swing: from N rooftop spawns, holds the stick forward and swings like a
##    simple player (fire when falling, let go on the upswing). Reports mean /
##    90th-percentile speed in the air, street touches and knockouts.
##    --plain switches the flow layer off for a before/after on the same spawns.
##  * climb: sprints at the foot of N facades. Reports whether the run up the
##    wall started, how high it went and whether it topped out onto the roof.
var main: Node3D
var runs := 4
var secs := 25.0
var plain := false
var knockouts := 0
var street := 0
var topped := false
var climbed := false


func _initialize() -> void:
	go.call_deferred()


func go() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs = int(a.trim_prefix("--runs="))
		elif a.begins_with("--secs="):
			secs = float(a.trim_prefix("--secs="))
		elif a == "--plain":
			plain = true
	root.get_node("SaveData").use_file("user://flow_probe_save.json")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 12:
		await process_frame
	var p: Player = main.player
	p.bot = null
	if plain:
		p.params.flow_accel = 0.0
		p.params.flow_drag_scale = 1.0
		p.params.flow_release_boost = 1.0
		p.params.flow_release_lift = 0.0
	p.stun_started.connect(func(_s): knockouts += 1)
	p.landed.connect(func(_s, on_street: bool): street += int(on_street))
	p.wall_topped.connect(func(): topped = true)
	main.start_mode("free", "")
	for i in 30:
		await physics_frame
	var all: Array[float] = []
	for r in (0 if OS.get_environment("CLIMB_ONLY") != "" else runs):
		var speeds := await _swing_run(p)
		all.append_array(speeds)
		speeds.sort()
		print("FLOW run %d: mean %.1f m/s  p90 %.1f  max %.1f  street %d  KO %d  swings %d" % [r,
			_mean(speeds), speeds[int(speeds.size() * 0.9)] if speeds.size() > 0 else 0.0,
			speeds[-1] if speeds.size() > 0 else 0.0, street, knockouts, p.swings])
	all.sort()
	print("FLOW %s: mean %.1f m/s (%.0f km/h)  p90 %.1f  street %d  KO %d" % ["plain" if plain else "flow",
		_mean(all), _mean(all) * 3.6, all[int(all.size() * 0.9)] if all.size() > 0 else 0.0, street, knockouts])
	var ok := 0
	for r in runs:
		ok += int(await _climb_run(p, r))
	print("WALL all-ok %d/%d" % [ok, runs])
	_release_all()
	main.queue_free()
	await process_frame
	quit()


func _mean(a: Array[float]) -> float:
	var t := 0.0
	for x in a:
		t += x
	return t / maxf(a.size(), 1.0)


func _release_all() -> void:
	for act in ["move_forward", "grapple", "jump"]:
		Input.action_release(act)


func _swing_run(p: Player) -> Array[float]:
	main.spawn_on_random_rooftop()
	p.bot = null
	street = 0
	knockouts = 0
	p.swings = 0
	for i in 10:
		await physics_frame
	Input.action_press("move_forward")
	# Run off the roof, then swing.
	var speeds: Array[float] = []
	var t := 0.0
	var held := false
	var held_t := 0.0
	var since_release := 0.0
	while t < secs:
		await physics_frame
		var dt := 1.0 / 60.0
		t += dt
		var v := p.s.velocity
		var airborne := not p.is_on_floor()
		if airborne and not p.stunned:
			speeds.append(v.length())
		var shots := OS.get_environment("SHOTS")
		if shots != "" and t > 3.0 and t < 15.0 and int(t * 60.0) % 24 == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/swing_%05.2f.png" % [shots, t])
		if p.stunned:
			if held:
				Input.action_release("grapple")
				held = false
			continue
		if not held:
			since_release += dt
			var low := p.height_above_ground() < 14.0
			if airborne and (v.y < -2.0 and since_release > 0.35 or low and since_release > 0.15):
				Input.action_press("grapple")
				held = true
				held_t = 0.0
		else:
			held_t += dt
			var spd := v.length()
			var up := rad_to_deg(asin(clampf(v.y / maxf(spd, 0.01), -1.0, 1.0)))
			if p.line_state == Player.Line.IDLE and held_t > 0.3:
				Input.action_release("grapple")  # missed: try again
				held = false
				since_release = 0.3
			elif p.s.attached and (up > 25.0 and spd > 10.0 or held_t > 3.5):
				Input.action_release("grapple")
				held = false
				since_release = 0.0
	_release_all()
	return speeds


## Wall moves at real facades: (a) sprint head-on into the wall, (b) fly at
## it at a glancing angle, (c) arrive slow just under a roof edge.
func _climb_run(p: Player, r: int) -> bool:
	var world: CityWorld = main.world
	var lay: CityLayout = world.layout
	var picked := {}
	var tries := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + r
	var space := p.get_world_3d().direct_space_state
	while picked.is_empty() and tries < 400:
		tries += 1
		var b: Dictionary = lay.buildings[rng.randi() % lay.buildings.size()]
		var bc: Vector2 = CityLayout.base_center(b)
		var g := lay.ground_y(bc.x, bc.y)
		var h := BuildingMesher.roof_y(b) - g
		if h < 22.0 or h > 70.0:
			continue
		var ang := rng.randf() * TAU
		var mid := g + h * 0.5
		var from := Vector3(bc.x, mid, bc.y) + Vector3(cos(ang), 0, sin(ang)) * 60.0
		world.build_all_near(from, 200.0)
		for i in 3:
			await physics_frame
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, Vector3(bc.x, mid, bc.y), Player.BUILDINGS_MASK))
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.2:
			continue
		var n: Vector3 = hit.normal
		var fg := lay.ground_y(hit.position.x, hit.position.z)
		# Street-level run-up clear?
		var st: Vector3 = Vector3(hit.position.x, fg + 1.0, hit.position.z) + n * 16.0
		var foot := space.intersect_ray(PhysicsRayQueryParameters3D.create(st, Vector3(hit.position.x, fg + 1.0, hit.position.z) + n * 0.6, Player.BUILDINGS_MASK | (1 << 4)))
		# This face's top edge: walk up it until a ray into it misses.
		var y: float = hit.position.y
		var probe_o: Vector3 = hit.position + n * 1.5
		while y < hit.position.y + 300.0:
			var o := Vector3(probe_o.x, y + 0.5, probe_o.z)
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o - n * 2.5, Player.BUILDINGS_MASK)).is_empty():
				break
			y += 0.5
		var top_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(hp_x(hit, n), y + 3.0, hp_z(hit, n)), Vector3(hp_x(hit, n), y - 3.0, hp_z(hit, n)), Player.BUILDINGS_MASK))
		if top_hit.is_empty():
			continue
		picked = {"hit": hit.position, "n": n, "g": fg, "top": (top_hit.position as Vector3).y, "street_ok": foot.is_empty(), "start": st}
	if picked.is_empty():
		print("WALL %d: no facade" % r)
		return false
	var n: Vector3 = picked["n"]
	var hp: Vector3 = picked["hit"]
	var yaw := atan2(n.x, n.z)
	var along := n.cross(Vector3.UP).normalized()
	var ok := true
	# (a) sprint head-on
	if picked["street_ok"]:
		var res := await _wall_case(p, picked["start"], Vector3.ZERO, -n, yaw, 4.0)
		var rise: float = res["max_y"] - float(picked["start"].y)
		print("WALL %d a sprint: run=%s rise %.1f m launched=%s KO=%s" % [r, res["ran"], rise, res["launched"], res["ko"]])
		ok = ok and res["ran"] and rise < 15.0 and not res["ko"]
	# (b) glancing flight: 26 m/s at 35° to the facade, 18 m up
	var gy := float(picked["g"]) + clampf(float(picked["top"]) - float(picked["g"]) - 12.0, 8.0, 18.0)
	var dir := (along * cos(deg_to_rad(35.0)) - n * sin(deg_to_rad(35.0))).normalized()
	var b_start := Vector3(hp.x, gy, hp.z) + n * 6.0 - dir * 6.0 / sin(deg_to_rad(35.0)) * 0.0 - along * 8.0
	var res_b := await _wall_case(p, b_start, dir * 26.0, dir, atan2(-dir.x, -dir.z), 3.0)
	print("WALL %d b glance: run=%s speed in 26.0 → out %.1f m/s launched=%s KO=%s" % [r, res_b["ran"], res_b["out_speed"], res_b["launched"], res_b["ko"]])
	ok = ok and res_b["ran"] and float(res_b["out_speed"]) > 18.0 and not res_b["ko"]
	# (c) slow, just under the roof edge
	var c_start := Vector3(hp.x, float(picked["top"]) - 2.0, hp.z) + n * 0.5
	var res_c := await _wall_case(p, c_start, Vector3.UP * 3.0, -n, yaw, 2.5, float(picked["top"]) - 0.5)
	print("WALL %d c scramble: on roof=%s (top %.1f, ended %.1f)" % [r, res_c["roof"] and res_c["end_y"] > float(picked["top"]) - 0.5,
		float(picked["top"]), res_c["end_y"]])
	ok = ok and res_c["end_y"] > float(picked["top"]) - 0.5 and res_c["roof"]
	return ok


func _wall_case(p: Player, at: Vector3, vel: Vector3, push: Vector3, yaw: float, dur: float, stop_above := INF) -> Dictionary:
	p.respawn(at)
	main.rig.set_facing(push)
	main.camera.face(yaw)
	for i in 3:
		await physics_frame
	p.global_position = at
	p.s.velocity = vel
	var st := {"ran": false, "launched": false, "out": 0.0}
	var c1 := func(_n): st["ran"] = true
	var c2 := func(): st["launched"] = true; st["out"] = p.s.velocity.length()
	p.wall_run_started.connect(c1)
	p.wall_run_launched.connect(c2)
	var max_y := at.y
	var t := 0.0
	while t < dur:
		# The stick in world terms (the probe steers relative to the camera).
		var cam_fwd: Vector3 = -main.camera.global_transform.basis.z
		cam_fwd.y = 0.0
		cam_fwd = cam_fwd.normalized()
		var cam_r: Vector3 = main.camera.global_transform.basis.x
		cam_r.y = 0.0
		cam_r = cam_r.normalized()
		Input.action_press("move_forward", clampf(push.dot(cam_fwd), 0.0, 1.0))
		if push.dot(cam_r) > 0.05:
			Input.action_press("move_right", push.dot(cam_r))
		else:
			Input.action_release("move_right")
		if push.dot(cam_r) < -0.05:
			Input.action_press("move_left", -push.dot(cam_r))
		else:
			Input.action_release("move_left")
		await physics_frame
		t += 1.0 / 60.0
		max_y = maxf(max_y, p.global_position.y)
		var shots := OS.get_environment("SHOTS")
		if shots != "" and int(t * 60.0) % 9 == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/wall_%s_%.0f_%04.2f.png" % [shots, "%.0f" % at.y, at.x, t])
		if p.is_on_floor() and p.global_position.y - 0.9 > stop_above:
			break
		if OS.get_environment("CLIMB_DEBUG") != "" and int(t * 60.0) % 6 == 0:
			print("   t=%.2f y=%.1f run=%s wall=%s floor=%s v=%s" % [t, p.global_position.y, p.wall_run, p.is_on_wall(), p.is_on_floor(), p.s.velocity.snapped(Vector3.ONE * 0.1)])
	for a in ["move_forward", "move_left", "move_right"]:
		Input.action_release(a)
	p.wall_run_started.disconnect(c1)
	p.wall_run_launched.disconnect(c2)
	return {"ran": st["ran"], "launched": st["launched"], "out_speed": st["out"], "max_y": max_y, "ko": p.stunned,
		"end_y": p.global_position.y - 0.9, "roof": p.is_on_floor()}


func hp_x(hit: Dictionary, n: Vector3) -> float:
	return (hit.position - n * 0.8).x


func hp_z(hit: Dictionary, n: Vector3) -> float:
	return (hit.position - n * 0.8).z
