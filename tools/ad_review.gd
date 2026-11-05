extends SceneTree
## Stills of the city at fixed views and times of day (real lighting – the
## --cam capture path pins the clock): used for the advertising district
## and the architecture passes.
##   xvfb-run -a godot --rendering-method mobile --resolution 960x540 -s res://tools/ad_review.gd -- \
##     --out=<dir> [--hours=13,18.6,23] [--views=name:x,y,z,lx,ly,lz;...] [--fov=70]
## Prints RENDER_STATS per still.
const VIEWS := {
	"circus_street": "290,14.5,-40,330,22,-80",
	"circus_aerial": "470,190,90,318,10,-63",
	"circus_swing": "220,40,-10,330,26,-70",
	"circus_roof": "180,70,-150,318,20,-63",
}
var out := "screenshots/ads"
var hours: Array[float] = [13.0, 18.6, 23.0]
var views := {}
var fov := 70.0


func _initialize() -> void:
	go.call_deferred()


func go() -> void:
	views = VIEWS.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--hours="):
			hours.clear()
			for h in a.trim_prefix("--hours=").split(","):
				hours.append(float(h))
		elif a.begins_with("--views="):
			views.clear()
			for v in a.trim_prefix("--views=").split(";"):
				var kv := v.split(":")
				views[kv[0]] = kv[1]
		elif a.begins_with("--fov="):
			fov = float(a.trim_prefix("--fov="))
	DirAccess.make_dir_recursive_absolute(out)
	root.get_node("SaveData").use_file("user://ad_review_save.json")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.hud.visible = false
	main.touch.visible = false
	main.menus.visible = false
	var atm: Atmosphere = main.atmosphere
	atm.live = false
	atm.set_weather("clear", true)
	for name in views:
		var c: PackedStringArray = (views[name] as String).split(",")
		var pos := Vector3(float(c[0]), float(c[1]), float(c[2]))
		var at := Vector3(float(c[3]), float(c[4]), float(c[5]))
		var xf := Transform3D.IDENTITY.translated(pos).looking_at(at, Vector3.UP)
		main.camera.cine = func(_dt): return [xf, fov]
		main.player.global_position = at + Vector3(0, 400, 0)  # out of shot
		main.world.build_all_near(pos, 600.0)
		for h in hours:
			atm.hour = h
			atm._apply(0.0, true)
			for i in 45:
				await process_frame
			await RenderingServer.frame_post_draw
			var file := "%s/%s_%s.png" % [out, name, ("%04.1f" % h).replace(".", "h")]
			root.get_texture().get_image().save_png(file)
			print("RENDER_STATS ", JSON.stringify({"shot": file.get_file(),
				"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				"vram_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1)}))
	main.queue_free()
	await process_frame
	quit()
