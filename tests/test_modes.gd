extends Node
## Game-mode tests.
## Courses (config/courses.json) are recorded from real autopilot flights.
##  * The recorded flight, fed through TimeTrialMode's gate check, must clear
##    every gate in order (course data and gate logic agree – deterministic).
##  * A fresh flight with today's physics through the real TimeTrialMode must
##    clear most gates (swinging is chaotic, so exact replays aren't expected);
##    a failure here means physics/layout drifted – re-run tools/make_courses.gd.
## Plus Endurance rules and personal-best persistence.

var world: CityWorld


func setup() -> void:
	# Fresh world per test: course replays must match the recorder's history.
	world = CityWorld.new()
	add_child(world)
	await get_tree().physics_frame


func teardown() -> void:
	world.queue_free()
	await get_tree().process_frame


func _player() -> Player:
	var p := Player.new()
	p.params = load("res://config/swing_params.tres").duplicate()
	add_child(p)
	return p


func _run_course(t, id: String, limit_s: float) -> void:
	var p := _player()
	var hud := Hud.new()
	var mode := TimeTrialMode.new()
	add_child(mode)
	mode.setup(p, hud, null, world)
	var course := CourseBuilder.load_course(id)
	if not t.check(not course.is_empty(), "course %s recorded in config/courses.json" % id):
		return
	for g in course["gates"]:
		t.check(not _inside_building(g["pos"]), "gate at %s is clear of buildings" % g["pos"])
	mode.setup_course(course)
	var result := {}
	mode.finished.connect(func(r): result.merge(r))
	mode.start()
	var bot := SwingBot.new(SwingBot.Style.EXPERT, Vector3.FORWARD)
	# Keep the follower referenced: a Callable does not keep its RefCounted target alive.
	var follower := RouteFollower.new(CourseBuilder.route(id, world.layout)["waypoints"])
	bot.goal_fn = follower.goal
	p.bot = bot
	var frames := int(limit_s * 60)
	for i in frames:
		await get_tree().physics_frame
		if not result.is_empty():
			break
	t.note("%s: %s rings %d/%d, %s" % [id, "done" if not result.is_empty() else "DNF", mode.next,
		course["gates"].size(), ("%.1f s (par %.1f)" % [result["time"], course["par"]]) if not result.is_empty() else ""])
	t.check(not result.is_empty() or mode.next >= int(ceil(course["gates"].size() * 0.6)),
		"fresh physics flight clears most of %s (%d/%d)" % [id, mode.next, course["gates"].size()])
	mode.abandon()
	mode.queue_free()
	p.queue_free()
	hud.free()
	await get_tree().process_frame


func _inside_building(p: Vector3) -> bool:
	for b in world.layout.buildings:
		for tt in b["tiers"]:
			if p.x > tt[0] and p.x < tt[2] and p.z > tt[1] and p.z < tt[3] and p.y > tt[4] and p.y < tt[5]:
				return true
	return false


func test_recorded_flights_clear_every_gate(t) -> void:
	for id in CourseBuilder.COURSES:
		var c := CourseBuilder.load_course(id)
		if not t.check(not c.is_empty() and c["path"].size() > 10, "course %s recorded with its flight path" % id):
			continue
		var next := 0
		var path: Array = c["path"]
		for i in range(1, path.size()):
			if next < c["gates"].size() and TimeTrialMode._crossed(c["gates"][next], path[i - 1], path[i]):
				next += 1
		t.check(next == c["gates"].size(), "%s: recorded flight clears %d/%d gates" % [id, next, c["gates"].size()])


func test_course_canyon_flyable(t) -> void:
	await _run_course(t, "canyon", 120.0)


func test_course_waterfront_flyable(t) -> void:
	await _run_course(t, "waterfront", 120.0)


func test_course_beacon_flyable(t) -> void:
	await _run_course(t, "beacon", 120.0)


func test_endurance_ends_on_street(t) -> void:
	var p := _player()
	p.global_position = Vector3(400, 3, 0)
	var mode := EnduranceMode.new()
	add_child(mode)
	mode.setup(p, Hud.new(), null, world)
	var result := {}
	mode.finished.connect(func(r): result.merge(r))
	mode.start()
	p.bot = _Idle.new()
	for i in 120:
		await get_tree().physics_frame
		if not result.is_empty():
			break
	t.check(result.get("reason", "") == "Touched the street", "run ends on street contact (%s)" % result)
	mode.queue_free()
	p.queue_free()


func test_personal_bests_persist(t) -> void:
	var before = SaveData.data.duplicate(true)
	SaveData.data["best_trial_times"] = {}
	t.check(SaveData.submit_trial("unit", 50.0), "first time is a best")
	t.check(not SaveData.submit_trial("unit", 60.0), "slower is not a best")
	t.check(SaveData.submit_trial("unit", 40.0), "faster is a best")
	SaveData.load_data()
	t.near(SaveData.best_trial("unit"), 40.0, 0.001, "best survives a reload from disk")
	SaveData.data = before
	SaveData.save()


class _Idle:
	extends RefCounted
	func drive(_p, _dt) -> Dictionary:
		return {"move": Vector3.ZERO, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}
