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
		if it.has("model") and it["model"] != "":
			t.check(ResourceLoader.exists(CharacterRig.GEAR_PATH), "gear model file exists")


func test_buying_and_equipping(t) -> void:
	var before := _fresh()
	t.check(Shop.owns("pants_navy") and Shop.owns("head_bare") and Shop.owns("hero_ren"), "free items are owned")
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
	t.check(Shop.look()["sole"] == Color(0.929, 0.929, 0.894),
		"Courier's classic trainers stay white when the jacket changes")
	t.check(Shop.look({"shoes": "shoes_gum"})["sole"] == Color(0.55, 0.35, 0.18),
		"shoe try-on retains its own sole colour independently of the jacket")
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
	t.check(shown == ["crown", "shades"], "crown + shades on (%s)" % [shown])
	rig.apply_look(Shop.look())
	shown.clear()
	for c in head.get_children():
		if c is MeshInstance3D and c.visible and c.name != "head":
			shown.append(String(c.name).to_lower())
	t.check(shown.is_empty() and rig.look_state.head == "", "default clears crown and shades")
	# Default: the long-sleeve top, Kai's face and hair, no mask.
	var vis := func(n: String) -> bool:
		var mi := rig.skeleton.find_child(n, true, false) as MeshInstance3D
		return mi != null and mi.visible
	t.check(vis.call("Top_Long") and not vis.call("Top_Short") and not vis.call("Skin_Arms_Short"), "default long-sleeve top")
	t.check(vis.call("Face_kai") and vis.call("Hair_kai") and not vis.call("Face_ade"), "default face and hair, one at a time")
	# Short sleeves bare the forearms; a full mask hides the face beneath it.
	rig.apply_look(Shop.look({"top": "top_short", "hero": "hero_ade", "face": "mask_courier"}))
	t.check(vis.call("Top_Short") and vis.call("Skin_Arms_Short") and not vis.call("Top_Long"), "short sleeves show the forearms")
	t.check(vis.call("Mask_courier") and not vis.call("Face_ade") and not vis.call("Hair_ade"), "the Courier mask covers the face")
	rig.apply_look(Shop.look({"hero": "hero_theo", "face": "mask_domino", "head": "head_beanie"}))
	t.check(vis.call("Face_theo") and vis.call("Mask_domino") and not vis.call("Hair_theo"), "domino over the face, hair under the beanie")
	var skin_tints := {}
	for e in rig._hero_materials:
		if e.region == "skin":
			skin_tints[str(e.material.get_shader_parameter("tint"))] = true
	rig.apply_look(Shop.look({"hero": "hero_ade"}))
	var changed := false
	for e in rig._hero_materials:
		if e.region == "skin" and not skin_tints.has(str(e.material.get_shader_parameter("tint"))):
			changed = true
	t.check(changed, "each face brings its own skin tone")
	rig.queue_free()


## A player standing on a slab (scene tests need a floor and physics frames).
func _stage() -> Array:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var stage := Node3D.new()
	root.add_child(stage)
	PrototypeWorld.add_box(stage, Vector3(0, -0.5, 0), Vector3(200, 1, 200), Color.GRAY, false, true)
	var p := Player.new()
	p.params = load("res://config/swing_params.tres").duplicate()
	p.input_enabled = false
	stage.add_child(p)
	p.respawn(Vector3(0, 1.0, 0))
	var g := Gadgets.new()
	stage.add_child(g)
	g.player = p
	g.coins = CoinMeter.new()
	stage.add_child(g.coins)
	g.enabled = true
	return [stage, p, g]


func test_gadgets(t) -> void:
	var st := _stage()
	var p: Player = st[1]
	var g: Gadgets = st[2]
	var tree := Engine.get_main_loop() as SceneTree
	for i in 20:
		await tree.physics_frame
	g.equip(Shop.item("gadget_none"))
	t.check(not g.trigger(), "nothing equipped, nothing happens")
	g.equip(Shop.item("gadget_jets"))
	t.check(g.trigger(), "jet boots fire")
	t.check(p.s.velocity.y > 5.0 and Vector2(p.s.velocity.x, p.s.velocity.z).length() > 12.0,
		"boost throws you forward and up (%s)" % p.s.velocity)
	t.check(not g.trigger(), "can't fire again while it runs")
	g.stop()
	t.check(g.cooldown > 0.0 and not g.ready_to_use(), "then it recharges")
	g.cooldown = 0.0
	p.bot = SwingBot.new(SwingBot.Style.EXPERT, Vector3.FORWARD)
	t.check(not g.trigger(), "never for the autopilot")
	p.bot = null
	# Glider: from high up, the fall stays slow.
	g.equip(Shop.item("gadget_glider"))
	p.respawn(Vector3(0, 80.0, 0))
	g.cooldown = 0.0
	t.check(g.trigger() and p.glide, "glider opens")
	for i in 60:
		await tree.physics_frame
	t.check(p.s.velocity.y >= -Player.GLIDE_SINK - 0.5, "gliding sinks slowly (%.1f m/s)" % p.s.velocity.y)
	g.stop()
	t.check(not p.glide, "wings fold when it ends")
	# Coin magnet doubles the pay.
	g.equip(Shop.item("gadget_magnet"))
	g.cooldown = 0.0
	g.coins.start_run()
	g.coins.swing(CoinMeter.METRES_PER_COIN * 10.0)
	var single := g.coins.run_coins
	g.trigger()
	g.coins.swing(CoinMeter.METRES_PER_COIN * 10.0)
	t.check(g.coins.run_coins - single >= single * 2 - 1, "magnet doubles coins (%d then %d)" % [single, g.coins.run_coins - single])
	g.stop()
	t.check(not g.coins.surge, "magnet ends")
	# Chrono watch slows time and always gives it back.
	g.equip(Shop.item("gadget_chrono"))
	g.cooldown = 0.0
	g.trigger()
	await tree.process_frame
	await tree.process_frame
	t.check(Engine.time_scale < 0.6, "chrono slows time (%.2f)" % Engine.time_scale)
	g.stop()
	t.check(Engine.time_scale == 1.0, "time back to normal")
	g.coins.active = false
	(st[0] as Node).queue_free()
