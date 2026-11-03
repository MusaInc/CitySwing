extends SceneTree
var main: Node3D
var out := "screenshots/cleanup/gameplay"
var failures := 0
func _initialize() -> void:
	go.call_deferred()
func check(ok: bool, message: String) -> void:
	print("GAMEPLAY ", "PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1
func go() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			out = arg.trim_prefix("--review-out=")
	DirAccess.make_dir_recursive_absolute(out)
	root.get_node("SaveData").use_file("user://cleanup_gameplay_save.json")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 12:
		await process_frame
	main.spawn_on_random_rooftop()
	main.player.bot = null
	for i in 8:
		await process_frame
	var before_tokens: int = root.get_node("SaveData").data.get("tokens", []).size()
	main.touch.touch_down(17, main.hud.home_rect().get_center())
	for i in 28:
		await process_frame
	check(main.homes.inside() == Homes.selected(), "home button returns to selected apartment")
	check(main.player.line_state == Player.Line.IDLE, "home tap does not fire a web")
	check(main.touch.touches.is_empty(), "teleport releases all touch roles")
	check(root.get_node("SaveData").data.get("tokens", []).size() == before_tokens, "teleport collects no route tokens")
	for viewport_size in [Vector2i(1520, 720), Vector2i(1024, 768)]:
		root.size = viewport_size
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		check(capture.get_size() == viewport_size, "capture has requested pixel dimensions %s" % viewport_size)
		capture.save_png(out + "/hud_%dx%d.png" % [viewport_size.x, viewport_size.y])
		var r: Rect2 = main.hud.home_rect()
		check(Rect2(Vector2.ZERO, main.hud.size).encloses(r), "home button within viewport %s" % viewport_size)
		check(r.size.x >= 48 and r.size.y >= 48, "home button retains a comfortable touch target")
	# Actual Player simulation above a rooftop, with a controlled overhead anchor.
	var spot := (main.world as CityWorld).spawn_point()
	main.player.respawn(spot + Vector3.UP * 32)
	main.player.s.velocity = Vector3.ZERO
	main.player.input_enabled = false
	var anchor: Vector3 = main.player.hand_position() + Vector3.UP * 35
	main.player.line_target = anchor
	main.player.line_state = Player.Line.ATTACHED
	SwingPhysics.attach(main.player.s, anchor, main.player.params)
	main.player.s.taut = true
	main.player._attach_length = main.player.s.rope_length
	var start: float = main.player.global_position.y
	for i in 90:
		await process_frame
	check(main.player.global_position.y > start + 8, "in-engine automatic hold climbs")
	check(main.player.s.velocity.y > 2, "climb carries upward velocity")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/web_climb.png")
	main.player._let_go()
	check(main.player.line_state == Player.Line.IDLE, "release detaches immediately")
	main.queue_free()
	await process_frame
	await process_frame
	quit(failures)
