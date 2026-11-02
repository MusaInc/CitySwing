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
const MEZZ := 3.4  # penthouse mezzanine deck (underside), m above the floor
const DOOR_H := 2.9  # tall openings: the follow camera looks through them over the hero
const WIN_Z := 0.3  # the window wall's inner face, m in from the facade
const SW := 2.4  # penthouse stair width (from the wall at 0.35)
## Per tier: wall, floor tint, ceiling colours, floor style (home_floor.gdshader).
const PALETTE := [
	[Color(0.86, 0.8, 0.7), Color(0.6, 0.42, 0.26), Color(0.9, 0.88, 0.84), 0],
	[Color(0.93, 0.92, 0.89), Color(0.74, 0.59, 0.42), Color(0.95, 0.95, 0.93), 3],
	[Color(0.7, 0.69, 0.66), Color(0.56, 0.56, 0.55), Color(0.27, 0.27, 0.29), 1],
	[Color(0.82, 0.78, 0.72), Color(0.8, 0.78, 0.74), Color(0.86, 0.84, 0.8), 2],
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
var trophy_spec: Array = []        # [x0, x1, z, y, inward]: the trophy shelf (room coords)
var spot_list: Array = []          # [kind, x, z, y]: things to use (room coords)
## Things to use in each built home, world positions: id -> [{kind, pos}].
static var spots := {}
var ramps: Array = []             # [Transform3D, size] (local frame): stair slopes to walk up
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
	var root: Node3D = _LIGHTS.new()
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
		for rp in ramps:
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = rp[1]
			cs.shape = sh
			cs.transform = xf * (rp[0] as Transform3D)
			body.add_child(cs)
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
		o.set_meta("base", o.light_energy)
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
	_trophies(root, xf)
	var list: Array = []
	for sp in spot_list:
		list.append({"kind": sp[0], "pos": xf * P(sp[1], sp[2], sp[3])})
	spots[String(h["id"])] = list
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
		wm.set_shader_parameter("seed", float(fx[8]) if fx.size() > 8 else 0.0)
		wm.set_shader_parameter("corners", 0.0 if int(fx[6]) == 6 else 1.0)
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


func _trophies(root: Node3D, xf: Transform3D) -> void:
	if trophy_spec.is_empty():
		return
	var x0: float = trophy_spec[0]
	var x1: float = trophy_spec[1]
	var z: float = trophy_spec[2]
	var y: float = trophy_spec[3]
	var inward: float = trophy_spec[4]
	var t := HomeTrophies.new()
	t.name = "Trophies"
	var zi := z + inward * 0.13
	t.upper = [xf * P(x0 + 0.1, zi, y + 0.53), xf * P(x1 - 0.1, zi, y + 0.53)]
	t.lower = [xf * P(x0 + 0.1, zi, y + 0.03), xf * P(x1 - 0.1, zi, y + 0.03)]
	t.out = (xf.basis * (P(0.0, z + inward, 0.0) - P(0.0, z, 0.0))).normalized()
	root.add_child(t)
	trophy_views[String(h["id"])] = {"centre": xf * P((x0 + x1) * 0.5, zi, y + 0.3), "out": t.out,
		"width": x1 - x0}


## Two shelves for the trophies, x0..x1 against a wall at depth z (`inward`
## +1 on the window wall, −1 on the back wall), the lower at height y.
func trophy_shelf(x0: float, x1: float, z: float, y: float, inward: float, wood: Color) -> void:
	trophy_spec = [x0, x1, z, y, inward]
	var z0 := minf(z, z + inward * 0.28)
	var z1 := maxf(z, z + inward * 0.28)
	for yy: float in [y, y + 0.5]:
		box(x0, x1, z0, z1, yy - 0.035, yy, wood)
		gbox(x0 + 0.05, x1 - 0.05, z0 + 0.02, z1 - 0.02, yy - 0.04, yy - 0.035, Color(1.0, 0.86, 0.62))
	for x: float in [x0 + 0.08, x1 - 0.12]:
		box(x, x + 0.04, minf(z, z + inward * 0.06), maxf(z, z + inward * 0.06), y - 0.2, y + 0.5, STEEL)
	lights.append([Vector3((x0 + x1) * 0.5, y + 0.9, z + inward * 0.9), Color(1.0, 0.86, 0.66), 0.3, 2.4])


## Something to use here (HomeSystem shows a prompt within reach).
func spot(kind: String, x: float, z: float, y := 0.0) -> void:
	spot_list.append([kind, x, z, y])


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
const _LIGHTS := preload("res://src/world/home_lights.gd")
## The trophy shelf of each built home, for the close-up: id -> {centre, out}.
static var trophy_views := {}


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
	_plaster(pal)
	_ceiling(tier)
	_curtains(tier)
	# Skirting all round (the window wall has its own reveals).
	var sk: Color = WALNUT if tier != 1 else CHALK.darkened(0.08)
	box(0.0, 0.1, 0.1, D, 0.0, 0.12, sk)
	box(W - 0.1, W, 0.1, D, 0.0, 0.12, sk)
	box(0.0, W, D - 0.1, D, 0.0, 0.12, sk)


## Plaster (home_wall style 5, with corner shading) on every outer wall the
## layout left plain.
func _plaster(pal: Array) -> void:
	var covered := {}
	for fx in walls_fx:
		var side: String = fx[0]
		var at: float = fx[1]
		var full: bool = float(fx[2]) <= 0.6 and float(fx[3]) >= (W if side == "back" else D) - 0.6
		if not full:
			continue
		if (side == "back" and absf(at - D) < 0.05) or (side == "left" and absf(at) < 0.05) or (side == "right" and absf(at - W) < 0.05):
			covered[side] = true
	var tint: Color = pal[0]
	if not covered.has("back"):
		feature("back", D, 0.0, W, 0.0, H, 5, tint)
	if not covered.has("left"):
		feature("left", 0.0, 0.0, D, 0.0, H, 5, tint)
	if not covered.has("right"):
		feature("right", W, 0.0, D, 0.0, H, 5, tint)


## Ceilings: recessed downlights over the open floor; a lit cove round the
## edge in the apartment, the sky apartment and the penthouse.
func _ceiling(tier: int) -> void:
	if tier == 2:
		return  # the loft's ceiling is its beams and ducts
	var trim := Color(0.86, 0.85, 0.82) if tier != 4 else Color(0.2, 0.15, 0.1)
	var warm := Color(1.0, 0.9, 0.74)
	var step := 2.8 if tier < 3 else 3.2
	var nx := maxi(int((W - 2.0) / step), 1)
	var nz := maxi(int((D - 2.0) / step), 1)
	for ix in nx + 1:
		for iz in nz + 1:
			var x := lerpf(1.4, W - 1.4, float(ix) / nx)
			var z := lerpf(1.6, D - 1.4, float(iz) / nz)
			box(x - 0.13, x + 0.13, z - 0.13, z + 0.13, H - 0.012, H - 0.004, trim)
			gbox(x - 0.09, x + 0.09, z - 0.09, z + 0.09, H - 0.016, H - 0.01, warm)
	if tier in [1, 3, 4]:
		var bw := 0.55
		var drop := 0.32
		var col: Color = trim if tier != 4 else WALNUT
		box(0.0, W, D - bw, D, H - drop, H, col)
		box(0.0, bw, 0.4, D - bw, H - drop, H, col)
		box(W - bw, W, 0.4, D - bw, H - drop, H, col)
		var glowc := Color(1.0, 0.82, 0.55)
		gbox(bw, W - bw, D - bw - 0.03, D - bw, H - drop + 0.02, H - drop + 0.06, glowc)
		gbox(bw, bw + 0.03, 0.4, D - bw, H - drop + 0.02, H - drop + 0.06, glowc)
		gbox(W - bw - 0.03, W - bw, 0.4, D - bw, H - drop + 0.02, H - drop + 0.06, glowc)


## Full-height curtains gathered either side of the window, on a track.
func _curtains(tier: int) -> void:
	var cols := [Color(0.82, 0.76, 0.64), Color(0.95, 0.94, 0.91), Color(), Color(0.52, 0.45, 0.4), Color(0.2, 0.19, 0.19)]
	if tier == 2:
		return  # steel-framed industrial glazing: bare
	var c: Color = cols[tier]
	var top := H - 0.12
	var x0 := ox0()
	var x1 := ox1()
	var span := 0.75 if tier < 3 else 0.95
	tube(Vector3(maxf(x0 - span - 0.1, 0.05), top + 0.04, WIN_Z + 0.13), Vector3(minf(x1 + span + 0.1, W - 0.05), top + 0.04, WIN_Z + 0.13),
		0.018, STEEL if tier != 4 else BRASS, 6)
	for side: float in [-1.0, 1.0]:
		var a: float = x0 - 0.04 if side < 0.0 else x1 + 0.04
		var n := 9
		for i in n:
			var t0 := a + side * span * float(i) / n
			var t1 := a + side * span * float(i + 1) / n
			var dz := 0.06 * (1.0 if i % 2 == 0 else -1.0)
			var shade := c.darkened(0.12 if i % 2 == 0 else 0.0)
			box(minf(t0, t1), maxf(t0, t1), WIN_Z + 0.1 + dz, WIN_Z + 0.16 + dz, 0.03, top, shade)


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
	box(d0, d1, z, z + 0.14, DOOR_H, H, c, true)
	if d1 < x1:
		box(d1, x1, z, z + 0.14, 0.0, H, c, true)


## A partition along z at x (z0..z1) with a door gap (d0..d1); collides.
func wall_z(x: float, z0: float, z1: float, d0: float, d1: float, c: Color) -> void:
	if d0 > z0:
		box(x, x + 0.14, z0, d0, 0.0, H, c, true)
	box(x, x + 0.14, d0, d1, DOOR_H, H, c, true)
	if d1 < z1:
		box(x, x + 0.14, d1, z1, 0.0, H, c, true)


## Feature wall finish (home_wall.gdshader): side "back" (faces the window,
## at depth `at`), "left"/"right" (at x = `at`); a0..a1 along it.
func feature(side: String, at: float, a0: float, a1: float, y0: float, y1: float, style: int, tint: Color, seed := 0.0) -> void:
	walls_fx.append([side, at, a0, a1, y0, y1, style, tint, seed])


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
# Every plan keeps furniture to the walls and the corners and leaves the
# middle open: the follow camera sits 3.5–4 m behind the hero indoors, and a
# room you can't turn round in is a room you can't see.

## A hanging lamp whose shade bottoms out `low` metres above the floor. Away
## from tables keep `low` near 3 m: lower, the follow camera meets it at eye height.
func hang(x: float, z: float, low: float, shade: Color, r := 0.16) -> void:
	pendant(x, z, maxf(H - low - r * 1.2, 0.3), shade, r)


## A low chest/cabinet with a top; collides.
func cabinet(x0: float, x1: float, z0: float, z1: float, hgt: float, body: Color, top: Color) -> void:
	box(x0, x1, z0, z1, 0.0, hgt - 0.04, body, true)
	box(x0 - 0.02, x1 + 0.02, z0 - 0.02, z1 + 0.02, hgt - 0.04, hgt, top)


## A framed painting on a wall (side as feature()): a canvas in the
## painting shader (home_wall style 6, coloured from cols[0]), a slim frame.
func picture(side: String, at: float, a0: float, a1: float, y0: float, y1: float, cols: Array) -> void:
	var into := -1.0 if side != "left" else 1.0  # off the wall, into the room
	var c0: Color = cols[0]
	var seed := fposmod(a0 * 7.3 + y0 * 3.1 + at, 10.0)
	walls_fx.append([side, at + into * 0.035, a0 + 0.05, a1 - 0.05, y0 + 0.05, y1 - 0.05, 6, c0, seed])
	var fc := FRAME if c0.get_luminance() > 0.35 else BRASS
	var d0 := at
	var d1 := at + into * 0.06
	var lo := minf(d0, d1)
	var hi := maxf(d0, d1)
	var back_lo := minf(at, at + into * 0.03)
	var back_hi := maxf(at, at + into * 0.03)
	match side:
		"back":
			box(a0, a1, back_lo, back_hi, y0, y1, Color(0.9, 0.88, 0.84))
			box(a0, a1, lo, hi, y0, y0 + 0.05, fc)
			box(a0, a1, lo, hi, y1 - 0.05, y1, fc)
			box(a0, a0 + 0.05, lo, hi, y0, y1, fc)
			box(a1 - 0.05, a1, lo, hi, y0, y1, fc)
		_:
			box(back_lo, back_hi, a0, a1, y0, y1, Color(0.9, 0.88, 0.84))
			box(lo, hi, a0, a1, y0, y0 + 0.05, fc)
			box(lo, hi, a0, a1, y1 - 0.05, y1, fc)
			box(lo, hi, a0, a0 + 0.05, y0, y1, fc)
			box(lo, hi, a1 - 0.05, a1, y0, y1, fc)


## A run of kitchen base units along a side wall (x = wall side), z0..z1,
## with doors, handles and a worktop; `right` puts it on the right wall.
func kitchen_run(right: bool, z0: float, z1: float, body: Color, top: Color, handle: Color) -> void:
	var xa := W - 0.62 if right else 0.04
	var xb := W - 0.04 if right else 0.62
	box(xa, xb, z0, z1, 0.1, 0.88, body, true)
	box(xa - 0.04 if right else xa, xb if right else xb + 0.04, z0 - 0.04, z1 + 0.04, 0.88, 0.93, top)
	var face := xa - 0.02 if right else xb
	for i in range(int((z1 - z0) / 0.6)):
		var z := z0 + 0.05 + i * 0.6
		box(face, face + 0.02, z + 0.03, z + 0.56, 0.16, 0.84, body.darkened(0.12))
		box(face - 0.02 if right else face + 0.02, face if right else face + 0.04, z + 0.22, z + 0.36, 0.74, 0.76, handle)


## Quay Studio: a courier's first place, one big brick-walled room. Bed on a
## pine platform in the back corner behind a curtain, galley kitchen down the
## right wall, a desk at the window, the bike on the wall, a bistro table,
## a sofa on a rug in the middle, parcels by the front door.
func _studio(pal: Array) -> void:
	feature("back", D, 0.0, W, 0.0, H, 0, Color(0.56, 0.3, 0.22))
	var pine := Color(0.72, 0.56, 0.36)
	# Sleeping platform (back left): one step up, bed, crate nightstand, curtain.
	box(0.1, 3.7, D - 3.3, D - 0.1, 0.0, 0.2, pine, true)
	box(0.1, 3.7, D - 3.34, D - 3.3, 0.0, 0.2, pine.darkened(0.2))
	asset("bed", 1.4, D - 1.5, 0.0, 0.2)
	proxy(0.45, 2.35, D - 2.65, D - 0.35, 0.92)
	box(2.6, 3.05, D - 0.62, D - 0.18, 0.2, 0.66, Color(0.58, 0.44, 0.28), true)
	tube(Vector3(2.82, 0.66, D - 0.4), Vector3(2.82, 0.98, D - 0.4), 0.02, STEEL, 5)
	gbox(2.7, 2.94, D - 0.52, D - 0.28, 0.98, 1.16, Color(1.0, 0.8, 0.52))
	tube(Vector3(0.1, H - 0.25, D - 3.4), Vector3(3.7, H - 0.25, D - 3.4), 0.015, STEEL, 5)
	for i in 6:
		var x := 0.15 + i * 0.13
		box(x, x + 0.12, D - 3.46 + 0.04 * (i % 2), D - 3.38 + 0.04 * (i % 2), 0.3, H - 0.3, Color(0.78, 0.7, 0.55))
	picture("back", D, 0.6, 3.2, 1.9, 2.9, [Color(0.15, 0.25, 0.4), Color(0.95, 0.78, 0.2)])
	# Clothes rail on the left wall: the work kit.
	for z: float in [D - 5.6, D - 3.9]:
		tube(Vector3(0.4, 0.0, z), Vector3(0.4, 1.75, z), 0.018, STEEL, 5)
	tube(Vector3(0.4, 1.75, D - 5.6), Vector3(0.4, 1.75, D - 3.9), 0.016, STEEL, 5)
	var kit := [Color(0.12, 0.12, 0.14), Color(0.2, 0.22, 0.26), Color(0.95, 0.75, 0.1), Color(0.7, 0.18, 0.14),
		Color(0.3, 0.32, 0.36), Color(0.15, 0.45, 0.5)]
	for i in 6:
		var z := D - 5.45 + i * 0.25
		box(0.22, 0.58, z, z + 0.2, 0.95, 1.67, kit[i])
	box(0.15, 0.65, D - 5.6, D - 3.9, 0.0, 0.3, Color(0.3, 0.3, 0.32), true)  # shoe crate
	# The bike on the left wall.
	var wy := 1.45
	var bz := 3.3
	ring(Vector3(0.2, wy, bz), Vector3.RIGHT, 0.34, 0.018, STEEL)
	ring(Vector3(0.2, wy, bz + 1.1), Vector3.RIGHT, 0.34, 0.018, STEEL)
	var orange := Color(0.92, 0.45, 0.12)
	tube(Vector3(0.2, wy, bz), Vector3(0.2, wy + 0.38, bz + 0.5), 0.02, orange, 5)
	tube(Vector3(0.2, wy + 0.38, bz + 0.5), Vector3(0.2, wy, bz + 1.1), 0.02, orange, 5)
	tube(Vector3(0.2, wy + 0.38, bz + 0.5), Vector3(0.2, wy + 0.42, bz + 0.85), 0.02, orange, 5)
	tube(Vector3(0.2, wy + 0.42, bz + 0.85), Vector3(0.2, wy, bz + 1.1), 0.02, orange, 5)
	tube(Vector3(0.2, wy, bz), Vector3(0.2, wy + 0.5, bz + 0.1), 0.018, orange, 5)
	tube(Vector3(0.08, wy + 0.5, bz + 0.1), Vector3(0.36, wy + 0.5, bz + 0.1), 0.014, STEEL, 5)
	box(0.15, 0.25, bz + 0.75, bz + 0.95, wy + 0.48, wy + 0.52, STEEL)
	box(0.02, 0.06, bz + 0.45, bz + 0.55, wy + 0.1, wy + 0.5, STEEL)
	# Desk at the window (left of the opening): laptop, lamp, chair, pinboard.
	box(0.3, 2.7, 0.45, 1.15, 0.72, 0.76, OAK, true)
	for x: float in [0.36, 2.64]:
		for z: float in [0.5, 1.1]:
			tube(Vector3(x, 0.0, z), Vector3(x, 0.72, z), 0.022, STEEL, 5)
	box(0.9, 1.3, 0.6, 0.88, 0.76, 0.78, Color(0.2, 0.2, 0.22))
	gbox(0.91, 1.29, 0.58, 0.6, 0.78, 1.02, Color(0.55, 0.75, 1.0))
	tube(Vector3(2.2, 0.76, 0.7), Vector3(2.2, 0.86, 0.7), 0.045, Color(0.9, 0.9, 0.88), 8)
	tube(Vector3(2.4, 0.76, 0.6), Vector3(2.4, 1.2, 0.6), 0.012, STEEL, 4)
	gbox(2.3, 2.5, 0.55, 0.75, 1.14, 1.24, Color(1.0, 0.82, 0.55))
	asset("chair", 1.4, 1.65)
	box(0.02, 0.05, 1.4, 2.9, 1.3, 2.3, Color(0.6, 0.45, 0.3))  # pinboard + route maps
	for i in 5:
		var z := 1.55 + i * 0.27
		box(0.05, 0.06, z, z + 0.2, 1.45 + 0.2 * (i % 3), 1.7 + 0.2 * (i % 3), [CHALK, Color(0.95, 0.85, 0.4), Color(0.6, 0.8, 0.9)][i % 3])
	# Galley kitchen down the right wall: sage units, butcher block, fridge, shelf.
	var sage := Color(0.4, 0.5, 0.43)
	box(W - 0.66, W - 0.04, 3.2, 3.95, 0.0, 1.95, CHALK, true)  # fridge
	box(W - 0.68, W - 0.66, 3.3, 3.35, 1.0, 1.6, STEEL)
	kitchen_run(true, 4.0, D - 0.2, sage, Color(0.66, 0.47, 0.28), BRASS)
	box(W - 0.6, W - 0.2, 5.6, 6.15, 0.93, 0.945, FRAME)  # hob
	tube(Vector3(W - 0.3, 0.93, 6.8), Vector3(W - 0.3, 1.13, 6.8), 0.07, Color(0.85, 0.2, 0.15), 8)
	box(W - 0.6, W - 0.15, 7.6, 8.3, 0.93, 0.96, STEEL)  # sink
	box(W - 0.32, W - 0.04, 4.2, D - 0.4, 1.6, 1.63, OAK)
	for i in 9:
		var z := 4.4 + i * 0.6
		tube(Vector3(W - 0.18, 1.63, z), Vector3(W - 0.18, 1.79 + 0.04 * (i % 3), z), 0.06,
			[Color(0.9, 0.85, 0.7), Color(0.5, 0.3, 0.15), Color(0.85, 0.85, 0.85)][i % 3], 8)
	# Bistro table for two (front right corner, out of the window band).
	var tx := W - 2.0
	var tz := 1.6
	tube(Vector3(tx, 0.0, tz), Vector3(tx, 0.72, tz), 0.04, STEEL, 6)
	tube(Vector3(tx, 0.72, tz), Vector3(tx, 0.75, tz), 0.42, pine, 14)
	proxy(tx - 0.42, tx + 0.42, tz - 0.42, tz + 0.42, 0.75)
	asset("chair", tx - 0.75, tz, PI * 0.5)
	asset("chair", tx + 0.75, tz, -PI * 0.5)
	hang(tx, tz, 1.6, Color(0.95, 0.92, 0.85), 0.1)
	# Lounge: sofa facing the window on a rug, crate table, beanbag, floor lamp.
	var lx := W * 0.5
	asset("sofa", lx, 6.9)
	proxy(lx - 1.4, lx + 1.4, 6.4, 7.4, 0.85)
	box(lx - 0.6, lx + 0.6, 5.0, 5.6, 0.0, 0.42, Color(0.58, 0.44, 0.28), true)
	_rug(lx - 2.2, lx + 2.2, 4.2, 7.8, Color(0.8, 0.58, 0.2))
	tube(Vector3(lx + 2.0, 0.0, 5.2), Vector3(lx + 2.0, 0.42, 5.2), 0.42, Color(0.2, 0.34, 0.42), 12)
	tube(Vector3(lx - 1.9, 0.0, 7.2), Vector3(lx - 1.9, 1.55, 7.2), 0.015, STEEL, 5)
	gbox(lx - 2.05, lx - 1.75, 7.05, 7.35, 1.55, 1.8, Color(1.0, 0.82, 0.55))
	# Front door (back wall, right of the platform), hooks, parcels.
	var door := 6.4
	box(door, door + 1.1, D - 0.06, D - 0.01, 0.0, 2.2, Color(0.25, 0.32, 0.3))
	box(door + 0.95, door + 1.0, D - 0.12, D - 0.06, 1.0, 1.1, BRASS)
	for i in 4:
		var x := door + 1.4 + i * 0.25
		tube(Vector3(x, 1.7, D - 0.02), Vector3(x, 1.75, D - 0.15), 0.012, STEEL, 4)
	var card := Color(0.66, 0.5, 0.32)
	box(door + 1.4, door + 2.1, D - 0.85, D - 0.2, 0.0, 0.45, card, true)
	box(door + 1.5, door + 2.0, D - 0.75, D - 0.3, 0.45, 0.72, card.lightened(0.1))
	box(door + 2.2, door + 2.95, D - 0.9, D - 0.25, 0.0, 0.3, card.darkened(0.1), true)
	picture("back", D, door + 1.4, door + 2.7, 1.95, 2.65, [Color(0.95, 0.3, 0.2), Color(0.15, 0.6, 0.62), Color(0.95, 0.78, 0.2)])
	board("back", D - 0.02, W - 2.2, 1.9, 1.2, Color(0.6, 0.45, 0.3))
	plant_big(W - 0.8, 3.0, 0.9)
	trophy_shelf(0.3, 3.0, WIN_Z, 1.35, 1.0, OAK)
	spot("wardrobe", 1.0, D - 4.75)
	spot("bed", 3.2, D - 2.0, 0.2)
	spot("jobs", 1.0, 2.1)
	spot("trophies", 2.6, 1.9)
	hang(lx + 1.3, 5.6, 2.9, Color(0.95, 0.92, 0.85), 0.09)
	lights.append([Vector3(lx, H - 1.2, 5.6), Color(1.0, 0.8, 0.58), 1.4, 8.0])
	lights.append([Vector3(2.0, 1.6, D - 1.5), Color(1.0, 0.75, 0.5), 0.8, 4.5])
	lights.append([Vector3(W - 1.6, 2.2, 6.5), Color(1.0, 0.85, 0.65), 0.8, 5.5])
	lights.append([Vector3(1.6, 1.4, 1.0), Color(0.75, 0.85, 1.0), 0.4, 3.0])


## City Apartment: a bright one-bedroom – pale oak parquet, white walls, a
## wall of books, an open kitchen with a breakfast bar, a proper bedroom and
## bathroom off an entrance hall at the back.
func _apartment(pal: Array) -> void:
	var wall: Color = pal[0]
	var split := D - 5.6
	var left := 6.6
	var right := W - 5.0
	# Bedroom (back left) and bathroom (back right) either side of the hall.
	wall_x(split, 0.0, left + 0.16, left - 2.6, left - 0.5, wall)
	box(left, left + 0.16, split, D, 0.0, H, wall, true)
	wall_x(split, right, W, right + 0.4, right + 1.7, wall)
	box(right, right + 0.16, split, D, 0.0, H, wall, true)
	feature("back", split - 0.002, 0.0, left - 2.6, 0.0, H, 4, Color(0.55, 0.62, 0.58))
	# Bedroom: bed, bedside lamps, wardrobe, a chair.
	asset("bed", left * 0.5 + 0.4, D - 1.5)
	proxy(left * 0.5 - 0.55, left * 0.5 + 1.35, D - 2.65, D - 0.35, 0.72)
	for x: float in [left * 0.5 - 0.95, left * 0.5 + 1.75]:
		box(x - 0.22, x + 0.22, D - 0.55, D - 0.15, 0.0, 0.5, OAK)
		gbox(x - 0.1, x + 0.1, D - 0.45, D - 0.25, 0.5, 0.75, Color(1.0, 0.85, 0.62))
	box(0.12, 0.75, split + 0.5, D - 0.5, 0.0, 2.4, CHALK, true)
	for z in range(3):
		var zz := split + 0.55 + z * ((D - 1.05 - split) / 3.0)
		box(0.75, 0.77, zz + 0.02, zz + (D - 1.05 - split) / 3.0 - 0.02, 0.05, 2.35, CHALK.darkened(0.05))
	_rug(left * 0.5 - 1.3, left * 0.5 + 2.1, split + 0.6, D - 0.3, Color(0.7, 0.55, 0.45))
	picture("back", D, left * 0.5 - 0.4, left * 0.5 + 1.2, 1.5, 2.2, [Color(0.85, 0.82, 0.7)])
	# Bathroom: vanity, toilet, a walk-in shower, a towel rail.
	asset("vanity", W - 0.72, D - 0.65)
	asset("toilet", right + 0.8, D - 0.65)
	box(right + 0.2, W - 0.2, split + 0.3, D - 0.1, 0.012, 0.026, STONE)
	pane(W - 1.6, W - 1.58, split + 0.3, split + 1.9, 0.0, 2.1)
	box(W - 1.5, W - 0.2, split + 0.3, split + 1.8, 0.03, 0.08, Color(0.55, 0.6, 0.58))
	tube(Vector3(W - 0.5, 2.0, split + 1.0), Vector3(W - 0.3, 2.0, split + 1.0), 0.09, STEEL, 10)
	gbox(W - 1.2, W - 0.25, D - 0.04, D - 0.02, 1.2, 1.9, Color(0.9, 0.95, 1.0))
	tube(Vector3(right + 0.3, 1.2, split + 2.4), Vector3(right + 0.3, 1.2, split + 3.4), 0.015, STEEL, 5)
	box(right + 0.22, right + 0.32, split + 2.45, split + 3.35, 0.7, 1.2, Color(0.85, 0.7, 0.55))
	# The hall: front door, console, mirror, coats, the progress board.
	var hx := (left + right) * 0.5
	box(hx - 0.6, hx + 0.6, D - 0.06, D - 0.01, 0.0, 2.2, Color(0.3, 0.33, 0.36))
	box(hx + 0.4, hx + 0.46, D - 0.12, D - 0.06, 1.0, 1.1, BRASS)
	cabinet(right - 0.45, right - 0.02, split + 0.8, split + 2.6, 0.85, OAK, OAK.darkened(0.1))
	pane(right - 0.03, right - 0.02, split + 1.0, split + 2.4, 1.2, 2.2)
	for i in 4:
		var z := split + 3.2 + i * 0.3
		tube(Vector3(right - 0.02, 1.75, z), Vector3(right - 0.15, 1.8, z), 0.012, STEEL, 4)
		box(right - 0.2, right - 0.05, z - 0.1, z + 0.1, 0.9, 1.7, [Color(0.6, 0.3, 0.2), Color(0.2, 0.25, 0.3)][i % 2])
	board("left", left + 0.16, split + 2.4, 1.7, 1.3, OAK)
	# Living: sofa facing the view, armchair, coffee table, rug, arc lamp.
	var sx := 3.4
	asset("sofa", sx, split - 1.6)
	asset("coffee", sx, split - 3.1)
	proxy(sx - 1.4, sx + 1.4, split - 2.1, split - 1.1, 0.85)
	asset("chair", sx - 2.2, split - 3.3, PI * 0.5)
	_rug(sx - 2.4, sx + 2.0, split - 4.6, split - 0.9, Color(0.82, 0.78, 0.7))
	tube(Vector3(sx + 1.9, 0.0, split - 1.3), Vector3(sx + 1.9, 2.1, split - 1.3), 0.02, BRASS, 6)
	tube(Vector3(sx + 1.9, 2.1, split - 1.3), Vector3(sx + 0.8, 2.3, split - 2.6), 0.018, BRASS, 6)
	gbox(sx + 0.65, sx + 0.95, split - 2.75, split - 2.45, 2.1, 2.25, Color(1.0, 0.87, 0.65))
	# A wall of books on the left wall, floor to near the ceiling, with a ladder.
	var bz0 := 0.5
	var bz1 := split - 2.2 - 1.6
	box(0.05, 0.4, bz0, bz1, 0.0, 3.3, CHALK, true)
	for i in 7:
		var y := 0.1 + i * 0.46
		box(0.05, 0.4, bz0, bz1, y, y + 0.03, CHALK.darkened(0.06))
		books(0.08, 0.36, bz0 + 0.05, bz1 - 0.05, y + 0.03, 101 + i, true)
	for z: float in [bz1 - 1.2, bz1 - 0.8]:
		tube(Vector3(0.95, 0.0, z), Vector3(0.42, 3.3, z), 0.02, OAK, 5)
	for k in 8:
		var t := (k + 0.5) / 8.0
		var x := lerpf(0.95, 0.42, t)
		tube(Vector3(x, t * 3.3, bz1 - 1.2), Vector3(x, t * 3.3, bz1 - 0.8), 0.015, OAK, 4)
	# Kitchen along the right wall, wall units over; breakfast bar with stools.
	var white := Color(0.95, 0.95, 0.93)
	kitchen_run(true, 3.4, split - 1.2, white, OAK, STEEL)
	box(W - 0.38, W - 0.04, 3.4, split - 1.2, 1.5, 2.3, white)
	box(W - 0.66, W - 0.04, split - 1.15, split - 0.3, 0.0, 2.1, Color(0.85, 0.86, 0.86), true)  # fridge
	box(W - 0.6, W - 0.2, 5.0, 5.6, 0.93, 0.945, FRAME)
	box(W - 0.6, W - 0.15, 6.4, 7.1, 0.93, 0.96, STEEL)
	for i in 4:
		tube(Vector3(W - 0.5 + i * 0.03, 1.1, 4.0 + i * 0.12), Vector3(W - 0.5 + i * 0.03, 1.32, 4.0 + i * 0.12), 0.04,
			[Color(0.2, 0.45, 0.3), CHALK, Color(0.75, 0.3, 0.2), BRASS][i], 6)
	var bx0 := W - 4.4
	var bx1 := W - 1.7
	box(bx0, bx1, 4.6, 5.2, 0.0, 0.9, white, true)
	box(bx0 - 0.05, bx1 + 0.05, 4.55, 5.25, 0.9, 0.95, OAK)
	for x: float in [bx0 + 0.45, (bx0 + bx1) * 0.5, bx1 - 0.45]:
		stool(x, 5.7, OAK)
		hang(x, 4.9, 2.7, Color(0.9, 0.85, 0.75), 0.12)
	# Round dining table for four in the window corner (right of the band).
	var dx := W - 2.1
	var dz := 1.6
	tube(Vector3(dx, 0.0, dz), Vector3(dx, 0.72, dz), 0.06, STEEL, 8)
	tube(Vector3(dx, 0.72, dz), Vector3(dx, 0.76, dz), 0.55, OAK, 18)
	proxy(dx - 0.55, dx + 0.55, dz - 0.55, dz + 0.55, 0.76)
	asset("chair", dx - 0.85, dz, PI * 0.5)
	asset("chair", dx + 0.85, dz, -PI * 0.5)
	hang(dx, dz, 1.75, Color(0.92, 0.9, 0.86), 0.2)
	plant_big(0.8, split - 0.7)
	plant_big(right - 0.6, split - 0.6, 0.8)
	trophy_shelf(0.6, 3.7, WIN_Z, 1.3, 1.0, OAK)
	box(bx0 + 0.3, bx0 + 0.75, 4.75, 5.05, 0.95, 0.965, Color(0.15, 0.15, 0.16))  # tablet on the bar
	gbox(bx0 + 0.32, bx0 + 0.73, 4.77, 5.03, 0.965, 0.97, Color(0.45, 0.7, 1.0))
	spot("wardrobe", 1.3, split + 2.8)
	spot("bed", 5.3, D - 2.4)
	spot("jobs", bx0 + 0.5, 6.1)
	spot("trophies", 2.2, 1.3)
	lights.append([Vector3(sx, H - 0.5, split * 0.55), Color(1.0, 0.9, 0.78), 1.3, 8.5])
	lights.append([Vector3(W - 3.0, H - 1.2, 4.9), Color(1.0, 0.86, 0.66), 1.0, 6.0])
	lights.append([Vector3(left * 0.5 + 0.4, H - 0.6, D - 2.6), Color(1.0, 0.87, 0.7), 1.4, 7.0])
	lights.append([Vector3(W - 2.4, H - 0.4, D - 2.4), Color(1.0, 0.95, 0.9), 0.7, 4.5])
	lights.append([Vector3(hx, H - 0.5, D - 2.6), Color(1.0, 0.88, 0.7), 0.6, 4.5])


## High-Rise Loft: industrial open plan under a 6 m ceiling – polished
## concrete, brick, steel beams and ducts, a glass-walled bedroom on a plinth,
## a long kitchen with an island, a training corner, a record wall and neon.
func _loft(pal: Array) -> void:
	var brick := Color(0.5, 0.27, 0.2)
	feature("back", D, 0.0, W, 0.0, H, 0, brick)
	feature("left", 0.0, 0.0, D, 0.0, H, 0, brick)
	feature("right", W, 0.0, D, 0.0, H, 3, Color(0.64, 0.63, 0.6))
	# Steel beams across, ducts along the back, a sprinkler riser.
	for k in 4:
		var x := W * (0.2 + 0.2 * k)
		box(x - 0.14, x + 0.14, 0.2, D, H - 0.5, H - 0.02, STEEL)
	var duct := Color(0.68, 0.7, 0.72)
	tube(Vector3(0.3, H - 0.8, D - 1.0), Vector3(W - 0.3, H - 0.8, D - 1.0), 0.3, duct, 12)
	tube(Vector3(W * 0.3, H - 0.8, D - 1.0), Vector3(W * 0.3, H - 0.8, 2.5), 0.2, duct, 10)
	tube(Vector3(W * 0.7, H - 0.8, D - 1.0), Vector3(W * 0.7, H - 0.8, 3.0), 0.2, duct, 10)
	tube(Vector3(0.25, 0.0, D - 0.3), Vector3(0.25, H, D - 0.3), 0.06, Color(0.55, 0.15, 0.1), 8)
	# Kitchen along the back wall: black units, open steel shelving, island.
	var black := Color(0.11, 0.11, 0.12)
	var conc := Color(0.6, 0.6, 0.58)
	box(0.5, 7.6, D - 0.66, D - 0.05, 0.1, 0.9, black, true)
	box(0.46, 7.64, D - 0.7, D - 0.02, 0.9, 0.96, conc)
	box(5.2, 5.8, D - 0.6, D - 0.1, 0.96, 0.98, STEEL)  # sink
	box(2.0, 2.7, D - 0.6, D - 0.1, 0.96, 0.975, FRAME)  # hob
	box(7.7, 8.5, D - 0.7, D - 0.05, 0.0, 2.2, Color(0.2, 0.2, 0.21), true)  # fridge
	for x: float in [0.6, 2.4, 4.2, 6.0, 7.5]:
		tube(Vector3(x, 1.4, D - 0.05), Vector3(x, 2.9, D - 0.05), 0.012, STEEL, 4)
	for y: float in [1.55, 2.15, 2.75]:
		box(0.5, 7.6, D - 0.34, D - 0.04, y, y + 0.04, OAK)
		books(0.7, 2.0, D - 0.3, D - 0.08, y + 0.04, int(y * 10.0))
		for i in 8:
			var x := 2.4 + i * 0.6
			tube(Vector3(x, y + 0.04, D - 0.2), Vector3(x, y + 0.2 + 0.06 * (i % 2), D - 0.2), 0.07,
				[CHALK, Color(0.3, 0.32, 0.35), Color(0.75, 0.6, 0.4)][i % 3], 8)
	var iz := D - 4.4
	box(1.6, 6.4, iz, iz + 1.1, 0.0, 0.9, WALNUT, true)
	box(1.55, 6.45, iz - 0.05, iz + 1.15, 0.9, 0.97, conc)
	for x: float in [2.3, 4.0, 5.7]:
		stool(x, iz - 0.5, black)
		hang(x, iz + 0.55, 3.0, black, 0.15)
	# Bedroom on a plinth (back right) behind steel-framed glass; door at its left.
	var bz := D - 5.6
	var px := W - 7.2
	box(px, W - 0.15, bz, D - 0.12, 0.0, 0.3, conc.darkened(0.15), true)
	box(px, W - 0.15, bz - 0.36, bz, 0.0, 0.15, conc.darkened(0.1))  # half step
	ramp(px, W - 0.15, bz - 0.6, bz + 0.02, 0.3)  # walked onto, not snagged on
	asset("bed", W - 3.4, D - 1.5, 0.0, 0.3)
	proxy(W - 4.35, W - 2.45, D - 2.65, D - 0.35, 1.02)
	for x: float in [W - 5.0, W - 1.8]:
		box(x - 0.25, x + 0.25, D - 0.55, D - 0.15, 0.3, 0.8, black)
		gbox(x - 0.1, x + 0.1, D - 0.45, D - 0.25, 0.8, 1.05, Color(1.0, 0.8, 0.55))
	tube(Vector3(W - 0.5, 0.3, bz + 0.6), Vector3(W - 0.5, 2.2, bz + 0.6), 0.02, STEEL, 5)
	tube(Vector3(W - 0.5, 2.2, bz + 0.6), Vector3(W - 0.5, 2.2, bz + 2.4), 0.02, STEEL, 5)
	tube(Vector3(W - 0.5, 0.3, bz + 2.4), Vector3(W - 0.5, 2.2, bz + 2.4), 0.02, STEEL, 5)
	for i in 6:
		var z := bz + 0.75 + i * 0.27
		box(W - 0.68, W - 0.32, z, z + 0.2, 1.25, 2.05, [black, Color(0.4, 0.42, 0.45), CHALK][i % 3])
	var ty := 2.6
	var door := px + 1.3
	box(px, px + 0.06, bz - 0.06, D - 0.12, 0.0, H, STEEL, true)
	pane(px + 0.02, px + 0.04, bz, D - 0.12, 0.3, ty)
	var z := bz + 1.2
	while z < D - 0.3:
		box(px, px + 0.06, z, z + 0.05, 0.0, ty, STEEL)
		z += 1.2
	col_boxes.append(AABB(P(px, bz, 0.0).min(P(px + 0.06, D - 0.12, H)), (P(px, bz, 0.0) - P(px + 0.06, D - 0.12, H)).abs()))
	box(px, W - 0.15, bz - 0.06, bz, ty, ty + 0.06, STEEL)  # transom
	pane(door, W - 0.15, bz - 0.04, bz - 0.02, 0.3, ty)
	var x := door
	while x < W - 0.2:
		box(x, x + 0.05, bz - 0.06, bz, 0.0, ty, STEEL)
		x += 1.2
	col_boxes.append(AABB(P(door, bz - 0.06, 0.0).min(P(W - 0.15, bz, ty)), (P(door, bz - 0.06, 0.0) - P(W - 0.15, bz, ty)).abs()))
	# Training corner (front left, clear of the opening): bag, pull-up bar, bench, rack.
	tube(Vector3(1.8, H, 4.8), Vector3(1.8, 2.1, 4.8), 0.01, STEEL, 4)
	tube(Vector3(1.8, 0.9, 4.8), Vector3(1.8, 2.1, 4.8), 0.2, Color(0.55, 0.1, 0.08), 12)
	tube(Vector3(0.05, 2.4, 3.0), Vector3(1.2, 2.4, 3.0), 0.018, STEEL, 6)
	box(0.0, 0.08, 2.9, 3.1, 2.25, 2.55, STEEL)
	box(0.6, 1.0, 6.6, 7.9, 0.0, 0.45, black, true)
	for zz: float in [7.0, 7.5]:
		tube(Vector3(0.5, 0.62, zz), Vector3(1.1, 0.62, zz), 0.02, STEEL, 5)
		for xx: float in [0.53, 1.07]:
			tube(Vector3(xx - 0.03, 0.62, zz), Vector3(xx + 0.03, 0.62, zz), 0.12, black, 10)
	box(0.1, 0.5, 8.6, 10.0, 0.0, 0.9, STEEL, true)  # kettlebell rack
	for i in 4:
		tube(Vector3(0.3, 0.9, 8.8 + i * 0.35), Vector3(0.3, 1.08, 8.8 + i * 0.35), 0.1 + 0.015 * i, black, 8)
	_rug(0.3, 3.4, 3.4, 10.2, Color(0.2, 0.2, 0.22))
	# Neon over the training corner: a wave on the brick.
	for i in 12:
		var a := float(i) / 11.0
		var zz := 4.0 + a * 4.0
		var yy := 3.9 + sin(a * TAU * 1.5) * 0.35
		gbox(0.02, 0.05, zz, zz + 0.36, yy, yy + 0.05, Color(1.0, 0.3, 0.55))
	# Record wall (right): low cabinet, turntable, speakers, sleeves above.
	cabinet(W - 0.6, W - 0.05, 3.2, 6.8, 0.72, WALNUT, WALNUT.darkened(0.2))
	box(W - 0.5, W - 0.12, 4.6, 5.1, 0.72, 0.8, FRAME)
	tube(Vector3(W - 0.31, 0.8, 4.85), Vector3(W - 0.31, 0.82, 4.85), 0.17, Color(0.05, 0.05, 0.05), 14)
	for zz: float in [2.6, 7.0]:
		box(W - 0.55, W - 0.1, zz, zz + 0.45, 0.0, 1.15, black, true)
		tube(Vector3(W - 0.55, 0.8, zz + 0.225), Vector3(W - 0.57, 0.8, zz + 0.225), 0.13, Color(0.3, 0.3, 0.32), 10)
	for r in 3:
		for i in 7:
			var zz := 3.3 + i * 0.5
			box(W - 0.06, W - 0.04, zz, zz + 0.4, 1.6 + r * 0.55, 2.0 + r * 0.55,
				[Color(0.85, 0.3, 0.2), Color(0.1, 0.4, 0.55), CHALK, Color(0.95, 0.75, 0.2), black][(i + r * 2) % 5])
	board("right", W - 0.02, 8.6, 2.2, 1.6, STEEL)
	# Lounge in the middle: sofa to the view, a second at right angles, rug.
	var lx := W * 0.55
	asset("sofa", lx, 8.9)
	asset("coffee", lx, 7.3)
	asset("sofa", lx - 2.6, 7.1, -PI * 0.5)
	proxy(lx - 1.4, lx + 1.4, 8.4, 9.4, 0.85)
	proxy(lx - 3.1, lx - 2.1, 5.7, 8.5, 0.85)
	_rug(lx - 3.6, lx + 2.4, 5.4, 9.8, Color(0.72, 0.35, 0.2))
	tube(Vector3(lx + 2.0, 0.0, 9.3), Vector3(lx + 2.0, 1.8, 9.3), 0.02, black, 6)
	gbox(lx + 1.85, lx + 2.15, 9.15, 9.45, 1.8, 2.05, Color(1.0, 0.82, 0.55))
	plant_big(W - 1.2, 1.2, 1.2)
	plant_big(px - 0.8, D - 0.8, 1.1)
	trophy_shelf(1.4, 4.6, WIN_Z, 1.35, 1.0, STEEL.lightened(0.25))
	box(3.3, 3.75, iz + 0.3, iz + 0.62, 0.97, 0.985, Color(0.15, 0.15, 0.16))  # laptop on the island
	gbox(3.32, 3.73, iz + 0.32, iz + 0.6, 0.985, 0.99, Color(0.45, 0.7, 1.0))
	spot("wardrobe", W - 1.4, bz + 1.5, 0.3)
	spot("bed", W - 5.4, D - 2.6, 0.3)
	spot("jobs", 3.5, iz - 0.9)
	spot("trophies", 3.0, 1.3)
	lights.append([Vector3(4.0, H - 2.6, iz + 0.5), Color(1.0, 0.78, 0.5), 1.5, 8.0])
	lights.append([Vector3(lx, H - 1.6, 7.4), Color(1.0, 0.86, 0.68), 1.4, 10.0])
	lights.append([Vector3(W - 3.4, 2.4, D - 2.6), Color(1.0, 0.8, 0.6), 1.0, 6.5])
	lights.append([Vector3(1.0, 3.8, 6.0), Color(1.0, 0.35, 0.55), 0.9, 6.0])
	lights.append([Vector3(W - 1.5, 2.6, 5.0), Color(1.0, 0.84, 0.62), 0.7, 5.0])


## Sky Apartment: contemporary luxury – marble, walnut slat wall with a
## linear fire and a lounge round it, a grand piano at the glass, dining
## for eight under a ring chandelier, a marble kitchen, a backlit wine wall,
## a gallery entrance and a master suite with a freestanding tub.
func _sky(pal: Array) -> void:
	var wall: Color = pal[0]
	feature("left", 0.0, 0.3, D - 0.2, 0.0, H, 1, Color(0.36, 0.22, 0.13))
	var sz := D - 6.5
	var sx := W * 0.56
	wall_x(sz, sx, W, sx + 1.2, sx + 3.0, wall)
	box(sx, sx + 0.16, sz, D, 0.0, H, wall, true)
	feature("back", sz, sx + 3.0, W, 0.0, H, 2, Color(0.9, 0.89, 0.87))
	# Linear fireplace set into the slat wall; the lounge round it.
	var fz := 7.6
	box(0.0, 0.5, fz - 2.2, fz + 2.2, 0.0, 1.5, Color(0.15, 0.15, 0.16), true)
	box(0.48, 0.5, fz - 1.9, fz + 1.9, 0.42, 0.82, Color(0.05, 0.05, 0.05))
	gbox(0.44, 0.47, fz - 1.8, fz + 1.8, 0.44, 0.58, Color(1.0, 0.55, 0.18))
	gbox(0.44, 0.46, fz - 1.6, fz + 1.6, 0.58, 0.68, Color(1.0, 0.75, 0.3))
	box(0.0, 0.62, fz - 2.3, fz + 2.3, 1.5, 1.56, Color(0.85, 0.83, 0.78))
	picture("left", 0.0, fz - 1.6, fz + 1.6, 2.2, 3.8, [Color(0.85, 0.82, 0.76), Color(0.7, 0.55, 0.4)])
	asset("sofa", 4.6, fz, PI * 0.5)
	asset("coffee", 2.7, fz)
	proxy(4.1, 5.1, fz - 1.4, fz + 1.4, 0.85)
	asset("sofa", 2.6, fz + 3.0)
	proxy(1.2, 4.0, fz + 2.5, fz + 3.5, 0.85)
	asset("chair", 2.4, fz - 2.6, PI)
	_rug(1.0, 5.6, fz - 2.8, fz + 3.6, Color(0.82, 0.8, 0.76))
	tube(Vector3(5.4, 0.0, fz - 1.9), Vector3(5.4, 1.5, fz - 1.9), 0.015, BRASS, 6)
	gbox(5.25, 5.55, fz - 2.05, fz - 1.75, 1.5, 1.72, Color(1.0, 0.9, 0.72))
	# Grand piano at the glass, left of the opening.
	var lacquer := Color(0.03, 0.03, 0.035)
	box(0.9, 2.5, 0.8, 2.8, 0.66, 0.98, lacquer, true)
	box(0.9, 1.6, 2.8, 3.2, 0.66, 0.98, lacquer, true)
	box(0.9, 2.5, 2.85, 3.05, 0.72, 0.76, CHALK)
	_q(m, P(0.92, 0.85, 1.0), P(2.48, 0.85, 1.0), P(2.48, 1.0, 1.75), P(0.92, 1.0, 1.75), Vector3.UP, lacquer)
	for p in [Vector2(1.05, 1.0), Vector2(2.35, 1.0), Vector2(1.7, 2.7)]:
		tube(Vector3(p.x, 0.0, p.y), Vector3(p.x, 0.66, p.y), 0.05, lacquer, 6)
	box(1.2, 2.2, 3.4, 3.75, 0.0, 0.48, lacquer)
	# Dining for eight under a ring chandelier (back left).
	var dz := D - 2.8
	var dcx := 4.4
	asset("dining", dcx - 1.1, dz)
	asset("dining", dcx + 1.1, dz)
	proxy(dcx - 2.2, dcx + 2.2, dz - 0.5, dz + 0.5, 0.8)
	for dx: float in [dcx - 1.8, dcx - 0.6, dcx + 0.6, dcx + 1.8]:
		asset("chair", dx, dz - 0.8, PI)
		asset("chair", dx, dz + 0.8)
	for i in 18:
		var a := TAU * i / 18.0
		var c := Vector3(dcx + cos(a) * 1.2, H - 0.9, dz + sin(a) * 0.6)
		gbox(c.x - 0.05, c.x + 0.05, c.z - 0.05, c.z + 0.05, c.y - 0.03, c.y + 0.03, Color(1.0, 0.88, 0.66))
	tube(Vector3(dcx, H, dz), Vector3(dcx, H - 0.9, dz), 0.01, BRASS, 4)
	cabinet(0.6, 1.1, dz - 1.6, dz + 1.6, 0.9, WALNUT, STONE)  # sideboard on the slat wall
	# Gallery entrance between dining and suite: front door, console, art.
	var gx := (dcx + 2.4 + sx) * 0.5
	box(gx - 0.7, gx + 0.7, D - 0.06, D - 0.01, 0.0, 2.6, WALNUT.darkened(0.3))
	box(gx + 0.5, gx + 0.56, D - 0.12, D - 0.06, 0.9, 1.4, BRASS)
	board("right", sx, D - 3.3, 1.8, 1.7, BRASS)
	picture("back", D, gx - 3.0, gx - 1.1, 1.3, 3.1, [Color(0.55, 0.3, 0.2)])
	picture("back", D, gx + 1.1, gx + 2.6, 1.5, 2.9, [Color(0.2, 0.32, 0.45)])
	box(sx - 0.45, sx, D - 5.4, D - 4.4, 0.0, 0.85, STONE, true)
	tube(Vector3(sx - 0.22, 0.85, D - 4.9), Vector3(sx - 0.22, 1.35, D - 4.9), 0.1, Color(0.15, 0.25, 0.3), 10)
	# Kitchen: marble run along the right wall (in front of the suite), island.
	kitchen_run(true, 4.4, sz - 0.3, CHALK, STONE, BRASS)
	box(W - 0.4, W - 0.04, 4.4, sz - 0.3, 1.6, 2.5, WALNUT)
	box(W - 0.6, W - 0.2, 6.2, 6.8, 0.96, 0.975, FRAME)
	var kx0 := W - 5.4
	var kx1 := W - 2.2
	box(kx0, kx1, 6.6, 7.8, 0.0, 0.9, CHALK, true)
	box(kx0 - 0.1, kx1 + 0.1, 6.5, 7.9, 0.9, 0.96, Color(0.93, 0.92, 0.9))
	for x: float in [kx0 + 0.5, (kx0 + kx1) * 0.5, kx1 - 0.5]:
		stool(x, 8.3, WALNUT)
		hang(x, 7.2, 3.0, BRASS, 0.12)
	# Wine wall by the window, right of the opening.
	box(W - 0.6, W - 0.05, 0.5, 3.8, 0.0, 2.9, WALNUT, true)
	gbox(W - 0.62, W - 0.6, 0.6, 3.7, 0.15, 2.75, Color(1.0, 0.68, 0.32))
	for r in 7:
		var y := 0.3 + r * 0.37
		for i in 10:
			var z := 0.75 + i * 0.31
			tube(Vector3(W - 0.64, y, z), Vector3(W - 0.72, y, z), 0.04, Color(0.12, 0.05, 0.06), 6)
	box(W - 2.6, W - 2.0, 1.0, 1.6, 0.0, 0.9, STONE, true)  # sculpture plinth
	tube(Vector3(W - 2.3, 0.9, 1.3), Vector3(W - 2.3, 1.3, 1.3), 0.2, BRASS, 10)
	tube(Vector3(W - 2.3, 1.3, 1.3), Vector3(W - 2.2, 1.7, 1.35), 0.12, BRASS, 10)
	# Master suite: bed, a freestanding tub behind glass, walk-in wardrobe.
	asset("bed", W - 3.4, D - 1.5)
	proxy(W - 4.35, W - 2.45, D - 2.65, D - 0.35, 0.72)
	for x: float in [W - 4.9, W - 1.9]:
		box(x - 0.25, x + 0.25, D - 0.55, D - 0.15, 0.0, 0.5, WALNUT)
		gbox(x - 0.1, x + 0.1, D - 0.45, D - 0.25, 0.5, 0.78, Color(1.0, 0.85, 0.62))
	tube(Vector3(sx + 1.6, 0.0, D - 1.6), Vector3(sx + 1.6, 0.58, D - 1.6), 0.7, CHALK, 16)
	tube(Vector3(sx + 1.6, 0.5, D - 1.6), Vector3(sx + 1.6, 0.56, D - 1.6), 0.62, Color(0.6, 0.78, 0.82), 16)
	proxy(sx + 0.9, sx + 2.3, D - 2.3, D - 0.9, 0.58)
	pane(sx + 3.0, sx + 3.02, D - 3.2, D - 0.2, 0.0, 2.3)
	box(sx + 0.2, sx + 0.8, sz + 0.5, sz + 3.0, 0.0, 2.5, WALNUT, true)
	_rug(W - 5.4, W - 1.4, D - 3.6, D - 0.4, Color(0.6, 0.55, 0.5))
	plant_big(4.0, 1.0, 1.1)
	plant_big(0.9, D - 0.9, 1.2)
	trophy_shelf(W - 3.8, W - 0.8, WIN_Z, 1.35, 1.0, WALNUT)
	box(kx1 - 1.2, kx1 - 0.75, 6.7, 7.0, 0.96, 0.975, Color(0.15, 0.15, 0.16))  # tablet on the island
	gbox(kx1 - 1.18, kx1 - 0.77, 6.72, 6.98, 0.975, 0.98, Color(0.45, 0.7, 1.0))
	spot("wardrobe", sx + 1.4, sz + 1.8)
	spot("bed", W - 5.6, D - 2.5)
	spot("jobs", kx1 - 1.0, 8.9)
	spot("trophies", W - 2.3, 2.0)
	lights.append([Vector3(dcx, 3.0, dz), Color(1.0, 0.85, 0.65), 1.4, 8.0])
	lights.append([Vector3(1.2, 1.1, fz), Color(1.0, 0.6, 0.3), 1.2, 6.5])
	lights.append([Vector3(W - 3.8, H - 1.6, 7.2), Color(1.0, 0.88, 0.7), 1.2, 8.0])
	lights.append([Vector3(W - 3.6, H - 0.6, D - 2.6), Color(1.0, 0.85, 0.68), 1.0, 7.0])
	lights.append([Vector3(W - 1.0, 1.4, 2.2), Color(1.0, 0.65, 0.3), 0.7, 3.5])
	lights.append([Vector3(gx, H - 0.6, D - 2.0), Color(1.0, 0.88, 0.7), 0.6, 5.0])
	lights.append([Vector3(W * 0.5, H - 1.0, 4.0), Color(1.0, 0.88, 0.72), 0.9, 10.0])  # the front, by the glass


## Ultimate Penthouse: dark stone and brass under a 7 m ceiling; a plunge
## pool along the glass, a mezzanine (real stairs – you can climb it) with
## the Hall of Fame wall and a study, a backlit bar and the master bed
## beneath it, dining for eight and a lounge facing the whole skyline.
func _penthouse(pal: Array) -> void:
	feature("back", D, 0.0, W, 0.0, H, 1, Color(0.32, 0.2, 0.12))
	feature("right", W, 0.0, D, 0.0, H, 2, Color(0.3, 0.3, 0.31))
	feature("left", 0.0, 0.0, D, 0.0, H, 3, Color(0.45, 0.44, 0.42))
	# Brass cove lines in the ceiling.
	gbox(1.0, W - 1.0, 1.2, 1.26, H - 0.04, H - 0.01, Color(1.0, 0.78, 0.45))
	gbox(1.0, W - 1.0, D - 5.6, D - 5.54, H - 0.04, H - 0.01, Color(1.0, 0.78, 0.45))
	# Mezzanine across the back (walkable) with a glass balustrade, reached by
	# floating stairs along the left wall.
	var mz := D - 5.0
	var my := MEZZ
	box(0.3, W - 0.2, mz, D - 0.08, my, my + 0.25, Color(0.16, 0.16, 0.17), true)
	box(0.3, W - 0.2, mz - 0.05, mz, my - 0.02, my + 0.27, BRASS)
	gbox(0.3, W - 0.2, mz + 0.05, mz + 0.4, my - 0.03, my - 0.01, Color(1.0, 0.8, 0.5))  # under-deck light line
	pane(SW + 0.1, W - 0.2, mz + 0.02, mz + 0.06, my + 0.25, my + 1.25)
	col_boxes.append(AABB(P(SW + 0.1, mz + 0.02, my).min(P(W - 0.2, mz + 0.06, my + 1.25)), (P(SW + 0.1, mz + 0.02, my) - P(W - 0.2, mz + 0.06, my + 1.25)).abs()))
	tube(Vector3(SW + 0.1, my + 1.25, mz + 0.04), Vector3(W - 0.2, my + 1.25, mz + 0.04), 0.03, BRASS, 6)
	var steps := 12  # 0.28 m risers (STEP_MAX 0.35 with the physics margin)
	var rise := my / steps
	for i in steps:
		var z0 := mz - (steps - i) * 0.42
		var top := (i + 1) * rise
		box(0.35, SW, z0, z0 + 0.42, top - 0.07, top, WALNUT)
	box(0.32, 0.4, mz - steps * 0.42, mz, 0.0, my, STEEL)  # stringer against the wall
	# The treads are for the eye; underfoot is one smooth slope from the floor
	# to the deck (stepping block by block caught the foot on every edge).
	ramp(0.35, SW, mz - steps * 0.42, mz, my + 0.25)
	tube(Vector3(SW + 0.05, rise + 0.9, mz - steps * 0.42), Vector3(SW + 0.05, my + 0.9, mz), 0.025, BRASS, 6)
	# Up there: the Hall of Fame, bookcases, a study desk and a reading chair.
	board("back", D - 0.02, W * 0.5, my + 1.7, 3.6, BRASS)
	for x: float in [W * 0.5 - 4.0, W * 0.5 + 2.6]:
		box(x, x + 1.4, D - 0.42, D - 0.08, my + 0.25, H - 0.3, WALNUT)
		for k in 6:
			var y := my + 0.35 + k * 0.5
			box(x, x + 1.4, D - 0.42, D - 0.08, y, y + 0.025, WALNUT.darkened(0.2))
			books(x + 0.04, x + 1.36, D - 0.38, D - 0.12, y + 0.025, int(x * 10.0) + k)
	box(W - 6.6, W - 4.6, D - 2.0, D - 1.2, my + 0.95, my + 1.0, WALNUT, true)
	for x: float in [W - 6.5, W - 4.7]:
		box(x - 0.03, x + 0.03, D - 1.95, D - 1.25, my + 0.25, my + 0.95, STEEL)
	gbox(W - 5.9, W - 5.3, D - 1.7, D - 1.5, my + 1.0, my + 1.03, Color(0.55, 0.75, 1.0))
	asset("chair", W - 5.6, D - 2.5, 0.0, my + 0.25)
	tube(Vector3(3.6, my + 0.25, D - 2.6), Vector3(3.6, my + 0.7, D - 2.6), 0.45, Color(0.45, 0.3, 0.2), 12)
	trophy_shelf(4.8, 8.4, D - 0.08, my + 1.0, -1.0, WALNUT)
	box(W - 6.0, W - 5.55, D - 1.9, D - 1.6, my + 1.0, my + 1.015, Color(0.15, 0.15, 0.16))
	# Walk-in wardrobe under the mezzanine (right wall).
	box(W - 0.65, W - 0.05, mz + 0.3, mz + 2.6, 0.0, my - 0.1, WALNUT, true)
	for k in 3:
		var zz := mz + 0.35 + k * 0.76
		box(W - 0.67, W - 0.65, zz, zz + 0.72, 0.1, my - 0.2, WALNUT.darkened(0.2))
		box(W - 0.69, W - 0.67, zz + 0.33, zz + 0.39, 1.0, 1.6, BRASS)
	spot("wardrobe", W - 1.4, mz + 1.4)
	spot("bed", W - 5.4, D - 2.7)
	spot("jobs", W - 5.6, D - 3.0, my + 0.25)
	spot("trophies", 6.6, D - 1.4, my + 0.25)
	# Under the mezzanine: a backlit bar (left), the master bed (right).
	box(4.4, 11.6, D - 2.6, D - 1.9, 0.0, 1.08, Color(0.12, 0.12, 0.13), true)
	box(4.35, 11.65, D - 2.65, D - 1.85, 1.08, 1.14, BRASS)
	gbox(4.6, 11.4, D - 0.12, D - 0.1, 0.9, 3.0, Color(1.0, 0.7, 0.38))
	for y: float in [1.2, 1.75, 2.3]:
		box(4.6, 11.4, D - 0.4, D - 0.12, y, y + 0.03, Color(0.15, 0.15, 0.16))
		for i in 20:
			var bx := 4.8 + i * 0.33
			tube(Vector3(bx, y + 0.03, D - 0.26), Vector3(bx, y + 0.3 + 0.05 * (i % 3), D - 0.26), 0.035,
				[Color(0.3, 0.12, 0.06), Color(0.15, 0.25, 0.12), Color(0.8, 0.75, 0.6)][i % 3], 6)
	for x: float in [5.3, 6.9, 8.5, 10.1]:
		stool(x, D - 3.1, Color(0.5, 0.36, 0.22), 0.78)
	asset("bed", W - 3.4, D - 1.5)
	proxy(W - 4.35, W - 2.45, D - 2.65, D - 0.35, 0.72)
	for x: float in [W - 5.1, W - 1.7]:
		box(x - 0.3, x + 0.3, D - 0.55, D - 0.12, 0.0, 0.5, WALNUT)
		gbox(x - 0.12, x + 0.12, D - 0.45, D - 0.21, 0.5, 0.82, Color(1.0, 0.85, 0.62))
	for zz in range(int(mz + 0.2), int(D)):
		box(W - 6.6, W - 6.54, float(zz), float(zz) + 0.06, 0.0, my, BRASS)  # slat screen
	# Plunge pool beside the glass (left), loungers.
	var pool := [3.2, 10.2, 3.4, 8.4]  # (a clear landing in front of the stairs)
	var cope := Color(0.78, 0.76, 0.7)
	box(pool[0] - 0.3, pool[1] + 0.3, pool[2] - 0.3, pool[2], 0.0, 0.5, cope, true)
	box(pool[0] - 0.3, pool[1] + 0.3, pool[3], pool[3] + 0.3, 0.0, 0.5, cope, true)
	box(pool[0] - 0.3, pool[0], pool[2], pool[3], 0.0, 0.5, cope, true)
	box(pool[1], pool[1] + 0.3, pool[2], pool[3], 0.0, 0.5, cope, true)
	pools.append([pool[0], pool[1], pool[2], pool[3], 0.42])
	for zz: float in [4.4, 6.6]:
		box(10.8, 11.45, zz, zz + 1.7, 0.0, 0.32, Color(0.9, 0.88, 0.84), true)
		_q(m, P(10.8, zz + 1.2, 0.32), P(11.45, zz + 1.2, 0.32), P(11.45, zz + 1.75, 0.8), P(10.8, zz + 1.75, 0.8), Vector3.UP, Color(0.9, 0.88, 0.84))
	# Lounge facing the skyline (right of the runway).
	var lx := W - 6.4
	var lz := 7.6
	asset("sofa", lx, lz + 2.2)
	asset("sofa", lx - 2.8, lz, -PI * 0.5)
	asset("sofa", lx + 2.8, lz, PI * 0.5)
	asset("coffee", lx, lz)
	proxy(lx - 1.4, lx + 1.4, lz + 1.7, lz + 2.7, 0.85)
	proxy(lx - 3.3, lx - 2.3, lz - 1.4, lz + 1.4, 0.85)
	proxy(lx + 2.3, lx + 3.3, lz - 1.4, lz + 1.4, 0.85)
	_rug(lx - 3.8, lx + 3.8, lz - 2.4, lz + 3.2, Color(0.55, 0.5, 0.42))
	# Dining for eight (mid-room, before the mezzanine) under a chandelier.
	var dcx := 14.6
	var dz := 12.6
	asset("dining", dcx - 1.1, dz)
	asset("dining", dcx + 1.1, dz)
	proxy(dcx - 2.2, dcx + 2.2, dz - 0.5, dz + 0.5, 0.8)
	for dx: float in [dcx - 1.8, dcx - 0.6, dcx + 0.6, dcx + 1.8]:
		asset("chair", dx, dz - 0.8, PI)
		asset("chair", dx, dz + 0.8)
	for i in 24:
		var a := TAU * i / 24.0
		var c := Vector3(dcx + cos(a) * 1.4, 4.4 - 0.18 * (i % 2), dz + sin(a) * 0.65)
		gbox(c.x - 0.05, c.x + 0.05, c.z - 0.05, c.z + 0.05, c.y - 0.04, c.y + 0.04, Color(1.0, 0.86, 0.6))
	tube(Vector3(dcx, H, dz), Vector3(dcx, 4.4, dz), 0.012, BRASS, 4)
	# Telescope and sculpture at the corners of the glass.
	for k in 3:
		var ang := TAU * k / 3.0
		tube(Vector3(W - 1.0 + cos(ang) * 0.45, 0.0, 3.4 + sin(ang) * 0.45), Vector3(W - 1.0, 1.15, 3.4), 0.015, BRASS, 4)
	tube(Vector3(W - 1.3, 1.1, 3.7), Vector3(W - 0.7, 1.45, 3.0), 0.075, BRASS, 10)
	box(0.4, 1.3, 3.2, 4.1, 0.0, 1.0, STONE, true)
	ring(Vector3(0.85, 1.65, 3.65), Vector3.FORWARD, 0.55, 0.06, BRASS, 20)
	# A big canvas on the marble wall, and a tall one by the stairs.
	box(W - 0.06, W - 0.02, 4.0, 11.0, 1.6, 5.2, Color(0.08, 0.07, 0.07))
	box(W - 0.07, W - 0.06, 4.1, 7.5, 1.7, 5.1, Color(0.85, 0.4, 0.18))
	box(W - 0.07, W - 0.06, 7.5, 10.9, 1.7, 5.1, Color(0.15, 0.2, 0.35))
	picture("left", 0.0, 4.6, 8.6, 3.8, 6.4, [Color(0.75, 0.7, 0.62), Color(0.2, 0.22, 0.26), Color(0.7, 0.5, 0.3)])
	plant_big(2.6, mz - 3.4, 1.3)
	plant_big(W - 1.0, mz - 1.0, 1.5)
	plant_big(W * 0.5, D - 0.8, 1.2)
	lights.append([Vector3(dcx, 4.0, dz), Color(1.0, 0.84, 0.62), 1.5, 9.0])
	lights.append([Vector3(6.7, 0.6, 5.9), Color(0.45, 0.85, 1.0), 1.3, 7.5])
	lights.append([Vector3(lx, H - 1.6, lz), Color(1.0, 0.86, 0.68), 1.5, 11.0])
	lights.append([Vector3(8.0, 2.0, D - 1.4), Color(1.0, 0.7, 0.4), 1.0, 6.0])
	lights.append([Vector3(W * 0.5, my + 2.4, D - 2.0), Color(1.0, 0.86, 0.68), 1.1, 10.0])
	lights.append([Vector3(W - 3.4, 2.0, D - 2.2), Color(1.0, 0.82, 0.6), 0.8, 5.5])
	lights.append([Vector3(W * 0.5, H - 1.8, 4.5), Color(1.0, 0.86, 0.68), 1.1, 12.0])  # the front, by the glass


## A walkable slope across x0..x1, rising along z from the floor at z0 to
## `top` at z1 (collision only, human layer).
func ramp(x0: float, x1: float, z0: float, z1: float, top: float) -> void:
	var along := (P(1.0, 0.0, 0.0) - P(0.0, 0.0, 0.0)).normalized()
	var inward := (P(0.0, 1.0, 0.0) - P(0.0, 0.0, 0.0)).normalized()
	var run := z1 - z0
	var a := atan2(top, run)
	var slope := (inward * cos(a) + Vector3.UP * sin(a)).normalized()
	var nrm := (Vector3.UP * cos(a) - inward * sin(a)).normalized()
	var length := sqrt(run * run + top * top)
	var centre := P((x0 + x1) * 0.5, (z0 + z1) * 0.5, top * 0.5) - nrm * 0.15
	var b := Basis(along, nrm, slope)
	if b.determinant() < 0.0:
		b = Basis(-along, nrm, slope)  # (the room frame is mirrored on some faces)
	ramps.append([Transform3D(b, centre), Vector3(x1 - x0, 0.3, length + 0.1)])


func proxy(x0: float, x1: float, z0: float, z1: float, height: float) -> void:
	var a := P(x0, z0, 0.0)
	var b := P(x1, z1, height)
	col_boxes.append(AABB(a.min(b), a.max(b) - a.min(b)))
