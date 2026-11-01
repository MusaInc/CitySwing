class_name HomeInteriors
extends RefCounted
## The rooms behind the homes' windows (Apartments): shell (floor, ceiling,
## three walls and the inside of the window wall round the opening), the
## opening's reveals so its edges have depth, frames and mullions, and
## furniture per tier – all simple boxes in the building material (one mesh,
## one draw call per home), with collision on the big pieces (human layer
## only, so webs and bots ignore it) and warm interior lights.
## Layout per room is in room coordinates: x along the window wall from its
## left end (0..W), z inward from the window (0..D), y up from the floor.
## The run from the spawn spot (centre, D/2) to the window is always clear.

const FRAME := Color(0.1, 0.1, 0.11)
## Per tier: wall, floor, ceiling colours.
const PALETTE := [
	[Color(0.78, 0.73, 0.64), Color(0.42, 0.3, 0.21), Color(0.86, 0.85, 0.8)],
	[Color(0.83, 0.81, 0.77), Color(0.5, 0.37, 0.26), Color(0.9, 0.89, 0.86)],
	[Color(0.44, 0.44, 0.45), Color(0.55, 0.55, 0.53), Color(0.3, 0.3, 0.31)],
	[Color(0.9, 0.89, 0.86), Color(0.66, 0.53, 0.38), Color(0.95, 0.94, 0.92)],
	[Color(0.88, 0.86, 0.82), Color(0.16, 0.16, 0.18), Color(0.93, 0.92, 0.9)],
]

var h: Dictionary
var m := BuildingMesher.new()
var W := 0.0
var D := 0.0
var H := 0.0
var col_boxes: Array[AABB] = []   # local frame
var lights: Array = []           # [room point, colour, energy, range]


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
	var r := Apartments.room_box(h)
	# Shell: floor, ceiling, side and back walls (facing in).
	m.top(r.position.x, r.position.z, r.end.x, r.end.z, r.position.y + 0.01, pal[1], BuildingMesher.KIND_TRIM, 0, 0)
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
	match tier:
		0:
			_bedsit(pal)
		1:
			_city(pal)
		2:
			_loft(pal)
		3:
			_sky(pal)
		_:
			_penthouse(pal)
	m._end()
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
	return root


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


func _bedsit(pal: Array) -> void:
	var wood := Color(0.36, 0.24, 0.16)
	# Bed in the back-left corner.
	box(0.15, 1.55, D - 2.15, D - 0.1, 0.0, 0.38, wood, true)
	box(0.2, 1.5, D - 2.1, D - 0.15, 0.38, 0.55, Color(0.9, 0.9, 0.88), true)
	box(0.3, 1.4, D - 0.65, D - 0.25, 0.55, 0.66, Color(0.95, 0.95, 0.95))
	box(0.25, 1.45, D - 1.6, D - 0.75, 0.56, 0.62, Color(0.25, 0.4, 0.62))  # duvet
	# Desk and chair on the right wall, near the window.
	box(W - 0.65, W - 0.05, 0.9, 2.3, 0.72, 0.77, wood, true)
	box(W - 0.6, W - 0.55, 0.95, 2.25, 0.0, 0.72, wood)
	box(W - 0.12, W - 0.07, 0.95, 2.25, 0.0, 0.72, wood)
	box(W - 1.15, W - 0.75, 1.4, 1.8, 0.0, 0.45, Color(0.2, 0.2, 0.22))
	box(W - 0.45, W - 0.3, 1.0, 1.15, 0.77, 1.15, Color(0.95, 0.8, 0.5))  # lamp
	box(W - 0.55, W - 0.15, 1.7, 2.0, 0.77, 1.05, Color(0.12, 0.12, 0.14))  # laptop screen
	# Kitchenette along the back-right.
	box(W - 1.9, W - 0.05, D - 0.65, D - 0.05, 0.0, 0.9, Color(0.86, 0.85, 0.82), true)
	box(W - 1.9, W - 0.05, D - 0.65, D - 0.05, 0.9, 0.94, Color(0.3, 0.3, 0.32))
	box(W - 1.6, W - 0.2, D - 0.4, D - 0.05, 1.5, 2.1, Color(0.86, 0.85, 0.82))
	# Shelf with books, poster, rug, plant.
	box(1.9, 3.1, D - 0.3, D - 0.02, 1.45, 1.5, wood)
	for i in 6:
		box(1.95 + i * 0.18, 2.08 + i * 0.18, D - 0.28, D - 0.06, 1.5, 1.72 + 0.04 * (i % 3),
			Color.from_hsv(fmod(i * 0.17, 1.0), 0.45, 0.7))
	box(0.0, 0.03, 1.0, 2.2, 1.2, 2.0, Color(0.85, 0.35, 0.25))  # poster
	_rug(1.8, W - 1.4, 1.4, D - 1.2, Color(0.55, 0.42, 0.3))
	box(0.2, 0.6, 0.4, 0.8, 0.0, 0.9, Color(0.24, 0.45, 0.25))
	lights.append([Vector3(W * 0.5, H - 0.4, D * 0.6), Color(1.0, 0.82, 0.6), 1.2, 6.0])


func _city(pal: Array) -> void:
	var wood := Color(0.42, 0.29, 0.19)
	var fabric := Color(0.32, 0.42, 0.5)
	# Sofa against the back wall, coffee table, rug.
	box(W * 0.5 - 1.6, W * 0.5 + 1.6, D - 0.95, D - 0.1, 0.0, 0.45, fabric, true)
	box(W * 0.5 - 1.6, W * 0.5 + 1.6, D - 0.35, D - 0.1, 0.45, 0.9, fabric.darkened(0.1))
	box(W * 0.5 - 0.8, W * 0.5 + 0.8, D - 2.1, D - 1.5, 0.0, 0.4, wood, true)
	_rug(W * 0.5 - 2.0, W * 0.5 + 2.0, D - 2.6, D - 0.9, Color(0.75, 0.68, 0.55))
	# Bed in the left-back corner with a headboard.
	box(0.15, 1.75, D - 2.3, D - 0.1, 0.0, 0.42, wood, true)
	box(0.2, 1.7, D - 2.25, D - 0.25, 0.42, 0.6, Color(0.92, 0.92, 0.9), true)
	box(0.15, 1.75, D - 0.12, D - 0.05, 0.0, 1.1, wood.darkened(0.2))
	# Kitchen along the right wall, dining table front-left.
	box(W - 0.65, W - 0.05, 2.0, D - 1.0, 0.0, 0.92, Color(0.9, 0.9, 0.88), true)
	box(W - 0.65, W - 0.05, 2.0, D - 1.0, 0.92, 0.96, Color(0.2, 0.2, 0.22))
	box(W - 0.4, W - 0.05, 2.2, D - 1.2, 1.55, 2.2, Color(0.9, 0.9, 0.88))
	box(0.5, 1.7, 1.2, 2.4, 0.72, 0.77, wood, true)
	box(1.05, 1.15, 1.75, 1.85, 0.0, 0.72, wood)
	for zc in [1.0, 2.6]:
		box(0.85, 1.35, zc - 0.2, zc + 0.2, 0.0, 0.46, Color(0.25, 0.25, 0.27))
	# Floor lamp, plant, art.
	box(W * 0.5 + 1.9, W * 0.5 + 2.0, D - 0.5, D - 0.4, 0.0, 1.6, Color(0.15, 0.15, 0.15))
	box(W * 0.5 + 1.8, W * 0.5 + 2.1, D - 0.6, D - 0.3, 1.6, 1.85, Color(1.0, 0.9, 0.7))
	box(W - 1.0, W - 0.5, 0.4, 0.9, 0.0, 1.2, Color(0.22, 0.45, 0.25))
	box(W * 0.5 - 1.0, W * 0.5 + 1.0, D - 0.03, D, 1.3, 2.2, Color(0.2, 0.35, 0.55))
	lights.append([Vector3(W * 0.5, H - 0.4, D * 0.55), Color(1.0, 0.85, 0.65), 1.4, 8.0])


func _loft(pal: Array) -> void:
	var steel := Color(0.12, 0.12, 0.13)
	var leather := Color(0.4, 0.24, 0.14)
	# Exposed steel beams across the ceiling and a brick feature wall.
	var nb := int(W / 2.5)
	for i in range(1, nb + 1):
		var x := minf(i * 2.5 - 0.6, W - 0.3)
		box(x - 0.12, x + 0.12, 0.0, D, H - 0.4, H - 0.01, steel)
	box(0.0, 0.04, 0.3, D, 0.0, H, Color(0.55, 0.3, 0.22))  # brick wall (left)
	# L-shaped leather sofa back-left, big rug, low table.
	box(0.3, 3.6, D - 0.95, D - 0.15, 0.0, 0.45, leather, true)
	box(0.3, 3.6, D - 0.4, D - 0.15, 0.45, 0.85, leather.darkened(0.15))
	box(0.3, 1.1, D - 2.9, D - 0.95, 0.0, 0.45, leather, true)
	_rug(0.9, 4.6, D - 3.4, D - 0.6, Color(0.7, 0.62, 0.5))
	box(1.7, 3.0, D - 2.5, D - 1.6, 0.0, 0.38, Color(0.3, 0.22, 0.15), true)
	# Kitchen along the right wall with an island.
	box(W - 0.7, W - 0.05, 1.8, D - 2.4, 0.0, 0.95, Color(0.18, 0.18, 0.19), true)
	box(W - 0.7, W - 0.05, 1.8, D - 2.4, 0.95, 1.0, Color(0.75, 0.74, 0.7))
	box(W - 2.9, W - 1.7, 2.6, D - 3.2, 0.0, 0.95, Color(0.75, 0.74, 0.7), true)
	for i in 3:
		box(W - 3.35, W - 3.05, 2.8 + i * 0.6, 3.1 + i * 0.6, 0.0, 0.75, steel)
	# Bed on a platform back-right.
	box(W - 2.6, W - 0.1, D - 2.3, D - 0.1, 0.0, 0.3, Color(0.3, 0.22, 0.15), true)
	box(W - 2.5, W - 0.2, D - 2.2, D - 0.2, 0.3, 0.5, Color(0.9, 0.89, 0.86), true)
	# Bookshelf on the brick wall near the window, pendant lights.
	box(0.05, 0.45, 0.8, 3.4, 0.0, 2.4, steel, true)
	for i in 12:
		box(0.08, 0.4, 0.9 + (i % 6) * 0.42, 1.2 + (i % 6) * 0.42, 0.5 + (i / 6) * 0.9, 0.82 + (i / 6) * 0.9,
			Color.from_hsv(fmod(i * 0.13, 1.0), 0.4, 0.65))
	for x in [W - 2.6, W - 2.0]:
		box(x - 0.01, x + 0.01, 3.4, 3.42, 2.4, H - 0.4, steel)
		box(x - 0.18, x + 0.18, 3.25, 3.6, 2.2, 2.4, Color(0.95, 0.75, 0.4))
	lights.append([Vector3(W * 0.3, H - 0.6, D * 0.65), Color(1.0, 0.8, 0.55), 1.6, 9.0])
	lights.append([Vector3(W * 0.75, H - 1.6, D * 0.45), Color(1.0, 0.82, 0.6), 1.2, 7.0])


func _sky(pal: Array) -> void:
	var fabric := Color(0.86, 0.84, 0.8)
	var oak := Color(0.55, 0.42, 0.3)
	var marble := Color(0.92, 0.91, 0.88)
	# Sectional sofa facing the view, coffee table, big rug.
	box(W * 0.5 - 2.5, W * 0.5 + 2.5, D - 1.4, D - 0.4, 0.0, 0.42, fabric, true)
	box(W * 0.5 - 2.5, W * 0.5 + 2.5, D - 0.7, D - 0.4, 0.42, 0.8, fabric.darkened(0.06))
	box(W * 0.5 + 1.6, W * 0.5 + 2.5, D - 3.2, D - 1.4, 0.0, 0.42, fabric, true)
	box(W * 0.5 - 1.0, W * 0.5 + 1.0, D - 2.8, D - 2.1, 0.0, 0.36, marble, true)
	_rug(W * 0.5 - 3.0, W * 0.5 + 3.0, D - 3.8, D - 0.6, Color(0.42, 0.4, 0.38))
	# Dining front-right, kitchen island back-right.
	box(W - 2.9, W - 0.7, 1.5, 3.0, 0.74, 0.8, oak, true)
	box(W - 1.9, W - 1.7, 2.15, 2.35, 0.0, 0.74, Color(0.2, 0.2, 0.2))
	for xc in [W - 2.6, W - 2.0, W - 1.4, W - 0.9]:
		box(xc - 0.2, xc + 0.2, 1.05, 1.4, 0.0, 0.48, Color(0.3, 0.3, 0.32))
	box(W - 3.0, W - 0.6, D - 4.4, D - 3.4, 0.0, 0.95, marble, true)
	box(W - 0.6, W - 0.05, D - 5.5, D - 0.1, 0.0, 2.3, Color(0.3, 0.3, 0.32), true)  # tall units
	# Bed zone back-left with a headboard and side tables.
	box(0.3, 2.5, D - 2.5, D - 0.15, 0.0, 0.45, oak, true)
	box(0.35, 2.45, D - 2.45, D - 0.3, 0.45, 0.62, Color(0.95, 0.95, 0.94), true)
	box(0.3, 2.5, D - 0.15, D - 0.08, 0.0, 1.3, oak.darkened(0.2))
	# Art, plants, floor lamp.
	box(W * 0.5 - 1.5, W * 0.5 + 1.5, D - 0.03, D, 1.2, 2.6, Color(0.75, 0.45, 0.25))
	box(0.3, 0.8, 0.5, 1.0, 0.0, 1.6, Color(0.2, 0.42, 0.24))
	box(W - 1.0, W - 0.5, 0.5, 1.0, 0.0, 1.4, Color(0.2, 0.42, 0.24))
	box(W * 0.5 - 2.9, W * 0.5 - 2.8, D - 0.6, D - 0.5, 0.0, 1.7, Color(0.75, 0.7, 0.55))
	lights.append([Vector3(W * 0.5, H - 0.3, D * 0.6), Color(1.0, 0.88, 0.72), 1.6, 10.0])
	lights.append([Vector3(W * 0.82, H - 0.3, D * 0.3), Color(1.0, 0.88, 0.72), 1.0, 7.0])


func _penthouse(pal: Array) -> void:
	var cream := Color(0.9, 0.87, 0.8)
	var walnut := Color(0.32, 0.2, 0.13)
	var brass := Color(0.78, 0.62, 0.3)
	var black := Color(0.07, 0.07, 0.08)
	# Living: a long sectional facing the panorama, marble table, rugs.
	box(1.0, 6.4, D - 1.5, D - 0.4, 0.0, 0.42, cream, true)
	box(1.0, 6.4, D - 0.75, D - 0.4, 0.42, 0.82, cream.darkened(0.06))
	box(1.0, 2.0, D - 4.2, D - 1.5, 0.0, 0.42, cream, true)
	box(2.8, 4.8, D - 3.2, D - 2.2, 0.0, 0.34, Color(0.92, 0.92, 0.9), true)
	_rug(0.6, 6.8, D - 5.0, D - 0.7, Color(0.55, 0.5, 0.45))
	# Grand piano by the glass on the left.
	box(1.0, 2.6, 1.6, 3.2, 0.62, 0.95, black, true)
	box(1.1, 1.2, 1.7, 1.8, 0.0, 0.62, black)
	box(2.4, 2.5, 1.7, 1.8, 0.0, 0.62, black)
	box(1.7, 1.8, 3.0, 3.1, 0.0, 0.62, black)
	box(1.2, 2.4, 3.3, 3.7, 0.0, 0.48, black)
	# Dining for eight on the right with a brass pendant.
	box(W - 5.2, W - 2.2, 2.0, 3.4, 0.74, 0.8, walnut, true)
	box(W - 3.8, W - 3.6, 2.6, 2.8, 0.0, 0.74, brass)
	for i in 4:
		for sd in [1.6, 3.8]:
			var xc := W - 4.8 + i * 0.85
			box(xc - 0.2, xc + 0.2, sd - 0.2, sd + 0.2, 0.0, 0.5, Color(0.25, 0.24, 0.24))
	box(W - 4.4, W - 3.0, 2.5, 2.9, H - 1.3, H - 1.15, brass)
	box(W - 3.71, W - 3.69, 2.69, 2.71, H - 1.15, H, brass)
	# Kitchen: a long island and a wall of tall units (back right).
	box(W - 5.5, W - 1.8, D - 4.0, D - 3.0, 0.0, 0.95, Color(0.95, 0.95, 0.93), true)
	box(W - 5.5, W - 1.8, D - 4.0, D - 3.0, 0.95, 1.0, Color(0.85, 0.84, 0.8))
	box(W - 6.0, W - 0.1, D - 0.6, D - 0.05, 0.0, 2.6, walnut, true)
	box(W - 0.6, W - 0.05, D - 6.0, D - 0.6, 0.0, 0.95, walnut, true)
	# Bar cart, sculpture, tall plants, art, a second seating corner.
	box(6.8, 7.6, D - 1.0, D - 0.5, 0.0, 0.9, brass)
	box(W - 1.9, W - 1.5, 0.9, 1.3, 0.0, 0.9, Color(0.3, 0.3, 0.3))
	box(W - 1.85, W - 1.55, 0.95, 1.25, 0.9, 1.9, Color(0.85, 0.85, 0.85))
	for p in [Vector2(0.4, 0.5), Vector2(W - 0.9, 0.5), Vector2(6.5, D - 0.6)]:
		box(p.x, p.x + 0.5, p.y, p.y + 0.5, 0.0, 0.45, Color(0.85, 0.83, 0.78))
		box(p.x + 0.05, p.x + 0.45, p.y + 0.05, p.y + 0.45, 0.45, 2.0, Color(0.2, 0.42, 0.24))
	box(1.5, 5.5, D - 0.03, D, 1.4, 3.4, Color(0.15, 0.3, 0.5))
	box(0.0, 0.03, 4.5, 9.0, 1.2, 3.2, Color(0.8, 0.55, 0.3))
	box(W - 2.2, W - 0.9, 5.0, 6.1, 0.0, 0.42, cream, true)
	box(W - 2.2, W - 0.9, 6.1, 6.4, 0.0, 0.8, cream.darkened(0.06))
	lights.append([Vector3(W * 0.25, H - 0.4, D * 0.6), Color(1.0, 0.86, 0.68), 1.8, 11.0])
	lights.append([Vector3(W * 0.75, H - 1.4, D * 0.3), Color(1.0, 0.8, 0.55), 1.6, 9.0])
	lights.append([Vector3(W * 0.6, H - 0.4, D * 0.8), Color(1.0, 0.88, 0.72), 1.2, 9.0])
