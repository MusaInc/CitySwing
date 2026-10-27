extends Node
## Character animation overhaul: skinned body follows the rig, web-arm IK,
## two-handed grip under load, planted feet when running, anatomical ragdoll
## limits and the get-up after a crash.

var world: Node3D
var player: Player
var rig: CharacterRig


class _Drive:
	extends RefCounted
	var move := Vector3.ZERO
	func drive(_p, _dt) -> Dictionary:
		return {"move": move, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}


func setup() -> void:
	world = Node3D.new()
	add_child(world)
	PrototypeWorld.add_box(world, Vector3(0, -0.5, 0), Vector3(600, 1, 600), Color.GRAY, false, true)
	PrototypeWorld.add_box(world, Vector3(0, 40, -40), Vector3(16, 80, 16), Color.WHITE)
	player = Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	add_child(player)
	player.bot = _Drive.new()
	rig = CharacterRig.new()
	player.add_child(rig)
	rig.set_player(player)
	await get_tree().physics_frame


func teardown() -> void:
	player.queue_free()
	world.queue_free()
	await get_tree().process_frame


func _pos(b: String) -> Vector3:
	return (rig.bones[b] as Node3D).global_position


func test_skinned_body_follows_the_rig(t) -> void:
	t.check(rig.skeleton != null, "character.glb has a skinned body on a skeleton")
	if rig.skeleton == null:
		return
	player.respawn(Vector3(0, 40, -20))
	player.fire_at(Vector3(0, 70, -32.0), 1)
	var worst := 0.0
	for i in 60:
		await get_tree().process_frame
		for b in CharacterRig.BONES:
			var idx := rig.skeleton.find_bone("b_" + b)
			if idx < 0:
				continue
			var g := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(idx)
			worst = maxf(worst, g.origin.distance_to(_pos(b)))
	t.note("skeleton vs pivots: worst joint offset %.1f mm" % (worst * 1000.0))
	t.check(worst < 0.005, "every skinned joint sits on its rig pivot")


func test_web_hand_stays_on_the_line(t) -> void:
	player.respawn(Vector3(-25, 48, -20))
	player.s.velocity = Vector3(14, 0, 0)
	player.fire_at(Vector3(0, 72, -32.0), 1)
	var worst := 0.0
	var frames := 0
	var grip := 0.0
	var left_gap := INF
	for i in 150:
		await get_tree().process_frame
		if player.line_state != Player.Line.ATTACHED or not player.s.taut:
			continue
		frames += 1
		var sh := _pos("upper_arm_r")
		var hand := _pos("hand_r")
		var dir := (player.s.anchor - sh).normalized()
		var off := (hand - sh) - dir * (hand - sh).dot(dir)
		worst = maxf(worst, off.length())
		grip = maxf(grip, rig._lgrip)
		if rig._lgrip > 0.9:
			var l := _pos("hand_l")
			var lo := (l - sh) - dir * (l - sh).dot(dir)
			left_gap = minf(left_gap, lo.length())
	t.note("web hand off the line: worst %.1f cm over %d taut frames; free-hand grip %.2f, closest %.1f cm" % [
		worst * 100.0, frames, grip, left_gap * 100.0])
	t.check(frames > 30, "the swing was taut long enough to judge")
	t.check(worst < 0.06, "the web hand stays on the rope line (IK)")
	t.check(grip > 0.9, "under heavy load the free hand joins the rope")
	t.check(left_gap < 0.08, "the second hand actually reaches the line")


func test_running_feet_plant_instead_of_sliding(t) -> void:
	player.respawn(Vector3(-40, 1.0, 20))
	(player.bot as _Drive).move = Vector3.RIGHT
	for i in 90:
		await get_tree().process_frame
	var prev := {"l": _pos("foot_l"), "r": _pos("foot_r")}
	var samples: Array = []  # [ankle height, ground speed]
	var body := 0.0
	var dt := 1.0 / 60.0
	for i in 120:
		await get_tree().process_frame
		body += player.speed()
		for sd in ["l", "r"]:
			var p := _pos("foot_" + sd)
			samples.append([p.y, Vector3(p.x - prev[sd].x, 0, p.z - prev[sd].z).length() / dt])
			prev[sd] = p
	# Contact = the ankle down at its lowest heights (within 3 cm).
	var low := INF
	for smp in samples:
		low = minf(low, smp[0])
	var slide := 0.0
	var n := 0
	for smp in samples:
		if smp[0] < low + 0.03:
			slide += smp[1]
			n += 1
	var mean_slide := slide / maxf(n, 1)
	var mean_body := body / 120.0
	t.note("running %.1f m/s: stance foot moves %.1f m/s over ground (%.0f%% of body speed)" % [
		mean_body, mean_slide, 100.0 * mean_slide / maxf(mean_body, 0.01)])
	t.check(mean_body > 8.0, "actually running")
	t.check(mean_slide < mean_body * 0.4, "the stance foot is (mostly) planted, not skating along")


func test_ragdoll_joints_bend_the_right_way(t) -> void:
	player.respawn(Vector3(0, 30, -14))
	await get_tree().physics_frame
	player.s.velocity = Vector3(0, 0, -player.params.wall_run_max_speed - 8.0)
	var bad := 0
	var samples := 0
	var getup_seen := false
	for i in 60 * 6:
		await get_tree().process_frame
		getup_seen = getup_seen or rig._getup_t > 0.0
		if not rig.ragdolling:
			continue
		var p: Dictionary = rig.ragdoll.pos
		var up: Vector3 = ((p["neck"] as Vector3) - (p["pelvis"] as Vector3)).normalized()
		var right: Vector3 = ((p["sh_r"] as Vector3) - (p["sh_l"] as Vector3))
		right = (right - up * right.dot(up)).normalized()
		var fwd := right.cross(up)  # x × y = z (back) → forward is -(that); see VerletRagdoll
		fwd = -fwd
		for sd in ["l", "r"]:
			samples += 1
			if _side(p["hip_" + sd], p["kn_" + sd], p["an_" + sd], fwd) < -0.02:
				bad += 1  # knee hyperextended backward
			if _side(p["sh_" + sd], p["el_" + sd], p["wr_" + sd], -fwd) < -0.02:
				bad += 1  # elbow bent the wrong way
	t.note("ragdoll hinge checks: %d bad of %d" % [bad, samples * 2])
	t.check(samples > 20, "the crash ragdolled")
	t.check(bad == 0, "knees and elbows only bend the anatomical way")
	t.check(getup_seen, "recovery goes through the get-up pose")
	t.check(not rig.ragdolling and not player.stunned, "back on its feet")


## Signed distance of the middle joint from the root→end line along `bend`.
static func _side(a: Vector3, m: Vector3, e: Vector3, bend: Vector3) -> float:
	var ax := (e - a).normalized()
	var off := (m - a) - ax * (m - a).dot(ax)
	var b := (bend - ax * bend.dot(ax)).normalized()
	return off.dot(b)
