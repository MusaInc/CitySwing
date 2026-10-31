class_name CityRoads
extends RefCounted
## The island's road network: not a grid.
##
##   * The island outline is organic (noisy rounded coast; the west side is the
##     straight quay along the strait, where the bridge lands).
##   * A coastal ring road runs inside the esplanade.
##   * Boulevards: hand-placed control points, smoothed into curves (the Grand
##     Diagonal from the bridge to the Heights, the Central Spine, Valley Road
##     along the railway, Heights Road). Roundabouts where boulevards cross.
##   * Every region between them is carved into blocks by recursive street
##     cuts, each district with its own character: a slightly skewed grid in
##     the CBD, a differently angled one in midtown, long quay-aligned blocks
##     in the docks, winding lanes and small irregular blocks in the Old Town.
##     Cuts end at the streets they meet, so T-junctions happen naturally.
##
## Output (all 2-D, x/z metres):
##   coast      PackedVector2Array  island outline (sea wall), counter-clockwise
##   roads      Array of {pts: PackedVector2Array, w: float, kind: "ring"|"major"|"minor"}
##   roundabouts Array of {c: Vector2, r: float (centre-line radius), w: float}
##   blocks     Array of {poly: PackedVector2Array, district: String, kind: "block"|"plaza"|"green"}

const ESPLANADE := 18.0
const RING_W := 22.0
const MAJOR_W := 26.0
const ROUNDABOUT_R := 24.0
const SAMPLE := 6.0           # m between smoothed curve points

## Per-district street character: base angle (deg), angle jitter (deg),
## target block area (m²), street width, bend (0 = straight cuts).
const STYLE := {
	"cbd": {"angle": 8.0, "jitter": 2.0, "area": 7000.0, "w": 16.0, "bend": 0.0},
	"midtown": {"angle": -14.0, "jitter": 5.0, "area": 7600.0, "w": 16.0, "bend": 0.03},
	"waterfront": {"angle": 0.0, "jitter": 4.0, "area": 6400.0, "w": 16.0, "bend": 0.02},
	"docks": {"angle": 0.0, "jitter": 1.5, "area": 9500.0, "w": 18.0, "bend": 0.0},
	"georgian": {"angle": 28.0, "jitter": 18.0, "area": 4600.0, "w": 13.0, "bend": 0.07},
}

var seed := 1207
var rng := RandomNumberGenerator.new()
var district_of: Callable    # (x, z) -> String
var bounds := Rect2(30.0, -656.0, 1000.0, 1271.0)
var coast := PackedVector2Array()
var roads: Array = []
var roundabouts: Array = []
var blocks: Array = []


func generate(p_seed: int, p_district: Callable, p_bounds: Rect2) -> CityRoads:
	seed = p_seed
	rng.seed = seed ^ 0x51ab
	district_of = p_district
	bounds = p_bounds
	_coast()
	var inner := _ring()
	var majors := _majors()
	_roundabouts(majors)
	# Regions: the land inside the ring road minus every boulevard and roundabout.
	var regions: Array = [inner]
	for m in majors:
		var poly := _buffer(m["pts"], m["w"] * 0.5)
		regions = _clip_all(regions, poly)
	for rb in roundabouts:
		regions = _clip_all(regions, _circle(rb["c"], float(rb["r"]) + float(rb["w"]) * 0.5, 28))
	for rb in roundabouts:
		blocks.append({"poly": _circle(rb["c"], float(rb["r"]) - float(rb["w"]) * 0.5, 20), "district": _dist(rb["c"]),
			"kind": "green"})
	for r in regions:
		_split(r, 0)
	return self


# ------------------------------------------------------------------ coast
func _coast() -> void:
	# A rounded, noisy outline inside `bounds`; the west edge stays straight
	# (the strait quay). Walk the perimeter clockwise in screen terms
	# (x right, z down): north edge west→east, east edge, south edge east→west.
	var b := bounds
	var pts := PackedVector2Array()
	var R := 150.0
	var amp := 34.0
	var n := 0
	var noise := func(s: float) -> float:
		return (_vn(s / 160.0 + 3.0) - 0.5) * 2.0 * 0.7 + (_vn(s / 55.0 + 11.0) - 0.5) * 2.0 * 0.3
	# Perimeter path of the rounded rect (west edge excluded), sampled.
	var path: Array = []
	path.append(Vector2(b.position.x, b.position.y))
	_arc_to(path, Vector2(b.end.x - R, b.position.y + R), R, -PI * 0.5, 0.0, Vector2(b.position.x, b.position.y))
	_arc_to(path, Vector2(b.end.x - R, b.end.y - R), R, 0.0, PI * 0.5, Vector2.INF)
	path.append(Vector2(b.position.x, b.end.y))
	# Resample at SAMPLE*2 and push out/in along the normal by noise; taper
	# to zero at the west ends so the quay meets the strait wall.
	var s := 0.0
	var dense: Array = []
	for i in path.size() - 1:
		var a: Vector2 = path[i]
		var c: Vector2 = path[i + 1]
		var L := a.distance_to(c)
		var k := maxi(1, ceili(L / 12.0))
		for j in k:
			dense.append([a.lerp(c, float(j) / k), (c - a).normalized(), s + L * j / k])
		s += L
	dense.append([path[-1], Vector2.LEFT, s])
	for d in dense:
		var p: Vector2 = d[0]
		var t: Vector2 = d[1]
		var out := Vector2(t.y, -t.x)  # left of travel = outward for this walk
		var taper := smoothstep(b.position.x, b.position.x + 160.0, p.x)
		pts.append(p + out * float(noise.call(d[2])) * amp * taper)
		n += 1
	# Close along the west quay (straight).
	coast = pts
	if Geometry2D.is_polygon_clockwise(coast):
		coast.reverse()


func _arc_to(path: Array, c: Vector2, r: float, a0: float, a1: float, _start: Vector2) -> void:
	for i in 9:
		var a := lerpf(a0, a1, i / 8.0)
		path.append(c + Vector2(cos(a), sin(a)) * r)


## The ring road round the coast; returns the land inside it.
func _ring() -> PackedVector2Array:
	var mid := Geometry2D.offset_polygon(coast, -(ESPLANADE + RING_W * 0.5))
	var line: PackedVector2Array = mid[0]
	line.append(line[0])
	roads.append({"pts": line, "w": RING_W, "kind": "ring"})
	var inner := Geometry2D.offset_polygon(coast, -(ESPLANADE + RING_W))
	return inner[0]


# ------------------------------------------------------------ boulevards
func _majors() -> Array:
	var b := bounds
	var X := func(f: float) -> float: return lerpf(b.position.x, b.end.x, f)
	var Z := func(f: float) -> float: return lerpf(b.position.y, b.end.y, f)
	var defs := [
		# Grand Diagonal: bridge landing → CBD → the Heights.
		[Vector2(b.position.x - 40.0, -17.0), Vector2(200, -40), Vector2(390, -105), Vector2(560, -215),
			Vector2(720, -330), Vector2(860, -470), Vector2(X.call(1.0) + 60.0, Z.call(0.0) + 80.0)],
		# Central Spine, north coast to south coast, a long S.
		[Vector2(470, Z.call(0.0) - 60.0), Vector2(495, -440), Vector2(520, -230), Vector2(585, 10),
			Vector2(650, 230), Vector2(625, 440), Vector2(590, Z.call(1.0) + 60.0)],
		# Valley Road along the railway valley, docks to the east coast.
		[Vector2(b.position.x - 40.0, 372), Vector2(250, 362), Vector2(470, 385), Vector2(700, 360),
			Vector2(880, 318), Vector2(X.call(1.0) + 60.0, 285)],
		# Heights Road: from the spine up and round to the east coast.
		[Vector2(585, 10), Vector2(720, -40), Vector2(860, -60), Vector2(X.call(1.0) + 60.0, -20)],
		# Old Town crescent: a long curve through the north.
		[Vector2(b.position.x - 40.0, -470), Vector2(200, -500), Vector2(330, -560), Vector2(470, Z.call(0.0) - 60.0)],
	]
	var out: Array = []
	for d in defs:
		var pts := _smooth(PackedVector2Array(d))
		roads.append({"pts": pts, "w": MAJOR_W, "kind": "major"})
		out.append({"pts": pts, "w": MAJOR_W})
	return out


func _roundabouts(majors: Array) -> void:
	for i in majors.size():
		for j in range(i + 1, majors.size()):
			var a: PackedVector2Array = majors[i]["pts"]
			var c: PackedVector2Array = majors[j]["pts"]
			for p in _crossings(a, c):
				var near := false
				for rb in roundabouts:
					if (rb["c"] as Vector2).distance_to(p) < 120.0:
						near = true
				if not near and Geometry2D.is_point_in_polygon(p, Geometry2D.offset_polygon(coast, -90.0)[0]):
					roundabouts.append({"c": p, "r": ROUNDABOUT_R, "w": MAJOR_W - 6.0})
	for rb in roundabouts:
		var ring := _circle(rb["c"], rb["r"], 28)
		ring.append(ring[0])
		roads.append({"pts": ring, "w": rb["w"], "kind": "major"})


# ---------------------------------------------------------------- blocks
func _split(poly: PackedVector2Array, depth: int) -> void:
	var area := _area(poly)
	if area < 40.0:
		return
	var c := _centroid(poly)
	var dist := _dist(c)
	var st: Dictionary = STYLE.get(dist, STYLE["midtown"])
	var brng := RandomNumberGenerator.new()
	brng.seed = hash(Vector3i(int(c.x * 4.0), int(c.y * 4.0), depth)) ^ seed
	var target: float = st["area"] * brng.randf_range(0.75, 1.3)
	var theta := deg_to_rad(float(st["angle"]) + brng.randf_range(-1.0, 1.0) * float(st["jitter"]))
	var d := Vector2(cos(theta), sin(theta))
	var n := Vector2(-d.y, d.x)
	var ext_d := _extent(poly, d)
	var ext_n := _extent(poly, n)
	var Ld := ext_d.y - ext_d.x
	var Ln := ext_n.y - ext_n.x
	var w: float = st["w"]
	if area < target or depth > 9 or minf(Ld, Ln) < 2.0 * 22.0 + w and maxf(Ld, Ln) < 2.6 * 22.0 + w:
		_emit(poly, dist, area)
		return
	# Cut across the longer axis (a street parallel to the shorter one).
	var along := d if Ld >= Ln else n
	var across := n if Ld >= Ln else d
	var ext_a := ext_d if Ld >= Ln else ext_n
	var ext_c := ext_n if Ld >= Ln else ext_d
	var pos := lerpf(ext_a.x, ext_a.y, brng.randf_range(0.38, 0.62))
	var line := PackedVector2Array()
	var span := ext_c.y - ext_c.x
	var k := 6 if float(st["bend"]) > 0.0 else 1
	for i in k + 1:
		var t := lerpf(ext_c.x - 30.0, ext_c.y + 30.0, float(i) / k)
		var bend := 0.0
		if k > 1:
			bend = (_vn(t / 60.0 + c.x * 0.01 + depth * 7.0) - 0.5) * 2.0 * float(st["bend"]) * span
		line.append(along * (pos + bend) + across * t)
	if k > 1:
		line = _smooth(line)
	var cut := _buffer(line, w * 0.5)
	var pieces := _clip_all([poly], cut)
	if pieces.size() < 2:
		_emit(poly, dist, area)
		return
	for seg in Geometry2D.intersect_polyline_with_polygon(line, poly):
		roads.append({"pts": seg, "w": w, "kind": "minor"})
	for p in pieces:
		_split(p, depth + 1)


func _emit(poly: PackedVector2Array, dist: String, area: float) -> void:
	# Slivers and scraps become small plazas (paved), not building plots.
	var thin := area / maxf(_perimeter(poly), 1.0)  # ≈ half the minimum width for long shapes
	var kind := "block"
	if area < 900.0 or thin < 6.0:
		kind = "plaza"
	blocks.append({"poly": poly, "district": dist, "kind": kind})


# --------------------------------------------------------------- helpers
func _dist(p: Vector2) -> String:
	return district_of.call(p.x, p.y) if district_of.is_valid() else "midtown"


static func _vn(x: float) -> float:
	var i := floorf(x)
	var f := x - i
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(absf(fmod(sin(i * 127.1) * 43758.5453, 1.0)), absf(fmod(sin((i + 1.0) * 127.1) * 43758.5453, 1.0)), f)


## Catmull-Rom through the control points, resampled every SAMPLE metres.
static func _smooth(cp: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if cp.size() < 3:
		return cp
	for i in cp.size() - 1:
		var p0 := cp[maxi(i - 1, 0)]
		var p1 := cp[i]
		var p2 := cp[i + 1]
		var p3 := cp[mini(i + 2, cp.size() - 1)]
		var k := maxi(1, ceili(p1.distance_to(p2) / SAMPLE))
		for j in k:
			var t := float(j) / k
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(cp[-1])
	return out


static func _buffer(line: PackedVector2Array, half: float) -> PackedVector2Array:
	var r := Geometry2D.offset_polyline(line, half, Geometry2D.JOIN_ROUND, Geometry2D.END_SQUARE)
	return r[0] if r.size() > 0 else PackedVector2Array()


## Every polygon in `polys` minus `hole`, dropping hole outlines.
static func _clip_all(polys: Array, hole: PackedVector2Array) -> Array:
	var out: Array = []
	for p in polys:
		for q in Geometry2D.clip_polygons(p, hole):
			if not Geometry2D.is_polygon_clockwise(q) or polys.size() == 0:
				out.append(q)
	return out


static func _circle(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _crossings(a: PackedVector2Array, b: PackedVector2Array) -> Array:
	var out: Array = []
	for i in a.size() - 1:
		for j in b.size() - 1:
			var p: Variant = Geometry2D.segment_intersects_segment(a[i], a[i + 1], b[j], b[j + 1])
			if p != null:
				out.append(p)
	return out


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


static func _perimeter(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		s += p[i].distance_to(p[(i + 1) % p.size()])
	return s


static func _centroid(p: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for v in p:
		c += v
	return c / maxf(p.size(), 1)


static func _extent(p: PackedVector2Array, axis: Vector2) -> Vector2:
	var lo := INF
	var hi := -INF
	for v in p:
		var t := v.dot(axis)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	return Vector2(lo, hi)
