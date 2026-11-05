extends SceneTree
## Unfinished-ground audit: every block of both layouts (island + mainland)
## with its kind, area, how much of it buildings cover and how many props
## dress it, worst first. Big bare plazas and near-empty blocks are what
## reads as "unfinished" from the rooftops.
##   godot --headless -s res://tools/ground_audit.gd -- [min_bare_m2] [out.png]
## The optional PNG is a top-down sketch (m_per_px 4): plazas tan, bare
## open ground red, parks green, buildings grey.


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var min_bare := float(args[0]) if args.size() > 0 else 1200.0
	var out: String = args[1] if args.size() > 1 else ""
	var world := CityWorld.new()
	root.add_child(world)
	await physics_frame
	var layouts: Array = [world.layout] if world.layout.mainland == null else [world.layout.mainland, world.layout]
	var rows: Array = []
	for L: CityLayout in layouts:
		var foot: Array = []   # building footprints (world polygons)
		for b in L.buildings:
			var tiers: Array = b["tiers"]
			if tiers.is_empty() or b.get("kind", "") == "invisible":
				continue
			var t: Array = tiers[0]
			var rot: float = b.get("rot", 0.0)
			var pv: Vector2 = b.get("pivot", Vector2.ZERO)
			var quad := PackedVector2Array()
			for c in [Vector2(t[0], t[1]), Vector2(t[2], t[1]), Vector2(t[2], t[3]), Vector2(t[0], t[3])]:
				quad.append(c if rot == 0.0 else CityLayout.to_world2(c, rot, pv))
			foot.append(quad)
		for bi in L.blocks.size():
			var blk: Dictionary = L.blocks[bi]
			var poly: PackedVector2Array = blk["poly"]
			var area := CityRoads._area(poly)
			var built := 0.0
			for q: PackedVector2Array in foot:
				if Geometry2D.is_point_in_polygon(CityRoads._centroid(q), poly):
					built += CityRoads._area(q)
			var bare := area - built
			if bare >= min_bare and blk["kind"] not in ["park", "basin", "esplanade"]:
				rows.append([bare, "mainland" if L.is_mainland else "island", bi, blk["kind"], blk["district"], area, built,
					CityRoads._centroid(poly)])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows:
		print("BARE %6.0f m2  %-8s block %3d  %-6s %-10s area %6.0f built %3.0f%%  at (%.0f, %.0f)" % [r[0], r[1], r[2], r[3],
			r[4], r[5], 100.0 * r[6] / maxf(r[5], 1.0), (r[7] as Vector2).x, (r[7] as Vector2).y])
	print("GROUND_AUDIT ", rows.size(), " blocks with >= ", min_bare, " m2 bare")
	quit()
