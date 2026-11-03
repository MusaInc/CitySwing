extends SceneTree
## Repeatable, live-engine city review; road cameras follow the generated plan.
var main: Node3D
var cam: Camera3D
var out := "screenshots/cleanup/before"
var records: Array = []

func _initialize() -> void:
	go.call_deferred()

func go() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			out = arg.trim_prefix("--review-out=")
	DirAccess.make_dir_recursive_absolute(out)
	root.get_node("SaveData").use_file("user://cleanup_review_save.json")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.camera.set_process(false)
	main.camera.set_physics_process(false)
	main.ui.visible = false
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 6500.0
	root.add_child(cam)
	cam.make_current()
	var world: CityWorld = main.world
	world.view_distance = 2400.0
	world.mainland.view_distance = 2400.0
	world.build_all_near(Vector3(350, 0, 0), 2200.0)
	world.set_viewer(cam)
	await shot("overview", Vector3(80, 420, 780), Vector3(530, 30, -60))
	await shot("bridge", Vector3(-155, 48, 100), Vector3(85, 20, -17))
	await shot("bridge_landing", Vector3(-15, 28, -17), Vector3(220, 24, -30))
	await shot("quay", Vector3(36, 4, 125), Vector3(40, 5, -80))
	for entry in [["cbd", "diagonal", 440.0], ["oldtown", "crescent", 240.0], ["rail", "valley", 400.0], ["heights", "heights", 220.0]]:
		var samples := world.layout.roads.along(entry[1], 12.0, entry[2], entry[2] + 36.0)
		if samples.size() < 2:
			continue
		var p: Vector2 = samples[0]
		var q: Vector2 = samples[-1]
		var y := world.layout.terrain.road_y(p.x, p.y)
		await shot(entry[0], Vector3(p.x, y + 3.2, p.y), Vector3(q.x, y + 9, q.y))
	await shot("coast", Vector3(1150, 65, 150), Vector3(950, 20, -30))
	await shot("docks", Vector3(110, 110, 580), Vector3(320, 0, 340))
	await shot("westbank", Vector3(-360, 90, 180), Vector3(-720, 20, -30))
	for home_id in ["city", "penthouse"]:
		main.spawn_at_home(home_id, true)
		cam.current = false
		main.camera.cam.make_current()
		main.camera.set_process(true)
		main.camera.set_physics_process(true)
		main.ui.visible = true
		for i in 12:
			await process_frame
		await save_frame("home_" + home_id)
	FileAccess.open(out + "/metrics.json", FileAccess.WRITE).store_string(JSON.stringify(records, "\t"))
	main.queue_free()
	cam.queue_free()
	await process_frame
	await process_frame
	quit()

func shot(label: String, pos: Vector3, target: Vector3) -> void:
	cam.position = pos
	cam.look_at(target)
	for i in 4:
		await process_frame
	await save_frame(label)

func save_frame(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + label + ".png")
	records.append({"view": label,
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"texture_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0})
	print("REVIEW ", label)
