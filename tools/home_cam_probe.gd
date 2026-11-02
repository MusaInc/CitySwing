extends SceneTree
## The follow camera indoors: walks the hero round each home (into the
## bedrooms, up the penthouse stairs) with the real SwingCamera and counts
## frames where the lens leaves the room or loses sight of the hero.
##   godot --headless --fixed-fps 30 -s res://tools/home_cam_probe.gd -- [home id] [shots dir]
## (with a display and a shots dir, saves a frame at every waypoint)

const ROUTES := {
	"starter": [[6, 4.5], [3.2, 5.5], [5, 9.5], [9.8, 8.5], [9.5, 3.5], [3.2, 2.8], [6, 4]],
	"city": [[8, 4], [2, 2.6], [5.5, 7.8], [5.4, 10.4], [5.5, 7.8], [8.8, 11], [8.8, 7], [12.5, 7.0], [12.0, 10.0],
		[12, 7.5], [8, 3]],
	"loft": [[10, 4], [2.5, 5.5], [2.5, 9], [7.5, 10.5], [13.4, 9.9], [13.4, 12.5], [13.4, 9.9], [17, 6], [10, 3]],
	"sky": [[12, 4], [6.5, 7.6], [6.5, 12.5], [10, 15], [11, 12], [15.5, 10.3], [15.6, 13.5], [15.5, 10.0], [17, 9.5],
		[12, 3]],
	"penthouse": [[13, 5], [11, 11], [1.4, 9.0], [1.4, 15.6], [8, 17.5], [17, 16.5], [8, 17.5], [1.4, 15.4], [1.4, 9.4],
		[8, 15.8], [11, 11], [24.5, 12], [24.5, 5], [19.6, 6], [13, 4]],
}


class _Drive:
	extends RefCounted
	var move := Vector3.ZERO
	var human_steer := true
	func drive(_p, _dt) -> Dictionary:
		return {"move": move, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var only: String = args[0] if args.size() > 0 else ""
	var shots: String = args[1] if args.size() > 1 else ""
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
	var atmo := Atmosphere.new()
	root.add_child(atmo)
	atmo.hour = 16.5
	var world := CityWorld.new()
	root.add_child(world)
	var player := Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	root.add_child(player)
	var rig := CharacterRig.new()
	rig.name = "Rig"
	player.add_child(rig)
	rig.set_player(player)
	var cam := SwingCamera.new()
	root.add_child(cam)
	cam.set_target(player)
	var hs := HomeSystem.new()
	root.add_child(hs)
	hs.setup(player, rig, world.layout)
	hs.camera = cam
	var all_ok := true
	for h: Dictionary in hs.homes:
		if only != "" and h["id"] != only:
			continue
		world.build_all_near(Apartments.window_center(h), 300.0)
		hs.spawn_in(h, world, cam)
		var d := _Drive.new()
		player.bot = d
		for i in 20:
			await process_frame
		var frames := 0
		var outside := 0
		var hidden := 0
		var reached := 0
		var worst := ""
		var missed := []
		var route: Array = ROUTES[h["id"]]
		for wi in route.size():
			var wp: Array = route[wi]
			var goal := Apartments.face_point(h, float(h["a0"]) + float(wp[0]), -float(wp[1]), float(h["y0"]))
			var t := 0.0
			while t < 7.0:
				var to := goal - player.global_position
				to.y = 0.0
				if to.length() < 0.5:
					reached += 1
					if OS.get_environment("PROBE_Y") != "":
						print("Y wp%d %.2f" % [wi, player.global_position.y - float(h["y0"])])
					break
				d.move = to.normalized() * (0.55 if to.length() < 2.0 else 1.0)
				await process_frame
				t += 1.0 / 30.0
				frames += 1
				var c := cam.global_position
				var f := Apartments.to_face(h, c)
				var inside: bool = f.x > float(h["a0"]) + 0.02 and f.x < float(h["a1"]) - 0.02 and f.y < -0.02 \
					and f.y > -float(h["depth"]) + 0.02 and f.z > float(h["y0"]) + 0.05 and f.z < float(h["y1"]) - 0.05
				if not inside and not in_opening(h, f):
					outside += 1
					worst = "wp%d out f=%s" % [wi, (f - Vector3(float(h["a0"]), 0, float(h["y0"]))).snapped(Vector3.ONE * 0.01)]
				var q := PhysicsRayQueryParameters3D.create(c, player.global_position + Vector3.UP * 0.4, 1 | CityWorld.HUMAN_LAYER)
				q.exclude = [player.get_rid()]
				var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
				if not hit.is_empty() and not _thin(hit):
					hidden += 1
					if worst == "":
						worst = "wp%d hidden by %s" % [wi, hit["collider"].name]
			if t >= 7.0:
				var pf := Apartments.to_face(h, player.global_position)
				missed.append("%d@%.1f,%.1f,%.2f" % [wi, pf.x - float(h["a0"]), -pf.y, pf.z - float(h["y0"])])
			d.move = Vector3.ZERO
			if shots != "" and DisplayServer.get_name() != "headless":
				for k in 6:
					await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/%s_%02d.png" % [shots, h["id"], wi])
				if OS.get_environment("PROBE_CAM") != "":
					var cf := Apartments.to_face(h, cam.global_position)
					print("CAMAT %s_%02d %.2f %.2f %.2f fwd %s" % [h["id"], wi, cf.x - float(h["a0"]), -cf.y, cf.z - float(h["y0"]), (-cam.global_transform.basis.z).snapped(Vector3.ONE * 0.01)])
		var ok := outside == 0 and hidden <= frames / 50
		all_ok = all_ok and ok
		print("CAMPROBE %-10s waypoints %d/%d  frames %d  lens outside room %d  hero hidden %d  %s  %s" % [h["id"],
			reached, route.size(), frames, outside, hidden, "OK" if ok else "BAD", worst + (" missed %s" % [missed] if missed else "")])
	print("CAMPROBE ", "ALL OK" if all_ok else "PROBLEMS")
	quit()


## Glass partitions and slim posts (boxes under 8 cm thick) don't hide the hero.
func _thin(hit: Dictionary) -> bool:
	var col = hit["collider"]
	if not (col is CollisionObject3D):
		return false
	var owner_id: int = col.shape_find_owner(hit["shape"])
	var cs = col.shape_owner_get_owner(owner_id)
	if cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D:
		var sz: Vector3 = ((cs as CollisionShape3D).shape as BoxShape3D).size
		return minf(sz.x, minf(sz.y, sz.z)) < 0.08
	return false


## Just out through the open window (turning back at the glass): a clear view.
func in_opening(h: Dictionary, f: Vector3) -> bool:
	return f.y >= 0.0 and f.y < 1.0 and f.x > float(h["oa0"]) and f.x < float(h["oa1"]) \
		and f.z > float(h["oy0"]) and f.z < float(h["oy1"])
