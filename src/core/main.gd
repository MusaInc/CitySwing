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
var impact_fx: ImpactFx
var atmosphere: Atmosphere
var world: Node3D
var mode: GameMode
var ui: CanvasLayer
var args := {}
var _last_mode := ["free", ""]
var _suits_before := []  # unlocked suit ids when the current run started


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
	player.perfect_release.connect(hud.on_perfect)
	# Wall knockout: hit-stop + slow-mo, camera jolt, red flash, the slam.
	impact_fx = ImpactFx.new()
	impact_fx.name = "ImpactFx"
	add_child(impact_fx)
	player.knockout.connect(func(spd: float, _n: Vector3):
		impact_fx.knockout(spd)
		camera.shake(clampf(spd / 45.0, 0.25, 0.7))
		hud.on_knockout(spd)
		audio.play("knockout", linear_to_db(clampf(spd / 35.0, 0.5, 1.0)))
		Settings.haptic(160, 1.0))
	player.respawned.connect(func(): impact_fx.cancel())
	hud.touch_mode = DisplayServer.is_touchscreen_available() or args.has("touch")
	touch.pause_pressed.connect(pause)
	menus = Menus.new()
	ui.add_child(menus)
	menus.params = player.params
	menus.start_mode.connect(start_mode)
	menus.resume.connect(unpause)
	menus.restart.connect(func(): start_mode(_last_mode[0], _last_mode[1]))
	menus.quit_to_title.connect(to_title)
	menus.end_session.connect(func():
		if mode is FreeSwingMode:
			get_tree().paused = false
			(mode as FreeSwingMode).stop())
	menus.suit_changed.connect(func(c): rig.set_suit_color(c))
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
	if args.has("front"):
		# Character review captures: look at the hero from the front.
		camera.face(camera.yaw + PI)
		camera.base_pitch = deg_to_rad(-4.0)
		camera.pitch = camera.base_pitch
	if args.has("bot"):
		_attract(SwingBot.Style.NOVICE if args["bot"] == "novice" else SwingBot.Style.EXPERT)
	if args.has("menu"):
		match args["menu"]:
			"settings": menus.show_settings(menus.show_title)
			"courses": menus.show_courses()
			"tuning": menus.show_tuning()
			"pause": menus.show_pause()
			"suits": menus.show_suits()
	if args.has("nohud"):
		ui.visible = false
	if OS.has_feature("web"):
		_web_debug = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('debug')", true)) == "1"
		var url_seed = JavaScriptBridge.eval("new URLSearchParams(location.search).get('seed')", true)
		if url_seed != null and str(url_seed).is_valid_int():
			_spawn_rng.seed = int(str(url_seed))  # reproducible spawns for browser tests
		player.grapple_fired.connect(func(_t, _h): _webs_fired += 1)
		touch.web_feedback.connect(func(p, ok, reason):
			var vsz := get_viewport().get_visible_rect().size
			_last_tap = {"ok": ok, "reason": reason, "fired": _webs_fired, "at": [p.x / vsz.x, p.y / vsz.y]})
		if _web_debug:
			# Keeps publishing while the game is paused (menus are tested too).
			var pub := _DebugPublisher.new()
			pub.process_mode = Node.PROCESS_MODE_ALWAYS
			pub.main = self
			add_child(pub)
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
	_suits_before = Progress.unlocked_ids()
	match kind:
		"training":
			var tr := TrainingMode.new()
			tr.touch = DisplayServer.is_touchscreen_available() or args.has("touch")
			mode = tr
			_install(mode)
			spawn_on_random_rooftop()
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
	menus.show_pause(mode is FreeSwingMode)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func unpause() -> void:
	state = State.PLAYING
	get_tree().paused = false
	menus.hide_all()
	touch.visible = DisplayServer.is_touchscreen_available() or args.has("touch")


func _on_finished(result: Dictionary) -> void:
	result["unlocks"] = Progress.newly_unlocked(_suits_before)
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


var _web_debug := false
var _web_debug_t := 0.0
var _webs_fired := 0
var _last_tap := {}


## Where the next web is aimed, as signed horizontal angles (degrees, + =
## right of the camera): the wanted heading (stick steering) and the pick.
func _web_aim_state(cam: Camera3D) -> Dictionary:
	var t := player.targeting
	var fwd := -cam.global_basis.z
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	var side := func(v: Vector3) -> float:
		var h := Vector3(v.x, 0.0, v.z).normalized()
		return rad_to_deg(atan2(fwd.cross(h).y * -1.0, fwd.dot(h)))
	var out := {"heading_side": snappedf(side.call(t.heading), 0.1), "pick_ok": t.pick_ok,
		"pick_gain": snappedf(t.pick_gain, 0.1)}
	if t.pick_ok:
		out["pick_side"] = snappedf(side.call(t.pick - player.global_position), 0.1)
	return out


## Web builds opened with ?debug=1 publish game state to window.__cs so a
## browser test can check that taps attach where they land. Off otherwise.
func _publish_web_state(dt: float) -> void:
	_web_debug_t += dt
	if _web_debug_t < 0.25:
		return
	_web_debug_t = 0.0
	var vs := get_viewport().get_visible_rect().size
	var cam := camera.cam
	var anchor_frac := []
	if player.line_state != Player.Line.IDLE:
		var a := player.rope_anchor() if player.line_state == Player.Line.ATTACHED else player.line_target
		if not cam.is_position_behind(a):
			var sp := cam.unproject_position(a) / vs
			anchor_frac = [sp.x, sp.y]
	var suggest := []
	var invalid := []
	if state == State.PLAYING:
		# Any pixel that is robustly not a valid target (sky / too far / street):
		# its neighbours give the same verdict.
		for y in range(int(vs.y * 0.04), int(vs.y * 0.9), 40):
			for x in range(int(vs.x * 0.45), int(vs.x * 0.95), 48):
				var r := player.screen_target(cam, Vector2(x, y))
				if r["ok"]:
					continue
				var same := true
				for d in [Vector2(20, 0), Vector2(-20, 0), Vector2(0, 20), Vector2(0, -20)]:
					if player.screen_target(cam, Vector2(x, y) + d)["reason"] != r["reason"]:
						same = false
						break
				if same:
					invalid = [x / vs.x, y / vs.y, r["reason"]]
					break
			if not invalid.is_empty():
				break
	if state == State.PLAYING and player.line_state == Player.Line.IDLE:
		# A pixel well inside a valid surface (its neighbours are valid too), so
		# it stays valid while the camera settles.
		for y in range(int(vs.y * 0.2), int(vs.y * 0.6), 24):
			for x in range(int(vs.x * 0.5), int(vs.x * 0.85), 32):
				var ok := true
				for d in [Vector2.ZERO, Vector2(20, 0), Vector2(-20, 0), Vector2(0, 20), Vector2(0, -20)]:
					if not player.screen_target(cam, Vector2(x, y) + d)["ok"]:
						ok = false
						break
				if ok:
					suggest = [x / vs.x, y / vs.y]
					break
			if not suggest.is_empty():
				break
	var st := {"state": ["title", "playing", "paused", "results"][state], "line": player.line_state,
		"swings": player.swings, "speed": player.speed(), "anchor": anchor_frac, "suggest": suggest, "invalid": invalid, "last_tap": _last_tap,
		"touch_web": player.web_touch_id, "stunned": player.stunned, "fps": Engine.get_frames_per_second(),
		"webs_fired": _webs_fired, "look_yaw": camera.look_yaw, "y": player.global_position.y,
		"grounded": player.is_on_floor(),
		"cam_yaw": camera.yaw, "player_y": player.global_position.y,
		"target_ready": player.targeting.has_target, "armed": player._armed_touch != -1,
		"rig": rig.debug_state(), "web": _web_aim_state(cam)}
	JavaScriptBridge.eval("window.__cs = %s" % JSON.stringify(st), true)


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


class _DebugPublisher:
	extends Node
	var main: Node
	func _process(dt: float) -> void:
		main._publish_web_state(dt)
