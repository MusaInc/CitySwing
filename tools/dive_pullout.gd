extends SceneTree
## Ledge dive pull-out trace: sprint off the motion-audit tower and print body
## up·world-up, chest·facing and swan state for the last 25 m of the fall.
##   godot --headless --fixed-fps 60 -s res://tools/dive_pullout.gd
const MotionAudit := preload("res://tools/motion_audit_core.gd")
var audit


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	audit = MotionAudit.new()
	root.add_child(audit)
	await audit.build_stage()
	audit._reset(Vector3(-118, 121, -120))
	audit.drv.move = Vector3.RIGHT
	for i in 60 * 5:
		await process_frame
		var r: CharacterRig = audit.rig
		if audit.player.is_on_floor():
			continue
		if r._ground_h < 25.0:
			var b := r.global_basis
			print("gh=%5.1f up.y=%5.2f chest·face=%5.2f swan=%.2f peak=%.2f vy=%.1f" % [r._ground_h,
				b.y.dot(Vector3.UP), (-b.z).dot(r._facing), r._swan, r._swan_peak, audit.player.velocity.y])
	quit()
