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
		u += w


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
	for i in tiers.size():
		var t: Array = tiers[i]
		var x0: float = t[0]
		var z0: float = t[1]
		var x1: float = t[2]
		var z1: float = t[3]
		var y0: float = t[4]
		var y1: float = t[5]
		walls(x0, z0, x1, z1, y0, y1, col, wall_kind, style, seed)
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
					_ledges(x0, z0, x1, z1, y0, y1, trim, style, seed)
			# Ground-floor plinth band on the base tier.
			if _has_plinth(b, i):
				var po := PLINTH_OUT
				walls(x0 - po, z0 - po, x1 + po, z1 + po, 0.0, PLINTH_H, col.darkened(0.3), KIND_TRIM, style, seed)
				top(x0 - po, z0 - po, x1 + po, z0, PLINTH_H, col.darkened(0.3), KIND_TRIM, style, seed)
				top(x0 - po, z1, x1 + po, z1 + po, PLINTH_H, col.darkened(0.3), KIND_TRIM, style, seed)
				top(x0 - po, z0, x0, z1, PLINTH_H, col.darkened(0.3), KIND_TRIM, style, seed)
				top(x1, z0, x1 + po, z1, PLINTH_H, col.darkened(0.3), KIND_TRIM, style, seed)
				for aw in awning_runs(b):
					_awning(aw[0], aw[1], aw[2], aw[3], (aw[3] as Color).darkened(0.15))
		else:
			top(x0, z0, x1, z1, y1, roof, KIND_ROOF, style, seed)


## Cornice: how far the roof slab overhangs the walls, and its depth (it
## straddles the tier top, so the roof surface is half of it above t[5]).
static func cornice_out(b: Dictionary) -> float:
	return 0.25 if _glassy(b) else 0.3


static func cornice_h(b: Dictionary) -> float:
	return 0.6 if _glassy(b) else 1.0


static func _glassy(b: Dictionary) -> bool:
	return int(b["style"]) == CityLayout.Style.GLASS or int(b["style"]) == CityLayout.Style.DARK_GLASS


static func _parapeted(b: Dictionary) -> bool:
	return b["kind"] in ["normal", "landmark", "spire"]


static func _has_plinth(b: Dictionary, tier: int) -> bool:
	return tier == 0 and float(b["tiers"][0][4]) == 0.0 and not _glassy(b) and b["kind"] != "bridge"


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
			return out
		"frame":
			for t in tiers:
				out.append(_aabb(t[0], t[1], t[2], t[3], t[4], t[5]))
			var t0: Array = tiers[0]
			var ytop: float = tiers[-1][5]
			var nx := maxi(2, int((t0[2] - t0[0]) / 8.0) + 1)
			var nz := maxi(2, int((t0[3] - t0[1]) / 8.0) + 1)
			for i in nx:
				for j in nz:
					if i != 0 and i != nx - 1 and j != 0 and j != nz - 1:
						continue
					var x: float = lerpf(t0[0] + 0.5, t0[2] - 0.5, i / float(nx - 1))
					var z: float = lerpf(t0[1] + 0.5, t0[3] - 0.5, j / float(nz - 1))
					out.append(_aabb(x - 0.3, z - 0.3, x + 0.3, z + 0.3, 0.0, ytop + 3.0))
			_ring(out, t0[0] - 1.5, t0[1] - 1.5, t0[2] + 1.5, t0[3] + 1.5, 0.0, 2.6, 0.12)
			_ring(out, t0[0] - 0.2, t0[1] - 0.2, t0[2] + 0.2, t0[3] + 0.2, ytop + 0.1, ytop + 1.2, 0.12)
			return out
	var o := cornice_out(b)
	var ch := cornice_h(b)
	for i in tiers.size():
		var t: Array = tiers[i]
		var y1: float = t[5]
		out.append(_aabb(t[0], t[1], t[2], t[3], t[4], y1 - ch * 0.5))
		out.append(_aabb(t[0] - o, t[1] - o, t[2] + o, t[3] + o, y1 - ch * 0.5, y1 + ch * 0.5))
		if kind != "bridge":
			_ring(out, t[0] - o, t[1] - o, t[2] + o, t[3] + o, y1 + ch * 0.5, y1 + ch * 0.5 + PARAPET, PARAPET_T)
		if _has_plinth(b, i):
			out.append(_aabb(t[0] - PLINTH_OUT, t[1] - PLINTH_OUT, t[2] + PLINTH_OUT, t[3] + PLINTH_OUT, 0.0, PLINTH_H))
	for aw in awning_runs(b):
		var a: Vector3 = aw[0]
		var e: Vector3 = aw[1]
		var far: Vector3 = e + (aw[2] as Vector3)
		var lo := Vector3(minf(a.x, far.x), AWNING_Y - 0.38, minf(a.z, far.z))
		var hi := Vector3(maxf(a.x, far.x), AWNING_Y + 0.18, maxf(a.z, far.z))
		out.append(AABB(lo, hi - lo))
	return out


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
		seed: float) -> void:
	var y := (floorf(y0 / LEDGE_EVERY) + 1.0) * LEDGE_EVERY
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
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(b["seed"]) * 1000003.0) ^ 0xa3
	var out := AWNING_OUT
	var y := AWNING_Y
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
	for t in tiers:
		solid(t[0], t[1], t[2], t[3], t[4], t[5], CONCRETE)
	if not detailed:
		return
	var ytop: float = tiers[-1][5]
	var nx := maxi(2, int((t0[2] - t0[0]) / 8.0) + 1)
	var nz := maxi(2, int((t0[3] - t0[1]) / 8.0) + 1)
	for i in nx:
		for j in nz:
			if i != 0 and i != nx - 1 and j != 0 and j != nz - 1:
				continue  # perimeter columns only
			var x: float = lerpf(t0[0] + 0.5, t0[2] - 0.5, i / float(nx - 1))
			var z: float = lerpf(t0[1] + 0.5, t0[3] - 0.5, j / float(nz - 1))
			beam(Vector3(x, 0.0, z), Vector3(x, ytop + 3.0, z), 0.6, 0.6, CONCRETE.darkened(0.12))
	# Hoarding round the site at street level, safety screens on the top two floors.
	walls(t0[0] - 1.5, t0[1] - 1.5, t0[2] + 1.5, t0[3] + 1.5, 0.0, 2.6, Color(0.2, 0.36, 0.3), KIND_TRIM, 0, 0)
	# Edge-protection barrier round the working floor.
	walls(t0[0] - 0.2, t0[1] - 0.2, t0[2] + 0.2, t0[3] + 0.2, ytop + 0.1, ytop + 1.2,
		Color(0.95, 0.55, 0.15), KIND_TRIM, 0, 0)


## Cranes and the bridge. `detailed` = lattice/girder geometry, else solid massing.
func add_structure(s: Dictionary, detailed: bool) -> void:
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
func add_ground(layout: CityLayout, chunk_rect: Rect2) -> void:
	var asphalt := Color(0.2, 0.21, 0.23)
	var pave := Color(0.58, 0.57, 0.55)
	var kerb := Color(0.7, 0.69, 0.66)
	var grass := Color(0.32, 0.45, 0.24)
	var land := Rect2(CityLayout.RIVER_EDGE, CityLayout.MIN_Z - 200, CityLayout.MAX_X + 400, CityLayout.MAX_Z - CityLayout.MIN_Z + 400)
	var r := chunk_rect.intersection(land)
	if r.has_area():
		for lr in layout.land:
			var g := r.intersection(lr)
			if g.has_area():
				top(g.position.x, g.position.y, g.end.x, g.end.y, 0.0, asphalt, KIND_ROOF, 0, 0)
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
		if is_basin:
			# Only the quay ring is paved; the middle is open water.
			for q in CityLayout._subtract(blk, blk.grow(-6.0)):
				var gq: Rect2 = (q as Rect2).intersection(chunk_rect)
				if gq.has_area():
					top(gq.position.x, gq.position.y, gq.end.x, gq.end.y, 0.15, pave, KIND_ROOF, 0, 0)
		else:
			top(g.position.x, g.position.y, g.end.x, g.end.y, 0.15, grass if is_park else pave, KIND_ROOF, 0, 0)
		walls(g.position.x, g.position.y, g.end.x, g.end.y, 0.0, 0.15, kerb, KIND_TRIM, 0, 0)
		if is_basin:
			# Quay walls down to the basin water.
			var w2: Rect2 = blk.grow(-6.0).intersection(chunk_rect)
			if w2.has_area():
				_inner_walls(w2, -3.0, 0.16, Color(0.4, 0.33, 0.28))
	# Waterfront promenade edge / river wall.
	if chunk_rect.position.x <= CityLayout.RIVER_EDGE and chunk_rect.end.x > CityLayout.RIVER_EDGE:
		var z0 := chunk_rect.position.y
		var z1 := chunk_rect.end.y
		var x := CityLayout.RIVER_EDGE
		quad(Vector3(x, 0.0, z0), Vector3(x, 0.0, z1), Vector3(x, -4.0, z1), Vector3(x, -4.0, z0), Vector3.LEFT,
			Vector2(z0, 0), Vector2(z1, 0), Vector2(z1, -4), Vector2(z0, -4), Color(0.45, 0.4, 0.34), KIND_WALL, 5, 0.3)
		solid(x, z0, x + 0.6, z1, 0.0, 1.1, Color(0.3, 0.32, 0.33))


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
