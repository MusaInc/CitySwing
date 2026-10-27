extends SceneTree
## Swing-feel numbers from autopilot runs through the city, for comparing
## tuning changes (judge over several starts – swinging is chaotic).
##   godot --headless --fixed-fps 60 -s res://tools/feel_report.gd -- [runs] [seconds] [expert|novice]
## Reports per run and the mean: average speed while airborne, share of time
## in the air, perfect releases, longest chain, street touches, hard crashes.

func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := int(args[0]) if args.size() > 0 else 6
	var secs := float(args[1]) if args.size() > 1 else 40.0
	var style := SwingBot.Style.NOVICE if args.size() > 2 and args[2] == "novice" else SwingBot.Style.EXPERT
	var w := CityWorld.new()
	root.add_child(w)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var tot := {"air_speed": 0.0, "air": 0.0, "perfect": 0.0, "releases": 0.0, "chain": 0.0, "street": 0.0, "stun": 0.0, "far": 0.0}
	for k in runs:
		var p := Player.new()
		p.params = load("res://config/swing_params.tres").duplicate()
		root.add_child(p)
		var spot := w.random_rooftop(rng) if k > 0 else {"position": w.spawn_point()}
		p.respawn(spot["position"])
		var bot := SwingBot.new(style, Vector3.FORWARD, 7 + k)
		bot.goal_fn = w.bot_goal
		p.bot = bot
		var c := {"street": 0, "stun": 0}
		p.landed.connect(func(_s, st): if st: c["street"] += 1)
		p.stun_started.connect(func(sp): c["stun"] += 1; print("   crash %.0f m/s %s" % [sp, "floor" if p.is_on_floor() else "wall"]))
		var start := p.global_position
		var far := 0.0
		var air_frames := 0
		var air_speed := 0.0
		var frames := int(secs * 60)
		for i in frames:
			await physics_frame
			if not p.is_on_floor():
				air_frames += 1
				air_speed += p.speed()
			far = maxf(far, Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length())
		var r := {"air_speed": air_speed / maxf(air_frames, 1) * 3.6, "air": 100.0 * air_frames / frames,
			"perfect": p.perfects, "releases": p.swings, "chain": p.best_chain, "street": c["street"],
			"stun": c["stun"], "far": far}
		print("run %d: air speed %.0f km/h, airborne %.0f%%, perfect %d/%d releases, best chain %d, street %d, crashes %d, %.0f m" % [
			k, r["air_speed"], r["air"], r["perfect"], r["releases"], r["chain"], r["street"], r["stun"], r["far"]])
		for key in tot:
			tot[key] += r[key]
		p.queue_free()
		await process_frame
	for key in tot:
		tot[key] /= runs
	print("MEAN: air speed %.0f km/h, airborne %.0f%%, perfect %.1f/%.1f, best chain %.1f, street %.1f, crashes %.1f, %.0f m" % [
		tot["air_speed"], tot["air"], tot["perfect"], tot["releases"], tot["chain"], tot["street"], tot["stun"], tot["far"]])
	quit()
