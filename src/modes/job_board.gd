class_name JobBoard
extends Node3D
## Contracts in Free Swing (rules: src/core/contracts.gd).
##
## A handful of offers stand in the city as columns of light on rooftops –
## teal for legal work, red for the Fence – so you find work just by
## swinging around. Landing on an offer's roof (or flying through a rescue
## gondola / survey point) takes the job; the pause menu's Job Board lists
## the same offers and can track one (route pointer + minimap).
##
## One contract runs at a time: a gold column marks the next objective, the
## clock starts at the pickup, and underworld jobs bring pursuit drones. A
## drone that has line of sight within Contracts.SPOT_RADIUS raises heat; at
## full heat you're busted (fined). Drones fly over the rooftops at a fixed
## top speed, so a fast, high line loses them and the heat cools.

signal job_started(c: Dictionary)
signal job_finished(c: Dictionary, outcome: String, coins: int)
signal offers_changed

const LEGAL_OFFERS := 3
const CRIME_OFFERS := 2
const REROLL_DIST := 900.0
const COL_LEGAL := Color(0.36, 0.95, 0.82)
const COL_CRIME := Color(1.0, 0.32, 0.26)
const COL_GOAL := Color(1.0, 0.78, 0.25)
const BEACON_H := 150.0
const HEIGHT_CELL := 20.0

var player: Player
var hud: Hud
var audio: AudioDirector
var layout: CityLayout
var roofs: Array = []          # [{position}] rooftop landing spots
var rescue_spots: Array = []   # [[position, outward normal]]
var vantage: Array = []        # [Vector3]
var offers: Array = []
var tracked := -1              # offer id the route pointer follows (-1 none)
var active := {}
var stage := 0                 # index into active["stops"]
var time_left := 0.0
var heat := 0.0
var spotted := false
var knockouts := 0
var hold_t := 0.0              # heist: seconds held on the target roof
var hold_offer := {}           # the heist offer being cracked
var session_done := 0
var session_coins := 0
## Last settled contract for the HUD toast: {title, outcome, coins, rep, rank_up, t}
var toast := {}

var _rng := RandomNumberGenerator.new()
var _prev := Vector3.ZERO
var _nodes := {}               # offer id -> Node3D (beacon / gondola)
var _goal: Node3D              # the active objective's marker
var _drones: Array = []        # [Drone]
var _next_id := 1
var _reroll_t := 0.0
var _heights := {}             # Vector2i cell -> roof height (drones fly over these)
var _beacon_shader: Shader
var _ray_t := 0.0


static var _spot_cache := {}   # layout instance id -> [rescue, vantage, heights]


func setup(p: Player, h: Hud, a: AudioDirector, world: Node3D, seed_value: int = -1) -> void:
	player = p
	hud = h
	audio = a
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_beacon_shader = load("res://src/world/shaders/beacon.gdshader")
	if world is CityWorld:
		layout = (world as CityWorld).layout
		roofs = (world as CityWorld).rooftop_spawns()
		var cached: Array = spots_for(layout)
		rescue_spots = cached[0]
		vantage = cached[1]
		_heights = cached[2]
	player.knockout.connect(_on_knockout)
	_prev = player.global_position
	refill()


## Gondola spots, survey points and the drones' height grid (cached per layout).
static func spots_for(lay: CityLayout) -> Array:
	var key := lay.get_instance_id()
	if _spot_cache.has(key):
		return _spot_cache[key]
	var grid := TokenField._tier_grid(lay)
	var rescue: Array = []
	var vant: Array = []
	var heights := {}
	for b in lay.buildings:
		for t in b["tiers"]:
			var bx := CityLayout.tier_aabb(b, t)
			for cx in range(floori(bx.position.x / HEIGHT_CELL), floori(bx.end.x / HEIGHT_CELL) + 1):
				for cz in range(floori(bx.position.z / HEIGHT_CELL), floori(bx.end.z / HEIGHT_CELL) + 1):
					var k := Vector2i(cx, cz)
					heights[k] = maxf(heights.get(k, -INF), bx.end.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7351
	for b in lay.buildings:
		if b["kind"] != "normal":
			continue
		var t: Array = b["tiers"][-1]
		var base := BuildingMesher.base_of(b)
		var h: float = t[5] - base
		var x := CityLayout.bxf(b)
		if h >= 45.0 and h <= 170.0 and rng.randf() < 0.35:
			# A gondola hanging off one face of the top tier, 9-22 m below the roof.
			var face := rng.randi() % 4
			var y := clampf(t[5] - rng.randf_range(9.0, 22.0), maxf(t[4], base) + 20.0, t[5] - 6.0)
			var lp: Vector3
			var ln: Vector3
			match face:
				0:
					lp = Vector3(t[2] + 1.4, y, (t[1] + t[3]) * 0.5)
					ln = Vector3.RIGHT
				1:
					lp = Vector3(t[0] - 1.4, y, (t[1] + t[3]) * 0.5)
					ln = Vector3.LEFT
				2:
					lp = Vector3((t[0] + t[2]) * 0.5, y, t[3] + 1.4)
					ln = Vector3.BACK
				_:
					lp = Vector3((t[0] + t[2]) * 0.5, y, t[1] - 1.4)
					ln = Vector3.FORWARD
			var wp := x * lp
			var wn := (x.basis * ln).normalized()
			if not TokenField._blocked(grid, wp + wn * 9.0) and not TokenField._blocked(grid, wp + wn * 16.0):
				rescue.append([wp, wn])
		if h >= 70.0 and rng.randf() < 0.5:
			var p := CityLayout.top_center(b) + Vector3.UP * 12.0
			var clear := not TokenField._blocked(grid, p)
			for q in vant:
				if q.distance_to(p) < 70.0:
					clear = false
					break
			if clear:
				vant.append(p)
	var out := [rescue, vant, heights]
	_spot_cache[key] = out
	return out


func roof_height_at(p: Vector3) -> float:
	return float(_heights.get(Vector2i(floori(p.x / HEIGHT_CELL), floori(p.z / HEIGHT_CELL)), 0.0))


func rep() -> int:
	return int(_save().data.get("rep", 0))


# -------------------------------------------------------------- offers
## Tops the offers back up (3 legal, 2 underworld) around the player.
func refill() -> void:
	var from := player.global_position
	var legal := offers.filter(func(c): return c["legal"]).size()
	var crime := offers.size() - legal
	var tries := 0
	while (legal < LEGAL_OFFERS or crime < CRIME_OFFERS) and tries < 30:
		tries += 1
		var want_legal := legal < LEGAL_OFFERS
		var pool: Array = (Contracts.LEGAL_TYPES if want_legal else Contracts.CRIME_TYPES).duplicate()
		# Variety: prefer a type that isn't already on offer.
		var fresh := pool.filter(func(t): return offers.all(func(o): return o["type"] != t))
		var type: String = (fresh if not fresh.is_empty() else pool)[_rng.randi() % (fresh if not fresh.is_empty() else pool).size()]
		var top := Contracts.max_tier(rep())
		var tier := _rng.randi_range(maxi(1, top - 1), top)
		var c := Contracts.make(_rng, type, tier, from, roofs, rescue_spots.map(func(r): return r[0]), vantage)
		if c.is_empty() or _too_close(c["start"]):
			continue
		c["id"] = _next_id
		_next_id += 1
		offers.append(c)
		_spawn_offer(c)
		if want_legal:
			legal += 1
		else:
			crime += 1
	offers_changed.emit()


func _too_close(p: Vector3) -> bool:
	for o in offers:
		if (o["start"] as Vector3).distance_to(p) < 60.0:
			return true
	return false


func offer_by_id(id: int) -> Dictionary:
	for o in offers:
		if o["id"] == id:
			return o
	return {}


func track(id: int) -> void:
	tracked = id if tracked != id else -1


func _remove_offer(c: Dictionary) -> void:
	offers.erase(c)
	if _nodes.has(c["id"]):
		(_nodes[c["id"]] as Node3D).queue_free()
		_nodes.erase(c["id"])
	if tracked == c["id"]:
		tracked = -1


# ------------------------------------------------------------- the loop
func _physics_process(dt: float) -> void:
	if player == null:
		return
	var a := _prev
	var b := player.global_position
	_prev = b
	if a.distance_to(b) > 40.0:
		a = b  # a respawn/teleport is not a fly-through
	var grounded := player.is_on_floor() and not player.stunned
	if active.is_empty():
		_check_offers(a, b, grounded, dt)
		_reroll_t -= dt
		if _reroll_t <= 0.0:
			_reroll_t = 12.0
			for o in offers.duplicate():
				if o["id"] != tracked and (o["start"] as Vector3).distance_to(b) > REROLL_DIST:
					_remove_offer(o)
			refill()
	else:
		_run_active(a, b, grounded, dt)
	if not toast.is_empty():
		toast["t"] = float(toast["t"]) + dt
		if toast["t"] > 4.5:
			toast = {}


func _check_offers(a: Vector3, b: Vector3, grounded: bool, dt: float) -> void:
	var holding := false
	for c in offers:
		var s: Vector3 = c["start"]
		if c["start_kind"] == "hold":
			if Contracts.reached("land", s, a, b, grounded) and player.speed() < Contracts.HOLD_SPEED:
				holding = true
				if hold_offer.get("id", -1) != c["id"]:
					hold_offer = c
					hold_t = 0.0
					hud.flash("CRACKING THE CASE…", 1.2)
				hold_t += dt
				if hold_t >= Contracts.HOLD_TIME:
					_begin(c)
					return
			continue
		if Contracts.reached(String(c["start_kind"]), s, a, b, grounded):
			_begin(c)
			return
	if not holding:
		hold_t = 0.0
		hold_offer = {}


func _begin(c: Dictionary) -> void:
	_remove_offer(c)
	active = c
	stage = 0
	time_left = float(c["time"])
	heat = 0.0
	knockouts = 0
	hold_t = 0.0
	hold_offer = {}
	if audio:
		audio.play("checkpoint", 0.0, 0.9)
	Settings.haptic(30, 0.6)
	var verb: String = {"rescue": "CLIENT ABOARD", "survey": "SURVEY STARTED", "heist": "CASE CRACKED — RUN",
		"getaway": "THEY'VE SEEN YOU — RUN"}.get(c["type"], "PARCEL COLLECTED")
	hud.flash(verb, 1.8)
	if c["heat"]:
		heat = 0.3 if c["type"] == "getaway" else 0.12
		for i in int(c["drones"]):
			_spawn_drone(i)
	_place_goal()
	job_started.emit(c)


func _run_active(a: Vector3, b: Vector3, grounded: bool, dt: float) -> void:
	time_left -= dt
	var target: Vector3 = active["stops"][stage]
	var kind: String = active["stop_kinds"][stage]
	if Contracts.reached(kind, target, a, b, grounded):
		stage += 1
		if stage >= (active["stops"] as Array).size():
			_finish("done")
			return
		if audio:
			audio.play("checkpoint", -2.0, 1.1 + 0.05 * stage)
		hud.flash("%d / %d" % [stage, (active["stops"] as Array).size()], 0.9)
		_place_goal()
	if active["heat"]:
		_update_drones(dt)
		heat = Contracts.heat_step(heat, spotted, player.on_street, int(active["tier"]), dt)
		if heat >= 1.0:
			_finish("busted")
			return
	if time_left <= 0.0:
		_finish("late")


## Starts a contract of `type` from the nearest suitable spot (captures/QA).
func start_now(type: String) -> bool:
	for o in offers:
		if o["type"] == type:
			_begin(o)
			return true
	var c := Contracts.make(_rng, type, Contracts.max_tier(rep()), player.global_position, roofs,
		rescue_spots.map(func(r): return r[0]), vantage)
	if c.is_empty():
		return false
	c["id"] = _next_id
	_next_id += 1
	_begin(c)
	return true


func abandon() -> void:
	if not active.is_empty():
		_finish("abandoned")


func _finish(outcome: String) -> void:
	var c := active
	var r := Contracts.settle(c, outcome, time_left, knockouts)
	var before := Contracts.rank_for(rep())
	var paid: int = _save().record_job(bool(c["legal"]), outcome, int(r["coins"]), int(r["rep"]))
	var rank_up := Contracts.rank_for(rep()) > before
	if outcome == "done":
		session_done += 1
	session_coins += paid
	toast = {"title": c["title"], "outcome": outcome, "coins": paid, "bonus": r["bonus"], "rep": r["rep"],
		"rank_up": rank_up, "rank": Contracts.rank_name(rep()), "legal": c["legal"], "t": 0.0}
	if audio:
		audio.play("finish" if outcome == "done" else "fail")
	Settings.haptic(60 if outcome == "done" else 120, 0.8)
	active = {}
	stage = 0
	heat = 0.0
	spotted = false
	for d in _drones:
		(d as Node3D).queue_free()
	_drones.clear()
	if is_instance_valid(_goal):
		_goal.queue_free()
	_goal = null
	job_finished.emit(c, outcome, paid)
	refill()


func _on_knockout(_spd: float, _n: Vector3) -> void:
	if active.is_empty():
		return
	knockouts += 1
	if active["heat"]:
		heat = minf(heat + Contracts.HEAT_KNOCKOUT, 1.0)


## The current objective (world point), or the tracked offer's start, or INF.
func objective() -> Vector3:
	if not active.is_empty():
		return active["stops"][stage]
	var o := offer_by_id(tracked)
	return o["start"] if not o.is_empty() else Vector3.INF


## Minimap markers: [[pos, kind]].
func markers() -> Array:
	var out: Array = []
	if not active.is_empty():
		out.append([active["stops"][stage], "next"])
		return out
	for o in offers:
		out.append([o["start"], "next" if o["id"] == tracked else ("job" if o["legal"] else "crime")])
	return out


# -------------------------------------------------------------- visuals
func _beacon(col: Color, height: float, top_r: float, bot_r: float, strength := 1.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.height = height
	cy.top_radius = top_r
	cy.bottom_radius = bot_r
	cy.radial_segments = 14
	cy.rings = 1
	cy.cap_top = false
	cy.cap_bottom = false
	m.mesh = cy
	var mat := ShaderMaterial.new()
	mat.shader = _beacon_shader
	mat.set_shader_parameter("tint", col)
	mat.set_shader_parameter("strength", strength)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position.y = height * 0.5
	m.extra_cull_margin = 4.0
	return m


func _ring(col: Color, r: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = r - 0.35
	t.outer_radius = r
	t.rings = 28
	t.ring_segments = 6
	m.mesh = t
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.6
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## A marker for a point: a column (and a landing pad or fly-through ring).
func _marker(p: Vector3, kind: String, col: Color, strength := 1.0) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	if kind == "pass":
		n.global_position = p
		var ring := _ring(col, Contracts.PASS_R * 0.7)
		ring.rotation.x = PI * 0.5
		ring.name = "Ring"
		n.add_child(ring)
		var col_m := _beacon(col, BEACON_H * 0.6, 0.5, 0.9, strength * 0.7)
		col_m.position.y += 3.0
		n.add_child(col_m)
	else:
		n.global_position = p - Vector3(0, 0.95, 0)  # spots are standing capsule centres
		n.add_child(_beacon(col, BEACON_H, 1.3, 2.6, strength))
		var pad := _beacon(col, 2.6, Contracts.LAND_R * 0.75, Contracts.LAND_R * 0.8, strength * 0.8)
		n.add_child(pad)
	return n


func _spawn_offer(c: Dictionary) -> void:
	var col := COL_LEGAL if c["legal"] else COL_CRIME
	var n := _marker(c["start"], "pass" if c["start_kind"] == "pass" else "land", col, 0.85)
	if c["type"] == "rescue":
		_add_gondola(n, c["start"])
	_nodes[c["id"]] = n


func _place_goal() -> void:
	if is_instance_valid(_goal):
		_goal.queue_free()
	_goal = _marker(active["stops"][stage], active["stop_kinds"][stage], COL_GOAL, 1.2)


## A window cleaner's cradle hanging off the facade: deck, rails, two cables
## up to the roof and the stranded cleaner waving.
func _add_gondola(n: Node3D, p: Vector3) -> void:
	var nrm := Vector3.FORWARD
	for r in rescue_spots:
		if (r[0] as Vector3).is_equal_approx(p):
			nrm = r[1]
	var g := Node3D.new()
	g.name = "Gondola"
	n.add_child(g)
	g.global_position = p - nrm * 0.6
	g.global_basis = Basis.looking_at(-nrm, Vector3.UP)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.82, 0.83, 0.85)
	steel.metallic = 0.6
	steel.roughness = 0.45
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.95, 0.72, 0.12)
	yellow.roughness = 0.6
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.95, 0.42, 0.12)
	var add_box := func(size: Vector3, pos: Vector3, mat: Material) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		mi.position = pos
		g.add_child(mi)
	add_box.call(Vector3(4.2, 0.18, 1.0), Vector3(0, -1.0, 0), yellow)        # deck
	add_box.call(Vector3(4.2, 0.08, 0.08), Vector3(0, 0.05, -0.46), steel)    # front rail
	add_box.call(Vector3(4.2, 0.4, 0.06), Vector3(0, -0.75, -0.48), yellow)   # kick plate
	for sx in [-2.05, 2.05]:
		add_box.call(Vector3(0.08, 1.05, 1.0), Vector3(sx, -0.45, 0), steel)  # end frames
		add_box.call(Vector3(0.04, 24.0, 0.04), Vector3(sx, 11.9, 0.2), steel) # cables
	# The cleaner: high-vis torso, head, an arm waving (animated in _process).
	add_box.call(Vector3(0.5, 0.75, 0.32), Vector3(0.6, -0.42, 0.05), body)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	head.mesh = sm
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.78, 0.6, 0.48)
	head.material_override = skin
	head.position = Vector3(0.6, 0.1, 0.05)
	g.add_child(head)
	var arm := Node3D.new()
	arm.name = "Arm"
	arm.position = Vector3(0.85, -0.12, 0.05)
	g.add_child(arm)
	var am := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(0.12, 0.6, 0.12)
	am.mesh = ab
	am.material_override = body
	am.position = Vector3(0, 0.28, 0)
	arm.add_child(am)
	g.rotate_object_local(Vector3.FORWARD, deg_to_rad(4.0))  # one cable has slipped


func _process(_dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for id in _nodes:
		var g: Node3D = (_nodes[id] as Node3D).get_node_or_null("Gondola")
		if g:
			var arm: Node3D = g.get_node("Arm")
			arm.rotation.z = -0.6 + sin(t * 7.0) * 0.55
		var ring: Node3D = (_nodes[id] as Node3D).get_node_or_null("Ring")
		if ring:
			ring.rotation.y = t * 0.6
	if is_instance_valid(_goal):
		var ring: Node3D = _goal.get_node_or_null("Ring")
		if ring:
			ring.rotation.y = t * 1.2


# --------------------------------------------------------------- drones
class Drone:
	extends Node3D
	var vel := Vector3.ZERO
	var light: MeshInstance3D
	var cone: MeshInstance3D
	var rotors: Array = []
	var lit_mat: StandardMaterial3D


func _spawn_drone(i: int) -> void:
	var d := Drone.new()
	d.name = "Drone%d" % i
	add_child(d)
	var ang := _rng.randf() * TAU
	var behind := -Vector3(player.s.velocity.x, 0, player.s.velocity.z).normalized()
	if behind.length_squared() < 0.5:
		behind = Vector3.FORWARD.rotated(Vector3.UP, ang)
	var side := behind.cross(Vector3.UP) * (i - 0.5) * 30.0
	d.global_position = player.global_position + behind * 75.0 + side + Vector3.UP * 22.0
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.12, 0.13, 0.16)
	hull.metallic = 0.5
	hull.roughness = 0.35
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.9, 0.92, 0.95)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 0.32, 1.4)
	body.mesh = bm
	body.material_override = hull
	d.add_child(body)
	var stripe := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(1.12, 0.1, 0.5)
	stripe.mesh = sb
	stripe.material_override = white
	stripe.position = Vector3(0, 0.05, 0.2)
	d.add_child(stripe)
	for k in 4:
		var arm_dir := Vector3(1 if k % 2 == 0 else -1, 0, 1 if k < 2 else -1).normalized()
		var arm := MeshInstance3D.new()
		var abm := BoxMesh.new()
		abm.size = Vector3(0.1, 0.08, 1.0)
		arm.mesh = abm
		arm.material_override = hull
		arm.position = arm_dir * 0.75
		arm.basis = Basis.looking_at(arm_dir, Vector3.UP)
		d.add_child(arm)
		var rotor := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.42
		cm.bottom_radius = 0.42
		cm.height = 0.03
		cm.radial_segments = 10
		rotor.mesh = cm
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.2, 0.2, 0.22, 0.45)
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rotor.material_override = rm
		rotor.position = arm_dir * 1.15 + Vector3.UP * 0.18
		d.add_child(rotor)
	d.lit_mat = StandardMaterial3D.new()
	d.lit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	d.lit_mat.emission_enabled = true
	d.light = MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.7, 0.1, 0.16)
	d.light.mesh = lb
	d.light.material_override = d.lit_mat
	d.light.position = Vector3(0, 0.22, 0)
	d.add_child(d.light)
	# Search beam: an additive cone toward the player while it has you.
	d.cone = MeshInstance3D.new()
	var cone_m := CylinderMesh.new()
	cone_m.top_radius = 1.8     # +Y points at the target (see _update_drones)
	cone_m.bottom_radius = 0.15
	cone_m.height = 1.0
	cone_m.radial_segments = 12
	cone_m.cap_top = false
	cone_m.cap_bottom = false
	d.cone.mesh = cone_m
	var cmat := ShaderMaterial.new()
	cmat.shader = _beacon_shader
	cmat.set_shader_parameter("tint", Color(0.85, 0.9, 1.0))
	cmat.set_shader_parameter("strength", 0.35)
	cmat.set_shader_parameter("pulse_rate", 0.0)
	d.cone.material_override = cmat
	d.cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.cone.visible = false
	d.add_child(d.cone)
	_drones.append(d)


func _update_drones(dt: float) -> void:
	var pp := player.global_position
	var top := Contracts.drone_speed(int(active["tier"]))
	var seen := false
	_ray_t -= dt
	var cast := _ray_t <= 0.0
	if cast:
		_ray_t = 0.15
	var space := get_world_3d().direct_space_state if cast else null
	var t := Time.get_ticks_msec() / 1000.0
	for d: Drone in _drones:
		var to := pp + Vector3.UP * 7.0 - d.global_position
		var dist := to.length()
		var flat := Vector3(to.x, 0, to.z)
		var fd := flat.length()
		var dir := flat / fd if fd > 0.01 else Vector3.ZERO
		# Route: straight at you if the roofs ahead are below it, else the
		# nearest heading either side that is clear; climb only if none is.
		# Altitude: your height (plus a little) once close, otherwise just
		# over the roofs it is about to cross.
		var alt := pp.y + 7.0
		var blocked := false
		if fd > 30.0:
			var cap := maxf(pp.y + 30.0, d.global_position.y)
			var best := Vector3.ZERO
			for turn in [0.0, 0.6, -0.6, 1.2, -1.2]:
				var cd := dir.rotated(Vector3.UP, turn)
				var hi := 0.0
				for k in [15.0, 30.0, 45.0]:
					hi = maxf(hi, roof_height_at(d.global_position + cd * k) + 9.0)
				if hi <= cap:
					best = cd
					alt = maxf(alt, hi)
					break
			if best == Vector3.ZERO:
				blocked = true
				alt = maxf(alt, roof_height_at(d.global_position + dir * 20.0) + 12.0)
			else:
				dir = best
			alt = maxf(alt, roof_height_at(d.global_position) + 6.0)
		var hs := top * (0.35 if blocked else 1.0)
		if fd < 14.0:
			hs *= fd / 14.0  # hover off your shoulder instead of ramming
		var dv := dir * hs + Vector3.UP * clampf((alt - d.global_position.y) * 1.5, -12.0, 14.0)
		d.vel = d.vel.move_toward(dv, Contracts.DRONE_ACCEL * dt)
		d.global_position += d.vel * dt
		# Bank into the flight direction; spin the rotors.
		var fwd := Vector3(d.vel.x, 0, d.vel.z)
		if fwd.length() > 0.5:
			var yaw := atan2(-fwd.x, -fwd.z)
			d.rotation.y = lerp_angle(d.rotation.y, yaw, minf(dt * 4.0, 1.0))
		d.rotation.x = lerpf(d.rotation.x, -clampf(fwd.length() / top, 0.0, 1.0) * 0.35, minf(dt * 3.0, 1.0))
		var blue := fmod(t * 3.0, 1.0) < 0.5
		d.lit_mat.albedo_color = Color(1.0, 0.15, 0.12) if blue else Color(0.15, 0.35, 1.0)
		d.lit_mat.emission = d.lit_mat.albedo_color * 2.5
		var has := dist < Contracts.SPOT_RADIUS
		if has and cast:
			var q := PhysicsRayQueryParameters3D.create(d.global_position, pp + Vector3.UP * 0.5, 1)
			has = space.intersect_ray(q).is_empty()
			d.set_meta("los", has)
		elif has:
			has = bool(d.get_meta("los", true))
		seen = seen or has
		d.cone.visible = has
		if has:
			var tgt := pp - Vector3.UP * 0.5
			var len := d.global_position.distance_to(tgt)
			d.cone.global_basis = Basis.looking_at(tgt - d.global_position, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
			d.cone.scale = Vector3(1, len, 1)
			d.cone.global_position = d.global_position.lerp(tgt, 0.5)
	spotted = seen


## Looked up by path so tools run with -s (no autoload globals) can load this.
func _save() -> Node:
	return get_node("/root/SaveData")
