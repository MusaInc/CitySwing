class_name CityLayout
extends RefCounted
## Deterministic city plan (pure data – no nodes). Loosely Liverpool: a river
## to the west, a waterfront of three domed/clock-towered landmarks, a dense
## glass business district peaking around a radio beacon, brick docks with
## basins and cranes to the north, low Georgian terraces to the east under a
## huge sandstone cathedral, and an elevated railway along the waterfront.
## Heights are shaped for swinging: tall clusters, wide avenues as launch gaps,
## low-rise districts as technical terrain.
## Compact (~0.94 x 1.24 km) so every street is worth swinging down: a
## supertall core, construction sites with tower cranes, quay cranes over the
## dock basins, rooftop billboards as low anchors, and a red suspension bridge
## over the river. Structures that aren't buildings (cranes, bridge) are
## collision boxes ("structure" kind) plus `structures` specs for the mesher
## and `anchor_lines` the web targeting can snap to.

const CHUNK := 200.0
const MIN_X := 70.0
const MAX_X := 1010.0
const MIN_Z := -640.0
const MAX_Z := 600.0
const RIVER_EDGE := 30.0
const FAR_SHORE := -440.0
const CBD_CENTER := Vector2(560.0, -170.0)
const CBD_RADIUS := 330.0
const BRIDGE_Z := -17.0
const BRIDGE_DECK := 24.0
const BRIDGE_TOWERS := [-80.0, -340.0]
const BRIDGE_TOWER_TOP := 132.0

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
var x_streets: Array = []      # [centre, width]
var z_streets: Array = []
var land: Array = []           # Rect2 ground collision (land minus basins)
var landmarks: Array = []      # [scene:String, Transform3D]
var spawn := Vector3(330, 0, -60)
var reserved: Array = []      # Rect2 footprints owned by landmarks
var structures: Array = []    # Dictionary specs for BuildingMesher.add_structure (cranes, bridge)
var anchor_lines: Array = []  # [from:Vector3, to:Vector3] web anchors on thin structures (jibs, cables)
var crossings: Array = []     # [x, z] street intersection centres
## Set-piece collision that isn't an axis-aligned box: [Transform3D, size]
## oriented boxes (beams) and convex hulls (PackedVector3Array).
var kit_obbs: Array = []
var kit_hulls: Array = []
var pieces: SetPieces
var _sites: Array = []        # [Rect2, district] construction lots, built after the blocks


func generate(p_seed := 1207) -> CityLayout:
	seed = p_seed
	rng.seed = seed
	_streets()
	_landmarks()
	_bridge()
	pieces = SetPieces.new(self)
	_blocks()
	_construction()
	_viaduct()
	_skybridges()
	pieces.elevated_rail()
	pieces.gateways()
	pieces.lighthouse()
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
		var bw := rng.randf_range(66.0, 100.0)
		x += w + bw
		i += 1
	x_streets = xs
	var z := MIN_Z
	i = 0
	var zs: Array = []
	while z < MAX_Z:
		var w := 28.0 if i % 3 == 1 else 16.0
		zs.append([z + w * 0.5, w])
		var bd := rng.randf_range(64.0, 100.0)
		z += w + bd
		i += 1
	z_streets = zs
	for xs_ in x_streets:
		for zs_ in z_streets:
			crossings.append([xs_[0], zs_[0]])


func district(x: float, z: float) -> String:
	if x < 250.0 and z > -330.0 and z < 260.0:
		return "waterfront"
	if z >= 260.0 and x < 560.0:
		return "docks"
	if x > 780.0 or z < -540.0 or z > 520.0:
		return "georgian"
	var d := Vector2(x, z).distance_to(CBD_CENTER)
	if d < CBD_RADIUS:
		return "cbd"
	return "midtown"


# ------------------------------------------------------------- landmarks
func _landmarks() -> void:
	# Clock building: stone block, two clock towers crowned with domes + birds.
	_add(_building([[92, -112, 162, -40, 0, 50]], Style.SANDSTONE, Color(0.76, 0.74, 0.7), "landmark"))
	for tx: float in [94.0, 144.0]:
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
	var cx := 900.0
	var cz := -390.0
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
			var piece := pieces.piece_for(rect)
			if piece != "":
				pieces.build(piece, rect)
				if piece in ["wheel", "yard"]:
					_street_props(rect, brng)
				continue
			if dist == "docks" and brng.randf() < 0.4 and c.x < 470.0:
				var basin := rect.grow(-6.0)
				water.append(basin)
				_quay_cranes(basin, brng)
				pieces.ship(basin)
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
	# Construction sites (cbd/midtown): the biggest lot gets a half-built
	# frame and a tower crane instead of a building.
	var site := Rect2()
	if dist in ["cbd", "midtown"] and _sites.size() < 9 and brng.randf() < 0.17:
		for lot in lots:
			if lot.get_area() > site.get_area() and minf(lot.size.x, lot.size.y) > 26.0 and not _reserved(lot):
				site = lot
		if site.has_area():
			_sites.append([site, dist])
	for lot in lots:
		if lot == site or _reserved(lot):
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
	# Same random draws as before (the plan doesn't reshuffle); only the
	# scale grew: a supertall core near 300 m, a real midtown skyline, and
	# low districts that are mid-rise rather than terraces.
	match dist:
		"cbd":
			var d := c.distance_to(CBD_CENTER)
			var peak := 90.0 + 215.0 * exp(-pow(d / 260.0, 2.0))
			if brng.randf() < 0.1:
				return brng.randf_range(30.0, 50.0)  # technical low spots
			return peak * brng.randf_range(0.72, 1.22)
		"midtown":
			return brng.randf_range(50.0, 125.0) if brng.randf() > 0.3 else brng.randf_range(135.0, 210.0)
		"waterfront":
			return brng.randf_range(42.0, 88.0)
		"docks":
			return brng.randf_range(18.0, 30.0) if brng.randf() < 0.75 else brng.randf_range(60.0, 110.0)
		_:
			return brng.randf_range(18.0, 40.0) if brng.randf() < 0.85 else brng.randf_range(62.0, 95.0)


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
	var ry: float = BuildingMesher.roof_y(b)  # the drawn roof (over the cornice), not the wall top
	var tw: float = top_t[2] - top_t[0]
	var td: float = top_t[3] - top_t[1]
	# Stair / lift housing tucked into a corner (solid: you land on it). Own
	# random stream, so adding it didn't reshuffle the rest of the city.
	var hrng := RandomNumberGenerator.new()
	hrng.seed = hash(Vector3i(int(rx * 10.0), int(rz * 10.0), int(top_t[5]))) ^ seed
	if tw > 15.0 and td > 15.0 and hrng.randf() < 0.65:
		var sx := 1.0 if hrng.randf() < 0.5 else -1.0
		var sz := 1.0 if hrng.randf() < 0.5 else -1.0
		var hx := rx + sx * (tw * 0.5 - 3.6)
		var hz := rz + sz * (td * 0.5 - 4.0)
		var yaw := 0.0 if sz < 0.0 else PI  # door faces into the roof
		props.append(["roof_hut", Transform3D(Basis(Vector3.UP, yaw), Vector3(hx, ry, hz))])
		buildings.append({"tiers": [[hx - 1.7, hz - 2.1, hx + 1.7, hz + 2.1, ry, ry + 3.1]], "style": Style.MODERN,
			"color": Color.WHITE, "kind": "structure", "seed": 0.0})
	if (style == Style.BRICK or style == Style.STONE or style == Style.SANDSTONE) and h < 80.0 and brng.randf() < 0.55:
		props.append(["water_tower", Transform3D(Basis(Vector3.UP, brng.randf_range(0, TAU)),
			Vector3(rx + brng.randf_range(-tw, tw) * 0.25, ry, rz + brng.randf_range(-td, td) * 0.25))])
	if h > 235.0 and tw > 16.0 and td > 16.0:
		# Supertall crown: a slim spire, the highest anchor in the city.
		var sp := brng.randf_range(2.5, 3.5)
		_add(_building([[rx - sp, rz - sp, rx + sp, rz + sp, ry, ry + brng.randf_range(28.0, 48.0)]], style,
			col.lightened(0.15), "spire"))
	elif h > 100.0 and brng.randf() < 0.55:
		props.append(["antenna", Transform3D(Basis(), Vector3(rx, ry, rz))])
	if h > 14.0 and h < 75.0 and tiers.size() == 1 and minf(tw, td) > 16.0 and brng.randf() < 0.16:
		_billboard(tiers[0], ry, brng)
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


# ------------------------------------------------------------ structures
## Collision-only box (the visuals come from `structures` specs).
func _box(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float) -> void:
	buildings.append({"tiers": [[minf(x0, x1), minf(z0, z1), maxf(x0, x1), maxf(z0, z1), y0, y1]],
		"style": Style.MODERN, "color": Color.WHITE, "kind": "structure", "seed": 0.0})


func _anchor(a: Vector3, b: Vector3) -> void:
	anchor_lines.append([a, b])


# ------------------------------------------------------------- set-piece kit
## A kit: one structure spec the mesher draws ("solids", "beams", "prisms")
## whose collision is made from the very same list.
func _kit(name: String) -> Dictionary:
	var k := {"type": "kit", "name": name, "solids": [], "beams": [], "prisms": []}
	structures.append(k)
	return k


func _ksolid(k: Dictionary, x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, col: Color,
		collide := true) -> void:
	k["solids"].append([minf(x0, x1), minf(z0, z1), maxf(x0, x1), maxf(z0, z1), y0, y1, col])
	if collide:
		_box(x0, z0, x1, z1, y0, y1)


## Beam of cross-section w×h from a to b (BuildingMesher.beam's frame).
func _kbeam(k: Dictionary, a: Vector3, b: Vector3, w: float, h: float, col: Color, collide := true) -> void:
	k["beams"].append([a, b, w, h, col])
	if collide and a.distance_to(b) > 0.01:
		kit_obbs.append([Transform3D(BuildingMesher.beam_basis(a, b), (a + b) * 0.5), Vector3(w, h, a.distance_to(b))])


## Vertical prism over a convex polygon (x, z) from y0 to y1.
func _kprism(k: Dictionary, pts: PackedVector2Array, y0: float, y1: float, col: Color) -> void:
	k["prisms"].append([pts, y0, y1, col])
	var hull := PackedVector3Array()
	for p in pts:
		hull.append(Vector3(p.x, y0, p.y))
		hull.append(Vector3(p.x, y1, p.y))
	kit_hulls.append(hull)


## Container cranes on the west quay of a dock basin, booms out over the water.
func _quay_cranes(basin: Rect2, brng: RandomNumberGenerator) -> void:
	var n := 2 if basin.size.y > 72.0 else 1
	var reach := minf(46.0, basin.size.x - 6.0)
	for i in n:
		var qx := basin.position.x
		var z := basin.position.y + basin.size.y * (i + 1.0) / (n + 1.0) + brng.randf_range(-4.0, 4.0)
		var top := 34.0
		for lx: float in [qx - 3.0, qx + 13.0]:
			for lz: float in [z - 6.0, z + 6.0]:
				_box(lx - 0.8, lz - 0.8, lx + 0.8, lz + 0.8, -2.0, top)
		for lz: float in [z - 6.0, z + 6.0]:
			_box(qx - 3.8, lz - 0.9, qx + 13.8, lz + 0.9, top - 4.0, top)
		_box(qx - 11.2, z - 2.0, qx + reach + 0.2, z + 2.0, top - 0.2, top + 3.0)
		_box(qx + 3.5, z - 1.0, qx + 5.5, z + 1.0, top + 3.0, top + 22.0)
		for lz: float in [z - 6.0, z + 6.0]:
			_box(qx - 3.8, lz - 0.9, qx + 13.8, lz + 0.9, 7.0, 8.4)  # lower portal beams
		for lx: float in [qx - 3.0, qx + 13.0]:  # diagonal leg braces (BuildingMesher._quay_crane)
			for e: Array in [[Vector3(lx, 4.0, z - 6.0), Vector3(lx, top - 4.0, z + 6.0)],
					[Vector3(lx, 4.0, z + 6.0), Vector3(lx, top - 4.0, z - 6.0)]]:
				kit_obbs.append([Transform3D(BuildingMesher.beam_basis(e[0], e[1]), (e[0] + e[1]) * 0.5),
					Vector3(0.4, 0.4, (e[0] as Vector3).distance_to(e[1]))])
		_box(qx - 11.0, z - 2.6, qx - 3.0, z + 2.6, top + 3.0, top + 7.0)  # machinery house
		var tx := qx + reach * 0.6
		_box(tx - 1.5, z - 2.0, tx + 1.5, z + 2.0, top - 1.0, top)  # trolley
		_box(tx - 6.0, z - 1.3, tx + 6.0, z + 1.3, 11.4, 14.0)  # container on the spreader
		_anchor(Vector3(qx + 4.0, top - 0.3, z), Vector3(qx + reach - 1.0, top - 0.3, z))
		structures.append({"type": "quay_crane", "x": qx, "z": z, "top": top, "reach": reach,
			"color": [Color(0.16, 0.36, 0.58), Color(0.78, 0.2, 0.14), Color(0.92, 0.68, 0.12)][brng.randi() % 3]})


## A rooftop billboard on one roof edge: a low, grappleable panel on legs.
func _billboard(t: Array, roof: float, brng: RandomNumberGenerator) -> void:
	var side := brng.randi() % 4
	var along_x := side < 2
	var len := minf((t[2] - t[0]) if along_x else (t[3] - t[1]), 18.0) - 4.0
	var cx: float = (t[0] + t[2]) * 0.5
	var cz: float = (t[1] + t[3]) * 0.5
	var y0: float = roof + 2.6
	var y1 := y0 + brng.randf_range(5.5, 7.5)
	var r: Array
	match side:
		0: r = [cx - len * 0.5, t[1] + 1.0, cx + len * 0.5, t[1] + 1.6]
		1: r = [cx - len * 0.5, t[3] - 1.6, cx + len * 0.5, t[3] - 1.0]
		2: r = [t[0] + 1.0, cz - len * 0.5, t[0] + 1.6, cz + len * 0.5]
		_: r = [t[2] - 1.6, cz - len * 0.5, t[2] - 1.0, cz + len * 0.5]
	var cols := [Color(0.95, 0.75, 0.15), Color(0.85, 0.2, 0.18), Color(0.15, 0.6, 0.62), Color(0.95, 0.95, 0.92),
		Color(0.25, 0.32, 0.75), Color(0.9, 0.45, 0.6)]
	var b := _building([[r[0], r[1], r[2], r[3], y0, y1]], Style.MODERN, cols[brng.randi() % cols.size()], "sign")
	b["roof"] = roof
	b["seed"] = brng.randf()
	_add(b)


## Half-built towers on the construction lots picked while filling blocks:
## concrete core, open floor slabs, and a tower crane whose jib clears the
## neighbours (it's placed to swing from: the jib reaches out over a street).
func _construction() -> void:
	for entry in _sites:
		var lot: Rect2 = (entry[0] as Rect2).grow(-1.2)
		var dist: String = entry[1]
		var brng := RandomNumberGenerator.new()
		brng.seed = hash(Vector2i(int(lot.position.x), int(lot.position.y))) ^ seed
		var c := lot.get_center()
		var h := clampf(_height_for(dist, c, brng) * brng.randf_range(0.4, 0.6), 34.0, 120.0)
		var f := lot.grow(-4.0)
		var floors: Array = []
		var y := 4.2
		while y <= h:
			floors.append([f.position.x, f.position.y, f.end.x, f.end.y, y - 0.45, y])
			y += 4.2
		var top: float = floors[-1][5]
		var fb := _building(floors, Style.MODERN, Color(0.66, 0.65, 0.62), "frame")
		_add(fb)
		_add(_building([[c.x - 4.5, c.y - 4.5, c.x + 4.5, c.y + 4.5, 0.0, top + 6.0]], Style.MODERN,
			Color(0.62, 0.61, 0.58), "plain"))
		props.append(["ac_unit", Transform3D(Basis(), Vector3(c.x + 6.0, top, c.y + 6.0))])
		_tower_crane(lot, top, brng)


func _tower_crane(lot: Rect2, site_top: float, brng: RandomNumberGenerator) -> void:
	var jib := 52.0
	var counter := 16.0
	var best := {}
	var best_obst := INF
	var corners := [lot.position + Vector2(2.5, 2.5), Vector2(lot.end.x - 2.5, lot.position.y + 2.5),
		lot.end - Vector2(2.5, 2.5), Vector2(lot.position.x + 2.5, lot.end.y - 2.5)]
	for m in corners:
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			# Jib pointing out of the lot (over the street), not back over the frame.
			if (m + d * 10.0).distance_to(lot.get_center()) < m.distance_to(lot.get_center()):
				continue
			var obst := _max_height_along(m - d * counter, m + d * jib, 4.0)
			obst += brng.randf() * 4.0
			if obst < best_obst:
				best_obst = obst
				best = {"m": m, "d": d}
	if best.is_empty():
		return
	var mh := maxf(best_obst + 12.0, site_top + 30.0)
	if mh > 235.0:
		return
	var m: Vector2 = best["m"]
	var d: Vector2 = best["d"]
	var tip := m + d * jib
	var back := m - d * counter
	_box(m.x - 3.0, m.y - 3.0, m.x + 3.0, m.y + 3.0, 0.0, 1.2)  # concrete base
	_box(m.x - 1.6, m.y - 1.6, m.x + 1.6, m.y + 1.6, 1.2, mh)  # lattice mast (chords included)
	_box(m.x - 1.8, m.y - 1.8, m.x + 1.8, m.y + 1.8, mh, mh + 1.2)  # slewing unit
	var side := Vector2(-d.y, d.x)
	var j0 := m - side * 1.2
	var j1 := tip + side * 1.2
	_box(j0.x, j0.y, j1.x, j1.y, mh + 1.0, mh + 3.6)
	var c0 := m - side * 1.8
	var c1 := back + side * 1.8
	_box(c0.x, c0.y, c1.x, c1.y, mh + 1.0, mh + 3.2)
	var w0 := back + d * 4.0 - side * 1.8
	var w1 := back + side * 1.8
	_box(w0.x, w0.y, w1.x, w1.y, mh - 2.6, mh + 1.2)
	_box(m.x - 1.0, m.y - 1.0, m.x + 1.0, m.y + 1.0, mh + 3.4, mh + 13.0)
	_anchor(Vector3(m.x + d.x * 4.0, mh + 0.9, m.y + d.y * 4.0), Vector3(tip.x, mh + 0.9, tip.y))
	_anchor(Vector3(m.x - d.x * 3.0, mh + 0.9, m.y - d.y * 3.0), Vector3(back.x + d.x * 4.0, mh + 0.9, back.y + d.y * 4.0))
	var trolley := brng.randf_range(0.35, 0.85)
	var hook := brng.randf_range(0.25, 0.6)
	# Trolley, hook block and its load of beams (BuildingMesher._tower_crane).
	var tr := m + d * jib * trolley
	_box(tr.x - 0.8, tr.y - 0.8, tr.x + 0.8, tr.y + 0.8, mh + 0.7, mh + 1.2)
	var hook_y := lerpf(8.0, mh - 6.0, hook)
	_box(tr.x - 0.5, tr.y - 0.5, tr.x + 0.5, tr.y + 0.5, hook_y + 0.4, hook_y + 1.4)
	var load_a := tr - d * 3.2 - side * 0.7
	var load_b := tr + d * 3.2 + side * 0.7
	_box(load_a.x, load_a.y, load_b.x, load_b.y, hook_y - 0.75, hook_y - 0.25)
	structures.append({"type": "tower_crane", "x": m.x, "z": m.y, "h": mh, "dir": d, "jib": jib, "counter": counter,
		"trolley": trolley, "hook": hook})


## Tallest building/structure top whose footprint touches the strip a→b (width w).
func _max_height_along(a: Vector2, b: Vector2, w: float) -> float:
	var r := Rect2(a, Vector2.ZERO).expand(b).grow(w * 0.5)
	var best := 0.0
	for bd in buildings:
		for t in bd["tiers"]:
			if Rect2(t[0], t[1], t[2] - t[0], t[3] - t[1]).intersects(r):
				best = maxf(best, t[5])
	return best


## Suspension bridge from the waterfront to the far shore: two red towers,
## sagging main cables (anchor lines) and a deck to land on.
func _bridge() -> void:
	var zc := BRIDGE_Z
	var deck := BRIDGE_DECK
	var top := BRIDGE_TOWER_TOP
	var x_east := 56.0
	var x_west := FAR_SHORE + 14.0
	_box(x_west, zc - 10.0, x_east, zc + 10.0, deck - 2.0, deck)
	for sz: float in [-1.0, 1.0]:
		_box(x_west, zc + sz * 10.0, x_east, zc + sz * 8.8, deck - 2.4, deck + 0.4)  # side girders
	for tx: float in BRIDGE_TOWERS:
		for sz: float in [-1.0, 1.0]:
			_box(tx - 3.0, zc + sz * 15.0, tx + 3.0, zc + sz * 9.5, -2.0, top)
		for sz: float in [-1.0, 1.0]:
			_box(tx - 3.5, zc + sz * 15.5, tx + 3.5, zc + sz * 9.0, top, top + 2.5)  # tower caps
		_box(tx - 5.0, zc - 18.0, tx + 5.0, zc + 18.0, -3.0, 1.0)  # footing in the river
		for yy in [[deck - 6.0, deck - 2.0], [88.0, 92.0], [top - 6.0, top - 2.0]]:
			_box(tx - 2.5, zc - 9.5, tx + 2.5, zc + 9.5, yy[0], yy[1])
			_anchor(Vector3(tx, yy[0] - 0.1, zc - 9.0), Vector3(tx, yy[0] - 0.1, zc + 9.0))
	# Anchorages (solid stone blocks at both ends).
	_add(_building([[x_east - 2.0, zc - 14.0, x_east + 14.0, zc + 14.0, 0.0, deck + 6.0]], Style.STONE,
		Color(0.62, 0.58, 0.52), "plain"))
	_add(_building([[x_west - 16.0, zc - 14.0, x_west + 2.0, zc + 14.0, -2.0, deck + 6.0]], Style.STONE,
		Color(0.62, 0.58, 0.52), "plain"))
	var cables: Array = []
	for sz: float in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		var z := zc + sz * 12.25
		var ta: float = BRIDGE_TOWERS[0]
		var tb: float = BRIDGE_TOWERS[1]
		var sag := deck + 5.0
		# East side span: anchorage → tower A (slight sag).
		for i in 6:
			var u := i / 6.0
			pts.append(Vector3(lerpf(x_east + 4.0, ta, u), lerpf(deck + 5.0, top - 1.0, u) - sin(u * PI) * 5.0, z))
		for i in 15:
			var u := i / 14.0
			var x := lerpf(ta, tb, u)
			var k := (u - 0.5) * 2.0
			pts.append(Vector3(x, sag + (top - 1.0 - sag) * k * k, z))
		for i in range(1, 7):
			var u := i / 6.0
			pts.append(Vector3(lerpf(tb, x_west - 4.0, u), lerpf(top - 1.0, deck + 5.0, u) - sin(u * PI) * 5.0, z))
		cables.append(pts)
		for i in pts.size() - 1:
			if pts[i].y > deck + 9.0 or pts[i + 1].y > deck + 9.0:
				_anchor(pts[i] + Vector3.DOWN * 0.6, pts[i + 1] + Vector3.DOWN * 0.6)
	structures.append({"type": "bridge", "z": zc, "deck": deck, "top": top, "towers": BRIDGE_TOWERS,
		"x_east": x_east, "x_west": x_west, "cables": cables})


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
		if top > 80.0 and district((t[0] + t[2]) * 0.5, (t[1] + t[3]) * 0.5) in ["cbd", "midtown"]:
			tall.append(b)
	var made := 0
	for i in tall.size():
		for j in range(i + 1, tall.size()):
			if made >= 20:
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
		lanes.append([Vector3(x - 3.2, 0.0, MIN_Z), Vector3(x - 3.2, 0.0, MAX_Z)])
		lanes.append([Vector3(x + 3.2, 0.0, MAX_Z), Vector3(x + 3.2, 0.0, MIN_Z)])
	for s in z_streets:
		var z: float = s[0]
		lanes.append([Vector3(MIN_X, 0.0, z + 3.2), Vector3(MAX_X, 0.0, z + 3.2)])
		lanes.append([Vector3(MAX_X, 0.0, z - 3.2), Vector3(MIN_X, 0.0, z - 3.2)])
	water.append(Rect2(FAR_SHORE, -2500, RIVER_EDGE - FAR_SHORE, 5000))
	# Traffic lights on two opposite corners of every junction, arms over the road.
	for xs in x_streets:
		for zs in z_streets:
			var hx: float = xs[1] * 0.5 + 1.0
			var hz: float = zs[1] * 0.5 + 1.0
			var a := Vector3(xs[0] + hx, 0.15, zs[0] - hz)
			var b := Vector3(xs[0] - hx, 0.15, zs[0] + hz)
			if not is_water(a) and not _in_park(a):
				props.append(["traffic_light", Transform3D(Basis(Vector3.UP, PI), a)])
			if not is_water(b) and not _in_park(b):
				props.append(["traffic_light", Transform3D(Basis(), b)])


func _in_park(p: Vector3) -> bool:
	for r in parks:
		if (r as Rect2).grow(2.0).has_point(Vector2(p.x, p.z)):
			return true
	return false


func _land() -> void:
	var rects: Array = [Rect2(RIVER_EDGE, MIN_Z - 200, MAX_X + 400 - RIVER_EDGE, (MAX_Z - MIN_Z) + 400)]
	for w in water:
		if w.position.x < 0.0:
			continue
		var next: Array = []
		for r in rects:
			next.append_array(_subtract(r, w))
		rects = next
	# Far shore (where the bridge lands): plain ground, so it isn't "water".
	rects.append(Rect2(FAR_SHORE - 1500.0, -2500.0, 1500.0, 5000.0))
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


func mean_height_near(p: Vector2, radius: float) -> float:
	var total := 0.0
	var n := 0
	for b in buildings:
		if b["kind"] != "normal":
			continue
		var t: Array = b["tiers"][0]
		if Vector2((t[0] + t[2]) * 0.5, (t[1] + t[3]) * 0.5).distance_to(p) < radius:
			total += b["tiers"][-1][5]
			n += 1
	return total / n if n > 0 else 0.0


func tallest_near(p: Vector2, radius: float) -> float:
	var best := 0.0
	for b in buildings:
		var t: Array = b["tiers"][0]
		if Vector2((t[0] + t[2]) * 0.5, (t[1] + t[3]) * 0.5).distance_to(p) < radius:
			best = maxf(best, b["tiers"][-1][5])
	return best
