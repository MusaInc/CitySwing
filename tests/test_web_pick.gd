extends Node
## The assisted web pick: the left stick steers it, and it is chosen by
## flying each candidate's swing (clear of buildings, best momentum out).

var world: Node3D
var player: Player


class _Steer:
	extends RefCounted
	var move := Vector3.ZERO
	func drive(_p, _dt) -> Dictionary:
		return {"move": move, "aim": Vector3.FORWARD, "grapple": false, "reel": 0.0, "jump": false}


func setup() -> void:
	world = Node3D.new()
	add_child(world)
	PrototypeWorld.add_box(world, Vector3(0, -0.5, 0), Vector3(600, 1, 600), Color.GRAY, false, true)
	# Two towers, one to the left and one to the right, a little ahead.
	PrototypeWorld.add_box(world, Vector3(-40, 45, -25), Vector3(16, 90, 16), Color.WHITE)
	PrototypeWorld.add_box(world, Vector3(40, 45, -25), Vector3(16, 90, 16), Color.WHITE)
	player = Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	add_child(player)
	player.bot = _Steer.new()
	await get_tree().physics_frame


func teardown() -> void:
	player.queue_free()
	world.queue_free()
	await get_tree().process_frame


## Holds the player mid-air, moving forward, with the stick at `steer`, and
## returns the pick after the targeting has settled.
func _pick_with(steer: Vector3) -> Dictionary:
	player.respawn(Vector3(0, 35, 0))
	(player.bot as _Steer).move = steer
	for i in 20:  # respawn() zeroes the smoothed stick: hold the state by hand
		player.global_position = Vector3(0, 35, 0)
		player.s.velocity = Vector3(0, 2, -16)
		await get_tree().physics_frame
	var t := player.targeting
	return {"ok": t.pick_ok, "pick": t.pick, "gain": t.pick_gain}


func test_left_stick_steers_the_web(t) -> void:
	var right := await _pick_with(Vector3.RIGHT)
	var left := await _pick_with(Vector3.LEFT)
	t.note("stick right → pick x=%.1f (gain %.1f m/s); stick left → pick x=%.1f (gain %.1f m/s)" % [
		right["pick"].x, right["gain"], left["pick"].x, left["gain"]])
	t.check(right["ok"] and left["ok"], "a flyable web exists both ways")
	t.check(right["pick"].x > 20.0, "stick right picks the right-hand tower")
	t.check(left["pick"].x < -20.0, "stick left picks the left-hand tower")


func test_pick_avoids_swings_into_walls(t) -> void:
	# Ahead: a block we are flying straight at; off to the right, a tall
	# tower. Anchors on the block's face swing the body into
	# it; the pick must be a swing that clears it.
	var face := Node3D.new()
	world.add_child(face)
	PrototypeWorld.add_box(face, Vector3(0, 30, -30), Vector3(14, 60, 10), Color.WHITE)
	PrototypeWorld.add_box(face, Vector3(30, 50, -20), Vector3(14, 100, 14), Color.WHITE)
	await get_tree().physics_frame
	(player.bot as _Steer).move = Vector3.ZERO
	var clear := 0
	var crash := 0
	var picks := 0
	var space := world.get_world_3d().direct_space_state
	for k in 8:
		player.respawn(Vector3(-6.0 + k * 1.5, 30, 15))
		player.s.velocity = Vector3(0, 0, -18)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var tg := player.targeting
		tg.refresh_pick(space, player.s, player.params, [player.get_rid()], 0.0, true)
		if not tg.has_target:
			continue
		# How many of the ranked candidates would crash?
		for c in tg._candidates.slice(0, GrappleTargeting.PREDICT_TOP):
			if not GrappleTargeting.predict_swing(space, player.s, c[1], player.params, [player.get_rid()], tg.heading)["clear"]:
				crash += 1
		if tg.pick_ok:
			picks += 1
			if GrappleTargeting.predict_swing(space, player.s, tg.pick, player.params, [player.get_rid()], tg.heading)["clear"]:
				clear += 1
	face.queue_free()
	t.note("%d starts with a pick, %d of them clear; %d of the top candidates would have crashed" % [picks, clear, crash])
	t.check(picks >= 4, "most starts find a web")
	t.check(clear == picks, "every pick's predicted swing clears the buildings")
