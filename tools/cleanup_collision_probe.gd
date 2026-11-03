extends SceneTree
func _initialize():
	var l := CityLayout.new().generate()
	for p in [Vector3(142.37,97.8,-399.29),Vector3(160.37,130.2,-393.29),Vector3(184.37,96.7,-507.29),Vector3(322.37,37.0,339.71)]:
		for b in l.buildings:
			var local: Vector3 = CityLayout.bxf(b).affine_inverse() * p
			for box in BuildingMesher.collision_boxes(b):
				if box.grow(0.12).has_point(local):
					print("MATCH ",p," kind=",b.kind," rot=",b.get("rot",0)," box=",box," tiers=",b.tiers)
	quit()
