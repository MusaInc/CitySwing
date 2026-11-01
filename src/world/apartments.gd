class_name Apartments
extends RefCounted
## Five homes, each a real room inside a real building of the generated city,
## opening onto the street/skyline through a window you can run out of and
## climb back into.
##
## Placement (deterministic – layout data only, no random draws, so the city
## and the recorded courses don't reshuffle): for each tier, the candidate
## buildings with a tier spanning the tier's floor height and room for the
## room, every face of that tier scored for its view (rays out of the window
## at eye height against every building's box: the longest clear sightlines
## win; a blank wall a few metres away fails), nearest the business district
## breaking ties for the higher tiers. The penthouse goes near the top of the
## tallest building that fits it.
##
## The result is stored on the building (b["apt"]) so BuildingMesher draws
## the facade with the opening (walls_with_opening), collision_boxes() cuts
## the room out of the tier, and features skip the opening. Coordinates are
## the building's lot frame (CityLayout.bxf turns them into the world).

const FLOOR := 3.6  # storey height (matches the facade shader's bands)
const TIERS := [
	{"id": "starter", "name": "Quay Studio", "floor": [14.0, 26.0], "w": 7.8, "d": 7.2, "h": 3.2,
		"open_w": 2.6, "sill": 0.0, "open_h": 2.4, "price": 0, "view": 45.0},
	{"id": "city", "name": "City Apartment", "floor": [28.0, 44.0], "w": 11.0, "d": 10.0, "h": 3.4,
		"open_w": 4.0, "sill": 0.0, "open_h": 2.55, "price": 1500, "view": 80.0},
	{"id": "loft", "name": "High-Rise Loft", "floor": [55.0, 85.0], "w": 14.0, "d": 12.0, "h": 4.4,
		"open_w": 7.2, "sill": 0.0, "open_h": 3.7, "price": 4000, "view": 120.0},
	{"id": "sky", "name": "Luxury Sky Apartment", "floor": [100.0, 150.0], "w": 18.0, "d": 14.0, "h": 4.2,
		"open_w": 9.6, "sill": 0.0, "open_h": 3.3, "price": 9000, "view": 160.0},
	{"id": "penthouse", "name": "Ultimate Penthouse", "floor": [-1.0, -1.0], "w": 24.0, "d": 18.0, "h": 5.2,
		"open_w": 20.0, "sill": 0.0, "open_h": 4.0, "price": 20000, "view": 50.0, "cbd": 900.0},
]

## Placed homes: [{id, tier, name, b (building dict), t (tier index), face,
## a0, a1, y0, y1, oa0, oa1, oy0, oy1, depth, price}]. World helpers below.
var homes: Array = []
var _layout: CityLayout
var _grid := {}     # 25 m cell -> Array of world AABBs (view blocking)


static func place(layout: CityLayout) -> Apartments:
	var A := Apartments.new()
	A._layout = layout
	A._index()
	var used := {}
	for ti in TIERS.size():
		var spec: Dictionary = TIERS[ti]
		var best := {}
		var best_s := -INF
		var cands: Array = A._candidates(spec, used)
		for c in cands:
			var s: float = c["score"]
			if s > best_s:
				best_s = s
				best = c
		if best.is_empty():
			continue
		best["id"] = spec["id"]
		best["tier"] = ti
		best["name"] = spec["name"]
		best["price"] = spec["price"]
		var b: Dictionary = best["b"]
		# Facade geometry needs a building frame, not a circular building→home→building graph.
		var facade_home := best.duplicate()
		facade_home["b"] = b.duplicate()
		b["apt"] = facade_home
		b.erase("_features")  # (re-derived clear of the window)
		A.homes.append(best)
	return A


func _index() -> void:
	for b in _layout.buildings:
		if b["kind"] == "invisible":
			continue
		for t in b["tiers"]:
			var box := CityLayout.tier_aabb(b, t)
			for cx in range(floori(box.position.x / 25.0), floori(box.end.x / 25.0) + 1):
				for cz in range(floori(box.position.z / 25.0), floori(box.end.z / 25.0) + 1):
					var k := Vector2i(cx, cz)
					if not _grid.has(k):
						_grid[k] = []
					_grid[k].append(box)


## Free metres along a ray from `p` (world) in horizontal direction `d`, up to `reach`.
func _clear(p: Vector3, d: Vector3, reach: float, skip: Array) -> float:
	var s := 4.0
	while s < reach:
		var q := p + d * s
		for box: AABB in _grid.get(Vector2i(floori(q.x / 25.0), floori(q.z / 25.0)), []):
			if box in skip:
				continue
			if box.has_point(q):
				return s
		if _layout.ground_y(q.x, q.z) > q.y:
			return s
		s += 5.0
	return reach


func _candidates(spec: Dictionary, used: Dictionary) -> Array:
	var out: Array = []
	var pent: bool = spec["floor"][0] < 0.0
	var order: Array = _layout.buildings
	if pent:
		# Tallest first: the penthouse wants the city's highest suitable roof.
		order = _layout.buildings.filter(func(b): return b["kind"] == "normal")
		var tall := func(b: Dictionary) -> float: return float(b["tiers"][-1][5]) - BuildingMesher.base_of(b)
		order.sort_custom(func(a, b): return tall.call(a) > tall.call(b))
		order = order.slice(0, 12)
	for b in order:
		if b["kind"] != "normal" or b.has("apt"):
			continue
		var base := BuildingMesher.base_of(b)
		var tiers: Array = b["tiers"]
		for ti in tiers.size():
			var t: Array = tiers[ti]
			var y0: float
			if pent:
				if ti != tiers.size() - 1:
					continue
				# A storey or so under the roof slab (and any crown above).
				y0 = base + floorf((float(t[5]) - base - spec["h"] - 2.4) / FLOOR) * FLOOR
			else:
				var lo: float = spec["floor"][0]
				var hi: float = spec["floor"][1]
				var mid := (lo + hi) * 0.5
				y0 = base + roundf(mid / FLOOR) * FLOOR
				if y0 - base < lo:
					y0 += FLOOR
			if y0 < float(t[4]) + 1.0 or y0 + spec["h"] > float(t[5]) - 1.5:
				continue
			for k in 4:
				var f := BuildingMesher._face(t, k)
				var flen: float = f[3]
				var depth := float(t[3]) - float(t[1]) if k % 2 == 0 else float(t[2]) - float(t[0])
				if flen < spec["w"] + 3.0 or depth < spec["d"] + 3.0:
					continue
				var a0 := (flen - float(spec["w"])) * 0.5
				var a1 := a0 + float(spec["w"])
				var oa0 := (flen - float(spec["open_w"])) * 0.5
				var c := {"b": b, "t": ti, "face": k, "a0": a0, "a1": a1, "y0": y0, "y1": y0 + spec["h"],
					"oa0": oa0, "oa1": oa0 + float(spec["open_w"]), "oy0": y0 + float(spec["sill"]),
					"oy1": y0 + float(spec["sill"]) + float(spec["open_h"]), "depth": spec["d"]}
				var view := _view(c, spec)
				if view < 0.0:
					continue
				var s := view
				if not pent:
					var cp := window_center(c)
					s -= Vector2(cp.x, cp.z).distance_to(CityLayout.CBD_CENTER) * (0.05 if spec["price"] > 0 else 0.0)
				else:
					s += (float(t[5]) - base) * 2.0  # height above its street first
				c["score"] = s
				out.append(c)
	return out


## Sum of clear sightlines out of the window (straight out and ±28°), or −1
## if the straight-out view is shorter than the tier needs (a wall outside).
func _view(c: Dictionary, spec: Dictionary) -> float:
	var p := window_center(c) + Vector3.UP * 1.6
	var n := outward(c)
	var skip: Array = []
	for t in (c["b"] as Dictionary)["tiers"]:
		skip.append(CityLayout.tier_aabb(c["b"], t))
	var reach := 320.0
	var straight := _clear(p + n * 1.0, n, reach, skip)
	if straight < float(spec["view"]):
		return -1.0
	var l := _clear(p + n * 1.0, n.rotated(Vector3.UP, 0.49), reach, skip)
	var r := _clear(p + n * 1.0, n.rotated(Vector3.UP, -0.49), reach, skip)
	var clear := straight + 0.6 * (l + r)
	if float(spec["view"]) < 120.0 and not spec.has("cbd"):
		return clear * 0.08 + _city_below(p + Vector3.UP * 30.0, n, skip) * 28.0
	# High up, an empty view (open sea) is dull: what makes it is city spread
	# out below – rooftops under eye level across the cone in front.
	var to_cbd := Vector3(CityLayout.CBD_CENTER.x - p.x, 0.0, CityLayout.CBD_CENTER.y - p.z).normalized()
	return clear * 0.05 + _city_below(p, n, skip) * 25.0 + float(spec.get("cbd", 150.0)) * n.dot(to_cbd)


func _city_below(p: Vector3, n: Vector3, skip: Array) -> float:
	var hits := 0.0
	for ang: float in [-0.6, -0.3, 0.0, 0.3, 0.6]:
		var d := n.rotated(Vector3.UP, ang)
		var dist := 60.0
		while dist <= 520.0:
			var q := p + d * dist
			for box: AABB in _grid.get(Vector2i(floori(q.x / 25.0), floori(q.z / 25.0)), []):
				if box in skip:
					continue
				if box.end.y < p.y - 5.0 and q.x >= box.position.x and q.x <= box.end.x \
						and q.z >= box.position.z and q.z <= box.end.z:
					hits += 1.0
					break
			dist += 40.0
	return hits


# ------------------------------------------------------------ geometry
## Local-frame face of the home's tier.
static func face_of(c: Dictionary) -> Array:
	return BuildingMesher._face((c["b"] as Dictionary)["tiers"][c["t"]], c["face"])


## The room (local frame).
static func room_box(c: Dictionary) -> AABB:
	return BuildingMesher._fbox(face_of(c), c["a0"], c["a1"], -float(c["depth"]), 0.0, c["y0"], c["y1"])


## World: centre of the window opening at sill height, and the outward normal.
static func window_center(c: Dictionary) -> Vector3:
	var f := face_of(c)
	var a := (float(c["oa0"]) + float(c["oa1"])) * 0.5
	var p: Vector3 = BuildingMesher._fpt(f, a, 0.0, c["oy0"])
	return CityLayout.bxf(c["b"]) * p


static func outward(c: Dictionary) -> Vector3:
	return (CityLayout.bxf(c["b"]).basis * (face_of(c)[2] as Vector3)).normalized()


static func along_dir(c: Dictionary) -> Vector3:
	return (CityLayout.bxf(c["b"]).basis * (face_of(c)[1] as Vector3)).normalized()


## World: where the hero wakes up (capsule centre) – inside, facing the window.
static func spawn_point(c: Dictionary) -> Vector3:
	# Near the glass in the big high rooms (so the follow camera, a few metres
	# behind, still looks out over the city), mid-room in the small flats.
	var back := 1.7 if float(c["depth"]) >= 8.0 else minf(float(c["depth"]) * 0.45, 3.0)
	var p := window_center(c) - outward(c) * back
	return Vector3(p.x, float(c["y0"]) + 0.95, p.z)


## Local → world for a point in the face frame (along, out, y).
static func face_point(c: Dictionary, a: float, o: float, y: float) -> Vector3:
	return CityLayout.bxf(c["b"]) * BuildingMesher._fpt(face_of(c), a, o, y)


## World point → face frame [along, out, y] (out > 0 = outside the facade).
static func to_face(c: Dictionary, p: Vector3) -> Vector3:
	var f := face_of(c)
	var q := CityLayout.bxf(c["b"]).affine_inverse() * p
	var d := q - (f[0] as Vector3)
	return Vector3(d.dot(f[1]), d.dot(f[2]), q.y)


## Height of the room's floor above its street (for the UI).
static func floor_height(c: Dictionary) -> float:
	return float(c["y0"]) - BuildingMesher.base_of(c["b"])


## The tier box minus the room: boxes for collision_boxes (local frame),
## plus jambs, lintel and sill framing the opening.
static func split_tier(c: Dictionary, box: AABB) -> Array[AABB]:
	var out: Array[AABB] = []
	var r := room_box(c)
	if not box.intersects(r):
		out.append(box)
		return out
	# Below and above the room: whole footprint.
	if r.position.y > box.position.y:
		out.append(AABB(box.position, Vector3(box.size.x, r.position.y - box.position.y, box.size.z)))
	if r.end.y < box.end.y:
		out.append(AABB(Vector3(box.position.x, r.end.y, box.position.z),
			Vector3(box.size.x, box.end.y - r.end.y, box.size.z)))
	# The room's storey: the footprint minus the room's rectangle.
	var y0 := maxf(r.position.y, box.position.y)
	var y1 := minf(r.end.y, box.end.y)
	var F := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	var R := Rect2(r.position.x, r.position.z, r.size.x, r.size.z).intersection(F)
	for rr in [Rect2(F.position.x, F.position.y, R.position.x - F.position.x, F.size.y),
			Rect2(R.end.x, F.position.y, F.end.x - R.end.x, F.size.y),
			Rect2(R.position.x, F.position.y, R.size.x, R.position.y - F.position.y),
			Rect2(R.position.x, R.end.y, R.size.x, F.end.y - R.end.y)]:
		if rr.size.x > 0.01 and rr.size.y > 0.01:
			out.append(AABB(Vector3(rr.position.x, y0, rr.position.y), Vector3(rr.size.x, y1 - y0, rr.size.y)))
	# Frame round the opening (inside the room's front 0.3 m).
	var f := face_of(c)
	var T := 0.3
	var frame := [[c["a0"], c["oa0"], c["y0"], c["y1"]], [c["oa1"], c["a1"], c["y0"], c["y1"]],
		[c["oa0"], c["oa1"], c["oy1"], c["y1"]], [c["oa0"], c["oa1"], c["y0"], c["oy0"]]]
	for fr in frame:
		if float(fr[1]) - float(fr[0]) > 0.01 and float(fr[3]) - float(fr[2]) > 0.01:
			out.append(BuildingMesher._fbox(f, fr[0], fr[1], -T, 0.0, fr[2], fr[3]))
	return out
