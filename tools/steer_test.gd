extends SceneTree
## How quickly a human can turn: holds the stick fully left (camera-relative,
## with the follow camera's yaw lag modelled) at speed, in free flight and on
## a web, and reports the time to turn 45° / 90° and the speed kept.
##   godot --headless -s res://tools/steer_test.gd
func _initialize() -> void:
	var p: SwingParams = load("res://config/swing_params.tres")
	for case in ["air 20 m/s", "air 30 m/s", "swing 25 m/s"]:
		var s := SwingPhysics.State.new()
		var spd := 30.0 if "30" in case else (25.0 if "25" in case else 20.0)
		s.position = Vector3(0, 300, 0)
		s.velocity = Vector3(0, 2, -spd)
		if case.begins_with("swing"):
			# Anchor up and ahead: the classic mid-swing.
			SwingPhysics.attach(s, s.position + Vector3(0, 28, -14), p)
		var c := SwingPhysics.Controls.new()
		c.turn_assist = true
		var cam_yaw := 0.0
		var t := 0.0
		var dt := 1.0 / 60.0
		var t45 := -1.0
		var t90 := -1.0
		while t < 4.0 and t90 < 0.0:
			# Camera follows the travel heading at its yaw_follow_rate (2.6/s).
			var vh := Vector3(s.velocity.x, 0, s.velocity.z)
			var heading := atan2(-vh.x, -vh.z)
			cam_yaw += wrapf(heading - cam_yaw, -PI, PI) * (1.0 - exp(-2.6 * dt))
			c.move = Basis(Vector3.UP, cam_yaw) * Vector3.LEFT
			if s.attached:
				c.reel = SwingPhysics.auto_tighten(s, p, 30.0)
			SwingPhysics.step(s, c, p, dt)
			t += dt
			var turned := absf(rad_to_deg(heading))
			if t45 < 0.0 and turned >= 45.0:
				t45 = t
			if turned >= 90.0:
				t90 = t
		print("%-14s 45° in %s   90° in %s   speed %.1f → %.1f m/s" % [case,
			("%.2f s" % t45) if t45 > 0 else "never", ("%.2f s" % t90) if t90 > 0 else ">4 s", spd,
			Vector3(s.velocity.x, 0, s.velocity.z).length()])
	quit()
