class_name NearMiss
extends Node
## Close calls: flying past a building at speed, within a couple of metres,
## without touching it. The reward for risky lines – coins, multiplier
## progress, a whoosh and a HUD callout. Head-on approaches don't count
## (that's a crash in the making, not a pass), and nothing counts if the pass
## ends in a bump, a stagger or a knockout.
##   Cost: two rays per physics tick while airborne above MIN_SPEED.

signal close_call(distance: float, speed: float, razor: bool)

const MIN_SPEED := 16.0      # m/s (58 km/h)
const REACH := 3.0           # m from the body's centre line
const RAZOR := 1.3           # m: a "razor" pass pays double
const ALONG := 0.42          # |v̂·n| above this is heading INTO the wall
const COOLDOWN := 1.0        # s between awards
const SETTLE := 0.25         # s clear of the wall before the pass is paid

var player: Player
var run_count := 0   # close calls this run (main resets it, results show it)
var _in_pass := false
var _min_d := INF
var _pass_speed := 0.0
var _clear_t := 0.0
var _cool := 0.0
var _spoiled := false
var _q: PhysicsRayQueryParameters3D


func set_player(p: Player) -> void:
	player = p
	var spoil := func(_a = null, _b = null): _spoiled = true
	p.bumped.connect(spoil)
	p.staggered.connect(spoil)
	p.knockout.connect(spoil)
	p.impact.connect(spoil)
	p.respawned.connect(func(): _reset())


func _reset() -> void:
	_in_pass = false
	_min_d = INF
	_spoiled = false
	_clear_t = 0.0


func _physics_process(dt: float) -> void:
	_cool = maxf(_cool - dt, 0.0)
	if player == null:
		return
	var v := player.s.velocity
	var vh := Vector3(v.x, 0.0, v.z)
	var airborne := not player.is_on_floor() and not player.stunned and not player.knocked_out
	var d := INF
	if airborne and v.length() >= MIN_SPEED and vh.length() > 4.0:
		d = _side_distance(v, vh)
	if d < REACH:
		if not _in_pass:
			_in_pass = true
			_min_d = d
			_spoiled = false
			_pass_speed = v.length()
		_min_d = minf(_min_d, d)
		_pass_speed = maxf(_pass_speed, v.length())
		_clear_t = 0.0
		return
	if not _in_pass:
		return
	_clear_t += dt
	if not airborne and not player.s.attached:
		_spoiled = _spoiled or player.stunned
	if _clear_t < SETTLE:
		return
	var ok := not _spoiled and _cool <= 0.0 and not player.stunned and not player.knocked_out
	_in_pass = false
	if ok:
		_cool = COOLDOWN
		run_count += 1
		close_call.emit(_min_d, _pass_speed, _min_d < RAZOR)


## Nearest facade beside the flight path (left or right), or INF. Only walls
## the hero is sliding past – roughly parallel to the velocity – count.
func _side_distance(v: Vector3, vh: Vector3) -> float:
	if _q == null:
		_q = PhysicsRayQueryParameters3D.new()
		_q.collision_mask = 1 | (1 << 1)
	_q.exclude = [player.get_rid()]
	var space := player.get_world_3d().direct_space_state
	var side := vh.normalized().cross(Vector3.UP)
	var from := player.global_position + Vector3.UP * 0.9
	var vn := v.normalized()
	var best := INF
	for sgn: float in [-1.0, 1.0]:
		_q.from = from
		_q.to = from + side * sgn * REACH
		var hit := space.intersect_ray(_q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if absf(n.y) > 0.5 or absf(vn.dot(n)) > ALONG:
			continue
		best = minf(best, from.distance_to(hit["position"]))
	return best
