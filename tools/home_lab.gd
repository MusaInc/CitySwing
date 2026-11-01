extends SceneTree
## Window moves filmed in the real city: standing at the window, running out
## and diving, catching the sill and climbing back in, vaulting in.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method mobile \
##     --resolution 960x540 --fixed-fps 30 -s res://tools/home_lab.gd -- <outdir> [home id]

var world: CityWorld
var player: Player
var rig: CharacterRig
var hs: HomeSystem
var cam: Camera3D
var out := ""
var h: Dictionary


class _Drive:
	extends RefCounted
	var move := Vector3.ZERO
	var human_steer := true
	func drive(_p, _dt) -> Dictionary:
		return {"move": move, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "screenshots/home_lab"
	DirAccess.make_dir_recursive_absolute(out)
	var atmo := Atmosphere.new()
	root.add_child(atmo)
	atmo.hour = 16.5
	world = CityWorld.new()
	root.add_child(world)
	player = Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	root.add_child(player)
	rig = CharacterRig.new()
	player.add_child(rig)
	rig.set_player(player)
	var rope := RopeVisual.new()
	root.add_child(rope)
	rope.player = player
	rope.hand = rig.launcher
	hs = HomeSystem.new()
	root.add_child(hs)
	hs.setup(player, rig, world.layout)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 2400.0
	root.add_child(cam)
	cam.make_current()
	h = hs.home_by_id(args[1] if args.size() > 1 else "city")
	world.build_all_near(Apartments.window_center(h), 700.0)
	await physics_frame
	var n := Apartments.outward(h)
	var al := Apartments.along_dir(h)
	var wc := Apartments.window_center(h)
	# 1. Standing at the window (camera behind, over the shoulder).
	hs.spawn_in(h, world, null)
	var d := _Drive.new()
	player.bot = d
	await _hold(1.2)
	_place(player.global_position - n * 2.6 + al * 0.9 + Vector3.UP * 1.1, wc + n * 40.0 - Vector3.UP * 12.0)
	await _shot("at_window")
	# 2. Run out of the window: film from outside, beside the facade.
	d.move = n
	var side := wc + n * 7.0 + al * 7.5 + Vector3.UP * 0.5
	for i in 5:
		await _hold(0.12 if i > 0 else 0.25)
		_place(side, player.global_position)
		await _shot("dive_%d" % i)
	d.move = Vector3.ZERO
	player.bot = null  # (HomeSystem leaves bots alone)
	await _hold(1.0)
	# 3. Coming back: from 1.6 m out, a little below the sill → grab, climb.
	var a := (float(h["oa0"]) + float(h["oa1"])) * 0.5
	player.respawn(Apartments.face_point(h, a, 1.6, float(h["oy0"]) - 0.6) + Vector3.UP * 0.9)
	player.s.velocity = -n * 4.0 + Vector3.UP * 1.0
	var view := Apartments.face_point(h, a, 4.5, float(h["oy0"]) + 0.6) + al * 3.2
	for i in 8:
		await _hold(0.11)
		_place(view, player.global_position + Vector3.UP * 0.3)
		await _shot("climb_%d" % i)
	# 4. Vault in from a fast approach.
	player.respawn(Apartments.face_point(h, a, 3.0, float(h["oy0"]) + 0.3) + Vector3.UP * 0.9)
	player.s.velocity = -n * 12.0
	for i in 4:
		await _hold(0.09)
		_place(view, player.global_position + Vector3.UP * 0.3)
		await _shot("vault_%d" % i)
	print("HOME_LAB done")
	quit()


func _hold(s: float) -> void:
	var t := 0.0
	while t < s:
		await process_frame
		t += 1.0 / 30.0


func _place(p: Vector3, look: Vector3) -> void:
	cam.global_position = p
	cam.look_at(look, Vector3.UP)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
