class_name SwingBot
extends RefCounted
## Autopilot that plays through the same input interface as a human
## (move / aim / grapple held / reel / jump). Used by the automated skill tests,
## and for attract-mode / screenshot capture. Two styles:
##   EXPERT – fires near the apex, pumps by reeling through the bottom,
##            releases on the upswing at ~30° above horizontal.
##   NOVICE – fires late while dropping, never pumps, lets go at the bottom.

enum Style { EXPERT, NOVICE }

var style := Style.EXPERT
var heading := Vector3.FORWARD
## Optional callable(player) -> Vector3 giving a moving goal (checkpoints).
var goal_fn: Callable
var _hold := false
var _cooldown := 0.0
var _ground_time := 0.0
var _stall := 0.0
var _rng := RandomNumberGenerator.new()


func _init(s := Style.EXPERT, h := Vector3.FORWARD, seed := 7) -> void:
	style = s
	heading = h.normalized()
	_rng.seed = seed


func drive(p: Player, dt: float) -> Dictionary:
	var pos := p.global_position
	var v := p.s.velocity
	var dir := heading
	if goal_fn.is_valid():
		var g: Vector3 = goal_fn.call(p)
		dir = Vector3(g.x - pos.x, 0.0, g.z - pos.z).normalized()
	var out := {"move": Vector3.ZERO, "aim": (dir + Vector3.UP * 0.2).normalized(), "grapple": _hold,
		"reel": 0.0, "jump": false}
	_cooldown -= dt
	var vh := Vector3(v.x, 0.0, v.z)

	if p.is_on_floor() and not p.s.attached:
		_ground_time += dt
		out["move"] = dir
		# Run, then jump and grab once moving.
		if _ground_time > 0.35 and vh.length() > 5.0:
			out["jump"] = true
		if _ground_time > 0.5 and p.targeting.has_target:
			_hold = true
		out["grapple"] = _hold
		return out
	_ground_time = 0.0

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
		_hold = fire
	elif p.line_state == Player.Line.ATTACHED:
		var rope := pos - p.s.anchor
		var past := Vector3(-rope.x, 0.0, -rope.z).dot(vh.normalized()) < 0.0  # moving away from beneath anchor
		var rise_angle := atan2(v.y, maxf(vh.length(), 0.01))
		var below_anchor := rope.normalized().angle_to(Vector3.DOWN)
		_stall = _stall + dt if v.length() < 3.0 else 0.0
		if style == Style.EXPERT:
			out["move"] = dir
			if _stall > 0.6:
				# Pinned against a wall: let go and find a better anchor.
				_hold = false
				_cooldown = 0.15
				_stall = 0.0
			# Pump: shorten through the bottom of the arc, and always keep the
			# bottom of the arc well clear of the street.
			out["reel"] = 1.0 if below_anchor < deg_to_rad(25.0) and p.s.rope_length > 18.0 else 0.0
			if p.s.anchor.y - p.s.rope_length < 9.0:
				out["reel"] = 1.0
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
		out["move"] = dir * (0.6 if style == Style.EXPERT else 0.2)
	out["grapple"] = _hold
	return out
