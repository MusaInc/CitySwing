class_name TokenField
extends Node3D
## Free Swing collectibles: Progress.TOKEN_TOTAL glowing tokens placed
## deterministically over the city (same spots every launch, so collection
## persists by id). Roughly a third float just above rooftops; the rest hang
## in the gaps between tall buildings at swing height, where only a good line
## reaches them.

signal collected(id: int, remaining: int)

const COLLECT_RADIUS := 4.0
const MIN_SPACING := 55.0
const SEED := 20261027

var spots: Array[Vector3] = []
var _nodes := {}  # id -> Node3D
var _mat: StandardMaterial3D
var _spin := 0.0


## Positions only (no scene access), so tests and tools can reuse them.
static func generate(layout: CityLayout) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var tall: Array = []  # [top centre (y = roof height)]
	for b in layout.buildings:
		if b["kind"] != "normal":
			continue
		var top: Array = b["tiers"][-1]
		if top[5] >= 28.0 and top[5] <= 150.0:
			tall.append(CityLayout.top_center(b))
	var grid := _tier_grid(layout)
	var out: Array[Vector3] = []
	if tall.is_empty():
		return out
	var roof_quota := Progress.TOKEN_TOTAL / 3
	for attempt in 4000:
		if out.size() >= Progress.TOKEN_TOTAL:
			break
		var ca: Vector3 = tall[rng.randi() % tall.size()]
		var p := Vector3.INF
		if out.size() < roof_quota:
			p = ca + Vector3.UP * 3.5
		else:
			# Mid-air between this building and a neighbour across a street.
			var near: Array = []
			for cb in tall:
				var d := Vector2(ca.x - cb.x, ca.z - cb.z).length()
				if d >= 35.0 and d <= 80.0:
					near.append(cb)
			if near.is_empty():
				continue
			var cb: Vector3 = near[rng.randi() % near.size()]
			var mx := (ca.x + cb.x) * 0.5
			var mz := (ca.z + cb.z) * 0.5
			var g := layout.ground_y(mx, mz)
			var h := (minf(ca.y, cb.y) - g) * rng.randf_range(0.45, 0.7)
			if h < 14.0:
				continue
			p = Vector3(mx, g + h, mz)
		var ok := not _blocked(grid, p)
		for q in out:
			if not ok:
				break
			ok = q.distance_to(p) >= MIN_SPACING
		if ok:
			out.append(p)
	return out


const GRID := 40.0


## Buildings bucketed by GRID-sized cells (each in every cell its tiers' world
## bounds touch).
static func _tier_grid(layout: CityLayout) -> Dictionary:
	var g := {}
	for b in layout.buildings:
		for t in b["tiers"]:
			var bx := CityLayout.tier_aabb(b, t)
			for cx in range(floori(bx.position.x / GRID), floori(bx.end.x / GRID) + 1):
				for cz in range(floori(bx.position.z / GRID), floori(bx.end.z / GRID) + 1):
					var k := Vector2i(cx, cz)
					if not g.has(k):
						g[k] = []
					if (g[k] as Array).is_empty() or not is_same(g[k][-1], b):
						g[k].append(b)
	return g


## True when a token at `p` would sit inside (or touching) a building.
static func _blocked(grid: Dictionary, p: Vector3) -> bool:
	var m := COLLECT_RADIUS + 1.5
	for cx in range(floori((p.x - m) / GRID), floori((p.x + m) / GRID) + 1):
		for cz in range(floori((p.z - m) / GRID), floori((p.z + m) / GRID) + 1):
			for b in grid.get(Vector2i(cx, cz), []):
				if CityLayout.inside(b, p, m, 1.5):
					return true
	return false


func setup(layout: CityLayout) -> void:
	spots = generate(layout)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(0.45, 1.0, 0.85)
	_mat.emission_enabled = true
	_mat.emission = Color(0.3, 1.0, 0.8)
	_mat.emission_energy_multiplier = 2.0
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_mat.albedo_color = Color(0.4, 1.0, 0.85, 0.22)
	var gem := SphereMesh.new()  # 4×2 segments: a faceted octahedron
	gem.radius = 1.2
	gem.height = 3.2
	gem.radial_segments = 4
	gem.rings = 2
	var halo := QuadMesh.new()
	halo.size = Vector2(5.5, 5.5)
	for i in spots.size():
		if _save().has_token(i):
			continue
		var n := Node3D.new()
		n.name = "Token%d" % i
		n.position = spots[i]
		var g := MeshInstance3D.new()
		g.name = "Gem"
		g.mesh = gem
		g.material_override = _mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(g)
		var hq := MeshInstance3D.new()
		hq.mesh = halo
		hq.material_override = halo_mat
		hq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(hq)
		add_child(n)
		_nodes[i] = n


func remaining() -> int:
	return _nodes.size()


## Nearest uncollected token to `p`, or Vector3.INF when all are collected.
func nearest(p: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for i in _nodes:
		var d := p.distance_squared_to(spots[i])
		if d < bd:
			bd = d
			best = spots[i]
	return best


## Collects every token the segment a→b passed close to. Returns ids taken.
func check(a: Vector3, b: Vector3) -> Array:
	var got := []
	for i in _nodes.keys():
		var q: Vector3 = spots[i]
		var closest := Geometry3D.get_closest_point_to_segment(q, a, b)
		if closest.distance_to(q) <= COLLECT_RADIUS:
			got.append(i)
	for i in got:
		(_nodes[i] as Node3D).queue_free()
		_nodes.erase(i)
		_save().collect_token(i)
		collected.emit(i, _nodes.size())
	return got


func _process(dt: float) -> void:
	_spin += dt * 1.8
	var bob := sin(_spin * 1.3) * 0.4
	for i in _nodes:
		var g: Node3D = _nodes[i].get_child(0)
		g.rotation.y = _spin + i
		g.position.y = bob


## Looked up by path so tools run with -s (no autoload globals) can load this.
func _save() -> Node:
	return get_node("/root/SaveData")
