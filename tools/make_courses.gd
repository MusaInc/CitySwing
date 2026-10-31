extends SceneTree
## Records Time Trial courses from real physics (see CourseBuilder).
##   godot --headless --fixed-fps 60 -s res://tools/make_courses.gd [-- id id ...]
## With ids, only those are (re)recorded and merged into the existing file.
## Writes config/courses.json. Re-run whenever physics or the city layout change
## (tests/test_modes.gd fails when the recorded courses stop being flyable).

const LIMIT_S := 180.0


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var only := OS.get_cmdline_user_args()
	var out: Dictionary = CourseBuilder._load_all() if not only.is_empty() else {}
	for id in CourseBuilder.COURSES:
		if not only.is_empty() and not id in only:
			continue
		# Swings are chaotic: a DNF is retried from a start nudged a few cm
		# (the exact start is stored, so replays stay bit-for-bit).
		for attempt in 6:
			if await _record(id, attempt, out):
				break
	var f := FileAccess.open(CourseBuilder.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  ", true, true))
	f.close()
	print("wrote ", CourseBuilder.PATH, " with ", out.keys())
	quit(0 if out.size() == CourseBuilder.COURSES.size() else 1)


func _record(id: String, attempt: int, out: Dictionary) -> bool:
	if true:
		# A fresh world per course: replays (tests) build theirs the same way,
		# and Jolt is only deterministic for identical world histories.
		var world := CityWorld.new()
		root.add_child(world)
		await physics_frame
		var r := CourseBuilder.route(id, world.layout)
		r["start"] += Vector3(0.11, 0.0, 0.07) * attempt
		var p := Player.new()
		p.params = load("res://config/swing_params.tres").duplicate()
		root.add_child(p)
		# Spawn exactly as TimeTrialMode does, so a replay is bit-for-bit the same flight.
		p.respawn(r["start"])
		p.last_safe_position = r["start"]
		var follower := RouteFollower.new(r["waypoints"])
		var bot := SwingBot.new(SwingBot.Style.EXPERT, Vector3.FORWARD)
		bot.goal_fn = follower.goal
		p.bot = bot
		var street := [false]
		p.landed.connect(func(_s, st): street[0] = street[0] or st)
		p.respawned.connect(func(): street[0] = true)
		var path: Array = [p.global_position]
		var t := 0.0
		var ok := false
		while t < LIMIT_S:
			await physics_frame
			t += 1.0 / 60.0
			if int(t * 60) % 6 == 0:
				path.append(p.global_position)
			if follower.done(p):
				ok = true
				break
		var gates := CourseBuilder.gates_from_path(world.layout, path)
		print("%-10s %s in %.1f s, %d gates, waypoint %d/%d, street contact: %s (try %d)" % [id, "OK " if ok else "DNF",
			t, gates.size(), follower.i + 1, follower.wps.size(), street[0], attempt + 1])
		if ok:
			var gs: Array = []
			for g in gates:
				gs.append({"pos": _a(g["pos"]), "dir": _a(g["dir"]), "half_w": snappedf(g["half_w"], 0.1),
					"half_h": g["half_h"]})
			# Start at full precision: swings are chaotic, 1 mm changes the run.
			var flown: Array = []
			for q in path:
				flown.append(_a(q))
			out[id] = {"path": flown, "start": [r["start"].x, r["start"].y, r["start"].z], "gates": gs, "par": snappedf(t * 1.1, 0.1), "recorded_s": snappedf(t, 0.1)}
		p.queue_free()
		world.queue_free()
		await process_frame
		return ok
	return false


static func _a(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
