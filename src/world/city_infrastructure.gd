class_name CityInfrastructure
extends RefCounted
## Designed connections and public spaces, using the existing batched kit.

static func bridge_landing(l: CityLayout) -> void:
	var road: PackedVector2Array = l.roads.by_name.diagonal.pts
	var path := PackedVector2Array()
	# First roundabout is the ramp's at-grade destination; use the same cut
	# as Traffic so its lanes meet the roundabout connectors exactly.
	var first: Dictionary = {}
	for rb in l.roads.roundabouts:
		if rb.c.x > 150.0 and rb.c.x < 400.0 and rb.c.y > -140.0:
			first = rb
	if first.is_empty():
		return
	var cut := CityRoads._circle(first.c, float(first.r) + float(first.w) * 0.5 + 0.5, 32)
	var sections := Geometry2D.clip_polyline_with_polygon(road, cut)
	var approach: PackedVector2Array = sections[0]
	path.append(Vector2(56.0, CityLayout.BRIDGE_Z))
	for p in approach:
		if p.x > 60.0:
			path.append(p)
	var flat := RailNetwork._resample_open(path, 6.0)
	var end := flat[-1]
	var finish := l.terrain.road_y(end.x, end.y)
	var total := CityRoads.length_of(flat)
	var travelled := 0.0
	for i in flat.size():
		if i > 0:
			travelled += flat[i].distance_to(flat[i - 1])
		var u := travelled / total
		var y := lerpf(CityLayout.BRIDGE_DECK, finish, smoothstep(0.0, 1.0, u))
		l.bridge_ramp.append(Vector3(flat[i].x, y, flat[i].y))
	var k := l._kit("island_bridge_approach")
	var stone := Color(0.43, 0.44, 0.43)
	var white := Color(0.76, 0.76, 0.70)
	for i in l.bridge_ramp.size() - 1:
		var a := l.bridge_ramp[i]
		var b := l.bridge_ramp[i + 1]
		var d := (b - a).normalized()
		var side := Vector3(-d.z, 0, d.x).normalized()
		var ext := d * 0.08
		l._kbeam(k, a - ext + Vector3.DOWN * 0.65, b + ext + Vector3.DOWN * 0.65, 20.0, 1.3, Color(0.15, 0.16, 0.17))
		for sg: float in [-1.0, 1.0]:
			var o := side * sg * 9.8
			# End barriers before the junction mouth, leaving turning space.
			if i < l.bridge_ramp.size() - 3:
				l._kbeam(k, a + o + Vector3.UP * 0.5, b + o + Vector3.UP * 0.5, 0.35, 1.0, stone)
			l._kbeam(k, a + side * sg * 8.4 + Vector3.UP * 0.025, b + side * sg * 8.4 + Vector3.UP * 0.025, 0.12, 0.02, white, false)
			if i % 2 == 0:
				l._kbeam(k, a + side * sg * 5.1 + Vector3.UP * 0.025, a.lerp(b, 0.5) + side * sg * 5.1 + Vector3.UP * 0.025, 0.12, 0.02, white, false)
		l._kbeam(k, a + Vector3.UP * 0.025, b + Vector3.UP * 0.025, 0.2, 0.02, Color(0.7, 0.6, 0.27), false)
		if i % 6 == 0:
			var g := l.terrain.road_y(a.x, a.z)
			var field := l.roads.field_at(Vector2(a.x, a.z))
			if a.y - g > 3.5 and field.w > 2.5:
				l._kbeam(k, Vector3(a.x, g - 0.4, a.z), a + Vector3.DOWN * 1.8, 1.6, 1.6, stone)
				l._kbeam(k, a - side * 8 + Vector3.DOWN * 1.7, a + side * 8 + Vector3.DOWN * 1.7, 1.6, 1.0, stone)
				l._ksolid(k, a.x - 1.5, a.z - 1.5, a.x + 1.5, a.z + 1.5, g - 0.6, g + 0.2, stone)
		# Lamps have their normal short visibility range and shared mesh.
		if i % 7 == 1:
			for sg: float in [-1.0, 1.0]:
				var p := a + side * sg * 8.9
				l.props.append(["streetlight", Transform3D(Basis(Vector3.UP, atan2(d.x, d.z) + (PI if sg > 0 else 0)), p)])

static func bridge_height(l: CityLayout, x: float) -> float:
	if x <= 56.0 or l.bridge_ramp.is_empty():
		return CityLayout.approach_y(x)
	for i in l.bridge_ramp.size() - 1:
		var a := l.bridge_ramp[i]
		var b := l.bridge_ramp[i + 1]
		if x <= b.x:
			return lerpf(a.y, b.y, clampf((x - a.x) / maxf(0.01, b.x - a.x), 0.0, 1.0))
	return l.bridge_ramp[-1].y

static func public_spaces(l: CityLayout) -> void:
	# Riverside seating bays sit between the viaduct and the quay edge.
	# Leave the bridge crossing, lighthouse and the corners unobstructed.
	if not l.is_mainland:
		for z in range(-520, 521, 56):
			if absf(z - CityLayout.BRIDGE_Z) < 55 or absf(z - SetPieces.LIGHTHOUSE_AT.y) < 22:
				continue
			var p := Vector3(37.5, l.ground_y(37.5, z), z)
			if l.is_water(p):
				continue
			var crossing := false
			for dz: float in [-14.0, 0.0, 14.0]:
				if l.roads.on_road(Vector2(p.x + 2.3, p.z + dz)):
					crossing = true
			if crossing:
				continue
			garden(l, p + Vector3(2.3, 0, 0), Vector2(2.5, 7.0), false)
			furniture(l, "bench", p + Vector3(0, 0, -5.5), PI * 0.5)
			furniture(l, "bin", p + Vector3(0, 0, 5.5), 0)
			l.props.append(["streetlight", Transform3D(Basis(Vector3.UP, PI * 0.5), p + Vector3(0, 0, 11))])
	# Turn genuinely empty block interiors into courtyard gardens. Test the
	# whole envelope against buildings, roads and existing props; no random
	# filling of streets, station platforms, landmarks or apartment entrances.
	var grid := l._building_grid()
	var count := 0
	for block in l.blocks:
		if block.kind != "block" or count >= 24:
			continue
		var c := CityRoads._centroid(block.poly)
		var p := Vector3(c.x, l.ground_y(c.x, c.y), c.y)
		var clear := true
		for dx: float in [-8.0, 0.0, 8.0]:
			for dz: float in [-8.0, 0.0, 8.0]:
				var q := c + Vector2(dx, dz)
				if not Geometry2D.is_point_in_polygon(q, block.poly) or l.roads.on_road(q) or absf(l.ground_y(q.x, q.y) - p.y) > 0.35:
					clear = false
		for gx in range(-1, 2):
			for gz in range(-1, 2):
				var cell := Vector2i(floori(c.x / 50), floori(c.y / 50)) + Vector2i(gx, gz)
				for b in grid.get(cell, []):
					if CityLayout.inside(b, p + Vector3.UP, 10.0, 2.0):
						clear = false
		for prop in l.props:
			if (prop[1].origin as Vector3).distance_to(p) < 9.0:
				clear = false
		if not clear:
			continue
		garden(l, p, Vector2(8, 8), true)
		furniture(l, "bench", p + Vector3(0, 0, 6), PI)
		furniture(l, "bench", p + Vector3(0, 0, -6), 0)
		furniture(l, "bin", p + Vector3(5, 0, 6), 0)
		count += 1

static func garden(l: CityLayout, p: Vector3, size: Vector2, tree: bool) -> void:
	var name := "gardens_%d_%d" % [floori(p.x / CityLayout.CHUNK), floori(p.z / CityLayout.CHUNK)]
	var k: Dictionary = {}
	for structure in l.structures:
		if structure.get("name", "") == name:
			k = structure
			break
	if k.is_empty():
		k = l._kit(name)
	var x := size.x * 0.5
	var z := size.y * 0.5
	l._ksolid(k, p.x - x, p.z - z, p.x + x, p.z + z, p.y - 0.1, p.y + 0.35, Color(0.34, 0.36, 0.32))
	l._ksolid(k, p.x - x + 0.2, p.z - z + 0.2, p.x + x - 0.2, p.z + z - 0.2, p.y + 0.35, p.y + 0.39, Color(0.23, 0.32, 0.20), false)
	l.public_gardens.append(p)
	if tree:
		l.props.append(["tree", Transform3D(Basis().scaled(Vector3.ONE * 0.85), p + Vector3.UP * 0.39)])
	else:
		for dz: float in [-2.0, 2.0]:
			l.props.append(["tree", Transform3D(Basis().scaled(Vector3.ONE * 0.48), p + Vector3(0, 0.39, dz))])

static func furniture(l: CityLayout, kind: String, p: Vector3, yaw: float) -> void:
	l.public_furniture.append([kind, Transform3D(Basis(Vector3.UP, yaw), p)])

## Compact switchback stairs in a clear pavement plot, joined to the
## adjacent platform by an elevated walkway. Smooth collision ramps
## share the visible stair flights, avoiding dozens of collision shapes.
static func station_access(l: CityLayout, k: Dictionary, c: Vector3, d: Vector3, side: Vector3) -> void:
	var at := Vector3.INF
	var grid := l._building_grid()
	for distance: float in [18.0, 24.0, 30.0, 38.0]:
		for sign_side: float in [-1.0, 1.0]:
			for along: float in [0.0, -24.0, 24.0]:
				var p := c + side * sign_side * distance + d * along
				p.y = l.ground_y(p.x, p.z)
				var clear := not l.is_water(p)
				for dx: float in [-3.0, 0.0, 3.0]:
					for dz: float in [-5.0, 0.0, 5.0]:
						var q := p + side * dx + d * dz
						if l.roads.on_road(Vector2(q.x, q.z)) or absf(l.ground_y(q.x, q.z) - p.y) > 0.45:
							clear = false
				for gx in range(-1, 2):
					for gz in range(-1, 2):
						for b in grid.get(Vector2i(floori(p.x / 50), floori(p.z / 50)) + Vector2i(gx, gz), []):
							if CityLayout.inside(b, p + Vector3.UP * 2, 6.5, 2.0):
								clear = false
				if clear:
					at = p
					break
			if at != Vector3.INF:
				break
		if at != Vector3.INF:
			break
	if at == Vector3.INF:
		return  # avoid inventing a tower in traffic or through an existing building
	var top := c.y + 1.0
	var flights := maxi(2, ceili((top - at.y) / 1.5))
	var rise := (top - at.y) / flights
	var steel := Color(0.24, 0.29, 0.29)
	var stone := Color(0.47, 0.47, 0.43)
	# Four full-height columns and a roof make the structure legible from afar.
	for sx: float in [-2.1, 2.1]:
		for sz: float in [-4.4, 4.4]:
			var p := at + side * sx + d * sz
			l._kbeam(k, p - Vector3.UP * 0.2, Vector3(p.x, top + 2.8, p.z), 0.24, 0.24, steel)
	for f in flights:
		var sg := 1.0 if f % 2 == 0 else -1.0
		var a := at + side * sg * 1.0 - d * sg * 3.2 + Vector3.UP * (rise * f)
		var b := at + side * sg * 1.0 + d * sg * 3.2 + Vector3.UP * (rise * (f + 1))
		l._kbeam(k, a + Vector3.DOWN * 0.12, b + Vector3.DOWN * 0.12, 1.7, 0.24, stone)
		for step in 9:
			var p := a.lerp(b, float(step + 1) / 9)
			l._kbeam(k, p - d * 0.36, p + d * 0.36, 1.7, 0.1, stone, false)
		var landing := b + d * sg * 0.6 - side * sg
		l._kbeam(k, landing - side * 2, landing + side * 2, 1.2, 0.2, stone)
		l._kbeam(k, a + side * sg * 0.85 + Vector3.UP, b + side * sg * 0.85 + Vector3.UP, 0.08, 0.08, steel, false)
	var upper := Vector3(at.x, top, at.z)
	var sg := signf((at - c).dot(side))
	var platform := c + side * sg * 6.0 + Vector3.UP
	l._kbeam(k, upper + Vector3.DOWN * 0.15, platform + Vector3.DOWN * 0.15, 2.2, 0.3, stone)
	for offset: float in [-1.0, 1.0]:
		l._kbeam(k, upper + d * offset + Vector3.UP, platform + d * offset + Vector3.UP, 0.08, 0.08, steel, false)
	l._kbeam(k, upper - d * 4.7 + Vector3.UP * 2.8, upper + d * 4.7 + Vector3.UP * 2.8, 4.6, 0.18, steel)
	furniture(l, "sign_post", at + d * 5.5, 0)
