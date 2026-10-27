extends Node3D
## Composition root and game-state machine:
##   TITLE (attract-mode autopilot swings behind the menu) → PLAYING → PAUSED
##   → RESULTS → PLAYING/TITLE.
## Command-line user args (after `--`), used by tools and automated captures:
##   --world=prototype|city   --mode=free|endurance|trial:<course>
##   --bot=expert|novice   --shot=<png> --shot-at=<s,s,...>   --quality=0|1|2
##   --perf   --touch   --cam=x,y,z,lx,ly,lz [--fov=deg]   --menu=<screen>

enum State { TITLE, PLAYING, PAUSED, RESULTS }

var world_kind := "city"
var state := State.TITLE
var player: Player
var camera: SwingCamera
var rig: CharacterRig
var rope: RopeVisual
var hud: Hud
var touch: TouchControls
var menus: Menus
var audio: AudioDirector
var atmosphere: Atmosphere
var world: Node3D
var mode: GameMode
var ui: CanvasLayer
var args := {}
var _last_mode := ["free", ""]


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
	if args.has("seed"):
		_spawn_rng.seed = int(args["seed"])  # reproducible spawns for captures/tests
	else:
		_spawn_rng.randomize()

	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	world = PrototypeWorld.new() if world_kind == "prototype" else CityWorld.new()
	world.name = "World"
	add_child(world)
	if world.has_method("set_sky_colors"):
		world.set_sky_colors(Atmosphere.ZENITH, Atmosphere.HORIZON)

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = world.spawn_point()
	player.last_safe_position = player.global_position
	if world.has_method("build_all_near"):
		var t0 := Time.get_ticks_msec()
		world.build_all_near(player.global_position, 420.0)
		print("Initial city build: %d chunks in %d ms" % [world.loaded_chunk_count(), Time.get_ticks_msec() - t0])

	rig = CharacterRig.new()
	rig.name = "Rig"
	player.add_child(rig)
	rig.set_player(player)
	rope = RopeVisual.new()
	rope.name = "Rope"
	add_child(rope)
	rope.player = player
	rope.hand = rig.launcher
	camera = SwingCamera.new()
	camera.name = "CameraRig"
	add_child(camera)
	camera.set_target(player)
	if world.has_method("set_viewer"):
		world.set_viewer(camera)
	audio = AudioDirector.new()
	audio.name = "Audio"
	add_child(audio)
	audio.attach_player(player)

	ui = CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	ui.add_child(hud)
	hud.player = player
	hud.camera = camera
	touch = TouchControls.new()
	ui.add_child(touch)
	touch.camera = camera
	touch.player = player
	touch.web_feedback.connect(hud.web_feedback)
	hud.touch_mode = DisplayServer.is_touchscreen_available() or args.has("touch")
	touch.pause_pressed.connect(pause)
	menus = Menus.new()
	ui.add_child(menus)
	menus.params = player.params
	menus.start_mode.connect(start_mode)
	menus.resume.connect(unpause)
	menus.restart.connect(func(): start_mode(_last_mode[0], _last_mode[1]))
	menus.quit_to_title.connect(to_title)
	Settings.changed.connect(_apply_settings)

	if args.has("cam"):
		_overview_camera()
	if args.has("closeup"):
		camera.distance_scale = 0.55
	if args.has("mode"):
		var m := String(args["mode"]).split(":")
		start_mode(m[0], m[1] if m.size() > 1 else "")
	else:
		to_title()
	if args.has("bot"):
		_attract(SwingBot.Style.NOVICE if args["bot"] == "novice" else SwingBot.Style.EXPERT)
	if args.has("menu"):
		match args["menu"]:
			"settings": menus.show_settings(menus.show_title)
			"courses": menus.show_courses()
			"tuning": menus.show_tuning()
			"pause": menus.show_pause()
	if args.has("nohud"):
		ui.visible = false
	if args.has("selftest"):
		_selftest.call_deferred()
	if args.has("shot"):
		var times: Array[float] = []
		for x in String(args.get("shot-at", "3.0")).split(","):
			times.append(float(x))
		_capture_series(args["shot"], times)


# --------------------------------------------------------------- states
func to_title() -> void:
	get_tree().paused = false
	_end_mode()
	state = State.TITLE
	hud.mode_text = ""
	hud.mode_sub = ""
	hud.visible = false
	touch.visible = false
	_attract(SwingBot.Style.EXPERT)
	menus.show_title()


func start_mode(kind: String, arg: String) -> void:
	get_tree().paused = false
	_end_mode()
	_last_mode = [kind, arg]
	player.bot = null
	player.input_enabled = true
	match kind:
		"trial":
			var tt := TimeTrialMode.new()
			_install(tt)
			tt.setup_course(CourseBuilder.load_course(arg))
			mode = tt
		"endurance":
			mode = EnduranceMode.new()
			_install(mode)
			player.respawn(world.spawn_point())
		"benchmark":
			mode = BenchmarkMode.new()
			_install(mode)
		_:
			mode = FreeSwingMode.new()
			_install(mode)
			spawn_on_random_rooftop()
	mode.finished.connect(_on_finished)
	mode.start()
	state = State.PLAYING
	menus.hide_all()
	hud.visible = true
	touch.visible = DisplayServer.is_touchscreen_available() or args.has("touch")
	camera.snap()


var _spawn_rng := RandomNumberGenerator.new()
var _last_spawn := Vector3.INF


## Free Swing starts on a random valid rooftop, facing a promising route.
## Building collision always exists, so the spawn is safe immediately; the
## visible chunks around it are meshed before the first frame.
func spawn_on_random_rooftop() -> Dictionary:
	if not world.has_method("random_rooftop"):
		return {}
	var spot: Dictionary = world.random_rooftop(_spawn_rng, _last_spawn)
	_last_spawn = spot["position"]
	world.build_all_near(spot["position"], 420.0)
	player.respawn(spot["position"])
	player.last_safe_position = spot["position"]
	var dir := Vector3.FORWARD.rotated(Vector3.UP, spot["yaw"])
	rig.set_facing(dir)
	camera.face(spot["yaw"])
	return spot


func _install(m: GameMode) -> void:
	m.name = "Mode"
	add_child(m)
	m.setup(player, hud, audio, world)


func _end_mode() -> void:
	if mode:
		if mode is TimeTrialMode:
			(mode as TimeTrialMode).abandon()
		mode.queue_free()
		mode = null


func pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	get_tree().paused = true
	touch.visible = false
	menus.show_pause()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func unpause() -> void:
	state = State.PLAYING
	get_tree().paused = false
	menus.hide_all()
	touch.visible = DisplayServer.is_touchscreen_available() or args.has("touch")


func _on_finished(result: Dictionary) -> void:
	state = State.RESULTS
	touch.visible = false
	player.input_enabled = false
	menus.show_results(result)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Title screen backdrop: the autopilot swings through the city.
func _attract(style: int) -> void:
	var bot := SwingBot.new(style, Vector3.FORWARD)
	if world.has_method("bot_goal"):
		bot.goal_fn = world.bot_goal
	player.bot = bot


func _apply_settings() -> void:
	var p := Settings.preset()
	if atmosphere and atmosphere.sun:
		atmosphere.sun.shadow_enabled = p["shadows"]
	if atmosphere and atmosphere.env:
		atmosphere.env.glow_enabled = p["glow"]


func _process(_dt: float) -> void:
	if Input.is_action_just_pressed("toggle_debug"):
		Settings.show_perf = not Settings.show_perf


func _unhandled_input(event: InputEvent) -> void:
	if state == State.PLAYING:
		if event is InputEventMouseButton and event.pressed and not DisplayServer.is_touchscreen_available():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if event.is_action_pressed("pause"):
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			pause()
	elif state == State.PAUSED and event.is_action_pressed("pause"):
		unpause()


func _notification(what: int) -> void:
	# Leaving the app (home button, call) pauses a run.
	if OS.has_feature("mobile") and (what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED):
		pause()


## Export validation: confirms the packaged build loaded everything it needs.
func _selftest() -> void:
	await get_tree().process_frame
	var problems: Array[String] = []
	var courses := 0
	for id in CourseBuilder.COURSES:
		if not CourseBuilder.load_course(id).is_empty():
			courses += 1
	if courses != CourseBuilder.COURSES.size():
		problems.append("courses %d/%d" % [courses, CourseBuilder.COURSES.size()])
	var sounds := audio._shots.size() + audio._loops.size()
	if sounds != AudioDirector.SHOTS.size() + AudioDirector.LOOPS.size():
		problems.append("audio %d/%d" % [sounds, AudioDirector.SHOTS.size() + AudioDirector.LOOPS.size()])
	var props: int = world.prop_meshes.size() if world is CityWorld else -1
	if world is CityWorld and props < 11:
		problems.append("kit meshes %d/11" % props)
	if (rig.bones["chest"] as Node3D).get_child_count() == 0 or not ResourceLoader.exists(CharacterRig.MODEL_PATH):
		problems.append("character model")
	for sh in ["building", "ground", "water", "sky", "traffic"]:
		if not ResourceLoader.exists("res://src/world/shaders/%s.gdshader" % sh):
			problems.append("shader " + sh)
	print("SELFTEST courses=%d sounds=%d kit=%d renderer=%s %s" % [courses, sounds, props,
		ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"OK" if problems.is_empty() else "FAIL " + ", ".join(problems)])
	get_tree().quit(0 if problems.is_empty() else 1)


# ------------------------------------------------------------- captures
func _overview_camera() -> void:
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
