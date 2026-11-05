extends RefCounted
## Progression (tokens, medals, suits) and the swing-feel rules layered on the
## pure model (snap redirect, perfect release window).

const DT := 1.0 / 60.0


func test_tokens_are_deterministic_and_clear_of_buildings(t) -> void:
	var layout := CityLayout.new().generate()
	var a := TokenField.generate(layout)
	var b := TokenField.generate(layout)
	t.check(a.size() == Progress.TOKEN_TOTAL, "all %d tokens placed (%d)" % [Progress.TOKEN_TOTAL, a.size()])
	t.check(a == b, "same spots every launch (collection is saved by index)")
	var inside := 0
	for p in a:
		for bd in layout.buildings:
			if CityLayout.inside(bd, p):
				inside += 1
	t.check(inside == 0, "no token inside a building")


func test_medal_thresholds(t) -> void:
	t.check(Progress.medal_for(100.0, 99.0) == Progress.Medal.GOLD, "under par is gold")
	t.check(Progress.medal_for(100.0, 120.0) == Progress.Medal.SILVER, "within 25% is silver")
	t.check(Progress.medal_for(100.0, 150.0) == Progress.Medal.BRONZE, "within 60% is bronze")
	t.check(Progress.medal_for(100.0, 200.0) == Progress.Medal.NONE, "slower earns nothing")
	t.check(Progress.medal_for(100.0, INF) == Progress.Medal.NONE, "no time, no medal")


func test_suit_unlocks_follow_progress(t) -> void:
	var sd: Node = Engine.get_main_loop().root.get_node("/root/SaveData")
	var before: Dictionary = sd.data.duplicate(true)
	sd.data["tokens"] = []
	sd.data["tutorial_done"] = false
	sd.data["best_trial_times"] = {}
	t.check(Progress.unlocked_ids() == ["ember"], "only the default suit at the start")
	var snap := Progress.unlocked_ids()
	sd.data["tutorial_done"] = true
	for i in 10:
		sd.data["tokens"].append(i)
	t.check(Progress.newly_unlocked(snap) == ["Cobalt", "Jade"], "training + 10 tokens unlock Cobalt and Jade")
	for id in CourseBuilder.COURSES:
		sd.data["best_trial_times"][id] = Progress.par(id) * 0.99
	t.check("gilded" in Progress.unlocked_ids() and "violet" in Progress.unlocked_ids(), "golds unlock Gilded and Violet")
	sd.data = before
	sd.save()


func test_snap_redirect_keeps_momentum_but_never_adds_energy(t) -> void:
	var p := SwingParams.new()
	p.air_drag = 0.0
	p.linear_drag = 0.0
	for redirect in [0.0, p.snap_redirect]:
		p.snap_redirect = redirect
		var s := SwingPhysics.State.new()
		# Flying sideways and outward when a slack 20 m rope snaps tight.
		s.anchor = Vector3(0, 100, 0)
		s.position = Vector3(18, 92, 0)
		s.velocity = Vector3(15, 0, 20)
		SwingPhysics.attach(s, s.anchor, p)
		s.rope_length = 20.0
		var e0 := SwingPhysics.energy(s, p)
		var c := SwingPhysics.Controls.new()
		var after := 0.0
		for i in 30:
			SwingPhysics.step(s, c, p, DT)
			if s.taut and after == 0.0:
				after = s.velocity.length()
		t.check(SwingPhysics.energy(s, p) <= e0 + 0.5, "redirect %.1f: no energy gain (%.1f → %.1f)" % [redirect, e0, SwingPhysics.energy(s, p)])
		t.note("redirect %.1f: speed just after the snap %.1f m/s" % [redirect, after])


func test_perfect_release_window(t) -> void:
	var p := SwingParams.new()
	var pl := Player.new()
	pl.params = p
	pl.s.attached = true
	pl.s.taut = true
	var cases := [[30.0, 25.0, true], [5.0, 25.0, false], [60.0, 25.0, false], [30.0, 6.0, false]]
	for cs in cases:
		var a := deg_to_rad(cs[0])
		pl.s.velocity = Vector3(0, sin(a), -cos(a)) * cs[1]
		t.check(pl.is_perfect_release() == cs[2], "%.0f° at %.0f m/s → perfect=%s" % [cs[0], cs[1], cs[2]])
	pl.free()


func test_save_survives_a_corrupt_file(t) -> void:
	# Saves are atomic with a backup: a truncated save.json (app killed
	# mid-write) recovers the last good progress instead of resetting it.
	var sd: Node = Engine.get_main_loop().root.get_node("/root/SaveData")
	var old_path: String = sd.path
	var p := "user://test_save_atomic.json"
	for f in [p, p + ".bak", p + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	sd.use_file(p)
	sd.data["coins"] = 1234
	sd.save()
	sd.data["coins"] = 5678
	sd.save()
	t.check(not FileAccess.file_exists(p + ".tmp"), "no temp file left behind")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("{\"coins\": 56")  # truncated mid-write
	f.close()
	sd.load_data()
	t.check(int(sd.data.get("coins", 0)) == 1234, "recovered from the backup (%s)" % str(sd.data.get("coins")))
	f = FileAccess.open(p, FileAccess.WRITE)
	f.close()  # empty file
	DirAccess.remove_absolute(p + ".bak")
	sd.load_data()
	t.check(sd.data.has("best_trial_times"), "an unreadable save with no backup falls back to safe defaults")
	for g in [p, p + ".bak", p + ".tmp"]:
		if FileAccess.file_exists(g):
			DirAccess.remove_absolute(g)
	sd.use_file(old_path)
