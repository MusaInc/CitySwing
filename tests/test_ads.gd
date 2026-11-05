extends Node
## Advertising screens (AdScreens): placed deterministically on open facades
## of the real layout, concentrated in Lumen Circus, quiet in Old Town and
## the suburbs, never in front of a building or the railway, and neighbours
## never showing the same advert at once.

var layout: CityLayout
var ads: AdScreens


func setup() -> void:
	layout = CityLayout.new().generate()
	ads = AdScreens.new()
	add_child(ads)
	ads.build(layout)
	await get_tree().process_frame


func teardown() -> void:
	ads.queue_free()
	await get_tree().process_frame


func test_atlas_metadata_is_complete(t) -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AdScreens.META))
	t.check((meta["ads"] as Array).size() == 12, "12 campaigns in the atlas (shader ORDER has 12)")
	for tk: Dictionary in meta["tickers"]:
		t.check(float(tk["period"]) <= float(meta["size"][0]), "ticker %s loops within the strip" % tk["id"])
	for ad: Dictionary in meta["ads"]:
		t.check(AdScreens.FX.has(ad["fx"]), "%s has a known motion kind" % ad["id"])


func test_placement_is_deterministic(t) -> void:
	var again := AdScreens.new()
	add_child(again)
	again.build(layout)
	t.check(again.screens.size() == ads.screens.size(), "same number of screens (%d)" % ads.screens.size())
	var same := true
	for i in mini(again.screens.size(), ads.screens.size()):
		if (again.screens[i]["c"] as Vector3).distance_to(ads.screens[i]["c"]) > 0.01 or again.screens[i]["off"] != ads.screens[i]["off"]:
			same = false
	t.check(same, "same screens in the same places with the same rotation")
	again.queue_free()


func test_district_is_busy_and_residential_streets_are_quiet(t) -> void:
	var district := 0
	var quiet := 0
	for s: Dictionary in ads.screens:
		var c: Vector3 = s["c"]
		if s["district"]:
			district += 1
			t.check(Vector2(c.x, c.z).distance_to(AdScreens.DISTRICT) < AdScreens.DISTRICT_R + 40.0, "district screen is in Lumen Circus")
		elif layout.district(c.x, c.z) in ["georgian", "suburb"]:
			quiet += 1
	t.check(district >= 40, "Lumen Circus has a real density of screens (%d)" % district)
	t.check(quiet == 0, "none in Old Town or the suburbs (%d)" % quiet)
	t.check(ads.screens.size() - district < 260, "the rest of the city stays restrained (%d)" % (ads.screens.size() - district))


func test_screens_are_on_open_facades(t) -> void:
	var blocked := 0
	var rail := 0
	for s: Dictionary in ads.screens:
		# Every point along the screen (corner wraps bend round a corner, so
		# the chord between the ends runs through the building).
		var pts: Array = s["pts"]
		var nrm: Array = s["n"]
		var y := (float(s["y0"]) + float(s["y1"])) * 0.5
		var hit := false
		var near := false
		for i in pts.size():
			var front: Vector3 = (pts[i] as Vector3) + Vector3(0, y, 0) + (nrm[i] as Vector3) * 2.0
			hit = hit or ads._solid(front)
			near = near or ads._near_rail(front, 8.0)
		blocked += int(hit)
		rail += int(near)
	t.check(blocked == 0, "nothing built in front of any screen (%d blocked)" % blocked)
	t.check(rail == 0, "no screen in the railway's way (%d)" % rail)


func test_neighbours_show_different_adverts(t) -> void:
	var pairs := 0
	var clash := 0
	var same_building := 0
	for i in ads.screens.size():
		var a: Dictionary = ads.screens[i]
		if int(a["kind"]) != 1:
			continue
		for j in range(i + 1, ads.screens.size()):
			var b: Dictionary = ads.screens[j]
			if int(b["kind"]) != 1:
				continue
			var d := (a["c"] as Vector3).distance_to(b["c"])
			if a.get("bkey", "a") == b.get("bkey", "b"):
				same_building += int(a["off"] == b["off"])
			elif d < 35.0:
				pairs += 1
				clash += int(a["off"] == b["off"])
	t.check(same_building == 0, "screens on one building never match (%d)" % same_building)
	t.check(clash == 0, "close neighbours never show the same advert (%d of %d pairs)" % [clash, pairs])
	t.note("%d close pairs checked" % pairs)
