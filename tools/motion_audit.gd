extends SceneTree
## Motion audit: drives the character through scripted scenarios covering every
## movement state and transition, and measures what reads as wrong on screen:
##   * snap    – fastest local bone rotation (deg/s) outside tricks/rolls/ragdoll,
##               and the whole body's turn rate (a pop between poses);
##   * joints  – knees/elbows bending backwards or off their hinge, heads
##               turned past the neck's range, thighs/arms past anatomical range;
##   * feet    – a planted foot sliding, any ankle below the ground, grounded
##               feet floating;
##   * hand    – the web hand off the rope line.
##   godot --headless --fixed-fps 60 -s res://tools/motion_audit.gd -- [scenario,...] [--json=path]
## Also used by tests/test_motion_quality.gd (MotionAudit.run_scenario).

const MotionAudit := preload("res://tools/motion_audit_core.gd")


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var which: Array = []
	var json := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--json="):
			json = a.substr(7)
		else:
			which = Array(a.split(","))
	var audit := MotionAudit.new()
	root.add_child(audit)
	await audit.build_stage()
	if which.is_empty():
		which = MotionAudit.SCENARIOS
	var all := {}
	for sc in which:
		var r: Dictionary = await audit.run_scenario(sc)
		all[sc] = r
		print(MotionAudit.format(sc, r))
	if json != "":
		var f := FileAccess.open(json, FileAccess.WRITE)
		f.store_string(JSON.stringify(all, "  "))
	quit()
