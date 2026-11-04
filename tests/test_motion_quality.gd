extends Node
## Movement quality across every state and transition (tools/motion_audit_core.gd
## scenarios): no feet through the ground or hovering, planted feet that don't
## skate, joints inside anatomical range, no pose pops on take-off / respawn,
## and the web hand on the line. Limits sit just above the measured values of
## the 2026-10-29 motion pass – a regression shows up as a failure here.

const MotionAudit := preload("res://tools/motion_audit_core.gd")

var audit: Node
var res := {}


func setup() -> void:
	if audit != null:
		return
	audit = MotionAudit.new()
	add_child(audit)
	await audit.build_stage()
	for sc in MotionAudit.SCENARIOS:
		res[sc] = await audit.run_scenario(sc)


func _r(sc: String) -> Dictionary:
	return res[sc]


func test_feet_never_sink_or_hover(t) -> void:
	for sc in res:
		var r := _r(sc)
		t.check(r["sink"] < 0.09, "%s: ankle %.3f m below the ground" % [sc, r["sink"]])
		if sc != "crash_recover":  # stops dead against a tower mid-stride (one frame)
			t.check(r["float"] < 0.06, "%s: standing feet %.3f m above the ground" % [sc, r["float"]])
	# Hard landings and getting up keep the feet on the ground too (the old
	# rig sank them 25 cm into it).
	for sc in ["drop", "wall_run", "run_jump", "knockout", "ledge_dive"]:
		t.check(_r(sc)["sink"] < 0.06, "%s: grounded crouch keeps feet on top (%.3f)" % [sc, _r(sc)["sink"]])


func test_planted_feet_hold_their_ground(t) -> void:
	var limits := {"idle": 0.05, "walk_stop": 0.4, "accelerate": 0.7, "steps": 0.9, "drop": 0.3,
		"run_jump": 1.8, "release_refire": 0.5, "swing_to_land": 1.3, "roll_land": 1.3, "wall_run": 1.2,
		"run_into_wall": 0.8, "ledge_dive": 2.0}
	for sc in limits:
		t.note("%s: planted foot drift %.2f m/s average" % [sc, _r(sc)["slide_avg"]])
		t.check(_r(sc)["slide_avg"] < limits[sc], "%s: planted feet skate %.2f m/s" % [sc, _r(sc)["slide_avg"]])


func test_joints_stay_in_anatomical_range(t) -> void:
	for sc in res:
		var r := _r(sc)
		# (Knockouts are random – a few frames of a couple of degrees over at an
		# ankle during the get-up are allowed there.)
		var limit := 15 if sc in ["knockout", "crash_recover"] else 3
		t.check(r["joint_bad"] <= limit and r["joint_worst"] < deg_to_rad(12.0),
			"%s: %d joint-limit frames, worst %s" % [sc, r["joint_bad"], r["joint_at"]])


func test_no_pose_pops(t) -> void:
	# Take-off and leaving a web hand the limbs to the springs without a jump.
	for sc in ["run_jump", "swing_slow", "swing_fast", "rapid_webs", "tricks", "drop"]:
		var r := _r(sc)
		t.note("%s: fastest bone %.0f°/s (%s), %d pops" % [sc, r["snap"], r["snap_at"], r["pops"]])
		if sc != "run_jump":
			t.check(r["snap"] < 2000.0, "%s: bone snaps at %.0f°/s (%s)" % [sc, r["snap"], r["snap_at"]])
		t.check(not String(r["snap_at"]).contains("air@1.2"), "%s: take-off snap (%s)" % [sc, r["snap_at"]])
	t.check(_r("swing_fast")["pops"] == 0 and _r("swing_slow")["pops"] == 0, "no pops on the web")


func test_jumping_off_a_building_dives_head_first(t) -> void:
	# Sprinting off the 120 m tower: the body goes head-down on the way.
	var a: Node = audit
	a._reset(Vector3(-118, 121, -120))
	a.drv.move = Vector3.RIGHT
	var most_down := 1.0
	var landed_feet_first := false
	var last_air_up := -1.0  # body up·world-up on the last airborne frame
	var was_air := false
	for i in 60 * 5:
		await get_tree().process_frame
		var r: CharacterRig = a.rig
		if not a.player.is_on_floor():
			last_air_up = r.global_basis.y.dot(Vector3.UP)
			most_down = minf(most_down, last_air_up)
			was_air = true
		elif was_air:
			# Judged at touchdown (the rig's _ground_h is refreshed only every
			# few frames, so "< 4 m" could skip straight to the ground).
			landed_feet_first = landed_feet_first or last_air_up > 0.3
			was_air = false
	a.drv.move = Vector3.ZERO
	t.note("dive: body up·world-up reached %.2f; upright again before the ground: %s" % [most_down, landed_feet_first])
	t.check(most_down < -0.6, "head-first dive off a tall building")
	t.check(landed_feet_first, "pulls out feet-first before the ground")


func test_web_hand_stays_on_the_line_in_every_swing(t) -> void:
	for sc in ["swing_slow", "swing_fast", "release_refire", "rapid_webs"]:
		t.check(_r(sc)["hand"] < 0.08, "%s: web hand %.3f m off the line" % [sc, _r(sc)["hand"]])
