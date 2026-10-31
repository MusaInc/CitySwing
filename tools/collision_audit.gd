extends SceneTree
## Compares what you SEE with what you STAND ON, over the whole visible map.
## Every drawn surface that matters for traversal (chunk buildings + ground,
## structures, landmarks, outskirts, water) is copied into trimesh bodies on
## a private layer; then a grid of downward rays is cast against those and
## against the game's collision, and every mismatch is classified:
##   hole   – something drawn, nothing (or something far lower) to stand on:
##            you fall through it
##   sink   – drawn surface 4–60 cm above the collision: feet sink into it
##   ghost  – collision ≥ 0.4 m above anything drawn: an invisible block
##   over   – a drawn overhang (awning, ledge, slab) with nothing solid in it
##   wall   – horizontal rays at body height: drawn wall in front of the
##            collision by ≥ 6 cm (limbs/body visibly inside it)
## Needs a renderer for mesh arrays:
##   xvfb-run -a -s "-screen 0 640x480x24" godot --rendering-method mobile \
##     --resolution 320x240 -s res://tools/collision_audit.gd -- [step_m] [region]
## region: all (default) | city (the playable grid only)

const VIS_LAYER := 1 << 15
const GAME_MASK := 1 | (1 << 1) | (1 << 3)

var world: CityWorld
var counts := {}
var samples := {}
var hist := {}


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var step := float(args[0]) if args.size() > 0 else 3.0
	var region := args[1] if args.size() > 1 else "all"
	world = CityWorld.new()
	root.add_child(world)
	world.build_all_near(Vector3(540, 0, -20), 5000.0)
	var t0 := Time.get_ticks_msec()
	var tris := _mirror_visuals(world)
	print("AUDIT mirrored %d triangles in %d ms" % [tris, Time.get_ticks_msec() - t0])
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	var x0 := CityLayout.FAR_SHORE - 300.0
	var x1 := CityLayout.MAX_X + 900.0
	var z0 := CityLayout.MIN_Z - 900.0
	var z1 := CityLayout.MAX_Z + 900.0
	if region == "city":
		x0 = CityLayout.RIVER_EDGE - 20.0
		x1 = CityLayout.MAX_X
		z0 = CityLayout.MIN_Z
		z1 = CityLayout.MAX_Z
	t0 = Time.get_ticks_msec()
	var n := 0
	var x := x0 + 0.37  # off the metre grid, so rays don't graze box edges
	while x < x1:
		var z := z0 + 0.71
		while z < z1:
			_probe_down(space, Vector3(x, 700.0, z))
			n += 1
			z += step
		x += step
	_probe_walls(space, x0, x1, z0, z1, step)
	print("AUDIT %d columns in %d ms (step %.1f m, region %s)" % [n, Time.get_ticks_msec() - t0, step, region])
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		print("AUDIT %-6s %6d  e.g. %s" % [k, counts[k], ", ".join(samples[k].slice(0, 8))])
	var hk := hist.keys()
	hk.sort()
	for k in hk:
		print("AUDIT   %s: %d" % [k, hist[k]])
	if counts.is_empty():
		print("AUDIT clean")
	quit()


func _note(kind: String, p: Vector3, extra := "") -> void:
	counts[kind] = counts.get(kind, 0) + 1
	if not samples.has(kind):
		samples[kind] = []
	var arr: Array = samples[kind]
	# Keep samples spread out: skip ones near an earlier sample.
	for s in arr:
		if (s as String).begins_with("(%d,%d" % [int(p.x / 40.0) * 40, int(p.z / 40.0) * 40]):
			return
	if arr.size() < 40:
		arr.append("(%d,%d %s)%s" % [int(p.x / 40.0) * 40, int(p.z / 40.0) * 40,
			"%.0f,%.1f,%.0f" % [p.x, p.y, p.z], extra])


func _ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, mask)
	q.hit_back_faces = false
	return space.intersect_ray(q)


func _probe_down(space: PhysicsDirectSpaceState3D, top: Vector3) -> void:
	var bottom := Vector3(top.x, -12.0, top.z)
	var vis := _ray(space, top, bottom, VIS_LAYER)
	var col := _ray(space, top, bottom, GAME_MASK)
	var vy: float = (vis["position"] as Vector3).y if not vis.is_empty() else -INF
	var cy: float = (col["position"] as Vector3).y if not col.is_empty() else -INF
	if vis.is_empty() and col.is_empty():
		return
	if vis.is_empty() or (cy - vy > 0.4):
		_note("ghost", Vector3(top.x, cy, top.z), " vis %.1f" % vy)
		return
	var water := world.layout.is_water(Vector3(top.x, 0, top.z)) and vy < -0.5
	if water:
		return
	var d := vy - cy
	if d < -0.04:
		_note("float@" + ("ground" if vy < 0.5 else "high"), Vector3(top.x, vy, top.z), " by %.2f" % -d)
		return
	if d < 0.04:
		return
	if col.is_empty() or (d > 1.2 and vy <= 0.3):
		_note("hole", Vector3(top.x, vy, top.z), " col %s" % ("none" if col.is_empty() else "%.1f" % cy))
	elif d > 0.6:
		_note("over", Vector3(top.x, vy, top.z), " col %.1f %s" % [cy, (vis["collider"] as Node).name])
	else:
		_note("sink@" + ("ground" if vy < 0.5 else "high"), Vector3(top.x, vy, top.z), " by %.2f %s" % [d, (vis["collider"] as Node).name])


## Body-height rays along every street in the playable grid, both ways across:
## a drawn wall that starts before the collision means the body slides inside it.
func _probe_walls(space: PhysicsDirectSpaceState3D, x0: float, x1: float, z0: float, z1: float, step: float) -> void:
	for h in [0.4, 1.0, 1.7]:
		for s in world.layout.x_streets:
			var cx: float = s[0]
			var z := maxf(z0, CityLayout.MIN_Z)
			while z < minf(z1, CityLayout.MAX_Z):
				for dir in [1.0, -1.0]:
					var a := Vector3(cx, h, z)
					_wall_pair(space, a, a + Vector3(dir * 60.0, 0, 0))
				z += step
		for s in world.layout.z_streets:
			var cz: float = s[0]
			var x := maxf(x0, CityLayout.RIVER_EDGE)
			while x < minf(x1, CityLayout.MAX_X):
				for dir in [1.0, -1.0]:
					var a := Vector3(x, h, cz)
					_wall_pair(space, a, a + Vector3(0, 0, dir * 60.0))
				x += step


func _wall_pair(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> void:
	var vis := _ray(space, a, b, VIS_LAYER)
	if vis.is_empty():
		return
	var col := _ray(space, a, b, GAME_MASK)
	var dv := a.distance_to(vis["position"])
	var dc := a.distance_to(col["position"]) if not col.is_empty() else INF
	if dc - dv > 0.06:
		_note("wall", vis["position"], " by %s %s" % ["all" if dc == INF else "%.2f" % (dc - dv), (vis["collider"] as Node).name])


# ------------------------------------------------------------- visuals
func _mirror_visuals(n: Node) -> int:
	var tris := 0
	for c in n.get_children():
		var nm := String(c.name)
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if nm in ["Detail", "Features", "Ground", "Water", "Outskirts", "OutskirtsNear", "OutskirtsBlocks", "OutskirtsGround"] \
					and mi.mesh != null:
				tris += _add_trimesh(mi.mesh, mi.global_transform, String(mi.get_parent().name) + "/" + nm)
		elif c is MultiMeshInstance3D and nm.begins_with("Landmark_"):
			var mm := (c as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				tris += _add_trimesh(mm.mesh, (c as Node3D).global_transform * mm.get_instance_transform(i), nm)
		if c.get_child_count() > 0 and not (c is MultiMeshInstance3D):
			tris += _mirror_visuals(c)
	return tris


func _add_trimesh(mesh: Mesh, xf: Transform3D, label: String) -> int:
	var faces := mesh.get_faces()
	if faces.is_empty():
		return 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.collision_layer = VIS_LAYER
	body.name = label.replace("/", "_")
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	world.add_child(body)
	body.global_transform = xf
	return faces.size() / 3
