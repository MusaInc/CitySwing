extends SceneTree
## Renders the shop thumbnails (ThumbStudio) for review: one PNG per slot's
## first few items plus a contact sheet.
##   xvfb-run -a godot --rendering-method mobile -s res://tools/thumb_sheet.gd -- <outdir>

func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "screenshots/thumbs"
	DirAccess.make_dir_recursive_absolute(out)
	var st := ThumbStudio.new()
	root.add_child(st)
	await process_frame
	var ids: Array[String] = []
	for sl in Shop.SLOTS:
		var n := 0
		for it in Shop.in_slot(sl[0]):
			if n < 3:
				ids.append(it["id"])
			n += 1
	for id in ids:
		st.request(id)
	while ThumbStudio.cache.size() < ids.size():
		await process_frame
	var files: Array[String] = []
	for id in ids:
		var f := "%s/%s.png" % [out, id]
		(ThumbStudio.cache[id] as Texture2D).get_image().save_png(f)
		files.append(f)
	OS.execute("python3", ["tools/contact_sheet.py", out + "/sheet.png"] + files)
	print("THUMBS ", ids.size())
	quit()
