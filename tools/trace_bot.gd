extends SceneTree
## Debug trace of the autopilot on the prototype range:
##   godot --headless --fixed-fps 60 -s res://tools/trace_bot.gd -- expert 30
func _initialize() -> void:
	_go.call_deferred()

func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var style := SwingBot.Style.NOVICE if args.size() > 0 and args[0] == "novice" else SwingBot.Style.EXPERT
	var secs := float(args[1]) if args.size() > 1 else 20.0
	var w := PrototypeWorld.new()
	root.add_child(w)
	var p := Player.new()
	p.params = load("res://config/swing_params.tres").duplicate()
	root.add_child(p)
	p.global_position = w.spawn_point()
	p.bot = SwingBot.new(style, Vector3.FORWARD)
	p.bot.goal_fn = w.bot_goal
	p.attached.connect(func(a): print("   ATTACH ", a.snapped(Vector3.ONE * 0.1), " L=%.1f" % p.s.rope_length))
	p.released.connect(func(v): print("   RELEASE v=", v.snapped(Vector3.ONE * 0.1)))
	p.landed.connect(func(s, st): print("   LAND %.1f street=%s" % [s, st]))
	p.grapple_missed.connect(func(): print("   MISS"))
	for i in int(secs * 60):
		await physics_frame
		if i % 15 == 0:
			print("t=%5.2f pos=%s v=%s line=%d tgt=%s" % [i / 60.0, p.global_position.snapped(Vector3.ONE * 0.1),
				p.s.velocity.snapped(Vector3.ONE * 0.1), p.line_state, p.targeting.has_target])
	quit()
