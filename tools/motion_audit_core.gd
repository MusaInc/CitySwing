extends Node
## Scenario driver + measurements for tools/motion_audit.gd and
## tests/test_motion_quality.gd. Runs on a small stage (ground, a tower, a
## low roof, kerb steps); each scenario is a timeline of inputs/events.

const SCENARIOS := ["idle", "accelerate", "reverse", "zigzag", "walk_stop", "run_jump", "drop", "roll_land",
	"steps", "swing_slow", "swing_fast", "release_refire", "rapid_webs", "swing_to_land", "wall_run",
	"knockout", "crash_recover", "tricks", "ledge_dive", "run_into_wall", "swing_graze"]
const TOWER := Vector3(0, 40, -40)

var player: Player
var rig: CharacterRig
var drv := Drive.new()


class Drive:
	extends RefCounted
	var move := Vector3.ZERO
	var jump := false
	var grapple := false
	## AUDIT_HUMAN=1 audits the player's movement (sprint speed, turn assist).
	var human_steer := OS.get_environment("AUDIT_HUMAN") == "1"
	func drive(_p, _dt) -> Dictionary:
		var j := jump
		jump = false
		return {"move": move, "aim": Vector3.FORWARD, "grapple": grapple, "reel": 0.0, "jump": j}


func build_stage() -> void:
	var stage := Node3D.new()
	add_child(stage)
	PrototypeWorld.add_box(stage, Vector3(0, -0.5, 0), Vector3(800, 1, 800), Color.GRAY, false, true)
	PrototypeWorld.add_box(stage, TOWER, Vector3(16, 80, 16), Color.WHITE)
	PrototypeWorld.add_box(stage, Vector3(40, 10, 30), Vector3(30, 20, 30), Color.WHITE)
	PrototypeWorld.add_box(stage, Vector3(-120, 60, -120), Vector3(20, 120, 20), Color.WHITE)
	PrototypeWorld.add_box(stage, Vector3(120, 60, -160), Vector3(20, 120, 20), Color.WHITE)
	for i in 4:
		var h := 0.15 * (i + 1)
		PrototypeWorld.add_box(stage, Vector3(-10 + i * 1.2, h * 0.5, 60), Vector3(1.2, h, 4), Color.GRAY, false)
		PrototypeWorld.add_box(stage, Vector3(-10 + (7 - i) * 1.2, h * 0.5, 60), Vector3(1.2, h, 4), Color.GRAY, false)
	player = Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	add_child(player)
	player.bot = drv
	rig = CharacterRig.new()
	player.add_child(rig)
	rig.set_player(player)
	await get_tree().physics_frame


func _reset(at: Vector3, vel := Vector3.ZERO) -> void:
	drv.move = Vector3.ZERO
	drv.jump = false
	drv.grapple = false
	player.respawn(at)
	player.s.velocity = vel
	rig._prev_vel = vel
	rig.set_facing(Vector3.FORWARD if vel.length() < 0.1 else Vector3(vel.x, 0, vel.z).normalized())


## Scenario timelines: [start position, start velocity, seconds, {time: Callable}]
func _plan(name: String) -> Array:
	var p := player
	match name:
		"idle":
			return [Vector3(0, 1, 20), Vector3.ZERO, 3.0, {}]
		"accelerate":  # standstill → walk → run → sprint
			return [Vector3(-60, 1, 20), Vector3.ZERO, 4.0, {0.3: func(): drv.move = Vector3.RIGHT * 0.25,
				1.3: func(): drv.move = Vector3.RIGHT * 0.6, 2.2: func(): drv.move = Vector3.RIGHT}]
		"reverse":  # full sprint, stick snapped the other way
			return [Vector3(-40, 1, 20), Vector3.ZERO, 4.5, {0.0: func(): drv.move = Vector3.RIGHT,
				2.0: func(): drv.move = Vector3.LEFT}]
		"zigzag":  # sharp 90° cuts at speed
			return [Vector3(-40, 1, 0), Vector3.ZERO, 5.0, {0.0: func(): drv.move = Vector3.RIGHT,
				1.8: func(): drv.move = Vector3.FORWARD, 2.6: func(): drv.move = Vector3.RIGHT,
				3.4: func(): drv.move = Vector3.BACK, 4.2: func(): drv.move = Vector3.RIGHT}]
		"walk_stop":
			return [Vector3(-40, 1, 20), Vector3.ZERO, 3.5, {0.0: func(): drv.move = Vector3.RIGHT * 0.3,
				2.0: func(): drv.move = Vector3.ZERO}]
		"run_jump":  # running jump, land, run on
			return [Vector3(-40, 1, 20), Vector3.ZERO, 4.0, {0.0: func(): drv.move = Vector3.RIGHT,
				1.2: func(): drv.jump = true}]
		"drop":  # ~14 m straight drop: hard landing
			return [Vector3(-20, 14, 20), Vector3(2, 0, 0), 3.4, {}]
		"roll_land":  # fast running landing
			return [Vector3(-40, 16, 20), Vector3(16, 0, 0), 3.5, {0.0: func(): drv.move = Vector3.RIGHT}]
		"steps":
			return [Vector3(-14, 1, 60), Vector3.ZERO, 5.0, {0.0: func(): drv.move = Vector3.RIGHT * 0.5}]
		"swing_slow":
			return [Vector3(-25, 48, -20), Vector3(8, 0, 0), 3.5, {0.0: func(): p.fire_at(Vector3(0, 72, -32), 1)}]
		"swing_fast":
			return [Vector3(-40, 50, -20), Vector3(34, -6, 0), 3.0, {0.0: func(): p.fire_at(Vector3(0, 74, -32), 1)}]
		"release_refire":  # swing, let go, short flight, next web, let go again
			return [Vector3(-25, 48, -20), Vector3(14, 0, 0), 5.0, {0.0: func(): p.fire_at(Vector3(0, 72, -32), 1),
				1.6: func(): p.release_web(), 2.3: func(): p.fire_at(Vector3(110, 100, -150), 2),
				3.8: func(): p.release_web()}]
		"rapid_webs":  # webs swapped every 0.3 s
			return [Vector3(-60, 60, -60), Vector3(20, 0, 0), 3.0, {0.0: func(): p.fire_at(TOWER + Vector3(-8, 20, 8), 1),
				0.35: func(): p.fire_at(Vector3(-120, 100, -110), 2), 0.7: func(): p.fire_at(TOWER + Vector3(-8, 30, 8), 3),
				1.05: func(): p.release_web(), 1.3: func(): p.fire_at(Vector3(110, 100, -150), 4),
				1.65: func(): p.fire_at(TOWER + Vector3(8, 30, 8), 5), 2.2: func(): p.release_web()}]
		"swing_to_land":  # low swing released into a running landing
			return [Vector3(-30, 14, -20), Vector3(14, 0, 0), 4.0, {0.0: func(): p.fire_at(Vector3(-8, 30, -32), 1),
				0.9: func(): p.release_web(), 0.95: func(): drv.move = Vector3.RIGHT}]
		"wall_run":
			return [Vector3(0, 30, -14), Vector3(0, 0, -16), 3.0, {}]
		"knockout":
			return [Vector3(0, 30, -20), Vector3(0, 1, -35), 4.5, {}]
		"crash_recover":  # crash on the ground at speed, get up, run on
			return [Vector3(0, 3, -10), Vector3(0, 0, -30), 5.0, {2.5: func(): drv.move = Vector3.RIGHT}]
		"ledge_dive":  # sprint off a 120 m tower: swan dive, pull out, land
			return [Vector3(-118, 121, -120), Vector3.ZERO, 7.5, {0.0: func(): drv.move = Vector3.RIGHT}]
		"run_into_wall":  # sprint straight into the tower's foot
			return [Vector3(0, 1, -10), Vector3.ZERO, 3.0, {0.0: func(): drv.move = Vector3.FORWARD}]
		"swing_graze":  # a swing that scrapes along a facade
			return [Vector3(-14, 40, -24), Vector3(10, 0, -6), 3.0, {0.0: func(): p.fire_at(Vector3(-2, 70, -32), 1)}]
		"tricks":
			return [Vector3(-20, 90, 200), Vector3(9, 9, 0), 3.0, {0.1: func(): rig.start_trick("corkscrew"),
				1.4: func(): rig.start_trick("aerial")}]
	push_error("unknown scenario " + name)
	return []


## Runs one scenario and returns its measurements.
func run_scenario(name: String) -> Dictionary:
	var plan := _plan(name)
	if plan.is_empty():
		return {}
	_reset(plan[0], plan[1])
	await get_tree().physics_frame
	var events: Dictionary = (plan[3] as Dictionary).duplicate()
	var secs: float = plan[2]
	var m := Meter.new(rig, player, get_viewport().get_world_3d().direct_space_state)
	m.trace = OS.get_environment("AUDIT_TRACE") == name
	var t := 0.0
	while t < secs:
		for at in events.keys():
			if t >= at:
				(events[at] as Callable).call()
				events.erase(at)
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		m.sample(t, dt)
	return m.result()


static func format(name: String, r: Dictionary) -> String:
	if r.has("rag_snap"):
		print("%-14s ragdoll fastest bone %.0f°/s %s" % [name, r["rag_snap"], r["rag_snap_at"]])
	var s := "%-14s snap %4.0f %-22s pops %3d body %3.0f | joints %2d %-30s | slide avg %.2f max %5.2f | sink %.3f float %.3f | hand %.3f" % [
		name, r["snap"], r["snap_at"], r["pops"], r["body_rate"], r["joint_bad"], r["joint_at"],
		r["slide_avg"], r["slide"], r["sink"], r["float"], r["hand"]]
	return s


class Meter:
	extends RefCounted
	var rig: CharacterRig
	var player: Player
	var space: PhysicsDirectSpaceState3D
	var prev := {}       # bone -> local quat
	var prev_w := {}     # bone -> angular velocity (rad/s, parent space)
	var prev_g := {}     # bone -> world rotation (ragdoll frames)
	var prev_body := Basis()
	var have_prev := false
	var prev_ankle := {}
	var r := {"snap": 0.0, "snap_at": "", "pop": 0.0, "pop_at": "", "body_rate": 0.0, "joint_bad": 0,
		"joint_at": "", "joint_worst": 0.0, "slide": 0.0, "slide_avg": 0.0, "pops": 0, "body_at": "", "sink": 0.0, "float": 0.0, "hand": 0.0, "frames": 0}
	var _slide_d := 0.0
	var _slide_t := 0.0
	var _was_slow := false
	var _skip := 6  # frames to ignore after the respawn teleport
	var trace := false

	func _init(rg: CharacterRig, pl: Player, sp: PhysicsDirectSpaceState3D) -> void:
		rig = rg
		player = pl
		space = sp

	func _state() -> String:
		if rig.ragdolling:
			return "ragdoll"
		if rig._trick != "":
			return "trick"
		if rig._roll_time > 0.0:
			return "roll"
		if rig._getup_t > 0.0:
			return "getup"
		if rig._hard_t > 0.0:
			return "hard"
		if player.line_state == Player.Line.ATTACHED:
			return "rope"
		if player.line_state == Player.Line.FLYING:
			return "fire"
		if player.is_on_floor():
			return "ground"
		return "air"

	func _ground_y(at: Vector3) -> float:
		var rq := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 3.0, player.collision_mask)
		rq.exclude = [player.get_rid()]
		var hit := space.intersect_ray(rq)
		return -INF if hit.is_empty() else (hit.position as Vector3).y

	func sample(t: float, dt: float) -> void:
		r["frames"] += 1
		var st := _state()
		var tag := "%s@%.2f" % [st, t]
		var free_pose := st not in ["ragdoll", "trick", "roll"]
		# --- snap / pop (local bone rotation rate and its change)
		for b in CharacterRig.BONES:
			var qn: Quaternion = (rig.bones[b] as Node3D).quaternion
			if have_prev and _skip <= 0:
				var d: Quaternion = qn * (prev[b] as Quaternion).inverse()
				if d.w < 0.0:
					d = -d
				var ang := d.get_angle()
				var w := (d.get_axis() * ang / dt) if ang > 1e-5 else Vector3.ZERO
				if st == "ragdoll":
					var gq := (rig.bones[b] as Node3D).global_basis.get_rotation_quaternion()
					if prev_g.has(b):
						var gd: Quaternion = gq * (prev_g[b] as Quaternion).inverse()
						if gd.w < 0.0:
							gd = -gd
						var gr := rad_to_deg(gd.get_angle() / dt)
						if trace and gr > 3000.0:
							var gb := (rig.bones[b] as Node3D).global_basis
							print("  ragflip %s %.0f t %.2f axis-turn %.1f° det %.2f" % [b, gr, t,
								rad_to_deg(gb.y.angle_to(Basis(prev_g[b] as Quaternion).y)), gb.determinant()])
						if gr > r.get("rag_snap", 0.0):
							r["rag_snap"] = gr
							r["rag_snap_at"] = "%s %s (world)" % [b, tag]
					prev_g[b] = gq
				if free_pose and rad_to_deg(w.length()) > r["snap"]:
					r["snap"] = rad_to_deg(w.length())
					r["snap_at"] = "%s %s" % [b, tag]
					if trace:
						print("  snap %s %.0f dt %.4f prev %s now %s" % [b, rad_to_deg(w.length()), dt, prev[b], qn])
				if prev_w.has(b) and free_pose:
					var acc := rad_to_deg(((w - (prev_w[b] as Vector3)) / dt).length())
					if acc > 90000.0:  # 1500°/s change of rate in one 60 fps frame
						r["pops"] += 1
						if trace:
							print("  pop %s %.0f" % [b, acc])
					if acc > r["pop"]:
						r["pop"] = acc
						r["pop_at"] = "%s %s" % [b, tag]
				prev_w[b] = w
			prev[b] = qn
		var bb := rig.global_basis.orthonormalized()
		if have_prev and _skip <= 0 and free_pose:
			var d := (bb * prev_body.inverse()).get_rotation_quaternion()
			if rad_to_deg(d.get_angle() / dt) > r["body_rate"]:
				r["body_rate"] = rad_to_deg(d.get_angle() / dt)
				r["body_at"] = tag
		prev_body = bb
		have_prev = true
		_skip -= 1
		if st == "ragdoll" or t < 0.2:  # (first frames: the respawn teleport settling)
			prev_ankle.clear()
			return
		# --- joints
		var bad := []
		for sd in ["l", "r"]:
			var shin := _hinge("shin_" + sd)
			if shin.x > deg_to_rad(4.0):
				bad.append(["knee_hyper_" + sd, shin.x])
			if shin.x < -deg_to_rad(155.0):
				bad.append(["knee_over_" + sd, -shin.x - deg_to_rad(155.0)])
			if shin.y > deg_to_rad(12.0):
				bad.append(["knee_twist_" + sd, shin.y])
			var fore := _hinge("forearm_" + sd)
			if fore.x < -deg_to_rad(4.0):
				bad.append(["elbow_hyper_" + sd, -fore.x])
			if fore.x > deg_to_rad(155.0):
				bad.append(["elbow_over_" + sd, fore.x - deg_to_rad(155.0)])
			if fore.y > deg_to_rad(15.0):
				bad.append(["elbow_twist_" + sd, fore.y])
			# Thigh: bone direction in the hips frame (-Y rest, -Z forward).
			var td: Vector3 = (rig.bones["thigh_" + sd] as Node3D).quaternion * Vector3.DOWN
			var back := atan2(td.z, -td.y)  # + = behind the body
			if back > deg_to_rad(50.0) and td.y < 0.0:
				bad.append(["hip_hyper_" + sd, back - deg_to_rad(50.0)])
			var abd := asin(clampf(absf(td.x), 0.0, 1.0))
			if abd > deg_to_rad(75.0):
				bad.append(["hip_abd_" + sd, abd - deg_to_rad(75.0)])
			var foot := _hinge("foot_" + sd)
			if absf(foot.x) > deg_to_rad(75.0):
				bad.append(["ankle_" + sd, absf(foot.x) - deg_to_rad(75.0)])
		var neck_q: Quaternion = (rig.bones["neck"] as Node3D).quaternion * (rig.bones["head"] as Node3D).quaternion
		if neck_q.get_angle() > deg_to_rad(80.0):
			bad.append(["neck", neck_q.get_angle() - deg_to_rad(80.0)])
		var torso_q: Quaternion = (rig.bones["spine"] as Node3D).quaternion * (rig.bones["chest"] as Node3D).quaternion
		if torso_q.get_angle() > deg_to_rad(75.0):
			bad.append(["torso", torso_q.get_angle() - deg_to_rad(75.0)])
		if not free_pose:
			bad = bad.filter(func(e): return not String(e[0]).begins_with("hip_abd"))
		for e in bad:
			r["joint_bad"] += 1
			if e[1] > r["joint_worst"]:
				r["joint_worst"] = e[1]
				r["joint_at"] = "%s +%.0f° %s" % [e[0], rad_to_deg(e[1]), tag]
		# --- feet
		var lowest := INF
		for sd in ["l", "r"]:
			var a := (rig.bones["foot_" + sd] as Node3D).global_position
			var gy := _ground_y(a)
			if gy > -INF:
				var h := a.y - gy - CharacterRig.ANKLE_H
				lowest = minf(lowest, h)
				if rig._plant.has(sd) and rig._toe[sd] < 0.05 and player.is_on_floor():
					r["plant_float"] = maxf(r.get("plant_float", 0.0), h)
					if trace and h > 0.04:
						print("  hover %s %.3f off %s settle %s heel %.2f" % [sd, h, (rig._foot_off[sd] as Vector3).snapped(Vector3.ONE * 0.01),
							rig._settle.has(sd), rig._heel[sd]])
				if st != "roll":
					r["sink"] = maxf(r["sink"], -h)
					if trace and -h > 0.03:
						print("  sink %s %.3f planted %s stance %.2f swing %.2f settle %s off %s" % [sd, -h, rig._plant.has(sd),
							rig._stance_w[sd], rig._swing_w[sd], rig._settle.has(sd), (rig._foot_off[sd] as Vector3).snapped(Vector3.ONE * 0.01)])
			if rig._plant.has(sd) and prev_ankle.has(sd):
				var mv: Vector3 = a - prev_ankle[sd]
				r["slide"] = maxf(r["slide"], Vector2(mv.x, mv.z).length() / dt)
				_slide_d += Vector2(mv.x, mv.z).length()
				_slide_t += dt
				if trace and Vector2(mv.x, mv.z).length() / dt > 0.5:
					print("  slide %s %.2f m/s off %s w %.2f toe %.2f" % [sd, Vector2(mv.x, mv.z).length() / dt,
						(rig._foot_off[sd] as Vector3).snapped(Vector3.ONE * 0.01), rig._stance_w[sd], rig._toe[sd]])
			if rig._plant.has(sd):
				prev_ankle[sd] = a
			else:
				prev_ankle.erase(sd)
		# Standing feet: scored from the second slow sample on – a dead stop
		# against a wall can catch the stride with both feet in the air, and
		# no foot can be planted in zero frames.
		var slow := st == "ground" and player.speed() < 1.5
		if slow and _was_slow and lowest < INF and rig._loco > 0.99:
			r["float"] = maxf(r["float"], lowest)
		_was_slow = slow
		if trace and player.line_state == Player.Line.ATTACHED:
			var rd := (player.s.anchor - player.global_position).normalized()
			print("%s L %.2f tension %.0f taut %s body-rope %.0f° v %s" % [tag, rig._load, player.s.tension, player.s.taut,
				rad_to_deg(rig.global_basis.y.angle_to(rd)), player.s.velocity.snapped(Vector3.ONE * 0.1)])
		elif trace:
			print("%s lowest %.3f plant %s loco %.2f squash %.2f hard %.2f v %s" % [tag, lowest, rig._plant.keys(),
				rig._loco, rig._land_squash, rig._hard_t, player.s.velocity.snapped(Vector3.ONE * 0.1)])
		var ds := rig.debug_state()
		if st == "rope" and t > 0.3:
			r["hand"] = maxf(r["hand"], ds["hand_line"])

	## Signed bend about the joint's hinge (local X) and the off-hinge angle.
	func _hinge(b: String) -> Vector2:
		var q: Quaternion = (rig.bones[b] as Node3D).quaternion
		var ang := q.get_angle()
		if ang < 1e-5:
			return Vector2.ZERO
		var ax := q.get_axis()
		if ang > PI:
			ang = TAU - ang
			ax = -ax
		return Vector2(ang * ax.x, ang * Vector2(ax.y, ax.z).length())

	func result() -> Dictionary:
		r["slide_avg"] = _slide_d / maxf(_slide_t, 1e-3)
		for k in ["slide_avg", "snap", "pop", "body_rate", "slide", "sink", "float", "hand", "joint_worst"]:
			r[k] = snappedf(r[k], 0.001)
		return r
