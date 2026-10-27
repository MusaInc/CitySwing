extends SceneTree
## Physics-frame CPU cost: empty world vs static city vs city + swinging player.
##   godot --headless -s res://tools/cpu_physics.gd
func _initialize() -> void:
	_go.call_deferred()

func _measure(label: String, frames := 240) -> void:
	var total := 0.0
	for i in frames:
		await physics_frame
		total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	print("%-28s %.2f ms / physics tick" % [label, total / frames * 1000.0])

func _go() -> void:
	await _measure("empty")
	var w := CityWorld.new()
	root.add_child(w)
	await _measure("static city")
	var p := Player.new()
	p.params = load("res://config/swing_params.tres").duplicate()
	root.add_child(p)
	p.global_position = w.spawn_point()
	var bot := SwingBot.new(SwingBot.Style.EXPERT, Vector3.FORWARD)
	bot.goal_fn = w.bot_goal
	p.bot = bot
	await _measure("city + swinging player")
	quit()
