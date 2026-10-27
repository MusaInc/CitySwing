extends SceneTree
## Debug trace of the autopilot.
##   godot --headless --fixed-fps 60 -s res://tools/trace_bot.gd -- <expert|novice> <seconds> [course id]
## Without a course id it runs the prototype range.
func _initialize() -> void:
	_go.call_deferred()

func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var style := SwingBot.Style.NOVICE if args.size() > 0 and args[0] == "novice" else SwingBot.Style.EXPERT
	var secs := float(args[1]) if args.size() > 1 else 20.0
	var course_id := args[2] if args.size() > 2 else ""
	var p := Player.new()
	p.params = load("res://config/swing_params.tres").duplicate()
	var bot := SwingBot.new(style, Vector3.FORWARD)
	var goal := func(_pl): return Vector3.ZERO
	if course_id == "":
		var w := PrototypeWorld.new()
		root.add_child(w)
		root.add_child(p)
		p.global_position = w.spawn_point()
		bot.goal_fn = w.bot_goal
		goal = w.bot_goal
	else:
		var w := CityWorld.new()
		root.add_child(w)
		root.add_child(p)
		# Loaded by path: mode scripts use autoloads, which -s scripts cannot see at compile time.
		var mode = load("res://src/modes/time_trial.gd").new()
		root.add_child(mode)
		mode.setup(p, Hud.new(), null, w)
		mode.setup_course(CourseBuilder.load_course(course_id))
		mode.start()
		var follower := RouteFollower.new(CourseBuilder.route(course_id, w.layout)["waypoints"])
		p.set_meta("follower", follower)  # keep it alive: Callables don't
		bot.goal_fn = follower.goal
		goal = follower.goal
		print("start: ", mode.course["start"])
		for g in mode.course["gates"]:
			print("gate pos=%s dir=%s half_w=%.1f half_h=%.1f" % [g["pos"].snapped(Vector3.ONE), g["dir"].snapped(Vector3.ONE * 0.01), g["half_w"], g["half_h"]])
		var prev := [p.global_position]
		p.get_tree().physics_frame.connect(func():
			if mode.next >= mode.course["gates"].size():
				return
			var g: Dictionary = mode.course["gates"][mode.next]
			var a: Vector3 = prev[0]
			var b := p.global_position
			prev[0] = b
			var da: float = (a - g["pos"]).dot(g["dir"])
			var db: float = (b - g["pos"]).dot(g["dir"])
			if signf(da) != signf(db):
				var x: Vector3 = b - g["pos"]
				var side := Vector3(-g["dir"].z, 0, g["dir"].x)
				print("   CROSS gate %d %s lateral=%.1f/%.1f vertical=%.1f/%.1f" % [mode.next, "fwd" if db > 0 else "back", x.dot(side), g["half_w"], x.y, g["half_h"]]))
	p.bot = bot
	p.attached.connect(func(a): print("   ATTACH ", a.snapped(Vector3.ONE * 0.1), " L=%.1f" % p.s.rope_length))
	p.released.connect(func(v): print("   RELEASE v=", v.snapped(Vector3.ONE * 0.1)))
	p.landed.connect(func(s, st): print("   LAND %.1f street=%s" % [s, st]))
	p.grapple_missed.connect(func(): print("   MISS"))
	p.rope_wrapped.connect(func(c): print("   WRAP at ", c.snapped(Vector3.ONE * 0.1), " L=%.1f" % p.s.rope_length))
	p.stun_started.connect(func(spd): print("   STUN %.1f" % spd))
	for i in int(secs * 60):
		await physics_frame
		if i % 30 == 0:
			var g: Vector3 = goal.call(p)
			print("t=%5.2f pos=%s v=%s line=%d tgt=%s goal=%s d=%.0f" % [i / 60.0, p.global_position.snapped(Vector3.ONE * 0.1),
				p.s.velocity.snapped(Vector3.ONE * 0.1), p.line_state, p.targeting.has_target, g.snapped(Vector3.ONE), p.global_position.distance_to(g)])
	quit()
