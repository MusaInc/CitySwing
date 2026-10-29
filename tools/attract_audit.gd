extends SceneTree
## How good the title-screen autopilot looks: flies it from several rooftops
## and reports what spoils a showcase – time on the street, knockouts and
## stuns, wall bumps, flying close to facades, height, speed.
##   godot --headless --fixed-fps 60 -s res://tools/attract_audit.gd -- [expert|showcase] [seconds] [runs]
func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var kind := args[0] if args.size() > 0 else "showcase"
	var secs := float(args[1]) if args.size() > 1 else 40.0
	var runs := int(args[2]) if args.size() > 2 else 4
	var w := CityWorld.new()
	root.add_child(w)
	var p := Player.new()
	p.params = load("res://config/swing_params.tres").duplicate()
	root.add_child(p)
	var rng := RandomNumberGenerator.new()
	var totals := {}
	for run in runs:
		rng.seed = 100 + run
		var start: Vector3 = w.spawn_point() if run == 0 else w.random_rooftop(rng, Vector3.INF)["position"]
		p.respawn(start)
		var bot: SwingBot
		if kind == "expert":
			bot = SwingBot.new(SwingBot.Style.EXPERT, Vector3.FORWARD)
			bot.goal_fn = w.bot_goal
			# Same mid-air avenue starts as the showcase pilot, for a fair comparison.
			var e: Array = load("res://src/player/showcase_pilot.gd").new(w).entry(rng)
			p.respawn(e[0])
			p.s.velocity = e[1]
		else:
			bot = load("res://src/player/showcase_pilot.gd").new(w)
			var e: Array = bot.entry(rng)
			p.respawn(e[0])
			p.s.velocity = e[1]
		p.set_meta("bot", bot)  # Callables don't keep their target alive
		p.bot = bot
		var m := {"ground": 0.0, "ko": 0, "stun": 0, "bumps": 0, "hard": 0, "slow": 0.0, "close": 0.0, "height": 0.0, "speed": 0.0,
			"swings": 0, "dist": 0.0}
		var c_ko := func(_s, _n): m["ko"] += 1
		var c_stun := func(_s): m["stun"] += 1
		var c_bump := func(s, n):
			if s > 15.0:
				m["hard"] += 1
			if s > 4.0:
				m["bumps"] += 1
				if OS.has_environment("AUDIT_TRACE"):
					print("    bump %.1f m/s at %s n=%s line=%d floor=%s lat=%s" % [s, p.global_position.snapped(Vector3.ONE),
						(n as Vector3).snapped(Vector3.ONE * 0.1), p.line_state, p.is_on_floor(),
						str(snappedf(bot._lateral(p.global_position), 0.1)) if bot.has_method("_lateral") else "-"])
		var c_att := func(_a): m["swings"] += 1
		p.knockout.connect(c_ko)
		p.stun_started.connect(c_stun)
		p.bumped.connect(c_bump)
		p.attached.connect(c_att)
		var space := p.get_world_3d().direct_space_state
		var rq := PhysicsRayQueryParameters3D.new()
		rq.collision_mask = Player.BUILDINGS_MASK
		rq.exclude = [p.get_rid()]
		var frames := int(secs * 60)
		var last := p.global_position
		for i in frames:
			await physics_frame
			var pos := p.global_position
			m["dist"] += Vector2(pos.x - last.x, pos.z - last.z).length()
			last = pos
			if p.is_on_floor() and pos.y < 1.0:
				m["ground"] += 1.0 / 60.0
			m["height"] += pos.y / frames
			if not p.is_on_floor() and p.s.velocity.length() < 5.0:
				m["slow"] += 1.0 / 60.0
				if OS.has_environment("AUDIT_TRACE") and i % 30 == 0:
					print("    slow at %s v=%s line=%d wall=%s wraps=%d anchor=%s" % [pos.snapped(Vector3.ONE * 0.1),
						p.s.velocity.snapped(Vector3.ONE * 0.1), p.line_state, p.is_on_wall(), p.wraps.size(),
						p.s.anchor.snapped(Vector3.ONE) if p.s.attached else "-"])
			m["speed"] += p.s.velocity.length() / frames
			if i % 6 == 0:
				var near := INF
				for a in 8:
					var d := Vector3(cos(a * TAU / 8.0), 0.0, sin(a * TAU / 8.0))
					rq.from = pos
					rq.to = pos + d * 12.0
					var hit := space.intersect_ray(rq)
					if not hit.is_empty():
						near = minf(near, pos.distance_to(hit.position))
				if near < 4.0:
					m["close"] += 0.1
		for s in [c_ko, c_stun, c_bump, c_att]:
			for sig in [p.knockout, p.stun_started, p.bumped, p.attached]:
				if sig.is_connected(s):
					sig.disconnect(s)
		print("%-8s run %d: street %4.1f s  KO %d  stun %d  bumps %2d (hard %d)  slow %4.1f s  near-wall %4.1f s  height %4.0f m  speed %4.1f m/s  swings %2d  covered %4.0f m" %
			[kind, run, m["ground"], m["ko"], m["stun"], m["bumps"], m["hard"], m["slow"], m["close"], m["height"], m["speed"], m["swings"], m["dist"]])
		for k in m:
			totals[k] = totals.get(k, 0.0) + float(m[k]) / runs
	print("%-8s MEAN : street %4.1f s  KO %.2f  stun %.2f  bumps %4.1f (hard %.1f)  slow %4.1f s  near-wall %4.1f s  height %4.0f m  speed %4.1f m/s  swings %4.1f  covered %4.0f m" %
		[kind, totals["ground"], totals["ko"], totals["stun"], totals["bumps"], totals["hard"], totals["slow"], totals["close"], totals["height"], totals["speed"],
		totals["swings"], totals["dist"]])
	quit()
