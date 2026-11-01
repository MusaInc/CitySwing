extends RefCounted
## Launch lifecycle regression: background scene load, retry and duplicate input.


func test_retry_loads_one_scene_and_releases_overlay(t) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var previous := tree.current_scene
	var fixture := Node.new()
	fixture.name = "StartupFixture"
	var packed := PackedScene.new()
	packed.pack(fixture)
	fixture.free()
	var path := "user://startup_fixture.tscn"
	t.check(ResourceSaver.save(packed, path) == OK, "create temporary scene")
	var boot: Node = load("res://scenes/boot.tscn").instantiate()
	boot.auto_start = false
	boot.scene_path = path
	tree.root.add_child(boot)
	await tree.process_frame
	boot._failed()
	t.check(boot.retry.visible and not boot.progress.visible, "failure provides a usable retry")
	t.check(boot.retry.has_focus(), "retry is accessible to keyboard/controller")
	boot.retry.pressed.emit()
	boot._begin()  # rapid second activation must not schedule a second scene
	var deadline := Time.get_ticks_msec() + 10000
	while is_instance_valid(boot) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	t.check(not is_instance_valid(boot), "loading overlay is removed after transition")
	var matches := 0
	var loaded: Node
	for child in tree.root.get_children():
		if child.name == "StartupFixture":
			matches += 1
			loaded = child
	t.check(matches == 1, "one game scene despite duplicate activation")
	t.check(loaded != null and tree.current_scene == loaded, "new scene becomes current")
	tree.current_scene = previous
	if is_instance_valid(loaded):
		loaded.queue_free()
	if is_instance_valid(boot):
		boot.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
