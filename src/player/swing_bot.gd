class_name SwingBot
extends RefCounted
## Autopilot that plays through the same input interface as a human
## (move / aim / grapple held / reel / jump). Used by the automated skill tests,
## and for attract-mode / screenshot capture. Two styles:
##   EXPERT – fires near the apex, releases on the upswing at ~30° above
##            horizontal, lets go when the line catches a corner, and sees
##            walls coming: a knockout-speed hit less than ~0.9 s ahead
##            means let go / re-web on a line that clears it, steering
##            along the facade.
##   NOVICE – fires late while dropping, lets go around the bottom of the arc.

enum Style { EXPERT, NOVICE }

var style := Style.EXPERT
var heading := Vector3.FORWARD
## Optional callable(player) -> Vector3 giving a moving goal (checkpoints).
var goal_fn: Callable
var _hold := false
var _cooldown := 0.0
var _ground_time := 0.0
var _stuck := 0.0  # s grounded, slow and with nothing to web
var _hopped := false
var _stuck_at := Vector3.ZERO
var _idle_held := false  # the button was down last frame with no line out
var _stall := 0.0
var _trust := 0.0  # s left trusting a web fired to avoid a wall
var _rng := RandomNumberGenerator.new()


func _init(s := Style.EXPERT, h := Vector3.FORWARD, seed := 7) -> void:
	style = s
	heading = h.normalized()
	_rng.seed = seed


func drive(p: Player, dt: float) -> Dictionary:
	var pos := p.global_position
	var v := p.s.velocity
	var dir := heading
	var goal := Vector3.ZERO
	if goal_fn.is_valid():
		goal = goal_fn.call(p)
		dir = Vector3(goal.x - pos.x, 0.0, goal.z - pos.z).normalized()
	var aim := (dir + Vector3.UP * 0.2).normalized()
	var out := {"move": Vector3.ZERO, "aim": aim, "grapple": _hold,
		"reel": 0.0, "jump": false}
	_cooldown -= dt
	_trust -= dt
	var vh := Vector3(v.x, 0.0, v.z)

	if p.is_on_floor() and not p.s.attached:
		_ground_time += dt
		out["move"] = dir
		# Run, then jump and grab once moving.
		if _ground_time > 0.35 and vh.length() > 5.0:
			out["jump"] = true
		if _ground_time > 0.5 and p.targeting.has_target:
			_hold = true
		# Boxed in (a ledge against a tower, a dead-end corner) with nothing
		# to web: hop, then turn back and drop off the edge.
		# Measured by real displacement (pinned against a wall the velocity
		# still reads high); _stuck survives the hops that reset _ground_time.
		var moved := Vector2(pos.x - _stuck_at.x, pos.z - _stuck_at.z).length()
		if moved > 2.0:
			_stuck = 0.0
			_hopped = false
			_stuck_at = pos
		else:
			_stuck += dt
		if _stuck > 1.5 and not _hopped:
			out["jump"] = true
			_hopped = true
		elif _hopped:
			out["move"] = -dir
		out["grapple"] = _repress(_hold) if p.line_state == Player.Line.IDLE else _hold
		return out
	_ground_time = 0.0

	var hit := _wall_ahead(p) if style == Style.EXPERT else []
	var wall: Vector3 = hit[0] if hit else Vector3.ZERO
	if wall != Vector3.ZERO:
		# Steer along the facade, not into it.
		var along := dir - wall * dir.dot(wall)
		along.y = 0.0
		if along.length_squared() > 0.01:
			dir = along.normalized()
		out["move"] = dir
		if p.line_state == Player.Line.ATTACHED and _trust <= 0.0:
			_hold = false  # this web is what's carrying us in
			_cooldown = 0.0
			out["grapple"] = false
			return out
		if p.line_state == Player.Line.IDLE and p.targeting.pick_ok:
			_hold = true  # the pick's swing is predicted to clear: trust it
			_trust = 0.7
			out["grapple"] = true
			return out
		if hit[1] < p.params.wall_save_window * 0.8:
			out["jump"] = true  # no way round it: kick off it
			return out

	if p.line_state == Player.Line.IDLE:
		_hold = false
		var fire := false
		var t := p.targeting
		if t.has_target and _cooldown <= 0.0:
			var to := t.point - pos
			var ahead := Vector3(to.x, 0.0, to.z).normalized().dot(dir)
			if style == Style.EXPERT:
				fire = ahead > 0.25 and (v.y < 3.0 or pos.y < 25.0)
			else:
				# Beginners fire once they notice they're dropping.
				fire = ahead > 0.25 and (v.y < -4.0 or pos.y < 15.0)
		_hold = _repress(fire)
	elif p.line_state == Player.Line.ATTACHED:
		var rope := pos - p.s.anchor
		var past := Vector3(-rope.x, 0.0, -rope.z).dot(vh.normalized()) < 0.0  # moving away from beneath anchor
		var rise_angle := atan2(v.y, maxf(vh.length(), 0.01))
		var below_anchor := rope.normalized().angle_to(Vector3.DOWN)
		_stall = _stall + dt if v.length() < 3.0 else 0.0
		if style == Style.EXPERT:
			out["move"] = dir
			if _stall > 0.6:
				# Pinned against a wall: kick off it and let go to find a better
				# anchor (the web tightens by itself; there is no climbing).
				out["jump"] = true
				_hold = false
				_cooldown = 0.2
				_stall = 0.0
				out["grapple"] = _hold
				return out
			# The line has caught a corner: the swing is about to bend round
			# the building. Let go while still heading the right way.
			if not p.wraps.is_empty() and vh.normalized().dot(dir) > 0.3 and v.y > -6.0:
				_hold = false
				_cooldown = 0.2
			if past and rise_angle > deg_to_rad(28.0):
				_hold = false
				_cooldown = 0.25
			if pos.y > p.s.anchor.y - 3.0:
				_hold = false
				_cooldown = 0.25
		else:
			# Holds forward the whole time and lets go around the bottom of the
			# arc – the classic beginner mistake that throws momentum away.
			out["move"] = dir
			if (past and below_anchor > deg_to_rad(12.0)) or _stall > 0.6:
				_hold = false
				_cooldown = 0.6
	else:
		out["move"] = dir * 0.5
	if p.line_state == Player.Line.IDLE and not _hold:
		out["move"] = dir * (1.0 if style == Style.EXPERT else 0.2)
	out["grapple"] = _hold
	return out


## [wall normal, seconds to impact] if a knockout-speed head-on hit is under
## ~0.9 s ahead, following the real path (the swing's curve on the web);
## [] otherwise.
## The game fires on a press, not a hold: if the button is still down from a
## press that didn't leave a line out, let go for a frame so the next one fires.
func _repress(want: bool) -> bool:
	var press := want and not _idle_held
	_idle_held = press
	return press


func _wall_ahead(p: Player) -> Array:
	if p.s.velocity.length() < p.params.wall_run_max_speed * 0.9:
		return []
	var s := SwingPhysics.State.new()
	s.position = p.global_position
	s.velocity = p.s.velocity
	s.attached = p.s.attached
	s.anchor = p.s.anchor
	s.rope_length = p.s.rope_length
	s.taut = p.s.taut
	var c := SwingPhysics.Controls.new()
	var rq := PhysicsRayQueryParameters3D.new()
	rq.collision_mask = Player.BUILDINGS_MASK
	rq.exclude = [p.get_rid()]
	var space := p.get_world_3d().direct_space_state
	for i in 18:
		var a := s.position
		var v := s.velocity
		SwingPhysics.step(s, c, p.params, 0.05)
		rq.from = a
		rq.to = s.position + (s.position - a).normalized() * 0.4
		var hit := space.intersect_ray(rq)
		if hit.is_empty():
			continue
		var n: Vector3 = hit.normal
		if absf(n.y) > 0.6:
			return []  # a roof or ledge top, not a facade
		var into := -v.dot(n)
		if into < p.params.wall_run_max_speed * 0.9 or into / maxf(v.length(), 0.1) < p.params.wall_glance_ratio * 0.9:
			return []
		var frac := (hit.position as Vector3).distance_to(a) / maxf(a.distance_to(s.position), 0.01)
		return [Vector3(n.x, 0.0, n.z).normalized(), (i + clampf(frac, 0.0, 1.0)) * 0.05]
	return []
