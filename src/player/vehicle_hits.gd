class_name VehicleHits
extends Node
## Cars and trains hit people: a player standing or running in the path of
## a moving car (on the street) or train (beside it, not riding on its roof)
## is thrown with it, limp – Player.hit_by, a knockout. People only: bots
## and recorded courses never meet traffic (Player.hit_by ignores them).
##
## Cars are drawn on the GPU and have no collision, so their positions come
## from Traffic (car_position, the same function the shader runs). The few
## cars near the player are listed a few times a second; those are tested
## against the body every physics tick.

const CAR_HALF := Vector3(1.05, 0.0, 2.35)   # half width / half length (m)
const CAR_TOP := 1.7
const MIN_SPEED := 3.0                       # m/s: slower is a nudge, not a hit
const LIST_EVERY := 0.2

var player: Player
var world: CityWorld
var _near: PackedInt32Array = []
var _list_t := 0.0


func _physics_process(dt: float) -> void:
	if player == null or world == null or player.stunned or player.scripted or player.bot != null:
		return
	var p := player.global_position
	_trains(p)
	if player.stunned:
		return
	var tr := world.traffic
	if tr == null or player.height_above_ground() > 2.6:
		return
	_list_t -= dt
	if _list_t <= 0.0:
		_list_t = LIST_EVERY
		_near.clear()
		for id in tr.car_count():
			if tr.car_position(id).distance_squared_to(p) < 45.0 * 45.0:
				_near.append(id)
	var feet := p.y - 0.9
	for id in _near:
		var v := tr.car_speed(id)
		if v < MIN_SPEED:
			continue
		var c := tr.car_position(id)
		if feet > c.y + CAR_TOP or p.y < c.y - 0.5:
			continue
		var f := tr.lane_dir(tr.c_lane[id], tr.car_s(id, tr.now))
		var side := Vector3(-f.z, 0.0, f.x)
		var d := p - c
		# The body's radius (0.35) on top of the car's box.
		if absf(d.dot(f)) < CAR_HALF.z + 0.35 and absf(d.dot(side)) < CAR_HALF.x + 0.35:
			player.hit_by("car", f * v)
			return


func _trains(p: Vector3) -> void:
	var trains := world.trains
	if trains == null:
		return
	var hit := trains.hit_test(p)
	if hit != Vector3.ZERO:
		player.hit_by("train", hit)
