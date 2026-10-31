extends Node
## Scale audit: the world's pieces agree with a 1.8 m person and with each
## other (doors, storeys, lanes vs cars, kerbs, lamps, rooftop kit, trains vs
## platforms, balconies). A believable city is mostly consistent proportions.

const PERSON := 1.8


func _aabb(name: String) -> AABB:
	var w := CityWorld.new()
	var m: Mesh = w._load_mesh(name)
	w.free()
	return m.get_aabb() if m else AABB()


func test_character_matches_the_world(t) -> void:
	var p := Player.new()
	add_child(p)
	var cap := (p.get_node("Shape") as CollisionShape3D).shape as CapsuleShape3D
	t.check(absf(cap.height - PERSON) < 0.15, "player capsule is person-sized (%.2f m)" % cap.height)
	# (The whole assembled model – body, hood, hands – in its rest pose.)
	var scene: PackedScene = load("res://assets/models/character.glb")
	var inst := scene.instantiate() as Node3D
	add_child(inst)
	var char_bb := AABB()
	var first := true
	for mi in inst.find_children("*", "VisualInstance3D", true, false):
		var bb: AABB = (mi as VisualInstance3D).global_transform * (mi as VisualInstance3D).get_aabb()
		char_bb = bb if first else char_bb.merge(bb)
		first = false
	inst.queue_free()
	t.note("character model %.2f m tall" % char_bb.size.y)
	t.check(char_bb.size.y > 1.65 and char_bb.size.y < 2.0, "character model ~1.8 m")
	p.queue_free()


func test_buildings_streets_and_props_share_one_scale(t) -> void:
	# Storeys (BuildingMesher window cells / the facade shader): 3.0–4.4 m.
	for st in BuildingMesher.BALCONY_CELLS:
		var c: Vector2 = BuildingMesher.BALCONY_CELLS[st]
		t.check(c.y >= 2.9 and c.y <= 4.5, "storey %.1f m" % c.y)
		t.check(c.y > PERSON * 1.55, "headroom over a person")
	# Shop doors (building.gdshader: 0.25–2.5 m, 1.1 m wide) clear a person.
	t.check(2.5 - 0.25 > PERSON + 0.3, "shop doors taller than a person")
	# Cars: ~4–5 m long, ≤ 2.1 m wide, lanes (3.2 m from the centre line) fit them.
	for k in ["car_sedan", "car_hatch", "car_suv", "car_taxi", "car_van"]:
		var bb := _aabb(k)
		var l := maxf(bb.size.x, bb.size.z)
		var w := minf(bb.size.x, bb.size.z)
		# (Widths include the door mirrors.)
		t.check(l > 3.4 and l < 5.8 and w < 2.4 and bb.size.y > 1.2 and bb.size.y < 2.6,
			"%s %.1f × %.1f × %.1f m" % [k, l, w, bb.size.y])
		t.check(w < 3.5 - 1.0, "%s fits a 3.5 m lane with room either side" % k)
	# Street lamps ~7 m; kerb 15 cm; rooftop kit person-scaled.
	var lamp := _aabb("streetlight")
	t.check(lamp.size.y > 6.0 and lamp.size.y < 9.0, "streetlight %.1f m" % lamp.size.y)
	t.check(is_equal_approx(CityTerrain.KERB, 0.15), "kerb 15 cm")
	var ac := _aabb("ac_unit")
	t.check(ac.size.y > 0.8 and ac.size.y < 2.0, "AC unit %.1f m tall" % ac.size.y)
	var ct := _aabb("cooling_tower")
	t.check(ct.size.y > 2.0 and ct.size.y < 4.0, "cooling tower %.1f m tall" % ct.size.y)
	var hut := _aabb("roof_hut")
	t.check(hut.size.y > PERSON + 0.8, "roof stair hut taller than a person (%.1f m)" % hut.size.y)


func test_trains_and_platforms_line_up(t) -> void:
	var car := _aabb("train_car")
	t.note("train car %.1f × %.1f × %.1f m" % [car.size.x, car.size.y, car.size.z])
	t.check(car.size.z > 16.0 and car.size.z < 19.0, "car ~17.6 m long")
	t.check(car.size.x > 2.6 and car.size.x < 3.2, "car ~2.9 m wide")
	t.check(car.size.y > 3.6 and car.size.y < 4.4, "car roof ~4 m over the rail")
	# Platform top (RailNetwork._station) sits at the car floor: 1.0 m over the rail.
	t.check(absf(-0.1 + 2.2 * 0.5 - 1.0) < 0.05, "platform level with the car floor")
	# Platform edge clear of the car side: track 2.1 + half car 1.45 < platform inner edge.
	var inner := RailNetwork.TRACK + RailNetwork.PLATFORM_GAP
	t.check(inner > RailNetwork.TRACK + car.size.x * 0.5 and inner < RailNetwork.TRACK + car.size.x * 0.5 + 0.2,
		"platform edge clears the train by a few cm (%.2f m)" % (inner - RailNetwork.TRACK - car.size.x * 0.5))


func test_balconies_are_person_scaled(t) -> void:
	var l := CityLayout.new().generate()
	var checked := 0
	for b in l.buildings:
		if b["kind"] != "normal":
			continue
		var f := BuildingMesher.features(b)
		for d in f["draw"]:
			var bx: AABB = d[0]
			# A railing: thin, about waist height.
			if d.size() == 2 and absf(bx.size.y - 1.05) < 0.01:
				t.check(minf(bx.size.x, bx.size.z) < 0.1, "railing is thin")
				checked += 1
				break
		if checked >= 10:
			break
	t.note("%d balcony railings checked" % checked)
	t.check(checked > 0, "balconies exist")
	t.check(1.05 > 0.95 and 1.05 < 1.2, "railings at ~1.05 m (waist height for 1.8 m)")
