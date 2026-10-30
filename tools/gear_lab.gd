extends SceneTree
## Shop gear review: the hero's head close up wearing each headwear / face
## item (front and three-quarter views), then each gadget on the whole body
## (idle and running), one PNG per shot.
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
	# Gadgets: on a real (standing) player so the rig poses every bone.
	rig.queue_free()
	var stage := Node3D.new()
	root.add_child(stage)
	PrototypeWorld.add_box(stage, Vector3(0, -0.5, 0), Vector3(60, 1, 60), Color(0.42, 0.43, 0.45), false, true)
	var player := Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	player.input_enabled = false
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	rig = CharacterRig.new()
	player.add_child(rig)
	rig.set_player(player)
	for i in 60:
		await physics_frame
	# Whole body from behind-left and the front-right, idle and running.
	for g in ["gadget_jets", "gadget_glider", "gadget_chrono", "gadget_magnet"]:
		for on in [false, true]:
			rig.apply_look(Shop.look({"gadget": g}))
			rig.set_gadget_active(on)
			for view in [PI + 0.7, -0.6]:
				var close: bool = g == "gadget_jets" or g == "gadget_magnet" or g == "gadget_chrono"
				var c := rig.global_position + Vector3(0, {"gadget_jets": -0.65, "gadget_magnet": 0.0,
					"gadget_chrono": -0.05}.get(g, 0.0), 0)
				cam.global_position = c + Vector3(sin(view), 0.25, -cos(view)).normalized() * (1.5 if close else 3.6)
				cam.look_at(c)
				for i in 3:
					await process_frame
				n += 1
				root.get_texture().get_image().save_png("%s/gear_%d.png" % [out, n])
		rig.set_gadget_active(false)
	print("GEAR_LAB ", n, " shots in ", out)
	quit()
