class_name HomeInteriors
extends RefCounted
## The rooms behind the homes' windows (Apartments): shell (floor, ceiling,
## three walls and the inside of the window wall round the opening), the
## opening's reveals so its edges have depth, frames and mullions, and
## furniture per tier – an architectural shell batched in the building material and shared
## Blender furniture, with collision on the big pieces (human layer
## only, so webs and bots ignore it) and warm interior lights.
## Layout per room is in room coordinates: x along the window wall from its
## left end (0..W), z inward from the window (0..D), y up from the floor.
## The run from the spawn spot (centre, D/2) to the window is always clear.

const FRAME := Color(0.1, 0.1, 0.11)
## Per tier: wall, floor, ceiling colours.
const PALETTE := [
	[Color(0.78, 0.73, 0.64), Color(0.42, 0.3, 0.21), Color(0.86, 0.85, 0.8)],
	[Color(0.83, 0.81, 0.77), Color(0.5, 0.37, 0.26), Color(0.9, 0.89, 0.86)],
	[Color(0.72, 0.70, 0.65), Color(0.38, 0.3, 0.23), Color(0.82, 0.81, 0.76)],
	[Color(0.9, 0.89, 0.86), Color(0.66, 0.53, 0.38), Color(0.95, 0.94, 0.92)],
	[Color(0.88, 0.86, 0.82), Color(0.48, 0.35, 0.23), Color(0.93, 0.92, 0.9)],
]

var h: Dictionary
var m := BuildingMesher.new()
var W := 0.0
var D := 0.0
var H := 0.0
var col_boxes: Array[AABB] = []   # local frame
var assets: Array = []
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
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = floor_mat
	floor_node.transform = xf * Transform3D(Basis(f[1], Vector3.UP, f[2]), P(W * 0.5, D * 0.5, 0.01))
	floor_node.visibility_range_end = 420.0
	root.add_child(floor_node)
	_place_assets(root)
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


## Shared metric furniture; no per-home material duplication. x/z are room coordinates.
func asset(id: String, x: float, z: float, yaw := 0.0) -> void:
	assets.append([id, x, z, yaw])

func _place_assets(root: Node3D) -> void:
	var xf := CityLayout.bxf(h["b"])
	var f := Apartments.face_of(h)
	var basis := Basis(f[1], Vector3.UP, f[2])
	for item in assets:
		var scene := load("res://assets/models/home_%s.glb" % item[0]) as PackedScene
		var node := scene.instantiate() as Node3D
		node.transform = xf * Transform3D(basis, P(item[1], item[2], 0.02)) * Transform3D(Basis(Vector3.UP, item[3]), Vector3.ZERO)
		root.add_child(node)
		for child in node.find_children("*", "MeshInstance3D"):
			child.visibility_range_end = 160.0

func _residence(tier: int, pal: Array) -> void:
	var wood := Color(0.3, 0.2, 0.13)
	var stone := Color(0.8, 0.78, 0.7)
	var split: float = D * [0.59, 0.57, 0.62, 0.65, 0.68][tier]
	var left: float = W * [0.38, 0.36, 0.38, 0.35, 0.38][tier]
	var right: float = W * [0.68, 0.7, 0.72, 0.75, 0.78][tier]
	# Rear bedroom, central hallway, bathroom. Door openings are 1.2 m wide.
	box(0.0, left - 1.3, split, split + 0.16, 0.0, H, pal[0], true)
	box(left - 1.3, left, split, split + 0.16, 2.35, H, pal[0], true)
	box(left, left + 0.16, split, D, 0.0, H, pal[0], true)
	box(right, right + 0.16, split, D, 0.0, H, pal[0], true)
	box(right, right + 1.25, split, split + 0.16, 2.35, H, pal[0], true)
	box(right + 1.25, W, split, split + 0.16, 0.0, H, pal[0], true)
	var bed_x := maxf(1.75, left * 0.55)
	asset("bed", bed_x, D - 1.4)
	proxy(bed_x - 0.93, bed_x + 0.93, D - 2.55, D - 0.25, 0.72)
	# Wardrobe with recessed door joints in the bedroom.
	box(0.12, 0.72, split + 0.35, D - 0.35, 0.0, 2.3, wood, true)
	for z in range(int(D - split - 0.7)):
		box(0.72, 0.75, split + 0.38 + z, split + 0.42 + z, 0.08, 2.22, FRAME)
	# The collision proxy is hidden inside the authored mattress.
	asset("vanity", W - 0.72, D - 0.65)
	asset("toilet", right + 0.7, D - 0.65)
	box(right + 0.2, W - 0.2, split + 0.3, D - 0.1, 0.012, 0.026, stone)
	box(W - 1.3, W - 0.2, split + 0.3, split + 1.4, 0.03, 0.08, Color(0.55, 0.6, 0.58))
	# Living room faces the open skyline; centre runway remains unobstructed.
	asset("sofa", 1.75, split - 1.0)
	asset("coffee", 1.75, split - 2.55)
	_rug(0.25, 3.25, maxf(0.8, split - 3.6), split - 0.4, Color(0.56, 0.52, 0.43))
	proxy(0.35, 3.15, split - 1.5, split - 0.5, 0.85)
	# Kitchen: recessed plinth, individual cabinet doors, stone worktop, hob.
	var kz := maxf(2.0, split - 1.2)
	box(W - 0.7, W - 0.08, 1.8, kz + 0.6, 0.1, 0.9, wood, true)
	box(W - 0.76, W - 0.05, 1.75, kz + 0.65, 0.9, 0.96, stone)
	for i in range(int((kz - 1.2) / 0.6)):
		var z := 1.8 + i * 0.6
		box(W - 0.72, W - 0.7, z + 0.02, z + 0.57, 0.18, 0.85, pal[0])
		box(W - 0.75, W - 0.72, z + 0.18, z + 0.42, 0.73, 0.75, FRAME)
	box(W - 0.65, W - 0.15, 2.0, 2.6, 0.96, 0.975, FRAME)
	if tier > 0:
		asset("dining", W - 2.5, split - 1.8)
		for x: float in [W - 3.2, W - 1.8]:
			asset("chair", x, split - 2.6, PI)
			asset("chair", x, split - 1.0)
	if tier >= 3:
		# Second lounge, gallery and kitchen island in the generous great room.
		asset("sofa", W - 3.7, 2.3, PI)
		asset("coffee", W - 3.7, 3.8)
		box(W - 4.5, W - 2.0, split - 4.2, split - 3.2, 0.0, 0.94, wood, true)
		box(W - 4.6, W - 1.9, split - 4.3, split - 3.1, 0.94, 1.0, stone)
	if tier >= 2:
		# Exposed ceiling coffers over the living spaces, safely above traversal.
		for x: float in [W * 0.25, W * 0.75]:
			box(x - 0.12, x + 0.12, 0.15, split, H - 0.24, H - 0.02, wood)
	if tier == 4:
		# Study suite behind the gallery, with an open doorway off the hallway.
		box(left + 0.16, right - 1.3, D - 4.2, D - 4.04, 0.0, H, pal[0], true)
		asset("dining", W * 0.52, D - 1.7)
		asset("chair", W * 0.52, D - 2.5, PI)
		asset("plant", W * 0.62, D - 0.6)
	for x: float in [0.55, W - 0.55]:
		asset("plant", x, 0.85)
		# Cove cornices and skirting give the shell thickness and human scale.
	box(0.02, 0.12, 0.1, D, 0.02, 0.16, wood)
	box(W - 0.12, W - 0.02, 0.1, D, 0.02, 0.16, wood)
	box(0.0, W, D - 0.12, D - 0.02, 0.02, 0.16, wood)
	for x: float in [0.12, W - 0.22]:
		box(x, x + 0.1, 0.1, D - 0.1, H - 0.16, H - 0.08, stone)
	# Framed abstract triptych above the sofa.
	for i in 3:
		box(0.4 + i * 0.85, 1.12 + i * 0.85, split - 0.045, split - 0.02, 1.4, 2.45, wood)
		box(0.44 + i * 0.85, 1.08 + i * 0.85, split - 0.052, split - 0.046, 1.44, 2.41, Color(0.22 + i * 0.12, 0.35, 0.36))
	for p in [Vector3(W * 0.25, H - 0.4, split * 0.5), Vector3(W * 0.78, H - 0.4, split * 0.5), Vector3(left * 0.5, H - 0.3, D - 1.8), Vector3(W - 1.4, H - 0.3, D - 1.6)]:
		lights.append([p, Color(1.0, 0.88, 0.73), 1.1, maxf(5.0, W * 0.45)])

func proxy(x0: float, x1: float, z0: float, z1: float, height: float) -> void:
	var a := P(x0, z0, 0.0)
	var b := P(x1, z1, height)
	col_boxes.append(AABB(a.min(b), a.max(b) - a.min(b)))
