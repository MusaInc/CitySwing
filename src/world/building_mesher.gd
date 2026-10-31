class_name BuildingMesher
extends RefCounted
## Turns CityLayout building specs into merged mesh arrays (one surface per
## chunk per LOD) for building.gdshader. Pure data in, Mesh arrays out, so it
## can run on a worker thread or in the offline bake.
## Winding: Godot treats clockwise triangles as front faces.

const KIND_WALL := 0.0
const KIND_TRIM := 1.0
const KIND_ROOF := 2.0
const KIND_GLASS := 3.0
const KIND_SIGN := 4.0
const ROOF_COLOR := Color(0.40, 0.40, 0.41)
## Roof finishes picked per building: gravel, tar, pale concrete, rust, green.
const ROOF_COLORS := [Color(0.40, 0.40, 0.41), Color(0.24, 0.25, 0.27), Color(0.6, 0.59, 0.56),
	Color(0.45, 0.33, 0.28), Color(0.36, 0.44, 0.3)]
const CRANE_YELLOW := Color(0.93, 0.68, 0.12)
const STEEL := Color(0.22, 0.23, 0.25)
const CONCRETE := Color(0.6, 0.59, 0.56)
const BRIDGE_RED := Color(0.66, 0.17, 0.12)
## Shop awnings at street level (brand-friendly, slightly muted).
const AWNING_COLORS := [Color(0.72, 0.16, 0.14), Color(0.13, 0.36, 0.3), Color(0.15, 0.22, 0.42),
	Color(0.85, 0.62, 0.18), Color(0.86, 0.82, 0.72), Color(0.42, 0.18, 0.36)]
const LEDGE_EVERY := 14.4   # m: a stone ledge every four floors on masonry facades
const KERB := 0.15        # m: pavement blocks stand this far above the road
const PARAPET := 0.3       # m: roof-edge lip; under Player.STEP_MAX, so a run steps onto it
const PARAPET_T := 0.3     # m: its thickness
const LEDGE_OUT := 0.08    # m: stone courses stand this far proud of the wall (visual only)
const PLINTH_OUT := 0.15   # m: ground-floor plinth band
const PLINTH_H := 0.9
const AWNING_Y := 3.25
const AWNING_OUT := 1.3
const IRON := [Color(0.11, 0.12, 0.12), Color(0.1, 0.16, 0.13), Color(0.3, 0.12, 0.09)]
const ESCAPE_DEPTH := 1.35   # m: fire-escape platforms stand this far out
const FIN_OUT := 0.24        # m: glass-tower fins
## Outskirt backdrop blocks opt out of features (drawn plain, collide plain).
const NO_FEATURES := {"draw": [], "beams": [], "col": []}

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var indices := PackedInt32Array()


func is_empty() -> bool:
	return verts.is_empty()


func arrays() -> Array:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = normals
	a[Mesh.ARRAY_COLOR] = colors
	a[Mesh.ARRAY_TEX_UV] = uvs
	a[Mesh.ARRAY_TEX_UV2] = uv2s
	a[Mesh.ARRAY_INDEX] = indices
	return a


## Quad from four corners given clockwise as seen from the front.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua: Vector2, ub: Vector2,
		uc: Vector2, ud: Vector2, col: Color, kind: float, style: float, seed: float) -> void:
	var i := verts.size()
	verts.append_array([a, b, c, d])
	normals.append_array([n, n, n, n])
	var cc := Color(col.r, col.g, col.b, kind / 8.0)
	colors.append_array([cc, cc, cc, cc])
	uvs.append_array([ua, ub, uc, ud])
	var s2 := Vector2(style, seed)
	uv2s.append_array([s2, s2, s2, s2])
	indices.append_array([i, i + 1, i + 2, i, i + 2, i + 3])


## Four outward walls of an axis-aligned box, UV u running round the perimeter.
func walls(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, col: Color,
		kind: float, style: float, seed: float, uv_y0 := -1.0) -> void:
	var vy0 := y0 if uv_y0 < 0.0 else uv_y0
	var vy1 := vy0 + (y1 - y0)
	var corners := [Vector2(x0, z1), Vector2(x1, z1), Vector2(x1, z0), Vector2(x0, z0)]
	var ns := [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]
	var u := 0.0
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var w := a.distance_to(b)
		quad(Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(b.x, y0, b.y), Vector3(a.x, y0, a.y), ns[k],
			Vector2(u, vy1), Vector2(u + w, vy1), Vector2(u + w, vy0), Vector2(u, vy0), col, kind, style, seed)
		_face_span(w, style, seed)
		u += w


## Tells the shader where a wall face's corners are, for corner quoins and
## edge shading: UV2.x = style + 0..1 across the face, UV2.y = width (¼ m
## steps) + seed. Quads without it (roofs, undersides) read as width 0.
func _face_span(w: float, style: float, seed: float) -> void:
	var n := uv2s.size()
	# Seed in 1/256 steps, centred, so interpolation noise can't change it.
	var wy := floorf(w * 4.0) + (floorf(seed * 256.0) + 0.5) / 256.0
	uv2s[n - 4] = Vector2(style, wy)
	uv2s[n - 3] = Vector2(style + 0.999, wy)
	uv2s[n - 2] = Vector2(style + 0.999, wy)
	uv2s[n - 1] = Vector2(style, wy)


func top(x0: float, z0: float, x1: float, z1: float, y: float, col: Color, kind: float, style: float, seed: float) -> void:
	quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP,
		Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1), col, kind, style, seed)


func bottom(x0: float, z0: float, x1: float, z1: float, y: float, col: Color, kind: float, style: float, seed: float) -> void:
	quad(Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), Vector3(x0, y, z0), Vector3.DOWN,
		Vector2(x0, z1), Vector2(x1, z1), Vector2(x1, z0), Vector2(x0, z0), col, kind, style, seed)


## The frame beam() builds a box in: x across (w), y up-ish (h), z along
## (negated, so the basis is right-handed for collision shapes).
static func beam_basis(a: Vector3, b: Vector3) -> Basis:
	var f := (b - a).normalized()
	var up := Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT
	var s := f.cross(up).normalized()
	var u := s.cross(f).normalized()
	return Basis(s, u, -f)


## Box of cross-section w x h from a to b (any direction), four sides + caps.
func beam(a: Vector3, b: Vector3, w: float, h: float, col: Color, kind := KIND_TRIM, caps := false) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var f := d / length
	var up := Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT
	var s := f.cross(up).normalized()
	var u := s.cross(f).normalized()
	var hs := s * w * 0.5
	var hu := u * h * 0.5
	var sides := [[hu, s], [hs, -u], [-hu, -s], [-hs, u]]
	for k in 4:
		var c0: Vector3 = sides[k][0]
		var c1: Vector3 = sides[(k + 1) % 4][0]
		var p0 := c0 + c1
		var p1 := c0 - c1
		var n: Vector3 = (c0).normalized()
		# Pick the winding that faces outward (clockwise seen from outside).
		var qa := a + p0
		var qb := b + p0
		var qc := b + p1
		var qd := a + p1
		if (qb - qa).cross(qc - qa).dot(n) > 0.0:
			quad(qa, qd, qc, qb, n, Vector2.ZERO, Vector2(0, length), Vector2(w, length), Vector2(w, 0), col, kind, 0, 0)
		else:
			quad(qa, qb, qc, qd, n, Vector2.ZERO, Vector2(0, length), Vector2(w, length), Vector2(w, 0), col, kind, 0, 0)
	if caps:
		for e in [[b, f], [a, -f]]:
			var o: Vector3 = e[0]
			var n2: Vector3 = e[1]
			var v := [o + hs + hu, o - hs + hu, o - hs - hu, o + hs - hu]
			if (v[1] - v[0]).cross(v[2] - v[0]).dot(n2) > 0.0:
				v.reverse()
			quad(v[0], v[1], v[2], v[3], n2, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col, kind, 0, 0)


## Solid axis-aligned box (walls, top, bottom) in one flat colour.
func solid(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, col: Color, kind := KIND_TRIM) -> void:
	walls(x0, z0, x1, z1, y0, y1, col, kind, 0, 0)
	top(x0, z0, x1, z1, y1, col, kind, 0, 0)
	bottom(x0, z0, x1, z1, y0, col.darkened(0.25), kind, 0, 0)


## Square lattice mast (4 chords, zig-zag bracing on every face).
func lattice(base: Vector3, height: float, size: float, col: Color, section := 4.0, detailed := true) -> void:
	var hs := size * 0.5
	var cs := [Vector3(-hs, 0, -hs), Vector3(hs, 0, -hs), Vector3(hs, 0, hs), Vector3(-hs, 0, hs)]
	if not detailed:
		solid(base.x - hs, base.z - hs, base.x + hs, base.z + hs, base.y, base.y + height, col)
		return
	for c in cs:
		beam(base + c, base + c + Vector3.UP * height, 0.45, 0.45, col)
	var n := maxi(1, int(height / section))
	var step := height / n
	for i in n:
		var y0 := base.y + i * step
		for k in 4:
			var a: Vector3 = cs[k]
			var b: Vector3 = cs[(k + 1) % 4]
			var p0 := Vector3(base.x, y0, base.z) + (a if i % 2 == 0 else b)
			var p1 := Vector3(base.x, y0 + step, base.z) + (b if i % 2 == 0 else a)
			beam(p0, p1, 0.22, 0.22, col)


## Triangular lattice girder from a to b (a jib or boom), apex on top.
func girder(a: Vector3, b: Vector3, width: float, depth: float, col: Color, detailed := true) -> void:
	var d := b - a
	var length := d.length()
	var f := d / length
	var s := f.cross(Vector3.UP).normalized() * width * 0.5
	var up := Vector3.UP * depth
	if not detailed:
		beam(a + up * 0.5, b + up * 0.5, width, depth, col, KIND_TRIM, true)
		return
	var chords := [a - s, a + s, a + up]
	for c in chords:
		beam(c, c + d, 0.4, 0.4, col)
	var n := maxi(1, int(length / 3.0))
	for i in n:
		var p := a + f * (length * i / n)
		var q := a + f * (length * (i + 1) / n)
		beam(p - s, q + up, 0.14, 0.14, col)
		beam(p + s, q + up, 0.14, 0.14, col)
		beam(q - s, q + s, 0.14, 0.14, col)


static func trim_color(b: Dictionary) -> Color:
	var c: Color = b["color"]
	match int(b["style"]):
		CityLayout.Style.GLASS, CityLayout.Style.DARK_GLASS:
			return Color(0.62, 0.66, 0.68)
		CityLayout.Style.BRICK, CityLayout.Style.WAREHOUSE:
			return Color(0.86, 0.82, 0.74)
		_:
			return c.lightened(0.12)


## Detailed LOD: walls, cornice slabs with undersides, parapet roof.
func add_building(b: Dictionary, detailed: bool) -> void:
	match b["kind"]:
		"invisible", "structure":
			return
		"sign":
			_add_sign(b, detailed)
			return
		"frame":
			_add_frame(b, detailed)
			return
		"plain":
			for t in b["tiers"]:
				solid(t[0], t[1], t[2], t[3], t[4], t[5], b["color"])
			return
	var style := float(b["style"])
	var seed: float = b["seed"]
	var col: Color = b["color"]
	var glassy := style == CityLayout.Style.GLASS or style == CityLayout.Style.DARK_GLASS
	var wall_kind := KIND_GLASS if glassy else KIND_WALL
	var trim := trim_color(b)
	var roof: Color = ROOF_COLORS[int(seed * 997.0) % ROOF_COLORS.size()]
	if roof == ROOF_COLORS[4] and tiers_top(b) > 60.0:
		roof = ROOF_COLORS[0]  # green roofs on low buildings only
	var tiers: Array = b["tiers"]
	var base := base_of(b)
	var bc := base_course(b)
	if bc.has_volume():
		# On a slope the lot is level at its uphill corner; down the hill the
		# building stands on a dressed-stone base course to the street.
		var stone := Color(0.56, 0.53, 0.48) if _glassy(b) else trim.darkened(0.18)
		solid(bc.position.x, bc.position.z, bc.end.x, bc.end.z, bc.position.y, bc.end.y, stone, KIND_WALL)
	for i in tiers.size():
		var t: Array = tiers[i]
		var x0: float = t[0]
		var z0: float = t[1]
		var x1: float = t[2]
		var z1: float = t[3]
		var y0: float = t[4]
		var y1: float = t[5]
		walls(x0, z0, x1, z1, y0, y1, col, wall_kind, style, seed, y0 - base)
		if b["kind"] == "bridge":
			bottom(x0, z0, x1, z1, y0, trim, KIND_TRIM, style, seed)
		if detailed:
			var o := cornice_out(b)
			var ch := cornice_h(b)
			walls(x0 - o, z0 - o, x1 + o, z1 + o, y1 - ch * 0.5, y1 + ch * 0.5, trim, KIND_TRIM, style, seed)
			bottom(x0 - o, z0 - o, x1 + o, z1 + o, y1 - ch * 0.5, trim, KIND_TRIM, style, seed)
			top(x0 - o, z0 - o, x1 + o, z1 + o, y1 + ch * 0.5, roof, KIND_ROOF, style, seed)
			if b["kind"] != "bridge":
				_parapet(x0 - o, z0 - o, x1 + o, z1 + o, y1 + ch * 0.5, trim)
				if not glassy:
					_ledges(x0, z0, x1, z1, y0, y1, trim, style, seed, base)
			# Ground-floor plinth band on the base tier.
			if _has_plinth(b, i):
				var po := PLINTH_OUT
				var ph := base + PLINTH_H
				walls(x0 - po, z0 - po, x1 + po, z1 + po, base, ph, col.darkened(0.3), KIND_TRIM, style, seed)
				top(x0 - po, z0 - po, x1 + po, z0, ph, col.darkened(0.3), KIND_TRIM, style, seed)
				top(x0 - po, z1, x1 + po, z1 + po, ph, col.darkened(0.3), KIND_TRIM, style, seed)
				top(x0 - po, z0, x0, z1, ph, col.darkened(0.3), KIND_TRIM, style, seed)
				top(x1, z0, x1 + po, z1, ph, col.darkened(0.3), KIND_TRIM, style, seed)
				for aw in awning_runs(b):
					_awning(aw[0], aw[1], aw[2], aw[3], (aw[3] as Color).darkened(0.15))
		else:
			top(x0, z0, x1, z1, y1, roof, KIND_ROOF, style, seed)


## Architectural features (features()) as their own mesh: CityWorld draws it
## over a shorter range than the detailed LOD, since it is small detail.
## Fins only need their two sides and face (6 triangles, not 12).
func add_features(b: Dictionary) -> void:
	var f := features(b)
	for d in f["draw"]:
		var bx: AABB = d[0]
		if d.size() > 2 and d[2] is String:
			continue  # skyline pieces: drawn with the building (add_skyline)
		if d.size() > 2 and d[2] is Vector3:
			_fin(bx, d[2], d[1])
		else:
			solid(bx.position.x, bx.position.z, bx.end.x, bx.end.z, bx.position.y, bx.end.y, d[1])
	for bm in f["beams"]:
		beam(bm[0], bm[1], bm[2], bm[3], bm[4])


## Feature pieces that shape the skyline (glass crowns): part of the building
## mesh at every LOD, not the short-range feature mesh.
func add_skyline(b: Dictionary) -> void:
	if b["kind"] != "normal":
		return
	for d in features(b)["draw"]:
		if d.size() > 2 and d[2] is String:
			var bx: AABB = d[0]
			solid(bx.position.x, bx.position.z, bx.end.x, bx.end.z, bx.position.y, bx.end.y, d[1])


## A thin vertical fin standing out of a wall along `out`: face + two sides.
func _fin(bx: AABB, out: Vector3, col: Color) -> void:
	var y0 := bx.position.y
	var y1 := bx.end.y
	var lo := bx.position
	var hi := bx.end
	var c := bx.get_center()
	var side := Vector3(out.z, 0, -out.x).abs()  # along the wall
	var hw := (side * bx.size).length() * 0.5
	var depth := (out.abs() * bx.size).length()
	var base := c - out * depth * 0.5  # on the wall plane
	var tip := c + out * depth * 0.5
	var s := Vector3(out.z, 0, -out.x)  # wall tangent (right of `out`)
	var a := tip - s * hw
	var e := tip + s * hw
	_vquad(a, e, y0, y1, out, col)
	_vquad(e, base + s * hw, y0, y1, s, col.darkened(0.12))
	_vquad(base - s * hw, a, y0, y1, -s, col.darkened(0.12))


## Vertical quad from a to b (seen with `n` toward the viewer), y0..y1.
func _vquad(a: Vector3, b: Vector3, y0: float, y1: float, n: Vector3, col: Color) -> void:
	var p := [Vector3(a.x, y1, a.z), Vector3(b.x, y1, b.z), Vector3(b.x, y0, b.z), Vector3(a.x, y0, a.z)]
	if (p[1] - p[0]).cross(p[2] - p[0]).dot(n) > 0.0:
		p.reverse()
	quad(p[0], p[1], p[2], p[3], n, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col, KIND_TRIM, 0, 0)


## Cornice: how far the roof slab overhangs the walls, and its depth (it
## straddles the tier top, so the roof surface is half of it above t[5]).
static func cornice_out(b: Dictionary) -> float:
	return 0.25 if _glassy(b) else 0.3


static func cornice_h(b: Dictionary) -> float:
	return 0.6 if _glassy(b) else 1.0


## Where a building stands: its block's terrace (0 on flat ground). Tiers,
## roofs and features are absolute; facade bands (shopfronts, ledges, plinth,
## awnings) are measured from here.
static func base_of(b: Dictionary) -> float:
	return float(b.get("base", 0.0))


## The stone base a building stands on down a slope: from its lowest street
## corner (b["foot"]) up to its lot level, a little proud of the walls.
## Empty when the lot is level.
static func base_course(b: Dictionary) -> AABB:
	var foot: float = b.get("foot", base_of(b))
	var base := base_of(b)
	if base - foot < 0.05 or b["kind"] not in ["normal", "landmark", "frame"]:
		return AABB()
	var t: Array = b["tiers"][0]
	var o := PLINTH_OUT + 0.05
	return _aabb(t[0] - o, t[1] - o, t[2] + o, t[3] + o, foot - 0.3, base + CityTerrain.KERB)


static func _on_ground(b: Dictionary, t: Array) -> bool:
	return absf(float(t[4]) - base_of(b)) < 0.01


static func _glassy(b: Dictionary) -> bool:
	return int(b["style"]) == CityLayout.Style.GLASS or int(b["style"]) == CityLayout.Style.DARK_GLASS


static func _parapeted(b: Dictionary) -> bool:
	return b["kind"] in ["normal", "landmark", "spire"]


static func _has_plinth(b: Dictionary, tier: int) -> bool:
	return tier == 0 and _on_ground(b, b["tiers"][0]) and not _glassy(b) and b["kind"] != "bridge"


## Height of the walkable roof of the top tier as drawn in the detailed LOD
## (props stand on it, collision matches it).
static func roof_y(b: Dictionary) -> float:
	var top: float = b["tiers"][-1][5]
	if _parapeted(b) or b["kind"] == "bridge":
		return top + cornice_h(b) * 0.5
	return top


## The solid boxes of a building exactly as the detailed LOD draws it:
## walls, the cornice/roof slab with its overhang, the parapet ring, the
## ground-floor plinth and shop awnings; construction frames with their
## columns, hoarding and edge barrier. Collision is built from this, so what
## you see is what you stand on and bump into.
static func collision_boxes(b: Dictionary) -> Array[AABB]:
	var out: Array[AABB] = []
	var kind: String = b["kind"]
	var tiers: Array = b["tiers"]
	match kind:
		"invisible":
			return out  # stand-ins for landmark models, which collide with their own mesh
		"structure", "sign", "plain":
			for t in tiers:
				out.append(_aabb(t[0], t[1], t[2], t[3], t[4], t[5]))
			if kind == "sign":
				_sign_boxes(b, out)
			return out
		"frame":
			if base_course(b).has_volume():
				out.append(base_course(b))
			for t in tiers:
				out.append(_aabb(t[0], t[1], t[2], t[3], t[4], t[5]))
			var t0: Array = tiers[0]
			var ytop: float = tiers[-1][5]
			var base: float = b.get("base", 0.0)
			var nx := maxi(2, int((t0[2] - t0[0]) / 8.0) + 1)
			var nz := maxi(2, int((t0[3] - t0[1]) / 8.0) + 1)
			for i in nx:
				for j in nz:
					if i != 0 and i != nx - 1 and j != 0 and j != nz - 1:
						continue
					var x: float = lerpf(t0[0] + 0.5, t0[2] - 0.5, i / float(nx - 1))
					var z: float = lerpf(t0[1] + 0.5, t0[3] - 0.5, j / float(nz - 1))
					out.append(_aabb(x - 0.3, z - 0.3, x + 0.3, z + 0.3, base, ytop + 3.0))
			_ring(out, t0[0] - 1.5, t0[1] - 1.5, t0[2] + 1.5, t0[3] + 1.5, base, base + 2.6, 0.12)
			_ring(out, t0[0] - 0.2, t0[1] - 0.2, t0[2] + 0.2, t0[3] + 0.2, ytop + 0.1, ytop + 1.2, 0.12)
			return out
	var o := cornice_out(b)
	var ch := cornice_h(b)
	var bc := base_course(b)
	if bc.has_volume():
		out.append(bc)
	for i in tiers.size():
		var t: Array = tiers[i]
		var y1: float = t[5]
		out.append(_aabb(t[0], t[1], t[2], t[3], t[4], y1 - ch * 0.5))
		out.append(_aabb(t[0] - o, t[1] - o, t[2] + o, t[3] + o, y1 - ch * 0.5, y1 + ch * 0.5))
		if kind != "bridge":
			_ring(out, t[0] - o, t[1] - o, t[2] + o, t[3] + o, y1 + ch * 0.5, y1 + ch * 0.5 + PARAPET, PARAPET_T)
		if _has_plinth(b, i):
			out.append(_aabb(t[0] - PLINTH_OUT, t[1] - PLINTH_OUT, t[2] + PLINTH_OUT, t[3] + PLINTH_OUT, base_of(b),
				base_of(b) + PLINTH_H))
	for aw in awning_runs(b):
		var a: Vector3 = aw[0]
		var e: Vector3 = aw[1]
		var far: Vector3 = e + (aw[2] as Vector3)
		var ay: float = a.y  # awning_runs gives absolute points
		var lo := Vector3(minf(a.x, far.x), ay - 0.38, minf(a.z, far.z))
		var hi := Vector3(maxf(a.x, far.x), ay + 0.18, maxf(a.z, far.z))
		out.append(AABB(lo, hi - lo))
	out.append_array(features(b)["col"])
	return out


# ------------------------------------------------------------ features
## A wall face of a tier in the order walls() draws them (k = 0 +z, 1 +x,
## 2 −z, 3 −x): [origin at the left end, along, outward, length, u at origin]
## (u = the shader's metres round the building, so features can line up with
## its window columns and shop bays).
static func _face(t: Array, k: int) -> Array:
	var w: float = t[2] - t[0]
	var d: float = t[3] - t[1]
	match k:
		0: return [Vector3(t[0], 0, t[3]), Vector3.RIGHT, Vector3.BACK, w, 0.0]
		1: return [Vector3(t[2], 0, t[3]), Vector3.FORWARD, Vector3.RIGHT, d, w]
		2: return [Vector3(t[2], 0, t[1]), Vector3.LEFT, Vector3.FORWARD, w, w + d]
	return [Vector3(t[0], 0, t[1]), Vector3.BACK, Vector3.LEFT, d, w * 2.0 + d]


## World box from face-local ranges: along a0..a1, out o0..o1, height y0..y1.
static func _fbox(f: Array, a0: float, a1: float, o0: float, o1: float, y0: float, y1: float) -> AABB:
	var org: Vector3 = f[0]
	var p: Vector3 = org + (f[1] as Vector3) * a0 + (f[2] as Vector3) * o0
	var q: Vector3 = org + (f[1] as Vector3) * a1 + (f[2] as Vector3) * o1
	var lo := Vector3(minf(p.x, q.x), y0, minf(p.z, q.z))
	var hi := Vector3(maxf(p.x, q.x), y1, maxf(p.z, q.z))
	return AABB(lo, hi - lo)


static func _fpt(f: Array, a: float, o: float, y: float) -> Vector3:
	return (f[0] as Vector3) + (f[1] as Vector3) * a + (f[2] as Vector3) * o + Vector3(0, y, 0)


## Architectural features of a building, decided from its seed (so the mesher
## and the collision agree without storing anything): fire escapes, entrance
## portals and canopies, glass fins, chimneys and crowns.
##   draw: [[AABB, Color]] solid boxes   beams: [[a, b, w, h, Color]]
##   col:  [AABB] what you stand on / bump into (covers draw and beams)
static func features(b: Dictionary) -> Dictionary:
	if b.has("_features"):
		return b["_features"]
	var out := _features(b)
	b["_features"] = out  # (the mesher, awnings and collision all ask)
	return out


static func _features(b: Dictionary) -> Dictionary:
	var out := {"draw": [], "beams": [], "col": []}
	if not _parapeted(b) or b["kind"] != "normal":
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(b["seed"]) * 7919.0 * 1000.0) ^ 0x5f3
	var style := int(b["style"])
	var t0: Array = b["tiers"][0]
	var col: Color = b["color"]
	var trim := trim_color(b)
	var single := (b["tiers"] as Array).size() == 1
	var base := base_of(b)
	var h0: float = float(t0[5]) - base  # storeys above the terrace
	# Fire escapes: brick flats and warehouses, 2nd floor to the top floor.
	if style in [CityLayout.Style.BRICK, CityLayout.Style.WAREHOUSE] and _on_ground(b, t0) \
			and h0 > 13.0 and h0 < 75.0 and rng.randf() < 0.7:
		var n := 1 + int(rng.randf() < 0.35)
		var iron: Color = IRON[rng.randi() % IRON.size()]
		var first := rng.randi() % 4
		for i in n:
			var k := (first + i * 2) % 4
			_fire_escape(out, _face(t0, k), style, h0, iron, rng, base)
	# Entrances: a stone portal on masonry, a steel canopy on modern/glass.
	if _on_ground(b, t0) and h0 > 24.0 and style != CityLayout.Style.WAREHOUSE:
		var k := 0
		var best := 0.0
		for kk in 4:
			var L: float = _face(t0, kk)[3]
			if L > best + 0.5:
				best = L
				k = kk
		if best > 18.0:
			var part := {"draw": [], "beams": [], "col": []}
			_portal(part, _face(t0, k), style, col, trim, rng)
			_raise_into(out, part, base)
	# Fins up the glass towers (a vertical rhythm the shader alone can't give).
	if _glassy(b) and rng.randf() < 0.6:
		var fin_col := trim.darkened(rng.randf_range(0.0, 0.5))
		for t in b["tiers"]:
			if float(t[5]) - float(t[4]) < 24.0:
				continue
			var y0: float = maxf(float(t[4]), base + 4.6)
			var y1: float = float(t[5]) - cornice_h(b) * 0.5
			for k in 4:
				var f := _face(t, k)
				var L: float = f[3]
				var u0: float = f[4]
				var m := ceili((u0 + 0.9) / 3.2)
				while m * 3.2 - u0 < L - 0.9:
					var a := m * 3.2 - u0
					out["draw"].append([_fbox(f, a - 0.07, a + 0.07, 0.0, FIN_OUT, y0, y1), fin_col, f[2]])
					m += 1
			out["col"].append(_aabb(t[0] - FIN_OUT, t[1] - FIN_OUT, t[2] + FIN_OUT, t[3] + FIN_OUT, y0, y1))
	var tt: Array = b["tiers"][-1]
	var ry := roof_y(b)
	var o := cornice_out(b)
	# Chimney stacks near the corners of brick roofs.
	if style in [CityLayout.Style.BRICK, CityLayout.Style.SANDSTONE] and float(tt[5]) < 60.0:
		var stack := col.darkened(0.25)
		for c in 4:
			if rng.randf() > 0.45:
				continue
			var f := _face(tt, c)
			var a := 1.2 + rng.randf_range(0.0, 0.4)
			var hgt := rng.randf_range(1.6, 2.8)
			var bx := _fbox(f, a - 0.45, a + 0.45, -1.4, -0.6, ry, ry + hgt)
			out["draw"].append([bx, stack])
			var cap := bx.grow(0.08)
			cap.position.y = ry + hgt
			cap.size.y = 0.18
			out["draw"].append([cap, trim])
			out["col"].append(AABB(cap.position - Vector3(0, hgt, 0), Vector3(cap.size.x, hgt + 0.18, cap.size.z)))
	# Glass crowns: the curtain wall carries on past the roof as a screen with
	# a light coping band, so each tower ends in its own cap (and the plant
	# behind it is hidden).
	if _glassy(b) and float(tt[5]) > 100.0 and rng.randf() < 0.7:
		var ch2 := rng.randf_range(4.0, 7.0)
		var scr := trim.darkened(rng.randf_range(0.25, 0.55))
		var x0: float = float(tt[0]) - o
		var z0: float = float(tt[1]) - o
		var x1: float = float(tt[2]) + o
		var z1: float = float(tt[3]) + o
		var rings: Array[AABB] = []
		_ring(rings, x0, z0, x1, z1, ry, ry + ch2, 0.3)
		for r in rings:
			out["draw"].append([r, scr, "far"])
			out["col"].append(r)
		var caps: Array[AABB] = []
		_ring(caps, x0 - 0.05, z0 - 0.05, x1 + 0.05, z1 + 0.05, ry + ch2, ry + ch2 + 0.35, 0.4)
		for r in caps:
			out["draw"].append([r, trim.lightened(0.25), "far"])
			out["col"].append(r)
	# Crowns: corner and mid piers rising over the parapet of deco/stone towers.
	if style in [CityLayout.Style.DECO, CityLayout.Style.STONE] and float(tt[5]) > 70.0 \
			and float(tt[2]) - float(tt[0]) > 14.0 and float(tt[3]) - float(tt[1]) > 14.0:
		var ph := rng.randf_range(3.5, 6.0)
		var pc := trim.lightened(0.08)
		for k in 4:
			var f := _face(tt, k)
			var L: float = f[3]
			for a in [-o + 0.0, L * 0.5 - 0.6]:
				var w := 1.6 if a < 0.0 else 1.2
				var bx := _fbox(f, a, a + w, -w + o, o, ry, ry + (ph if a < 0.0 else ph * 0.7))
				out["draw"].append([bx, pc])
				out["col"].append(bx)
	return out


## Appends `part`'s pieces to `out`, raised by dy (pieces built from 0).
static func _raise_into(out: Dictionary, part: Dictionary, dy: float) -> void:
	var up := Vector3(0, dy, 0)
	for d in part["draw"]:
		var bx: AABB = d[0]
		var nd: Array = d.duplicate()
		nd[0] = AABB(bx.position + up, bx.size)
		out["draw"].append(nd)
	for bm in part["beams"]:
		out["beams"].append([bm[0] + up, bm[1] + up, bm[2], bm[3], bm[4]])
	for bx: AABB in part["col"]:
		out["col"].append(AABB(bx.position + up, bx.size))


static func _fire_escape(out: Dictionary, f: Array, style: int, h: float, iron: Color,
		rng: RandomNumberGenerator, base := 0.0) -> void:
	var L: float = f[3]
	var u0: float = f[4]
	if L < 12.0:
		return
	var col_w := 4.0 if style == CityLayout.Style.WAREHOUSE else 3.2
	var floor_h := 4.4 if style == CityLayout.Style.WAREHOUSE else 3.0
	var sill := 1.0 if style == CityLayout.Style.WAREHOUSE else 0.6
	# Centred on a window-column boundary, so it spans two windows.
	var c := roundf((u0 + rng.randf_range(4.0, L - 4.0)) / col_w) * col_w - u0
	var hw := col_w + 0.2
	if c - hw < 1.2 or c + hw > L - 1.2:
		return
	var d := ESCAPE_DEPTH
	var levels: Array[float] = []
	var k := 2 if style != CityLayout.Style.WAREHOUSE else 1
	while k * floor_h + sill < h - 3.2:
		levels.append(base + k * floor_h + sill)
		k += 1
	if levels.size() < 2:
		return
	for i in levels.size():
		var y: float = levels[i]
		out["draw"].append([_fbox(f, c - hw, c + hw, 0.0, d, y - 0.08, y), iron])
		var r := 1.0
		out["beams"].append([_fpt(f, c - hw, d - 0.03, y + r), _fpt(f, c + hw, d - 0.03, y + r), 0.06, 0.06, iron])
		for e in [c - hw + 0.03, c + hw - 0.03]:
			out["beams"].append([_fpt(f, e, 0.05, y + r), _fpt(f, e, d - 0.03, y + r), 0.06, 0.06, iron])
			out["beams"].append([_fpt(f, e, d - 0.03, y), _fpt(f, e, d - 0.03, y + r), 0.05, 0.05, iron])
		if i + 1 < levels.size():
			# Zig-zag stair to the next platform, against the wall.
			var y2: float = levels[i + 1]
			var lr := 1.0 if i % 2 == 0 else -1.0
			var a := _fpt(f, c - lr * (hw - 0.4), 0.45, y)
			var e2 := _fpt(f, c + lr * (hw - 1.3), 0.45, y2 - 0.08)
			out["beams"].append([a, e2, 0.7, 0.07, iron])
			out["beams"].append([a + Vector3.UP * 0.9 + (f[2] as Vector3) * 0.32, e2 + Vector3.UP * 0.9 + (f[2] as Vector3) * 0.32,
				0.04, 0.04, iron])
	var ya: float = levels[0]
	var yb: float = levels[-1]
	out["col"].append(_fbox(f, c - hw, c + hw, 0.0, d, ya - 0.08, yb))
	out["col"].append(_fbox(f, c - hw, c + hw, d - 0.1, d, yb, yb + 1.0))
	out["col"].append(_fbox(f, c - hw, c - hw + 0.1, 0.0, d, yb, yb + 1.0))
	out["col"].append(_fbox(f, c + hw - 0.1, c + hw, 0.0, d, yb, yb + 1.0))
	# Counterweighted drop ladder under the lowest platform.
	var lx := c + hw - 0.7
	for s2 in [-0.22, 0.22]:
		out["beams"].append([_fpt(f, lx + s2, d - 0.2, ya - 2.3), _fpt(f, lx + s2, d - 0.2, ya), 0.05, 0.05, iron])
	for j in 3:
		var yy := ya - 2.0 + j * 0.8
		out["beams"].append([_fpt(f, lx - 0.22, d - 0.2, yy), _fpt(f, lx + 0.22, d - 0.2, yy), 0.03, 0.03, iron])
	out["col"].append(_fbox(f, lx - 0.27, lx + 0.27, d - 0.25, d - 0.15, ya - 2.3, ya))


static func _portal(out: Dictionary, f: Array, style: int, col: Color, trim: Color,
		rng: RandomNumberGenerator) -> void:
	var L: float = f[3]
	var u0: float = f[4]
	# On a shop-bay centre (the shader draws the door there), near the middle.
	var bay := roundf((u0 + L * 0.5 - 3.0) / 6.0)
	var c := bay * 6.0 + 3.0 - u0
	if c < 5.0 or c > L - 5.0:
		return
	var glassy := style == CityLayout.Style.GLASS or style == CityLayout.Style.DARK_GLASS
	var door := Color(0.07, 0.08, 0.1)
	if glassy or style == CityLayout.Style.MODERN:
		# Cantilevered steel-and-glass canopy over a full-height glazed lobby.
		var steel := Color(0.78, 0.8, 0.82) if rng.randf() < 0.5 else Color(0.16, 0.17, 0.19)
		var cw := rng.randf_range(4.5, 6.5)
		out["draw"].append([_fbox(f, c - 2.8, c + 2.8, 0.0, 0.2, 0.0, 4.3), door])
		var can := _fbox(f, c - cw, c + cw, 0.0, 3.2, 4.4, 4.75)
		out["draw"].append([can, steel])
		out["col"].append(_fbox(f, c - 2.8, c + 2.8, 0.0, 0.2, 0.0, 4.3))
		out["col"].append(can)
		return
	# Classical portal: two pilasters, entablature and a cornice cap.
	var stone := Color(0.7, 0.64, 0.55) if style == CityLayout.Style.BRICK else col.lightened(0.04)
	var pw := 1.0
	var ph := rng.randf_range(5.6, 6.6)
	var parts := [
		[_fbox(f, c - 2.6 - pw, c - 2.6, 0.0, 0.55, 0.0, ph), stone],
		[_fbox(f, c + 2.6, c + 2.6 + pw, 0.0, 0.55, 0.0, ph), stone],
		[_fbox(f, c - 2.9 - pw, c + 2.9 + pw, 0.0, 0.7, ph, ph + 1.1), stone],
		[_fbox(f, c - 3.1 - pw, c + 3.1 + pw, 0.0, 0.88, ph + 1.1, ph + 1.35), stone.lightened(0.08)],
		[_fbox(f, c - 2.6, c + 2.6, 0.0, 0.18, 0.0, ph - 0.9), door],
		[_fbox(f, c - 2.6, c + 2.6, 0.0, 0.12, ph - 0.9, ph), stone.darkened(0.25)],
	]
	for pt in parts:
		out["draw"].append(pt)
		out["col"].append(pt[0])
	# Brass lamps either side of the door.
	for e in [c - 2.6 - pw * 0.5, c + 2.6 + pw * 0.5]:
		out["draw"].append([_fbox(f, e - 0.14, e + 0.14, 0.55, 0.85, 3.0, 3.5), Color(0.95, 0.78, 0.4)])
		out["col"].append(_fbox(f, e - 0.14, e + 0.14, 0.55, 0.85, 3.0, 3.5))


## A billboard's legs and its catwalk, as _add_sign draws them.
static func _sign_boxes(b: Dictionary, out: Array[AABB]) -> void:
	var t: Array = b["tiers"][0]
	var roof: float = b.get("roof", float(t[4]) - 2.6)
	var along_x: bool = t[2] - t[0] > t[3] - t[1]
	var length: float = (t[2] - t[0]) if along_x else (t[3] - t[1])
	var n := maxi(2, int(length / 5.0) + 1)
	for i in n:
		var u := lerpf(0.1, 0.9, i / float(n - 1))
		var x: float = lerpf(t[0], t[2], u) if along_x else (t[0] + t[2]) * 0.5
		var z: float = (t[1] + t[3]) * 0.5 if along_x else lerpf(t[1], t[3], u)
		out.append(_aabb(x - 0.125, z - 0.125, x + 0.125, z + 0.125, roof, t[4]))
	var cx: float = (t[0] + t[2]) * 0.5
	var cz: float = (t[1] + t[3]) * 0.5
	var y: float = float(t[4]) - 0.1
	if along_x:
		out.append(_aabb(cx - length * 0.5, cz + 0.27 - 0.45, cx + length * 0.5, cz + 0.27 + 0.45, y - 0.06, y + 0.06))
	else:
		out.append(_aabb(cx + 0.27 - 0.45, cz - length * 0.5, cx + 0.27 + 0.45, cz + length * 0.5, y - 0.06, y + 0.06))


static func _aabb(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float) -> AABB:
	return AABB(Vector3(x0, y0, z0), Vector3(x1 - x0, y1 - y0, z1 - z0))


## Four thin walls of thickness t just inside the rectangle.
static func _ring(out: Array[AABB], x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, t: float) -> void:
	out.append(_aabb(x0, z0, x1, z0 + t, y0, y1))
	out.append(_aabb(x0, z1 - t, x1, z1, y0, y1))
	out.append(_aabb(x0, z0 + t, x0 + t, z1 - t, y0, y1))
	out.append(_aabb(x1 - t, z0 + t, x1, z1 - t, y0, y1))


## Low lip round a roof edge: outer and inner faces plus a top ring.
func _parapet(x0: float, z0: float, x1: float, z1: float, y: float, col: Color) -> void:
	var t := PARAPET_T
	var y1 := y + PARAPET
	walls(x0, z0, x1, z1, y, y1, col, KIND_TRIM, 0, 0)
	_inner_walls(Rect2(x0 + t, z0 + t, x1 - x0 - t * 2.0, z1 - z0 - t * 2.0), y, y1, col.darkened(0.15), KIND_TRIM)
	top(x0, z0, x1, z0 + t, y1, col, KIND_TRIM, 0, 0)
	top(x0, z1 - t, x1, z1, y1, col, KIND_TRIM, 0, 0)
	top(x0, z0 + t, x0 + t, z1 - t, y1, col, KIND_TRIM, 0, 0)
	top(x1 - t, z0 + t, x1, z1 - t, y1, col, KIND_TRIM, 0, 0)


## Projecting stone courses every few floors (relief the shader can't fake).
func _ledges(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, col: Color, style: float,
		seed: float, base := 0.0) -> void:
	var y := base + (floorf((y0 - base) / LEDGE_EVERY) + 1.0) * LEDGE_EVERY
	while y < y1 - 4.0:
		var o := LEDGE_OUT
		walls(x0 - o, z0 - o, x1 + o, z1 + o, y, y + 0.32, col, KIND_TRIM, style, seed)
		bottom(x0 - o, z0 - o, x1 + o, z1 + o, y, col.darkened(0.25), KIND_TRIM, style, seed)
		top(x0 - o, z0 - o, x1 + o, z1 + o, y + 0.32, col.lightened(0.1), KIND_TRIM, style, seed)
		y += LEDGE_EVERY


## Shop awnings along the ground floor of masonry buildings, in runs with
## gaps, colours per shop: [a, b, out, colour] (a on the left looking out).
## Solid: collision_boxes() makes a slab of each, so you can land on them.
static func awning_runs(b: Dictionary) -> Array:
	var out_runs: Array = []
	if not _has_plinth(b, 0) or not _parapeted(b) or int(b["style"]) not in [CityLayout.Style.BRICK,
			CityLayout.Style.STONE, CityLayout.Style.SANDSTONE, CityLayout.Style.DECO]:
		return out_runs
	var t: Array = b["tiers"][0]
	var x0: float = t[0]
	var z0: float = t[1]
	var x1: float = t[2]
	var z1: float = t[3]
	var avoid: Array = []  # entrance portals take the ground floor where they stand
	for bx: AABB in features(b)["col"]:
		if bx.position.y < base_of(b) + AWNING_Y + 1.0:
			avoid.append(bx.grow(0.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(b["seed"]) * 1000003.0) ^ 0xa3
	var out := AWNING_OUT
	var y := base_of(b) + AWNING_Y
	for side in 4:
		var along_x := side % 2 == 0
		var a := x0 if along_x else z0
		var bb := x1 if along_x else z1
		var d := a + 1.5
		while d + 4.0 < bb - 1.5:
			var w := rng.randf_range(3.5, 6.0)
			if rng.randf() < 0.55 and d + w < bb - 1.5:
				var col: Color = AWNING_COLORS[rng.randi() % AWNING_COLORS.size()]
				var e := d + w
				var span: AABB
				match side:
					0, 2: span = _aabb(d, (z0 if side == 0 else z1) - out, e, (z0 if side == 0 else z1) + out, y - 0.75, y + 0.75)
					_: span = _aabb((x1 if side == 1 else x0) - out, d, (x1 if side == 1 else x0) + out, e, y - 0.75, y + 0.75)
				if avoid.any(func(a2: AABB) -> bool: return a2.intersects(span)):
					d += w + rng.randf_range(0.6, 2.5)
					continue
				match side:
					0: out_runs.append([Vector3(d, y, z0), Vector3(e, y, z0), Vector3.FORWARD * out, col])
					1: out_runs.append([Vector3(x1, y, d), Vector3(x1, y, e), Vector3.RIGHT * out, col])
					2: out_runs.append([Vector3(e, y, z1), Vector3(d, y, z1), Vector3.BACK * out, col])
					3: out_runs.append([Vector3(x0, y, e), Vector3(x0, y, d), Vector3.LEFT * out, col])
			d += w + rng.randf_range(0.6, 2.5)
	return out_runs


## One awning from wall points a→b (a on the left looking out), sticking out
## by `out`: canopy top and underside, a front valance. 6 triangles.
func _awning(a: Vector3, b: Vector3, out: Vector3, col: Color, drop: Color) -> void:
	var n := out.normalized()
	var up := Vector3.UP * 0.18
	var fa := a + out
	var fb := b + out
	# (Clockwise from the visible side, like top(): a → fa → fb → b from above.)
	quad(a + up, fa + up, fb + up, b + up, Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
		col, KIND_TRIM, 0, 0)
	quad(a, b, fb, fa, Vector3.DOWN, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
		col.darkened(0.3), KIND_TRIM, 0, 0)
	quad(fa + up, fa + Vector3.DOWN * 0.38, fb + Vector3.DOWN * 0.38, fb + up, n, Vector2.ZERO, Vector2.ZERO,
		Vector2.ZERO, Vector2.ZERO, drop, KIND_TRIM, 0, 0)


static func tiers_top(b: Dictionary) -> float:
	return b["tiers"][-1][5]


func _add_sign(b: Dictionary, detailed: bool) -> void:
	var t: Array = b["tiers"][0]
	var col: Color = b["color"]
	walls(t[0], t[1], t[2], t[3], t[4], t[5], col, KIND_SIGN, 0, b["seed"], 0.0)
	top(t[0], t[1], t[2], t[3], t[5], STEEL, KIND_TRIM, 0, 0)
	bottom(t[0], t[1], t[2], t[3], t[4], STEEL, KIND_TRIM, 0, 0)
	if not detailed:
		return
	var roof: float = b.get("roof", t[4] - 2.6)
	var along_x: bool = t[2] - t[0] > t[3] - t[1]
	var length: float = (t[2] - t[0]) if along_x else (t[3] - t[1])
	var n := maxi(2, int(length / 5.0) + 1)
	for i in n:
		var u := lerpf(0.1, 0.9, i / float(n - 1))
		var x: float = lerpf(t[0], t[2], u) if along_x else (t[0] + t[2]) * 0.5
		var z: float = (t[1] + t[3]) * 0.5 if along_x else lerpf(t[1], t[3], u)
		beam(Vector3(x, roof, z), Vector3(x, t[4], z), 0.25, 0.25, STEEL)
	# Catwalk along the bottom edge.
	var o := Vector3(0, 0, 0.9) if along_x else Vector3(0.9, 0, 0)
	var c := Vector3((t[0] + t[2]) * 0.5, t[4] - 0.1, (t[1] + t[3]) * 0.5)
	var half := Vector3(length * 0.5, 0, 0) if along_x else Vector3(0, 0, length * 0.5)
	beam(c - half + o * 0.3, c + half + o * 0.3, 0.9, 0.12, STEEL)


## Construction frame: open floor slabs, columns, a safety-net band on the top floors.
func _add_frame(b: Dictionary, detailed: bool) -> void:
	var tiers: Array = b["tiers"]
	var t0: Array = tiers[0]
	var bc := base_course(b)
	if bc.has_volume():
		solid(bc.position.x, bc.position.z, bc.end.x, bc.end.z, bc.position.y, bc.end.y, CONCRETE.darkened(0.2))
	for t in tiers:
		solid(t[0], t[1], t[2], t[3], t[4], t[5], CONCRETE)
	if not detailed:
		return
	var ytop: float = tiers[-1][5]
	var base: float = b.get("base", 0.0)
	var nx := maxi(2, int((t0[2] - t0[0]) / 8.0) + 1)
	var nz := maxi(2, int((t0[3] - t0[1]) / 8.0) + 1)
	for i in nx:
		for j in nz:
			if i != 0 and i != nx - 1 and j != 0 and j != nz - 1:
				continue  # perimeter columns only
			var x: float = lerpf(t0[0] + 0.5, t0[2] - 0.5, i / float(nx - 1))
			var z: float = lerpf(t0[1] + 0.5, t0[3] - 0.5, j / float(nz - 1))
			beam(Vector3(x, base, z), Vector3(x, ytop + 3.0, z), 0.6, 0.6, CONCRETE.darkened(0.12))
	# Hoarding round the site at street level, safety screens on the top two floors.
	walls(t0[0] - 1.5, t0[1] - 1.5, t0[2] + 1.5, t0[3] + 1.5, base, base + 2.6, Color(0.2, 0.36, 0.3), KIND_TRIM, 0, 0)
	# Edge-protection barrier round the working floor.
	walls(t0[0] - 0.2, t0[1] - 0.2, t0[2] + 0.2, t0[3] + 0.2, ytop + 0.1, ytop + 1.2,
		Color(0.95, 0.55, 0.15), KIND_TRIM, 0, 0)


## Cranes and the bridge. `detailed` = lattice/girder geometry, else solid massing.
func add_structure(s: Dictionary, detailed: bool) -> void:
	var first := verts.size()
	_structure(s, detailed)
	# Structures are specified from street level 0; y0 lifts them onto their
	# block's terrace (CityLayout._lift).
	var dy: float = s.get("y0", 0.0)
	if dy != 0.0:
		for i in range(first, verts.size()):
			verts[i].y += dy


func _structure(s: Dictionary, detailed: bool) -> void:
	match s["type"]:
		"tower_crane":
			_tower_crane(s, detailed)
		"quay_crane":
			_quay_crane(s, detailed)
		"bridge":
			_bridge(s, detailed)
		"kit":
			_kit(s, detailed)


## Set pieces (SetPieces): boxes, beams and prisms; the far LOD drops thin beams.
func _kit(s: Dictionary, detailed: bool) -> void:
	for v in s["solids"]:
		solid(v[0], v[1], v[2], v[3], v[4], v[5], v[6])
	for v in s["beams"]:
		if detailed or minf(v[2], v[3]) >= 0.45:
			beam(v[0], v[1], v[2], v[3], v[4], KIND_TRIM, true)
	for v in s["prisms"]:
		prism(v[0], v[1], v[2], v[3])


## Vertical prism over a convex polygon given counter-clockwise or clockwise
## in (x, z): side walls, top and bottom.
func prism(pts: PackedVector2Array, y0: float, y1: float, col: Color) -> void:
	var n := pts.size()
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= n
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var mid := (a + b) * 0.5
		var nrm := Vector3(b.y - a.y, 0.0, -(b.x - a.x)).normalized()
		if Vector2(nrm.x, nrm.z).dot(mid - c) < 0.0:
			nrm = -nrm
		var qa := Vector3(a.x, y1, a.y)
		var qb := Vector3(b.x, y1, b.y)
		var qc := Vector3(b.x, y0, b.y)
		var qd := Vector3(a.x, y0, a.y)
		var w := a.distance_to(b)
		if (qb - qa).cross(qc - qa).dot(nrm) > 0.0:
			quad(qa, qd, qc, qb, nrm, Vector2.ZERO, Vector2(0, y1 - y0), Vector2(w, y1 - y0), Vector2(w, 0), col, KIND_TRIM, 0, 0)
		else:
			quad(qa, qb, qc, qd, nrm, Vector2.ZERO, Vector2(w, 0), Vector2(w, y1 - y0), Vector2(0, y1 - y0), col, KIND_TRIM, 0, 0)
		# Top and bottom as fans from the centre.
		var ct := Vector3(c.x, y1, c.y)
		var cb := Vector3(c.x, y0, c.y)
		_tri(ct, qa, qb, Vector3.UP, col)
		_tri(cb, qd, qc, Vector3.DOWN, col.darkened(0.25))


func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	var i := verts.size()
	verts.append_array([a, b, c])
	normals.append_array([n, n, n])
	var cc := Color(col.r, col.g, col.b, KIND_TRIM / 8.0)
	colors.append_array([cc, cc, cc])
	uvs.append_array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
	uv2s.append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	indices.append_array([i, i + 1, i + 2])


func _tower_crane(s: Dictionary, detailed: bool) -> void:
	var m := Vector3(s["x"], 0.0, s["z"])
	var h: float = s["h"]
	var d2: Vector2 = s["dir"]
	var d := Vector3(d2.x, 0.0, d2.y)
	var side := Vector3(-d.z, 0.0, d.x)
	var jib: float = s["jib"]
	var counter: float = s["counter"]
	solid(m.x - 3.0, m.z - 3.0, m.x + 3.0, m.z + 3.0, 0.0, 1.2, CONCRETE)
	lattice(m, h, 2.8, CRANE_YELLOW, 4.0, detailed)
	var ytop := m + Vector3.UP * h
	# Slewing unit, cab and tower head.
	solid(m.x - 1.8, m.z - 1.8, m.x + 1.8, m.z + 1.8, h, h + 1.2, STEEL)
	var cab := ytop + side * 2.2 + d * 0.6
	solid(cab.x - 1.2, cab.z - 1.2, cab.x + 1.2, cab.z + 1.2, h - 1.2, h + 1.4, Color(0.92, 0.92, 0.9))
	var apex := ytop + Vector3.UP * 13.0
	lattice(ytop + Vector3.UP * 1.2, 11.8, 1.6, CRANE_YELLOW, 3.0, detailed)
	# Jib and counter-jib.
	var j0 := ytop + Vector3.UP * 1.2
	girder(j0, j0 + d * jib, 2.0, 2.2, CRANE_YELLOW, detailed)
	girder(j0, j0 - d * counter, 3.0, 1.8, CRANE_YELLOW, detailed)
	var back := j0 - d * counter
	var w := back + d * 2.0
	solid(minf(w.x, back.x) - 1.8 * absf(side.x) - 0.1, minf(w.z, back.z) - 1.8 * absf(side.z) - 0.1,
		maxf(w.x, back.x) + 1.8 * absf(side.x) + 0.1, maxf(w.z, back.z) + 1.8 * absf(side.z) + 0.1,
		h - 2.6, h + 1.2, CONCRETE.darkened(0.15))
	# Pendant ties from the head to the jib and counter-jib.
	beam(apex, j0 + Vector3.UP * 2.2 + d * jib * 0.62, 0.12, 0.12, STEEL)
	beam(apex, j0 + Vector3.UP * 1.8 - d * counter * 0.9, 0.12, 0.12, STEEL)
	# Trolley, hoist line and hook block (with a load of steel beams).
	var tr := j0 + d * jib * float(s["trolley"])
	solid(tr.x - 0.8, tr.z - 0.8, tr.x + 0.8, tr.z + 0.8, tr.y - 0.5, tr.y, STEEL)
	var hook_y: float = lerpf(8.0, h - 6.0, float(s["hook"]))
	beam(tr, Vector3(tr.x, hook_y + 1.4, tr.z), 0.07, 0.07, STEEL)
	solid(tr.x - 0.5, tr.z - 0.5, tr.x + 0.5, tr.z + 0.5, hook_y + 0.4, hook_y + 1.4, CRANE_YELLOW)
	# The load of beams (drawn at every distance: it collides at every distance).
	for k in 3:
		var o := side * (k - 1) * 0.5
		beam(Vector3(tr.x, hook_y - 0.5, tr.z) + o - d * 3.0, Vector3(tr.x, hook_y - 0.5, tr.z) + o + d * 3.0,
			0.35, 0.5, Color(0.5, 0.24, 0.16))
	# Red warning light on the head.
	solid(apex.x - 0.3, apex.z - 0.3, apex.x + 0.3, apex.z + 0.3, apex.y, apex.y + 0.5, Color(1.0, 0.15, 0.1))


func _quay_crane(s: Dictionary, detailed: bool) -> void:
	var qx: float = s["x"]
	var z: float = s["z"]
	var ytop: float = s["top"]
	var reach: float = s["reach"]
	var col: Color = s["color"]
	for lx: float in [qx - 3.0, qx + 13.0]:
		for lz: float in [z - 6.0, z + 6.0]:
			solid(lx - 0.8, lz - 0.8, lx + 0.8, lz + 0.8, -2.0, ytop, col)
		beam(Vector3(lx, 4.0, z - 6.0), Vector3(lx, ytop - 4.0, z + 6.0), 0.4, 0.4, col)  # solid: drawn at every distance
		beam(Vector3(lx, 4.0, z + 6.0), Vector3(lx, ytop - 4.0, z - 6.0), 0.4, 0.4, col)
	for lz: float in [z - 6.0, z + 6.0]:
		solid(qx - 3.8, lz - 0.9, qx + 13.8, lz + 0.9, ytop - 4.0, ytop, col)
		solid(qx - 3.8, lz - 0.9, qx + 13.8, lz + 0.9, 7.0, 8.4, col)
	# Boom (out over the water) and back-reach with the machinery house.
	girder(Vector3(qx - 11.0, ytop, z), Vector3(qx + reach, ytop, z), 3.6, 3.0, col, detailed)
	solid(qx - 11.0, z - 2.6, qx - 3.0, z + 2.6, ytop + 3.0, ytop + 7.0, Color(0.9, 0.9, 0.88))
	lattice(Vector3(qx + 4.5, ytop + 3.0, z), 19.0, 2.0, col, 4.0, detailed)
	var apex := Vector3(qx + 4.5, ytop + 22.0, z)
	beam(apex, Vector3(qx + reach * 0.75, ytop + 3.0, z), 0.14, 0.14, STEEL)
	beam(apex, Vector3(qx - 10.0, ytop + 3.0, z), 0.14, 0.14, STEEL)
	# Trolley with a hanging container spreader.
	var tx := qx + reach * 0.6
	solid(tx - 1.5, z - 2.0, tx + 1.5, z + 2.0, ytop - 1.0, ytop, STEEL)
	beam(Vector3(tx, ytop - 1.0, z), Vector3(tx, 14.0, z), 0.08, 0.08, STEEL)
	solid(tx - 6.0, z - 1.3, tx + 6.0, z + 1.3, 11.4, 14.0, [Color(0.2, 0.42, 0.62), Color(0.75, 0.25, 0.15),
		Color(0.2, 0.5, 0.3)][int(absf(z)) % 3])


func _bridge(s: Dictionary, detailed: bool) -> void:
	var zc: float = s["z"]
	var deck: float = s["deck"]
	var ytop: float = s["top"]
	var xe: float = s["x_east"]
	var xw: float = s["x_west"]
	# Deck: road surface, red side girders, railings.
	top(xw, zc - 10.0, xe, zc + 10.0, deck, Color(0.23, 0.24, 0.26), KIND_TRIM, 0, 0)
	bottom(xw, zc - 10.0, xe, zc + 10.0, deck - 2.0, BRIDGE_RED.darkened(0.4), KIND_TRIM, 0, 0)
	for sz: float in [-1.0, 1.0]:
		var z0 := zc + sz * 10.0
		solid(xw, minf(z0, z0 - sz * 1.2), xe, maxf(z0, z0 - sz * 1.2), deck - 2.4, deck + 0.4, BRIDGE_RED)
		if detailed:
			beam(Vector3(xw, deck + 1.2, z0 - sz * 0.4), Vector3(xe, deck + 1.2, z0 - sz * 0.4), 0.12, 0.12, STEEL)
	if detailed:
		var x := xw
		while x < xe:
			top(x, zc - 0.12, x + 3.0, zc + 0.12, deck + 0.02, Color(0.9, 0.85, 0.6), KIND_TRIM, 0, 0)
			x += 9.0
	# Towers: two legs, three portal beams.
	for tx: float in s["towers"]:
		for sz: float in [-1.0, 1.0]:
			solid(tx - 3.0, minf(zc + sz * 15.0, zc + sz * 9.5), tx + 3.0, maxf(zc + sz * 15.0, zc + sz * 9.5),
				-2.0, ytop, BRIDGE_RED)
			solid(tx - 3.5, minf(zc + sz * 15.5, zc + sz * 9.0), tx + 3.5, maxf(zc + sz * 15.5, zc + sz * 9.0),
				ytop, ytop + 2.5, BRIDGE_RED.darkened(0.2))
		for yy in [[deck - 6.0, deck - 2.0], [88.0, 92.0], [ytop - 6.0, ytop - 2.0]]:
			solid(tx - 2.5, zc - 9.5, tx + 2.5, zc + 9.5, yy[0], yy[1], BRIDGE_RED)
		solid(tx - 5.0, zc - 18.0, tx + 5.0, zc + 18.0, -3.0, 1.0, Color(0.5, 0.47, 0.42))
	# Main cables and vertical suspenders down to the deck.
	for pts in s["cables"]:
		var cable: PackedVector3Array = pts
		for i in cable.size() - 1:
			beam(cable[i], cable[i + 1], 0.9, 0.9, BRIDGE_RED)
		if not detailed:
			continue
		for i in cable.size() - 1:
			var a := cable[i]
			var b := cable[i + 1]
			var n := int(absf(b.x - a.x) / 10.0)
			for k in n:
				var p := a.lerp(b, (k + 0.5) / n)
				if p.y > deck + 2.0:
					beam(p, Vector3(p.x, deck + 0.4, p.z), 0.12, 0.12, STEEL)


## Ground for one chunk: asphalt, raised pavement blocks with kerbs, park
## lawns and dashed avenue centre lines, clipped to the chunk rectangle.
const GROUND_STEP := 16.0  # m: road surface tessellation (bilinear between junctions; ≤ ~3 cm off)


func add_ground(layout: CityLayout, chunk_rect: Rect2) -> void:
	var asphalt := Color(0.2, 0.21, 0.23)
	var pave := Color(0.58, 0.57, 0.55)
	var kerb := Color(0.7, 0.69, 0.66)
	var grass := Color(0.32, 0.45, 0.24)
	var wall := Color(0.5, 0.46, 0.4)
	var T := layout.terrain
	var land := Rect2(CityLayout.RIVER_EDGE, CityLayout.MIN_Z - 200, CityLayout.MAX_X + 400, CityLayout.MAX_Z - CityLayout.MIN_Z + 400)
	var r := chunk_rect.intersection(land)
	if r.has_area():
		# Streets only: cut the land along every kerb line and skip the cells
		# a block covers (its pavement or terrace is drawn over it).
		var kx := _kerb_lines(layout.x_streets)
		var kz := _kerb_lines(layout.z_streets)
		for lr in layout.land:
			var g := r.intersection(lr)
			if not g.has_area():
				continue
			var cx := _cuts(g.position.x, g.end.x, kx)
			var cz := _cuts(g.position.y, g.end.y, kz)
			for i in cx.size() - 1:
				for j in cz.size() - 1:
					var cell := Rect2(cx[i], cz[j], cx[i + 1] - cx[i], cz[j + 1] - cz[j])
					if not layout.block_at(cell.get_center().x, cell.get_center().y).has_area():
						terrain_patch(T, cell, 0.0, asphalt)
	for blk in layout.blocks:
		var g: Rect2 = (blk as Rect2).intersection(chunk_rect)
		if not g.has_area():
			continue
		var is_park := false
		for p in layout.parks:
			if p == blk:
				is_park = true
		var is_basin := false
		for w in layout.water:
			if (w as Rect2).encloses(blk.grow(-7.0)) and w.position.x > 0.0:
				is_basin = true
		var level: float = layout.terraces.get(blk, NAN)
		var flat := not is_nan(level)
		if is_basin:
			# Only the quay ring is paved; the middle is open water.
			for q in CityLayout._subtract(blk, blk.grow(-6.0)):
				var gq: Rect2 = (q as Rect2).intersection(chunk_rect)
				if gq.has_area():
					top(gq.position.x, gq.position.y, gq.end.x, gq.end.y, level, pave, KIND_ROOF, 0, 0)
		elif flat:
			top(g.position.x, g.position.y, g.end.x, g.end.y, level, grass if is_park else pave, KIND_ROOF, 0, 0)
		else:
			terrain_patch(T, g, CityTerrain.KERB, grass if is_park else pave)
		# Kerb (sloping blocks) or retaining wall down to the street (terraces).
		terrain_skirt(T, blk, chunk_rect, level, kerb if not flat else wall)
		if is_basin:
			# Quay walls down to the basin water.
			var w2: Rect2 = blk.grow(-6.0).intersection(chunk_rect)
			if w2.has_area():
				_inner_walls(w2, -3.0, level + 0.01, Color(0.4, 0.33, 0.28))
	# Waterfront promenade edge / river wall.
	if chunk_rect.position.x <= CityLayout.RIVER_EDGE and chunk_rect.end.x > CityLayout.RIVER_EDGE:
		var z0 := chunk_rect.position.y
		var z1 := chunk_rect.end.y
		var x := CityLayout.RIVER_EDGE
		quad(Vector3(x, 0.0, z0), Vector3(x, 0.0, z1), Vector3(x, -4.0, z1), Vector3(x, -4.0, z0), Vector3.LEFT,
			Vector2(z0, 0), Vector2(z1, 0), Vector2(z1, -4), Vector2(z0, -4), Color(0.45, 0.4, 0.34), KIND_WALL, 5, 0.3)
		solid(x, z0, x + 0.6, z1, 0.0, 1.1, Color(0.3, 0.32, 0.33))


static func _kerb_lines(streets: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for st in streets:
		out.append(float(st[0]) - float(st[1]) * 0.5)
		out.append(float(st[0]) + float(st[1]) * 0.5)
	return out


## a, b and every line strictly between them, ascending.
static func _cuts(a: float, b: float, lines: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array([a])
	for l in lines:
		if l > a + 0.01 and l < b - 0.01:
			out.append(l)
	out.append(b)
	out.sort()
	return out


## The ground over `r`, dy above the road surface (CityTerrain.road_y): a
## grid through every junction line, at most `step` apart, so it matches
## road_y everywhere (collision is built from these very triangles).
func terrain_patch(T: CityTerrain, r: Rect2, dy: float, col: Color, step := GROUND_STEP) -> void:
	var xs := T.splits(r.position.x, r.end.x, T.xs, step)
	var zs := T.splits(r.position.y, r.end.y, T.zs, step)
	var row := PackedFloat32Array()
	row.resize(xs.size() * zs.size())
	for i in xs.size():
		for j in zs.size():
			row[i * zs.size() + j] = T.road_y(xs[i], zs[j]) + dy
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var x0 := xs[i]
			var x1 := xs[i + 1]
			var z0 := zs[j]
			var z1 := zs[j + 1]
			var a := Vector3(x0, row[i * zs.size() + j], z0)
			var b := Vector3(x1, row[(i + 1) * zs.size() + j], z0)
			var c := Vector3(x1, row[(i + 1) * zs.size() + j + 1], z1)
			var d := Vector3(x0, row[i * zs.size() + j + 1], z1)
			var n := (c - a).cross(b - d).normalized()
			if n.y < 0.0:
				n = -n
			quad(a, b, c, d, n, Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1), col, KIND_ROOF, 0, 0)


## Walls round a block (only the parts inside `clip`): from below the street
## up to the pavement – a kerb where the pavement follows the street
## (level = NAN), a retaining wall up to a terrace at `level`.
func terrain_skirt(T: CityTerrain, blk: Rect2, clip: Rect2, level: float, col: Color, step := GROUND_STEP) -> void:
	var x0 := blk.position.x
	var z0 := blk.position.y
	var x1 := blk.end.x
	var z1 := blk.end.y
	# Same corner order and outward normals as walls().
	var corners := [Vector2(x0, z1), Vector2(x1, z1), Vector2(x1, z0), Vector2(x0, z0)]
	var ns := [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var along_x := absf(a.y - b.y) < 0.01
		var lines := T.xs if along_x else T.zs
		var u0 := a.x if along_x else a.y
		var u1 := b.x if along_x else b.y
		var cuts := T.splits(minf(u0, u1), maxf(u0, u1), lines, step)
		if u0 > u1:
			cuts.reverse()
		for m in cuts.size() - 1:
			var p := Vector2(cuts[m], a.y) if along_x else Vector2(a.x, cuts[m])
			var q := Vector2(cuts[m + 1], a.y) if along_x else Vector2(a.x, cuts[m + 1])
			var mid := (p + q) * 0.5
			if not clip.has_point(mid):
				continue
			var yp := T.road_y(p.x, p.y)
			var yq := T.road_y(q.x, q.y)
			var tp := level if not is_nan(level) else yp + CityTerrain.KERB
			var tq := level if not is_nan(level) else yq + CityTerrain.KERB
			quad(Vector3(p.x, tp, p.y), Vector3(q.x, tq, q.y), Vector3(q.x, yq - 0.3, q.y), Vector3(p.x, yp - 0.3, p.y),
				ns[k], Vector2(cuts[m], tp), Vector2(cuts[m + 1], tq), Vector2(cuts[m + 1], yq - 0.3),
				Vector2(cuts[m], yp - 0.3), col, KIND_TRIM if is_nan(level) else KIND_WALL, 5, 0.42)


## All triangles, for a ConcavePolygonShape3D (collision = what's drawn).
func faces() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(indices.size())
	for i in indices.size():
		out[i] = verts[indices[i]]
	return out


func _inner_walls(r: Rect2, y0: float, y1: float, col: Color, kind := KIND_WALL) -> void:
	# Walls facing inward (towards the basin centre).
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	var corners := [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]
	var ns := [Vector3.BACK, Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var w := a.distance_to(b)
		quad(Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(b.x, y0, b.y), Vector3(a.x, y0, a.y), ns[k],
			Vector2(0, y1), Vector2(w, y1), Vector2(w, y0), Vector2(0, y0), col, kind, 3, 0.5)
