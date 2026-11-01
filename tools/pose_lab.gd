extends SceneTree
## Character motion review: scripted movement scenarios on a small stage,
## filmed by a camera that follows the hero from a fixed side angle (so body
## motion reads clearly), saved as frames + one contact sheet per scenario.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method mobile \
##     --resolution 640x480 --fixed-fps 30 -s res://tools/pose_lab.gd -- <outdir> [scenario,...]
## Scenarios (also idlelife edge winded): idle run steps jump swing swing34 swingfast release wallrun crash
##   land jumpclose tricks freefall dive knockout drop chain ledgedive bump turns
##   airturn swingwing

const ALL := ["idle", "run", "steps", "tricks", "freefall", "dive", "knockout", "jump", "swing", "swing34", "swingfast", "release", "wallrun", "crash", "land", "jumpclose", "drop", "chain", "ledgedive", "bump", "turns", "airturn", "swingwing", "groundweb", "idlelife", "edge", "winded", "idleacts", "stumble", "hands", "closeup"]

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
	var human_steer := false  # steer with the player's turn assist
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
	PrototypeWorld.add_box(stage, Vector3(120, 60, -160), Vector3(20, 120, 20), Color(0.7, 0.68, 0.66))
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


## Long idle on the ground: breathing, weight shifts, gaze, idle actions.
func _sc_idlelife() -> void:
	_reset(Vector3(0, 1.0, 20))
	rig.exert = 0.0
	_cam_off = Vector3(1.5, 0.35, -2.0)
	var t := []
	for i in 16:
		t.append(1.0 + i * 1.5)
	await _film("idlelife", 25.0, t)


## Head and clothing up close: front, three-quarter, side, back.
func _sc_closeup() -> void:
	_reset(Vector3(0, 1.0, 20))
	_look_y = 0.78
	for v in [["head_front", Vector3(0, 0.0, -0.9)], ["head_34", Vector3(0.65, 0.05, -0.65)],
			["head_side", Vector3(0.9, 0.0, 0.0)], ["head_back", Vector3(0.3, 0.1, 0.9)]]:
		_cam_off = v[1]
		await _film(v[0], 0.6 if v[0] == "head_front" else 0.2, [0.5 if v[0] == "head_front" else 0.1])
	_look_y = 0.35
	for v in [["torso_front", Vector3(0, 0.0, -1.7)], ["torso_34", Vector3(1.2, 0.1, -1.2)], ["torso_back", Vector3(0.4, 0.1, 1.7)]]:
		_cam_off = v[1]
		await _film(v[0], 0.2, [0.1])
	_look_y = 0.1


## Hands up close: standing (open), running (fists), on the web (grip).
func _sc_hands() -> void:
	_reset(Vector3(0, 1.0, 20))
	_cam_off = Vector3(0.9, -0.05, -0.75)
	_look_y = -0.05
	await _film("hands_stand_r", 1.0, [0.8])
	_cam_off = Vector3(-0.9, -0.05, -0.75)
	await _film("hands_stand_l", 0.3, [0.2])
	_cam_off = Vector3(0.0, -0.05, -1.1)
	await _film("hands_stand_front", 0.3, [0.2])
	var sc := _reset(Vector3(-20, 1.0, 20))
	sc.move = Vector3.RIGHT
	_cam_off = Vector3(0.6, 0.2, 1.4)
	_look_y = 0.1
	await _film("hands_run", 2.2, [1.6, 1.8, 2.0])
	_look_y = 0.1


## Landing moving sideways to the facing: the off-balance catch.
func _sc_stumble() -> void:
	_reset(Vector3(0, 4.5, 20), Vector3(8.0, 0.0, 0.0))
	rig.set_facing(Vector3.FORWARD)
	_cam_off = Vector3(0.0, 0.5, -4.2)  # from the front: the sideways lean reads
	await _film("stumble", 1.6, [0.35, 0.5, 0.6, 0.7, 0.8, 0.95, 1.1, 1.3, 1.5])


## Each idle action, close up (forced one after another).
func _sc_idleacts() -> void:
	_reset(Vector3(0, 1.0, 20))
	rig.exert = 0.0
	_cam_off = Vector3(1.3, 0.45, -1.7)
	_look_y = 0.45
	for a in CharacterRig.IDLE_ACTIONS:
		await _film("act_" + a + "_settle", 1.0, [])
		rig.play_idle(a, 1.0)
		var d: float = CharacterRig.IDLE_ACTIONS[a]
		await _film("act_" + a, d, [d * 0.2, d * 0.4, d * 0.55, d * 0.75])
	_look_y = 0.1


## Standing a step back from a roof edge (the 20 m block's south side).
func _sc_edge() -> void:
	_reset(Vector3(40, 21.0, 16.2))
	rig.exert = 0.0
	_cam_off = Vector3(2.4, 0.4, -2.2)
	var t := []
	for i in 12:
		t.append(1.0 + i * 1.6)
	await _film("edge", 20.0, t)


## Sprint, stop, get the breath back.
func _sc_winded() -> void:
	var sc := _reset(Vector3(-60, 1.0, 20))
	sc.human_steer = true
	sc.move = Vector3.RIGHT
	rig.exert = 0.8
	_cam_off = Vector3(0.6, 0.3, 3.2)
	await _film("winded", 7.0, [0.5, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.5], {0.6: func(): sc.move = Vector3.ZERO})


func _sc_run() -> void:
	var sc := _reset(Vector3(-20, 1.0, 20))
	sc.human_steer = true  # the player's sprint (player_run_speed)
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


## Webbing from the street beside a tower: the launch hop, the zip up and
## the swing along its face (the web must never cut through the corner).
func _sc_groundweb() -> void:
	_reset(Vector3(-12, 0.95, -22), Vector3.ZERO)
	_cam_off = Vector3(-3.5, 0.8, 4.0)
	await _film("groundweb_idle", 0.4, [0.3])
	player.fire_at(Vector3(-4, 50, -32.0), 1)
	await _film("groundweb", 2.4, [0.05, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0, 1.3, 1.6, 2.0, 2.3])


## Same swing, close three-quarter view (arm/leg depth reads), fewer frames.
func _sc_swing34() -> void:
	_reset(Vector3(-25, 48, -20), Vector3(14, 0, 0))
	_cam_off = Vector3(2.6, 0.6, 2.6)
	player.fire_at(Vector3(0, 72, -32.0), 1)
	await _film("swing34", 2.6, [0.15, 0.4, 0.8, 1.1, 1.4, 1.7, 2.0, 2.3])


## The swing from the free-arm side (front-left): the wing arm and the lean.
func _sc_swingwing() -> void:
	_reset(Vector3(-25, 48, -20), Vector3(14, 0, 0))
	_cam_off = Vector3(4.0, 0.8, -1.5)
	player.fire_at(Vector3(0, 72, -32.0), 1)
	await _film("swingwing", 2.6, [0.4, 0.8, 1.1, 1.4, 1.7, 2.0])


## A fast, deep swing (≈ 34 m/s entry) from the side.
func _sc_swingfast() -> void:
	_reset(Vector3(-40, 50, -20), Vector3(34, -6, 0))
	_cam_off = Vector3(0.5, 0.6, 5.0)
	player.fire_at(Vector3(0, 74, -32.0), 1)
	await _film("swingfast", 2.2, [0.05, 0.15, 0.3, 0.5, 0.7, 0.9, 1.1, 1.3, 1.5, 1.7, 1.9, 2.1])


## Web → release → web → release: the transitions between swings.
func _sc_chain() -> void:
	_reset(Vector3(-25, 48, -20), Vector3(14, 0, 0))
	_cam_off = Vector3(3.0, 0.7, 4.0)
	player.fire_at(Vector3(0, 72, -32.0), 1)
	await _film("chain", 4.2, [1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.6, 2.8, 3.1, 3.4, 3.7, 4.0],
		{1.6: func(): player.release_web(), 2.3: func(): player.fire_at(Vector3(110, 100, -150), 2),
		3.8: func(): player.release_web()})


## Sprint off a 120 m tower: swan dive, pull-out, landing.
func _sc_ledgedive() -> void:
	var sc := _reset(Vector3(126, 121, -160))
	sc.move = Vector3.LEFT
	_cam_off = Vector3(0.5, 0.8, 5.5)
	var shots := []
	for i in 14:
		shots.append(1.2 + i * 0.36 if i < 9 else 4.4 + (i - 9) * 0.12)
	await _film("ledgedive", 6.5, shots)
	sc.move = Vector3.ZERO


## Running into a wall, then a swing that scrapes along a facade.
func _sc_bump() -> void:
	var sc := _reset(Vector3(0, 1.0, -18))
	sc.move = Vector3.FORWARD
	_cam_off = Vector3(3.5, 0.6, 1.0)
	await _film("bump_run", 3.0, [1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.75, 1.9, 2.1, 2.4, 2.7, 2.95])
	sc.move = Vector3.ZERO
	_reset(Vector3(-14, 40, -24), Vector3(10, 0, -6))
	_cam_off = Vector3(-2.0, 0.6, 4.5)
	player.fire_at(Vector3(-2, 70, -32), 1)
	await _film("bump_swing", 2.4, [0.3, 0.5, 0.7, 0.9, 1.1, 1.3, 1.6, 2.0])


## Walking 90° turns, then sprint cuts (camera high three-quarter).
func _sc_turns() -> void:
	var sc := _reset(Vector3(-20, 1.0, 20))
	_cam_off = Vector3(2.5, 2.2, 3.0)
	sc.move = Vector3.RIGHT * 0.3
	await _film("turn_walk", 2.6, [1.0, 1.15, 1.3, 1.45, 1.6, 1.8, 2.0, 2.3],
		{1.0: func(): sc.move = Vector3.FORWARD * 0.3})
	sc.move = Vector3.RIGHT
	await _film("turn_run", 2.4, [1.2, 1.3, 1.4, 1.5, 1.6, 1.75, 1.9, 2.1],
		{1.2: func(): sc.move = Vector3.FORWARD})
	sc.move = Vector3.ZERO


func _sc_release() -> void:
	_reset(Vector3(-25, 48, -20), Vector3(14, 0, 0))
	_cam_off = Vector3(0, 0.3, 5.5)
	player.fire_at(Vector3(0, 72, -32.0), 1)
	await _film("release", 4.0, [1.3, 1.5, 1.7, 1.9, 2.1, 2.4, 2.7, 3.0, 3.3, 3.6, 3.9], {1.6: func(): player.release_web()})
	_reset(Vector3(-25, 48, -20), Vector3(14, 0, 0))
	_cam_off = Vector3(3.5, 0.8, 3.5)  # three-quarter view: arm depth reads
	player.fire_at(Vector3(0, 72, -32.0), 1)
	await _film("release34", 3.0, [1.7, 1.9, 2.1, 2.4, 2.7, 2.9], {1.6: func(): player.release_web()})


## Release into a glide, then steer hard to one side: the bank into the turn.
func _sc_airturn() -> void:
	var sc := _reset(Vector3(-25, 48, -20), Vector3(14, 0, 0))
	sc.human_steer = true
	_cam_off = Vector3(-4.5, 1.2, 2.0)  # from behind-left: the bank reads
	player.fire_at(Vector3(0, 72, -32.0), 1)
	await _film("airturn", 3.4, [1.5, 1.8, 2.0, 2.2, 2.4, 2.6, 2.8, 3.0, 3.2],
		{1.6: func(): player.release_web(), 1.9: func(): sc.move = Vector3.FORWARD})
	sc.move = Vector3.ZERO


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
	# The get-up, close: every 0.12 s from the moment the stun ends.
	_reset(Vector3(0, 30, -20), Vector3(0, 1, -35))
	_cam_off = Vector3(3.2, 0.6, 1.6)
	while not rig.ragdolling:
		await process_frame
	while rig.ragdolling:
		await process_frame
	var shots := []
	for i in 12:
		shots.append(0.02 + i * 0.11)
	await _film("getup", 1.45, shots)


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


func _sc_drop() -> void:
	# Straight drop from ~14 m with a little drift: the three-point landing.
	_reset(Vector3(-20, 14, 20), Vector3(2, 0, 0))
	_cam_off = Vector3(-1.5, 0.4, 4.0)
	await _film("drop", 3.2, [1.4, 1.6, 1.7, 1.8, 1.95, 2.1, 2.3, 2.5, 2.8, 3.1])


func _sc_jumpclose() -> void:
	var sc := _reset(Vector3(-20, 1.0, 20))
	_cam_off = Vector3(-1.0, 0.3, 3.2)
	sc.move = Vector3.RIGHT
	await _film("jumpclose", 2.4, [1.15, 1.45, 1.75, 2.05], {1.0: func(): sc.jump = true})


## Fast, repeatable full-body inspection; no saved wardrobe influences QA.
func _sc_review() -> void:
	_reset(Vector3(0, 1.0, 20))
	var outfit := Shop.look()
	outfit.suit = Color(0.22, 0.24, 0.26)
	outfit.pants = Color(0.24, 0.26, 0.28)
	outfit.shoe = Color(0.929, 0.929, 0.894)
	outfit.glove = Color(0.098, 0.098, 0.106)
	outfit.head = "hood"
	outfit.face = ""
	outfit.gadget = {}
	rig.apply_look(outfit)
	for i in 30:
		await process_frame
	for view in [["front", Vector3(0, 0.1, -2.8)], ["rear", Vector3(0, 0.1, 2.8)],
			["side", Vector3(2.8, 0.1, 0)], ["threequarter", Vector3(1.9, 0.2, -2.1)]]:
		cam.position = player.position + view[1]
		cam.look_at(player.position + Vector3(0, 0.05, 0))
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/%s.png" % [out_dir, view[0]])
	print("REVIEW complete")
