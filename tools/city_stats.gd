extends SceneTree
## City size/cost report: building, prop and collision counts plus generated
## triangle totals (detail / low LOD / ground / road marks / structures).
##   godot --headless -s res://tools/city_stats.gd


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var w = load("res://src/world/city_world.gd").new()
	root.add_child(w)
	await process_frame
	var l: CityLayout = w.layout
	var tris := {}
	var gen_us := 0
	for key in w._all_keys:
		var t1 := Time.get_ticks_usec()
		var res: Dictionary = w.generate_chunk_arrays(key)
		gen_us += Time.get_ticks_usec() - t1
		for k in res:
			if res[k] is Array:
				tris[k] = tris.get(k, 0) + (res[k][Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var shapes := 0
	for c in w.get_children():
		if c is StaticBody3D:
			shapes += c.get_child_count()
	var tall := 0
	var top := 0.0
	for b in l.buildings:
		if b["kind"] == "normal":
			var h: float = b["tiers"][-1][5]
			top = maxf(top, h)
			if h > 100.0:
				tall += 1
	var kinds := {}
	for st in l.structures:
		kinds[st["type"]] = kinds.get(st["type"], 0) + 1
	var stris := 0
	for c in w.get_children():
		if c.name.begins_with("Structure_"):
			stris += (c.get_node("Detail") as MeshInstance3D).mesh.get_faces().size() / 3
	print("STATS structures %s (detail tris %d), anchor lines %d, signs %d, frames %d, spires %d" % [kinds, stris,
		l.anchor_lines.size(), l.buildings.filter(func(b): return b["kind"] == "sign").size(),
		l.buildings.filter(func(b): return b["kind"] == "frame").size(),
		l.buildings.filter(func(b): return b["kind"] == "spire").size()])
	var extra := ""
	for c in w.get_children():
		if c is MeshInstance3D and c.mesh:
			extra += " %s=%d" % [c.name, c.mesh.get_faces().size() / 3]
	print("STATS area %.0fx%.0f m, buildings %d (>100 m: %d, tallest %.0f m), props %d, chunks %d, collision shapes %d" % [
		CityLayout.MAX_X - CityLayout.MIN_X, CityLayout.MAX_Z - CityLayout.MIN_Z, l.buildings.size(), tall, top,
		l.props.size(), w._all_keys.size(), shapes])
	print("STATS chunk tris %s, chunk gen total %d ms; static:%s; total %d ms" % [tris, gen_us / 1000, extra,
		Time.get_ticks_msec() - t0])
	quit()
