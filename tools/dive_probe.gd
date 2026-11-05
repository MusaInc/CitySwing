extends SceneTree
## Dive probe: from rooftop spawns, hold the stick forward (no web), run off
## the edge and fall. Logs camera yaw, body facing and travel heading, and
## flags any >90° turn away from the run-off direction.
##   godot --headless --fixed-fps 60 -s res://tools/dive_probe.gd -- [--runs=N]
var main: Node3D


func _initialize() -> void:
	go.call_deferred()


func go() -> void:
	var runs := 8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs = int(a.trim_prefix("--runs="))
	root.get_node("SaveData").use_file("user://dive_probe_save.json")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 12:
		await process_frame
	var p: Player = main.player
	p.bot = null
	main.start_mode("free", "")
	for i in 30:
		await physics_frame
	var bad := 0
	for r in runs:
		main.spawn_on_random_rooftop()
		p.bot = null
		for i in 10:
			await physics_frame
		Input.action_press("move_forward")
		var t := 0.0
		var off_yaw := INF
		var worst_cam := 0.0
		var worst_body := 0.0
		var log := []
		var left_roof := false
		var right0 := Vector3.ZERO
		var worst_twist := 0.0
		while t < 9.0:
			await physics_frame
			await process_frame
			t += 1.0 / 60.0
			var v := p.s.velocity
			var air := not p.is_on_floor()
			var cy: float = main.camera.view_yaw()
			var fac: Vector3 = main.rig._facing
			var by := atan2(-fac.x, -fac.z)
			if air and not left_roof and p.height_above_ground() > 6.0:
				left_roof = true
				off_yaw = cy
			var rb: Basis = main.rig._body_basis
			if left_roof and right0 == Vector3.ZERO:
				right0 = rb.x
			if left_roof:
				worst_twist = maxf(worst_twist, right0.angle_to(rb.x))
				var dc := absf(wrapf(cy - off_yaw, -PI, PI))
				var db := absf(wrapf(by - off_yaw, -PI, PI))
				worst_cam = maxf(worst_cam, dc)
				worst_body = maxf(worst_body, db)
				if int(t * 60.0) % 6 == 0:
					log.append("  t=%.1f h=%.0f v=(%.1f,%.1f,%.1f) cam=%+.0f body=%+.0f wallhold=%.2f wallrun=%s floor=%s" % [t, p.height_above_ground(), v.x, v.y, v.z,
						rad_to_deg(wrapf(cy - off_yaw, -PI, PI)), rad_to_deg(wrapf(by - off_yaw, -PI, PI)), p.wall_hold, p.wall_run, not air])
				if not air and t > 1.0 and p.height_above_ground() < 2.0:
					break
		Input.action_release("move_forward")
		var flag := worst_cam > deg_to_rad(90.0) or worst_body > deg_to_rad(90.0)
		bad += int(flag)
		print("DIVE run %d: left roof=%s  worst cam turn %.0f°  worst body turn %.0f°  body twist %.0f° %s" % [r, left_roof, rad_to_deg(worst_cam), rad_to_deg(worst_body), rad_to_deg(worst_twist), "<-- BACKWARDS" if flag else ""])
		if flag or OS.get_environment("DIVE_LOG") != "":
			for l in log:
				print(l)
	print("DIVE backwards %d/%d" % [bad, runs])
	main.queue_free()
	await process_frame
	quit()
