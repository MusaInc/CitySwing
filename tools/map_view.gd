extends SceneTree
## Top-down map of the whole world (playable grid + outskirts + far shore):
## building tops coloured by height above ground (grey < 30 m, then blue →
## green → yellow → red at 250 m+), water blue, parks green, ground dark.
## Prints per-district height stats for swingability (share of footprint
## area with tops ≥ 45 m above street).
##   godot --headless -s res://tools/map_view.gd -- <out.png> [m_per_px] [half_extent_m]

func _initialize() -> void:
	_go.call_deferred()


func _hcol(h: float) -> Color:
	if h < 30.0:
		return Color(0.45, 0.45, 0.45).lerp(Color(0.62, 0.62, 0.62), h / 30.0)
	var t := clampf((h - 30.0) / 220.0, 0.0, 1.0)
	return Color.from_hsv(0.66 * (1.0 - t), 0.85, 0.95)


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "map.png"
	var mpp := float(args[1]) if args.size() > 1 else 4.0
	var ext := float(args[2]) if args.size() > 2 else 1600.0
	var world := CityWorld.new()
	root.add_child(world)
	await physics_frame
	var c0 := Vector2(540.0, -20.0)
	var n := int(ext * 2.0 / mpp)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	img.fill(Color(0.16, 0.15, 0.14))
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1 | (1 << 1) | (1 << 3)
	var l: CityLayout = world.layout
	var stats := {}
	for i in n:
		for j in n:
			var x := c0.x - ext + (i + 0.5) * mpp
			var z := c0.y - ext + (j + 0.5) * mpp
			q.from = Vector3(x, 900.0, z)
			q.to = Vector3(x, -30.0, z)
			var hit := space.intersect_ray(q)
			var g := l.ground_y(x, z) if l.has_method("ground_y") else 0.0
			var col := Color(0.12, 0.25, 0.42)  # water / nothing
			if not hit.is_empty():
				var y: float = hit.position.y
				var hh := y - g
				col = _hcol(hh) if hh > 2.0 else Color(0.22, 0.21, 0.2)
				if hh <= 2.0 and l.is_water(Vector3(x, 0, z)):
					col = Color(0.12, 0.25, 0.42)
				if x > CityLayout.RIVER_EDGE and x < CityLayout.MAX_X and z > CityLayout.MIN_Z and z < CityLayout.MAX_Z:
					var d := l.district(x, z)
					var s: Array = stats.get(d, [0, 0, 0])
					s[0] += 1
					if hh > 2.0:
						s[1] += 1
					if hh >= 45.0:
						s[2] += 1
					stats[d] = s
			img.set_pixel(i, j, col)
	img.save_png(out)
	for d in stats:
		var s: Array = stats[d]
		print("%-11s built %3d%%  tall(>=45m) %3d%% of area, %3d%% of built" % [d, 100 * s[1] / s[0], 100 * s[2] / s[0], 100 * s[2] / maxi(s[1], 1)])
	quit()
