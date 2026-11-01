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
	"canyon": {"name": "Canyon Sprint", "desc": "North up the Central Spine through the towers. Find your rhythm."},
	"waterfront": {"name": "Three Graces", "desc": "Down the Grand Diagonal to the clock towers by the strait."},
	"beacon": {"name": "Beacon Loop", "desc": "A lap of the plaza round the radio beacon. Tight corners."},
	"uptown": {"name": "Uptown Express", "desc": "The whole Central Spine, south coast to north. Nothing but speed."},
	"spires": {"name": "Spire Run", "desc": "Up the Grand Diagonal under the tallest towers, out to the cathedral."},
	"switchback": {"name": "Switchback", "desc": "Left, right, left. The spine's S-bends through midtown – steer hard."},
	"riverside": {"name": "Riverside", "desc": "Along the strait road, past the clock towers."},
	"grand_tour": {"name": "Grand Tour", "desc": "A lap of the Inner Ring round the skyscraper district."},
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
## {start: Vector3, waypoints: Array[Vector3]} – waypoints on road centre
## lines (CityRoads' named roads), ~100 m apart.
static func route(id: String, layout: CityLayout) -> Dictionary:
	var R := layout.roads
	var pts: Array = []
	match id:
		"canyon":
			# North up the Central Spine through the business district.
			pts = _part(R.along("spine", 100.0), func(q: Vector2) -> bool: return q.y > -520.0 and q.y < 140.0)
			pts.reverse()
		"waterfront":
			# West down the Grand Diagonal to the clock towers by the strait.
			pts = _part(R.along("diagonal", 100.0), func(q: Vector2) -> bool: return q.x > 185.0 and q.x < 640.0)
			pts.reverse()
			pts.append(Vector2(190.0, -24.0))
		"beacon":
			pts = _beacon_lap(layout)
		"uptown":
			pts = _part(R.along("spine", 110.0), func(q: Vector2) -> bool: return q.y > -560.0 and q.y < 540.0)
			pts.reverse()
		"spires":
			pts = _part(R.along("diagonal", 100.0), func(q: Vector2) -> bool: return q.x > 290.0 and q.x < 860.0)
		"switchback":
			# South down the spine's S-bends through midtown.
			pts = _part(R.along("spine", 70.0), func(q: Vector2) -> bool: return q.y > -40.0 and q.y < 545.0)
		"riverside":
			pts = _part(R.along("ring", 110.0), func(q: Vector2) -> bool:
				return q.x < 110.0 and q.y > -540.0 and q.y < 330.0)
			if pts.size() > 1 and (pts[0] as Vector2).y > (pts[-1] as Vector2).y:
				pts.reverse()
		"grand_tour":
			pts = R.along("inner", 100.0)
			if not pts.is_empty():
				pts.append(pts[0])
	var wps: Array[Vector3] = []
	for q in pts:
		wps.append(Vector3(q.x, 0, q.y))
	if wps.size() < 2:
		wps = [Vector3(500, 0, -100), Vector3(500, 0, -300)]
	var start := start_roof(layout, wps[0], wps[1])
	return {"start": start, "waypoints": wps}


static func _part(pts: Array, keep: Callable) -> Array:
	var out: Array = []
	for q in pts:
		if keep.call(q):
			out.append(q)
	return out


## A lap of the roads round the beacon plaza: its block outline pushed out
## to the middle of the surrounding streets, a corner every ~60 m.
static func _beacon_lap(layout: CityLayout) -> Array:
	var beacon := Vector2(CityLayout.CBD_CENTER.x - 40, CityLayout.CBD_CENTER.y + 60)
	var i := layout.block_at(beacon.x, beacon.y)
	if i < 0:
		return []
	var ring: Array = Geometry2D.offset_polygon(layout.blocks[i]["poly"], 9.0)
	if ring.is_empty():
		return []
	var poly: PackedVector2Array = CityRoads._simplify(ring[0], 3.0)
	var out: Array = []
	for q in poly:
		if out.is_empty() or (out[-1] as Vector2).distance_to(q) > 25.0:
			out.append(q)
	out.append(out[0])
	return out


## A rooftop ~70 m up, behind the first waypoint (away from the second).
static func start_roof(layout: CityLayout, first: Vector3, second: Vector3) -> Vector3:
	var back := Vector2(first.x - second.x, first.z - second.z).normalized()
	var want := Vector2(first.x, first.z) + back * 40.0
	var best := Vector3(want.x, 60.0, want.y)
	var best_s := -INF
	for b in layout.buildings:
		if b["kind"] != "normal" or b.get("roof_blocked", false):
			continue
		var t: Array = b["tiers"][-1]
		if t[2] - t[0] < 10.0 or t[3] - t[1] < 10.0:
			continue
		var tc := CityLayout.top_center(b)
		var c := Vector2(tc.x, tc.z)
		var d := c.distance_to(want)
		if d > 90.0:
			continue
		var s: float = -absf(t[5] - BuildingMesher.base_of(b) - 70.0) * 0.7 - d
		if s > best_s:
			best_s = s
			best = Vector3(tc.x, BuildingMesher.roof_y(b) + 2.0, tc.z)  # (on a crown's deck, not inside it)
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
			var g := layout.ground_y(mid.x, mid.z)
			var above := mid.y - g
			var gp := Vector3(mid.x, g + maxf(above, 18.0), mid.z)
			var hw := street_half_width(layout, gp, dir)
			gates.append({"pos": gp, "dir": dir, "half_w": hw, "half_h": 16.0 + maxf(0.0, 18.0 - above)})
	return gates


## Half the clear width across `dir` at p (to the building faces either side),
## +0.5 m so hugging a facade still counts; 14 m in the open.
static func street_half_width(layout: CityLayout, p: Vector3, dir: Vector3) -> float:
	var side := Vector3(-dir.z, 0.0, dir.x)
	var near: Array = []
	for b in layout.buildings:
		if b["kind"] in ["normal", "landmark", "plain", "frame"] and CityLayout.base_center(b).distance_to(Vector2(p.x, p.z)) < 120.0:
			near.append(b)
	for d in [4.0, 7.0, 10.0, 13.0, 16.0, 19.0, 22.0]:
		for sgn in [-1.0, 1.0]:
			var q: Vector3 = p + side * d * sgn
			for b in near:
				if CityLayout.inside(b, Vector3(q.x, p.y - 1.0, q.z)):
					return maxf(d + 0.5, 9.0)
	return 14.0
