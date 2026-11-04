extends SceneTree
## Ledge dive twist check: sprint off the motion-audit tower and measure how
## far the body's left-right axis turns (a clean forward dive never flips it).
##   godot --headless --fixed-fps 60 -s res://tools/dive_twist.gd
const MotionAudit := preload("res://tools/motion_audit_core.gd")
var worst := 0.0
var r0 := Vector3.ZERO
var audit


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	audit = MotionAudit.new()
	root.add_child(audit)
	await audit.build_stage()
	physics_frame.connect(_sample)
	var r: Dictionary = await audit.run_scenario("ledge_dive")
	print(MotionAudit.format("ledge_dive", r))
	print("TWIST worst body twist %.0f°" % rad_to_deg(worst))
	quit()


func _sample() -> void:
	if audit.rig == null or audit.player == null:
		return
	var b: Basis = audit.rig._body_basis
	if audit.player.is_on_floor():
		r0 = b.x
		return
	worst = maxf(worst, r0.angle_to(b.x))
