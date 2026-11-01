class_name HomeInteriors
extends RefCounted
## The rooms behind the homes' windows (Apartments): shell (floor, ceiling,
## three walls and the inside of the window wall round the opening), the
## opening's reveals so its edges have depth, frames and mullions, and a
## distinct home per tier – its own plan, materials, lighting and things:
##   0 Quay Studio      a courier's lived-in studio: brick, pine, bike on the wall
##   1 City Apartment   Scandinavian one-bed: pale oak, bookshelves, breakfast bar
##   2 High-Rise Loft   industrial: concrete, brick, ducts, gym corner, neon
##   3 Sky Apartment    contemporary luxury: marble, walnut slats, fireplace, piano
##   4 Penthouse        dark stone and brass, plunge pool, a mezzanine you can
##                      climb to, a bar and a Hall of Fame wall
## Geometry is batched in the building material (plain boxes and tubes, one
## draw call), plus one unshaded mesh for everything that glows, one for
## glass, shader planes for floors/feature walls, shared Blender furniture,
## collision on the big pieces (human layer only, so webs and bots ignore
## it), warm lights and a board showing your progress (HomeBoard).
## Layout per room is in room coordinates: x along the window wall from its
## left end (0..W), z inward from the window (0..D), y up from the floor.
## The strip from the spawn spot to the window, and a band 2.6 m deep across
## the whole opening (window entries land there), never get collision.

const FRAME := Color(0.1, 0.1, 0.11)
const WALNUT := Color(0.26, 0.15, 0.09)
const OAK := Color(0.66, 0.5, 0.33)
const STEEL := Color(0.07, 0.07, 0.08)
const BRASS := Color(0.74, 0.57, 0.3)
const CHALK := Color(0.93, 0.92, 0.89)
const STONE := Color(0.82, 0.8, 0.74)
## Per tier: wall, floor tint, ceiling colours, floor style (home_floor.gdshader).
const PALETTE := [
	[Color(0.86, 0.8, 0.7), Color(0.6, 0.42, 0.26), Color(0.9, 0.88, 0.84), 0],
	[Color(0.93, 0.92, 0.89), Color(0.74, 0.59, 0.42), Color(0.95, 0.95, 0.93), 3],
	[Color(0.7, 0.69, 0.66), Color(0.56, 0.56, 0.55), Color(0.27, 0.27, 0.29), 1],
	[Color(0.91, 0.89, 0.85), Color(0.88, 0.87, 0.84), Color(0.95, 0.94, 0.92), 2],
	[Color(0.5, 0.47, 0.43), Color(0.2, 0.2, 0.21), Color(0.24, 0.18, 0.13), 4],
]

var h: Dictionary
var m := BuildingMesher.new()
var W := 0.0
var D := 0.0
var H := 0.0
var col_boxes: Array[AABB] = []   # local frame
var assets: Array = []
var lights: Array = []           # [room point, colour, energy, range]
var glow := BuildingMesher.new()  # unshaded, vertex-coloured (lamps, screens, flames)
var glass := BuildingMesher.new() # transparent panels
var walls_fx: Array = []          # [side, a0, a1, y0, y1, style, tint] feature walls
var boards: Array = []            # [room point, side, width] HomeBoard positions
var pools: Array = []             # [x0, x1, z0, z1, y]


static func build(home: Dictionary, mat: Material) -> Node3D:
	var I := HomeInteriors.new()
	I.h = home
	return I._build(mat)


## Room coords → the building's local frame.
func P(x: float, z: float, y: float) -> Vector3:
	return BuildingMesher._fpt(Apartments.face_of(h), float(h["a0"]) + x, -z, float(h["y0"]) + y)


## A box in room coords (x0..x1, z0..z1, y0..y1); `solid` adds collision.
func box(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, c: Color, solid := false) -> void:
	var a := P(x0, z0, y0)
	var b := P(x1, z1, y1)
	var lo := a.min(b)
	var hi := a.max(b)
	m.solid(lo.x, lo.z, hi.x, hi.z, lo.y, hi.y, c)
	if solid:
		col_boxes.append(AABB(lo, hi - lo))


func _build(mat: Material) -> Node3D:
	var tier: int = h["tier"]
	W = float(h["a1"]) - float(h["a0"])
	D = float(h["depth"])
	H = float(h["y1"]) - float(h["y0"])
	var pal: Array = PALETTE[tier]
	var f := Apartments.face_of(h)
	m._begin(h["b"])
	glow._begin(h["b"])
	glass._begin(h["b"])
	var r := Apartments.room_box(h)
	# Shell: floor, ceiling, side and back walls (facing in).
	m.bottom(r.position.x, r.position.z, r.end.x, r.end.z, r.end.y - 0.01, pal[2], BuildingMesher.KIND_TRIM, 0, 0)
	_inner_three(r, f, pal[0])
	# The inside of the window wall round the opening, 0.3 m in, and the
	# opening's reveals (so its edges have the wall's thickness).
	var inward := -(f[2] as Vector3)
	var A := [float(h["a0"]), float(h["oa0"]), float(h["oa1"]), float(h["a1"])]
	var Y := [float(h["y0"]), float(h["oy0"]), float(h["oy1"]), float(h["y1"])]
	for ia in 3:
		for iy in 3:
			if ia == 1 and iy == 1:
				continue
			if float(A[ia + 1]) - float(A[ia]) < 0.01 or float(Y[iy + 1]) - float(Y[iy]) < 0.01:
				continue
			var p1 := BuildingMesher._fpt(f, A[ia + 1], -0.3, 0.0)
			var p0 := BuildingMesher._fpt(f, A[ia], -0.3, 0.0)
			m.quad(Vector3(p1.x, Y[iy + 1], p1.z), Vector3(p0.x, Y[iy + 1], p0.z), Vector3(p0.x, Y[iy], p0.z),
				Vector3(p1.x, Y[iy], p1.z), inward, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, pal[0],
				BuildingMesher.KIND_TRIM, 0, 0)
	var oa0: float = h["oa0"]
	var oa1: float = h["oa1"]
	var oy0: float = h["oy0"]
	var oy1: float = h["oy1"]
	var trim: Color = (pal[0] as Color).darkened(0.25)
	# Reveals: left, right (thin boxes lining the jambs), sill and head.
	box(oa0 - float(h["a0"]) - 0.02, oa0 - float(h["a0"]), -0.02, 0.32, oy0 - float(h["y0"]), oy1 - float(h["y0"]), trim)
	box(oa1 - float(h["a0"]), oa1 - float(h["a0"]) + 0.02, -0.02, 0.32, oy0 - float(h["y0"]), oy1 - float(h["y0"]), trim)
	box(oa0 - float(h["a0"]), oa1 - float(h["a0"]), -0.02, 0.32, oy1 - float(h["y0"]), oy1 - float(h["y0"]) + 0.02, trim)
	if oy0 > float(h["y0"]) + 0.01:
		box(oa0 - float(h["a0"]) - 0.05, oa1 - float(h["a0"]) + 0.05, -0.08, 0.36, oy0 - float(h["y0"]) - 0.02,
			oy0 - float(h["y0"]) + 0.03, Color(0.86, 0.84, 0.8))  # stone sill
	_frame(tier)
	_residence(tier, pal)
	m._end()
	glow._end()
	glass._end()
	var root := Node3D.new()
	root.name = "Home_" + String(h["id"])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.arrays())
	var mi := MeshInstance3D.new()
	mi.name = "Interior"
	mi.mesh = mesh
	mi.material_override = mat
	mi.visibility_range_end = 420.0  # only drawn when it can matter
	root.add_child(mi)
	var xf := CityLayout.bxf(h["b"])
	if not col_boxes.is_empty():
		var body := StaticBody3D.new()
		body.name = "Furniture"
		body.collision_layer = CityWorld.HUMAN_LAYER
		body.collision_mask = 0
		for bx in col_boxes:
			CityWorld._add_box_xf(body, bx, xf)
		root.add_child(body)
	for L in lights:
		var o := OmniLight3D.new()
		var lp: Vector3 = L[0]
		o.position = xf * P(lp.x, lp.z, lp.y)
		o.light_color = L[1]
		o.light_energy = L[2]
		o.omni_range = L[3]
		o.omni_attenuation = 1.2
		o.shadow_enabled = false
		o.distance_fade_enabled = true
		o.distance_fade_begin = 120.0
		o.distance_fade_length = 40.0
		root.add_child(o)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(W, D)
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = load("res://src/world/shaders/home_floor.gdshader")
	floor_mat.set_shader_parameter("timber", pal[1])
	floor_mat.set_shader_parameter("room_size", Vector2(W, D))
	floor_mat.set_shader_parameter("style", int(pal[3]))
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = floor_mat
	floor_node.transform = xf * Transform3D(Basis(f[1], Vector3.UP, f[2]), P(W * 0.5, D * 0.5, 0.01))
	floor_node.visibility_range_end = 420.0
	floor_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(floor_node)
	_place_assets(root)
	_extras(root, xf)
	return root


## The layers beside the batched shell: glow, glass, feature walls, pools
## and progress boards.
func _extras(root: Node3D, xf: Transform3D) -> void:
	if not glow.is_empty():
		var gm := ArrayMesh.new()
		gm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glow.arrays())
		var gi := MeshInstance3D.new()
		gi.name = "Glow"
		gi.mesh = gm
		gi.material_override = _shared("glow")
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.visibility_range_end = 300.0
		root.add_child(gi)
	if not glass.is_empty():
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glass.arrays())
		var ai := MeshInstance3D.new()
		ai.name = "Glass"
		ai.mesh = am
		ai.material_override = _shared("glass")
		ai.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ai.visibility_range_end = 160.0
		root.add_child(ai)
	for fx in walls_fx:
		var c := _wall_corners(fx[0], fx[1], fx[2], fx[3], fx[4], fx[5])
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n: Vector3 = c[4]
		var q: Array = [c[0], c[1], c[2], c[3]]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var order := [0, 1, 2, 0, 2, 3]
		if (xf * (q[1] as Vector3) - xf * (q[0] as Vector3)).cross(xf * (q[2] as Vector3) - xf * (q[0] as Vector3)).dot(xf.basis * n) > 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for i in order:
			st.set_normal((xf.basis * n).normalized())
			st.set_uv(uv[i])
			st.add_vertex(xf * (q[i] as Vector3))
		var wm := ShaderMaterial.new()
		wm.shader = load("res://src/world/shaders/home_wall.gdshader")
		wm.set_shader_parameter("tint", fx[7])
		wm.set_shader_parameter("size", Vector2(float(fx[3]) - float(fx[2]), float(fx[5]) - float(fx[4])))
		wm.set_shader_parameter("style", int(fx[6]))
		var wi := MeshInstance3D.new()
		wi.name = "Feature"
		wi.mesh = st.commit()
		wi.material_override = wm
		wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wi.visibility_range_end = 260.0
		root.add_child(wi)
	for pl in pools:
		var pm := PlaneMesh.new()
		pm.size = Vector2(float(pl[1]) - float(pl[0]), float(pl[3]) - float(pl[2]))
		var pi := MeshInstance3D.new()
		pi.name = "Pool"
		pi.mesh = pm
		pi.material_override = _shared("pool")
		var f := Apartments.face_of(h)
		pi.transform = xf * Transform3D(Basis(f[1], Vector3.UP, f[2]),
			P((float(pl[0]) + float(pl[1])) * 0.5, (float(pl[2]) + float(pl[3])) * 0.5, float(pl[4])))
		pi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pi.visibility_range_end = 200.0
		root.add_child(pi)
	for bd in boards:
		var lb := HomeBoard.new()
		lb.tier = int(h["tier"])
		lb.board_w = float(bd[4])
		var c := _wall_corners(bd[0], bd[1], float(bd[2]) - 0.5, float(bd[2]) + 0.5, float(bd[3]) - 0.5, float(bd[3]) + 0.5)
		var n: Vector3 = (xf.basis * (c[4] as Vector3)).normalized()
		var centre: Vector3 = xf * (((c[0] as Vector3) + (c[2] as Vector3)) * 0.5) + n * 0.07
		lb.transform = Transform3D(Basis(Vector3.UP.cross(n).normalized(), Vector3.UP, n), centre)
		root.add_child(lb)


## Corners (building frame) of a wall patch and its inward normal:
## [bottom-left, bottom-right, top-right, top-left, normal].
func _wall_corners(side: String, at: float, a0: float, a1: float, y0: float, y1: float) -> Array:
	var e := 0.012
	match side:
		"back":
			var n := (P(0.0, at - 1.0, 0.0) - P(0.0, at, 0.0)).normalized()
			return [P(a0, at - e, y0), P(a1, at - e, y0), P(a1, at - e, y1), P(a0, at - e, y1), n]
		"left":
			var n := (P(at + 1.0, 0.0, 0.0) - P(at, 0.0, 0.0)).normalized()
			return [P(at + e, a1, y0), P(at + e, a0, y0), P(at + e, a0, y1), P(at + e, a1, y1), n]
		_:
			var n := (P(at - 1.0, 0.0, 0.0) - P(at, 0.0, 0.0)).normalized()
			return [P(at - e, a0, y0), P(at - e, a1, y0), P(at - e, a1, y1), P(at - e, a0, y1), n]


static var _mats := {}


static func _shared(kind: String) -> Material:
	if _mats.has(kind):
		return _mats[kind]
	var mt := StandardMaterial3D.new()
	match kind:
		"glow":
			mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mt.vertex_color_use_as_albedo = true
		"glass":
			mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mt.albedo_color = Color(0.78, 0.88, 0.9, 0.16)
			mt.roughness = 0.05
			mt.metallic_specular = 0.9
			mt.cull_mode = BaseMaterial3D.CULL_DISABLED
		"pool":
			mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mt.albedo_color = Color(0.1, 0.52, 0.62, 0.82)
			mt.roughness = 0.04
			mt.metallic_specular = 1.0
			mt.emission_enabled = true
			mt.emission = Color(0.04, 0.3, 0.36)
	_mats[kind] = mt
	return mt


func _inner_three(r: AABB, f: Array, col: Color) -> void:
	# Like BuildingMesher._inner_walls, minus the window wall.
	var x0 := r.position.x
	var z0 := r.position.z
	var x1 := r.end.x
	var z1 := r.end.z
	var y0 := r.position.y
	var y1 := r.end.y
	var corners := [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]
	var ns := [Vector3.BACK, Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT]
	var skip: int = {0: 2, 1: 1, 2: 0, 3: 3}[int(h["face"])]
	for k in 4:
		if k == skip:
			continue
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		m.quad(Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(b.x, y0, b.y), Vector3(a.x, y0, a.y), ns[k],
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col, BuildingMesher.KIND_TRIM, 0, 0)


## Window frames: slim dark frames on the small flats, a steel grid over head
## height in the loft, fine metal edges on the glass of the top two.
func _frame(tier: int) -> void:
	var a0 := float(h["oa0"]) - float(h["a0"])
	var a1 := float(h["oa1"]) - float(h["a0"])
	var y0 := float(h["oy0"]) - float(h["y0"])
	var y1 := float(h["oy1"]) - float(h["y0"])
	var t := 0.07 if tier < 3 else 0.04
	var c := FRAME if tier != 4 else Color(0.62, 0.6, 0.55)
	box(a0, a0 + t, -0.04, 0.06, y0, y1, c)
	box(a1 - t, a1, -0.04, 0.06, y0, y1, c)
	box(a0, a1, -0.04, 0.06, y1 - t, y1, c)
	if tier == 2:
		# Industrial: a transom at 2.9 m with a mullion grid above it.
		var ty := 2.9
		box(a0, a1, -0.04, 0.06, ty, ty + 0.08, FRAME)
		var n := int((a1 - a0) / 1.2)
		for i in range(1, n):
			var x := lerpf(a0, a1, float(i) / n)
			box(x - 0.03, x + 0.03, -0.04, 0.06, ty, y1, FRAME)
	elif tier < 2:
		# Casement sash swung open against the outside wall.
		box(a1, a1 + 0.05, 0.0, 0.0 + 0.04, y0, y1, FRAME)


func _rug(x0: float, x1: float, z0: float, z1: float, c: Color) -> void:
	box(x0, x1, z0, z1, 0.0, 0.015, c)


## Shared metric furniture; no per-home material duplication. x/z are room coordinates.
func asset(id: String, x: float, z: float, yaw := 0.0, y := 0.0) -> void:
	assets.append([id, x, z, yaw, y])

func _place_assets(root: Node3D) -> void:
	var xf := CityLayout.bxf(h["b"])
	var f := Apartments.face_of(h)
	var basis := Basis(f[1], Vector3.UP, f[2])
	for item in assets:
		var scene := load("res://assets/models/home_%s.glb" % item[0]) as PackedScene
		var node := scene.instantiate() as Node3D
		node.transform = xf * Transform3D(basis, P(item[1], item[2], 0.02 + float(item[4]))) * Transform3D(Basis(Vector3.UP, item[3]), Vector3.ZERO)
		root.add_child(node)
		for child in node.find_children("*", "MeshInstance3D"):
			child.visibility_range_end = 120.0
			# The shell shapes the sunlight through the window; furniture
			# casting into the sun's cascades from 200 m away costs a pass each.
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _residence(tier: int, pal: Array) -> void:
	match tier:
		0:
			_studio(pal)
		1:
			_apartment(pal)
		2:
			_loft(pal)
		3:
			_sky(pal)
		_:
			_penthouse(pal)
	# Skirting all round (the window wall has its own reveals).
	var sk: Color = WALNUT if tier != 1 else CHALK.darkened(0.08)
	box(0.0, 0.1, 0.1, D, 0.0, 0.12, sk)
	box(W - 0.1, W, 0.1, D, 0.0, 0.12, sk)
	box(0.0, W, D - 0.1, D, 0.0, 0.12, sk)


# ------------------------------------------------------------- primitives
func ox0() -> float:
	return float(h["oa0"]) - float(h["a0"])


func ox1() -> float:
	return float(h["oa1"]) - float(h["a0"])


## A glowing box (lamp shades, screens, flames, backlights): unshaded.
func gbox(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, c: Color) -> void:
	var a := P(x0, z0, y0)
	var b := P(x1, z1, y1)
	var lo := a.min(b)
	var hi := a.max(b)
	glow.solid(lo.x, lo.z, hi.x, hi.z, lo.y, hi.y, c)


## A glass panel (transparent, shared material).
func pane(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float) -> void:
	var a := P(x0, z0, y0)
	var b := P(x1, z1, y1)
	var lo := a.min(b)
	var hi := a.max(b)
	glass.solid(lo.x, lo.z, hi.x, hi.z, lo.y, hi.y, Color(0.75, 0.85, 0.88))


## A quad with its winding fixed to face `n` (building frame).
func _q(target: BuildingMesher, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = d
		d = t
	target.quad(a, b, c, d, n, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col, BuildingMesher.KIND_TRIM, 0, 0)


## A round bar from a to b (room coords x, y, z with y up), capped.
func tube(a: Vector3, b: Vector3, r: float, c: Color, sides := 8, lit := false) -> void:
	var target := glow if lit else m
	var A := P(a.x, a.z, a.y)
	var B := P(b.x, b.z, b.y)
	var ax := (B - A).normalized()
	var u := ax.cross(Vector3.UP)
	if u.length() < 0.01:
		u = ax.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := ax.cross(u).normalized()
	for i in sides:
		var t0 := TAU * i / sides
		var t1 := TAU * (i + 1) / sides
		var o0 := (u * cos(t0) + v * sin(t0)) * r
		var o1 := (u * cos(t1) + v * sin(t1)) * r
		var n := (u * cos((t0 + t1) * 0.5) + v * sin((t0 + t1) * 0.5))
		_q(target, A + o0, A + o1, B + o1, B + o0, n, c)
		_q(target, A, A, A + o1, A + o0, -ax, c)
		_q(target, B, B, B + o0, B + o1, ax, c)


## A wheel/ring in the plane normal to `axis` (room coords).
func ring(centre: Vector3, axis: Vector3, r: float, thick: float, c: Color, segs := 14) -> void:
	var u := axis.cross(Vector3.UP)
	if u.length() < 0.01:
		u = axis.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := axis.cross(u).normalized()
	for i in segs:
		var p0 := centre + (u * cos(TAU * i / segs) + v * sin(TAU * i / segs)) * r
		var p1 := centre + (u * cos(TAU * (i + 1) / segs) + v * sin(TAU * (i + 1) / segs)) * r
		tube(p0, p1, thick, c, 5)


## A partition along x at depth z (x0..x1) with a door gap (d0..d1); collides.
func wall_x(z: float, x0: float, x1: float, d0: float, d1: float, c: Color) -> void:
	if d0 > x0:
		box(x0, d0, z, z + 0.14, 0.0, H, c, true)
	box(d0, d1, z, z + 0.14, 2.3, H, c, true)
	if d1 < x1:
		box(d1, x1, z, z + 0.14, 0.0, H, c, true)


## A partition along z at x (z0..z1) with a door gap (d0..d1); collides.
func wall_z(x: float, z0: float, z1: float, d0: float, d1: float, c: Color) -> void:
	if d0 > z0:
		box(x, x + 0.14, z0, d0, 0.0, H, c, true)
	box(x, x + 0.14, d0, d1, 2.3, H, c, true)
	if d1 < z1:
		box(x, x + 0.14, d1, z1, 0.0, H, c, true)


## Feature wall finish (home_wall.gdshader): side "back" (faces the window,
## at depth `at`), "left"/"right" (at x = `at`); a0..a1 along it.
func feature(side: String, at: float, a0: float, a1: float, y0: float, y1: float, style: int, tint: Color) -> void:
	walls_fx.append([side, at, a0, a1, y0, y1, style, tint])


## Your progress on a board (HomeBoard): side/at as feature(); centre along, y.
func board(side: String, at: float, along: float, y: float, width: float, frame: Color) -> void:
	boards.append([side, at, along, y, width])
	var hh := width * 0.42
	match side:
		"back":
			box(along - width * 0.5 - 0.06, along + width * 0.5 + 0.06, at - 0.04, at, y - hh * 0.5 - 0.06, y + hh * 0.5 + 0.06, frame)
		"left":
			box(at, at + 0.04, along - width * 0.5 - 0.06, along + width * 0.5 + 0.06, y - hh * 0.5 - 0.06, y + hh * 0.5 + 0.06, frame)
		_:
			box(at - 0.04, at, along - width * 0.5 - 0.06, along + width * 0.5 + 0.06, y - hh * 0.5 - 0.06, y + hh * 0.5 + 0.06, frame)


## Books on a shelf run (x0..x1 along x at depth z0..z1, or along z when vertical_z).
func books(x0: float, x1: float, z0: float, z1: float, y: float, seed: int, along_z := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cols := [Color(0.55, 0.16, 0.12), Color(0.15, 0.25, 0.4), Color(0.85, 0.8, 0.68), Color(0.2, 0.35, 0.28),
		Color(0.75, 0.55, 0.2), Color(0.12, 0.12, 0.13), Color(0.6, 0.6, 0.62)]
	var p := x0 if not along_z else z0
	var end := x1 if not along_z else z1
	while p < end - 0.05:
		var w := rng.randf_range(0.025, 0.06)
		var hgt := rng.randf_range(0.2, 0.3)
		if rng.randf() < 0.12:
			p += rng.randf_range(0.05, 0.15)  # a gap / an object
			continue
		var c: Color = cols[rng.randi() % cols.size()]
		if along_z:
			box(x0, x1, p, minf(p + w, end), y, y + hgt, c)
		else:
			box(p, minf(p + w, end), z0, z1, y, y + hgt, c)
		p += w + 0.004


func pendant(x: float, z: float, drop: float, shade: Color, r := 0.16) -> void:
	tube(Vector3(x, H, z), Vector3(x, H - drop, z), 0.008, STEEL, 4)
	tube(Vector3(x, H - drop, z), Vector3(x, H - drop - r * 1.2, z), r, shade, 10)
	gbox(x - r * 0.6, x + r * 0.6, z - r * 0.6, z + r * 0.6, H - drop - r * 1.25, H - drop - r * 1.15, Color(1.0, 0.86, 0.62))


func stool(x: float, z: float, top: Color, hgt := 0.72) -> void:
	tube(Vector3(x, 0.0, z), Vector3(x, hgt - 0.04, z), 0.025, STEEL, 6)
	tube(Vector3(x, 0.0, z), Vector3(x, 0.02, z), 0.18, STEEL, 10)
	tube(Vector3(x, hgt - 0.05, z), Vector3(x, hgt, z), 0.19, top, 12)


func plant_big(x: float, z: float, s := 1.0) -> void:
	tube(Vector3(x, 0.0, z), Vector3(x, 0.55 * s, z), 0.26 * s, Color(0.85, 0.83, 0.78), 10)
	var leaf := Color(0.12, 0.3, 0.15)
	for i in 7:
		var a := i * 2.4
		var tip := Vector3(x + cos(a) * 0.55 * s, (1.1 + 0.12 * (i % 3)) * s, z + sin(a) * 0.55 * s)
		tube(Vector3(x, 0.5 * s, z), tip, 0.05 * s, leaf, 5)
		tube(tip, tip + Vector3(cos(a) * 0.25, 0.12, sin(a) * 0.25) * s, 0.09 * s, leaf, 5)


# ---------------------------------------------------------------- homes
## Quay Studio: a courier's first place. One room, bed in the brick corner,
## a galley kitchen, a desk at the window, the bike on the wall, parcels by
## the door.
func _studio(pal: Array) -> void:
	feature("back", D, 0.0, W, 0.0, H, 0, Color(0.56, 0.3, 0.22))
	asset("bed", 1.15, D - 1.35)
	proxy(0.22, 2.08, D - 2.5, D - 0.2, 0.72)
	# Crate nightstand + lamp.
	box(2.2, 2.65, D - 0.62, D - 0.18, 0.0, 0.46, Color(0.58, 0.44, 0.28), true)
	tube(Vector3(2.42, 0.46, D - 0.4), Vector3(2.42, 0.78, D - 0.4), 0.02, STEEL, 5)
	gbox(2.3, 2.54, D - 0.52, D - 0.28, 0.78, 0.96, Color(1.0, 0.8, 0.52))
	# Clothes rail: the work kit (hoodies, a high-vis vest).
	for x: float in [2.95, 4.45]:
		tube(Vector3(x, 0.0, D - 0.35), Vector3(x, 1.7, D - 0.35), 0.018, STEEL, 5)
	tube(Vector3(2.95, 1.7, D - 0.35), Vector3(4.45, 1.7, D - 0.35), 0.016, STEEL, 5)
	var kit := [Color(0.12, 0.12, 0.14), Color(0.2, 0.22, 0.26), Color(0.95, 0.75, 0.1), Color(0.7, 0.18, 0.14), Color(0.3, 0.32, 0.36)]
	for i in 5:
		var x := 3.1 + i * 0.26
		box(x, x + 0.2, D - 0.55, D - 0.16, 0.95, 1.62, kit[i])
	# Galley kitchen on the right wall: sage cabinets, butcher block, fridge, shelf.
	var sage := Color(0.4, 0.5, 0.43)
	box(W - 0.62, W - 0.04, 3.0, D - 0.12, 0.1, 0.88, sage, true)
	box(W - 0.66, W - 0.02, 2.96, D - 0.08, 0.88, 0.93, Color(0.66, 0.47, 0.28))
	for i in range(int((D - 3.1) / 0.6)):
		var z := 3.05 + i * 0.6
		box(W - 0.64, W - 0.62, z + 0.03, z + 0.56, 0.16, 0.84, sage.darkened(0.15))
		box(W - 0.66, W - 0.64, z + 0.22, z + 0.36, 0.74, 0.76, BRASS)
	box(W - 0.6, W - 0.2, 4.4, 4.95, 0.93, 0.945, FRAME)  # hob
	tube(Vector3(W - 0.3, 0.93, 5.6), Vector3(W - 0.3, 1.13, 5.6), 0.07, Color(0.85, 0.2, 0.15), 8)  # kettle
	box(W - 0.66, W - 0.04, 2.15, 2.9, 0.0, 1.92, CHALK, true)  # fridge
	box(W - 0.68, W - 0.66, 2.25, 2.3, 1.0, 1.6, STEEL)
	box(W - 0.32, W - 0.04, 3.2, D - 0.3, 1.55, 1.58, OAK)  # open shelf + jars
	for i in 7:
		var z := 3.35 + i * 0.5
		tube(Vector3(W - 0.18, 1.58, z), Vector3(W - 0.18, 1.74 + 0.04 * (i % 3), z), 0.06,
			[Color(0.9, 0.85, 0.7), Color(0.5, 0.3, 0.15), Color(0.85, 0.85, 0.85)][i % 3], 8)
	# Desk at the window (left of the opening): laptop glowing, chair.
	box(0.12, 1.6, 0.45, 1.15, 0.72, 0.76, OAK, true)
	for x: float in [0.18, 1.54]:
		for z: float in [0.5, 1.1]:
			tube(Vector3(x, 0.0, z), Vector3(x, 0.72, z), 0.022, STEEL, 5)
	box(0.55, 0.95, 0.6, 0.88, 0.76, 0.78, Color(0.2, 0.2, 0.22))
	gbox(0.56, 0.94, 0.58, 0.6, 0.78, 1.02, Color(0.55, 0.75, 1.0))
	tube(Vector3(1.3, 0.76, 0.75), Vector3(1.3, 0.86, 0.75), 0.045, Color(0.9, 0.9, 0.88), 8)  # mug
	asset("chair", 0.85, 1.6)
	# The bike on the left wall: wheels, frame, bars, saddle.
	var wy := 1.45
	ring(Vector3(0.2, wy, 3.25), Vector3.RIGHT, 0.34, 0.018, STEEL)
	ring(Vector3(0.2, wy, 4.35), Vector3.RIGHT, 0.34, 0.018, STEEL)
	var orange := Color(0.92, 0.45, 0.12)
	tube(Vector3(0.2, wy, 3.25), Vector3(0.2, wy + 0.38, 3.75), 0.02, orange, 5)
	tube(Vector3(0.2, wy + 0.38, 3.75), Vector3(0.2, wy, 4.35), 0.02, orange, 5)
	tube(Vector3(0.2, wy + 0.38, 3.75), Vector3(0.2, wy + 0.42, 4.1), 0.02, orange, 5)
	tube(Vector3(0.2, wy + 0.42, 4.1), Vector3(0.2, wy, 4.35), 0.02, orange, 5)
	tube(Vector3(0.2, wy, 3.25), Vector3(0.2, wy + 0.5, 3.35), 0.018, orange, 5)
	tube(Vector3(0.08, wy + 0.5, 3.35), Vector3(0.36, wy + 0.5, 3.35), 0.014, STEEL, 5)
	box(0.15, 0.25, 4.0, 4.2, wy + 0.48, wy + 0.52, STEEL)
	box(0.02, 0.06, 3.7, 3.8, wy + 0.1, wy + 0.5, STEEL)  # wall hook
	# Parcels stacked by the door (front right, clear of the window).
	var card := Color(0.66, 0.5, 0.32)
	box(W - 1.7, W - 1.1, 0.3, 0.85, 0.0, 0.42, card, true)
	box(W - 1.62, W - 1.18, 0.38, 0.78, 0.42, 0.68, card.lightened(0.1))
	box(W - 1.0, W - 0.25, 0.3, 0.95, 0.0, 0.3, card.darkened(0.1), true)
	box(W - 0.9, W - 0.4, 0.4, 0.8, 0.3, 0.5, card)
	# Rug, beanbag, posters.
	_rug(2.3, 5.5, 3.2, 5.6, Color(0.8, 0.58, 0.2))
	tube(Vector3(W - 1.6, 0.0, 4.3), Vector3(W - 1.6, 0.42, 4.3), 0.42, Color(0.2, 0.34, 0.42), 12)
	for i in 3:
		var z := 5.0 + i * 0.62
		box(0.02, 0.04, z, z + 0.48, 1.55, 2.2, [Color(0.95, 0.3, 0.2), Color(0.15, 0.6, 0.62), Color(0.95, 0.78, 0.2)][i])
	board("left", 0.02, 1.0, 1.65, 1.0, Color(0.6, 0.45, 0.3))
	pendant(W * 0.5, D * 0.55, 0.7, Color(0.95, 0.92, 0.85), 0.07)
	lights.append([Vector3(W * 0.5, H - 0.9, D * 0.55), Color(1.0, 0.8, 0.58), 1.3, 6.5])
	lights.append([Vector3(2.42, 1.2, D - 0.6), Color(1.0, 0.75, 0.5), 0.6, 3.0])
	lights.append([Vector3(0.9, 1.3, 1.0), Color(0.75, 0.85, 1.0), 0.35, 2.5])


## City Apartment: a bright one-bedroom – pale oak parquet, white walls, a
## wall of books, a breakfast bar, a proper bedroom and bathroom.
func _apartment(pal: Array) -> void:
	var wall: Color = pal[0]
	var split := D * 0.6
	var left := W * 0.36
	var right := W * 0.7
	wall_x(split, 0.0, left + 0.16, left - 1.3, left - 0.1, wall)
	box(left, left + 0.16, split, D, 0.0, H, wall, true)
	wall_x(split, right, W, right + 0.1, right + 1.3, wall)
	box(right, right + 0.16, split, D, 0.0, H, wall, true)
	feature("back", split - 0.002, 0.0, left + 0.16, 0.0, H, 4, Color(0.55, 0.62, 0.58))
	# Bedroom: bed, bedside lamps, wardrobe.
	asset("bed", left * 0.5, D - 1.4)
	proxy(left * 0.5 - 0.93, left * 0.5 + 0.93, D - 2.55, D - 0.25, 0.72)
	for x: float in [left * 0.5 - 1.3, left * 0.5 + 1.3]:
		box(x - 0.22, x + 0.22, D - 0.55, D - 0.15, 0.0, 0.5, OAK)
		gbox(x - 0.1, x + 0.1, D - 0.45, D - 0.25, 0.5, 0.75, Color(1.0, 0.85, 0.62))
	box(0.12, 0.72, split + 0.4, D - 2.7, 0.0, 2.3, CHALK, true)
	# Bathroom: vanity, toilet, a glass shower.
	asset("vanity", W - 0.72, D - 0.65)
	asset("toilet", right + 0.7, D - 0.65)
	box(right + 0.2, W - 0.2, split + 0.3, D - 0.1, 0.012, 0.026, STONE)
	pane(W - 1.4, W - 1.38, split + 0.3, split + 1.5, 0.0, 2.1)
	box(W - 1.3, W - 0.2, split + 0.3, split + 1.4, 0.03, 0.08, Color(0.55, 0.6, 0.58))
	# Living: sofa facing the view, coffee table, rug, arc lamp.
	asset("sofa", 1.9, split - 1.0)
	asset("coffee", 1.9, split - 2.5)
	proxy(0.5, 3.3, split - 1.5, split - 0.5, 0.85)
	_rug(0.4, 3.5, split - 3.6, split - 0.4, Color(0.82, 0.78, 0.7))
	tube(Vector3(3.6, 0.0, split - 0.6), Vector3(3.6, 1.9, split - 0.6), 0.02, BRASS, 6)
	tube(Vector3(3.6, 1.9, split - 0.6), Vector3(2.6, 2.1, split - 1.5), 0.018, BRASS, 6)
	gbox(2.45, 2.75, split - 1.65, split - 1.35, 1.9, 2.05, Color(1.0, 0.87, 0.65))
	# A wall of books on the left, by the window.
	box(0.05, 0.4, 0.4, split - 3.9, 0.0, 2.4, CHALK, true)
	for i in 5:
		var y := 0.1 + i * 0.47
		box(0.05, 0.4, 0.4, split - 3.9, y, y + 0.03, CHALK.darkened(0.06))
		books(0.08, 0.36, 0.45, split - 3.95, y + 0.03, 101 + i, true)
	# Kitchen along the right wall + a breakfast bar with stools.
	var white := Color(0.95, 0.95, 0.93)
	box(W - 0.62, W - 0.04, 1.0, split - 0.3, 0.1, 0.88, white, true)
	box(W - 0.66, W - 0.02, 0.96, split - 0.26, 0.88, 0.93, OAK)
	box(W - 0.38, W - 0.04, 1.0, split - 0.3, 1.5, 2.25, white)  # wall units
	for i in range(int((split - 1.3) / 0.6)):
		var z := 1.05 + i * 0.6
		box(W - 0.64, W - 0.62, z + 0.03, z + 0.56, 0.16, 0.84, white.darkened(0.06))
		box(W - 0.4, W - 0.38, z + 0.03, z + 0.56, 1.52, 2.23, white.darkened(0.06))
	box(W - 0.6, W - 0.2, 3.0, 3.6, 0.93, 0.945, FRAME)
	box(W - 2.9, W - 0.62, 3.3, 3.9, 0.0, 0.9, white, true)
	box(W - 2.95, W - 0.62, 3.25, 3.95, 0.9, 0.95, OAK)
	for x: float in [W - 2.5, W - 1.8, W - 1.1]:
		stool(x, 4.35, OAK)
	pendant(W - 1.8, 3.6, 0.9, Color(0.9, 0.85, 0.75), 0.14)
	# Round dining table for four in the window corner.
	var dx := W - 2.0
	var dz := 1.5
	tube(Vector3(dx, 0.0, dz), Vector3(dx, 0.72, dz), 0.06, STEEL, 8)
	tube(Vector3(dx, 0.72, dz), Vector3(dx, 0.76, dz), 0.55, OAK, 18)
	proxy(dx - 0.55, dx + 0.55, dz - 0.55, dz + 0.55, 0.76)
	asset("chair", dx - 0.85, dz, PI * 0.5)
	asset("chair", dx + 0.85, dz, -PI * 0.5)
	plant_big(0.6, split - 0.6)
	board("back", split, left * 0.5 + 0.2, 1.7, 1.2, OAK)
	lights.append([Vector3(W * 0.3, H - 0.4, split * 0.5), Color(1.0, 0.9, 0.78), 1.1, 6.0])
	lights.append([Vector3(W - 1.8, H - 1.2, 3.6), Color(1.0, 0.86, 0.66), 0.9, 4.5])
	lights.append([Vector3(left * 0.5, H - 0.4, D - 1.8), Color(1.0, 0.85, 0.65), 0.9, 4.5])
	lights.append([Vector3(W - 1.4, H - 0.3, D - 1.6), Color(1.0, 0.95, 0.9), 0.6, 3.5])


## High-Rise Loft: industrial open plan – polished concrete, brick, steel
## beams and ducts, a glass-walled bedroom on a plinth, a big kitchen island,
## a training corner and a neon sign.
func _loft(pal: Array) -> void:
	var brick := Color(0.5, 0.27, 0.2)
	feature("back", D, 0.0, W, 0.0, H, 0, brick)
	feature("left", 0.0, 0.0, D, 0.0, H, 0, brick)
	feature("right", W, 0.0, D, 0.0, H, 3, Color(0.64, 0.63, 0.6))
	# Steel beams across, ducts along the back.
	for x: float in [W * 0.25, W * 0.5, W * 0.75]:
		box(x - 0.12, x + 0.12, 0.2, D, H - 0.42, H - 0.02, STEEL)
	var duct := Color(0.68, 0.7, 0.72)
	tube(Vector3(0.3, H - 0.62, D - 1.0), Vector3(W - 0.3, H - 0.62, D - 1.0), 0.26, duct, 12)
	tube(Vector3(W * 0.35, H - 0.62, D - 1.0), Vector3(W * 0.35, H - 0.62, 2.0), 0.18, duct, 10)
	tube(Vector3(W * 0.7, H - 0.62, D - 1.0), Vector3(W * 0.7, H - 0.62, 2.5), 0.18, duct, 10)
	tube(Vector3(0.25, 0.0, D - 0.3), Vector3(0.25, H, D - 0.3), 0.06, Color(0.55, 0.15, 0.1), 8)  # sprinkler riser
	# Kitchen: black run along the back wall, open steel shelving, island.
	var black := Color(0.11, 0.11, 0.12)
	var conc := Color(0.6, 0.6, 0.58)
	box(0.3, 5.6, D - 0.66, D - 0.05, 0.1, 0.9, black, true)
	box(0.26, 5.64, D - 0.7, D - 0.02, 0.9, 0.96, conc)
	for x: float in [0.4, 2.0, 3.6, 5.2]:
		tube(Vector3(x, 1.4, D - 0.05), Vector3(x, 2.6, D - 0.05), 0.012, STEEL, 4)
	for y: float in [1.5, 2.05]:
		box(0.3, 5.6, D - 0.34, D - 0.04, y, y + 0.04, OAK)
		books(0.6, 1.6, D - 0.3, D - 0.08, y + 0.04, int(y * 10.0))
		for i in 6:
			var x := 2.0 + i * 0.55
			tube(Vector3(x, y + 0.04, D - 0.2), Vector3(x, y + 0.2 + 0.06 * (i % 2), D - 0.2), 0.07,
				[CHALK, Color(0.3, 0.32, 0.35), Color(0.75, 0.6, 0.4)][i % 3], 8)
	box(1.3, 4.7, D - 3.3, D - 2.3, 0.0, 0.9, WALNUT, true)
	box(1.25, 4.75, D - 3.35, D - 2.25, 0.9, 0.97, conc)
	for x: float in [1.8, 3.0, 4.2]:
		stool(x, D - 3.75, black)
		pendant(x, D - 2.8, 1.5, black, 0.13)
	# Bedroom on a plinth behind steel-framed glass.
	var bz := D - 4.4
	box(W - 5.1, W - 0.15, bz, D - 0.12, 0.0, 0.3, conc.darkened(0.15), true)
	asset("bed", W - 2.6, D - 1.4, 0.0, 0.3)
	proxy(W - 3.55, W - 1.65, D - 2.55, D - 0.25, 1.02)
	var px := W - 5.25
	box(px, px + 0.06, bz - 0.06, D - 0.12, 0.0, H, STEEL, true)  # side post (left of the suite)
	var x := px + 1.1
	box(px, W - 0.15, bz - 0.06, bz, 2.4, 2.46, STEEL)  # transom
	pane(x, W - 0.15, bz - 0.04, bz - 0.02, 0.3, 2.4)
	while x < W - 0.2:
		box(x, x + 0.05, bz - 0.06, bz, 0.0, H, STEEL)
		x += 1.2
	col_boxes.append(AABB(P(px + 1.1, bz - 0.06, 0.0).min(P(W - 0.15, bz, H)), (P(px + 1.1, bz - 0.06, 0.0) - P(W - 0.15, bz, H)).abs()))
	# Training corner (front left, clear of the opening): bag, pull-up bar, bench.
	tube(Vector3(1.3, H, 4.0), Vector3(1.3, 2.1, 4.0), 0.01, STEEL, 4)
	tube(Vector3(1.3, 0.9, 4.0), Vector3(1.3, 2.1, 4.0), 0.2, Color(0.55, 0.1, 0.08), 12)
	tube(Vector3(0.05, 2.35, 2.6), Vector3(1.2, 2.35, 2.6), 0.018, STEEL, 6)
	box(0.0, 0.08, 2.5, 2.7, 2.2, 2.5, STEEL)
	box(0.55, 0.95, 5.2, 6.5, 0.0, 0.45, black, true)
	for z: float in [5.6, 6.1]:
		tube(Vector3(0.45, 0.62, z), Vector3(1.05, 0.62, z), 0.02, STEEL, 5)
		for xx: float in [0.48, 1.02]:
			tube(Vector3(xx - 0.03, 0.62, z), Vector3(xx + 0.03, 0.62, z), 0.12, black, 10)
	_rug(0.3, 2.6, 3.0, 7.0, Color(0.2, 0.2, 0.22))
	# Lounge: sofa to the view, a second one alongside, coffee table, big rug.
	asset("sofa", W - 4.6, 6.4)
	asset("coffee", W - 4.6, 4.9)
	proxy(W - 6.0, W - 3.2, 5.9, 6.9, 0.85)
	_rug(W - 7.2, W - 2.0, 3.6, 7.2, Color(0.72, 0.35, 0.2))
	plant_big(W - 1.2, 1.2, 1.2)
	plant_big(1.0, 1.0, 1.0)
	board("right", W - 0.02, 5.4, 1.75, 1.4, STEEL)
	lights.append([Vector3(3.0, H - 1.9, D - 2.8), Color(1.0, 0.78, 0.5), 1.4, 6.5])
	lights.append([Vector3(W - 4.6, H - 0.8, 5.0), Color(1.0, 0.86, 0.68), 1.2, 7.5])
	lights.append([Vector3(W - 2.6, H - 1.2, D - 2.0), Color(1.0, 0.8, 0.6), 0.8, 5.0])
	lights.append([Vector3(1.0, 3.2, 4.4), Color(1.0, 0.35, 0.55), 0.7, 4.0])  # neon spill


## Sky Apartment: contemporary luxury – marble floors, walnut slat wall
## with a linear fire, grand piano at the glass, a dining table for eight
## under a ring chandelier, a backlit wine wall and a master suite.
func _sky(pal: Array) -> void:
	var wall: Color = pal[0]
	feature("left", 0.0, 0.3, D - 0.2, 0.0, H, 1, Color(0.36, 0.22, 0.13))
	var sz := D - 5.0
	var sx := W * 0.52
	wall_x(sz, sx, W, sx + 0.4, sx + 1.6, wall)
	feature("back", sz, sx + 1.6, W, 0.0, H, 2, Color(0.9, 0.89, 0.87))
	# Linear fireplace set into the slat wall.
	box(0.0, 0.5, 5.0, 8.6, 0.0, 1.5, Color(0.15, 0.15, 0.16), true)
	box(0.48, 0.5, 5.3, 8.3, 0.42, 0.82, Color(0.05, 0.05, 0.05))
	gbox(0.44, 0.47, 5.4, 8.2, 0.44, 0.58, Color(1.0, 0.55, 0.18))
	gbox(0.44, 0.46, 5.6, 8.0, 0.58, 0.68, Color(1.0, 0.75, 0.3))
	box(0.0, 0.62, 4.9, 8.7, 1.5, 1.56, Color(0.85, 0.83, 0.78))
	# Sofas round the fire; rug; lamp.
	asset("sofa", 3.3, 6.8, PI * 0.5)
	asset("coffee", 1.85, 6.8)
	proxy(2.8, 3.8, 5.4, 8.2, 0.85)
	asset("sofa", 5.0, 9.4, PI)
	_rug(1.0, 6.4, 4.6, 9.0, Color(0.82, 0.8, 0.76))
	tube(Vector3(5.6, 0.0, 5.0), Vector3(5.6, 1.5, 5.0), 0.015, BRASS, 6)
	gbox(5.45, 5.75, 4.85, 5.15, 1.5, 1.72, Color(1.0, 0.9, 0.72))
	# Grand piano at the glass, left of the opening.
	var lacquer := Color(0.03, 0.03, 0.035)
	box(0.6, 2.2, 0.7, 2.7, 0.66, 0.98, lacquer, true)
	box(0.6, 1.3, 2.7, 3.1, 0.66, 0.98, lacquer, true)
	box(0.6, 2.2, 2.75, 2.95, 0.72, 0.76, CHALK)  # keys
	_q(m, P(0.62, 0.75, 1.0), P(2.18, 0.75, 1.0), P(2.18, 0.9, 1.75), P(0.62, 0.9, 1.75), Vector3.UP, lacquer)
	for p in [Vector2(0.75, 0.9), Vector2(2.05, 0.9), Vector2(1.4, 2.6)]:
		tube(Vector3(p.x, 0.0, p.y), Vector3(p.x, 0.66, p.y), 0.05, lacquer, 6)
	box(0.9, 1.9, 3.3, 3.65, 0.0, 0.48, lacquer)
	# Dining for eight under a ring chandelier (back left).
	asset("dining", 2.6, D - 2.6)
	asset("dining", 4.8, D - 2.6)
	proxy(1.5, 5.9, D - 3.1, D - 2.1, 0.8)
	for dx: float in [1.9, 3.2, 4.4, 5.6]:
		asset("chair", dx, D - 3.4, PI)
		asset("chair", dx, D - 1.8)
	for i in 16:
		var a := TAU * i / 16.0
		var c := Vector3(3.7 + cos(a) * 1.0, H - 1.1, D - 2.6 + sin(a) * 0.55)
		gbox(c.x - 0.05, c.x + 0.05, c.z - 0.05, c.z + 0.05, c.y - 0.03, c.y + 0.03, Color(1.0, 0.88, 0.66))
	tube(Vector3(3.7, H, D - 2.6), Vector3(3.7, H - 1.1, D - 2.6), 0.01, BRASS, 4)
	# Wine wall by the window, right of the opening.
	box(W - 0.6, W - 0.05, 0.5, 3.6, 0.0, 2.7, WALNUT, true)
	gbox(W - 0.62, W - 0.6, 0.6, 3.5, 0.15, 2.55, Color(1.0, 0.68, 0.32))
	for r in 6:
		var y := 0.3 + r * 0.38
		for i in 9:
			var z := 0.75 + i * 0.32
			tube(Vector3(W - 0.64, y, z), Vector3(W - 0.72, y, z), 0.04, Color(0.12, 0.05, 0.06), 6)
	# Kitchen: marble island and a run along the right wall.
	box(W - 0.62, W - 0.04, 4.1, sz - 0.2, 0.1, 0.9, CHALK, true)
	box(W - 0.66, W - 0.02, 4.05, sz - 0.16, 0.9, 0.96, STONE)
	box(W - 4.6, W - 1.7, 5.4, 6.4, 0.0, 0.9, CHALK, true)
	box(W - 4.7, W - 1.6, 5.3, 6.5, 0.9, 0.96, Color(0.93, 0.92, 0.9))
	for x: float in [W - 4.0, W - 3.1, W - 2.2]:
		stool(x, 6.9, WALNUT)
		pendant(x, 5.9, 1.3, BRASS, 0.12)
	# Master suite: bed, a freestanding tub behind glass, walk-in wardrobe.
	asset("bed", W - 3.0, D - 1.4)
	proxy(W - 3.95, W - 2.05, D - 2.55, D - 0.25, 0.72)
	tube(Vector3(sx + 2.0, 0.0, D - 1.6), Vector3(sx + 2.0, 0.58, D - 1.6), 0.62, CHALK, 16)
	tube(Vector3(sx + 2.0, 0.5, D - 1.6), Vector3(sx + 2.0, 0.56, D - 1.6), 0.54, Color(0.6, 0.78, 0.82), 16)
	pane(sx + 3.2, sx + 3.22, sz + 0.2, D - 0.2, 0.0, 2.2)
	box(sx + 0.2, sx + 0.8, sz + 0.4, sz + 2.6, 0.0, 2.4, WALNUT, true)
	# Sculpture on a plinth at the right corner of the glass.
	box(W - 1.6, W - 1.0, 0.8, 1.4, 0.0, 0.9, STONE, true)
	tube(Vector3(W - 1.3, 0.9, 1.1), Vector3(W - 1.3, 1.3, 1.1), 0.2, BRASS, 10)
	tube(Vector3(W - 1.3, 1.3, 1.1), Vector3(W - 1.2, 1.7, 1.15), 0.12, BRASS, 10)
	plant_big(sx + 1.2, 1.0, 1.3)
	board("back", sz, sx + 4.4, 1.75, 1.6, BRASS)
	lights.append([Vector3(3.7, H - 1.4, D - 2.6), Color(1.0, 0.85, 0.65), 1.3, 7.0])
	lights.append([Vector3(1.2, 1.1, 6.8), Color(1.0, 0.6, 0.3), 1.0, 5.0])
	lights.append([Vector3(W - 3.1, H - 1.4, 5.9), Color(1.0, 0.88, 0.7), 1.1, 6.5])
	lights.append([Vector3(W - 3.0, H - 0.5, D - 2.0), Color(1.0, 0.85, 0.68), 0.9, 6.0])
	lights.append([Vector3(W - 1.0, 1.4, 2.0), Color(1.0, 0.65, 0.3), 0.6, 3.0])


## Ultimate Penthouse: dark stone and brass under a walnut ceiling; a plunge
## pool along the glass, a mezzanine (real stairs – you can climb it) with
## the Hall of Fame wall, a backlit bar beneath it, a dining table for ten
## and a sunken-feeling lounge facing the whole skyline.
func _penthouse(pal: Array) -> void:
	feature("back", D, 0.0, W, 0.0, H, 1, Color(0.32, 0.2, 0.12))
	feature("right", W, 0.0, D, 0.0, H, 2, Color(0.3, 0.3, 0.31))
	feature("left", 0.0, 0.0, D, 0.0, H, 3, Color(0.45, 0.44, 0.42))
	# Brass cove lines in the ceiling.
	gbox(1.0, W - 1.0, 1.2, 1.26, H - 0.04, H - 0.01, Color(1.0, 0.78, 0.45))
	gbox(1.0, W - 1.0, D - 4.0, D - 3.94, H - 0.04, H - 0.01, Color(1.0, 0.78, 0.45))
	# Mezzanine across the back (walkable) with a glass balustrade, reached by
	# floating stairs along the left wall.
	var mz := D - 3.4
	var my := 2.7
	box(0.3, W - 0.2, mz, D - 0.08, my, my + 0.25, Color(0.16, 0.16, 0.17), true)
	box(0.3, W - 0.2, mz - 0.05, mz, my - 0.02, my + 0.27, BRASS)
	pane(1.8, W - 0.2, mz + 0.02, mz + 0.06, my + 0.25, my + 1.25)
	col_boxes.append(AABB(P(1.8, mz + 0.02, my).min(P(W - 0.2, mz + 0.06, my + 1.25)), (P(1.8, mz + 0.02, my) - P(W - 0.2, mz + 0.06, my + 1.25)).abs()))
	tube(Vector3(1.8, my + 1.25, mz + 0.04), Vector3(W - 0.2, my + 1.25, mz + 0.04), 0.03, BRASS, 6)
	var steps := 9
	var rise := my / steps
	for i in steps:
		var z0 := mz - (steps - i) * 0.42
		var top := (i + 1) * rise
		box(0.35, 1.7, z0, z0 + 0.42, top - 0.07, top, WALNUT)
		var lo := P(0.35, z0, 0.0)
		var hi := P(1.7, z0 + 0.42, top)
		col_boxes.append(AABB(lo.min(hi), (hi - lo).abs()))
	box(0.32, 0.4, mz - steps * 0.42, mz, 0.0, my, STEEL)  # stringer against the wall
	# Up there: study desk, bookcases and the Hall of Fame wall.
	board("back", D - 0.02, W * 0.5, my + 1.45, 3.2, BRASS)
	for x: float in [W * 0.5 - 3.4, W * 0.5 + 2.2]:
		box(x, x + 1.2, D - 0.42, D - 0.08, my + 0.25, H - 0.2, WALNUT)
		for k in 4:
			var y := my + 0.35 + k * 0.5
			box(x, x + 1.2, D - 0.42, D - 0.08, y, y + 0.025, WALNUT.darkened(0.2))
			books(x + 0.04, x + 1.16, D - 0.38, D - 0.12, y + 0.025, int(x * 10.0) + k)
	box(W - 6.0, W - 4.2, D - 1.6, D - 0.9, my + 0.95, my + 1.0, WALNUT, true)
	asset("chair", W - 5.1, D - 2.0, 0.0)
	# Under the mezzanine: a backlit bar (left), the master bed (right).
	box(4.0, 10.5, D - 2.4, D - 1.7, 0.0, 1.08, Color(0.12, 0.12, 0.13), true)
	box(3.95, 10.55, D - 2.45, D - 1.65, 1.08, 1.14, BRASS)
	gbox(4.2, 10.3, D - 0.12, D - 0.1, 0.9, 2.4, Color(1.0, 0.7, 0.38))
	for y: float in [1.2, 1.75]:
		box(4.2, 10.3, D - 0.4, D - 0.12, y, y + 0.03, Color(0.15, 0.15, 0.16))
		for i in 18:
			var bx := 4.4 + i * 0.33
			tube(Vector3(bx, y + 0.03, D - 0.26), Vector3(bx, y + 0.3 + 0.05 * (i % 3), D - 0.26), 0.035,
				[Color(0.3, 0.12, 0.06), Color(0.15, 0.25, 0.12), Color(0.8, 0.75, 0.6)][i % 3], 6)
	for x: float in [5.0, 6.5, 8.0, 9.5]:
		stool(x, D - 2.9, Color(0.5, 0.36, 0.22), 0.78)
	asset("bed", W - 3.2, D - 1.4)
	proxy(W - 4.15, W - 2.25, D - 2.55, D - 0.25, 0.72)
	for x: float in [W - 5.0, W - 1.4]:
		box(x - 0.3, x + 0.3, D - 0.55, D - 0.12, 0.0, 0.5, WALNUT)
		gbox(x - 0.12, x + 0.12, D - 0.45, D - 0.21, 0.5, 0.82, Color(1.0, 0.85, 0.62))
	for z in range(int(mz + 0.2), int(D)):
		box(W - 6.4, W - 6.34, float(z), float(z) + 0.06, 0.0, my, BRASS)  # slat screen
	# Plunge pool along the glass, left of the runway.
	var pool := [2.6, 8.6, 3.2, 9.6]
	var cope := Color(0.78, 0.76, 0.7)
	box(pool[0] - 0.3, pool[1] + 0.3, pool[2] - 0.3, pool[2], 0.0, 0.5, cope, true)
	box(pool[0] - 0.3, pool[1] + 0.3, pool[3], pool[3] + 0.3, 0.0, 0.5, cope, true)
	box(pool[0] - 0.3, pool[0], pool[2], pool[3], 0.0, 0.5, cope, true)
	box(pool[1], pool[1] + 0.3, pool[2], pool[3], 0.0, 0.5, cope, true)
	pools.append([pool[0], pool[1], pool[2], pool[3], 0.42])
	for z: float in [4.2, 6.2]:
		box(9.3, 9.95, z, z + 1.7, 0.0, 0.32, Color(0.9, 0.88, 0.84), true)
		_q(m, P(9.3, z + 1.2, 0.32), P(9.95, z + 1.2, 0.32), P(9.95, z + 1.75, 0.8), P(9.3, z + 1.75, 0.8), Vector3.UP, Color(0.9, 0.88, 0.84))
	# Lounge facing the skyline (right of the runway).
	asset("sofa", 17.0, 9.0)
	asset("sofa", 14.6, 7.0, -PI * 0.5)
	asset("sofa", 19.4, 7.0, PI * 0.5)
	asset("coffee", 17.0, 7.0)
	proxy(15.6, 18.4, 8.5, 9.5, 0.85)
	_rug(14.0, 20.0, 4.6, 10.0, Color(0.55, 0.5, 0.42))
	# Dining for ten (back right, before the mezzanine) under a chandelier.
	asset("dining", 18.4, 12.6)
	asset("dining", 20.6, 12.6)
	proxy(17.3, 21.7, 12.1, 13.1, 0.8)
	for dx: float in [17.6, 18.9, 20.1, 21.4]:
		asset("chair", dx, 11.8, PI)
		asset("chair", dx, 13.4)
	for i in 20:
		var a := TAU * i / 20.0
		var c := Vector3(19.5 + cos(a) * 1.3, H - 1.6 - 0.15 * (i % 2), 12.6 + sin(a) * 0.6)
		gbox(c.x - 0.05, c.x + 0.05, c.z - 0.05, c.z + 0.05, c.y - 0.04, c.y + 0.04, Color(1.0, 0.86, 0.6))
	# Telescope and sculpture at the corners of the glass.
	for k in 3:
		var ang := TAU * k / 3.0
		tube(Vector3(W - 1.0 + cos(ang) * 0.45, 0.0, 1.1 + sin(ang) * 0.45), Vector3(W - 1.0, 1.15, 1.1), 0.015, BRASS, 4)
	tube(Vector3(W - 1.3, 1.1, 1.4), Vector3(W - 0.7, 1.45, 0.7), 0.075, BRASS, 10)
	box(0.5, 1.4, 0.6, 1.5, 0.0, 1.0, STONE, true)
	ring(Vector3(0.95, 1.65, 1.05), Vector3.FORWARD, 0.55, 0.06, BRASS, 20)
	# A big canvas on the marble wall.
	box(W - 0.06, W - 0.02, 3.4, 8.6, 1.3, 3.8, Color(0.08, 0.07, 0.07))
	box(W - 0.07, W - 0.06, 3.5, 6.0, 1.4, 3.7, Color(0.85, 0.4, 0.18))
	box(W - 0.07, W - 0.06, 6.0, 8.5, 1.4, 3.7, Color(0.15, 0.2, 0.35))
	plant_big(1.2, 11.2, 1.4)
	plant_big(W - 1.0, 10.5, 1.4)
	lights.append([Vector3(19.5, H - 2.0, 12.6), Color(1.0, 0.84, 0.62), 1.4, 8.0])
	lights.append([Vector3(5.6, 0.6, 6.4), Color(0.45, 0.85, 1.0), 1.2, 6.0])
	lights.append([Vector3(17.0, H - 1.0, 7.0), Color(1.0, 0.86, 0.68), 1.3, 9.0])
	lights.append([Vector3(7.2, 1.6, D - 1.2), Color(1.0, 0.7, 0.4), 0.9, 5.0])
	lights.append([Vector3(W * 0.5, my + 2.0, D - 1.6), Color(1.0, 0.86, 0.68), 1.0, 8.0])

func proxy(x0: float, x1: float, z0: float, z1: float, height: float) -> void:
	var a := P(x0, z0, 0.0)
	var b := P(x1, z1, height)
	col_boxes.append(AABB(a.min(b), a.max(b) - a.min(b)))
