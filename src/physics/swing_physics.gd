class_name SwingPhysics
extends RefCounted
## Pure, deterministic traversal model: gravity, drag, limited steering,
## ground running and an inextensible rope that can go slack.
## No scene access – the Player node feeds it state and resolves collisions,
## and tests drive it directly.


class State:
	extends RefCounted
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var grounded := false
	var attached := false
	var anchor := Vector3.ZERO
	var rope_length := 0.0
	## True while the rope is at full length and carrying load.
	var taut := false
	## Rope load per unit mass (m/s²): centripetal + gravity component. Drives audio/visuals.
	var tension := 0.0
	## Set for one step when a slack rope snaps tight; value is the radial speed lost.
	var snap_speed := 0.0


class Controls:
	extends RefCounted
	## Desired direction in world space, horizontal, length 0..1.
	var move := Vector3.ZERO
	## +1 reel in, -1 reel out.
	var reel := 0.0
	var jump := false
	## Game-layer gravity multiplier (apex hang time). Model tests leave it at 1.
	var gravity_scale := 1.0


static func attach(s: State, anchor: Vector3, p: SwingParams) -> bool:
	var dist := s.position.distance_to(anchor)
	if dist > p.grapple_range or dist < 0.5:
		return false
	s.attached = true
	s.anchor = anchor
	s.rope_length = clampf(dist * p.attach_length_factor, p.min_rope_length, p.max_rope_length)
	s.taut = false
	s.tension = 0.0
	return true


## Releasing never touches velocity: the player flies off with exactly the
## momentum the swing gave them.
static func release(s: State) -> void:
	s.attached = false
	s.taut = false
	s.tension = 0.0


static func step(s: State, c: Controls, p: SwingParams, dt: float) -> void:
	s.snap_speed = 0.0
	if c.jump and s.grounded:
		s.velocity.y = maxf(s.velocity.y, 0.0) + p.jump_speed
		s.grounded = false
	var n := maxi(1, p.substeps)
	var h := dt / n
	for i in n:
		_substep(s, c, p, h)


static func _substep(s: State, c: Controls, p: SwingParams, h: float) -> void:
	var v := s.velocity
	var on_ground := s.grounded and not s.attached
	if on_ground:
		v = _ground_move(v, c, p, h)
	else:
		v.y -= p.gravity * c.gravity_scale * h
		if s.attached and s.taut:
			v = _swing_steer(s, v, c, p, h)
		else:
			v = _air_steer(v, c, p, h)

	var spd := v.length()
	if spd > 0.0001:
		var dec := (p.air_drag * spd * spd + p.linear_drag * spd) * h
		v -= v / spd * minf(dec, spd)
	v.y = maxf(v.y, -p.max_fall_speed)

	if s.attached and c.reel != 0.0:
		v = _reel(s, v, c.reel, p, h)

	var moved_on_arc := false
	if s.attached and s.taut:
		var d := s.position - s.anchor
		var dist := d.length()
		if dist > 0.0001:
			var nrm := d / dist
			var vr := v.dot(nrm)
			if vr > 0.0:
				# Tension cancels any outward velocity (gravity's radial share).
				v -= nrm * vr
				vr = 0.0
			if vr > -0.001:
				# Taut: advance along the circle itself rather than a chord, so the
				# rope does no work and swings neither leak nor gain energy.
				var vt_len := v.length()
				if vt_len > 0.0001:
					var axis := d.cross(v).normalized()
					var ang := vt_len * h / dist
					d = d.rotated(axis, ang)
					v = v.rotated(axis, ang)
				s.position = s.anchor + d
				moved_on_arc = true
	if not moved_on_arc:
		s.position += v * h

	if s.attached:
		var d := s.position - s.anchor
		var dist := d.length()
		if dist >= s.rope_length - 0.0005 and dist > 0.0001:
			var nrm := d / dist
			s.position = s.anchor + nrm * minf(dist, s.rope_length)
			var vr := v.dot(nrm)
			if vr > 0.0:
				var lost := vr * (p.taut_inelasticity if not s.taut else 1.0)
				# Slack rope snapping tight is an inelastic jerk...
				v -= nrm * lost
				if not s.taut:
					s.snap_speed = maxf(s.snap_speed, vr)
					# ...but part of its energy carries on along the swing, so a
					# web caught mid-flight keeps your momentum (never a gain).
					var vt := v - nrm * v.dot(nrm)
					var vt_len := vt.length()
					if vt_len > 1.0:
						var keep := sqrt(vt_len * vt_len + p.snap_redirect * lost * lost)
						v += vt / vt_len * (keep - vt_len)
			s.taut = true
			var vt2 := (v - nrm * v.dot(nrm)).length_squared()
			s.tension = maxf(0.0, vt2 / s.rope_length - p.gravity * nrm.y)
		else:
			s.taut = false
			s.tension = 0.0
	s.velocity = v


static func _reel(s: State, v: Vector3, reel: float, p: SwingParams, h: float) -> Vector3:
	var old_len := s.rope_length
	var rate := p.reel_in_speed if reel > 0.0 else p.reel_out_speed
	var new_len := clampf(old_len - reel * rate * h, p.min_rope_length, p.max_rope_length)
	if new_len < old_len and s.taut:
		# Pulling yourself in along the rope conserves angular momentum about
		# the anchor (L·v_t = const) – reeling in at the bottom of an arc pumps
		# energy into the swing, exactly like a playground swing.
		var d := s.position - s.anchor
		var dist := d.length()
		if dist > 0.0001:
			var nrm := d / dist
			var vr := v.dot(nrm)
			var vt := v - nrm * vr
			var vt_len := vt.length()
			var target := minf(vt_len * old_len / new_len, maxf(vt_len, p.reel_speed_cap))
			if vt_len > 0.0001:
				vt = vt / vt_len * target
			v = vt + nrm * minf(vr, 0.0)
	s.rope_length = new_len
	return v


static func _swing_steer(s: State, v: Vector3, c: Controls, p: SwingParams, h: float) -> Vector3:
	if c.move.length_squared() < 0.0001:
		return v
	var nrm := (s.position - s.anchor).normalized()
	var m := c.move - nrm * c.move.dot(nrm)
	var ml := m.length()
	if ml < 0.0001:
		return v
	var dir := m / ml
	var accel := p.swing_steer_accel
	if v.length_squared() > 0.01:
		accel *= 1.0 + p.swing_pump_bonus * maxf(0.0, dir.dot(v.normalized()))
	return v + dir * accel * minf(c.move.length(), 1.0) * h


static func _air_steer(v: Vector3, c: Controls, p: SwingParams, h: float) -> Vector3:
	var m := Vector3(c.move.x, 0.0, c.move.z)
	var ml := m.length()
	if ml < 0.0001:
		return v
	var dir := m / ml
	var along := Vector3(v.x, 0.0, v.z).dot(dir)
	if along >= p.air_steer_speed_limit:
		return v
	var dv := minf(p.air_steer_accel * minf(ml, 1.0) * h, p.air_steer_speed_limit - along)
	return v + dir * dv


static func _ground_move(v: Vector3, c: Controls, p: SwingParams, h: float) -> Vector3:
	var vh := Vector3(v.x, 0.0, v.z)
	var m := Vector3(c.move.x, 0.0, c.move.z).limit_length(1.0)
	var speed := vh.length()
	if speed > p.run_speed and m.length_squared() > 0.01 and m.dot(vh) > 0.0:
		# Carrying swing momentum onto a rooftop: keep flowing, bleed slowly, steer.
		var new_speed := maxf(p.run_speed, speed - p.ground_overspeed_decel * h)
		var dir := vh.normalized().slerp(m.normalized(), clampf(4.0 * h, 0.0, 1.0))
		vh = dir * new_speed
	elif m.length_squared() > 0.01:
		vh = vh.move_toward(m * p.run_speed, p.run_accel * h)
	else:
		vh = vh.move_toward(Vector3.ZERO, (p.ground_friction + speed * 2.0) * h)
	return Vector3(vh.x, minf(v.y, 0.0), vh.z)


## Automatic web pull (fraction of reel_in_speed) – there are no reel buttons.
## The taut line tightens through the bottom of the arc, where tension peaks:
## shortening it there conserves angular momentum, so the pull does real work
## and the swing gains speed and lifts the body. It never pulls the line below
## auto_tighten_min_fraction of its attach length, and it winches harder when
## the lowest point of the arc would come too close to the street.
static func auto_tighten(s: State, p: SwingParams, attach_length: float) -> float:
	if not (s.attached and s.taut):
		return 0.0
	var shortfall := p.swing_ground_clearance - (s.anchor.y - s.rope_length)
	if shortfall > 0.0:
		return clampf(1.0 + shortfall / 6.0, 1.0, 2.5)
	if s.rope_length <= attach_length * p.auto_tighten_min_fraction:
		return 0.0
	var r := (s.position - s.anchor).normalized()
	var vt := (s.velocity - r * s.velocity.dot(r)).length()
	if vt < 4.0:
		return 0.0
	var below := r.angle_to(Vector3.DOWN)
	return pow(clampf(1.0 - below / deg_to_rad(55.0), 0.0, 1.0), 1.5)


## Mechanical energy per unit mass – used by tests and the debug overlay.
static func energy(s: State, p: SwingParams) -> float:
	return 0.5 * s.velocity.length_squared() + p.gravity * s.position.y
