extends Node
## Frame-hitch probe: logs per-frame main-thread time during real play and
## names the slow frames. Added by main.gd for --hitchprobe=<seconds>.
##   godot --headless -- --mode=free --bot=expert --seed=3 --hitchprobe=40
var duration := 40.0
var _t := 0.0
var _times: PackedFloat64Array = []
var _last := 0
var _spikes: Array = []
var _dists: PackedFloat64Array = []
var _fovs: PackedFloat64Array = []

func _ready() -> void:
	process_priority = -1000
	_last = Time.get_ticks_usec()

func _process(dt: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last) / 1000.0
	_last = now
	_t += dt
	if _t > 3.0:  # skip load
		_times.append(ms)
		var m := get_parent()
		if m.camera and m.player and not m.player.is_on_floor():
			_dists.append(m.camera.cam.global_position.distance_to(m.player.global_position + Vector3.UP * 0.9))
			_fovs.append(m.camera.cam.fov)
		if ms > 33.0:
			var w = get_parent().get("world")
			_spikes.append("t=%.1f %.1fms chunks=%s" % [_t, ms, str(w.loaded_chunk_count()) if w and w.has_method("loaded_chunk_count") else "?"])
	if _t >= duration:
		var s := _times.duplicate(); s.sort()
		var n := s.size()
		var sum := 0.0
		for v in s: sum += v
		print("HITCH frames=%d mean=%.2fms p50=%.2f p95=%.2f p99=%.2f max=%.2f over33=%d over100=%d" % [n, sum / n,
			s[n / 2], s[int(n * 0.95)], s[int(n * 0.99)], s[n - 1], _spikes.size(), _count_over(s, 100.0)])
		for line in _spikes.slice(0, 25): print("  SPIKE ", line)
		if _dists.size() > 0:
			var d := _dists.duplicate(); d.sort()
			var f := 0.0
			for v in _fovs: f += v
			print("CAMDIST airborne n=%d p25=%.2f p50=%.2f p75=%.2f fov_mean=%.1f" % [d.size(), d[d.size() / 4], d[d.size() / 2], d[d.size() * 3 / 4], f / _fovs.size()])
		get_tree().quit()


func _count_over(a: PackedFloat64Array, lim: float) -> int:
	var c := 0
	for v in a:
		if v > lim: c += 1
	return c
