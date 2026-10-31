extends SceneTree
## Top-down preview of the road network (CityRoads): sea, coast, roads,
## blocks coloured by district (plazas pale, greens green).
##   godot --headless -s res://tools/roads_view.gd -- <out.png> [m_per_px]

const COLS := {"cbd": Color(0.85, 0.55, 0.35), "midtown": Color(0.75, 0.7, 0.45), "waterfront": Color(0.5, 0.7, 0.85),
	"docks": Color(0.6, 0.55, 0.6), "georgian": Color(0.75, 0.45, 0.45)}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "roads.png"
	var mpp := float(args[1]) if args.size() > 1 else 2.0
	var lay := CityLayout.new()
	var t0 := Time.get_ticks_msec()
	var R := CityRoads.new().generate(1207, lay.district, Rect2(30.0, -656.0, 1000.0, 1271.0))
	print("roads: %d, blocks: %d, roundabouts %d, %d ms" % [R.roads.size(), R.blocks.size(), R.roundabouts.size(), Time.get_ticks_msec() - t0])
	var kinds := {}
	for b in R.blocks:
		kinds[b["kind"]] = kinds.get(b["kind"], 0) + 1
	print(kinds)
	var x0 := -60.0
	var z0 := -720.0
	var W := int(1180.0 / mpp)
	var H := int(1400.0 / mpp)
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	img.fill(Color(0.12, 0.25, 0.42))
	var fill := func(poly: PackedVector2Array, col: Color) -> void:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for v in poly:
			lo = lo.min(v)
			hi = hi.max(v)
		for i in range(maxi(0, int((lo.x - x0) / mpp)), mini(W, int((hi.x - x0) / mpp) + 1)):
			for j in range(maxi(0, int((lo.y - z0) / mpp)), mini(H, int((hi.y - z0) / mpp) + 1)):
				if Geometry2D.is_point_in_polygon(Vector2(x0 + (i + 0.5) * mpp, z0 + (j + 0.5) * mpp), poly):
					img.set_pixel(i, j, col)
	fill.call(R.coast, Color(0.86, 0.8, 0.62))  # esplanade / beach edge
	fill.call(Geometry2D.offset_polygon(R.coast, -CityRoads.ESPLANADE)[0], Color(0.2, 0.2, 0.22))  # road surface
	for b in R.blocks:
		var col: Color = COLS.get(b["district"], Color.WHITE)
		if b["kind"] == "plaza":
			col = Color(0.8, 0.8, 0.78)
		elif b["kind"] == "green":
			col = Color(0.35, 0.6, 0.3)
		fill.call(b["poly"], col)
	img.save_png(out)
	quit()
