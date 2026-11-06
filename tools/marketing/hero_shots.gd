extends "res://tools/marketing/capture.gd"
## Hero-forward store photography (gallery v3). Same real game, city, rig,
## rope and swing physics as capture.gd; the camera is a close, longer-lens
## "photographer" so the hero reads at thumbnail size. The outfit is a real
## Shop.look() (catalogue items), applied through the game's own dress().
##   bash tools/marketing/hero_shots.sh <out> <WxH> [ids]
## Scenes: swing near a real tower face, at a real time of day / weather.

const LOOK := {"suit": "tangerine", "pants": "pants_black", "shoes": "shoes_classic",
	"web": "web_classic", "face": "mask_courier", "top": "top_long"}

# id, centre (x,z), tower height band, hour, weather, frames after firing,
# preferred facade normal (x,z) or ZERO, cameras [(name, right, up, ahead, fov)]
var scenes := [
	["gold", Vector2(470, -140), Vector2(150, 260), 18.2, "clear", [16, 24], Vector2.ZERO,
		[["sun", 0, 0, 0, 46.0], ["low34", 2.2, -1.3, 2.4, 50.0], ["side", 3.4, -0.5, 0.5, 46.0], ["chase", 1.2, 0.7, -3.3, 52.0]]],
	["neon", Vector2(318, -63), Vector2(45, 160), 22.5, "clear", [18, 28], Vector2.ZERO,
		[["low34", 2.2, -1.3, 2.4, 52.0], ["under", 1.0, -2.8, 1.2, 60.0], ["side", 3.4, -0.5, 0.5, 48.0], ["chase", 1.2, 0.7, -3.3, 54.0]]],
	["dusk", Vector2(318, -63), Vector2(45, 160), 18.6, "clear", [18, 28], Vector2.ZERO,
		[["low34", 2.2, -1.3, 2.4, 52.0], ["side", 3.4, -0.5, 0.5, 48.0], ["front", -2.6, -0.8, 2.2, 50.0]]],
	["late", Vector2(318, -63), Vector2(45, 160), 18.85, "clear", [18, 28], Vector2.ZERO,
		[["low34", 2.2, -1.3, 2.4, 52.0], ["side", 3.4, -0.5, 0.5, 48.0], ["front", -2.6, -0.8, 2.2, 50.0]]],
	["rain", Vector2(318, -63), Vector2(45, 160), 19.2, "rain", [22], Vector2.ZERO,
		[["low34", 2.2, -1.3, 2.4, 52.0], ["side", 3.4, -0.5, 0.5, 48.0], ["chase", 1.2, 0.7, -3.3, 54.0]]],
	["canyon", Vector2(560, -170), Vector2(180, 330), 16.6, "clear", [14, 26], Vector2.ZERO,
		[["dive", 0.8, 2.0, -2.0, 62.0], ["low34", 2.2, -1.3, 2.4, 50.0], ["chase", 1.2, 0.7, -3.3, 56.0]]],
	["blue", Vector2(380, 60), Vector2(110, 230), 18.85, "clear", [20], Vector2.ZERO,
		[["sun", 0, 0, 0, 46.0], ["low34", 2.2, -1.3, 2.4, 50.0], ["side", 3.4, -0.5, 0.5, 46.0]]],
]

func action_photos() -> void:
	game.dress(Shop.look(LOOK))
	var used := {}
	for sc in scenes:
		var id: String = sc[0]
		var wanted := selection.is_empty()
		for name in selection:
			if name.begins_with(id + "_"): wanted = true
		if not wanted: continue
		game.atmosphere.hour = sc[3]
		game.atmosphere.set_weather(sc[4], true)
		await settle(5)
		var towers: Array = []
		var centre: Vector2 = sc[1]
		var band: Vector2 = sc[2]
		for b in world.layout.buildings:
			if b.kind != "normal": continue
			var c := CityLayout.top_center(b)
			if c.y > band.x and c.y < band.y and Vector2(c.x, c.z).distance_to(centre) < 220.0:
				towers.append(b)
		towers.sort_custom(func(a, b): return Vector2(CityLayout.top_center(a).x, CityLayout.top_center(a).z).distance_to(centre) < Vector2(CityLayout.top_center(b).x, CityLayout.top_center(b).z).distance_to(centre))
		var done := false
		for b in towers.slice(0, 6):
			if done: break
			var tier: Array = b.tiers[-1]
			var xf := CityLayout.bxf(b)
			for side in 4:
				if done: break
				var n := [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT][side] as Vector3
				var a := Vector3((tier[0] + tier[2]) * 0.5, tier[5] - 8.0, (tier[1] + tier[3]) * 0.5)
				if side == 0: a.z = tier[3]
				if side == 1: a.x = tier[2]
				if side == 2: a.z = tier[1]
				if side == 3: a.x = tier[0]
				var anchor := xf * a
				n = xf.basis * n
				var along := n.cross(Vector3.UP).normalized()
				# Keep the swing path clear: no tower in the 40 m in front of the face.
				var q := PhysicsRayQueryParameters3D.create(anchor + n * 1.5 - Vector3.UP * 20.0, anchor + n * 45.0 - Vector3.UP * 20.0)
				if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty(): continue
				for frames in sc[5]:
					player.respawn(anchor + n * 18.0 - along * 15.0 - Vector3.UP * 30.0)
					player.s.velocity = along * 20.0
					game.rig.set_facing(along)
					await settle(1)
					player.fire_at(anchor, 1)
					await settle(frames)
					if player.line_state != Player.Line.ATTACHED or game.rig.ragdolling:
						print("REJECT ", id, " side ", side)
						break
					done = true
					for c in sc[7]:
						var h := player.global_position + Vector3.UP * 0.3
						var v := player.s.velocity
						var f := Vector3(v.x, 0, v.z).normalized()
						var r := f.cross(Vector3.UP).normalized()
						var pos: Vector3
						if c[0] == "sun":
							var to_sun: Vector3 = game.atmosphere.sun.global_basis.z
							to_sun.y = 0.0
							to_sun = to_sun.normalized()
							pos = h - to_sun * 3.6 - Vector3.UP * 1.5
						else:
							pos = h + r * c[1] + Vector3.UP * c[2] + f * c[3]
						await take_framed("%s_%d_%s" % [id, frames, c[0]], pos, h + f * 0.4, c[4])
	if selection.is_empty() or "perch" in "".join(selection): await perch_photos()


## Puts the subject at `HERO_X` of the frame width (right third) so the
## headline has open space on the left; the camera only yaws.
const HERO_X := 0.66
## On iPad (4:3) the copy sits across the top, so swinging heroes drop to the
## lower right instead.
const IPAD_HERO := Vector2(0.69, 0.61)
func take_framed(id: String, pos: Vector3, subject: Vector3, fov: float, drop := true) -> void:
	var aspect := float(output_size.x) / output_size.y
	var at := Vector2(HERO_X, 0.5)
	if aspect < 1.6 and drop: at = IPAD_HERO
	var t := tan(deg_to_rad(fov) * 0.5)
	var yaw := atan((at.x * 2.0 - 1.0) * aspect * t)
	var pitch := atan((at.y * 2.0 - 1.0) * t)
	var d := subject - pos
	var right := d.cross(Vector3.UP).normalized()
	var up := right.cross(d).normalized()
	await take(id, pos, subject - right * d.length() * tan(yaw) + up * d.length() * tan(pitch), fov, 0.0)


## Real floor contact on a roof edge, facing the skyline at sunset.
func perch_photos() -> void:
	for cond in [["perch_gold", 18.25, "clear"], ["perch_blue", 18.9, "clear"]]:
		game.atmosphere.hour = cond[1]
		game.atmosphere.set_weather(cond[2], true)
		await settle(5)
		var to_sun: Vector3 = game.atmosphere.sun.global_basis.z
		to_sun.y = 0.0
		to_sun = to_sun.normalized()
		var k := 0
		for b in world.layout.buildings:
			if k >= 3: break
			if b.kind != "normal" or b.get("roof_blocked", false): continue
			var c := CityLayout.top_center(b)
			if c.y < 90.0 or c.y > 170.0 or Vector2(c.x, c.z).distance_to(Vector2(380, -20)) > 260.0: continue
			var t: Array = b.tiers[-1]
			var xf := CityLayout.bxf(b)
			# Edge whose outward normal points most toward the sun.
			var best := -1
			var bd := -2.0
			for side in 4:
				var n := xf.basis * ([Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT][side] as Vector3)
				if n.dot(to_sun) > bd: bd = n.dot(to_sun); best = side
			var pos := Vector3((t[0] + t[2]) * 0.5, BuildingMesher.roof_y(b) + 1.05, (t[1] + t[3]) * 0.5)
			if best == 0: pos.z = t[1] + 0.85
			if best == 1: pos.x = t[2] - 0.85
			if best == 2: pos.z = t[3] - 0.85
			if best == 3: pos.x = t[0] + 0.85
			pos = xf * pos
			var n: Vector3 = xf.basis * ([Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT][best] as Vector3)
			# Open view: nothing taller in the 150 m beyond the edge.
			var q := PhysicsRayQueryParameters3D.create(pos + n * 2.0 + Vector3.UP * 2.0, pos + n * 150.0 + Vector3.UP * 2.0)
			if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty(): continue
			player.respawn(pos)
			game.rig.set_facing(n)
			await settle(40)
			if not player.is_on_floor(): continue
			var along := n.cross(Vector3.UP).normalized()
			var p := player.global_position + Vector3.UP * 0.9
			await take_framed("%s_%d_back" % [cond[0], k], p - n * 3.2 + along * 1.2 + Vector3.UP * 0.4, p + n * 1.0, 50.0, false)
			await take_framed("%s_%d_low" % [cond[0], k], p - n * 2.4 - along * 1.6 - Vector3.UP * 0.6, p + n * 0.5 + Vector3.UP * 0.3, 54.0, false)
			k += 1
