extends Node
## Tap-to-web targeting and multi-touch controls, in a purpose-built scene:
##   tower A (0,30,-30) 10×60×10 – an obstruction
##   tower B (20,40,-60) 10×80×10 – the target
##   tower C far away (0,40,-260) – out of range
##   street slab at y=0 (street group/layer)

var player: Player
var cam: Camera3D
var world: Node3D


func setup() -> void:
	world = Node3D.new()
	add_child(world)
	PrototypeWorld.add_box(world, Vector3(0, -0.5, 0), Vector3(800, 1, 800), Color.GRAY, false, true)
	PrototypeWorld.add_box(world, Vector3(0, 30, -30), Vector3(10, 60, 10), Color.WHITE)
	PrototypeWorld.add_box(world, Vector3(20, 40, -60), Vector3(10, 80, 10), Color.WHITE)
	PrototypeWorld.add_box(world, Vector3(0, 40, -260), Vector3(20, 80, 20), Color.WHITE)
	player = Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	add_child(player)
	player.bot = _Idle.new()
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	await get_tree().physics_frame


func teardown() -> void:
	for n in [player, cam, world]:
		n.queue_free()
	await get_tree().process_frame


func _place(p: Vector3) -> void:
	player.respawn(p)
	player.s.velocity = Vector3.ZERO


func _independent_hit(screen: Vector2) -> Dictionary:
	var from := cam.project_ray_origin(screen)
	var to := from + cam.project_ray_normal(screen) * 500.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 0xFFFF, [player.get_rid()])
	return get_viewport().world_3d.direct_space_state.intersect_ray(q)


func test_tap_attaches_exactly_under_the_finger(t) -> void:
	_place(Vector3(12, 30, -30))
	cam.look_at_from_position(Vector3(12, 32, -15), Vector3(20, 45, -55))
	await get_tree().physics_frame
	var px := cam.unproject_position(Vector3(17, 47, -55.0))
	var r := player.screen_target(cam, px)
	var hit := _independent_hit(px)
	t.check(r["ok"], "valid building surface accepted (%s)" % r["reason"])
	t.check(not hit.is_empty() and (r["point"] as Vector3).distance_to(hit["position"]) < 0.01,
		"point is the surface under the pixel (%s vs %s)" % [r["point"], hit.get("position")])
	player.fire_at(r["point"], 7)
	for i in 20:
		await get_tree().physics_frame
	t.check(player.line_state == Player.Line.ATTACHED, "web attached")
	t.check(player.rope_anchor().distance_to(r["point"]) < 0.001, "anchor is the exact tapped point")
	# The anchor stays put in world space while the body swings under it.
	var a0 := player.rope_anchor()
	for i in 60:
		await get_tree().physics_frame
	t.check(player.rope_anchor().distance_to(a0) < 0.001 or not player.wraps.is_empty(), "anchor fixed in world space")


func test_attach_height_changes_the_trajectory(t) -> void:
	var finals: Array[Vector3] = []
	for y in [48.0, 70.0]:
		_place(Vector3(12, 30, -30))
		await get_tree().physics_frame
		player.fire_at(Vector3(17, y, -55.0), 1)
		for i in 90:
			await get_tree().physics_frame
		finals.append(player.global_position)
		player.release_web()
	t.note("after 1.5 s: low anchor %s, high anchor %s" % [finals[0].snapped(Vector3.ONE * 0.1), finals[1].snapped(Vector3.ONE * 0.1)])
	t.check(finals[0].distance_to(finals[1]) > 2.0, "different attach heights give different swings")


func test_rejections_never_redirect(t) -> void:
	# Blocked: the camera sees tower B, but tower A stands between it and the launcher.
	_place(Vector3(-10, 30, -5))
	cam.look_at_from_position(Vector3(30, 52, 10), Vector3(20, 50, -55))
	await get_tree().physics_frame
	var r := player.screen_target(cam, cam.unproject_position(Vector3(20, 50, -55.0)))
	t.check(not r["ok"] and r["reason"] == "blocked", "obstructed target rejected as blocked (%s)" % r["reason"])
	# Too far.
	_place(Vector3(0, 30, -100))
	cam.look_at_from_position(Vector3(0, 32, -90), Vector3(0, 50, -250))
	await get_tree().physics_frame
	r = player.screen_target(cam, cam.unproject_position(Vector3(0, 50, -250.0)))
	t.check(not r["ok"] and r["reason"] == "too far", "out-of-range target rejected (%s)" % r["reason"])
	# Sky and street.
	cam.look_at_from_position(Vector3(0, 32, -90), Vector3(0, 300, -400))
	await get_tree().physics_frame
	r = player.screen_target(cam, Vector2(640, 100))
	t.check(not r["ok"] and r["reason"] == "sky", "sky rejected (%s)" % r["reason"])
	cam.look_at_from_position(Vector3(0, 32, -90), Vector3(0, 0, -100))
	await get_tree().physics_frame
	r = player.screen_target(cam, Vector2(640, 360))
	t.check(not r["ok"] and r["reason"] == "street", "street rejected (%s)" % r["reason"])
	t.check(player.line_state == Player.Line.IDLE, "no rejected tap ever fired a web")


func test_reattach_and_per_finger_release(t) -> void:
	_place(Vector3(12, 30, -30))
	await get_tree().physics_frame
	player.fire_at(Vector3(17, 55, -55.0), 3)
	for i in 30:
		await get_tree().physics_frame
	t.check(player.line_state == Player.Line.ATTACHED and player.web_touch_id == 3, "finger 3 holds the web")
	player.release_web(5)
	t.check(player.line_state == Player.Line.ATTACHED, "another finger lifting does not release")
	var v := player.s.velocity
	player.fire_at(Vector3(5, 50, -28.0), 4)  # immediate reattach to tower A
	t.check(player.s.velocity == v, "reattaching keeps momentum exactly")
	t.check(player.swings == 1, "the old web counts as a completed swing")
	for i in 20:
		await get_tree().physics_frame
	t.check(player.line_state == Player.Line.ATTACHED and player.web_touch_id == 4, "now attached by finger 4")
	t.check(player.rope_anchor().distance_to(Vector3(5, 50, -28.0)) < 0.001, "new exact anchor")
	player.release_web(3)
	t.check(player.line_state == Player.Line.ATTACHED, "old finger lifting doesn't drop the new web")
	v = player.s.velocity
	player.release_web(4)
	t.check(player.line_state == Player.Line.IDLE and player.s.velocity == v, "owning finger releases, momentum kept")


func test_multitouch_roles(t) -> void:
	var cam_rig := SwingCamera.new()
	add_child(cam_rig)
	cam_rig.set_target(player)
	var tc := TouchControls.new()
	add_child(tc)
	tc.size = Vector2(1280, 720)
	tc._update_safe()
	tc.camera = cam_rig
	tc.player = player
	var feedback: Array = []
	tc.web_feedback.connect(func(p, ok, reason): feedback.append([ok, reason]))
	_place(Vector3(12, 30, -30))
	cam_rig.face(atan2(-8.0, 25.0))  # look toward tower B
	for i in 4:
		await get_tree().process_frame
	# Find a right-side pixel that sees tower B.
	var web_px := Vector2.ZERO
	for y in range(120, 420, 20):
		for x in range(700, 1100, 40):
			if player.screen_target(cam_rig.cam, Vector2(x, y))["ok"]:
				web_px = Vector2(x, y)
				break
		if web_px != Vector2.ZERO:
			break
	if not t.check(web_px != Vector2.ZERO, "a valid building pixel on the right side"):
		cam_rig.queue_free()
		tc.queue_free()
		return
	# Finger 0: stick (left). Finger 1: web. Finger 2: drag on sky = camera.
	tc.touch_down(0, Vector2(200, 560))
	tc.touch_drag(0, Vector2(200, 480))
	t.check(Input.is_action_pressed("move_forward"), "stick drives movement")
	tc.touch_down(1, web_px)
	t.check(player.line_state == Player.Line.FLYING and player.web_touch_id == 1, "finger 1 fired the web where it touched")
	var expected: Vector3 = tc.touches[1]["result"]["point"]
	t.check(player.line_target.distance_to(expected) < 0.001, "line aimed at the touched point")
	for i in 20:
		await get_tree().physics_frame
	var yaw0 := cam_rig.view_yaw()
	var sky_px := Vector2(1000, 40)
	tc.touch_down(2, sky_px)
	for k in 6:
		tc.touch_drag(2, sky_px - Vector2(25 * (k + 1), 0))
	t.check(absf(cam_rig.view_yaw() - yaw0) > 0.05, "dragging empty sky turns the camera")
	t.check(player.line_state == Player.Line.ATTACHED, "camera drag does not touch the web")
	tc.touch_up(2)
	t.check(player.line_state == Player.Line.ATTACHED, "lifting the camera finger keeps the web")
	# LOOK pad drag rotates and never fires.
	var lp := tc.button_center("look")
	var yaw1 := cam_rig.view_yaw()
	tc.touch_down(3, lp)
	for k in 5:
		tc.touch_drag(3, lp + Vector2(0, -20 * (k + 1)) + Vector2(30 * (k + 1), 0))
	tc.touch_up(3)
	t.check(absf(cam_rig.view_yaw() - yaw1) > 0.05, "LOOK pad rotates the camera")
	t.check(player.web_touch_id == 1, "LOOK pad did not fire a web")
	# A tap on the sky (no drag) is rejected with feedback, not fired.
	tc.touch_down(5, sky_px)
	tc.touch_up(5)
	t.check(feedback.size() >= 2 and feedback[-1][0] == false and feedback[-1][1] == "sky",
		"invalid tap shows feedback (%s)" % [feedback])
	t.check(player.web_touch_id == 1, "invalid tap didn't steal the web")
	tc.touch_up(1)
	t.check(player.line_state == Player.Line.IDLE, "web finger lifting releases")
	tc.touch_up(0)
	t.check(not Input.is_action_pressed("move_forward"), "stick release clears movement")
	cam_rig.queue_free()
	tc.queue_free()


func test_rope_wraps_round_a_corner_and_never_cuts_through(t) -> void:
	# Swing round the corner of tower A from an anchor high on its east face.
	_place(Vector3(20, 40, -24))
	player.params.wrap_cut_length = 1.0  # follow the line round both corners
	await get_tree().physics_frame
	player.fire_at(Vector3(5.0, 52.0, -30.0), 1)
	for i in 6:
		await get_tree().physics_frame
	player.s.velocity = Vector3(0, 0, 26)  # carry on round the north-east corner
	var wrapped := false
	var cut := 0
	var frames := 0
	var space := get_viewport().world_3d.direct_space_state
	for i in 150:
		await get_tree().physics_frame
		if player.line_state != Player.Line.ATTACHED:
			break
		frames += 1
		wrapped = wrapped or not player.wraps.is_empty()
		var a := player.global_position
		var b := player.s.anchor
		# Grazing the corner right at the pivot is the rope resting on it, not cutting through.
		var q := PhysicsRayQueryParameters3D.create(a, b - (b - a).normalized() * 1.0, 3, [player.get_rid()])
		var hh := space.intersect_ray(q)
		if not hh.is_empty():
			cut += 1
			if OS.has_environment("DBG_WRAP") and cut < 6:
				t.note("blocked f%d pos=%s pivot=%s wraps=%d L=%.1f hit=%s" % [i, a.snapped(Vector3.ONE * 0.01), b.snapped(Vector3.ONE * 0.01), player.wraps.size(), player.s.rope_length, (hh["position"] as Vector3).snapped(Vector3.ONE * 0.01)])
	t.note("wrapped=%s, frames with the free segment blocked: %d/%d" % [wrapped, cut, frames])
	t.check(wrapped, "rope caught on the corner")
	t.check(cut <= 1, "the rope never passes through the building")


class _Idle:
	extends RefCounted
	func drive(_p, _dt) -> Dictionary:
		return {"move": Vector3.ZERO, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}
