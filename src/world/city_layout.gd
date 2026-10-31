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
## The city is an island: sea all round except the strait (the old river) to
## the mainland in the west, which the suspension bridge crosses. Past the
## outermost streets an esplanade runs to the sea wall (cliffs on the east,
## where the land is high).
const ESPLANADE := 18.0
const SEA_REACH := 4000.0
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
var island := Rect2()           # the island's land (sea wall to sea wall; west edge = the strait's quay wall)
var sea: Array = []             # Rect2 sea round the island (also in `water`)
var reserved: Array = []      # Rect2 footprints owned by landmarks
var structures: Array = []    # Dictionary specs for BuildingMesher.add_structure (cranes, bridge)
var anchor_lines: Array = []  # [from:Vector3, to:Vector3] web anchors on thin structures (jibs, cables)
var crossings: Array = []     # [x, z] street intersection centres
## Set-piece collision that isn't an axis-aligned box: [Transform3D, size]
## oriented boxes (beams) and convex hulls (PackedVector3Array).
var kit_obbs: Array = []
var kit_hulls: Array = []
var pieces: SetPieces
## The ground (see CityTerrain): junction heights, road surface, terraces.
var terrain := CityTerrain.new()
## Blocks levelled into a terrace (set pieces, basins): Rect2 -> pavement level.
## Every other block's pavement follows the street slope (road_y + kerb).
var terraces := {}
var _sites: Array = []        # [Rect2, district] construction lots, built after the blocks


func generate(p_seed := 1207) -> CityLayout:
	seed = p_seed
	rng.seed = seed
	_streets()
	_island()
	terrain.build(x_streets, z_streets)
	var ls := _snap()
	_landmarks()
	_lift_on_slope(ls)
	_bridge()
	pieces = SetPieces.new(self)
	_blocks()
	_construction()
	_viaduct()
	_skybridges()
	_causeway()
	pieces.elevated_rail()
	pieces.gateways()
	pieces.lighthouse()
	_traffic()
	_sea()
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
	# The island's east edge: one more avenue past the last block column, so
	# the eastern blocks (and the cathedral) are whole and the esplanade runs
	# along a street. No random draw: the rest of the plan is unchanged.
	if x_streets.size() > 0:
		x_streets.append([x + 8.0, 16.0])
	for xs_ in x_streets:
		for zs_ in z_streets:
			crossings.append([xs_[0], zs_[0]])


func _island() -> void:
	var lx: Array = x_streets[-1]
	var fz: Array = z_streets[0]
	var lz: Array = z_streets[-1]
	var east := float(lx[0]) + float(lx[1]) * 0.5 + ESPLANADE
	var north := float(fz[0]) - float(fz[1]) * 0.5 - ESPLANADE
	var south := float(lz[0]) + float(lz[1]) * 0.5 + ESPLANADE
	island = Rect2(RIVER_EDGE, north, east - RIVER_EDGE, south - north)


## Sea on the three open sides (the strait in the west is the river rect).
func _sea() -> void:
	var i := island
	sea = [
		Rect2(i.end.x, -SEA_REACH, SEA_REACH, SEA_REACH * 2.0),                       # east
		Rect2(RIVER_EDGE, -SEA_REACH, i.end.x - RIVER_EDGE, i.position.y + SEA_REACH),  # north
		Rect2(RIVER_EDGE, i.end.y, i.end.x - RIVER_EDGE, SEA_REACH - i.end.y),          # south
	]
	water.append_array(sea)


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


## Lifts what was added to the layout since `snap` (see _snap) by dy metres:
## buildings, props, structures (their y0), anchors, set-piece collision and
## landmark models. Every block's contents are generated at street level 0
## and then lifted onto the block's terrace.
func _lift(snap: Array, dy: float) -> void:
	if absf(dy) < 0.001:
		return
	for i in range(snap[0], buildings.size()):
		var b: Dictionary = buildings[i]
		for t in b["tiers"]:
			t[4] += dy
			t[5] += dy
		if b.has("roof"):
			b["roof"] += dy
		b["base"] = float(b.get("base", 0.0)) + dy
	for i in range(snap[1], props.size()):
		var xf: Transform3D = props[i][1]
		props[i][1] = xf.translated(Vector3(0, dy, 0))
	for i in range(snap[2], structures.size()):
		structures[i]["y0"] = float(structures[i].get("y0", 0.0)) + dy
	for i in range(snap[3], anchor_lines.size()):
		anchor_lines[i] = [anchor_lines[i][0] + Vector3(0, dy, 0), anchor_lines[i][1] + Vector3(0, dy, 0)]
	for i in range(snap[4], kit_obbs.size()):
		kit_obbs[i][0] = (kit_obbs[i][0] as Transform3D).translated(Vector3(0, dy, 0))
	for i in range(snap[5], kit_hulls.size()):
		var hull: PackedVector3Array = kit_hulls[i]
		for k in hull.size():
			hull[k] += Vector3(0, dy, 0)
		kit_hulls[i] = hull
	for i in range(snap[6], landmarks.size()):
		landmarks[i][1] = (landmarks[i][1] as Transform3D).translated(Vector3(0, dy, 0))


## Lifts what a sloping block's generation added since `snap`: each building
## stands level on its own lot at the lot's highest street-level corner (its
## base course shows down the slope: b["foot"]); whatever stands on or in a
## building (roof props, huts, spires, signs) rises with that building; the
## rest (street lights, trees) stands on the ground where it is.
func _lift_on_slope(snap: Array) -> void:
	var feet: Array = []  # [Rect2 footprint, dy]
	for i in range(snap[0], buildings.size()):
		var b: Dictionary = buildings[i]
		if not b["kind"] in ["normal", "landmark"]:
			continue
		var t: Array = b["tiers"][0]
		var fp := Rect2(t[0], t[1], t[2] - t[0], t[3] - t[1])
		var inside := false
		for f in feet:
			if (f[0] as Rect2).grow(0.05).encloses(fp):
				inside = true  # stands on an earlier building (landmark towers)
		if inside:
			continue
		var hi := -INF
		var lo := INF
		for c in [fp.position, fp.end, Vector2(fp.end.x, fp.position.y), Vector2(fp.position.x, fp.end.y)]:
			var y := terrain.road_y(c.x, c.y)
			hi = maxf(hi, y)
			lo = minf(lo, y)
		feet.append([fp, hi])
		b["foot"] = lo
	var dy_at := func(x: float, z: float) -> float:
		for f in feet:
			if (f[0] as Rect2).grow(0.05).has_point(Vector2(x, z)):
				return f[1]
		return terrain.road_y(x, z)
	for i in range(snap[0], buildings.size()):
		var b: Dictionary = buildings[i]
		var t: Array = b["tiers"][0]
		var at: Vector2 = b.get("lift_at", Vector2((t[0] + t[2]) * 0.5, (t[1] + t[3]) * 0.5))
		var dy: float = dy_at.call(at.x, at.y)
		for tt in b["tiers"]:
			tt[4] += dy
			tt[5] += dy
		if b.has("roof"):
			b["roof"] += dy
		if b.has("foot"):
			b["foot"] = minf(b["foot"], dy)
		b["base"] = float(b.get("base", 0.0)) + dy
	for i in range(snap[1], props.size()):
		var xf: Transform3D = props[i][1]
		props[i][1] = xf.translated(Vector3(0, dy_at.call(xf.origin.x, xf.origin.z), 0))
	for i in range(snap[3], anchor_lines.size()):
		var m: Vector3 = (anchor_lines[i][0] + anchor_lines[i][1]) * 0.5
		var up := Vector3(0, dy_at.call(m.x, m.z), 0)
		anchor_lines[i] = [anchor_lines[i][0] + up, anchor_lines[i][1] + up]
	for i in range(snap[6], landmarks.size()):
		var o: Vector3 = (landmarks[i][1] as Transform3D).origin
		landmarks[i][1] = (landmarks[i][1] as Transform3D).translated(Vector3(0, dy_at.call(o.x, o.z), 0))


func _snap() -> Array:
	return [buildings.size(), props.size(), structures.size(), anchor_lines.size(), kit_obbs.size(),
		kit_hulls.size(), landmarks.size()]


## The block (pavement rectangle between streets) containing (x, z), or an
## empty Rect2 on a street or off the grid.
func block_at(x: float, z: float) -> Rect2:
	var xr := Vector2.ZERO
	var zr := Vector2.ZERO
	for i in x_streets.size() - 1:
		var a: float = x_streets[i][0] + x_streets[i][1] * 0.5
		var b: float = x_streets[i + 1][0] - x_streets[i + 1][1] * 0.5
		if x >= a and x <= b:
			xr = Vector2(a, b)
	for j in z_streets.size() - 1:
		var a: float = z_streets[j][0] + z_streets[j][1] * 0.5
		var b: float = z_streets[j + 1][0] - z_streets[j + 1][1] * 0.5
		if z >= a and z <= b:
			zr = Vector2(a, b)
	if xr == Vector2.ZERO or zr == Vector2.ZERO:
		return Rect2()
	return Rect2(xr.x, zr.x, xr.y - xr.x, zr.y - zr.x)


## How far a block's contents are lifted: its terrace (pavement) level less
## the kerb, so a flat block at 0 is exactly the old city.
func block_lift(r: Rect2) -> float:
	return terrain.block_level(r) - CityTerrain.KERB


## Height of what you'd stand on at (x, z): a block's pavement or the road.
## (Basins are water: their quay ring is the block level.)
func ground_y(x: float, z: float) -> float:
	var r := block_at(x, z)
	if r.has_area():
		if terraces.has(r):
			return terraces[r]
		return terrain.road_y(x, z) + CityTerrain.KERB
	return terrain.road_y(x, z)


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
			var snap := _snap()
			var n_struct := structures.size()
			_block(rect, cbd_plaza_done)
			if parks.size() > 0 and parks[-1] == rect and rect.grow(10).has_point(Vector2(CBD_CENTER.x - 40, CBD_CENTER.y + 60)):
				cbd_plaza_done = true
			if structures.size() > n_struct or water.size() > 0 and water[-1] == rect.grow(-6.0):
				# Set pieces and dock basins stand on a level terrace with
				# retaining walls down to the streets.
				terraces[rect] = terrain.block_level(rect)
				_lift(snap, block_lift(rect))
			else:
				_lift_on_slope(snap)


## One block's contents, generated at street level 0 (_blocks lifts them).
func _block(rect: Rect2, cbd_plaza_done: bool) -> void:
	blocks.append(rect)
	var c := rect.get_center()
	var dist := district(c.x, c.y)
	var brng := RandomNumberGenerator.new()
	brng.seed = hash(Vector2i(int(c.x), int(c.y))) ^ seed
	# A plaza near the beacon: the beacon stands in it, and it's a big launch gap.
	if not cbd_plaza_done and rect.grow(10).has_point(Vector2(CBD_CENTER.x - 40, CBD_CENTER.y + 60)):
		parks.append(rect)
		_park_props(rect, brng)
		return
	var piece := pieces.piece_for(rect)
	if piece != "":
		pieces.build(piece, rect)
		if piece in ["wheel", "yard"]:
			_street_props(rect, brng)
		return
	if dist == "docks" and brng.randf() < 0.4 and c.x < 470.0:
		var basin := rect.grow(-6.0)
		water.append(basin)
		_quay_cranes(basin, brng)
		pieces.ship(basin)
		return
	if dist == "georgian" and brng.randf() < 0.07 or dist == "midtown" and brng.randf() < 0.05:
		parks.append(rect)
		_park_props(rect, brng)
		return
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


## Building heights per district. Every district is swingable (most roofs
## ≥ 45 m above the street, the height a good swing needs); each has its own
## skyline. CBD: supertall core near 300 m. Midtown: a real tower district.
## Waterfront: riverside towers and hotels. Docks: chunky warehouses (and
## grain silos) mixed with loft and residential towers. Old Town (georgian):
## mansion blocks with church and civic towers above them.
func _height_for(dist: String, c: Vector2, brng: RandomNumberGenerator) -> float:
	var r := brng.randf()
	match dist:
		"cbd":
			var d := c.distance_to(CBD_CENTER)
			var peak := 90.0 + 215.0 * exp(-pow(d / 260.0, 2.0))
			if r < 0.08:
				return brng.randf_range(34.0, 52.0)  # technical low spots
			return peak * brng.randf_range(0.72, 1.22)
		"midtown":
			return brng.randf_range(62.0, 130.0) if r < 0.6 else brng.randf_range(135.0, 215.0)
		"waterfront":
			return brng.randf_range(52.0, 112.0) if r < 0.75 else brng.randf_range(120.0, 175.0)
		"docks":
			return brng.randf_range(28.0, 44.0) if r < 0.45 else brng.randf_range(62.0, 150.0)
		_:
			if r < 0.45:
				return brng.randf_range(36.0, 60.0)
			return brng.randf_range(62.0, 105.0) if r < 0.88 else brng.randf_range(110.0, 155.0)


## A building's form, from its own random stream (so the plan's draws don't
## shift): "box" (plain or podium + setbacks), "offset" (setbacks stepped to
## one side), "pencil" (slender tower), "slab" (long and thin), "twin" (two
## towers on a podium joined by a sky bridge), "cantilever" (a top block
## hanging out over a recessed body), "crown" (stepped crown), "campanile"
## (a slim tower rising off one corner), "silos" (a grain-silo row).
func _form_for(dist: String, h: float, r: Rect2, frng: RandomNumberGenerator) -> String:
	var lo := minf(r.size.x, r.size.y)
	var hi := maxf(r.size.x, r.size.y)
	var opts: Array = []  # [form, weight]
	match dist:
		"cbd":
			opts = [["pencil", 0.08], ["twin", 0.1], ["cantilever", 0.1], ["crown", 0.16], ["offset", 0.2]]
		"midtown":
			opts = [["pencil", 0.12], ["twin", 0.1], ["slab", 0.1], ["cantilever", 0.14], ["crown", 0.12],
				["offset", 0.18]]
		"waterfront":
			opts = [["slab", 0.18], ["pencil", 0.1], ["cantilever", 0.1], ["campanile", 0.06], ["offset", 0.16]]
		"docks":
			if h < 45.0:
				opts = [["silos", 0.24]]
			else:
				opts = [["cantilever", 0.2], ["slab", 0.15], ["twin", 0.1], ["offset", 0.15]]
		_:
			opts = [["campanile", 0.2 if h < 75.0 else 0.0], ["crown", 0.1], ["twin", 0.05], ["offset", 0.2]]
	var x := frng.randf()
	for o in opts:
		x -= float(o[1])
		if x < 0.0:
			var f: String = o[0]
			match f:
				"pencil":
					return f if h > 90.0 and lo > 26.0 else "box"
				"twin":
					return f if h > 80.0 and hi > 50.0 and lo > 24.0 else "box"
				"slab":
					return f if h > 50.0 and hi > 44.0 and lo > 26.0 else "box"
				"cantilever":
					return f if h > 50.0 and lo > 24.0 else "box"
				"crown":
					return f if h > 60.0 and lo > 24.0 else "box"
				"campanile":
					return f if lo > 22.0 else "box"
				"silos":
					return f if hi > 30.0 and lo > 14.0 else "box"
			return f
	return "box"


func _style_for(dist: String, h: float, form: String, brng: RandomNumberGenerator) -> int:
	if dist == "docks" and h < 45.0:
		return Style.WAREHOUSE
	if dist == "georgian" and h < 62.0:
		var g := brng.randf()
		return Style.BRICK if g < 0.6 else (Style.SANDSTONE if g < 0.8 else Style.STONE)
	if form in ["pencil", "twin", "cantilever"] and h > 70.0:
		return [Style.GLASS, Style.DARK_GLASS, Style.MODERN][brng.randi() % 3]
	if dist == "georgian" and h < 110.0:
		return [Style.STONE, Style.DECO, Style.SANDSTONE, Style.BRICK][brng.randi() % 4]
	if h > 115.0:
		return Style.GLASS if brng.randf() < 0.6 else Style.DARK_GLASS
	if h > 65.0:
		return [Style.MODERN, Style.DECO, Style.GLASS, Style.STONE][brng.randi() % 4]
	if h > 35.0:
		return [Style.STONE, Style.BRICK, Style.MODERN, Style.DECO][brng.randi() % 4]
	return [Style.BRICK, Style.STONE, Style.SANDSTONE][brng.randi() % 3]


func _make_building(r: Rect2, dist: String, brng: RandomNumberGenerator) -> void:
	var c := r.get_center()
	var h := _height_for(dist, c, brng)
	var frng := RandomNumberGenerator.new()
	frng.seed = hash(Vector2i(int(c.x * 8.0), int(c.y * 8.0))) ^ (seed * 7 + 3)
	var form := _form_for(dist, h, r, frng)
	if form == "silos":
		_silos(r, frng)
		return
	if form == "pencil":
		var side := clampf(minf(r.size.x, r.size.y) * 0.62, 17.0, 24.0)
		var px := frng.randf_range(r.position.x, r.end.x - side)
		var pz := frng.randf_range(r.position.y, r.end.y - side)
		r = Rect2(px, pz, side, side)
		h = minf(h * frng.randf_range(1.1, 1.25), 330.0)
	elif form == "slab":
		var thin := frng.randf_range(15.0, 19.0)
		if r.size.x > r.size.y:
			r = Rect2(r.position.x, r.get_center().y - thin * 0.5, r.size.x, thin)
		else:
			r = Rect2(r.get_center().x - thin * 0.5, r.position.y, thin, r.size.y)
	var style := _style_for(dist, h, form, brng)
	var cols: Array = STYLE_COLORS[style]
	var col: Color = cols[brng.randi() % cols.size()]
	col = col.lightened(brng.randf_range(-0.06, 0.06))
	var tiers: Array = []
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	var extra: Array = []      # more buildings standing on this one (twin towers, campanile)
	var blocked: Array = []    # roof areas they take (no roof furniture there)
	if form == "twin":
		var pod := frng.randf_range(14.0, 24.0)
		tiers.append([x0, z0, x1, z1, 0.0, pod])
		var along_x := r.size.x >= r.size.y
		var L := (r.size.x if along_x else r.size.y) * 0.38
		var ins := 2.5
		var h2 := h * frng.randf_range(0.74, 0.92)
		var towers: Array = []
		if along_x:
			towers = [[x0 + ins, z0 + ins, x0 + ins + L, z1 - ins], [x1 - ins - L, z0 + ins, x1 - ins, z1 - ins]]
		else:
			towers = [[x0 + ins, z0 + ins, x1 - ins, z0 + ins + L], [x0 + ins, z1 - ins - L, x1 - ins, z1 - ins]]
		for k in 2:
			var tw: Array = towers[k]
			var th: float = h if k == 0 else h2
			var tt: Array = [[tw[0], tw[1], tw[2], tw[3], pod, th]]
			if frng.randf() < 0.5 and minf(tw[2] - tw[0], tw[3] - tw[1]) > 16.0:
				var si := frng.randf_range(2.5, 4.0)
				tt[0][5] = th - frng.randf_range(10.0, 18.0)
				tt.append([tw[0] + si, tw[1] + si, tw[2] - si, tw[3] - si, tt[0][5], th])
			var tb := _building(tt, style, col, "normal")
			tb["seed"] = frng.randf()
			extra.append(tb)
			blocked.append(Rect2(tw[0] - 2.0, tw[1] - 2.0, tw[2] - tw[0] + 4.0, tw[3] - tw[1] + 4.0))
		# Sky bridge between the towers, two thirds of the way up the lower one.
		var by := pod + (h2 - pod) * frng.randf_range(0.55, 0.75)
		var a: Array = towers[0]
		var b2: Array = towers[1]
		if along_x:
			var zc := (z0 + z1) * 0.5
			extra.append(_building([[a[2] - 1.0, zc - 3.5, b2[0] + 1.0, zc + 3.5, by, by + 5.0]], Style.DARK_GLASS,
				Color(0.22, 0.26, 0.3), "bridge"))
		else:
			var xc := (x0 + x1) * 0.5
			extra.append(_building([[xc - 3.5, a[3] - 1.0, xc + 3.5, b2[1] + 1.0, by, by + 5.0]], Style.DARK_GLASS,
				Color(0.22, 0.26, 0.3), "bridge"))
	elif form == "cantilever":
		# A recessed body with the top block hanging out over it on one or
		# two sides (a covered gap to swing under, a strong silhouette).
		var top_h := frng.randf_range(14.0, 26.0)
		var body := [x0, z0, x1, z1]
		var sides := [0, 1, 2, 3]
		for k in range(3, 0, -1):  # (seeded shuffle: Array.shuffle() uses the global RNG)
			var j := frng.randi_range(0, k)
			var tmp: int = sides[k]
			sides[k] = sides[j]
			sides[j] = tmp
		for k in 1 + int(frng.randf() < 0.5):
			var o := frng.randf_range(3.5, 6.5)
			match sides[k]:
				0: body[0] += o
				1: body[1] += o
				2: body[2] -= o
				3: body[3] -= o
		var y_top := maxf(h - top_h, 24.0)
		tiers.append([body[0], body[1], body[2], body[3], 0.0, y_top])
		tiers.append([x0, z0, x1, z1, y_top, h])
	elif h > 70.0 and min(r.size.x, r.size.y) > 30.0 and (form == "offset" or brng.randf() < 0.7):
		# Podium + slimmer tower, then setbacks (stepped to one side for "offset").
		var dx := 0.0
		var dz := 0.0
		if form == "offset":
			dx = -1.0 if frng.randf() < 0.5 else 1.0
			dz = -1.0 if frng.randf() < 0.5 else 1.0
		var pod := brng.randf_range(12.0, 22.0)
		tiers.append([x0, z0, x1, z1, 0.0, pod])
		var inset := brng.randf_range(3.0, minf(r.size.x, r.size.y) * 0.22)
		x0 += inset * (1.0 + dx); z0 += inset * (1.0 + dz); x1 -= inset * (1.0 - dx); z1 -= inset * (1.0 - dz)
		var y := pod
		var steps := 1 + int(h > 110.0) + int(brng.randf() < 0.4)
		for s_ in steps:
			var top := y + (h - y) * (0.62 if s_ < steps - 1 else 1.0)
			if s_ == steps - 1:
				top = h
			tiers.append([x0, z0, x1, z1, y, top])
			y = top
			var si := brng.randf_range(2.5, 5.0)
			if x1 - x0 - si * 2.0 < 10.0 or z1 - z0 - si * 2.0 < 10.0:
				break
			x0 += si * (1.0 + dx); z0 += si * (1.0 + dz); x1 -= si * (1.0 - dx); z1 -= si * (1.0 - dz)
		if tiers[-1][5] < h:
			tiers[-1][5] = h
	else:
		tiers.append([x0, z0, x1, z1, 0.0, h])
		if form != "crown" and form != "campanile" and h > 40.0 and brng.randf() < 0.35 \
				and min(r.size.x, r.size.y) > 22.0:
			var si := brng.randf_range(3.0, 6.0)
			var top := h + brng.randf_range(6.0, 14.0)
			tiers.append([x0 + si, z0 + si, x1 - si, z1 - si, h, top])
	if form == "crown":
		# Replace the last tier's top with 3–5 stepped setbacks (deco crown).
		var last: Array = tiers[-1]
		var n := frng.randi_range(3, 5)
		var step_h := frng.randf_range(3.5, 5.5)
		var bottom: float = float(last[5]) - step_h * n
		if bottom > float(last[4]) + 8.0:
			last[5] = bottom
			var t := last.duplicate()
			for k in n:
				var si := frng.randf_range(1.8, 3.0)
				if float(t[2]) - float(t[0]) - si * 2.0 < 6.0 or float(t[3]) - float(t[1]) - si * 2.0 < 6.0:
					break
				t = [float(t[0]) + si, float(t[1]) + si, float(t[2]) - si, float(t[3]) - si, float(t[5]),
					float(t[5]) + step_h]
				tiers.append(t)
	if form == "campanile":
		# A slim bell/clock tower rising off one corner of the roof.
		var side := frng.randf_range(9.0, 12.0)
		var cx := x0 if frng.randf() < 0.5 else x1 - side
		var cz := z0 if frng.randf() < 0.5 else z1 - side
		var top: float = tiers[-1][5]
		var th := maxf(top + frng.randf_range(28.0, 48.0), frng.randf_range(78.0, 105.0))
		var tt: Array = [[cx, cz, cx + side, cz + side, top, th - 7.0],
			[cx + 1.6, cz + 1.6, cx + side - 1.6, cz + side - 1.6, th - 7.0, th]]
		var tb := _building(tt, Style.SANDSTONE if style == Style.BRICK else style, col.lightened(0.05), "normal")
		tb["seed"] = frng.randf()
		extra.append(tb)
		blocked.append(Rect2(cx - 3.0, cz - 3.0, side + 6.0, side + 6.0))
		# A slim spire on top: the highest anchor in its neighbourhood.
		var sp := 1.2
		var mx := cx + side * 0.5
		var mz := cz + side * 0.5
		extra.append(_building([[mx - sp, mz - sp, mx + sp, mz + sp, th + 0.5, th + frng.randf_range(9.0, 16.0)]],
			style, col.lightened(0.15), "spire"))
	var b := _building(tiers, style, col, "normal")
	b["seed"] = brng.randf()
	if not blocked.is_empty():
		b["roof_blocked"] = true  # (no rooftop spawns: towers stand on it)
	_add(b)
	for e in extra:
		_add(e)
	_roof_furniture(b, tiers, style, h, col, brng, blocked)
	for e in extra:
		if e["kind"] == "normal" and form == "twin":
			_roof_furniture(e, e["tiers"], style, float(e["tiers"][-1][5]), col, frng, [])


## Grain silos (docks): a row of tall concrete bins under a headhouse.
func _silos(r: Rect2, frng: RandomNumberGenerator) -> void:
	var along_x := r.size.x >= r.size.y
	var L := r.size.x if along_x else r.size.y
	var D := minf(r.size.x if not along_x else r.size.y, 13.0)
	var n := clampi(int(L / (D + 0.8)), 2, 6)
	var w := (L - 0.8 * (n - 1)) / n
	var h := frng.randf_range(46.0, 62.0)
	var concrete := Color(0.72, 0.7, 0.65).lightened(frng.randf_range(-0.08, 0.04))
	var c := r.get_center()
	for i in n:
		var a := (r.position.x if along_x else r.position.y) + i * (w + 0.8)
		var t: Array = [a, c.y - D * 0.5, a + w, c.y + D * 0.5, -6.0, h] if along_x \
			else [c.x - D * 0.5, a, c.x + D * 0.5, a + w, -6.0, h]  # (footed below the street: slopes)
		var bin := _building([t], Style.MODERN, concrete, "plain")
		bin["lift_at"] = c
		_add(bin)
	# Headhouse over the bins (solid, flat roof you can land on), a gallery
	# on its long side.
	var hh := frng.randf_range(7.0, 11.0)
	var hl := L * frng.randf_range(0.35, 0.6)
	var h0 := (r.position.x if along_x else r.position.y) + frng.randf_range(0.0, L - hl)
	var ht: Array = [h0, c.y - D * 0.5 - 0.5, h0 + hl, c.y + D * 0.5 + 0.5, h, h + hh] if along_x \
		else [c.x - D * 0.5 - 0.5, h0, c.x + D * 0.5 + 0.5, h0 + hl, h, h + hh]
	var head := _building([ht], Style.WAREHOUSE, Color(0.5, 0.27, 0.2), "plain")
	head["lift_at"] = c
	_add(head)
	# Conveyor gallery from the headhouse down the length of the row.
	var gt: Array = [r.position.x, c.y - 1.6, r.end.x, c.y + 1.6, h, h + 3.0] if along_x \
		else [c.x - 1.6, r.position.y, c.x + 1.6, r.end.y, h, h + 3.0]
	var gal := _building([gt], Style.MODERN, Color(0.45, 0.46, 0.47), "plain")
	gal["lift_at"] = c
	_add(gal)


func _roof_furniture(b: Dictionary, tiers: Array, style: int, h: float, col: Color, brng: RandomNumberGenerator,
		blocked: Array) -> void:
	var free := func(x: float, z: float) -> bool:
		for q in blocked:
			if (q as Rect2).has_point(Vector2(x, z)):
				return false
		return true
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
		if free.call(hx, hz):
			var yaw := 0.0 if sz < 0.0 else PI  # door faces into the roof
			props.append(["roof_hut", Transform3D(Basis(Vector3.UP, yaw), Vector3(hx, ry, hz))])
			buildings.append({"tiers": [[hx - 1.7, hz - 2.1, hx + 1.7, hz + 2.1, ry, ry + 3.1]], "style": Style.MODERN,
				"color": Color.WHITE, "kind": "structure", "seed": 0.0})
	if (style == Style.BRICK or style == Style.STONE or style == Style.SANDSTONE) and h < 80.0 and brng.randf() < 0.55:
		var wx := rx + brng.randf_range(-tw, tw) * 0.25
		var wz := rz + brng.randf_range(-td, td) * 0.25
		if free.call(wx, wz):
			props.append(["water_tower", Transform3D(Basis(Vector3.UP, brng.randf_range(0, TAU)), Vector3(wx, ry, wz))])
	if h > 235.0 and tw > 16.0 and td > 16.0:
		# Supertall crown: a slim spire, the highest anchor in the city.
		var sp := brng.randf_range(2.5, 3.5)
		_add(_building([[rx - sp, rz - sp, rx + sp, rz + sp, ry, ry + brng.randf_range(28.0, 48.0)]], style,
			col.lightened(0.15), "spire"))
	elif h > 100.0 and brng.randf() < 0.55 and free.call(rx, rz):
		props.append(["antenna", Transform3D(Basis(), Vector3(rx, ry, rz))])
	if h > 14.0 and h < 75.0 and tiers.size() == 1 and minf(tw, td) > 16.0 and blocked.is_empty() \
			and brng.randf() < 0.16:
		_billboard(tiers[0], ry, brng)
	for i in brng.randi_range(0, 3):
		if tw > 10.0 and td > 10.0:
			var ax := rx + brng.randf_range(-tw, tw) * 0.32
			var az := rz + brng.randf_range(-td, td) * 0.32
			if free.call(ax, az):
				props.append(["ac_unit", Transform3D(Basis(Vector3.UP, (brng.randi() % 2) * PI * 0.5),
					Vector3(ax, ry, az))])


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
		var snap := _snap()
		_site(entry)
		# Rigid (the crane's collision must stay with the crane), on the lot's
		# highest street corner; the frame's foot reaches down the slope.
		var lot: Rect2 = entry[0]
		var hi := -INF
		var lo := INF
		for c in [lot.position, lot.end, Vector2(lot.end.x, lot.position.y), Vector2(lot.position.x, lot.end.y)]:
			hi = maxf(hi, terrain.road_y(c.x, c.y))
			lo = minf(lo, terrain.road_y(c.x, c.y))
		_lift(snap, hi)
		for i in range(snap[0], buildings.size()):
			buildings[i]["foot"] = lo


## One construction site (frame, core, crane), built at street level 0.
func _site(entry: Array) -> void:
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
			var a := Vector3(xs[0] + hx, 0.0, zs[0] - hz)
			var b := Vector3(xs[0] - hx, 0.0, zs[0] + hz)
			a.y = ground_y(a.x, a.z)
			b.y = ground_y(b.x, b.z)
			if not is_nan(terrain.deck_y(xs[0], zs[0])):
				continue  # (no lights under the causeway)
			if not is_water(a) and not _in_park(a):
				props.append(["traffic_light", Transform3D(Basis(Vector3.UP, PI), a)])
			if not is_water(b) and not _in_park(b):
				props.append(["traffic_light", Transform3D(Basis(), b)])


## The Valley Causeway: the avenue nearest x = 715 carried across the rail
## valley on a road deck from the north rim junction to the south bank, at
## street level at both ends. The valley streets pass under it and the
## railway over it – three levels at one crossing.
func _causeway() -> void:
	var st: Array = x_streets[0]
	for s in x_streets:
		if absf(float(s[0]) - 715.0) < absf(float(st[0]) - 715.0):
			st = s
	var x: float = st[0]
	var half: float = float(st[1]) * 0.5 - 4.0  # deck: the carriageway, pavements stay below
	var zn: Array = z_streets[0]
	var zsth: Array = z_streets[-1]
	for s in z_streets:
		if absf(float(s[0]) - 171.0) < absf(float(zn[0]) - 171.0):
			zn = s
		if absf(float(s[0]) - 581.0) < absf(float(zsth[0]) - 581.0):
			zsth = s
	var za: float = float(zn[0]) + float(zn[1]) * 0.5
	var zb: float = float(zsth[0]) - float(zsth[1]) * 0.5
	var ya := terrain.road_y(x, za)
	var yb := terrain.road_y(x, zb)
	terrain.decks.append({"x": x, "half": half, "za": za, "zb": zb, "ya": ya, "yb": yb})
	var k := _kit("causeway")
	var concrete := Color(0.62, 0.6, 0.56)
	var dark := Color(0.38, 0.37, 0.36)
	var at := func(z: float) -> float: return lerpf(ya, yb, (z - za) / (zb - za))
	# Deck in spans between piers; parapets; piers mid-block (clear of the
	# valley streets crossing underneath).
	var piers: Array[float] = [za]
	for j in z_streets.size() - 1:
		var mid: float = (float(z_streets[j][0]) + float(z_streets[j + 1][0])) * 0.5
		if mid > za + 20.0 and mid < zb - 20.0:
			piers.append(mid)
	piers.append(zb)
	const T := 1.1  # deck thickness
	for i in piers.size() - 1:
		var a := Vector3(x, at.call(piers[i]) - T * 0.5, piers[i])
		var b := Vector3(x, at.call(piers[i + 1]) - T * 0.5, piers[i + 1])
		_kbeam(k, a, b, half * 2.0, T, concrete)
		for sd in [-1.0, 1.0]:
			var off := Vector3(sd * (half - 0.2), T * 0.5 + 0.55, 0.0)
			_kbeam(k, a + off, b + off, 0.4, 1.1, dark)
			# Edge girders under the deck, so the underside reads as a bridge.
			var g := Vector3(sd * (half - 1.2), -T * 0.5 - 0.5, 0.0)
			_kbeam(k, a + g, b + g, 0.8, 1.0, dark)
		_anchor(a + Vector3(-half, T * 0.5 + 1.1, 0), b + Vector3(-half, T * 0.5 + 1.1, 0))
		_anchor(a + Vector3(half, T * 0.5 + 1.1, 0), b + Vector3(half, T * 0.5 + 1.1, 0))
	for i in range(1, piers.size() - 1):
		var z := piers[i]
		var top: float = at.call(z) - T - 1.0
		for sd in [-1.0, 1.0]:
			var px: float = x + sd * (half - 2.5)
			var gy := terrain.road_y(px, z)
			if top - gy > 1.0:
				_ksolid(k, px - 0.9, z - 0.9, px + 0.9, z + 0.9, gy - 0.3, top, concrete)
		_ksolid(k, x - half + 1.0, z - 1.0, x + half - 1.0, z + 1.0, top - 1.0, top + 0.05, concrete)


func _in_park(p: Vector3) -> bool:
	for r in parks:
		if (r as Rect2).grow(2.0).has_point(Vector2(p.x, p.z)):
			return true
	return false


func _land() -> void:
	var rects: Array = [island]
	for w in water:
		if w.position.x < 0.0 or w in sea:
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
