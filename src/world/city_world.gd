class_name CityWorld
extends Node3D
## The procedural city at runtime.
##  * Collision for every building tier is created up front (cheap boxes on the
##    world + grappleable layers), so traversal never depends on streaming.
##  * Visuals stream by distance in 200 m chunks: mesh arrays are generated on
##    worker threads (~1.6 ms/chunk on the dev VPS) and turned into nodes on
##    the main thread, a couple per frame.
##  * Each chunk has a detailed LOD (cornices, plinths) and a low LOD (plain
##    massing) switched with visibility ranges, MultiMesh props with short
##    ranges, GPU-animated traffic, and an occluder for occlusion culling.

const CHUNK := CityLayout.CHUNK
const MODEL_DIR := "res://assets/models/"
const PROP_RANGES := {
	"streetlight": 260.0, "tree": 420.0, "water_tower": 520.0, "ac_unit": 240.0, "antenna": 700.0, "crane": 1200.0,
	"traffic_light": 220.0, "roof_hut": 650.0,
}
const MARKS_RANGE := 320.0
const CAR_COLORS := [Color(0.85, 0.85, 0.83), Color(0.1, 0.1, 0.11), Color(0.62, 0.08, 0.07), Color(0.12, 0.24, 0.45),
	Color(0.55, 0.57, 0.6), Color(0.9, 0.72, 0.15), Color(0.2, 0.35, 0.3)]

var layout: CityLayout
var viewer: Node3D
var detail_range := 380.0
var view_distance := 900.0
var prop_density := 1.0
var traffic_density := 1.0
var max_builds_per_frame := 2

var building_mat: ShaderMaterial
var ground_mat: ShaderMaterial
var water_mat: ShaderMaterial
var prop_meshes := {}
var car_mesh: Mesh
var walker_mesh: Mesh
var _walk_paths: Array = []  # [from, to] pavement segments (directional)
const WALKER_RANGE := 170.0
const CLOTHES := [Color(0.85, 0.85, 0.82), Color(0.12, 0.13, 0.16), Color(0.55, 0.12, 0.12), Color(0.16, 0.28, 0.5),
	Color(0.36, 0.42, 0.3), Color(0.75, 0.6, 0.35), Color(0.45, 0.45, 0.48), Color(0.62, 0.36, 0.5), Color(0.2, 0.45, 0.48)]

var _by_chunk := {}
var _props_by_chunk := {}
var _all_keys: Array[Vector2i] = []
var _loaded := {}      # key -> Node3D
var _pending := {}     # key -> WorkerThreadPool task id
var _results := {}     # key -> Dictionary of mesh arrays
var _mutex := Mutex.new()
var _want := {}        # key -> distance, from the latest streaming update
var chunks_built := 0
var gen_ms_total := 0.0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	layout = CityLayout.new().generate()
	_by_chunk = layout.buildings_by_chunk()
	_props_by_chunk = layout.props_by_chunk()
	var settings := get_node_or_null("/root/Settings")
	if settings:
		var p: Dictionary = settings.preset()
		view_distance = p["view_distance"]
		prop_density = p["props"]
		traffic_density = p["traffic"]
		detail_range = minf(380.0, view_distance * 0.45)
	_materials()
	_load_props()
	for cx in range(floori(CityLayout.RIVER_EDGE / CHUNK) - 1, ceili((CityLayout.MAX_X + 200.0) / CHUNK)):
		for cz in range(floori((CityLayout.MIN_Z - 100.0) / CHUNK), ceili((CityLayout.MAX_Z + 100.0) / CHUNK)):
			_all_keys.append(Vector2i(cx, cz))
	_build_collision()
	_build_water()
	_build_landmarks()
	_build_structures()
	_build_outskirts()
	GrappleTargeting.anchor_lines = layout.anchor_lines
	print("CityWorld: %d buildings, %d props, %d chunks, layout+collision %d ms" % [
		layout.buildings.size(), layout.props.size(), _all_keys.size(), Time.get_ticks_msec() - t0])


func _exit_tree() -> void:
	if GrappleTargeting.anchor_lines == layout.anchor_lines:
		GrappleTargeting.anchor_lines = []


func set_viewer(v: Node3D) -> void:
	viewer = v


func spawn_point() -> Vector3:
	# A tall rooftop near the business district with open avenue ahead.
	var best: Dictionary = {}
	var best_score := -INF
	for b in layout.buildings:
		if b["kind"] != "normal":
			continue
		var t: Array = b["tiers"][-1]
		var c := Vector2((t[0] + t[2]) * 0.5, (t[1] + t[3]) * 0.5)
		var h: float = t[5]
		if h < 55.0 or h > 95.0 or t[2] - t[0] < 14.0 or t[3] - t[1] < 14.0:
			continue
		var s := -c.distance_to(CityLayout.CBD_CENTER + Vector2(-60, 260)) - absf(h - 75.0) * 2.0
		if s > best_score:
			best_score = s
			best = b
	if best.is_empty():
		return Vector3(300, 120, 0)
	var t2: Array = best["tiers"][-1]
	return Vector3((t2[0] + t2[2]) * 0.5, t2[5] + 2.0, (t2[1] + t2[3]) * 0.5)


## Clearance (m) to keep from each kind of rooftop prop when standing.
const PROP_CLEARANCE := {"water_tower": 6.0, "ac_unit": 4.0, "antenna": 3.0, "roof_hut": 5.5}
const ROOF_EDGE_CLEARANCE := 4.5

var _roof_spawns: Array = []


## Every rooftop that makes a good start: high enough for an exciting first
## swing, big enough to walk on, clear of props, facing a promising route.
## [{position: Vector3 (capsule centre, standing), yaw: float, height: float}]
func rooftop_spawns() -> Array:
	if not _roof_spawns.is_empty():
		return _roof_spawns
	var roof_props := {}
	for pr in layout.props:
		if pr[0] in PROP_CLEARANCE:
			var o: Vector3 = pr[1].origin
			var k := Vector2i(roundi(o.x / 50.0), roundi(o.z / 50.0))
			if not roof_props.has(k):
				roof_props[k] = []
			roof_props[k].append(pr)
	for b in layout.buildings:
		if b["kind"] != "normal":
			continue
		var t: Array = b["tiers"][-1]
		var h: float = t[5]
		if h < 45.0 or h > 115.0 or t[2] - t[0] < 18.0 or t[3] - t[1] < 18.0:
			continue
		var spot := _clear_spot(t, roof_props)
		if spot.is_empty():
			continue
		var p := Vector3(spot["x"], h + 0.6 + 0.95, spot["z"])
		_roof_spawns.append({"position": p, "height": h})  # yaw is computed when picked
	return _roof_spawns


## Picks a valid rooftop, avoiding `avoid` (the previous spawn) when possible.
func random_rooftop(rng: RandomNumberGenerator, avoid := Vector3.INF) -> Dictionary:
	var all := rooftop_spawns()
	if all.is_empty():
		return {"position": spawn_point(), "yaw": 0.0, "height": 0.0}
	var fallback := {}
	for attempt in 24:
		var c: Dictionary = all[rng.randi() % all.size()]
		if not c.has("yaw"):
			c["yaw"] = _best_heading(c["position"], c["height"])
			if not is_nan(c["yaw"]) and not _web_in_reach(c["position"], c["yaw"]):
				c["yaw"] = NAN  # nothing to web from a standstill here
		if is_nan(c["yaw"]):
			continue  # nowhere promising to swing from this roof
		if avoid == Vector3.INF or c["position"].distance_to(avoid) > 150.0:
			return c
		fallback = c
	return fallback if not fallback.is_empty() else {"position": spawn_point(), "yaw": 0.0, "height": 0.0}


var _spawn_params: SwingParams


## True if holding SWING on this roof, facing `yaw`, finds an anchor.
func _web_in_reach(p: Vector3, yaw: float) -> bool:
	if not is_inside_tree():
		return true
	if _spawn_params == null:
		_spawn_params = load("res://config/swing_params.tres")
	var dir := Vector3.FORWARD.rotated(Vector3.UP, yaw)
	var t := GrappleTargeting.new()
	t.update(get_world_3d().direct_space_state, p + Vector3.UP * 0.5, (dir + Vector3.UP * 0.2).normalized(),
		Vector3.ZERO, _spawn_params, true, [])
	return t.has_target


func _clear_spot(t: Array, roof_props: Dictionary) -> Dictionary:
	var x0: float = t[0] + ROOF_EDGE_CLEARANCE
	var z0: float = t[1] + ROOF_EDGE_CLEARANCE
	var x1: float = t[2] - ROOF_EDGE_CLEARANCE
	var z1: float = t[3] - ROOF_EDGE_CLEARANCE
	var nearby: Array = []
	var c := Vector2i(roundi((t[0] + t[2]) * 0.25 / 25.0), roundi((t[1] + t[3]) * 0.25 / 25.0))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			nearby.append_array(roof_props.get(c + Vector2i(dx, dz), []))
	var best := {}
	var best_margin := 0.0
	for i in 5:
		for j in 5:
			var x := lerpf(x0, x1, i / 4.0)
			var z := lerpf(z0, z1, j / 4.0)
			var margin := 30.0
			for pr in nearby:
				var o: Vector3 = pr[1].origin
				if absf(o.y - t[5]) > 1.0:
					continue
				margin = minf(margin, Vector2(o.x - x, o.z - z).length() - PROP_CLEARANCE[pr[0]])
			if margin > best_margin:
				best_margin = margin
				best = {"x": x, "z": z}
	return best


## Direction with the most taller anchors ahead and nothing blocking the run-up.
## Returns the camera-style yaw (looking along -Z rotated by yaw), NAN if none.
func _best_heading(p: Vector3, roof_h: float) -> float:
	var best := NAN
	var best_s := 0.5
	for k in 8:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 8.0)
		var score := 0.0
		var blocked := false
		for b in layout.buildings:
			if b["kind"] == "invisible":
				continue
			var t: Array = b["tiers"][0]
			var top: float = b["tiers"][-1][5]
			var near := Vector3(clampf(p.x, t[0], t[2]), 0.0, clampf(p.z, t[1], t[3]))
			var off := Vector3(near.x - p.x, 0.0, near.z - p.z)
			var d := off.length()
			if d < 0.5:
				continue  # the building we're standing on
			var along := off.dot(dir)
			if along > 0.0 and d < 9.0 and top > roof_h + 2.0 and off.normalized().dot(dir) > 0.7:
				blocked = true
			if d < 25.0 or d > 110.0 or off.normalized().dot(dir) < 0.8 or top < roof_h + 5.0:
				continue
			score += minf(top - roof_h, 60.0) / d
		if not blocked and score > best_s:
			best_s = score
			best = atan2(-dir.x, -dir.z)
	return best


func bot_heading() -> Vector3:
	return Vector3.FORWARD


## Autopilot goal: down the nearest north–south avenue, ahead of the player.
func bot_goal(p: Node3D) -> Vector3:
	var x := p.global_position.x
	var best := x
	var bd := INF
	for s in layout.x_streets:
		if absf(s[0] - x) < bd and s[1] > 20.0:
			bd = absf(s[0] - x)
			best = s[0]
	var z := p.global_position.z - 90.0
	if z < CityLayout.MIN_Z + 60.0:
		z = CityLayout.MAX_Z  # turn round at the edge of the map
	return Vector3(best, 0.0, z)


func is_water(p: Vector3) -> bool:
	return layout.is_water(p)


# ------------------------------------------------------------- materials
func _materials() -> void:
	building_mat = ShaderMaterial.new()
	building_mat.shader = load("res://src/world/shaders/building.gdshader")
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = load("res://src/world/shaders/ground.gdshader")
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://src/world/shaders/water.gdshader")


func set_sky_colors(top: Color, horizon: Color) -> void:
	for m in [building_mat, water_mat]:
		m.set_shader_parameter("sky_top", top)
		m.set_shader_parameter("sky_horizon", horizon)


func _load_mesh(name: String) -> Mesh:
	var path := MODEL_DIR + name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	var inst := scene.instantiate()
	var mis := inst.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (mis[0] as MeshInstance3D).mesh if mis.size() > 0 else null
	inst.free()
	return mesh


func _load_props() -> void:
	for k in ["streetlight", "tree", "water_tower", "ac_unit", "antenna", "crane", "viaduct", "clock_crown",
			"harbour_dome", "beacon", "cathedral_top", "traffic_light", "roof_hut"]:
		var m := _load_mesh(k)
		if m:
			prop_meshes[k] = m
	var car := _load_mesh("car")
	if car:
		car_mesh = car.duplicate()
		var shader: Shader = load("res://src/world/shaders/traffic.gdshader")
		for i in car_mesh.get_surface_count():
			var src := car_mesh.surface_get_material(i)
			var sm := ShaderMaterial.new()
			sm.shader = shader
			var name := String(src.resource_name) if src else ""
			if src is BaseMaterial3D:
				sm.set_shader_parameter("tint", (src as BaseMaterial3D).albedo_color)
			sm.set_shader_parameter("use_instance_color", name == "paint")
			sm.set_shader_parameter("emission", 2.0 if name.begins_with("lamp") else 0.0)
			car_mesh.surface_set_material(i, sm)
	var walker := _load_mesh("pedestrian")
	if walker:
		walker_mesh = walker.duplicate()
		var wshader: Shader = load("res://src/world/shaders/pedestrian.gdshader")
		for i in walker_mesh.get_surface_count():
			var src := walker_mesh.surface_get_material(i)
			var sm := ShaderMaterial.new()
			sm.shader = wshader
			if src is BaseMaterial3D:
				sm.set_shader_parameter("tint", (src as BaseMaterial3D).albedo_color)
			sm.set_shader_parameter("use_instance_color", src != null and String(src.resource_name) == "shirt")
			walker_mesh.surface_set_material(i, sm)
	_walk_paths = _pavement_paths()


# ------------------------------------------------------------- collision
func _build_collision() -> void:
	var by_chunk := _by_chunk
	for key in by_chunk:
		var body := StaticBody3D.new()
		body.name = "Col_%d_%d" % [key.x, key.y]
		body.collision_layer = 1 | (1 << 1)
		body.collision_mask = 0
		for b in by_chunk[key]:
			for t in b["tiers"]:
				var shape := CollisionShape3D.new()
				var box := BoxShape3D.new()
				var lip := 0.6 if b["kind"] in ["normal", "landmark"] else 0.0
				box.size = Vector3(t[2] - t[0], t[5] - t[4] + lip, t[3] - t[1])
				shape.shape = box
				shape.position = Vector3((t[0] + t[2]) * 0.5, (t[4] + t[5] + lip) * 0.5, (t[1] + t[3]) * 0.5)
				body.add_child(shape)
		add_child(body)
	var street := StaticBody3D.new()
	street.name = "Street"
	street.collision_layer = 1 << 3
	street.collision_mask = 0
	street.add_to_group("street")
	for r in layout.land:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x, 2.0, r.size.y)
		shape.shape = box
		shape.position = Vector3(r.get_center().x, -0.9, r.get_center().y)
		street.add_child(shape)
	add_child(street)
	var water_floor := StaticBody3D.new()
	water_floor.name = "WaterFloor"
	water_floor.collision_layer = 1 << 3
	water_floor.add_to_group("street")
	water_floor.add_to_group("water")
	for w in layout.water:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(w.size.x, 2.0, w.size.y)
		shape.shape = box
		shape.position = Vector3(w.get_center().x, -4.0, w.get_center().y)
		water_floor.add_child(shape)
	add_child(water_floor)


func _build_water() -> void:
	var m := BuildingMesher.new()
	for w in layout.water:
		var r: Rect2 = w
		m.top(r.position.x, r.position.y, r.end.x, r.end.y, -1.6, Color.WHITE, 0, 0, 0)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.arrays())
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = mesh
	mi.material_override = water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_landmarks() -> void:
	var groups := {}
	for lm in layout.landmarks:
		if not groups.has(lm[0]):
			groups[lm[0]] = []
		groups[lm[0]].append(lm[1])
	for k in groups:
		var mesh: Mesh = prop_meshes.get(k)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = groups[k].size()
		for i in groups[k].size():
			mm.set_instance_transform(i, groups[k][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Landmark_" + k
		mmi.multimesh = mm
		add_child(mmi)


## Cranes and the bridge: one mesh per structure (own culling box), detailed
## lattices near, solid massing far. Always loaded – they're the skyline's
## landmarks and few in number. Collision comes from the layout boxes.
func _build_structures() -> void:
	for i in layout.structures.size():
		var s: Dictionary = layout.structures[i]
		var root := Node3D.new()
		root.name = "Structure_%s_%d" % [s["type"], i]
		for detailed in [true, false]:
			var m := BuildingMesher.new()
			m.add_structure(s, detailed)
			var mi := MeshInstance3D.new()
			mi.name = "Detail" if detailed else "Low"
			mi.mesh = _mesh_from(m.arrays())
			mi.material_override = building_mat
			if detailed:
				mi.visibility_range_end = detail_range
				mi.visibility_range_end_margin = 30.0
			else:
				mi.visibility_range_begin = detail_range
				mi.visibility_range_begin_margin = 30.0
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
		add_child(root)


## Low-detail skyline beyond the playable grid (and a far river shore) so every
## horizon reads as city. One mesh, low LOD only; outskirt blocks still collide.
func _build_outskirts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.seed * 31
	var m := BuildingMesher.new()
	var col_body := StaticBody3D.new()
	col_body.name = "OutskirtsCol"
	col_body.collision_layer = 1 | (1 << 1)
	var styles := [CityLayout.Style.BRICK, CityLayout.Style.STONE, CityLayout.Style.MODERN, CityLayout.Style.SANDSTONE,
		CityLayout.Style.BRICK]
	var near_m := BuildingMesher.new()  # detailed, close to the playable grid
	var blocks_m := BuildingMesher.new()  # pavements, kerbs and lawns of the outer blocks
	# The street grid carries on past the playable area: blocks with kerbs and
	# pavements, filled with lower, older buildings that thin out with
	# distance – so every edge reads as more city, not an empty apron.
	var xr_in := _block_ranges(layout.x_streets)
	var zr_in := _block_ranges(layout.z_streets)
	var last_x: Array = layout.x_streets[-1]
	var xr_out := _extend_ranges(last_x[0] + last_x[1] * 0.5, 1.0, 760.0, rng)
	var first_z: Array = layout.z_streets[0]
	var last_z: Array = layout.z_streets[-1]
	var zr_out := _extend_ranges(first_z[0] - first_z[1] * 0.5, -1.0, 760.0, rng) \
		+ _extend_ranges(last_z[0] + last_z[1] * 0.5, 1.0, 760.0, rng)
	var grid := Rect2(CityLayout.MIN_X, CityLayout.MIN_Z, CityLayout.MAX_X - CityLayout.MIN_X, CityLayout.MAX_Z - CityLayout.MIN_Z)
	for xr in xr_in + xr_out:
		for zr in zr_in + zr_out:
			if xr in xr_in and zr in zr_in:
				continue  # the playable city
			var blk := Rect2(xr[0], zr[0], xr[1] - xr[0], zr[1] - zr[0])
			var c := blk.get_center()
			var far := maxf(maxf(c.x - grid.end.x, grid.position.y - c.y), c.y - grid.end.y)
			var near := far < 230.0
			var brng := RandomNumberGenerator.new()
			brng.seed = hash(Vector2i(int(c.x), int(c.y))) ^ layout.seed
			var park := brng.randf() < 0.1
			blocks_m.top(blk.position.x, blk.position.y, blk.end.x, blk.end.y, 0.15,
				Color(0.32, 0.45, 0.24) if park else Color(0.58, 0.57, 0.55), BuildingMesher.KIND_ROOF, 0, 0)
			blocks_m.walls(blk.position.x, blk.position.y, blk.end.x, blk.end.y, 0.0, 0.15, Color(0.7, 0.69, 0.66),
				BuildingMesher.KIND_TRIM, 0, 0)
			if park:
				continue
			var lots: Array = []
			var inner := blk.grow(-3.5)
			var fx := brng.randf_range(0.35, 0.65)
			var fz := brng.randf_range(0.35, 0.65)
			for i in 2:
				for j in 2:
					var lx0 := inner.position.x + (0.0 if i == 0 else inner.size.x * fx)
					var lx1 := inner.position.x + (inner.size.x * fx if i == 0 else inner.size.x)
					var lz0 := inner.position.y + (0.0 if j == 0 else inner.size.y * fz)
					var lz1 := inner.position.y + (inner.size.y * fz if j == 0 else inner.size.y)
					lots.append(Rect2(lx0, lz0, lx1 - lx0, lz1 - lz0).grow(-1.2))
			if brng.randf() < 0.35:
				lots = [inner.grow(-1.2)]  # one big building (warehouse, offices)
			for r in lots:
				if r.size.x < 8.0 or r.size.y < 8.0 or brng.randf() < 0.08:
					continue
				var tall := brng.randf() < maxf(0.18 - far * 0.0003, 0.03)
				var h := brng.randf_range(42.0, 80.0) if tall else brng.randf_range(10.0, 30.0)
				var st: int = styles[brng.randi() % styles.size()]
				var cols: Array = CityLayout.STYLE_COLORS[st]
				var bd := {"tiers": [[r.position.x, r.position.y, r.end.x, r.end.y, 0.0, h]], "style": st,
					"color": (cols[brng.randi() % cols.size()] as Color).lightened(brng.randf_range(-0.05, 0.05)),
					"kind": "normal", "seed": brng.randf()}
				if near:
					near_m.add_building(bd, true)
					var shape := CollisionShape3D.new()
					var box := BoxShape3D.new()
					box.size = Vector3(r.size.x, h + 0.6, r.size.y)
					shape.shape = box
					shape.position = Vector3(r.get_center().x, (h + 0.6) * 0.5, r.get_center().y)
					col_body.add_child(shape)
				else:
					m.add_building(bd, false)
	# Far shore across the river (where the bridge lands): a quay road, then
	# terraces and a few towers. Near the bridge they collide, so it's a place
	# to land, not a painted backdrop.
	var shore_x := CityLayout.FAR_SHORE - 40.0
	var z2 := -2200.0
	while z2 < 2200.0:
		var w2 := rng.randf_range(24.0, 50.0)
		var d2 := rng.randf_range(24.0, 50.0)
		var bx := shore_x - w2 - rng.randf_range(0.0, 30.0)
		var near_bridge := absf(z2 - CityLayout.BRIDGE_Z) < 300.0
		while bx > shore_x - (520.0 if near_bridge else 260.0):
			if absf(z2 + d2 * 0.5 - CityLayout.BRIDGE_Z) < 40.0 + d2 * 0.5:
				break  # keep the bridge's landing road open
			var h2 := rng.randf_range(10.0, 26.0) if rng.randf() > 0.12 else rng.randf_range(40.0, 75.0)
			var st2: int = [CityLayout.Style.BRICK, CityLayout.Style.STONE, CityLayout.Style.SANDSTONE][rng.randi() % 3]
			var cols2: Array = CityLayout.STYLE_COLORS[st2]
			var b2 := {"tiers": [[bx, z2, bx + w2, z2 + d2, 0.0, h2]], "style": st2,
				"color": cols2[rng.randi() % cols2.size()], "kind": "normal", "seed": rng.randf()}
			m.add_building(b2, near_bridge)
			if near_bridge:
				var shape2 := CollisionShape3D.new()
				var box2 := BoxShape3D.new()
				box2.size = Vector3(w2, h2, d2)
				shape2.shape = box2
				shape2.position = Vector3(bx + w2 * 0.5, h2 * 0.5, z2 + d2 * 0.5)
				col_body.add_child(shape2)
			bx -= w2 + rng.randf_range(14.0, 24.0)
		z2 += d2 + rng.randf_range(14.0, 24.0)
	m.top(-2600.0, -2600.0, CityLayout.FAR_SHORE, 2600.0, 0.0, Color(0.33, 0.33, 0.34), BuildingMesher.KIND_ROOF, 0, 0)
	m.walls(CityLayout.FAR_SHORE - 0.6, -2600.0, CityLayout.FAR_SHORE, 2600.0, -4.0, 1.1, Color(0.42, 0.38, 0.33),
		BuildingMesher.KIND_TRIM, 0, 0)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.arrays())
	var mi := MeshInstance3D.new()
	mi.name = "Outskirts"
	mi.mesh = mesh
	mi.material_override = building_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var g := BuildingMesher.new()
	# Under everything, minus the dock basins (their water sits below street level).
	var rects: Array = [Rect2(CityLayout.RIVER_EDGE, CityLayout.MIN_Z - 1000.0,
		CityLayout.MAX_X + 1000.0 - CityLayout.RIVER_EDGE, CityLayout.MAX_Z - CityLayout.MIN_Z + 2000.0)]
	for w in layout.water:
		if (w as Rect2).position.x < 0.0:
			continue
		var next: Array = []
		for r in rects:
			next.append_array(CityLayout._subtract(r, w))
		rects = next
	for r in rects:
		g.top(r.position.x, r.position.y, r.end.x, r.end.y, -0.02, Color(0.22, 0.23, 0.24), BuildingMesher.KIND_ROOF, 0, 0)
	var gmesh := ArrayMesh.new()
	gmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g.arrays())
	var gi := MeshInstance3D.new()
	gi.name = "OutskirtsGround"
	gi.mesh = gmesh
	gi.material_override = ground_mat
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gi)
	var bi := MeshInstance3D.new()
	bi.name = "OutskirtsBlocks"
	bi.mesh = _mesh_from(blocks_m.arrays())
	bi.material_override = ground_mat
	bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bi)
	if not near_m.is_empty():
		var ni := MeshInstance3D.new()
		ni.name = "OutskirtsNear"
		ni.mesh = _mesh_from(near_m.arrays())
		ni.material_override = building_mat
		add_child(ni)
	add_child(col_body)


## [start, end] of each block between consecutive streets ([centre, width] list).
static func _block_ranges(streets: Array) -> Array:
	var out: Array = []
	for i in streets.size() - 1:
		out.append([streets[i][0] + streets[i][1] * 0.5, streets[i + 1][0] - streets[i + 1][1] * 0.5])
	return out


## Blocks continuing outward from `edge` (a street's outer kerb) in direction
## `sgn`, with 16 m streets between, out to `reach` metres.
static func _extend_ranges(edge: float, sgn: float, reach: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var d := 0.0
	while d < reach:
		var w := rng.randf_range(60.0, 92.0)
		var a := edge + sgn * d
		var b := edge + sgn * (d + w)
		out.append([minf(a, b), maxf(a, b)])
		d += w + 16.0
	return out


# ------------------------------------------------------------- streaming
func _process(_dt: float) -> void:
	if viewer == null:
		return
	update_streaming(viewer.global_position)


## Request/instantiate/free chunks around `pos`. `budget` caps instantiations.
func update_streaming(pos: Vector3, budget := -1) -> void:
	if budget < 0:
		budget = max_builds_per_frame
	var here := Vector2(pos.x, pos.z)
	var want := {}
	for key in _all_keys:
		var c := (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK
		var d := c.distance_to(here)
		if d < view_distance + CHUNK * 0.75:
			want[key] = d
		elif _loaded.has(key) and d > view_distance + CHUNK * 1.25:
			_loaded[key].queue_free()
			_loaded.erase(key)
	_want = want
	# Nearest first.
	var order := want.keys()
	order.sort_custom(func(a, b): return want[a] < want[b])
	var in_flight := _pending.size()
	for key in order:
		if _loaded.has(key) or _pending.has(key):
			continue
		if in_flight >= 3:
			break
		_request(key)
		in_flight += 1
	_collect(budget)


func _request(key: Vector2i) -> void:
	_pending[key] = WorkerThreadPool.add_task(_generate.bind(key), false, "city chunk")


func _generate(key: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	var res := generate_chunk_arrays(key)
	res["usec"] = Time.get_ticks_usec() - t0
	_mutex.lock()
	_results[key] = res
	_mutex.unlock()


## Pure data: mesh arrays for one chunk. Safe to call from worker threads.
func generate_chunk_arrays(key: Vector2i) -> Dictionary:
	var rect := Rect2(Vector2(key) * CHUNK, Vector2(CHUNK, CHUNK))
	var detail := BuildingMesher.new()
	var low := BuildingMesher.new()
	var ground := BuildingMesher.new()
	var marks := BuildingMesher.new()
	for b in _by_chunk.get(key, []):
		detail.add_building(b, true)
		low.add_building(b, false)
	ground.add_ground(layout, rect)
	marks.add_road_marks(layout, rect)
	return {
		"detail": null if detail.is_empty() else detail.arrays(),
		"low": null if low.is_empty() else low.arrays(),
		"ground": null if ground.is_empty() else ground.arrays(),
		"marks": null if marks.is_empty() else marks.arrays(),
	}


func _collect(budget: int) -> void:
	var done: Array = []
	for key in _pending:
		if WorkerThreadPool.is_task_completed(_pending[key]):
			WorkerThreadPool.wait_for_task_completion(_pending[key])
			done.append(key)
	for key in done:
		_pending.erase(key)
	var built := 0
	_mutex.lock()
	var keys := _results.keys()
	_mutex.unlock()
	for key in keys:
		if built >= budget:
			break
		_mutex.lock()
		var res: Dictionary = _results[key]
		_results.erase(key)
		_mutex.unlock()
		if not _want.has(key):
			continue  # viewer moved on while this chunk was generating
		_instantiate(key, res)
		built += 1


## Blocks until every chunk within `radius` of `pos` is built (loading screen).
func build_all_near(pos: Vector3, radius: float) -> void:
	var here := Vector2(pos.x, pos.z)
	for key in _all_keys:
		var c := (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK
		if c.distance_to(here) < radius and not _loaded.has(key):
			var t0 := Time.get_ticks_usec()
			var res := generate_chunk_arrays(key)
			res["usec"] = Time.get_ticks_usec() - t0
			_instantiate(key, res)


func _mesh_from(arrays) -> ArrayMesh:
	if arrays == null:
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _instantiate(key: Vector2i, res: Dictionary) -> void:
	if _loaded.has(key):
		return
	gen_ms_total += res.get("usec", 0) / 1000.0
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [key.x, key.y]
	var detail := _mesh_from(res.get("detail"))
	var low := _mesh_from(res.get("low"))
	var ground := _mesh_from(res.get("ground"))
	var marks := _mesh_from(res.get("marks"))
	if marks:
		var mk := MeshInstance3D.new()
		mk.name = "Marks"
		mk.mesh = marks
		mk.material_override = ground_mat
		mk.visibility_range_end = MARKS_RANGE
		mk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mk)
	if detail:
		var mi := MeshInstance3D.new()
		mi.name = "Detail"
		mi.mesh = detail
		mi.material_override = building_mat
		mi.visibility_range_end = detail_range
		mi.visibility_range_end_margin = 30.0
		root.add_child(mi)
	if low:
		var lo := MeshInstance3D.new()
		lo.name = "Low"
		lo.mesh = low
		lo.material_override = building_mat
		lo.visibility_range_begin = detail_range
		lo.visibility_range_begin_margin = 30.0
		lo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(lo)
	if ground:
		var gi := MeshInstance3D.new()
		gi.name = "Ground"
		gi.mesh = ground
		gi.material_override = ground_mat
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(gi)
	_add_props(root, key)
	_add_traffic(root, key)
	_add_walkers(root, key)
	_add_occluder(root, key)
	add_child(root)
	_loaded[key] = root
	chunks_built += 1


func _add_props(root: Node3D, key: Vector2i) -> void:
	var by_kind := {}
	var i := 0
	for p in _props_by_chunk.get(key, []):
		i += 1
		if prop_density < 1.0 and p[0] in ["streetlight", "tree", "ac_unit", "traffic_light"] \
				and fmod(i * 0.618, 1.0) > prop_density:
			continue
		if not by_kind.has(p[0]):
			by_kind[p[0]] = []
		by_kind[p[0]].append(p[1])
	for kind in by_kind:
		var mesh: Mesh = prop_meshes.get(kind)
		if mesh == null:
			continue
		var list: Array = by_kind[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Props_" + kind
		mmi.multimesh = mm
		mmi.visibility_range_end = PROP_RANGES.get(kind, 300.0)
		mmi.visibility_range_end_margin = 20.0
		if kind in ["ac_unit", "streetlight", "traffic_light"]:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)


func _add_traffic(root: Node3D, key: Vector2i) -> void:
	if car_mesh == null or traffic_density <= 0.0:
		return
	var rect := Rect2(Vector2(key) * CHUNK, Vector2(CHUNK, CHUNK))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var xf: Array = []
	var custom: Array = []
	for lane in layout.lanes:
		var a: Vector3 = lane[0]
		var b: Vector3 = lane[1]
		var seg := _clip_segment(a, b, rect)
		if seg.is_empty():
			continue
		var s0: Vector3 = seg[0]
		var s1: Vector3 = seg[1]
		var length := s0.distance_to(s1)
		if length < 20.0:
			continue
		var dir := (s1 - s0) / length
		var basis := Basis.looking_at(dir, Vector3.UP)
		var n := int(length / 55.0 * traffic_density)
		for c in n:
			xf.append(Transform3D(basis, s0 + Vector3.UP * 0.02))
			custom.append(Color(rng.randf_range(9.0, 15.0), rng.randf_range(0.0, length), length, 0.0))
	_parked_cars(rect, rng, xf, custom)
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = car_mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_custom_data(i, custom[i])
		mm.set_instance_color(i, CAR_COLORS[rng.randi() % CAR_COLORS.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Traffic"
	mmi.multimesh = mm
	mmi.visibility_range_end = 520.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Cars travel up to a full segment along -Z; widen the culling box to match.
	mmi.extra_cull_margin = CHUNK
	root.add_child(mmi)


## Two walking lines along every pavement (one each way), between the kerb
## and the building line; round park edges too. Not on dock quays.
func _pavement_paths() -> Array:
	var out: Array = []
	for blk in layout.blocks:
		var r: Rect2 = blk
		var basin := false
		for w in layout.water:
			if (w as Rect2).position.x > 0.0 and (w as Rect2).encloses(r.grow(-7.0)):
				basin = true
		if basin:
			continue
		for inset_dir in [[1.7, 1.0], [3.0, -1.0]]:
			var i: float = inset_dir[0]
			var fwd: bool = inset_dir[1] > 0.0
			var c := [Vector3(r.position.x + i, 0.15, r.position.y + i), Vector3(r.end.x - i, 0.15, r.position.y + i),
				Vector3(r.end.x - i, 0.15, r.end.y - i), Vector3(r.position.x + i, 0.15, r.end.y - i)]
			for k in 4:
				var a: Vector3 = c[k]
				var b: Vector3 = c[(k + 1) % 4]
				out.append([a, b] if fwd else [b, a])
	return out


func _add_walkers(root: Node3D, key: Vector2i) -> void:
	if walker_mesh == null or traffic_density <= 0.0:
		return
	var rect := Rect2(Vector2(key) * CHUNK, Vector2(CHUNK, CHUNK))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0x5eed
	var xf: Array = []
	var custom: Array = []
	for path in _walk_paths:
		var seg := _clip_segment(path[0], path[1], rect)
		if seg.is_empty():
			continue
		var s0: Vector3 = seg[0]
		var s1: Vector3 = seg[1]
		var length := s0.distance_to(s1)
		if length < 6.0:
			continue
		var dir := (s1 - s0) / length
		var basis := Basis.looking_at(dir, Vector3.UP)
		var n := int(length / 9.0 * traffic_density + rng.randf())
		for i in n:
			var sc := rng.randf_range(0.9, 1.08)
			xf.append(Transform3D(basis.scaled(Vector3.ONE * sc), Vector3(s0.x, 0.15, s0.z)))
			custom.append(Color(rng.randf_range(1.1, 1.6), rng.randf_range(0.0, length), length, 0.0))
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = walker_mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_custom_data(i, custom[i])
		mm.set_instance_color(i, CLOTHES[rng.randi() % CLOTHES.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Walkers"
	mmi.multimesh = mm
	mmi.visibility_range_end = WALKER_RANGE
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = CHUNK
	root.add_child(mmi)


## Cars parked along both kerbs of the ordinary streets (not the avenues,
## not near junctions), with gaps. Same MultiMesh as traffic: speed 0 and a
## phase in the middle of a short "segment", the transform offset to match.
func _parked_cars(rect: Rect2, rng: RandomNumberGenerator, xf: Array, custom: Array) -> void:
	for axis in 2:
		var mains: Array = layout.x_streets if axis == 0 else layout.z_streets
		var cross: Array = layout.z_streets if axis == 0 else layout.x_streets
		for st in mains:
			if st[1] > 20.0:
				continue
			for k in cross.size() - 1:
				var a: float = cross[k][0] + cross[k][1] * 0.5 + 12.0
				var b: float = cross[k + 1][0] - cross[k + 1][1] * 0.5 - 12.0
				for side in [-1.0, 1.0]:
					var lateral: float = st[0] + side * (st[1] * 0.5 - 1.5)
					var d := a
					while d < b:
						var pos := Vector3(lateral, 0.02, d) if axis == 0 else Vector3(d, 0.02, lateral)
						if rect.has_point(Vector2(pos.x, pos.z)) and rng.randf() < 0.6:
							# Parked facing with the traffic on that side.
							var fwd := (Vector3.BACK if side > 0.0 else Vector3.FORWARD) if axis == 0 \
								else (Vector3.LEFT if side > 0.0 else Vector3.RIGHT)
							var basis := Basis.looking_at(fwd, Vector3.UP)
							# Phase 5 m into a 10 m "segment": full size, shifted 5 m along -Z.
							xf.append(Transform3D(basis, pos + basis.z * 5.0))
							custom.append(Color(0.0, 5.0, 10.0, 0.0))
						d += rng.randf_range(6.2, 7.5)


static func _clip_segment(a: Vector3, b: Vector3, r: Rect2) -> Array:
	# Axis-aligned lanes only: clip the varying coordinate to the rect.
	if absf(a.x - b.x) < 0.01:
		if a.x < r.position.x or a.x > r.end.x:
			return []
		var z0 := clampf(a.z, r.position.y, r.end.y)
		var z1 := clampf(b.z, r.position.y, r.end.y)
		return [] if absf(z1 - z0) < 1.0 else [Vector3(a.x, 0, z0), Vector3(a.x, 0, z1)]
	if a.z < r.position.y or a.z > r.end.y:
		return []
	var x0 := clampf(a.x, r.position.x, r.end.x)
	var x1 := clampf(b.x, r.position.x, r.end.x)
	return [] if absf(x1 - x0) < 1.0 else [Vector3(x0, 0, a.z), Vector3(x1, 0, a.z)]


func _add_occluder(root: Node3D, key: Vector2i) -> void:
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for b in _by_chunk.get(key, []):
		if b["kind"] not in ["normal", "landmark"]:
			continue
		var t: Array = b["tiers"][0]
		if t[5] - t[4] < 20.0 or t[2] - t[0] < 12.0 or t[3] - t[1] < 12.0:
			continue
		# Slightly shrunken so occluders never poke out of their building.
		var x0: float = t[0] + 0.5
		var z0: float = t[1] + 0.5
		var x1: float = t[2] - 0.5
		var z1: float = t[3] - 0.5
		var y1: float = t[5] - 0.5
		var base := v.size()
		v.append_array([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1),
			Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1)])
		for f in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]]:
			idx.append_array([base + f[0], base + f[1], base + f[2], base + f[0], base + f[2], base + f[3]])
	if v.is_empty():
		return
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(v, idx)
	var oi := OccluderInstance3D.new()
	oi.occluder = occ
	root.add_child(oi)


func loaded_chunk_count() -> int:
	return _loaded.size()
