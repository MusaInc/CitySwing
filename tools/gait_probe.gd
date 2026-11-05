extends SceneTree
## Measures the run: hip height over the ground and knee flexion through a
## steady sprint (pose quality numbers for tuning the gait).
##   godot --headless --fixed-fps 60 -s res://tools/gait_probe.gd -- [secs] [move_scale]

func _initialize() -> void:
	_go.call_deferred()


class Drive:
	extends RefCounted
	var move := Vector3.RIGHT
	var human_steer := true
	func drive(_p, _dt) -> Dictionary:
		return {"move": move, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var secs := float(args[0]) if args.size() > 0 else 3.0
	var k := float(args[1]) if args.size() > 1 else 1.0
	var stage := Node3D.new()
	root.add_child(stage)
	PrototypeWorld.add_box(stage, Vector3(0, -0.5, 0), Vector3(600, 1, 600), Color.GRAY, false, true)
	var p := Player.new()
	p.params = load("res://config/swing_params.tres").duplicate()
	root.add_child(p)
	p.respawn(Vector3(-100, 1.0, 0))
	var rig := CharacterRig.new()
	p.add_child(rig)
	rig.set_player(p)
	var d := Drive.new()
	d.move = Vector3.RIGHT * k
	p.bot = d
	var t := 0.0
	var hips: Array = []
	var knees: Array = []
	var stance_knee: Array = []
	var drops: Array = []
	var bobs: Array = []
	while t < secs:
		await physics_frame
		t += 1.0 / 60.0
		if t < 1.2:
			continue
		var hip: Vector3 = (rig.bones["thigh_l"] as Node3D).global_position.lerp((rig.bones["thigh_r"] as Node3D).global_position, 0.5)
		hips.append(hip.y)
		drops.append(rig._hip_drop)
		bobs.append((rig.bones["hips"] as Node3D).position.y)
		for sd in ["l", "r"]:
			var a: Vector3 = (rig.bones["thigh_" + sd] as Node3D).global_position
			var kn: Vector3 = (rig.bones["shin_" + sd] as Node3D).global_position
			var an: Vector3 = (rig.bones["foot_" + sd] as Node3D).global_position
			var flex := 180.0 - rad_to_deg((a - kn).angle_to(an - kn))
			knees.append(flex)
			if (rig._gait.feet[sd] as Gait.Foot).planted:
				stance_knee.append(flex)
	var avg := func(a: Array) -> float: return a.reduce(func(x, y): return x + y, 0.0) / maxf(a.size(), 1)
	print("GAIT speed %.1f m/s  hip height mean %.3f min %.3f max %.3f  knee flex mean %.0f° max %.0f°  stance knee mean %.0f° max %.0f°" % [
		p.speed(), avg.call(hips), hips.min(), hips.max(), avg.call(knees), knees.max(), avg.call(stance_knee), stance_knee.max()])
	print("GAIT hip_drop mean %.3f max %.3f  hips local y mean %.3f  duty %.2f freq %.2f run %.2f sprint %.2f" % [avg.call(drops), drops.max(), avg.call(bobs), rig._gait.duty, rig._gait.freq, rig._gait.run, rig._gait.sprint])
	quit()
