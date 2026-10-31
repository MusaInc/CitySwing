class_name RailNetwork
extends RefCounted
## The city's railways as data the trains run on, plus the Loop Line's
## viaduct and stations (built into the layout as set-piece kits, so they're
## drawn and collide like everything else).
##
##   * Loop Line: right round the island – up the waterfront on the old brick
##     viaduct, then on a concrete viaduct over the coastal ring road (one
##     central pier per span in the median, so traffic runs underneath). Two
##     tracks; one train each way. Four stations.
##   * Valley Line: the existing elevated line along Valley Road – a shuttle
##     that runs end to end and back.
##
## A line: {name, pts: PackedVector3Array (rail top on the centreline, every
## STEP m), loop: bool, tracks: [offset m, ...] (+ = left of travel),
## stations: [s m, ...], cars: int}

const STEP := 2.0
const LOOP_DECK_ABOVE_ROAD := 10.6   # the brick viaduct's deck height (its road is at sea level)
const VIADUCT_X := 48.0
const VIADUCT_DECK := 10.6
const RAIL_H := 0.2                  # rail top above the deck
const TRACK := 2.1                   # each track's offset from the centreline
const CONCRETE := Color(0.62, 0.61, 0.58)
const CONCRETE_DK := Color(0.45, 0.45, 0.44)
const RAIL_STEEL := Color(0.3, 0.3, 0.31)
const CANOPY := Color(0.18, 0.22, 0.24)
const PLATFORM := Color(0.7, 0.69, 0.66)
const STATION_LEN := 64.0
## Platform edge from the track centre: half the car (1.5 m) + a 10 cm gap.
const PLATFORM_GAP := 1.6

var lines: Array = []
var L: CityLayout


func _init(layout: CityLayout) -> void:
	L = layout


# ------------------------------------------------------------- the Loop Line
func build_loop() -> void:
	var ring: Dictionary = L.roads.by_name.get("ring", {})
	if ring.is_empty():
		return
	var rp: PackedVector2Array = ring["pts"]
	var n := rp.size()
	if rp[0].distance_to(rp[n - 1]) < 0.5:
		n -= 1
	# The ring without its west leg (the waterfront viaduct replaces it):
	# start just after the west leg, run round N → E → S until it comes back.
	var start := -1
	for i in n:
		if rp[(i - 1 + n) % n].x < 200.0 and rp[i].x >= 200.0:
			start = i
			break
	if start < 0:
		return
	var path := PackedVector2Array()
	for k in n:
		var q := rp[(start + k) % n]
		if q.x < 200.0:
			break
		path.append(q)
	# Down the waterfront on the brick viaduct (south → north), every 20 m.
	var z_hi := minf(path[-1].y - 80.0, CityLayout.MAX_Z - 60.0)
	var z_lo := maxf(path[0].y + 80.0, CityLayout.MIN_Z + 60.0)
	var z := z_hi
	while z > z_lo:
		path.append(Vector2(VIADUCT_X, z))
		z -= 20.0
	path.append(Vector2(VIADUCT_X, z_lo))
	# Round the corners (Chaikin on a 20 m resample: ~50 m radius curves).
	var sm := _resample_closed(path, 36.0)
	for it in 4:
		sm = _chaikin_closed(sm)
	# Swing out round anything in the way (the cathedral's close to the ring
	# on the east coast): push blocked points seaward, then re-ease.
	sm = _clear_buildings(sm)
	sm = _resample_closed(sm, 16.0)
	for it in 2:
		sm = _chaikin_closed(sm)
	# (Chaikin keeps the long waterfront straight exactly on the viaduct's
	# axis: collinear points stay collinear.)
	var flat := _resample_closed(sm, STEP)
	# Heights: deck = road + 10.6 (exactly the brick viaduct on the
	# waterfront), eased along the line so grades stay gentle.
	var ys := PackedFloat32Array()
	ys.resize(flat.size())
	for i in flat.size():
		var q := flat[i]
		var on_viaduct := q.x < VIADUCT_X + 0.05
		ys[i] = VIADUCT_DECK if on_viaduct else L.terrain.road_y(q.x, q.y) + LOOP_DECK_ABOVE_ROAD
	for pass_i in 3:
		ys = _ease_closed(ys, 40)
	for i in flat.size():
		var q := flat[i]
		if q.x < VIADUCT_X + 0.5:
			ys[i] = VIADUCT_DECK
		else:
			ys[i] = maxf(ys[i], L.terrain.road_y(q.x, q.y) + 8.5)
	ys = _ease_closed(ys, 10)
	for i in flat.size():
		if flat[i].x < VIADUCT_X + 0.5:
			ys[i] = VIADUCT_DECK
	var pts := PackedVector3Array()
	for i in flat.size():
		pts.append(Vector3(flat[i].x, ys[i] + RAIL_H, flat[i].y))
	var total := pts.size() * STEP
	var stations: Array = []
	for f: float in [0.1, 0.33, 0.58, 0.86]:
		stations.append(_straightest(pts, total * f, 160.0))
	var line := {"name": "loop", "pts": pts, "loop": true, "tracks": [TRACK, -TRACK], "stations": stations,
		"cars": 4}
	lines.append(line)
	_loop_viaduct(pts)
	for s: float in stations:
		_station(line, s)


func _clear_buildings(p: PackedVector2Array) -> PackedVector2Array:
	var grid := L._building_grid()
	var c := L.island.get_center()
	var hit := func(q: Vector2) -> bool:
		var y := L.terrain.road_y(q.x, q.y) + LOOP_DECK_ABOVE_ROAD
		for b in grid.get(Vector2i(floori(q.x / 50.0), floori(q.y / 50.0)), []):
			if CityLayout.inside(b, Vector3(q.x, y + 1.0, q.y), 7.0, 4.0):
				return true
		return false
	# How far out each point must go, as a smooth bulge: push until clear,
	# widen (max filter) and ease (box filter) the offsets, apply; twice.
	var n := p.size()
	for it in 2:
		var need := PackedFloat32Array()
		need.resize(n)
		var any := false
		for i in n:
			if p[i].x < VIADUCT_X + 6.0:
				continue
			var out := (p[i] - c).normalized()
			var d := 0.0
			while d < 30.0 and hit.call(p[i] + out * d):
				d += 2.0
			need[i] = d
			any = any or d > 0.0
		if not any:
			break
		var wide := PackedFloat32Array()
		wide.resize(n)
		for i in n:
			var m := 0.0
			for o in range(-12, 13):
				m = maxf(m, need[(i + o + n) % n])
			wide[i] = m
		for pass_i in 2:
			wide = _ease_closed(wide, 12)
		for i in n:
			p[i] += (p[i] - c).normalized() * wide[i] * 1.15
	return p


## The concrete viaduct and the rails (the waterfront leg already has its
## brick viaduct: rails only there). Kits of ~300 m so each culls on its own.
func _loop_viaduct(pts: PackedVector3Array) -> void:
	var n := pts.size()
	var k := L._kit("loop_0")
	var run := 0.0
	var i := 0
	var seg := 10  # samples per drawn segment (20 m on straights)
	while i < n:
		var j := mini(i + seg, n)  # (j == n closes the loop back to sample 0)
		# Shorter chords on curves, so the straight rail pieces stay on the
		# path the wheels follow (within ~12 cm).
		while j > i + 1 and _chord_dev(pts, i, j) > 0.12:
			j -= 1
		var a := pts[i]
		var b := pts[j % n]
		var d := b - a
		var side := Vector3(-d.z, 0.0, d.x).normalized()
		var ext := d.normalized() * 0.3
		var deck_a := a - Vector3.UP * RAIL_H
		var deck_b := b - Vector3.UP * RAIL_H
		var brick := a.x < VIADUCT_X + 0.5 and b.x < VIADUCT_X + 0.5
		if not brick:
			L._kbeam(k, deck_a - ext + Vector3.DOWN * 0.7, deck_b + ext + Vector3.DOWN * 0.7, 9.6, 1.4, CONCRETE)
			L._kbeam(k, deck_a - ext + Vector3.DOWN * 1.7, deck_b + ext + Vector3.DOWN * 1.7, 5.0, 0.8, CONCRETE_DK, false)
			for sgn: float in [-1.0, 1.0]:
				var o := side * sgn * 4.6
				L._kbeam(k, deck_a - ext + o + Vector3.UP * 0.5, deck_b + ext + o + Vector3.UP * 0.5, 0.4, 1.0, CONCRETE)
				L._anchor(deck_a + side * sgn * 4.9 + Vector3.DOWN * 1.2, deck_b + side * sgn * 4.9 + Vector3.DOWN * 1.2)
		for t: float in [TRACK, -TRACK]:
			for r: float in [-0.72, 0.72]:
				var ro := side * (t + r) + Vector3.DOWN * 0.08
				L._kbeam(k, a + ro - ext, b + ro + ext, 0.1, 0.16, RAIL_STEEL, false)
			if not brick:
				var so := side * t + Vector3.DOWN * (RAIL_H - 0.04)
				L._kbeam(k, a + so - ext, b + so + ext, 2.6, 0.12, Color(0.36, 0.33, 0.3), false)  # ballast bed
		# Piers: one column in the ring road's median every ~30 m, with a hammerhead.
		if not brick:
			var s0 := i * STEP
			var s1 := j * STEP
			var sp := ceilf(s0 / 30.0) * 30.0
			while sp < s1:
				var p := _at(pts, sp)
				var dir := _at(pts, sp + 2.0) - _at(pts, sp - 2.0)
				dir.y = 0.0
				dir = dir.normalized()
				var ps := Vector3(-dir.z, 0.0, dir.x)
				var gy := L.terrain.road_y(p.x, p.z)
				var top := p.y - RAIL_H - 2.1
				L._kbeam(k, Vector3(p.x, gy - 0.3, p.z), Vector3(p.x, top, p.z), 1.7, 1.7, CONCRETE_DK)
				L._kbeam(k, Vector3(p.x, top + 0.4, p.z) - ps * 4.2, Vector3(p.x, top + 0.4, p.z) + ps * 4.2, 1.8, 1.0,
					CONCRETE)
				sp += 30.0
		run += d.length()
		if run > 300.0:
			run = 0.0
			k = L._kit("loop_%d" % L.structures.size())
		i = j


## A station: platforms both sides (outboard of the tracks), canopies on
## columns, a lift/stair tower down to the street, name boards.
func _station(line: Dictionary, s0: float) -> void:
	var pts: PackedVector3Array = line["pts"]
	var k := L._kit("station")
	var a := _at(pts, s0 - STATION_LEN * 0.5)
	var b := _at(pts, s0 + STATION_LEN * 0.5)
	var d := (b - a)
	d.y = 0.0
	d = d.normalized()
	var side := Vector3(-d.z, 0.0, d.x)
	var c := _at(pts, s0)
	var brick := c.x < VIADUCT_X + 0.5
	for sgn: float in [-1.0, 1.0]:
		var off := side * sgn * (TRACK + PLATFORM_GAP + 1.75)
		var pa := a + off
		var pb := b + off
		# Platform at car-floor height, its edge along the track.
		L._kbeam(k, pa + Vector3.DOWN * 0.1, pb + Vector3.DOWN * 0.1, 3.5, 2.2 if not brick else 1.6, PLATFORM)
		L._kbeam(k, pa + side * sgn * -1.72 + Vector3.UP * 0.96, pb + side * sgn * -1.72 + Vector3.UP * 0.96,
			0.06, 0.04, Color(0.95, 0.8, 0.15), false)  # yellow safety line
		# Canopy: columns down the outer edge, a roof sloping to the track.
		var t := 4.0
		while t < STATION_LEN - 2.0:
			var q := pa.lerp(pb, t / STATION_LEN) + side * sgn * 1.3
			L._kbeam(k, q + Vector3.UP * 1.0, q + Vector3.UP * 4.6, 0.25, 0.25, CANOPY)
			t += 10.0
		var ra := pa + side * sgn * 0.2 + Vector3.UP * 4.75
		var rb := pb + side * sgn * 0.2 + Vector3.UP * 4.75
		L._kbeam(k, ra, rb, 4.4, 0.18, CANOPY)
		L._kbeam(k, ra + side * sgn * -2.15 + Vector3.DOWN * 0.25, rb + side * sgn * -2.15 + Vector3.DOWN * 0.25,
			0.12, 0.5, Color(0.72, 0.09, 0.08), false)  # crimson fascia
		# Back wall with a glass screen, and a name board in the middle.
		L._kbeam(k, pa + side * sgn * 1.7 + Vector3.UP * 1.6, pb + side * sgn * 1.7 + Vector3.UP * 1.6, 0.12, 1.2,
			Color(0.3, 0.38, 0.42), false)
		var m := (pa + pb) * 0.5 + side * sgn * 1.55 + Vector3.UP * 3.3
		L._kbeam(k, m - d * 2.4, m + d * 2.4, 0.1, 0.7, Color(0.08, 0.16, 0.36), false)
	# Stair/lift tower down to the street on the seaward side, past the road
	# (solid: a landing spot).
	var out := side if (Vector2(c.x, c.z) + Vector2(side.x, side.z)).distance_to(L.island.get_center()) \
		> Vector2(c.x, c.z).distance_to(L.island.get_center()) else -side
	var tw := c + out * 13.8
	var gy := L.terrain.road_y(tw.x, tw.z)
	L._kbeam(k, Vector3(tw.x, gy, tw.z), Vector3(tw.x, c.y + 5.0, tw.z), 4.0, 4.0, Color(0.36, 0.38, 0.4))
	L._kbeam(k, Vector3(tw.x, c.y + 5.0, tw.z), Vector3(tw.x, c.y + 5.3, tw.z), 4.6, 4.6, CANOPY)


# ------------------------------------------------------------ the Valley Line
## Registers the existing elevated line (SetPieces.elevated_rail builds its
## structure) as a shuttle: one track, stations at both ends.
func add_valley(path2: PackedVector2Array, deck: float) -> void:
	var flat := _resample_open(path2, STEP)
	var pts := PackedVector3Array()
	for q in flat:
		pts.append(Vector3(q.x, deck + 0.16, q.y))
	var total := (pts.size() - 1) * STEP
	if total < 120.0:
		return
	lines.append({"name": "valley", "pts": pts, "loop": false, "tracks": [-2.0], "stations": [24.0, total - 24.0],
		"cars": 3})


# ------------------------------------------------------------------- helpers
static func _chord_dev(pts: PackedVector3Array, i: int, j: int) -> float:
	var n := pts.size()
	var a := Vector2(pts[i].x, pts[i].z)
	var b := Vector2(pts[j % n].x, pts[j % n].z)
	var worst := 0.0
	for k in range(i + 1, j):
		var q := Vector2(pts[k].x, pts[k].z)
		worst = maxf(worst, Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q))
	return worst


## Point s metres along a line's samples (wraps for loops, clamps otherwise).
static func _at(pts: PackedVector3Array, s: float) -> Vector3:
	var n := pts.size()
	var f := fposmod(s / STEP, float(n))
	var i := int(f)
	return pts[i].lerp(pts[(i + 1) % n], f - i)


static func _resample_closed(p: PackedVector2Array, step: float) -> PackedVector2Array:
	var loop := p.duplicate()
	loop.append(p[0])
	var out := _resample_open(loop, step)
	out.remove_at(out.size() - 1)
	return out


static func _resample_open(p: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([p[0]])
	var total := CityRoads.length_of(p)
	var n := maxi(1, roundi(total / step))
	var st := total / n
	var acc := 0.0
	var i := 0
	for k in range(1, n + 1):
		var target := k * st
		while i < p.size() - 2 and acc + p[i].distance_to(p[i + 1]) < target:
			acc += p[i].distance_to(p[i + 1])
			i += 1
		var seg := p[i].distance_to(p[i + 1])
		out.append(p[i].lerp(p[i + 1], clampf((target - acc) / maxf(seg, 0.001), 0.0, 1.0)))
	return out


static func _chaikin_closed(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := p.size()
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % n]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out


static func _ease_closed(y: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var n := y.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var acc := 0.0
	for k in range(-r, r + 1):
		acc += y[(k + n) % n]
	for i in n:
		out[i] = acc / (2 * r + 1)
		acc += y[(i + r + 1) % n] - y[(i - r + n) % n]
	return out


## The s within ±reach of s0 where the line is straightest (stations want a
## straight run).
static func _straightest(pts: PackedVector3Array, s0: float, reach: float) -> float:
	var best := s0
	var best_c := INF
	var s := s0 - reach
	while s <= s0 + reach:
		var c := 0.0
		for o: float in [-30.0, 0.0, 30.0]:
			var d0 := _at(pts, s + o) - _at(pts, s + o - 4.0)
			var d1 := _at(pts, s + o + 4.0) - _at(pts, s + o)
			c += Vector2(d0.x, d0.z).normalized().angle_to(Vector2(d1.x, d1.z).normalized()) ** 2
		if c < best_c:
			best_c = c
			best = s
		s += 8.0
	return fposmod(best, pts.size() * STEP)
