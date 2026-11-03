extends SceneTree
func _initialize():
	var l = CityLayout.new().generate()
	print("DIAGONAL ", l.roads.along("diagonal", 40, 0, 500))
	for r in l.roads.roundabouts:
		print("ROUNDABOUT ",r.c)
	print("PLAZAS")
	for b in l.blocks:
		if b.kind == "plaza":
			print(CityRoads._centroid(b.poly), " area=", CityRoads._area(b.poly))
	quit()
