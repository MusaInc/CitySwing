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
## Street furniture, lamp posts, trunks, roof units and parked cars: solid to
## the body (and ragdoll), but not web targets and not in the way of webs.
const PROPS_LAYER := 1 << 4
const MODEL_DIR := "res://assets/models/"
const PROP_RANGES := {
	"streetlight": 260.0, "tree": 320.0, "water_tower": 520.0, "ac_unit": 240.0, "antenna": 700.0, "crane": 1200.0,
	"traffic_light": 220.0, "roof_hut": 650.0, "tree_tall": 320.0,
}
## Street furniture (tools/blender/build_street.py), merged into one mesh per
## chunk: [kind, inset from the kerb line (m)].
const FURNITURE := ["bench", "bin", "hydrant", "bollard", "sign_post", "bus_shelter", "planter"]
const FURNITURE_RANGE := 190.0
## Traffic models (tools/blender/build_cars.py) and how common each is.
const CAR_KINDS := [["car_sedan", 0.32], ["car_hatch", 0.25], ["car_suv", 0.2], ["car_taxi", 0.13], ["car_van", 0.1]]
const TAXI_YELLOW := Color(0.98, 0.76, 0.12)
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
var car_meshes: Array[Mesh] = []  # CAR_KINDS order; null where the model is missing
var car_far_meshes: Array[Mesh] = []  # two-box stand-ins (24 tris) for chunks past CAR_NEAR
## Full car models only in chunks this close (centre distance); 1 650 tris each
## is wasted on a car a few pixels long.
const CAR_NEAR := 260.0
const CAR_FAR := 520.0
var walker_mesh: Mesh
var furniture_mat: StandardMaterial3D
var _furn_src := {}             # kind -> [verts, normals, colors, indices] (material colours baked in)
var _furniture_by_chunk := {}   # Vector2i -> Array of [kind, Transform3D]
var _walk_paths: Array = []  # [from, to] pavement segments (directional)
const WALKER_RANGE := 130.0
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
	for key in _by_chunk:
		if not key in _all_keys:
			_all_keys.append(key)  # e.g. the far bridge anchorage across the river
	_build_collision()
	_build_prop_collision()
	_build_water()
	_build_landmarks()
	_build_structures()
	_build_outskirts()
	_bake_street_maps()
	_build_birds()
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
		if h < 50.0 or h > 150.0 or t[2] - t[0] < 18.0 or t[3] - t[1] < 18.0:
			continue
		var spot := _clear_spot(t, roof_props)
		if spot.is_empty():
			continue
		var p := Vector3(spot["x"], BuildingMesher.roof_y(b) + 0.95, spot["z"])
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
			# Best-scoring heading where holding SWING from a standstill gives a
			# swing that clears every wall (a new player's first move).
			# Otherwise the best heading with a web in reach (Player's
			# first-swing grace covers the wall there).
			c["yaw"] = NAN
			var hs := _headings(c["position"], c["height"])
			for yaw in hs:
				if _first_swing_clear(c["position"], yaw):
					c["yaw"] = yaw
					break
			if is_nan(c["yaw"]):
				for yaw in hs:
					if _web_in_reach(c["position"], yaw):
						c["yaw"] = yaw
						break
		if is_nan(c["yaw"]):
			continue  # nowhere promising to swing from this roof
		if avoid == Vector3.INF or c["position"].distance_to(avoid) > 150.0:
			return c
		fallback = c
	return fallback if not fallback.is_empty() else {"position": spawn_point(), "yaw": 0.0, "height": 0.0}


var _spawn_params: SwingParams


## True if holding SWING on this roof, facing `yaw`, fires a web: at once,
## or during the launch hop (see _armed_launch).
func _web_in_reach(p: Vector3, yaw: float) -> bool:
	return not is_inside_tree() or not _armed_launch(p, yaw).is_empty()


## The press from the roof launches (Player._launch_state); with nothing in
## reach yet it stays armed through the hop and fires once an anchor comes
## into view. Returns [body state, targeting, seconds waited] at that moment,
## or [] if the hop comes back down first.
func _armed_launch(p: Vector3, yaw: float) -> Array:
	if _spawn_params == null:
		_spawn_params = load("res://config/swing_params.tres")
	var space := get_world_3d().direct_space_state
	var t := GrappleTargeting.new()
	var st := SwingPhysics.State.new()
	st.position = p
	st.velocity = Vector3.FORWARD.rotated(Vector3.UP, yaw) * 6.0 + Vector3.UP * _spawn_params.jump_speed
	t.update(space, p + Vector3.UP * 0.5, spawn_aim(yaw), Vector3.ZERO, _spawn_params, true, [])
	var c := SwingPhysics.Controls.new()
	var waited := 0.0
	while not t.has_target:
		SwingPhysics.step(st, c, _spawn_params, 1.0 / 30.0)
		waited += 1.0 / 30.0
		if waited > 1.2 or st.position.y < p.y - 1.0:
			return []
		t.update(space, st.position + Vector3.UP * 0.5, spawn_aim(yaw), st.velocity, _spawn_params, false, [])
	return [st, t, waited]


## Where a fresh spawn's view points: along `yaw`, tilted down by the
## camera's resting pitch (SwingCamera.base_pitch).
static func spawn_aim(yaw: float) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.RIGHT, deg_to_rad(-12.0)).rotated(Vector3.UP, yaw)


## True if holding SWING on this roof, facing `yaw` – and keeping it held, as
## a new player does – swings without a wall knockout or a drop to the street.
## Near-equal anchors flip with tiny differences (hand vs body position), so
## every anchor the game might pick then must be safe.
func _first_swing_clear(p: Vector3, yaw: float) -> bool:
	if not is_inside_tree():
		return true
	if _spawn_params == null:
		_spawn_params = load("res://config/swing_params.tres")
	var launch := _armed_launch(p, yaw)
	if launch.is_empty():
		return false
	var space := get_world_3d().direct_space_state
	var st: SwingPhysics.State = launch[0]
	var t: GrappleTargeting = launch[1]
	var waited: float = launch[2]
	var picks: Array[Vector3] = [t.best_flyable(space, st, _spawn_params, [])]
	for cand in t.candidates():
		if picks.size() >= 4:
			break
		if picks.all(func(q: Vector3): return q.distance_to(cand[1]) > 4.0):
			picks.append(cand[1])
	for anchor in picks:
		if not _held_swing_safe(space, st, anchor, waited):
			return false
	return true


## Flies a held web from `from` (the body in the air when the web fires) for
## ~5 s: line flight, zip-up, auto-tighten, rope wrapping, wall slides.
func _held_swing_safe(space: PhysicsDirectSpaceState3D, from: SwingPhysics.State, anchor: Vector3, t0: float) -> bool:
	var st := SwingPhysics.State.new()
	st.position = from.position
	st.velocity = from.velocity
	var c := SwingPhysics.Controls.new()
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1 | GrappleTargeting.GRAPPLE_MASK | (1 << 3)
	var dt := 1.0 / 30.0
	# The web flies out while the body is in the air (Player._advance_line).
	var fly := (anchor - st.position).length() / _spawn_params.line_speed
	var attach_length := 0.0
	var zip := true
	for i in int((5.0 - t0) / dt):
		var a := st.position
		if not st.attached and i * dt >= fly:
			if not SwingPhysics.attach(st, anchor, _spawn_params):
				return false
			attach_length = st.rope_length
		if st.attached:
			# The ground launch winches in first (Player.auto_tighten's zip).
			zip = zip and st.rope_length > attach_length * _spawn_params.auto_tighten_min_fraction + 0.5
			c.reel = 2.0 if zip else SwingPhysics.auto_tighten(st, _spawn_params, attach_length)
		SwingPhysics.step(st, c, _spawn_params, dt)
		q.from = a
		q.to = st.position + (st.position - a).normalized() * 0.4
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			# The rope catching on a corner (Player wraps it there) shortens
			# the swing into the wall below: count it as unsafe.
			if st.attached and not Player._clear(space, st.position, anchor):
				return false
			continue
		var n: Vector3 = hit["normal"]
		var col = hit.get("collider")
		if col is CollisionObject3D and ((col as CollisionObject3D).collision_layer & (1 << 3)) != 0:
			return false  # the street
		if n.y > 0.6:
			if Vector2(st.velocity.x, st.velocity.z).length() < 8.0:
				return true  # set down on a roof
			# Skimming a roof edge at speed: carried on along it.
			st.position = (hit["position"] as Vector3) + n * 0.95
			st.velocity.y = maxf(st.velocity.y, 0.0)
			continue
		# A facade: knocked out if it's fast and head-on (margin for the real
		# body's width and timing); anything softer slides along it and the
		# swing carries on (Player.move_and_slide).
		var into := -st.velocity.dot(n)
		if into > _spawn_params.wall_run_max_speed * 0.92 and into > st.velocity.length() * _spawn_params.wall_glance_ratio:
			return false
		st.velocity += n * maxf(into, 0.0)
		st.position = (hit["position"] as Vector3) + n * 0.45
	return true


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


## Headings (camera-style yaw: looking along -Z rotated by yaw) with taller
## anchors ahead and nothing blocking the run-up, best first.
func _headings(p: Vector3, roof_h: float) -> Array:
	var ranked: Array = []
	for k in 16:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 16.0)
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
		if not blocked:  # weak headings rank last, but a safe one beats none
			ranked.append([score, atan2(-dir.x, -dir.z)])
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	return ranked.map(func(r): return r[1])


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
	for k in ["streetlight", "tree", "tree_tall", "water_tower", "ac_unit", "antenna", "crane", "viaduct", "clock_crown",
			"harbour_dome", "beacon", "cathedral_top", "traffic_light", "roof_hut"]:
		var m := _load_mesh(k)
		if m:
			prop_meshes[k] = m
	var shader: Shader = load("res://src/world/shaders/traffic.gdshader")
	for kind in CAR_KINDS:
		var car := _load_mesh(kind[0])
		var cm: Mesh = null
		if car:
			cm = car.duplicate()
			for i in cm.get_surface_count():
				var src := cm.surface_get_material(i)
				var sm := ShaderMaterial.new()
				sm.shader = shader
				var name := String(src.resource_name) if src else ""
				if src is BaseMaterial3D:
					sm.set_shader_parameter("tint", (src as BaseMaterial3D).albedo_color)
				sm.set_shader_parameter("use_instance_color", name == "paint")
				sm.set_shader_parameter("emission", 2.0 if name.begins_with("lamp") else 0.0)
				sm.set_shader_parameter("roughness", 0.25 if name == "car_glass" else 0.45)
				cm.surface_set_material(i, sm)
		car_meshes.append(cm)
		car_far_meshes.append(_car_far_mesh(cm) if cm else null)
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
			var nm := String(src.resource_name) if src else ""
			sm.set_shader_parameter("use_instance_color", nm == "shirt")
			sm.set_shader_parameter("part", {"skin": 1, "pants": 2, "hair": 3}.get(nm, 0))
			walker_mesh.surface_set_material(i, sm)
	_walk_paths = _pavement_paths()
	for k in FURNITURE:
		var fm := _load_mesh(k)
		if fm:
			_furn_src[k] = _flatten_colors(fm)
	furniture_mat = StandardMaterial3D.new()
	furniture_mat.vertex_color_use_as_albedo = true
	furniture_mat.vertex_color_is_srgb = true
	furniture_mat.roughness = 0.75
	_furniture_by_chunk = _place_furniture()


## Body + cabin boxes sized from the full model, sharing its paint and glass
## materials (so the GPU drive, instance colour and taxi yellow still apply).
static func _car_far_mesh(full: Mesh) -> Mesh:
	var paint: Material
	var glass: Material
	for i in full.get_surface_count():
		var m := full.surface_get_material(i) as ShaderMaterial
		if m == null:
			continue
		if m.get_shader_parameter("use_instance_color"):
			paint = m
		elif is_equal_approx(float(m.get_shader_parameter("roughness")), 0.25):
			glass = m
	var bb := full.get_aabb()
	var h := bb.size.y
	var c := bb.get_center()
	var out := ArrayMesh.new()
	for part in [[Vector3(bb.size.x * 0.96, h * 0.42, bb.size.z * 0.98), Vector3(c.x, bb.position.y + h * 0.34, c.z), paint],
			[Vector3(bb.size.x * 0.84, h * 0.4, bb.size.z * 0.5), Vector3(c.x, bb.position.y + h * 0.74, c.z + bb.size.z * 0.04), glass]]:
		var box := BoxMesh.new()
		box.size = part[0]
		var arr := box.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for j in v.size():
			v[j] += part[1]
		arr[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, part[2])
	return out


## One mesh's surfaces flattened into a single vertex-coloured array set.
static func _flatten_colors(m: Mesh) -> Array:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for i in m.get_surface_count():
		var a := m.surface_get_arrays(i)
		var mat := m.surface_get_material(i) as BaseMaterial3D
		var c := mat.albedo_color if mat else Color.WHITE
		var base := v.size()
		v.append_array(a[Mesh.ARRAY_VERTEX])
		nrm.append_array(a[Mesh.ARRAY_NORMAL])
		for j in (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			col.append(c)
		for j in a[Mesh.ARRAY_INDEX]:
			idx.append(base + j)
	return [v, nrm, col, idx]


## Street furniture along every built-up block (not parks or dock basins):
## kerbside bins, bollards, hydrants and corner street signs; benches,
## planters and – on avenues – bus shelters back by the building line.
## Placement walks each block edge with its own RNG (the layout's random
## streams are untouched), keeps clear of junction corners, streetlights and
## the two pedestrian walking lines (1.7 m / 3.0 m in from the kerb).
func _place_furniture() -> Dictionary:
	var out := {}
	for blk in layout.blocks:
		var r: Rect2 = blk
		if r in layout.parks:
			continue
		var basin := false
		for w in layout.water:
			if (w as Rect2).position.x > 0.0 and (w as Rect2).encloses(r.grow(-7.0)):
				basin = true
		if basin:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(int(r.position.x), int(r.position.y))) ^ 0xf00d
		# Edges: start corner, direction along, outward normal (towards the road), length.
		var edges := [
			[Vector2(r.position.x, r.position.y), Vector2.RIGHT, Vector2.UP, r.size.x],
			[Vector2(r.end.x, r.position.y), Vector2.DOWN, Vector2.RIGHT, r.size.y],
			[Vector2(r.end.x, r.end.y), Vector2.LEFT, Vector2.DOWN, r.size.x],
			[Vector2(r.position.x, r.end.y), Vector2.UP, Vector2.LEFT, r.size.y],
		]
		for ei in edges.size():
			var e: Array = edges[ei]
			var o: Vector2 = e[0]
			var along: Vector2 = e[1]
			var nrm: Vector2 = e[2]
			var length: float = e[3]
			var inward := -nrm
			var basis := Basis.looking_at(Vector3(nrm.x, 0, nrm.y), Vector3.UP)  # front faces the road
			var avenue := _street_width_beside(r, nrm) > 20.0
			var put := func(kind: String, d: float, inset: float, yaw := 0.0):
				var p2 := o + along * d + inward * inset
				var key := Vector2i(floori(p2.x / CHUNK), floori(p2.y / CHUNK))
				if not out.has(key):
					out[key] = []
				out[key].append([kind, Transform3D(basis * Basis(Vector3.UP, yaw), Vector3(p2.x, 0.15, p2.y))])
			# Corner street sign at the start of every other edge.
			if ei % 2 == 0:
				put.call("sign_post", 2.2, 0.5, PI * 0.25)
			# Kerbside line.
			var d := 7.0 + rng.randf_range(0.0, 6.0)
			while d < length - 7.0:
				var lamp_d := fmod(absf((o + along * d).x - r.position.x) - 8.0 + 320.0, 32.0)
				if ei % 2 == 1 or (lamp_d > 1.5 and lamp_d < 30.5):
					var roll := rng.randf()
					if roll < 0.32:
						put.call("bin", d, 0.55)
					elif roll < 0.44:
						put.call("hydrant", d, 0.5, PI * 0.5)
					elif roll < 0.58:
						put.call("bollard", d, 0.45)
						put.call("bollard", d + 1.4, 0.45)
				d += rng.randf_range(11.0, 22.0)
			# Building line: one bus shelter per avenue edge, benches/planters.
			var shelter_at := length * rng.randf_range(0.35, 0.65) if avenue and length > 40.0 and rng.randf() < 0.7 else -100.0
			if shelter_at > 0.0:
				put.call("bus_shelter", shelter_at, 3.95)
			d = 12.0 + rng.randf_range(0.0, 10.0)
			while d < length - 10.0:
				if absf(d - shelter_at) > 5.0:
					var roll := rng.randf()
					if roll < 0.4:
						put.call("bench", d, 4.1)
					elif roll < 0.6:
						put.call("planter", d, 4.0)
				d += rng.randf_range(16.0, 34.0)
	return out


## Width of the street on the `nrm` side of block `r` (0 if none found).
func _street_width_beside(r: Rect2, nrm: Vector2) -> float:
	var list: Array = layout.x_streets if nrm.x != 0.0 else layout.z_streets
	var edge := (r.end.x if nrm.x > 0.0 else r.position.x) if nrm.x != 0.0 else (r.end.y if nrm.y > 0.0 else r.position.y)
	for st in list:
		if absf(st[0] - (edge + (nrm.x + nrm.y) * st[1] * 0.5)) < 1.0:
			return st[1]
	return 0.0


## Merged furniture arrays for one chunk (worker-thread safe: reads only).
func _furniture_arrays(key: Vector2i):
	var items: Array = chunk_furniture(key)
	if items.is_empty() or _furn_src.is_empty():
		return null
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for it in items:
		var src: Array = _furn_src.get(it[0], [])
		if src.is_empty():
			continue
		var xf: Transform3D = it[1]
		var base := v.size()
		for p in src[0]:
			v.append(xf * p)
		for q in src[1]:
			nrm.append(xf.basis * q)
		col.append_array(src[2])
		for i in src[3]:
			idx.append(base + i)
	if v.is_empty():
		return null
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = nrm
	a[Mesh.ARRAY_COLOR] = col
	a[Mesh.ARRAY_INDEX] = idx
	return a


# ------------------------------------------------------------- collision
## Collision mirrors the drawn city exactly (BuildingMesher.collision_boxes):
## roofs at the height they're drawn, cornices, parapets, plinths and awnings
## solid, the street at 0 and the raised pavements at their kerb height.
func _build_collision() -> void:
	var by_chunk := _by_chunk
	for key in by_chunk:
		var body := StaticBody3D.new()
		body.name = "Col_%d_%d" % [key.x, key.y]
		body.collision_layer = 1 | (1 << 1)
		body.collision_mask = 0
		for b in by_chunk[key]:
			for box in BuildingMesher.collision_boxes(b):
				_add_box(body, box)
		add_child(body)
	var street := StaticBody3D.new()
	street.name = "Street"
	street.collision_layer = 1 << 3
	street.collision_mask = 0
	street.add_to_group("street")
	for r in ground_rects():
		_add_box(street, AABB(Vector3(r.position.x, -2.0, r.position.y), Vector3(r.size.x, 2.0, r.size.y)))
	for r in pavement_rects():
		_add_box(street, AABB(Vector3(r.position.x, 0.0, r.position.y), Vector3(r.size.x, BuildingMesher.KERB, r.size.y)))
	# River wall along the promenade (the parapet drawn by add_ground).
	_add_box(street, AABB(Vector3(CityLayout.RIVER_EDGE, -4.0, CityLayout.MIN_Z - 200.0),
		Vector3(0.6, 5.1, CityLayout.MAX_Z - CityLayout.MIN_Z + 400.0)))
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
	# Set pieces: oriented beams and convex prisms (their boxes are buildings).
	var kit := StaticBody3D.new()
	kit.name = "SetPieceCol"
	kit.collision_layer = 1 | (1 << 1)
	kit.collision_mask = 0
	for ob in layout.kit_obbs:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = ob[1]
		cs.shape = bs
		cs.transform = ob[0]
		kit.add_child(cs)
	for hull in layout.kit_hulls:
		var cs2 := CollisionShape3D.new()
		var cv := ConvexPolygonShape3D.new()
		cv.points = hull
		cs2.shape = cv
		kit.add_child(cs2)
	add_child(kit)


## Solid shapes for every drawn prop, in the prop's own frame:
## [size, centre] boxes (poles, trunks, units, furniture, cars).
func _prop_boxes(kind: String) -> Array:
	match kind:
		"streetlight":
			return [[Vector3(0.24, 7.0, 0.24), Vector3(0, 3.5, 0)]]
		"traffic_light":
			return [[Vector3(0.3, 6.2, 0.3), Vector3(0, 2.8, 0)]]
		"sign_post":
			return [[Vector3(0.14, 2.9, 0.14), Vector3(0, 1.45, 0)]]
		"tree", "tree_tall":
			return [[Vector3(0.36, 2.6, 0.36), Vector3(0, 1.3, 0)]]
		"antenna":
			return [[Vector3(0.3, 14.3, 0.3), Vector3(0, 7.15, 0)]]
		"roof_hut", "crane":
			return []  # the layout's own boxes
	var m: Mesh = prop_meshes.get(kind)
	if m == null:
		var src: Array = _furn_src.get(kind, [])
		if src.is_empty():
			return []
		var bb := AABB((src[0] as PackedVector3Array)[0], Vector3.ZERO)
		for v in src[0]:
			bb = bb.expand(v)
		return [[bb.size, bb.get_center()]]
	var a := m.get_aabb()
	return [[a.size, a.get_center()]]


func _build_prop_collision() -> void:
	var car_boxes: Array = []
	for k in CAR_KINDS:
		var cm := _load_mesh(k[0])
		var a := cm.get_aabb() if cm else AABB(Vector3(-1, 0, -2.3), Vector3(2, 1.45, 4.6))
		car_boxes.append([a.size, a.get_center()])
	var cache := {}
	var keys := {}
	for k in _props_by_chunk:
		keys[k] = true
	for k in _furniture_by_chunk:
		keys[k] = true
	for k in _all_keys:
		keys[k] = true
	for key in keys:
		var body := StaticBody3D.new()
		body.name = "Props_%d_%d" % [key.x, key.y]
		body.collision_layer = PROPS_LAYER
		body.collision_mask = 0
		var items: Array = chunk_props(key) + chunk_furniture(key)
		for it in items:
			var kind: String = it[0]
			if not cache.has(kind):
				cache[kind] = _prop_boxes(kind)
			for bx in cache[kind]:
				_add_oriented_box(body, it[1], bx[0], bx[1])
		for pc in parked_cars(key):
			var bx: Array = car_boxes[int(pc[1])]
			_add_oriented_box(body, pc[0], bx[0], bx[1])
		if body.get_child_count() > 0:
			add_child(body)
		else:
			body.free()


## A box of `size` at `centre` in the frame `xf` (uniform scale baked into the size).
static func _add_oriented_box(body: StaticBody3D, xf: Transform3D, size: Vector3, centre: Vector3) -> void:
	var sc := xf.basis.get_scale()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size * sc
	shape.shape = bs
	shape.transform = Transform3D(xf.basis.orthonormalized(), xf * centre)
	body.add_child(shape)


static func _add_box(body: StaticBody3D, box: AABB) -> void:
	if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
		return
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	shape.shape = bs
	shape.position = box.get_center()
	body.add_child(shape)


## Every piece of street-level ground that is drawn (the playable city, the
## outskirts round it and the far shore), minus the dock basins.
func ground_rects() -> Array:
	var rects: Array = [Rect2(CityLayout.RIVER_EDGE, CityLayout.MIN_Z - 1000.0,
		CityLayout.MAX_X + 1000.0 - CityLayout.RIVER_EDGE, CityLayout.MAX_Z - CityLayout.MIN_Z + 2000.0)]
	for w in layout.water:
		if (w as Rect2).position.x < 0.0:
			continue
		var next: Array = []
		for r in rects:
			next.append_array(CityLayout._subtract(r, w))
		rects = next
	rects.append(Rect2(-2600.0, -2600.0, CityLayout.FAR_SHORE + 2600.0, 5200.0))
	return rects


## Raised pavement blocks (kerb height) as drawn by BuildingMesher.add_ground:
## whole blocks, or just the quay ring round a dock basin.
func pavement_rects() -> Array:
	var out: Array = []
	for blk in layout.blocks:
		var basin := false
		for w in layout.water:
			if (w as Rect2).encloses((blk as Rect2).grow(-7.0)) and (w as Rect2).position.x > 0.0:
				basin = true
		if basin:
			out.append_array(CityLayout._subtract(blk, (blk as Rect2).grow(-6.0)))
		else:
			out.append(blk)
	return out


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
		# Landmarks collide with their exact surface (domes, crowns, the
		# viaduct's arches), not a box round them.
		var body := StaticBody3D.new()
		body.name = "LandmarkCol_" + k
		body.collision_layer = 1 | (1 << 1)
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(mesh.get_faces())
		for xf in groups[k]:
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.transform = xf
			body.add_child(cs)
		add_child(body)


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


## Pigeon flocks circling over parks, plazas and a few rooftops – a little
## life in the sky. A tiny procedural bird; flight is all in the shader.
func _build_birds() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Body (thin diamond) and two wings, facing -Z, ~0.6 m span.
	for tri in [[Vector3(0, 0, -0.16), Vector3(0.05, 0, 0.0), Vector3(0, 0, 0.18)],
			[Vector3(0, 0, -0.16), Vector3(0, 0, 0.18), Vector3(-0.05, 0, 0.0)],
			[Vector3(0.04, 0, -0.06), Vector3(0.32, 0.02, 0.02), Vector3(0.04, 0, 0.07)],
			[Vector3(-0.04, 0, -0.06), Vector3(-0.04, 0, 0.07), Vector3(-0.32, 0.02, 0.02)]]:
		for v in tri:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/world/shaders/birds.gdshader")
	mesh.surface_set_material(0, mat)
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.seed * 7
	var homes: Array = []
	for p in layout.parks:
		homes.append(Vector3((p as Rect2).get_center().x, rng.randf_range(18.0, 34.0), (p as Rect2).get_center().y))
	for i in 10:
		var b: Dictionary = layout.buildings[rng.randi() % layout.buildings.size()]
		if b["kind"] == "normal":
			var t: Array = b["tiers"][-1]
			homes.append(Vector3((t[0] + t[2]) * 0.5, t[5] + rng.randf_range(10.0, 22.0), (t[1] + t[3]) * 0.5))
	for h in homes:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		var n := rng.randi_range(6, 12)
		mm.instance_count = n
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		var base_r := rng.randf_range(10.0, 22.0)
		for i in n:
			var c := (h as Vector3) + Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.5, 2.5), rng.randf_range(-2.0, 2.0))
			mm.set_instance_transform(i, Transform3D(Basis(), c))
			mm.set_instance_custom_data(i, Color(base_r + rng.randf_range(-3.0, 3.0), dir * rng.randf_range(0.45, 0.6),
				i * 0.35 + rng.randf_range(0.0, 0.2), rng.randf_range(0.5, 1.6)))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Birds"
		mmi.multimesh = mm
		mmi.extra_cull_margin = 30.0
		mmi.visibility_range_end = 320.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


## Low-detail skyline beyond the playable grid (and a far river shore) so every
## horizon reads as city. One mesh, low LOD only; outskirt blocks still collide.
func _build_outskirts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.seed * 31
	var m := BuildingMesher.new()
	var col_body := StaticBody3D.new()
	col_body.name = "OutskirtsCol"
	col_body.collision_layer = 1 | (1 << 1)
	col_body.collision_mask = 0
	var pave_body := StaticBody3D.new()  # outer pavements: street, not a web target
	pave_body.name = "OutskirtsPavements"
	pave_body.collision_layer = 1 << 3
	pave_body.collision_mask = 0
	pave_body.add_to_group("street")
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
	_outer_ranges = [xr_in + xr_out, zr_in + zr_out]
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
			_add_box(pave_body, AABB(Vector3(blk.position.x, 0.0, blk.position.y),
				Vector3(blk.size.x, BuildingMesher.KERB, blk.size.y)))
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
				# Everything drawn out here is solid too: the outskirts are part
				# of the city you can swing into, not a painted backdrop.
				if near:
					near_m.add_building(bd, true)
					for box in BuildingMesher.collision_boxes(bd):
						_add_box(col_body, box)
				else:
					m.add_building(bd, false)
					_add_box(col_body, AABB(Vector3(r.position.x, 0.0, r.position.y), Vector3(r.size.x, h, r.size.y)))
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
				for box in BuildingMesher.collision_boxes(b2):
					_add_box(col_body, box)
			else:
				_add_box(col_body, AABB(Vector3(bx, 0.0, z2), Vector3(w2, h2, d2)))
			bx -= w2 + rng.randf_range(14.0, 24.0)
		z2 += d2 + rng.randf_range(14.0, 24.0)
	m.top(-2600.0, -2600.0, CityLayout.FAR_SHORE, 2600.0, 0.0, Color(0.33, 0.33, 0.34), BuildingMesher.KIND_ROOF, 0, 0)
	_add_box(pave_body, AABB(Vector3(CityLayout.FAR_SHORE - 0.6, -4.0, -2600.0), Vector3(0.6, 5.1, 5200.0)))
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
	add_child(pave_body)


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


## Street layout for ground.gdshader: per axis, a 1-texel-per-metre strip
## holding (offset from the nearest street centre line at the texel centre,
## half width, avenue flag). The shader adds its sub-texel offset back, so
## lane lines, crossings, kerbs and paving are exact without any geometry.
var _outer_ranges: Array = [[], []]
const STREET_MAP_X := Vector2(-640.0, 2600.0)  # origin, texels (1 m each)
const STREET_MAP_Z := Vector2(-1500.0, 3000.0)


func _bake_street_maps() -> void:
	for axis in 2:
		var streets: Array = (layout.x_streets if axis == 0 else layout.z_streets).duplicate()
		var ranges: Array = _outer_ranges[axis].duplicate()
		ranges.sort_custom(func(a, b): return a[0] < b[0])
		for i in ranges.size() - 1:
			var gap: float = ranges[i + 1][0] - ranges[i][1]
			var c: float = (ranges[i][1] + ranges[i + 1][0]) * 0.5
			if gap > 4.0 and gap < 40.0 and streets.all(func(st): return absf(st[0] - c) > 4.0):
				streets.append([c, gap])
		streets.sort_custom(func(a, b): return a[0] < b[0])
		var m: Vector2 = STREET_MAP_X if axis == 0 else STREET_MAP_Z
		var img := Image.create(int(m.y), 1, false, Image.FORMAT_RGBF)
		var j := 0
		for i in int(m.y):
			var p := m.x + i + 0.5
			while j < streets.size() - 1 and absf(streets[j + 1][0] - p) < absf(streets[j][0] - p):
				j += 1
			var st: Array = streets[j]
			img.set_pixel(i, 0, Color(p - st[0], st[1] * 0.5, 1.0 if st[1] > 20.0 else 0.0))
		ground_mat.set_shader_parameter("street_x" if axis == 0 else "street_z", ImageTexture.create_from_image(img))
	ground_mat.set_shader_parameter("street_map", Vector4(STREET_MAP_X.x, STREET_MAP_X.y, STREET_MAP_Z.x, STREET_MAP_Z.y))
	ground_mat.set_shader_parameter("has_streets", true)


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
	for b in _by_chunk.get(key, []):
		detail.add_building(b, true)
		low.add_building(b, false)
	ground.add_ground(layout, rect)
	var furn: Variant = _furniture_arrays(key)
	return {
		"detail": null if detail.is_empty() else detail.arrays(),
		"low": null if low.is_empty() else low.arrays(),
		"ground": null if ground.is_empty() else ground.arrays(),
		"furniture": furn,
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
	if detail:
		var mi := MeshInstance3D.new()
		mi.name = "Detail"
		mi.mesh = detail
		mi.material_override = building_mat
		mi.visibility_range_end = detail_range
		mi.visibility_range_end_margin = 30.0
		root.add_child(mi)
		if low:
			# Shadows come from the plain massing (walls + roofs, ~1/6 of the
			# triangles): ledges, parapets and awnings don't need to be drawn
			# twice more into the shadow splits.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var sh := MeshInstance3D.new()
			sh.name = "ShadowProxy"
			sh.mesh = low
			sh.material_override = building_mat
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			sh.visibility_range_end = detail_range
			sh.visibility_range_end_margin = 30.0
			root.add_child(sh)
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
	var furn := _mesh_from(res.get("furniture"))
	if furn:
		var fi := MeshInstance3D.new()
		fi.name = "Furniture"
		fi.mesh = furn
		fi.material_override = furniture_mat
		fi.visibility_range_end = FURNITURE_RANGE
		fi.visibility_range_end_margin = 20.0
		root.add_child(fi)
	_add_props(root, key)
	_add_traffic(root, key)
	_add_walkers(root, key)
	_add_occluder(root, key)
	add_child(root)
	_loaded[key] = root
	chunks_built += 1


## The props drawn in a chunk at the current density: [kind, Transform3D].
## Collision is built from the same list, so a prop you can't see never blocks you.
func chunk_props(key: Vector2i) -> Array:
	var out: Array = []
	var i := 0
	for p in _props_by_chunk.get(key, []):
		i += 1
		if prop_density < 1.0 and p[0] in ["streetlight", "tree", "ac_unit", "traffic_light"] \
				and fmod(i * 0.618, 1.0) > prop_density:
			continue
		var kind: String = p[0]
		var xf: Transform3D = p[1]
		if kind == "tree":
			# Mix in the columnar tree and turn each one differently (looks
			# only: the layout's tree positions don't change).
			var h := hash(Vector2i(int(xf.origin.x * 4.0), int(xf.origin.z * 4.0)))
			if h % 5 < 2 and prop_meshes.has("tree_tall"):
				kind = "tree_tall"
			xf.basis = xf.basis * Basis(Vector3.UP, (h % 628) * 0.01)
		out.append([kind, xf])
	return out


## Furniture drawn in a chunk at the current density: [kind, Transform3D].
func chunk_furniture(key: Vector2i) -> Array:
	var out: Array = []
	var n := 0
	for it in _furniture_by_chunk.get(key, []):
		n += 1
		if prop_density < 1.0 and fmod(n * 0.618, 1.0) > prop_density:
			continue
		out.append(it)
	return out


func _add_props(root: Node3D, key: Vector2i) -> void:
	var by_kind := {}
	for p in chunk_props(key):
		var kind: String = p[0]
		var xf: Transform3D = p[1]
		if not by_kind.has(kind):
			by_kind[kind] = []
		by_kind[kind].append(xf)
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
	if car_meshes.is_empty() or traffic_density <= 0.0:
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
	var moving := xf.size()
	var parked := parked_cars(key)
	for pc in parked:
		var m: Transform3D = pc[0]
		xf.append(Transform3D(m.basis, m.origin + m.basis.z * 5.0))  # the shader's 5 m phase
		custom.append(Color(0.0, 5.0, 10.0, 0.0))
	if xf.is_empty():
		return
	# Sort the cars into one MultiMesh per model (own RNG: the colour draws
	# below stay as they were).
	var kind_rng := RandomNumberGenerator.new()
	kind_rng.seed = hash(key) ^ 0xca75
	var groups: Array = []
	for k in CAR_KINDS.size():
		groups.append([])
	for i in xf.size():
		var k := _car_kind(kind_rng.randf()) if i < moving else int(parked[i - moving][1])
		if car_meshes[k] == null:
			k = 0
		var col: Color = CAR_COLORS[rng.randi() % CAR_COLORS.size()]
		groups[k].append([xf[i], custom[i], TAXI_YELLOW if CAR_KINDS[k][0] == "car_taxi" else col])
	# Cars only ever drive inside their chunk (lanes are clipped to it), so the
	# chunk itself is an exact culling box for the GPU-moved instances.
	var bounds := AABB(Vector3(rect.position.x, -1.0, rect.position.y), Vector3(CHUNK, 6.0, CHUNK))
	for k in groups.size():
		var g: Array = groups[k]
		if g.is_empty() or car_meshes[k] == null:
			continue
		# One packed buffer for both LODs (much cheaper than per-instance setters
		# on the main thread while chunks stream in).
		var buf := _instance_buffer(g)
		for far in [false, true]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = car_far_meshes[k] if far else car_meshes[k]
			mm.instance_count = g.size()
			mm.buffer = buf
			mm.custom_aabb = bounds
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Traffic_" + CAR_KINDS[k][0] + ("_far" if far else "")
			mmi.multimesh = mm
			if far:
				mmi.visibility_range_begin = CAR_NEAR
				mmi.visibility_range_end = CAR_FAR
			else:
				mmi.visibility_range_end = CAR_NEAR
			mmi.visibility_range_begin_margin = 20.0
			mmi.visibility_range_end_margin = 20.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)


## MultiMesh buffer (TRANSFORM_3D + colour + custom) for [xform, custom, colour] items.
static func _instance_buffer(items: Array) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(items.size() * 20)
	var j := 0
	for it in items:
		var x: Transform3D = it[0]
		var cu: Color = it[1]
		var co: Color = it[2]
		for r in 3:
			buf[j] = x.basis.x[r]
			buf[j + 1] = x.basis.y[r]
			buf[j + 2] = x.basis.z[r]
			buf[j + 3] = x.origin[r]
			j += 4
		buf[j] = co.r; buf[j + 1] = co.g; buf[j + 2] = co.b; buf[j + 3] = co.a
		buf[j + 4] = cu.r; buf[j + 5] = cu.g; buf[j + 6] = cu.b; buf[j + 7] = cu.a
		j += 8
	return buf


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
	var items: Array = []
	for i in xf.size():
		items.append([xf[i], custom[i], CLOTHES[rng.randi() % CLOTHES.size()]])
	mm.buffer = _instance_buffer(items)
	mm.custom_aabb = AABB(Vector3(rect.position.x, -1.0, rect.position.y), Vector3(CHUNK, 4.0, CHUNK))  # walks stay in the chunk
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Walkers"
	mmi.multimesh = mm
	mmi.visibility_range_end = WALKER_RANGE
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


## Cars parked along both kerbs of the ordinary streets (not the avenues,
## not near junctions), with gaps. Same MultiMesh as traffic: speed 0 and a
## phase in the middle of a short "segment", the transform offset to match.
static func _car_kind(r: float) -> int:
	var k := 0
	while k < CAR_KINDS.size() - 1 and r > CAR_KINDS[k][1]:
		r -= CAR_KINDS[k][1]
		k += 1
	return k


## Parked cars in a chunk: [Transform3D of the model, CAR_KINDS index]. Own
## random stream per chunk, independent of the traffic density, so the
## collision built up front matches what the chunk later draws.
func parked_cars(key: Vector2i) -> Array:
	var rect := Rect2(Vector2(key) * CHUNK, Vector2(CHUNK, CHUNK))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0x9a4c
	var xf: Array = []
	var custom: Array = []
	_parked_cars(rect, rng, xf, custom)
	var out: Array = []
	for t in xf:
		# The shader shifts a parked car 5 m back along its segment (see below).
		out.append([Transform3D((t as Transform3D).basis, (t as Transform3D).origin - (t as Transform3D).basis.z * 5.0),
			_car_kind(rng.randf())])
	return out


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
