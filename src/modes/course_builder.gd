class_name CourseBuilder
extends RefCounted
## Time Trial courses, recorded from real physics.
##
## A course starts life as a *route*: a start rooftop plus street waypoints in
## the generated city. tools/make_courses.gd flies the expert autopilot along
## each route and places gates along the line it actually flew (so every gate
## is provably reachable with the current physics), sizing each gate to the
## clear width of the street there. The result is written to
## config/courses.json; tests replay it to catch physics/layout regressions.

const PATH := "res://config/courses.json"
const GATE_SPACING := 105.0

const COURSES := {
	"canyon": {"name": "Canyon Sprint", "desc": "Straight down the main avenue. Find your rhythm."},
	"waterfront": {"name": "Three Graces", "desc": "Cut across midtown and down to the clock towers by the river."},
	"beacon": {"name": "Beacon Loop", "desc": "A lap of the plaza round the radio beacon. Tight corners."},
}


## Loads a recorded course: {id, name, start, gates:[{pos, dir, half_w, half_h}], par}
static func load_course(id: String) -> Dictionary:
	var data := _load_all()
	if not data.has(id):
		return {}
	var c: Dictionary = data[id]
	var gates: Array = []
	for g in c["gates"]:
		gates.append({"pos": _v(g["pos"]), "dir": _v(g["dir"]), "half_w": float(g["half_w"]),
			"half_h": float(g["half_h"])})
	var rings: Array = []
	for g in gates:
		rings.append(g["pos"])
	var path: Array = []
	for q in c.get("path", []):
		path.append(_v(q))
	return {"id": id, "name": COURSES[id]["name"], "start": _v(c["start"]), "gates": gates, "rings": rings,
		"par": float(c["par"]), "path": path}


static func _load_all() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if parsed is Dictionary else {}


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


# --------------------------------------------------------------- routes
## {start: Vector3, waypoints: Array[Vector3]} – waypoints on street centres.
static func route(id: String, layout: CityLayout) -> Dictionary:
	var wps: Array[Vector3] = []
	match id:
		"canyon":
			var x := _avenue_x(layout, CityLayout.CBD_CENTER.x)
			for i in 9:
				wps.append(Vector3(x, 0, CityLayout.CBD_CENTER.y + 330.0 - i * 100.0))
		"waterfront":
			var x0 := _avenue_x(layout, 560.0)
			var z0 := _avenue_z(layout, -150.0)
			wps.append(Vector3(x0, 0, z0 + 260.0))
			wps.append(Vector3(x0, 0, z0 + 120.0))
			wps.append(Vector3(x0, 0, z0))
			var x := x0 - 110.0
			while x > 210.0:
				wps.append(Vector3(x, 0, z0))
				x -= 110.0
			wps.append(Vector3(195.0, 0, z0 + 10.0))
			wps.append(Vector3(195.0, 0, -76.0))  # in front of the clock towers
		"beacon":
			# Streets bounding the beacon plaza, one lap.
			var plaza := Rect2()
			for p in layout.parks:
				if (p as Rect2).grow(10).has_point(Vector2(CityLayout.CBD_CENTER.x - 40, CityLayout.CBD_CENTER.y + 60)):
					plaza = p
			var g := plaza.grow(9.0)
			var corners := [Vector3(g.position.x, 0, g.end.y), Vector3(g.position.x, 0, g.position.y),
				Vector3(g.end.x, 0, g.position.y), Vector3(g.end.x, 0, g.end.y)]
			for c in corners:
				wps.append(c)
			wps.append(corners[0])
	var start := start_roof(layout, wps[0], wps[1])
	return {"start": start, "waypoints": wps}


static func _avenue_x(layout: CityLayout, near: float) -> float:
	var best := near
	var bd := INF
	for s in layout.x_streets:
		if s[1] > 20.0 and absf(s[0] - near) < bd:
			bd = absf(s[0] - near)
			best = s[0]
	return best


static func _avenue_z(layout: CityLayout, near: float) -> float:
	var best := near
	var bd := INF
	for s in layout.z_streets:
		if absf(s[0] - near) < bd:
			bd = absf(s[0] - near)
			best = s[0]
	return best


## A rooftop ~70 m up, behind the first waypoint (away from the second).
static func start_roof(layout: CityLayout, first: Vector3, second: Vector3) -> Vector3:
	var back := Vector2(first.x - second.x, first.z - second.z).normalized()
	var want := Vector2(first.x, first.z) + back * 40.0
	var best := Vector3(want.x, 60.0, want.y)
	var best_s := -INF
	for b in layout.buildings:
		if b["kind"] != "normal":
			continue
		var t: Array = b["tiers"][-1]
		if t[2] - t[0] < 10.0 or t[3] - t[1] < 10.0:
			continue
		var c := Vector2((t[0] + t[2]) * 0.5, (t[1] + t[3]) * 0.5)
		var d := c.distance_to(want)
		if d > 90.0:
			continue
		var s: float = -absf(t[5] - 70.0) * 0.7 - d
		if s > best_s:
			best_s = s
			best = Vector3(c.x, t[5] + 2.0, c.y)
	return best


## Gates every GATE_SPACING metres along a recorded flight path.
static func gates_from_path(layout: CityLayout, path: Array) -> Array:
	var gates: Array = []
	var acc := 0.0
	for i in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		acc += Vector2(b.x - a.x, b.z - a.z).length()
		var last := i == path.size() - 1
		var seg := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if (acc >= GATE_SPACING or last) and seg.length() > 0.3:
			acc = 0.0
			# Centre the gate on the segment actually flown and face it along that
			# segment, so the recorded flight crosses it by construction.
			var mid := (a + b) * 0.5
			var dir := seg.normalized()
			# Keep gates in the air even where the flight dipped to the street.
			var gp := Vector3(mid.x, maxf(mid.y, 18.0), mid.z)
			var hw := street_half_width(layout, gp, dir)
			gates.append({"pos": gp, "dir": dir, "half_w": hw, "half_h": 16.0 + maxf(0.0, 18.0 - mid.y)})
	return gates


## Half the clear width across `dir` at p (to the building faces either side),
## +0.5 m so hugging a facade still counts; 14 m in the open.
static func street_half_width(layout: CityLayout, p: Vector3, dir: Vector3) -> float:
	var side := Vector3(-dir.z, 0.0, dir.x)
	for d in [4.0, 7.0, 10.0, 13.0, 16.0, 19.0, 22.0]:
		for sgn in [-1.0, 1.0]:
			var q: Vector3 = p + side * d * sgn
			for b in layout.buildings:
				var t: Array = b["tiers"][0]
				if q.x > t[0] and q.x < t[2] and q.z > t[1] and q.z < t[3] and b["tiers"][-1][5] > p.y:
					return maxf(d + 0.5, 9.0)
	return 14.0
