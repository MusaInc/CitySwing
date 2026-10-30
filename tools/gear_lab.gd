extends SceneTree
## Shop gear review: the hero's head close up wearing each headwear / face
## item (front and three-quarter views), one PNG per look.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method mobile \
##     --resolution 480x480 -s res://tools/gear_lab.gd -- <outdir>
## Then: python3 tools/contact_sheet.py <outdir>/sheet.png <outdir>/gear_*.png

const LOOKS := [
	["head_hood", "face_none"], ["head_bare", "face_none"], ["head_cap", "face_none"], ["head_beanie", "face_none"],
	["head_phones", "face_none"], ["head_crown", "face_none"], ["head_bare", "face_shades"], ["head_bare", "face_visor"],
	["head_bare", "face_mask"], ["head_hood", "face_mask"], ["head_cap", "face_shades"], ["head_beanie", "face_visor"],
]


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "screenshots/gear_lab"
	DirAccess.make_dir_recursive_absolute(out)
	root.add_child(Atmosphere.new())
	var rig := CharacterRig.new()
	root.add_child(rig)
	var cam := Camera3D.new()
	cam.fov = 30.0
	root.add_child(cam)
	cam.make_current()
	var head: Node3D = rig.bones["head"]
	var n := 0
	for lk in LOOKS:
		for view in [0.0, 0.8]:
			rig.apply_look(Shop.look({"head": lk[0], "face": lk[1], "suit": "ember"}))
			var c := head.global_position + Vector3(0, 0.11, 0)
			cam.global_position = c + Vector3(sin(view), 0.05, -cos(view)).normalized() * 0.9
			cam.look_at(c)
			for i in 3:
				await process_frame
			n += 1
			root.get_texture().get_image().save_png("%s/gear_%d.png" % [out, n])
	print("GEAR_LAB ", n, " shots in ", out)
	quit()
