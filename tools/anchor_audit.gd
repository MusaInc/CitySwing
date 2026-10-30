extends SceneTree
## Where can you swing? For every cell of the playable map, at street level
## (1.5 m) and in flight (28 m up), fans rays like GrappleTargeting (16
## headings × 5 elevations, grapple range) plus the anchor lines, and scores
## the best anchor: none / weak (rise < 12 m) / good. Writes a top-down PNG
## (black = building footprint, red = no anchor, orange = weak, green = good)
## and prints coverage per district.
##   godot --headless -s res://tools/anchor_audit.gd -- <out.png> [cell_m]

const ELEVATIONS := [30.0, 42.0, 55.0, 68.0, 80.0]


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "anchor_audit.png"
	var cell := float(args[1]) if args.size() > 1 else 10.0
	var world := CityWorld.new()
	root.add_child(world)
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	var range_m: float = (load("res://config/swing_params.tres") as SwingParams).grapple_range
	var x0 := CityLayout.RIVER_EDGE
	var z0 := CityLayout.MIN_Z
	var w := int((CityLayout.MAX_X - x0) / cell)
	var h := int((CityLayout.MAX_Z - z0) / cell)
	var img := Image.create(w * 2 + 4, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.2, 0.25))
	var stats := {}  # "district/level" -> [good, weak, none]
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1 << 1
	var down := PhysicsRayQueryParameters3D.new()
	down.collision_mask = 1 | (1 << 1)
	for i in w:
		for j in h:
			var x := x0 + (i + 0.5) * cell
			var z := z0 + (j + 0.5) * cell
			down.from = Vector3(x, 600.0, z)
			down.to = Vector3(x, -1.0, z)
			var roof := space.intersect_ray(down)
			var inside := not roof.is_empty() and (roof["position"] as Vector3).y > 2.0
			var dist := world.layout.district(x, z)
			if world.layout.is_water(Vector3(x, 0, z)):
				dist = "water"
			for lv in 2:
				var px := i + lv * (w + 4)
				if inside and lv == 0:
					img.set_pixel(px, j, Color.BLACK)
					continue
				var y := 1.5 if lv == 0 else 28.0
				if inside and (roof["position"] as Vector3).y > y - 2.0:
					img.set_pixel(px, j, Color.BLACK)
					continue
				var best := _best_rise(space, q, Vector3(x, y, z), range_m)
				var k := 0 if best >= 12.0 else (1 if best > 0.0 else 2)
				img.set_pixel(px, j, [Color(0.2, 0.75, 0.3), Color(0.95, 0.6, 0.1), Color(0.85, 0.15, 0.15)][k])
				var key := "%s/%s" % [dist, "street" if lv == 0 else "air"]
				if not stats.has(key):
					stats[key] = [0, 0, 0]
				stats[key][k] += 1
	img.save_png(out)
	var keys := stats.keys()
	keys.sort()
	for key in keys:
		var s: Array = stats[key]
		var n: int = s[0] + s[1] + s[2]
		print("ANCHORS %-18s good %5.1f%%  weak %5.1f%%  none %5.1f%%  (%d cells)" % [key, 100.0 * s[0] / n,
			100.0 * s[1] / n, 100.0 * s[2] / n, n])
	print("ANCHORS wrote ", out)
	quit()


## Highest useful rise (m) of any anchor in reach, all round; 0 = none.
func _best_rise(space: PhysicsDirectSpaceState3D, q: PhysicsRayQueryParameters3D, o: Vector3, range_m: float) -> float:
	var best := 0.0
	for a in 16:
		var hd := Vector3.FORWARD.rotated(Vector3.UP, a * TAU / 16.0)
		for el in ELEVATIONS:
			var e := deg_to_rad(el)
			var d := (hd * cos(e) + Vector3.UP * sin(e)).normalized()
			q.from = o
			q.to = o + d * range_m
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var p: Vector3 = hit["position"]
			if o.distance_to(p) >= 6.0 and p.y - o.y >= 3.0:
				best = maxf(best, p.y - o.y)
	for line in GrappleTargeting.anchor_lines:
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		for t in 5:
			var p := a.lerp(b, t / 4.0)
			if o.distance_to(p) <= range_m and o.distance_to(p) >= 8.0 and p.y - o.y >= 3.0:
				best = maxf(best, p.y - o.y)
	return best
