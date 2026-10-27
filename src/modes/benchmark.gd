class_name BenchmarkMode
extends GameMode
## On-device performance benchmark: the autopilot flies a fixed 45 s route
## through the densest part of the city (same start, same inputs every run)
## while frame times and render stats are recorded. Results are shown and
## appended to user://benchmark.json so device runs can be compared.

const DURATION := 45.0
const WARMUP := 3.0

var frame_ms: Array[float] = []
var draw_calls := 0.0
var prims := 0.0
var samples := 0
var cpu_process := 0.0
var cpu_physics := 0.0


func mode_name() -> String:
	return "Benchmark"


func start() -> void:
	super.start()
	var route := CourseBuilder.route("canyon", world.layout)
	player.respawn(route["start"])
	var follower := RouteFollower.new(route["waypoints"])
	set_meta("follower", follower)  # Callables don't keep RefCounted targets alive
	var bot := SwingBot.new(SwingBot.Style.EXPERT, Vector3.FORWARD)
	bot.goal_fn = follower.goal
	player.bot = bot
	hud.flash("BENCHMARK", 1.5)


func _process(dt: float) -> void:
	if not running:
		return
	var t := elapsed
	hud.mode_text = "%d s" % int(DURATION - t)
	hud.mode_sub = "measuring frame times – hands off"
	if t < WARMUP:
		return
	frame_ms.append(dt * 1000.0)
	draw_calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	cpu_process += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	cpu_physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	samples += 1
	if t >= DURATION:
		_finish()


func _finish() -> void:
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var n := sorted.size()
	var total := 0.0
	for f in sorted:
		total += f
	var avg := total / maxf(n, 1)
	var p99: float = sorted[int(n * 0.99)] if n > 0 else 0.0
	var worst: float = sorted[-1] if n > 0 else 0.0
	var over_33 := 0
	for f in sorted:
		if f > 34.0:
			over_33 += 1
	var result := {
		"mode": "benchmark", "device": OS.get_model_name(), "os": OS.get_name() + " " + OS.get_version(),
		"renderer": RenderingServer.get_video_adapter_name(), "quality": ["low", "medium", "high"][Settings.quality],
		"target_fps": Engine.max_fps, "avg_fps": 1000.0 / maxf(avg, 0.001), "avg_ms": avg, "p99_ms": p99,
		"worst_ms": worst, "frames_over_33ms": over_33, "frames": n,
		"avg_draw_calls": draw_calls / maxf(samples, 1), "avg_prims": prims / maxf(samples, 1),
		"cpu_process_ms": cpu_process / maxf(samples, 1), "cpu_physics_ms": cpu_physics / maxf(samples, 1),
		"time": Time.get_datetime_string_from_system(),
	}
	_append(result)
	print("BENCHMARK ", JSON.stringify(result))
	player.bot = null
	end_run(result)


static func _append(r: Dictionary) -> void:
	var path := "user://benchmark.json"
	var runs: Array = []
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Array:
			runs = parsed
	runs.append(r)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(runs, "  "))
