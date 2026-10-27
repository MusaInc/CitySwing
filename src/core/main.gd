extends Node3D
## Composition root. Command-line user args (after `--`):
##   --world=prototype|city   --mode=free|trial|endurance   --bot=expert|novice
##   --shot=<png path> --shot-at=<seconds>   --quality=0|1|2   --perf

var world_kind := "city"
var mode_name := "menu"
var player: Player
var camera: SwingCamera
var rig: CharacterRig
var rope: RopeVisual
var hud: Hud
var touch: TouchControls
var world: Node3D
var ui: CanvasLayer
var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	world_kind = args.get("world", world_kind)
	if args.has("quality"):
		Settings.quality = int(args["quality"])
	if args.has("perf"):
		Settings.show_perf = true
	Settings.apply()

	_build_environment()
	if world_kind == "prototype":
		world = PrototypeWorld.new()
	else:
		world = CityWorld.new()
	world.name = "World"
	add_child(world)
	if world.has_method("set_sky_colors"):
		world.set_sky_colors(Atmosphere.ZENITH, Atmosphere.HORIZON)

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = world.spawn_point()
	player.spawn_transform = player.global_transform
	player.last_safe_position = player.global_position
	if world.has_method("build_all_near"):
		var t0 := Time.get_ticks_msec()
		world.build_all_near(player.global_position, 420.0)
		print("Initial city build: %d chunks in %d ms" % [world.loaded_chunk_count(), Time.get_ticks_msec() - t0])

	rig = CharacterRig.new()
	rig.name = "Rig"
	player.add_child(rig)
	rig.player = player
	player.landed.connect(func(spd, _street): rig.on_landed(spd))

	rope = RopeVisual.new()
	rope.name = "Rope"
	add_child(rope)
	rope.player = player

	camera = SwingCamera.new()
	camera.name = "CameraRig"
	add_child(camera)
	camera.set_target(player)
	if world.has_method("set_viewer"):
		world.set_viewer(camera)

	ui = CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	ui.add_child(hud)
	hud.player = player
	hud.camera = camera
	touch = TouchControls.new()
	ui.add_child(touch)
	touch.camera = camera
	touch.visible = DisplayServer.is_touchscreen_available() or args.has("touch")

	if args.has("bot"):
		var style := SwingBot.Style.NOVICE if args["bot"] == "novice" else SwingBot.Style.EXPERT
		var h: Vector3 = world.call("bot_heading") if world.has_method("bot_heading") else Vector3.FORWARD
		player.bot = SwingBot.new(style, h)
		if world.has_method("bot_goal"):
			player.bot.goal_fn = world.bot_goal
	if args.has("cam"):
		# Fixed overview camera: --cam=x,y,z,look_x,look_y,look_z
		var v := String(args["cam"]).split_floats(",")
		camera.target = null
		camera.global_position = Vector3(v[0], v[1], v[2])
		camera.look_at(Vector3(v[3], v[4], v[5]), Vector3.UP)
		camera.cam.fov = float(args.get("fov", "60"))
		camera.cam.far = 4000.0
		player.input_enabled = false
		if world.has_method("build_all_near"):
			world.view_distance = 2000.0
			world.build_all_near(Vector3(v[3], 0, v[5]), 1600.0)
	if args.has("shot"):
		var times: Array[float] = []
		for x in String(args.get("shot-at", "3.0")).split(","):
			times.append(float(x))
		_capture_series(args["shot"], times)


func _process(_dt: float) -> void:
	touch.target_locked = player.targeting.has_target
	if Input.is_action_just_pressed("toggle_debug"):
		Settings.show_perf = not Settings.show_perf


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("pause") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_environment() -> void:
	var atmosphere := Atmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)


## Saves one PNG per time (path gets _<i> suffix when several), then quits.
## Times are simulated seconds, so runs under --fixed-fps are deterministic.
func _capture_series(path: String, times: Array[float]) -> void:
	var elapsed := 0.0
	for i in times.size():
		while elapsed < times[i]:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var out := path if times.size() == 1 else path.get_basename() + "_%d.png" % i
		img.save_png(out)
		print("SCREENSHOT ", out)
	get_tree().quit()
