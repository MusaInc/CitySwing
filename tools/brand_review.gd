extends SceneTree
## Exercise the real startup -> title -> main menu -> Play path and capture
## rendered frames. Use --headless for an input/transition smoke test only.

var failed := false
var out := "res://docs/qa/branding"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--brand-out="):
			out = arg.trim_prefix("--brand-out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var boot: Node = load("res://scenes/boot.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	await process_frame
	await _capture("loading")
	var deadline := Time.get_ticks_msec() + 120000
	while is_instance_valid(boot) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not is_instance_valid(boot), "launch overlay removed after loading")
	var game := root.get_node_or_null("Main")
	if game == null:
		_check(false, "main scene loaded")
		quit(1)
		return
	_check(current_scene == game, "game becomes the active scene")
	await create_timer(1.0).timeout
	_check(game.menus.screen_name == "splash", "live title appears first")
	await _capture("start")
	# Real UI input: focus/accept must reach the start button after the overlay.
	Input.action_press("ui_accept")
	await process_frame
	Input.action_release("ui_accept")
	# Inject UI events as well: action_press alone affects polling, not Controls.
	var down := InputEventAction.new()
	down.action = "ui_accept"
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventAction.new()
	up.action = "ui_accept"
	up.pressed = false
	Input.parse_input_event(up)
	await create_timer(0.4).timeout
	_check(game.menus.screen_name == "title", "keyboard start opens main menu")
	await _capture("menu")
	if game.menus._buttons.has("free"):
		var button: Button = game.menus._buttons["free"]
		var mouse := InputEventMouseButton.new()
		mouse.position = button.get_global_rect().get_center()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = true
		Input.parse_input_event(mouse)
		await process_frame
		mouse = mouse.duplicate()
		mouse.pressed = false
		Input.parse_input_event(mouse)
		await create_timer(1.0).timeout
		_check(game.state == game.State.PLAYING, "pointer Play enters gameplay")
	else:
		_check(false, "Play button available")
	print("BRANDING_SMOKE ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _capture(name_: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(out.path_join(name_ + ".png"))
	_check(err == OK, "captured " + name_)


func _check(ok: bool, message: String) -> void:
	print("  ", "PASS " if ok else "FAIL ", message)
	failed = failed or not ok
