extends SceneTree
## Does the people-only detail (balconies, rooftop plant, trains: CityWorld
## HUMAN_LAYER) get in a human's way? Expert autopilot runs from rooftop
## spawns, once colliding with that layer (as a human player does) and once
## not; counts hits on it, knockouts, staggers and street touches.
##   godot --headless --fixed-fps 60 -s res://tools/human_layer_audit.gd -- [runs] [seconds]

func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var a := OS.get_cmdline_user_args()
	var runs := int(a[0]) if a.size() > 0 else 6
	var secs := float(a[1]) if a.size() > 1 else 30.0
	var w := CityWorld.new()
	root.add_child(w)
	var only := OS.get_environment("RUN")
	for layer_on in ([false] if only != "" else [false, true]):
		var rng := RandomNumberGenerator.new()
		rng.seed = 21
		var tot := {"hits": 0, "ko": 0, "stagger": 0, "street": 0, "dist": 0.0}
		for k in runs:
			var p := Player.new()
			p.params = load("res://config/swing_params.tres").duplicate()
			root.add_child(p)
			var spot := w.random_rooftop(rng)
			if only != "" and k != int(only):
				continue
			p.respawn(spot["position"])
			var bot := SwingBot.new(SwingBot.Style.EXPERT, Vector3.FORWARD)
			bot.goal_fn = w.bot_goal
			p.bot = bot
			p.set_collision_mask_value(6, layer_on)
			var ko := [0]
			var st := [0]
			var street := [0]
			p.knockout.connect(func(_a, _b): ko[0] += 1)
			p.staggered.connect(func(sp, n): if only != "": print("   STAGGER %.1f m/s n %s at %s" % [sp, n.snapped(Vector3.ONE * 0.1), p.global_position.snapped(Vector3.ONE * 0.1)]))
			if p.has_signal("staggered"):
				p.staggered.connect(func(_a = null, _b = null): st[0] += 1)
			p.landed.connect(func(_s, s2): if s2: street[0] += 1)
			var hits := 0
			var start := p.global_position
			var far := 0.0
			var last_hit := ""
			for i in int(60 * secs):
				await physics_frame
				p.set_collision_mask_value(6, layer_on)
				for c in p.get_slide_collision_count():
					var col := p.get_slide_collision(c).get_collider() as Node
					if col and (String(col.name).begins_with("ColHuman") or String(col.name).begins_with("PropsHuman")):
						hits += 1
						last_hit = "%s at %s" % [col.name, p.global_position.snapped(Vector3.ONE)]
				if only != "" and i % 20 == 0:
					var cols := []
					for c in p.get_slide_collision_count():
						var cc := p.get_slide_collision(c)
						cols.append("%s n%s" % [(cc.get_collider() as Node).name if cc.get_collider() else "?", cc.get_normal().snapped(Vector3.ONE * 0.1)])
					print("   t %.1f pos %s v %s floor %s line %s %s" % [i / 60.0, p.global_position.snapped(Vector3.ONE * 0.1), p.velocity.snapped(Vector3.ONE * 0.1), p.is_on_floor(), p.line_state, cols])
				far = maxf(far, Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length())
			print("  layer %s run %d: %.0f m, human-layer contact frames %d (%s), KO %d, stagger %d, street %d" % [
				layer_on, k, far, hits, last_hit, ko[0], st[0], street[0]])
			tot["hits"] += hits
			tot["ko"] += ko[0]
			tot["stagger"] += st[0]
			tot["street"] += street[0]
			tot["dist"] += far
			p.queue_free()
			await physics_frame
		print("HUMAN LAYER %s: %s" % [layer_on, tot])
	quit()
