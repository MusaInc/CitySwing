class_name TimeTrialMode
extends GameMode
## Fly through every ring in order as fast as possible. The clock starts on
## the first movement; respawning restarts the course.


var course: Dictionary
var rings: Array[Node3D] = []
var next := 0
var started := false
var splits: Array[float] = []
var _prev_pos := Vector3.ZERO


func mode_name() -> String:
	return "Time Trial"


func setup_course(c: Dictionary) -> void:
	course = c
	for i in c["gates"].size():
		var r := _make_gate(c["gates"][i], i)
		world.add_child(r)
		rings.append(r)


func start() -> void:
	super.start()
	_reset()
	hud.flash(course["name"].to_upper(), 2.0)


func _reset() -> void:
	next = 0
	started = false
	elapsed = 0.0
	splits.clear()
	player.respawn(course["start"])
	player.last_safe_position = course["start"]
	player.reset_stats()
	_prev_pos = player.global_position
	_update_ring_visuals()


func current_goal(_p = null) -> Vector3:
	return course["rings"][mini(next, course["rings"].size() - 1)]


func _physics_process(dt: float) -> void:
	if not running:
		return
	if not started:
		if player.speed() > 1.0 or player.line_state != Player.Line.IDLE:
			started = true
		else:
			_hud()
			return
	super._physics_process(dt)
	var g: Dictionary = course["gates"][next]
	var pos := player.global_position
	if _crossed(g, _prev_pos, pos):
		splits.append(elapsed)
		next += 1
		Settings.haptic(15, 0.4)
		if next >= rings.size():
			_complete()
			return
		if audio:
			audio.play("checkpoint")
		_update_ring_visuals()
	_prev_pos = pos
	_hud()


## True when the segment a→b passes through the gate rectangle.
static func _crossed(g: Dictionary, a: Vector3, b: Vector3) -> bool:
	var p: Vector3 = g["pos"]
	var f: Vector3 = g["dir"]
	var da := (a - p).dot(f)
	var db := (b - p).dot(f)
	if da > 0.0 or db < 0.0:
		return false
	var t := da / (da - db) if absf(da - db) > 1e-5 else 0.0
	var x := a.lerp(b, t) - p
	var side := Vector3(-f.z, 0.0, f.x)
	return absf(x.dot(side)) <= g["half_w"] and absf(x.y) <= g["half_h"]


func _hud() -> void:
	var best := SaveData.best_trial(course["id"])
	hud.mode_text = "%s" % _fmt(elapsed)
	var target := ""
	for m in [Progress.Medal.GOLD, Progress.Medal.SILVER, Progress.Medal.BRONZE]:
		var t := Progress.medal_target(course["par"], m)
		if elapsed <= t:
			target = "%s %s" % [Progress.MEDAL_NAMES[m].to_lower(), _fmt(t)]
			break
	hud.mode_sub = "ring %d/%d   ·   %s   ·   best %s" % [mini(next + 1, rings.size()), rings.size(),
		target if target != "" else "no medal", "--" if best == INF else _fmt(best)]


func _complete() -> void:
	var best := SaveData.submit_trial(course["id"], elapsed)
	if audio:
		audio.play("finish")
	for r in rings:
		r.queue_free()
	rings.clear()
	end_run({"mode": "trial", "course": course["name"], "course_id": course["id"], "time": elapsed,
		"new_best": best, "best": SaveData.best_trial(course["id"]), "par": course["par"], "splits": splits,
		"medal": Progress.medal_for(course["par"], elapsed),
		"swings": player.swings, "top_speed": player.top_speed, "chain": player.best_chain})


func _on_respawned() -> void:
	if running and started:
		call_deferred("_reset")


func _on_water() -> void:
	_reset()


func abandon() -> void:
	running = false
	for r in rings:
		r.queue_free()
	rings.clear()


func _update_ring_visuals() -> void:
	for i in rings.size():
		var r := rings[i]
		r.visible = i >= next and i < next + 3
		var m: StandardMaterial3D = r.get_meta("mat")
		var is_next := i == next
		m.albedo_color = Color(1.0, 0.78, 0.3, 0.95 if is_next else 0.35)
		m.emission_energy_multiplier = 1.6 if is_next else 0.4
		(r.get_node("Pillar") as Node3D).visible = is_next


func _make_gate(g: Dictionary, i: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Gate%d" % i
	root.position = g["pos"]
	root.basis = Basis.looking_at(g["dir"], Vector3.UP)
	var w: float = g["half_w"]
	var h: float = g["half_h"]
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.78, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.25)
	for bar in [[Vector3(0, h, 0), Vector3(w * 2.0, 0.5, 0.5)], [Vector3(0, -h, 0), Vector3(w * 2.0, 0.5, 0.5)],
			[Vector3(-w, 0, 0), Vector3(0.5, h * 2.0, 0.5)], [Vector3(w, 0, 0), Vector3(0.5, h * 2.0, 0.5)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bar[1]
		mi.mesh = bm
		mi.position = bar[0]
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	# Faint fill so the opening reads as a target from a distance.
	var fill := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w * 2.0, h * 2.0)
	fill.mesh = qm
	var fm := StandardMaterial3D.new()
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.albedo_color = Color(1.0, 0.8, 0.4, 0.07)
	fill.material_override = fm
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fill)
	root.set_meta("mat", mat)
	var pillar := MeshInstance3D.new()
	pillar.name = "Pillar"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 400.0
	cyl.radial_segments = 8
	pillar.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(1.0, 0.8, 0.4, 0.2)
	pillar.material_override = pm
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pillar.position.y = h + 200.0
	root.add_child(pillar)
	return root


static func _fmt(s: float) -> String:
	if s == INF:
		return "--"
	return "%d:%05.2f" % [int(s) / 60, fmod(s, 60.0)]
