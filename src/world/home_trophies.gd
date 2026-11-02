class_name HomeTrophies
extends Node3D
## Your achievements, on a shelf in your home: a medal for every Time Trial
## course (an empty stand until you earn one), a cup that grows with your
## contract rank, a jar that fills with the tokens you've found, and a fold
## of every suit colour you've unlocked. Built from SaveData; rebuilt when it
## changes (checked every few seconds while the camera is near). Batched into
## four meshes (metal, matte, glass, glow) with vertex colours: four draw calls.
##
## `upper` and `lower` are the two shelf rows (building-local start/end
## points, items stand along them), `out` the direction they face.

var upper: Array = []   # [from, to] (local frame of the parent)
var lower: Array = []
var out := Vector3.FORWARD
var _sig := ""
var _t := 0.0

const CUP_COLORS := [Color(0.55, 0.56, 0.58), Color(0.72, 0.45, 0.25), Color(0.78, 0.8, 0.84), Color(0.95, 0.72, 0.25),
	Color(0.85, 0.9, 0.95), Color(1.0, 0.8, 0.3)]

static var _mats := {}


func _ready() -> void:
	refresh()


func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 4.0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam and cam.global_position.distance_to(global_position) < 30.0:
		refresh()


## [course medals], rank, tokens, unlocked suit colours.
static func snapshot() -> Dictionary:
	var medals: Array = []
	for id in CourseBuilder.COURSES:
		medals.append([String(CourseBuilder.COURSES[id]["name"]), Progress.course_medal(id)])
	var sd: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/SaveData")
	var d: Dictionary = sd.data if sd else {}
	var suits: Array = []
	for s in Progress.SUITS:
		if Progress.unlocked(s):
			suits.append(s["color"])
	return {"medals": medals, "rank": Contracts.rank_for(int(d.get("rep", 0))),
		"tokens": (d.get("tokens", []) as Array).size(), "suits": suits}


func refresh() -> void:
	var snap := snapshot()
	var sig := str(snap)
	if sig == _sig:
		return
	_sig = sig
	for c in get_children():
		c.queue_free()
	_buckets = {"metal": [], "matte": [], "glass": [], "glow": []}
	var b := Basis.looking_at(-out, Vector3.UP)  # local -Z faces the room
	# Upper row: the medals.
	var medals: Array = snap["medals"]
	for i in medals.size():
		var p: Vector3 = (upper[0] as Vector3).lerp(upper[1], (i + 0.5) / medals.size())
		_medal(p, b, int(medals[i][1]))
	# Lower row: cup, token jar, suit folds.
	var a: Vector3 = lower[0]
	var z: Vector3 = lower[1]
	var run := a.distance_to(z)
	var dir := (z - a).normalized()
	_cup(a + dir * minf(0.3, run * 0.15), b, int(snap["rank"]))
	_jar(a + dir * minf(0.85, run * 0.38), b, float(snap["tokens"]) / Progress.TOKEN_TOTAL)
	var suits: Array = snap["suits"]
	var s0 := minf(1.3, run * 0.55)
	for i in suits.size():
		var t := s0 + (run - s0 - 0.12) * (i + 0.5) / maxf(suits.size(), 1.0)
		_fold(a + dir * t, b, suits[i])
	for kind in _buckets:
		var parts: Array = _buckets[kind]
		if parts.is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in parts:
			_append(st, part[0], part[1], part[2])
		var m := MeshInstance3D.new()
		m.name = kind
		m.mesh = st.commit()
		m.material_override = _material(kind)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visibility_range_end = 40.0
		add_child(m)


var _buckets := {}


func _add(kind: String, mesh: PrimitiveMesh, xf: Transform3D, c: Color) -> void:
	_buckets[kind].append([mesh, xf, c])


static func _append(st: SurfaceTool, mesh: PrimitiveMesh, xf: Transform3D, c: Color) -> void:
	var arr := mesh.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nb := xf.basis.inverse().transposed()
	for k in idx:
		st.set_color(c)
		st.set_normal((nb * n[k]).normalized())
		st.add_vertex(xf * v[k])


static func _material(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	match kind:
		"metal":
			m.metallic = 0.9
			m.roughness = 0.26
		"matte":
			m.roughness = 0.7
		"glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic_specular = 0.9
		"glow":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[kind] = m
	return m


func _medal(p: Vector3, b: Basis, medal: int) -> void:
	var dark := Color(0.12, 0.12, 0.13)
	var stand := BoxMesh.new()
	stand.size = Vector3(0.06, 0.02, 0.08)
	_add("metal", stand, Transform3D(b, p + Vector3.UP * 0.01), dark)
	var post := CylinderMesh.new()
	post.top_radius = 0.006
	post.bottom_radius = 0.006
	post.height = 0.17
	post.radial_segments = 6
	_add("metal", post, Transform3D(b, p + Vector3.UP * 0.095), dark)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.085
	disc.bottom_radius = 0.085
	disc.height = 0.014
	disc.radial_segments = 24
	var face := b * Basis(Vector3.RIGHT, PI * 0.5)  # disc axis toward the room
	if medal > 0:
		_add("metal", disc, Transform3D(face, p + Vector3.UP * 0.26), Progress.MEDAL_COLORS[medal])
		var rib := BoxMesh.new()
		rib.size = Vector3(0.045, 0.11, 0.004)
		var rc: Color = [Color(), Color(0.7, 0.18, 0.15), Color(0.15, 0.3, 0.6), Color(0.1, 0.45, 0.3)][medal]
		_add("matte", rib, Transform3D(b, p + Vector3.UP * 0.37 - b.z * 0.01), rc)
	else:
		_add("glass", disc, Transform3D(face, p + Vector3.UP * 0.26), Color(0.8, 0.85, 0.9, 0.18))


func _cup(p: Vector3, b: Basis, rank: int) -> void:
	var s := 1.0 + rank * 0.16
	var c: Color = CUP_COLORS[clampi(rank, 0, CUP_COLORS.size() - 1)]
	var base := BoxMesh.new()
	base.size = Vector3(0.1, 0.05, 0.1) * s
	_add("matte", base, Transform3D(b, p + Vector3.UP * 0.025 * s), Color(0.1, 0.08, 0.07))
	var stem := CylinderMesh.new()
	stem.top_radius = 0.012 * s
	stem.bottom_radius = 0.03 * s
	stem.height = 0.09 * s
	stem.radial_segments = 12
	_add("metal", stem, Transform3D(b, p + Vector3.UP * 0.095 * s), c)
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.07 * s
	bowl.bottom_radius = 0.02 * s
	bowl.height = 0.11 * s
	bowl.radial_segments = 20
	_add("metal", bowl, Transform3D(b, p + Vector3.UP * 0.195 * s), c)
	for side: float in [-1.0, 1.0]:
		var hd := TorusMesh.new()
		hd.inner_radius = 0.022 * s
		hd.outer_radius = 0.03 * s
		hd.rings = 12
		hd.ring_segments = 6
		_add("metal", hd, Transform3D(b * Basis(Vector3.FORWARD, PI * 0.5), p + Vector3.UP * 0.2 * s + b.x * side * 0.075 * s), c)


func _jar(p: Vector3, b: Basis, frac: float) -> void:
	var glass := CylinderMesh.new()
	glass.top_radius = 0.09
	glass.bottom_radius = 0.095
	glass.height = 0.32
	glass.radial_segments = 20
	_add("glass", glass, Transform3D(b, p + Vector3.UP * 0.16), Color(0.85, 0.92, 0.95, 0.22))
	var lid := CylinderMesh.new()
	lid.top_radius = 0.08
	lid.bottom_radius = 0.09
	lid.height = 0.025
	lid.radial_segments = 20
	_add("metal", lid, Transform3D(b, p + Vector3.UP * 0.332), Color(0.74, 0.57, 0.3))
	if frac > 0.0:
		var fill := CylinderMesh.new()
		var hgt := 0.3 * clampf(frac, 0.03, 1.0)
		fill.top_radius = 0.083
		fill.bottom_radius = 0.088
		fill.height = hgt
		fill.radial_segments = 20
		_add("glow", fill, Transform3D(b, p + Vector3.UP * (0.01 + hgt * 0.5)), Color(0.2, 0.95, 0.85))


func _fold(p: Vector3, b: Basis, c: Color) -> void:
	var f := BoxMesh.new()
	f.size = Vector3(0.14, 0.08, 0.2)
	_add("matte", f, Transform3D(b, p + Vector3.UP * 0.04), c)
	var f2 := BoxMesh.new()
	f2.size = Vector3(0.14, 0.01, 0.2)
	_add("matte", f2, Transform3D(b, p + Vector3.UP * 0.085), c.lightened(0.15))
