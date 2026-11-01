extends SceneTree
## Captures the shipped hero in the real city, using Player, CharacterRig,
## HomeSystem, collision and rope simulation. No alternate render-only model.
var main: Node3D
var player: Player
var cam: Camera3D
var out := "screenshots/courier/city"
var records: Array = []

class Drive:
	extends RefCounted
	var move := Vector3.ZERO
	var human_steer := true
	func drive(_p, _dt) -> Dictionary:
		return {"move": move, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}

func _initialize() -> void:
	go.call_deferred()

func go() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	player = main.player
	main.ui.visible = false
	main.camera.set_process(false)
	main.camera.set_physics_process(false)
	cam = Camera3D.new()
	cam.fov = 46.0
	cam.far = 2000.0
	root.add_child(cam)
	cam.make_current()
	var drive := Drive.new()
	player.bot = drive
	var world := main.world as CityWorld
	var spot: Vector3 = world.spawn_point()
	world.build_all_near(spot, 600.0)
	player.respawn(spot)
	main.rig.set_facing(Vector3.FORWARD)
	await hold(0.65)
	for view in [["front", Vector3(0.3, 0.15, -3.0)], ["rear", Vector3(-0.4, 0.35, 3.0)], ["side", Vector3(3.0, 0.25, 0.3)]]:
		await shot(view[0], view[1])
	# Running on the same real rooftop.
	drive.move = Vector3.RIGHT
	await hold(0.3)
	await shot("running", Vector3(-1.6, 0.3, 3.0))
	drive.move = Vector3.ZERO
	# Drop onto that roof; capture physical contact and recovery.
	player.respawn(spot + Vector3.UP * 5.0)
	player.s.velocity = Vector3(0, -8, 0)
	var landed := false
	for i in 70:
		await process_frame
		follow(Vector3(2.4, 0.3, -2.5))
		if player.is_on_floor():
			landed = true
			break
	await hold(0.08)
	await shot("landing", Vector3(2.4, 0.3, -2.5))
	print("CITY_LANDING floor=", landed)
	# Choose a real tower face near the core; approach tangentially in open air.
	var chosen: Dictionary = {}
	var score := INF
	for b in world.layout.buildings:
		if b.kind != "normal":
			continue
		var t: Array = b.tiers[-1]
		var height: float = t[5] - BuildingMesher.base_of(b)
		var center := CityLayout.top_center(b)
		var distance := Vector2(center.x, center.z).distance_to(CityLayout.CBD_CENTER)
		if height > 95.0 and height < 180.0 and distance < score:
			score = distance
			chosen = b
	if not chosen.is_empty():
		var tier: Array = chosen.tiers[-1]
		var transform := CityLayout.bxf(chosen)
		var local_anchor := Vector3((tier[0] + tier[2]) * 0.5, tier[5] - 6.0, tier[3])
		var anchor := transform * local_anchor
		var outward := transform.basis * Vector3.BACK
		var along := transform.basis * Vector3.RIGHT
		var start := anchor + outward * 19.0 - along * 13.0 - Vector3.UP * 23.0
		world.build_all_near(start, 600.0)
		player.respawn(start)
		player.s.velocity = along * 15.0
		await physics_frame
		player.fire_at(anchor, 1)
		for i in 3:
			await hold(0.23)
			await shot("swing_%d" % i, outward * 3.5 - along * 1.8 + Vector3.UP * 0.6)
		print("CITY_SWING attached=", player.line_state == Player.Line.ATTACHED)
	# The starter home uses the same hero and physically embedded room.
	main.spawn_at_home("city", true)
	player.bot = drive
	await hold(0.4)
	var home: Dictionary = main.homes.home_by_id("city")
	var normal := Apartments.outward(home)
	await shot("window", -normal * 2.9 + Apartments.along_dir(home) * 0.8 + Vector3.UP * 0.4)
	var file := FileAccess.open(out + "/render_metrics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	print("CITY_HERO_CAPTURE_COMPLETE")
	main.queue_free()
	cam.queue_free()
	await process_frame
	await process_frame
	quit()

func hold(seconds: float) -> void:
	for i in int(ceil(seconds * 30.0)):
		await process_frame
		follow(Vector3(2.4, 0.4, 3.0))

func follow(offset: Vector3) -> void:
	cam.global_position = player.global_position + offset
	cam.look_at(player.global_position + Vector3.UP * 0.08)

func shot(label: String, offset: Vector3) -> void:
	follow(offset)
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out + "/" + label + ".png")
	records.append({"frame": label, "position": str(player.position), "on_floor": player.is_on_floor(),
		"line_state": player.line_state, "speed": player.speed(),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"texture_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)})
	print("CITY_HERO_SHOT ", label)
