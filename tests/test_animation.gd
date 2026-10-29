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
	var wing := INF  # how far out to the side the free hand gets (least, over the fast taut frames)
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
		if rig._glide_rope > 0.95 and i > 40:
			# Swinging forward: the free arm is out wide like a wing (the hand
			# well out past the left shoulder, along the body's left side).
			var left := -rig.global_basis.x.normalized()
			wing = minf(wing, (_pos("hand_l") - _pos("chest")).dot(left))
	t.note("web hand off the line: worst %.1f cm over %d taut frames; free hand out %.2f m" % [
		worst * 100.0, frames, wing])
	t.check(frames > 30, "the swing was taut long enough to judge")
	t.check(worst < 0.06, "the web hand stays on the rope line (IK)")
	t.check(wing > 0.4 and wing < INF, "swinging forward, the free arm spreads out like a wing")


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


func test_running_up_and_down_kerbs(t) -> void:
	# Kerb-height steps up (0.15 → 0.6 m) and back down, then a wall.
	var steps := Node3D.new()
	world.add_child(steps)
	for i in 4:
		var h := 0.15 * (i + 1)
		PrototypeWorld.add_box(steps, Vector3(20 + i * 1.2, h * 0.5, 60), Vector3(1.2, h, 4), Color.GRAY, false)
		PrototypeWorld.add_box(steps, Vector3(20 + (7 - i) * 1.2, h * 0.5, 60), Vector3(1.2, h, 4), Color.GRAY, false)
	PrototypeWorld.add_box(steps, Vector3(40, 2.0, 60), Vector3(1, 4, 4), Color.GRAY, false)
	await get_tree().physics_frame
	player.respawn(Vector3(14, 1.0, 60))
	(player.bot as _Drive).move = Vector3.RIGHT * 0.5
	var top := 0.0
	var steps_up := [0]
	player.stepped_up.connect(func(_h): steps_up[0] += 1)
	var worst_sink := 0.0   # ankle below the surface under it
	var worst_float := 0.0  # planted ankle above it
	var float_sum := 0.0
	var planted := 0
	var space := world.get_world_3d().direct_space_state
	for i in 60 * 5:
		await get_tree().process_frame
		top = maxf(top, player.global_position.y)
		if not player.is_on_floor():
			continue
		for sd in ["l", "r"]:
			var p := _pos("foot_" + sd)
			var rq := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 2.0, 1 | (1 << 3))
			var hit := space.intersect_ray(rq)
			if hit.is_empty():
				continue
			var above: float = p.y - (hit.position as Vector3).y - CharacterRig.ANKLE_H
			worst_sink = maxf(worst_sink, -above)
			if rig._plant.has(sd) and rig._toe[sd] < 0.05:
				worst_float = maxf(worst_float, above)
				float_sum += absf(above)
				planted += 1
	var x := player.global_position.x
	steps.queue_free()
	var mean_float := float_sum / maxf(planted, 1)
	t.note("steps: %d step-ups, top %.2f m, ended at x=%.1f; ankle sink %.1f cm; flat planted foot off the surface %.1f cm mean, %.1f cm worst (%d samples)" % [
		steps_up[0], top - 0.9, x, worst_sink * 100.0, mean_float * 100.0, worst_float * 100.0, planted])
	t.check(steps_up[0] >= 4 and top - 0.9 > 0.55, "running climbs kerb-height steps")
	t.check(x > 28.5 and x < 40.0, "comes back down the far side and the 4 m wall still blocks")
	t.check(worst_sink < 0.06, "feet never sink into the steps")
	t.check(planted > 40 and mean_float < 0.015, "planted feet sit on the step surface")
	t.check(worst_float < 0.07, "lock-in transients stay small (no visible hover)")


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


func test_high_drop_lands_in_a_forward_crouch(t) -> void:
	# A straight drop from ~14 m: the hips sink, the chest pitches forward over
	# the knees (never back), then the body rises to standing.
	player.respawn(Vector3(0, 14, 30))
	player.s.velocity = Vector3(2, 0, 0)
	var lowest := INF
	var chest_fwd := -INF
	var landed := [false]
	player.landed.connect(func(_s, _st): landed[0] = true)
	for i in 60 * 3:
		await get_tree().physics_frame
		if landed[0]:
			var hip_h := _pos("hips").y - player.global_position.y
			lowest = minf(lowest, hip_h)
			var ch: Node3D = rig.bones["chest"]
			chest_fwd = maxf(chest_fwd, ch.global_basis.y.dot(Vector3.RIGHT))
	var stand_h := _pos("hips").y - player.global_position.y
	t.note("hips sank to %.2f m (standing %.2f), chest leaned forward up to %.2f" % [lowest, stand_h, chest_fwd])
	t.check(landed[0], "landed")
	t.check(stand_h - lowest > 0.3, "the hips drop into the landing")
	t.check(chest_fwd > 0.4, "the chest pitches forward over the knees")
	t.check(not player.stunned, "a 14 m drop is a landing, not a crash")
