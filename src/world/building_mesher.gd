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
const ROOF_COLOR := Color(0.40, 0.40, 0.41)

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
	if b["kind"] == "invisible":
		return
	var style := float(b["style"])
	var seed: float = b["seed"]
	var col: Color = b["color"]
	var glassy := style == CityLayout.Style.GLASS or style == CityLayout.Style.DARK_GLASS
	var wall_kind := KIND_GLASS if glassy else KIND_WALL
	var trim := trim_color(b)
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
			var o := 0.25 if glassy else 0.6
			var ch := 0.6 if glassy else 1.2
			walls(x0 - o, z0 - o, x1 + o, z1 + o, y1 - ch * 0.5, y1 + ch * 0.5, trim, KIND_TRIM, style, seed)
			bottom(x0 - o, z0 - o, x1 + o, z1 + o, y1 - ch * 0.5, trim, KIND_TRIM, style, seed)
			top(x0 - o, z0 - o, x1 + o, z1 + o, y1 + ch * 0.5, ROOF_COLOR, KIND_ROOF, style, seed)
			# Ground-floor plinth band on the base tier.
			if i == 0 and y0 == 0.0 and not glassy and b["kind"] != "bridge":
				walls(x0 - 0.15, z0 - 0.15, x1 + 0.15, z1 + 0.15, 0.0, 0.9, col.darkened(0.3), KIND_TRIM, style, seed)
		else:
			top(x0, z0, x1, z1, y1, ROOF_COLOR, KIND_ROOF, style, seed)


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
		walls(x, z0, x + 0.6, z1, 0.0, 1.1, Color(0.3, 0.32, 0.33), KIND_TRIM, 0, 0)
	for m in layout.avenue_marks:
		var a: Vector3 = m[0]
		var b: Vector3 = m[1]
		var dir := (b - a).normalized()
		var length := a.distance_to(b)
		var side := dir.cross(Vector3.UP) * 0.12
		var d := 0.0
		while d < length:
			var p0 := a + dir * d
			var p1 := a + dir * minf(d + 3.0, length)
			if chunk_rect.has_point(Vector2(p0.x, p0.z)):
				quad(p0 - side, p1 - side, p1 + side, p0 + side, Vector3.UP, Vector2.ZERO, Vector2.ZERO,
					Vector2.ZERO, Vector2.ZERO, Color(0.85, 0.82, 0.7), KIND_TRIM, 0, 0)
			d += 9.0


func _inner_walls(r: Rect2, y0: float, y1: float, col: Color) -> void:
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
			Vector2(0, y1), Vector2(w, y1), Vector2(w, y0), Vector2(0, y0), col, KIND_WALL, 3, 0.5)
