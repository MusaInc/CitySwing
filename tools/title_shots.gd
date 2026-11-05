extends SceneTree
## Picks the title screen's scenic flights (config/title_shots.json).
##   godot --headless --fixed-fps 60 -s res://tools/title_shots.gd
## For each scenic Time Trial route, candidate entries are taken from the
## recorded flight (config/courses.json: a high point, at speed). Each is
## flown for real – the expert autopilot following the route's waypoints, as
## the title will – for one shot's length, several times from slightly nudged
## starts. A candidate is kept only if every trial stays clean: no knockout or
## stun, never down on the street, never stalled, always well above the
## ground. Re-run after physics or layout changes.

const SHOT_S := 12.0
const TRIALS := 3
const ROUTES := ["spires", "waterfront", "riverside", "uptown", "grand_tour", "canyon"]
const PER_ROUTE := 3

var world: CityWorld


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	world = CityWorld.new()
	root.add_child(world)
	await physics_frame
	var courses: Dictionary = CourseBuilder._load_all()
	var keep: Array = []
	for id in ROUTES:
		if not courses.has(id):
			continue
		var path: Array = courses[id]["path"]
		var wps: Array = CourseBuilder.route(id, world.layout)["waypoints"]
		var found := 0
		var k := 20
		while k < path.size() - 130 and found < PER_ROUTE:
			var p0 := _v(path[k])
			var hg := p0.y - world.layout.terrain.road_y(p0.x, p0.z)
			if hg < 28.0:
				k += 10
				continue
			var score := 0.0
			var ok := true
			for trial in TRIALS:
				var r := await _fly(path, wps, k, trial)
				if not r["ok"]:
					ok = false
					break
				score += float(r["score"])
			print("%-10s k=%4d h=%3.0f  %s" % [id, k, hg, "CLEAN %.0f" % (score / TRIALS) if ok else "rejected"])
			if ok:
				keep.append({"course": id, "k": k, "score": snappedf(score / TRIALS, 0.1)})
				found += 1
				k += 130  # the next shot from this route starts after this one
			else:
				k += 25
	var f := FileAccess.open("res://config/title_shots.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(keep, "  "))
	f.close()
	print("TITLE SHOTS ", keep.size())
	quit(0 if keep.size() >= 6 else 1)


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## Entry from the recorded flight at sample k: [position, velocity, waypoint index].
static func entry(path: Array, wps: Array, k: int) -> Array:
	var p := _v(path[k])
	var v := (_v(path[mini(k + 1, path.size() - 1)]) - _v(path[maxi(k - 1, 0)])) / 0.2  # samples are 0.1 s apart
	var wi := 0
	var best := INF
	for i in wps.size():
		var w: Vector3 = wps[i]
		var d := Vector2(w.x - p.x, w.z - p.z).length()
		# The nearest waypoint that is ahead of the travel.
		if d < best and Vector2(w.x - p.x, w.z - p.z).dot(Vector2(v.x, v.z)) > 0.0:
			best = d
			wi = i
	return [p, v, wi]


func _fly(path: Array, wps: Array, k: int, trial: int) -> Dictionary:
	var e := entry(path, wps, k)
	var p := Player.new()
	p.params = load("res://config/swing_params.tres").duplicate()
	root.add_child(p)
	p.respawn(e[0] + Vector3(0.07, 0.0, 0.05) * trial)
	p.s.velocity = e[1]
	var follower := RouteFollower.new(wps)
	follower.i = e[2]
	var bot := SwingBot.new(SwingBot.Style.EXPERT, Vector3.FORWARD)
	bot.goal_fn = follower.goal
	p.bot = bot
	var bad := [false]
	p.landed.connect(func(_s, street): bad[0] = bad[0] or street)
	p.respawned.connect(func(): bad[0] = true)
	var t := 0.0
	var spd := 0.0
	var hsum := 0.0
	var n := 0
	while t < SHOT_S:
		await physics_frame
		t += 1.0 / 60.0
		var h := p.height_above_ground()
		var s := p.s.velocity.length()
		if p.stunned or p.knocked_out or (t > 1.0 and (h < 6.0 or s < 6.0)) or bad[0]:
			bad[0] = true
			break
		spd += s
		hsum += h
		n += 1
	p.queue_free()
	await process_frame
	if bad[0] or n == 0:
		return {"ok": false}
	return {"ok": true, "score": spd / n + hsum / n * 0.3}
