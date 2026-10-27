class_name CityLayout
extends RefCounted
## Deterministic city plan (pure data – no nodes). Loosely Liverpool: a river
## to the west, a waterfront of three domed/clock-towered landmarks, a dense
## glass business district peaking around a radio beacon, brick docks with
## basins and cranes to the north, low Georgian terraces to the east under a
## huge sandstone cathedral, and an elevated railway along the waterfront.
## Heights are shaped for swinging: tall clusters, wide avenues as launch gaps,
## low-rise districts as technical terrain.

const CHUNK := 200.0
const MIN_X := 70.0
const MAX_X := 1460.0
const MIN_Z := -940.0
const MAX_Z := 940.0
const RIVER_EDGE := 30.0
const CBD_CENTER := Vector2(640.0, -230.0)

enum Style { STONE, BRICK, GLASS, WAREHOUSE, MODERN, SANDSTONE, DARK_GLASS, DECO }

const STYLE_COLORS := {
	Style.STONE: [Color(0.80, 0.77, 0.70), Color(0.74, 0.72, 0.68), Color(0.86, 0.82, 0.74)],
	Style.BRICK: [Color(0.56, 0.28, 0.21), Color(0.63, 0.35, 0.25), Color(0.47, 0.3, 0.25), Color(0.7, 0.5, 0.38)],
	Style.GLASS: [Color(0.36, 0.44, 0.5), Color(0.55, 0.62, 0.66), Color(0.3, 0.38, 0.36)],
	Style.WAREHOUSE: [Color(0.5, 0.25, 0.18), Color(0.44, 0.24, 0.2)],
	Style.MODERN: [Color(0.88, 0.88, 0.86), Color(0.36, 0.38, 0.42), Color(0.78, 0.72, 0.62)],
	Style.SANDSTONE: [Color(0.66, 0.42, 0.33), Color(0.72, 0.5, 0.38)],
	Style.DARK_GLASS: [Color(0.18, 0.2, 0.23), Color(0.25, 0.27, 0.3)],
	Style.DECO: [Color(0.87, 0.81, 0.69), Color(0.8, 0.74, 0.64)],
}

var seed := 1207
var rng := RandomNumberGenerator.new()
var buildings: Array = []      # Dictionary specs (see _building)
var blocks: Array = []         # Rect2 (x,z) of raised pavement blocks
var parks: Array = []          # Rect2
var water: Array = []          # Rect2 water surfaces (river + basins)
var props: Array = []          # [kind:String, Transform3D]
var lanes: Array = []          # [from:Vector3, to:Vector3]
var avenue_marks: Array = []   # [from:Vector3, to:Vector3] centre lines to dash
var x_streets: Array = []      # [centre, width]
var z_streets: Array = []
var land: Array = []           # Rect2 ground collision (land minus basins)
var landmarks: Array = []      # [scene:String, Transform3D]
var spawn := Vector3(330, 0, -60)
var reserved: Array = []      # Rect2 footprints owned by landmarks


func generate(p_seed := 1207) -> CityLayout:
	seed = p_seed
	rng.seed = seed
	_streets()
	_landmarks()
	_blocks()
	_viaduct()
	_skybridges()
	_traffic()
	_land()
	return self


# ------------------------------------------------------------------ grid
func _streets() -> void:
	var x := MIN_X
	var i := 0
	var xs: Array = []
	while x < MAX_X:
		var w := 26.0 if i % 3 == 0 else 16.0
		xs.append([x + w * 0.5, w])
		var bw := rng.randf_range(72.0, 112.0)
		x += w + bw
		i += 1
	x_streets = xs
	var z := MIN_Z
	i = 0
	var zs: Array = []
	while z < MAX_Z:
		var w := 28.0 if i % 3 == 1 else 16.0
		zs.append([z + w * 0.5, w])
		var bd := rng.randf_range(70.0, 115.0)
		z += w + bd
		i += 1
	z_streets = zs


func district(x: float, z: float) -> String:
	if x < 250.0 and z > -330.0 and z < 260.0:
		return "waterfront"
	if z >= 260.0 and x < 560.0:
		return "docks"
	if x > 980.0 or z < -700.0 or z > 640.0:
		return "georgian"
	var d := Vector2(x, z).distance_to(CBD_CENTER)
	if d < 420.0:
		return "cbd"
	return "midtown"


# ------------------------------------------------------------- landmarks
func _landmarks() -> void:
	# Clock building: stone block, two clock towers crowned with domes + birds.
	_add(_building([[92, -112, 162, -40, 0, 50]], Style.SANDSTONE, Color(0.76, 0.74, 0.7), "landmark"))
	for tx in [94.0, 144.0]:
		_add(_building([[tx, -84, tx + 16, -68, 50, 64]], Style.SANDSTONE, Color(0.76, 0.74, 0.7), "landmark"))
		landmarks.append(["clock_crown", Transform3D(Basis(), Vector3(tx + 8, 64, -76))])
		_add(_building([[tx + 2, -82, tx + 14, -70, 64, 92]], Style.SANDSTONE, Color(0.76, 0.74, 0.7), "invisible"))
	# Shipping-line office: heavy palazzo block.
	_add(_building([[92, 6, 162, 78, 0, 38]], Style.STONE, Color(0.82, 0.8, 0.74), "landmark"))
	# Port authority: domed block with corner cupolas.
	_add(_building([[92, 100, 162, 164, 0, 34]], Style.STONE, Color(0.8, 0.78, 0.72), "landmark"))
	landmarks.append(["harbour_dome", Transform3D(Basis(), Vector3(127, 34, 132))])
	_add(_building([[115, 119, 139, 145, 34, 56]], Style.STONE, Color(0.8, 0.78, 0.72), "invisible"))
	# Dark glass wedges by the old dock entrance.
	_add(_building([[96, -214, 128, -176, 0, 30]], Style.DARK_GLASS, Color(0.15, 0.16, 0.18), "landmark"))
	_add(_building([[134, -220, 160, -180, 0, 26]], Style.DARK_GLASS, Color(0.15, 0.16, 0.18), "landmark"))
	# Radio beacon in the business district.
	landmarks.append(["beacon", Transform3D(Basis(), Vector3(CBD_CENTER.x - 40, 0, CBD_CENTER.y + 60))])
	var bx := CBD_CENTER.x - 40
	var bz := CBD_CENTER.y + 60
	_add(_building([[bx - 6, bz - 6, bx + 6, bz + 6, 0, 115]], Style.MODERN, Color(0.82, 0.8, 0.76), "invisible"))
	_add(_building([[bx - 11, bz - 11, bx + 11, bz + 11, 115, 127]], Style.MODERN, Color(0.82, 0.8, 0.76), "invisible"))
	# Sandstone cathedral on the eastern ridge.
	var cx := 1210.0
	var cz := -420.0
	var sand := Color(0.64, 0.4, 0.31)
	_add(_building([[cx - 90, cz - 24, cx + 90, cz + 24, 0, 44]], Style.SANDSTONE, sand, "landmark"))
	_add(_building([[cx - 22, cz - 60, cx + 22, cz + 60, 0, 40]], Style.SANDSTONE, sand, "landmark"))
	_add(_building([[cx - 17, cz - 17, cx + 17, cz + 17, 44, 82]], Style.SANDSTONE, sand, "landmark"))
	landmarks.append(["cathedral_top", Transform3D(Basis(), Vector3(cx, 82, cz))])
	_add(_building([[cx - 17, cz - 17, cx + 17, cz + 17, 82, 103]], Style.SANDSTONE, sand, "invisible"))


func _reserved(r: Rect2) -> bool:
	for q in reserved:
		if r.grow(4.0).intersects(q):
			return true
	return false


# ---------------------------------------------------------------- blocks
func _blocks() -> void:
	var bx := []
	for i in x_streets.size() - 1:
		var a: Array = x_streets[i]
		var b: Array = x_streets[i + 1]
		bx.append([a[0] + a[1] * 0.5, b[0] - b[1] * 0.5])
	var bz := []
	for i in z_streets.size() - 1:
		var a: Array = z_streets[i]
		var b: Array = z_streets[i + 1]
		bz.append([a[0] + a[1] * 0.5, b[0] - b[1] * 0.5])
	var cbd_plaza_done := false
	for xr in bx:
		for zr in bz:
			var rect := Rect2(xr[0], zr[0], xr[1] - xr[0], zr[1] - zr[0])
			blocks.append(rect)
			var c := rect.get_center()
			var dist := district(c.x, c.y)
			var brng := RandomNumberGenerator.new()
			brng.seed = hash(Vector2i(int(c.x), int(c.y))) ^ seed
			# A plaza near the beacon: the beacon stands in it, and it's a big launch gap.
			if not cbd_plaza_done and rect.grow(10).has_point(Vector2(CBD_CENTER.x - 40, CBD_CENTER.y + 60)):
				parks.append(rect)
				_park_props(rect, brng)
				cbd_plaza_done = true
				continue
			if dist == "docks" and brng.randf() < 0.32 and c.x < 470.0:
				var basin := rect.grow(-6.0)
				water.append(basin)
				if brng.randf() < 0.7:
					props.append(["crane", Transform3D(Basis(Vector3.UP, brng.randf_range(0, TAU)),
						Vector3(basin.position.x + 4, 0, basin.get_center().y))])
				continue
			if dist == "georgian" and brng.randf() < 0.12 or dist == "midtown" and brng.randf() < 0.06:
				parks.append(rect)
				_park_props(rect, brng)
				continue
			_fill_block(rect, dist, brng)
			_street_props(rect, brng)


func _park_props(rect: Rect2, brng: RandomNumberGenerator) -> void:
	var n := int(rect.get_area() / 420.0)
	for i in n:
		var p := Vector3(brng.randf_range(rect.position.x + 5, rect.end.x - 5), 0.15,
			brng.randf_range(rect.position.y + 5, rect.end.y - 5))
		var s := brng.randf_range(0.8, 1.35)
		props.append(["tree", Transform3D(Basis(Vector3.UP, brng.randf_range(0, TAU)).scaled(Vector3.ONE * s), p)])


func _street_props(rect: Rect2, brng: RandomNumberGenerator) -> void:
	# Streetlights along the long edges, facing the road.
	var step := 32.0
	var x := rect.position.x + 8.0
	while x < rect.end.x - 6.0:
		props.append(["streetlight", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, 0.15, rect.position.y + 1.2))])
		props.append(["streetlight", Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, 0.15, rect.end.y - 1.2))])
		x += step
	if brng.randf() < 0.5:
		var z := rect.position.y + 10.0
		while z < rect.end.y - 6.0:
			props.append(["tree", Transform3D(Basis().scaled(Vector3.ONE * 0.7), Vector3(rect.position.x + 2.0, 0.15, z))])
			z += 18.0


func _fill_block(rect: Rect2, dist: String, brng: RandomNumberGenerator) -> void:
	var inner := rect.grow(-3.5)
	var lots: Array = []
	_split(inner, lots, brng, 26.0 if dist in ["georgian", "docks"] else 34.0, 0)
	for lot in lots:
		if _reserved(lot):
			continue
		var r: Rect2 = lot.grow(-1.2)
		if r.size.x < 9.0 or r.size.y < 9.0:
			continue
		_make_building(r, dist, brng)


func _split(r: Rect2, out: Array, brng: RandomNumberGenerator, min_size: float, depth: int) -> void:
	var can_x := r.size.x > min_size * 2.0
	var can_z := r.size.y > min_size * 2.0
	if depth > 3 or not (can_x or can_z) or (depth >= 1 and brng.randf() < 0.22):
		out.append(r)
		return
	var along_x := can_x and (not can_z or r.size.x > r.size.y)
	var f := brng.randf_range(0.35, 0.65)
	if along_x:
		var w := r.size.x * f
		_split(Rect2(r.position, Vector2(w, r.size.y)), out, brng, min_size, depth + 1)
		_split(Rect2(r.position + Vector2(w, 0), Vector2(r.size.x - w, r.size.y)), out, brng, min_size, depth + 1)
	else:
		var h := r.size.y * f
		_split(Rect2(r.position, Vector2(r.size.x, h)), out, brng, min_size, depth + 1)
		_split(Rect2(r.position + Vector2(0, h), Vector2(r.size.x, r.size.y - h)), out, brng, min_size, depth + 1)


func _height_for(dist: String, c: Vector2, brng: RandomNumberGenerator) -> float:
	match dist:
		"cbd":
			var d := c.distance_to(CBD_CENTER)
			var peak := 60.0 + 120.0 * exp(-pow(d / 300.0, 2.0))
			if brng.randf() < 0.12:
				return brng.randf_range(24.0, 40.0)  # technical low spots
			return peak * brng.randf_range(0.7, 1.25)
		"midtown":
			return brng.randf_range(32.0, 82.0) if brng.randf() > 0.15 else brng.randf_range(90.0, 120.0)
		"waterfront":
			return brng.randf_range(34.0, 70.0)
		"docks":
			return brng.randf_range(16.0, 26.0) if brng.randf() < 0.75 else brng.randf_range(45.0, 85.0)
		_:
			return brng.randf_range(14.0, 32.0) if brng.randf() < 0.85 else brng.randf_range(48.0, 72.0)


func _make_building(r: Rect2, dist: String, brng: RandomNumberGenerator) -> void:
	var c := r.get_center()
	var h := _height_for(dist, c, brng)
	var style: int
	if dist == "docks" and h < 30.0:
		style = Style.WAREHOUSE
	elif dist == "georgian" and h < 40.0:
		style = Style.BRICK if brng.randf() < 0.75 else Style.SANDSTONE
	elif h > 115.0:
		style = Style.GLASS if brng.randf() < 0.6 else Style.DARK_GLASS
	elif h > 65.0:
		style = [Style.MODERN, Style.DECO, Style.GLASS, Style.STONE][brng.randi() % 4]
	elif h > 35.0:
		style = [Style.STONE, Style.BRICK, Style.MODERN, Style.DECO][brng.randi() % 4]
	else:
		style = [Style.BRICK, Style.STONE, Style.SANDSTONE][brng.randi() % 3]
	var cols: Array = STYLE_COLORS[style]
	var col: Color = cols[brng.randi() % cols.size()]
	col = col.lightened(brng.randf_range(-0.06, 0.06))
	var tiers: Array = []
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	if h > 70.0 and min(r.size.x, r.size.y) > 30.0 and brng.randf() < 0.7:
		# Podium + slimmer tower, then setbacks.
		var pod := brng.randf_range(12.0, 22.0)
		tiers.append([x0, z0, x1, z1, 0.0, pod])
		var inset := brng.randf_range(3.0, minf(r.size.x, r.size.y) * 0.22)
		x0 += inset; z0 += inset; x1 -= inset; z1 -= inset
		var y := pod
		var steps := 1 + int(h > 110.0) + int(brng.randf() < 0.4)
		for s in steps:
			var top := y + (h - y) * (0.62 if s < steps - 1 else 1.0)
			if s == steps - 1:
				top = h
			tiers.append([x0, z0, x1, z1, y, top])
			y = top
			var si := brng.randf_range(2.5, 5.0)
			if x1 - x0 - si * 2.0 < 10.0 or z1 - z0 - si * 2.0 < 10.0:
				break
			x0 += si; z0 += si; x1 -= si; z1 -= si
		if tiers[-1][5] < h:
			tiers[-1][5] = h
	else:
		tiers.append([x0, z0, x1, z1, 0.0, h])
		if h > 40.0 and brng.randf() < 0.35 and min(r.size.x, r.size.y) > 22.0:
			var si := brng.randf_range(3.0, 6.0)
			var top := h + brng.randf_range(6.0, 14.0)
			tiers.append([x0 + si, z0 + si, x1 - si, z1 - si, h, top])
	var b := _building(tiers, style, col, "normal")
	b["seed"] = brng.randf()
	_add(b)
	# Rooftop furniture.
	var top_t: Array = tiers[-1]
	var rx: float = (top_t[0] + top_t[2]) * 0.5
	var rz: float = (top_t[1] + top_t[3]) * 0.5
	var ry: float = top_t[5]
	var tw: float = top_t[2] - top_t[0]
	var td: float = top_t[3] - top_t[1]
	if (style == Style.BRICK or style == Style.STONE or style == Style.SANDSTONE) and h < 80.0 and brng.randf() < 0.55:
		props.append(["water_tower", Transform3D(Basis(Vector3.UP, brng.randf_range(0, TAU)),
			Vector3(rx + brng.randf_range(-tw, tw) * 0.25, ry, rz + brng.randf_range(-td, td) * 0.25))])
	if h > 100.0 and brng.randf() < 0.55:
		props.append(["antenna", Transform3D(Basis(), Vector3(rx, ry, rz))])
	for i in brng.randi_range(0, 3):
		if tw > 10.0 and td > 10.0:
			props.append(["ac_unit", Transform3D(Basis(Vector3.UP, (brng.randi() % 2) * PI * 0.5),
				Vector3(rx + brng.randf_range(-tw, tw) * 0.32, ry, rz + brng.randf_range(-td, td) * 0.32))])


func _building(tiers: Array, style: int, col: Color, kind: String) -> Dictionary:
	return {"tiers": tiers, "style": style, "color": col, "kind": kind, "seed": rng.randf()}


func _add(b: Dictionary) -> void:
	buildings.append(b)
	if b["kind"] == "landmark" or b["kind"] == "invisible":
		var t: Array = b["tiers"][0]
		reserved.append(Rect2(t[0], t[1], t[2] - t[0], t[3] - t[1]))


# ------------------------------------------------------- elevated & bridges
func _viaduct() -> void:
	# Elevated railway along the waterfront – a long, low, grappleable line.
	var z := MIN_Z + 20.0
	while z < MAX_Z - 25.0:
		landmarks.append(["viaduct", Transform3D(Basis(Vector3.UP, PI), Vector3(48, 0, z + 25.0))])
		z += 25.0
	_add(_building([[43.5, MIN_Z + 20.0, 52.5, z, 9.8, 12.0]], Style.MODERN, Color(0.2, 0.24, 0.26), "invisible"))


func _skybridges() -> void:
	# Glass skybridges across streets between tall neighbours in the CBD.
	var tall: Array = []
	for b in buildings:
		if b["kind"] != "normal":
			continue
		var t: Array = b["tiers"][0]
		var top: float = b["tiers"][-1][5]
		if top > 80.0 and district((t[0] + t[2]) * 0.5, (t[1] + t[3]) * 0.5) == "cbd":
			tall.append(b)
	var made := 0
	for i in tall.size():
		for j in range(i + 1, tall.size()):
			if made >= 14:
				return
			var a: Array = tall[i]["tiers"][0]
			var b2: Array = tall[j]["tiers"][0]
			var ov_z0 := maxf(a[1], b2[1])
			var ov_z1 := minf(a[3], b2[3])
			var gap: float = b2[0] - a[2]
			if ov_z1 - ov_z0 > 12.0 and gap > 10.0 and gap < 34.0:
				var y := minf(tall[i]["tiers"][-1][5], tall[j]["tiers"][-1][5]) * rng.randf_range(0.4, 0.6)
				var zc := (ov_z0 + ov_z1) * 0.5
				_add(_building([[a[2] - 1.0, zc - 3.5, b2[0] + 1.0, zc + 3.5, y, y + 5.0]], Style.DARK_GLASS,
					Color(0.22, 0.26, 0.3), "bridge"))
				made += 1


# --------------------------------------------------------------- traffic
func _traffic() -> void:
	for s in x_streets:
		var x: float = s[0]
		if s[1] > 20.0:
			avenue_marks.append([Vector3(x, 0.03, MIN_Z), Vector3(x, 0.03, MAX_Z)])
		lanes.append([Vector3(x - 3.2, 0.0, MIN_Z), Vector3(x - 3.2, 0.0, MAX_Z)])
		lanes.append([Vector3(x + 3.2, 0.0, MAX_Z), Vector3(x + 3.2, 0.0, MIN_Z)])
	for s in z_streets:
		var z: float = s[0]
		if s[1] > 20.0:
			avenue_marks.append([Vector3(MIN_X, 0.03, z), Vector3(MAX_X, 0.03, z)])
		lanes.append([Vector3(MIN_X, 0.0, z + 3.2), Vector3(MAX_X, 0.0, z + 3.2)])
		lanes.append([Vector3(MAX_X, 0.0, z - 3.2), Vector3(MIN_X, 0.0, z - 3.2)])
	water.append(Rect2(-1500, -2500, 1500 + RIVER_EDGE, 5000))


func _land() -> void:
	var rects: Array = [Rect2(RIVER_EDGE, MIN_Z - 200, MAX_X + 400 - RIVER_EDGE, (MAX_Z - MIN_Z) + 400)]
	for w in water:
		if w.position.x < 0.0:
			continue
		var next: Array = []
		for r in rects:
			next.append_array(_subtract(r, w))
		rects = next
	land = rects


static func _subtract(r: Rect2, hole: Rect2) -> Array:
	if not r.intersects(hole):
		return [r]
	var out: Array = []
	var h := r.intersection(hole)
	if h.position.y > r.position.y:
		out.append(Rect2(r.position.x, r.position.y, r.size.x, h.position.y - r.position.y))
	if h.end.y < r.end.y:
		out.append(Rect2(r.position.x, h.end.y, r.size.x, r.end.y - h.end.y))
	if h.position.x > r.position.x:
		out.append(Rect2(r.position.x, h.position.y, h.position.x - r.position.x, h.size.y))
	if h.end.x < r.end.x:
		out.append(Rect2(h.end.x, h.position.y, r.end.x - h.end.x, h.size.y))
	return out


# ----------------------------------------------------------------- queries
static func chunk_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))


func buildings_by_chunk() -> Dictionary:
	var out := {}
	for b in buildings:
		var t: Array = b["tiers"][0]
		var k := chunk_of(Vector2((t[0] + t[2]) * 0.5, (t[1] + t[3]) * 0.5))
		if not out.has(k):
			out[k] = []
		out[k].append(b)
	return out


func props_by_chunk() -> Dictionary:
	var out := {}
	for p in props:
		var o: Vector3 = p[1].origin
		var k := chunk_of(Vector2(o.x, o.z))
		if not out.has(k):
			out[k] = []
		out[k].append(p)
	return out


func is_water(p: Vector3) -> bool:
	for w in water:
		if (w as Rect2).has_point(Vector2(p.x, p.z)):
			return true
	return false


func tallest_near(p: Vector2, radius: float) -> float:
	var best := 0.0
	for b in buildings:
		var t: Array = b["tiers"][0]
		if Vector2((t[0] + t[2]) * 0.5, (t[1] + t[3]) * 0.5).distance_to(p) < radius:
			best = maxf(best, b["tiers"][-1][5])
	return best
