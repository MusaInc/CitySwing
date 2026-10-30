extends RefCounted
## The shop (buying, equipping, try-on looks) and coins for swinging
## (CoinMeter: the multiplier climbs while you swing, a knockout resets it).


func _sd() -> Node:
	return Engine.get_main_loop().root.get_node("/root/SaveData")


func _fresh() -> Dictionary:
	var before: Dictionary = _sd().data.duplicate(true)
	_sd().data = _sd().DEFAULTS.duplicate(true)
	return before


func test_catalogue_is_consistent(t) -> void:
	var ids := {}
	for it in Shop.items():
		t.check(not ids.has(it["id"]), "unique id %s" % it["id"])
		ids[it["id"]] = true
	for sl in Shop.SLOTS:
		var d: String = Shop.DEFAULTS[sl[0]]
		t.check(Shop.item(d).get("slot", "") == sl[0], "default for %s is in its slot" % sl[0])
		t.check(Shop.in_slot(sl[0]).size() >= 4, "%s has a real choice" % sl[1])
	for it in Shop.items():
		if it.has("model") and it["model"] != "" and it["model"] != "hood":
			t.check(ResourceLoader.exists(CharacterRig.GEAR_PATH), "gear model file exists")


func test_buying_and_equipping(t) -> void:
	var before := _fresh()
	t.check(Shop.owns("pants_navy") and Shop.owns("head_hood"), "free items are owned")
	t.check(not Shop.owns("head_cap"), "paid items start locked")
	t.check(not Shop.buy("head_cap"), "can't buy without coins")
	t.check(not Shop.equip("head_cap"), "can't wear what you don't own")
	_sd().add_coins(1000)
	t.check(Shop.buy("head_cap"), "buy with enough coins")
	t.check(Shop.coins() == 400, "price taken (%d left)" % Shop.coins())
	t.check(not Shop.buy("head_cap"), "can't buy twice")
	t.check(Shop.equip("head_cap") and Shop.equipped("head") == "head_cap", "wear it")
	t.check(Shop.look()["head"] == "cap", "look carries the hat model")
	t.check(not Shop.for_sale("jade") and not Shop.buy("jade"), "earned suits aren't sold")
	_sd().add_coins(1000)
	t.check(Shop.buy("tangerine") and Shop.equip("tangerine"), "buy and wear a suit")
	t.check(Progress.current_suit_color() == Shop.item("tangerine")["color"], "bought suit colours the hero")
	t.check(Shop.look({"suit": "ember"})["suit"] == Shop.item("ember")["color"], "try-on overrides a slot")
	t.check(Shop.look()["sole"] == Shop.item("tangerine")["color"], "classic soles match the suit")
	_sd().data["outfit"]["face"] = "face_visor"  # tampered / unowned
	t.check(Shop.equipped("face") == "face_none", "unowned saved item falls back to the default")
	_sd().data = before


func test_multiplier_climbs_and_knockout_resets(t) -> void:
	var before := _fresh()
	var m := CoinMeter.new()
	m.start_run()
	t.check(m.multiplier() == 1.0, "starts at ×1")
	m.swing(CoinMeter.METRES_PER_COIN * 4.0)
	t.check(m.run_coins == 4, "×1 pays a coin per %d m (%d)" % [CoinMeter.METRES_PER_COIN, m.run_coins])
	m.swing(CoinMeter.LEVEL_METRES * 3.0)
	# 100 m + 360 m swung = three steps
	t.check(is_equal_approx(m.multiplier(), 1.0 + 3.0 * CoinMeter.STEP), "climbs while swinging (×%.1f)" % m.multiplier())
	var c0 := m.run_coins
	m.swing(CoinMeter.METRES_PER_COIN * 10.0)
	t.check(m.run_coins - c0 >= 20, "a higher multiplier pays more (%d for 10 coins' worth)" % (m.run_coins - c0))
	var lost := []
	m.multiplier_changed.connect(func(mult, up, from): if not up: lost.append(from))
	m.lose()
	t.check(m.multiplier() == 1.0 and lost.size() == 1 and lost[0] > 2.0, "knockout drops it to ×1")
	t.check(_sd().data["coins"] == m.run_coins, "earned coins are banked, not lost")
	m.swing(CoinMeter.LEVEL_METRES * 1000.0)
	t.check(m.multiplier() == CoinMeter.MAX_MULT, "capped at ×%d" % CoinMeter.MAX_MULT)
	m.active = false
	m.free()
	_sd().data = before


func test_rig_wears_the_look(t) -> void:
	var rig := CharacterRig.new()
	Engine.get_main_loop().root.add_child(rig)
	rig.apply_look(Shop.look({"head": "head_crown", "face": "face_shades", "pants": "pants_red"}))
	var head: Node3D = rig.bones["head"]
	var shown := []
	for c in head.get_children():
		if c is MeshInstance3D and c.visible and c.name != "head":
			shown.append(String(c.name).to_lower())
	shown.sort()
	t.check(shown == ["crown", "shades"], "crown + shades on, hood off (%s)" % [shown])
	rig.apply_look(Shop.look())
	shown.clear()
	for c in head.get_children():
		if c is MeshInstance3D and c.visible and c.name != "head":
			shown.append(String(c.name).to_lower())
	t.check(shown == ["hood"], "default look is the hood (%s)" % [shown])
	rig.queue_free()
