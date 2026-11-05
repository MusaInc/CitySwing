extends SceneTree
## Brand art from the real game: the actual hero (CharacterRig, default
## courier look) flown by the real swing physics on a real web, filmed on a
## transparent background with a studio key + rim light. Frames feed the app
## icon, emblem and title art (tools/brand/*.html), so the brand shows exactly
## the character and moves the game has.
##   xvfb-run -a -s "-screen 0 1400x1400x24" godot --rendering-method mobile \
##     --resolution 1024x1024 --fixed-fps 60 -s res://tools/brand/hero_render.gd -- <outdir>

var player: Player
var rig: CharacterRig
var rope: RopeVisual
var cam: Camera3D
var key: DirectionalLight3D
var rim: DirectionalLight3D
var out_dir := ""


class _Idle:
	extends RefCounted
	func drive(_p, _dt) -> Dictionary:
		return {"move": Vector3.ZERO, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "screenshots/brand_hero"
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_root().transparent_bg = true
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.55)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	# Warm low sun from front-left (the game's golden hour) and a cool sky fill.
	key = DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.93, 0.84)
	key.light_energy = 1.1
	key.rotation_degrees = Vector3(-25, -35, 0)
	root.add_child(key)
	rim = DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.78, 0.3)  # Signal Gold rim from behind
	rim.light_energy = 4.0
	rim.rotation_degrees = Vector3(-5, 160, 0)
	root.add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.65, 1.0)
	fill.light_energy = 0.5
	fill.rotation_degrees = Vector3(-60, 60, 0)
	root.add_child(fill)
	# Invisible collision stage (the anchor tower) – never drawn.
	var stage := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(16, 200, 16)
	cs.shape = bx
	stage.add_child(cs)
	stage.position = Vector3(0, 0, -60)
	root.add_child(stage)
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
	cam.fov = 30.0
	root.add_child(cam)
	cam.make_current()
	await physics_frame
	# Swing: drop in moving sideways, web to a high anchor ahead, film the arc.
	var views := {
		"low34": Vector3(3.2, -1.6, 3.4),   # low three-quarter front: heroic, looking up
		"low34b": Vector3(2.4, -2.2, 3.8),
	}
	for vname in views:
		player.bot = _Idle.new()
		player.respawn(Vector3(-25, 120, -20))
		player.s.velocity = Vector3(16, 0, 0)
		rig.set_facing(Vector3.RIGHT)
		player.fire_at(Vector3(0, 150, -34.0), 1)
		var t := 0.0
		var k := 0
		var shots := [0.95, 1.05, 1.15, 1.25]
		while k < shots.size():
			await process_frame
			t += 1.0 / 60.0
			var h := player.global_position + Vector3.UP * 0.25
			var v := player.s.velocity
			var f := Vector3(v.x, 0, v.z).normalized() if Vector3(v.x, 0, v.z).length() > 0.5 else Vector3.RIGHT
			var r := f.cross(Vector3.UP).normalized()
			var o: Vector3 = views[vname]
			cam.global_position = h + r * o.x + Vector3.UP * o.y + f * o.z  # o: (right, up, ahead)
			cam.look_at(h, Vector3.UP)
			# Rim straight from behind the hero (as the camera sees it), edging the
			# silhouette in Signal Gold; key from the camera's upper left.
			var back := (h - cam.global_position).normalized()
			rim.look_at_from_position(h + back * 10.0 + Vector3.UP * 3.0, h, Vector3.UP)
			var cl := cam.global_transform.basis
			key.look_at_from_position(cam.global_position - cl.x * 6.0 + Vector3.UP * 6.0, h, Vector3.UP)
			if t >= shots[k]:
				await RenderingServer.frame_post_draw
				var img := get_root().get_texture().get_image()
				img.save_png("%s/%s_%d.png" % [out_dir, vname, k])
				k += 1
		print("HERO %s done" % vname)
	quit()
