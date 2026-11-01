extends SceneTree
## Top-down debug render of the road paint logic (ground.gdshader's use of the
## road field) around a point: asphalt, junctions, centre lines, zebras.
##   godot --headless -s res://tools/paint_view.gd -- <out.png> <x> <z> [half m] [m/px]

func _band(x: float, w: float) -> float:
	return 1.0 if absf(x) < w else 0.0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0]
	var cx := float(a[1])
	var cz := float(a[2])
	var half := float(a[3]) if a.size() > 3 else 80.0
	var mpp := float(a[4]) if a.size() > 4 else 0.25
	var L := CityLayout.new().generate()
	var R := L.roads
	var n := int(half * 2.0 / mpp)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for j in n:
		for i in n:
			var p := Vector2(cx - half + (i + 0.5) * mpp, cz - half + (j + 0.5) * mpp)
			var col := Color(0.75, 0.72, 0.66)
			var bi := L.block_at(p.x, p.y)
			if bi < 0:
				# Bilinear like the shader would (texel centres).
				var f := _field(R, p)
				var hw := absf(f.y)
				var aa := absf(f.x)
				var other := f.w
				col = Color(0.3, 0.3, 0.32)
				if aa < hw and other > 0.0:
					var avenue := f.y < 0.0
					var along := f.z
					var centre := 0.0
					if avenue:
						centre = _band(aa - 0.22, 0.07 + mpp * 0.5) * (1.0 if other >= 4.6 else 0.0)
					else:
						centre = _band(f.x, 0.07 + mpp * 0.5) * (1.0 if other >= 5.0 else 0.0) * (1.0 if fposmod(along / 8.0, 1.0) <= 0.375 else 0.0)
					var zu := fposmod((f.x + hw - 1.5) / 1.2, 1.0)
					var zebra := _band(zu - 0.5, 0.25) * (1.0 if other <= 4.0 and other >= 1.0 else 0.0) * (1.0 if aa <= hw - 1.0 else 0.0)
					var stop := _band(other - 4.8, 0.22 + mpp * 0.5) * (1.0 if aa >= 0.3 and aa <= hw - 0.3 else 0.0)
					if centre > 0.0:
						col = Color(0.95, 0.8, 0.2) if avenue else Color.WHITE
					if maxf(zebra, stop) > 0.0:
						col = Color.WHITE
				elif aa < hw:
					col = Color(0.4, 0.38, 0.4)
				elif not L.is_water(Vector3(p.x, 0.0, p.y)):
					col = Color(0.55, 0.2, 0.2)   # asphalt by block_at but off every carriageway
			img.set_pixel(i, j, col)
	img.save_png(out)
	print("saved ", out)
	quit()


func _field(R: CityRoads, p: Vector2) -> Vector4:
	var u := (p - R.field_rect.position) / R.field_cell - Vector2(0.5, 0.5)
	var i := floori(u.x)
	var j := floori(u.y)
	var fx := u.x - i
	var fy := u.y - j
	var s00 := R.field_at(R.field_rect.position + (Vector2(i, j) + Vector2(0.5, 0.5)) * R.field_cell)
	var s10 := R.field_at(R.field_rect.position + (Vector2(i + 1, j) + Vector2(0.5, 0.5)) * R.field_cell)
	var s01 := R.field_at(R.field_rect.position + (Vector2(i, j + 1) + Vector2(0.5, 0.5)) * R.field_cell)
	var s11 := R.field_at(R.field_rect.position + (Vector2(i + 1, j + 1) + Vector2(0.5, 0.5)) * R.field_cell)
	return s00.lerp(s10, fx).lerp(s01.lerp(s11, fx), fy)
