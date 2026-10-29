extends SceneTree
## Main-thread cost of putting one streamed chunk into the scene (the part
## that can cause a frame spike while travelling fast) plus worker-side
## generation, averaged over the 16 densest chunks.
##   godot --headless -s res://tools/chunk_cost.gd
func _initialize() -> void:
	_go.call_deferred()

func _go() -> void:
	var w = load("res://src/world/city_world.gd").new()
	root.add_child(w)
	await process_frame
	var keys: Array = w._all_keys.duplicate()
	keys.sort_custom(func(a, b): return w._by_chunk.get(a, []).size() > w._by_chunk.get(b, []).size())
	keys = keys.slice(0, 16)
	var gen := 0
	var inst := 0
	var worst := 0
	for k in keys:
		var t0 := Time.get_ticks_usec()
		var res: Dictionary = w.generate_chunk_arrays(k)
		var t1 := Time.get_ticks_usec()
		w._instantiate(k, res)
		var t2 := Time.get_ticks_usec()
		gen += t1 - t0
		inst += t2 - t1
		worst = maxi(worst, t2 - t1)
	print("CHUNK_COST gen %.1f ms (worker), instantiate %.2f ms avg, %.2f ms worst (main thread)" % [
		gen / 16000.0, inst / 16000.0, worst / 1000.0])
	quit()
