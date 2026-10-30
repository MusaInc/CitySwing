extends SceneTree
## First-swing safety: on many Free Swing spawns, hold SWING from a standstill
## (the touch SWING button, no stick, aim along the spawn heading, like a new player) and count wall
## knockouts and street touches.
##   godot --headless --fixed-fps 60 -s res://tools/spawn_audit.gd -- [spawns] [seconds]

var _ko := 0


class Hold:
	extends RefCounted
	var aim := Vector3.FORWARD
	var human_steer := true
	func drive(_p, _dt) -> Dictionary:
		return {"move": Vector3.ZERO, "aim": aim, "grapple": false, "reel": 0.0, "jump": false}


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 24
	var secs := float(args[1]) if args.size() > 1 else 6.0
	var w := CityWorld.new()
	root.add_child(w)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var kos := 0
	var streets := 0
	var last := Vector3.INF
	for k in n:
		var spot: Dictionary = w.random_rooftop(rng, last)
		last = spot["position"]
		var p := Player.new()
		p.params = load("res://config/swing_params.tres").duplicate()
		root.add_child(p)
		var bot := Hold.new()
		bot.aim = CityWorld.spawn_aim(spot["yaw"])
		p.bot = bot
		p.respawn(spot["position"])
		_ko = 0
		var on_ko := func(sp, nrm):
			_ko += 1
			var a: Vector3 = p.s.anchor
			print("   KO %.0f m/s  wall n %s  anchor %s (%.0f m above the hit, %.0f m away)  attached %s  rope %.0f m" % [sp, nrm.snapped(Vector3.ONE * 0.1),
				a.snapped(Vector3.ONE), a.y - p.global_position.y, a.distance_to(p.global_position), p.s.attached, p.s.rope_length])
		p.knockout.connect(on_ko)
		var street := false
		var t := 0.0
		for f in 60:  # stand on the roof first
			await physics_frame
			if f > 3 and p.is_on_floor():
				break
		var fired := p.assist_fire(7)  # the touch SWING button, held for the whole run
		if OS.has_environment("SPAWN_DEBUG"): print("   real anchor ", p.line_target.snapped(Vector3.ONE), " from ", p.global_position.snapped(Vector3.ONE * 0.1))
		if not fired:
			print("  nothing to web from a standstill")
		while t < secs and _ko == 0:
			await physics_frame
			t += 1.0 / 60.0
			if OS.has_environment("SPAWN_TRACE") and int(t * 60) % 15 == 0: print("   t %.2f pos %s v %s line %s" % [t, p.global_position.snapped(Vector3.ONE * 0.1), p.s.velocity.snapped(Vector3.ONE * 0.1), p.line_state])
			street = street or (p.is_on_floor() and p.global_position.y < 3.0)
		var start: Vector3 = spot["position"]
		print("spawn %2d  %s  yaw %4.0f°  %s  %.1f s  travelled %.0f m" % [k, start.snapped(Vector3.ONE), rad_to_deg(spot["yaw"]),
			"KNOCKOUT" if _ko > 0 else ("street" if street else "ok"), t, p.global_position.distance_to(start)])
		kos += 1 if _ko > 0 else 0
		streets += 1 if street else 0
		p.queue_free()
		await physics_frame
	print("KNOCKOUTS %d/%d  street %d/%d" % [kos, n, streets, n])
	quit()
