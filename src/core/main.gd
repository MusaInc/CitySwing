extends Node3D
## Composition root. Command-line user args (after `--`):
##   --world=prototype|city   --mode=free|trial|endurance   --bot=expert|novice
##   --shot=<png path> --shot-at=<seconds>   --quality=0|1|2   --perf

var world_kind := "prototype"
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
		world = load("res://src/world/city_world.gd").new()
	world.name = "World"
	add_child(world)

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = world.spawn_point()
	player.spawn_transform = player.global_transform
	player.last_safe_position = player.global_position

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
	if args.has("shot"):
		_capture_later(args["shot"], float(args.get("shot-at", "3.0")))


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
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.5, 0.78)
	sky_mat.sky_horizon_color = Color(0.86, 0.8, 0.74)
	sky_mat.ground_horizon_color = Color(0.7, 0.66, 0.62)
	sky_mat.ground_bottom_color = Color(0.3, 0.3, 0.32)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.76, 0.75)
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.25
	sun.shadow_enabled = Settings.preset()["shadows"]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)


func _capture_later(path: String, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SCREENSHOT ", path)
	get_tree().quit()
