extends SceneTree
## Micro-profile of per-tick gameplay CPU in the real city (headless, VPS).
##   godot --headless -s res://tools/cpu_breakdown.gd
func _initialize() -> void:
	_go.call_deferred()

func _go() -> void:
	var w := CityWorld.new()
	root.add_child(w)
	await physics_frame
	var p := Player.new()
	p.params = load("res://config/swing_params.tres").duplicate()
	root.add_child(p)
	p.global_position = w.spawn_point()
	await physics_frame
	var space := w.get_world_3d().direct_space_state
	var n := 600
	var t0 := Time.get_ticks_usec()
	for i in n:
		p.targeting.update(space, p.hand_position(), Vector3.FORWARD.rotated(Vector3.UP, i * 0.01), Vector3(0, 0, -20),
			p.params, false, [p.get_rid()])
	var t_target := (Time.get_ticks_usec() - t0) / float(n)
	var s := SwingPhysics.State.new()
	s.position = Vector3(0, 100, 0)
	SwingPhysics.attach(s, Vector3(0, 140, -20), p.params)
	var c := SwingPhysics.Controls.new()
	t0 = Time.get_ticks_usec()
	for i in n:
		SwingPhysics.step(s, c, p.params, 1.0 / 60.0)
	var t_model := (Time.get_ticks_usec() - t0) / float(n)
	t0 = Time.get_ticks_usec()
	for i in n:
		w.update_streaming(Vector3(600, 0, -200), 0)
	var t_stream := (Time.get_ticks_usec() - t0) / float(n)
	print("per call: targeting %.0f us (%d rays), swing model %.0f us, streaming scan %.0f us" % [
		t_target, GrappleTargeting.ELEVATIONS.size() * GrappleTargeting.YAWS.size(), t_model, t_stream])
	quit()
