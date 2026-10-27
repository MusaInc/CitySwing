extends SceneTree
## Character motion review: scripted movement scenarios on a small stage,
## filmed by a camera that follows the hero from a fixed side angle (so body
## motion reads clearly), saved as frames + one contact sheet per scenario.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method mobile \
##     --resolution 640x480 --fixed-fps 30 -s res://tools/pose_lab.gd -- <outdir> [scenario,...]
## Scenarios: idle run steps jump swing release wallrun crash land jumpclose
##   tricks freefall dive knockout

const ALL := ["idle", "run", "steps", "tricks", "freefall", "dive", "knockout", "jump", "swing", "release", "wallrun", "crash", "land", "jumpclose"]

var player: Player
var rig: CharacterRig
var rope: RopeVisual
var cam: Camera3D
var out_dir := ""
var _cam_off := Vector3(0, 0.4, 4.5)
var _cam_pos := Vector3.ZERO
var _look_y := 0.1  # aim point above the capsule centre


class Script_:
	extends RefCounted
	var move := Vector3.ZERO
	var jump := false
	var grapple := false
	func drive(_p, _dt) -> Dictionary:
		var j := jump
		jump = false
		return {"move": move, "aim": Vector3.FORWARD, "grapple": grapple, "reel": 0.0, "jump": j}


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "screenshots/pose_lab"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var which: Array = Array(args[1].split(",")) if args.size() > 1 else ALL
	var atmo := Atmosphere.new()
	root.add_child(atmo)
	var stage := Node3D.new()
	root.add_child(stage)
	PrototypeWorld.add_box(stage, Vector3(0, -0.5, 0), Vector3(600, 1, 600), Color(0.42, 0.43, 0.45), false, true)
	PrototypeWorld.add_box(stage, Vector3(0, 40, -40), Vector3(16, 80, 16), Color(0.75, 0.72, 0.68))
	PrototypeWorld.add_box(stage, Vector3(40, 10, 30), Vector3(30, 20, 30), Color(0.6, 0.55, 0.5))
	for i in 4:  # kerb-height steps up, then down again (the "steps" scenario)
		var h := 0.15 * (i + 1)
		PrototypeWorld.add_box(stage, Vector3(-10 + i * 1.2, h * 0.5, 60), Vector3(1.2, h, 4), Color(0.55, 0.52, 0.5), false)
		PrototypeWorld.add_box(stage, Vector3(-10 + (7 - i) * 1.2, h * 0.5, 60), Vector3(1.2, h, 4), Color(0.55, 0.52, 0.5), false)
	player = Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	root.add_child(player)
	rig = CharacterRig.new()
	player.add_child(rig)
	rig.set_player(player)
	rope = RopeVisual.new()
	root.add_child(rope)
	rope.player = player
	rope.hand = rig.launcher
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 1500.0
	root.add_child(cam)
	cam.make_current()
	await physics_frame
	for sc in which:
		await call("_sc_" + sc)
	quit()


## Runs `secs` of simulation, saving a frame at each time in `shots`.
func _film(name: String, secs: float, shots: Array, events := {}) -> void:
	var t := 0.0
	var k := 0
	var files: Array[String] = []
	_cam_pos = player.global_position + _cam_off
	while t < secs:
		for at in events.keys():
			if t >= at:
				(events[at] as Callable).call()
				events.erase(at)
		await process_frame
		t += 1.0 / 30.0
		var target := player.global_position + Vector3(0, _look_y, 0)
		if rig.ragdolling:
			target = rig.global_position
		_cam_pos = _cam_pos.lerp(target + _cam_off, 0.25)
		cam.global_position = _cam_pos
		cam.look_at(target, Vector3.UP)
		if k < shots.size() and t >= shots[k]:
			await RenderingServer.frame_post_draw
			var f := "%s/%s_%02d.png" % [out_dir, name, k]
			get_root().get_texture().get_image().save_png(f)
			files.append(f)
			k += 1
	OS.execute("python3", ["tools/contact_sheet.py", "%s/%s_sheet.png" % [out_dir, name]] + files)
	print("SHEET %s (%d frames)" % [name, files.size()])


func _reset(at: Vector3, vel := Vector3.ZERO) -> Script_:
	var sc := Script_.new()
	player.bot = sc
	player.respawn(at)
	player.s.velocity = vel
	rig.set_facing(Vector3.FORWARD if vel.length() < 0.1 else Vector3(vel.x, 0, vel.z).normalized())
	return sc


func _sc_idle() -> void:
	_reset(Vector3(0, 1.0, 20))
	_cam_off = Vector3(0, 0.1, -2.6)  # front
	await _film("idle_front", 3.0, [0.5, 2.5])
	_cam_off = Vector3(2.6, 0.1, 0)
	await _film("idle_side", 1.0, [0.5])
	_cam_off = Vector3(1.6, 0.4, -1.6)
	await _film("idle_34", 1.0, [0.5])
	_cam_off = Vector3(0.25, 0.0, -0.75)
	_look_y = 0.78
	await _film("idle_face", 1.0, [0.5])
	_look_y = 0.1


func _sc_run() -> void:
	var sc := _reset(Vector3(-20, 1.0, 20))
	_cam_off = Vector3(0, 0.2, 3.6)
	sc.move = Vector3.RIGHT
	var cyc := []
	for i in 12:
		cyc.append(2.0 + i / 30.0)
	await _film("run_cycle", 2.5, cyc)
	_cam_off = Vector3(2.2, 0.5, 2.2)  # three-quarter, close: arm swing and clearance
	var cyc34 := []
	for i in 8:
		cyc34.append(0.2 + i / 30.0)
	await _film("run_34", 0.5, cyc34)
	_cam_off = Vector3(0, 0.2, 3.6)
	await _film("run_stop", 1.4, [0.1, 0.25, 0.4, 0.6, 0.9, 1.3], {0.05: func(): sc.move = Vector3.ZERO})
	var sc2 := _reset(Vector3(-20, 1.0, 20))
	sc2.move = Vector3.RIGHT * 0.25
	await _film("walk", 2.0, [1.0, 1.1, 1.2, 1.3, 1.4, 1.5])
	sc2.move = Vector3.ZERO


func _sc_jump() -> void:
	var sc := _reset(Vector3(-20, 1.0, 20))
	_cam_off = Vector3(0, 0.5, 6.0)
	sc.move = Vector3.RIGHT
	await _film("jump", 3.0, [0.9, 1.05, 1.2, 1.4, 1.6, 1.8, 2.0, 2.15, 2.3, 2.5, 2.7, 2.9], {1.0: func(): sc.jump = true})


func _sc_swing() -> void:
	_reset(Vector3(-25, 48, -20), Vector3(14, 0, 0))
	_cam_off = Vector3(0, 0.3, 5.0)
	player.fire_at(Vector3(0, 72, -32.0), 1)
	await _film("swing", 3.0, [0.1, 0.3, 0.6, 0.9, 1.2, 1.5, 1.8, 2.1, 2.4, 2.7, 2.9])


func _sc_release() -> void:
	_reset(Vector3(-25, 48, -20), Vector3(14, 0, 0))
	_cam_off = Vector3(0, 0.3, 5.5)
	player.fire_at(Vector3(0, 72, -32.0), 1)
	await _film("release", 4.0, [1.3, 1.5, 1.7, 1.9, 2.1, 2.4, 2.7, 3.0, 3.3, 3.6, 3.9], {1.6: func(): player.release_web()})
	_reset(Vector3(-25, 48, -20), Vector3(14, 0, 0))
	_cam_off = Vector3(3.5, 0.8, 3.5)  # three-quarter view: arm depth reads
	player.fire_at(Vector3(0, 72, -32.0), 1)
	await _film("release34", 3.0, [1.7, 1.9, 2.1, 2.4, 2.7, 2.9], {1.6: func(): player.release_web()})


func _sc_wallrun() -> void:
	_reset(Vector3(0, 30, -14), Vector3(0, 0, -40))
	_cam_off = Vector3(7.0, 0.5, 2.0)
	await _film("wallrun", 3.0, [0.3, 0.45, 0.55, 0.65, 0.8, 1.0, 1.3, 1.6, 2.0, 2.4, 2.9])


func _sc_crash() -> void:
	_reset(Vector3(0, 30, -14), Vector3(0, 0, -58))
	_cam_off = Vector3(7.0, 0.8, 3.0)
	await _film("crash", 5.0, [0.25, 0.35, 0.5, 0.8, 1.2, 1.6, 2.0, 2.5, 3.0, 3.5, 4.2, 4.9])


## Every air trick from the same take-off (one sheet each).
func _sc_tricks() -> void:
	for name in CharacterRig.TRICKS:
		_reset(Vector3(-20, 90, 200), Vector3(9, 9, 0))
		_cam_off = Vector3(0, 0.6, 6.5)
		await process_frame
		rig.start_trick(name)
		var dur: float = rig._trick_dur
		var shots := []
		for i in 9:
			shots.append(0.05 + dur * i / 8.0)
		await _film("trick_" + name, dur + 0.15, shots)


func _sc_freefall() -> void:
	_reset(Vector3(-20, 140, 200), Vector3(5, 0, 0))
	_cam_off = Vector3(0, 1.0, 6.0)
	await _film("freefall", 3.4, [0.2, 0.6, 1.0, 1.4, 1.8, 2.2, 2.6, 3.0, 3.3])


func _sc_dive() -> void:
	_reset(Vector3(-20, 140, 200), Vector3(22, -24, 0))
	_cam_off = Vector3(0, 1.0, 6.0)
	await _film("dive", 1.6, [0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4])


func _sc_knockout() -> void:
	_reset(Vector3(0, 30, -20), Vector3(0, 1, -35))
	_cam_off = Vector3(7.0, 0.8, 3.0)
	await _film("knockout", 4.0, [0.3, 0.36, 0.42, 0.5, 0.6, 0.75, 0.95, 1.2, 1.6, 2.1, 2.8, 3.8])


func _sc_steps() -> void:
	var sc := _reset(Vector3(-14, 1.0, 60))
	_cam_off = Vector3(0, 0.3, 3.4)
	sc.move = Vector3.RIGHT * 0.3
	var shots := []
	for i in 12:
		shots.append(1.0 + i * 0.35)
	await _film("steps", 5.4, shots)
	sc.move = Vector3.ZERO


func _sc_land() -> void:
	_reset(Vector3(-20, 16, 20), Vector3(14, 0, 0))
	_cam_off = Vector3(0, 0.5, 6.0)
	await _film("land", 3.0, [0.6, 0.8, 0.95, 1.05, 1.15, 1.3, 1.5, 1.7, 2.0, 2.4, 2.9])


func _sc_jumpclose() -> void:
	var sc := _reset(Vector3(-20, 1.0, 20))
	_cam_off = Vector3(-1.0, 0.3, 3.2)
	sc.move = Vector3.RIGHT
	await _film("jumpclose", 2.4, [1.15, 1.45, 1.75, 2.05], {1.0: func(): sc.jump = true})
