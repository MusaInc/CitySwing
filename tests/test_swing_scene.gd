extends Node
## Scene-level tests: real Jolt collision, real raycast targeting, the real
## Player controller, driven by the autopilot through the human input path.
## Run with --fixed-fps 60 so simulated time is deterministic and fast.

var world: PrototypeWorld
var player: Player


func setup() -> void:
	world = PrototypeWorld.new()
	add_child(world)
	player = Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	if OS.has_environment("NO_WRAP"):
		player.params.rope_wrapping = false
	add_child(player)
	player.global_position = world.spawn_point()
	player.last_safe_position = player.global_position
	await get_tree().physics_frame


func teardown() -> void:
	player.queue_free()
	world.queue_free()
	await get_tree().process_frame


## Runs the bot until it reaches `goal_z`, touches the street, or times out.
func _run(bot: SwingBot, seconds: float, goal_z: float) -> Dictionary:
	player.bot = bot
	var res := {"street": false, "best_z": 0.0, "time": 0.0, "max_speed": 0.0, "swings": 0}
	player.landed.connect(func(_s, street): if street: res["street"] = true)
	var frames := int(seconds * 60)
	for i in frames:
		await get_tree().physics_frame
		res["best_z"] = minf(res["best_z"], player.global_position.z)
		res["max_speed"] = maxf(res["max_speed"], player.speed())
		res["time"] = i / 60.0
		if res["street"] or player.global_position.z < goal_z:
			break
	res["swings"] = player.swings
	return res


func test_targeting_finds_building_geometry(t) -> void:
	player.targeting.update(get_viewport().world_3d.direct_space_state, player.hand_position(),
		Vector3.FORWARD, Vector3.ZERO, player.params, false, [player.get_rid()])
	if t.check(player.targeting.has_target, "should see the tower ahead"):
		t.check(player.targeting.point.y > player.global_position.y + 3.0, "anchor is above the player")
		t.check(player.targeting.point.z < -40.0, "anchor is on the tower ahead, z=%.1f" % player.targeting.point.z)
	player.targeting.update(get_viewport().world_3d.direct_space_state, player.hand_position(),
		Vector3.BACK, Vector3.ZERO, player.params, false, [player.get_rid()])
	t.check(not player.targeting.has_target, "nothing to grab behind (open sky)")


## Swinging is chaotic: a few centimetres at the start change everything after
## the first crash. So skill is judged over several starts, not one lucky run.
const STARTS := [Vector3(0, 0, 0), Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 2), Vector3(3, 0, 1)]


func _trials(style: int) -> Array:
	var out: Array = []
	for off in STARTS:
		await teardown()
		await setup()
		player.respawn(world.spawn_point() + off)
		var bot := SwingBot.new(style, Vector3.FORWARD)
		bot.goal_fn = world.bot_goal
		out.append(await _run(bot, 60.0, -420.0))
	return out


func test_skill_gap_expert_vs_novice(t) -> void:
	var experts := await _trials(SwingBot.Style.EXPERT)
	var novices := await _trials(SwingBot.Style.NOVICE)
	var ed: Array[float] = []
	var nd: Array[float] = []
	var cleared := 0
	for r in experts:
		ed.append(-r["best_z"])
		if not r["street"] and r["best_z"] < -420.0:
			cleared += 1
	for r in novices:
		nd.append(-r["best_z"])
	ed.sort()
	nd.sort()
	t.note("expert distances %s (cleared %d/%d), novice %s" % [ed, cleared, experts.size(), nd])
	t.check(ed[2] > nd[2] * 2.5, "skilled timing goes much further (median %.0f m vs %.0f m)" % [ed[2], nd[2]])
	t.check(cleared >= 1, "the whole range can be cleared without touching the street")
	var novice_fails := 0
	for r in novices:
		if r["street"] or r["best_z"] > -420.0:
			novice_fails += 1
	t.check(novice_fails == novices.size(), "poor timing never clears it")


func test_cannot_tunnel_through_buildings(t) -> void:
	# Fire the player at a tower face at 70 m/s (max fall speed class).
	player.global_position = Vector3(-16, 30, 0)
	player.s.velocity = Vector3(0, 0, -70)
	player.bot = _Idle.new()
	for i in 90:
		await get_tree().physics_frame
	# Tower 1 spans z in [-68, -52]; the player must be stopped at its face.
	t.check(player.global_position.z > -52.5 or player.global_position.y > 70.0,
		"player ended at z=%.2f, inside the building" % player.global_position.z)


func test_release_preserves_momentum_in_scene(t) -> void:
	var bot := _Hold.new()
	player.bot = bot
	player.global_position = Vector3(0, 40, -20)
	player.s.velocity = Vector3(0, 0, -15)
	bot.hold = true
	for i in 90:
		await get_tree().physics_frame
	if not t.check(player.line_state == Player.Line.ATTACHED, "should be attached"):
		return
	var before := player.s.velocity
	bot.hold = false
	await get_tree().physics_frame
	var after := player.s.velocity
	var expected_y := before.y - player.params.gravity / 60.0
	t.check(Vector3(after.x, 0, after.z).distance_to(Vector3(before.x, 0, before.z)) < 0.5,
		"horizontal velocity carried through release")
	t.near(after.y, expected_y, 0.6, "vertical continues ballistically")


func test_falls_respawn_at_last_safe_point(t) -> void:
	player.bot = _Idle.new()
	player.last_safe_position = Vector3(0, 31, 4)
	player.global_position = Vector3(300, player.params.kill_plane_y + 1.0, 0)  # off the map edge
	var respawned := [false]
	player.respawned.connect(func(): respawned[0] = true)
	for i in 60:
		await get_tree().physics_frame
	t.check(respawned[0], "respawn fired below the kill plane")
	t.check(player.global_position.distance_to(Vector3(0, 31, 4)) < 2.0, "back on the safe rooftop")


class _Idle:
	extends RefCounted
	func drive(_p, _dt) -> Dictionary:
		return {"move": Vector3.ZERO, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}


class _Hold:
	extends RefCounted
	var hold := false
	func drive(_p, _dt) -> Dictionary:
		return {"move": Vector3.ZERO, "aim": (Vector3.FORWARD + Vector3.UP).normalized(), "grapple": hold,
			"reel": 0.0, "jump": false}


func test_wall_kick_pushes_off(t) -> void:
	# Hang against the +x face of tower 1 (x in [-24,-8]) and jump.
	var bot := _Jump.new()
	player.bot = bot
	player.global_position = Vector3(-7.4, 40, -60)
	player.s.velocity = Vector3(-5, 0, 0)
	for i in 6:
		await get_tree().physics_frame
	bot.jump = true
	await get_tree().physics_frame
	bot.jump = false
	for i in 20:
		await get_tree().physics_frame
	t.check(player.global_position.x > -4.0, "kicked away from the wall (x=%.1f)" % player.global_position.x)


class _Jump:
	extends RefCounted
	var jump := false
	var kicked := false
	func drive(_p, _dt) -> Dictionary:
		kicked = kicked or jump
		var mv := Vector3.ZERO if kicked else Vector3(-1, 0, 0)
		return {"move": mv, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": jump}
