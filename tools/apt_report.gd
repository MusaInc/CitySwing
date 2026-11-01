extends SceneTree
## Where the homes went: building, floor, height, view.
##   godot --headless -s res://tools/apt_report.gd
func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var l := CityLayout.new().generate()
	print("APT layout+homes %d ms" % (Time.get_ticks_msec() - t0))
	for h in l.apartments.homes:
		var w := Apartments.window_center(h)
		print("APT %-10s floor %.1f m above street, building top %.0f m, window %s, out %s" % [h["id"],
			Apartments.floor_height(h), float(h["b"]["tiers"][-1][5]) - BuildingMesher.base_of(h["b"]), w.snapped(Vector3.ONE * 0.1),
			Apartments.outward(h).snapped(Vector3.ONE * 0.01)])
		var n := Apartments.outward(h)
		var sp := Apartments.spawn_point(h)
		var ci := sp + Vector3.UP * 0.75 - n * 1.6
		var li := Apartments.window_center(h) + n * 40.0 + Vector3.UP * 1.0
		var co := w + n * 13.0 + Vector3.UP * 3.0 + Apartments.along_dir(h) * 4.0
		print("CAM %s in %s out %s" % [h["id"], _c(ci, li), _c(co, w + Vector3.UP * 1.2)])
	quit()


func _c(a: Vector3, b: Vector3) -> String:
	return "%.2f,%.2f,%.2f,%.2f,%.2f,%.2f" % [a.x, a.y, a.z, b.x, b.y, b.z]
