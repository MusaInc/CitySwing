class_name Hinterland
extends Node3D
## The land round the bay the city sits in: a horseshoe of hills and
## mountains – highest in the west behind Westbank (snow on the peaks, the
## sun sets behind them), lower ranges along the north and south, open sea to
## the east. Beaches and green foothills at the water, forest, rock, snow.
## Backdrop only (1.5–5 km out, far beyond web range): one heightfield mesh,
## triangles under the sea skipped, shaded by height and slope
## (hinterland.gdshader). Power lines come down off the hills on lattice
## pylons and cross the sound to Westbank (PowerLines).
##
## height_at() is pure (no scene access) so tests/tools can sample it.

const BAY_C := Vector2(-80.0, 0.0)   # bay ellipse centre (x, z)
const BAY_R := Vector2(1950.0, 1450.0)
const EXTENT := Rect2(-5600.0, -4600.0, 9800.0, 9200.0)
const CELL := 90.0
const SEA_Y := -1.6


## Ground height at (x, z): below the sea inside the bay, rising beyond it.
static func height_at(x: float, z: float) -> float:
	var q := Vector2((x - BAY_C.x) / BAY_R.x, (z - BAY_C.y) / BAY_R.y)
	var r := q.length()
	# Metres outside the bay's shoreline (roughly; the ellipse is stretched).
	var noise_r := 0.06 * (_fbm(Vector2(x, z) * 0.0011, 3) - 0.5)
	var out := (r - 1.0 - noise_r) * minf(BAY_R.x, BAY_R.y)
	if out < -40.0:
		return -30.0
	var ang := atan2(q.y, q.x)                    # 0 = east, ±PI = west
	var west := clampf(-cos(ang), 0.0, 1.0)       # 1 behind Westbank
	var east := clampf(cos(ang), 0.0, 1.0)
	# Open sea to the east: the land falls away there.
	var lift := 1.0 - smoothstep(0.35, 0.85, east)
	var peak := lerpf(360.0, 1150.0, pow(west, 1.4))
	var rise := smoothstep(0.0, 1.0, clampf(out / lerpf(1400.0, 1900.0, west), 0.0, 1.0))
	var ridges := 0.55 + 0.75 * _ridged(Vector2(x, z) * 0.00042)
	var hills := 30.0 * smoothstep(-40.0, 120.0, out) * (0.6 + _fbm(Vector2(x, z) * 0.004, 2))
	var h := (hills + peak * rise * ridges) * lift
	# Beach: a gentle shelf through the waterline.
	h += clampf(out * 0.08, -6.0, 0.0)
	return h if lift > 0.02 else minf(h, -30.0)


static func _hash(p: Vector2) -> float:
	return fposmod(sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)


static func _vnoise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	var a := _hash(i)
	var b := _hash(i + Vector2(1, 0))
	var c := _hash(i + Vector2(0, 1))
	var d := _hash(i + Vector2(1, 1))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)


static func _fbm(p: Vector2, octaves: int) -> float:
	var s := 0.0
	var w := 0.5
	var tot := 0.0
	for i in octaves:
		s += _vnoise(p) * w
		tot += w
		p = p * 2.03 + Vector2(17.3, 9.1)
		w *= 0.5
	return s / tot


## Sharp-crested ridges (1 - |noise|), a few octaves.
static func _ridged(p: Vector2) -> float:
	var s := 0.0
	var w := 0.6
	for i in 4:
		var n := 1.0 - absf(_vnoise(p) * 2.0 - 1.0)
		s += n * n * w
		p = p * 2.1 + Vector2(5.2, 1.3)
		w *= 0.45
	return s


func _ready() -> void:
	var nx := int(EXTENT.size.x / CELL) + 1
	var nz := int(EXTENT.size.y / CELL) + 1
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	for j in nz:
		for i in nx:
			hs[j * nx + i] = height_at(EXTENT.position.x + i * CELL, EXTENT.position.y + j * CELL)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var map := PackedInt32Array()
	map.resize(nx * nz)
	map.fill(-1)
	var vid := func(i: int, j: int) -> int:
		var k := j * nx + i
		if map[k] < 0:
			map[k] = verts.size()
			var h := hs[k]
			verts.append(Vector3(EXTENT.position.x + i * CELL, h, EXTENT.position.y + j * CELL))
			var hl := hs[j * nx + maxi(i - 1, 0)]
			var hr := hs[j * nx + mini(i + 1, nx - 1)]
			var hd := hs[maxi(j - 1, 0) * nx + i]
			var hu := hs[mini(j + 1, nz - 1) * nx + i]
			normals.append(Vector3(hl - hr, 2.0 * CELL, hd - hu).normalized())
		return map[k]
	for j in nz - 1:
		for i in nx - 1:
			var a := hs[j * nx + i]
			var b := hs[j * nx + i + 1]
			var c := hs[(j + 1) * nx + i]
			var d := hs[(j + 1) * nx + i + 1]
			if maxf(maxf(a, b), maxf(c, d)) < SEA_Y - 2.0:
				continue  # wholly under the sea
			var i0: int = vid.call(i, j)
			var i1: int = vid.call(i + 1, j)
			var i2: int = vid.call(i, j + 1)
			var i3: int = vid.call(i + 1, j + 1)
			idx.append_array([i0, i1, i3, i0, i3, i2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Mountains"
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/world/shaders/hinterland.gdshader")
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 50.0
	add_child(mi)
	var lines := PowerLines.new()
	lines.name = "PowerLines"
	add_child(lines)


func triangle_count() -> int:
	var mi: MeshInstance3D = get_node_or_null("Mountains")
	return mi.mesh.surface_get_array_index_len(0) / 3 if mi else 0
