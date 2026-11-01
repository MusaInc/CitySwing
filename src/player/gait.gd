class_name Gait
extends RefCounted
## World-space foot placement for ground locomotion (visual only).
##
## A gait clock advances at a cadence picked from the player's real
## horizontal speed. Each foot runs stance → swing on that clock (left at
## phase 0, right at 0.5):
##  * stance: the ankle is LOCKED in the world where it touched down (the hip
##    travels over it, the leg is solved with IK), the heel rolls up over the
##    ball of the foot at the end (toe-off);
##  * swing: the ankle flies from where it lifted to a landing spot predicted
##    from the velocity – ahead of where the hip will be at touchdown by half
##    the ground the stance will cover – arriving with zero world velocity, so
##    it lands where it is and stays there.
## Stance length (duty factor) is capped by how far the legs can reach, so a
## locked foot never has to skate. Turns, diagonals, back-pedalling and slopes
## all fall out of the prediction (it follows the velocity and raycasts the
## landing spot). Standing, both feet stay planted and a foot left out of
## place takes a small settle step. The rig reads the feet (ankle position,
## heading, toe/heel roll, ground normal) and the phase signals used to drive
## pelvis, spine and arms.

const ANKLE_H := 0.05
const LEG_LEN := 0.89
const BALL := 0.13
const SETTLE_DIST := 0.15
const SETTLE_TIME := 0.3
const START_SPEED := 0.35   # m/s: below this (both feet down) the body stands
const STAND_W := 0.1       # standing feet: half the stance width (m)


class Foot:
	extends RefCounted
	var side := "l"
	var sgn := -1.0           # -1 left, +1 right
	var planted := true
	var pos := Vector3.ZERO   # ankle (planted: lock point, before toe roll)
	var normal := Vector3.UP
	var heading := Vector3.FORWARD
	var from := Vector3.ZERO  # swing: where the ankle lifted
	var from_heading := Vector3.FORWARD
	var target := Vector3.ZERO
	var target_n := Vector3.UP
	var w := 0.0              # swing progress 0..1
	var stance_u := 0.0       # stance progress 0..1
	var toe := 0.0            # heel-up roll about the ball (rad)
	var heel := 0.0           # heel-strike toes-up (rad)
	var pitch := 0.0          # swing foot pitch relative to level (+ = toes up)
	var settle := false       # standing settle step
	var quick := false        # settle = just putting a foot in the air down where it is
	var cur := Vector3.ZERO   # ankle position this frame (what the rig solves to)
	var lift_toe := 0.0       # heel roll when the foot left the ground
	var world_k := 1.0        # swing: 1 = foot pitch is world-referenced (lift/landing), 0 = relaxed on the shin
	var ease := Vector3.ZERO  # start-up offset eased away (gait begun from a pose off the ground)
	var out := Vector3.ZERO   # cur + ease: the ankle target the rig solves to
	var last_u := 0.0         # clock phase last frame (detects the wrap = touchdown due)
	var due := false          # swing: touchdown time has come
	var rush := INF           # swing: forced touchdown countdown (s) after a dead stop

	func _init(s: String) -> void:
		side = s
		sgn = -1.0 if s == "l" else 1.0


var feet := {"l": Foot.new("l"), "r": Foot.new("r")}
## Touchdowns so far (footstep sounds poll this) and where the last one was.
var touchdowns := 0
var last_touchdown := Vector3.ZERO
var phase := 0.0          # 0..1 gait clock (left touchdown at 0)
var freq := 0.0           # cycles per second
var duty := 0.6           # stance fraction of the cycle
var run := 0.0            # 0 walk … 1 run (gait style)
const FOLD_MIN := 0.36    # m: closest an ankle comes to its hip (calf against hamstring)
var sprint := 0.0         # 0..1 above a jog
var moving := false       # stepping (false = standing)
var active := false
var speed := 0.0
var dir := Vector3.FORWARD  # travel direction (horizontal)
var _settle_side := ""
var _stand_t := 0.0
var _prev_speed := 0.0
var _jolt := 0.0          # s: just stopped dead (wall, collision): feet come straight down


## Steps per second for a horizontal speed (walk ~2/s at 1.4 m/s, jog ~2.8,
## sprint up to ~4.6 – the hero sprints at ~14.5 m/s).
static func cadence(s: float) -> float:
	return clampf(1.55 + 0.36 * s - 0.006 * s * s, 1.5, 5.2)


## Forget everything: the next update starts from the current ankle positions.
func reset() -> void:
	active = false
	moving = false
	_settle_side = ""


## Starts the gait from where the feet are now (landing, end of a get-up,
## respawn). `ankles` side -> world ankle, `ground` callable(at) -> hit dict.
func begin(ankles: Dictionary, facing: Vector3, ground: Callable, vel: Vector3) -> void:
	active = true
	var vh := Vector3(vel.x, 0.0, vel.z)
	dir = vh.normalized() if vh.length() > 0.3 else facing
	# The lower (or further-forward) foot takes the weight first.
	var la: Vector3 = ankles["l"]
	var ra: Vector3 = ankles["r"]
	var lead := "l" if (la.y - ra.y) < -0.03 or ((la - ra).dot(dir) > 0.0 and absf(la.y - ra.y) < 0.03) else "r"
	phase = 0.0 if lead == "l" else 0.5
	speed = vh.length()
	_style(speed)
	moving = speed > START_SPEED
	for sd in ["l", "r"]:
		var f: Foot = feet[sd]
		var a: Vector3 = ankles[sd]
		f.heading = facing
		f.toe = 0.0
		f.heel = 0.0
		f.pitch = 0.0
		f.settle = false
		var u := _u(f)
		f.ease = Vector3.ZERO
		var gh: Dictionary = ground.call(a)
		var high := not gh.is_empty() and a.y - (gh.position as Vector3).y - ANKLE_H > 0.05
		if moving and high:
			# Landing on the run with this foot still in the air: it comes
			# down in a quick step instead of being dragged onto the ground.
			f.planted = false
			f.from = a
			f.from_heading = facing
			f.cur = a
			f.w = 0.0
			f.last_u = u
			f.due = false
			f.rush = 0.07 if sd == lead else 0.16
			f.target = Vector3.ZERO
		elif sd == lead or not moving or u < duty:
			_plant_at(f, a, ground)
			f.ease = (a - f.cur).limit_length(0.5)
			f.stance_u = 0.0 if sd == lead else clampf(u / duty, 0.0, 1.0)
		else:
			f.planted = false
			f.from = a
			f.from_heading = facing
			f.cur = a
			f.w = 0.0
			f.last_u = u
			f.due = false
			f.target = Vector3.ZERO
	_settle_side = ""


func _u(f: Foot) -> float:
	return fposmod(phase + (0.0 if f.side == "l" else 0.5), 1.0)


func _style(s: float) -> void:
	run = smoothstep(1.9, 3.6, s)
	sprint = smoothstep(5.0, 12.0, s)


func _plant_at(f: Foot, a: Vector3, ground: Callable) -> void:
	var hit := _sole_hit(ground, a, f.heading)
	f.planted = true
	f.pos = Vector3(a.x, (hit.position as Vector3).y + ANKLE_H, a.z) if not hit.is_empty() else a
	f.normal = hit.normal if not hit.is_empty() else Vector3.UP
	f.cur = f.pos
	f.w = 0.0
	f.due = false
	f.rush = INF


## Advance one frame. `hips`: side -> world hip joint; `centre`: the body's
## ground-level centre (capsule xz); returns nothing – read `feet`.
func update(dt: float, vel: Vector3, facing: Vector3, centre: Vector3, hips: Dictionary, ground: Callable,
		crouch: float) -> void:
	_update(dt, vel, facing, centre, hips, ground, crouch)
	for f: Foot in feet.values():
		f.ease *= exp(-16.0 * dt)
		f.out = f.cur + f.ease


func _update(dt: float, vel: Vector3, facing: Vector3, centre: Vector3, hips: Dictionary, ground: Callable,
		crouch: float) -> void:
	var vh := Vector3(vel.x, 0.0, vel.z)
	speed = vh.length()
	# A collision kills the speed far faster than any braking (>40 m/s²).
	if _prev_speed - speed > 40.0 * dt:
		_jolt = 0.3
	_jolt = maxf(_jolt - dt, 0.0)
	_prev_speed = speed
	if speed > 0.3:
		var nd := dir.lerp(vh / speed, 1.0 - exp(-14.0 * dt))
		dir = nd.normalized() if nd.length() > 0.2 else vh / speed
	_style(speed)
	var right := Vector3.UP.cross(facing).normalized() * -1.0
	# Reach: how far ahead / behind the hip a stance ankle can be, at the
	# stance hip height (knees flexed a little more at speed).
	# (Hip height at the contacts: walking, the pelvis is lowest there.)
	var hh := LEG_LEN - 0.03 - crouch - lerpf(0.04, 0.015, run)
	var reach_f := sqrt(maxf(LEG_LEN * LEG_LEN - hh * hh, 0.0)) * 0.9
	var toe_max := lerpf(0.55, 0.85, run)
	var hb := hh - BALL * sin(toe_max)
	var reach_b := (sqrt(maxf(LEG_LEN * LEG_LEN - hb * hb, 0.0)) + BALL * (1.0 - cos(toe_max))) * 0.9
	var swinging: bool = not (feet["l"] as Foot).planted or not (feet["r"] as Foot).planted

	# --- start / stop ----------------------------------------------------
	if not moving:
		if speed > START_SPEED:
			_start(centre, ground)
		else:
			_stand(dt, facing, right, centre, ground, hips)
			return
	elif speed < START_SPEED * 0.6:
		# Stopped (or stopped dead – a wall): a foot still in the air is put
		# straight down, then the stance tidies up with settle steps.
		moving = false
		_stand_t = 0.0
		_stand(dt, facing, right, centre, ground, hips)
		return

	# --- clock -----------------------------------------------------------
	var steps := cadence(maxf(speed, 0.8))
	freq = steps * 0.5
	var want_duty := lerpf(0.62, 0.38, run) - 0.1 * sprint
	# Ground covered while a foot is down must fit the legs' reach.
	var cover_max := reach_f + reach_b
	duty = minf(want_duty, cover_max * freq / maxf(speed, 0.01))
	duty = maxf(duty, 0.12)
	phase = fposmod(phase + freq * dt, 1.0)
	var cover := speed * duty / freq  # m travelled during one stance
	# Walking lands well ahead (heel strike); running lands closer under the
	# hips and pushes off further behind – no reaching, braking overstride.
	var ahead := cover * lerpf(reach_f / cover_max, 0.36, run)
	var width := lerpf(0.095, 0.035, run)

	for sd in ["l", "r"]:
		var f: Foot = feet[sd]
		var u := _u(f)
		var hip: Vector3 = hips[sd]
		if f.planted:
			f.stance_u = clampf(u / duty, 0.0, 1.0) if u < duty else 1.0
			# Heel strike: walking lands heel first and rolls flat; runners
			# land on the midfoot.
			f.heel = (1.0 - smoothstep(0.0, 0.3, f.stance_u)) * lerpf(0.28, 0.06, run)
			f.toe = smoothstep(0.55, 1.0, f.stance_u) * toe_max * smoothstep(0.4, 1.6, speed)  # (none when coming to a stop)
			# The heel also comes up early if the flat foot is out of reach.
			var a := _roll(f.pos, f.heading, f.normal, f.toe)
			while f.toe < toe_max + 0.2 and a.distance_to(hip) > LEG_LEN - 0.01:
				f.toe += 0.04
				a = _roll(f.pos, f.heading, f.normal, f.toe)
			f.cur = a
			_pivot(f, facing)
			# Lift: the clock says so, or the body has run away from the foot
			# (a sharp cut, a stop dead): then it's a step, never a skate or a
			# leg hyper-extended behind the hip.
			var rel := a - hip
			var back := -Vector2(rel.x, rel.z).dot(Vector2(facing.x, facing.z))
			var lost := a.distance_to(hip) > LEG_LEN + 0.01 or atan2(back, maxf(-rel.y, 0.05)) > 0.6 \
				or Vector2(rel.x, rel.z).length() > LEG_LEN * 0.9
			if u >= duty or lost:
				f.planted = false
				f.from = a
				f.from_heading = f.heading
				f.lift_toe = f.toe
				f.pitch = -f.toe
				f.w = 0.0
				f.heel = 0.0
				f.target = Vector3.ZERO
				f.due = false
				f.rush = INF
				f.last_u = u
		if not f.planted:
			# Time left until this foot's touchdown (its phase wraps to 0). A
			# foot that's late (forced lift, slowing clock) finishes quickly
			# but still smoothly.
			if u < f.last_u - 0.5:
				f.due = true
			f.last_u = u
			var left := 0.06 if f.due else (1.0 - u) / freq
			if speed < 1.5 or _jolt > 0.0:
				f.rush = minf(f.rush, 0.07 + 0.06 * minf(speed, 1.5))  # stopped dead mid-stride: come down now
			if f.rush < INF:
				f.rush -= dt
				left = minf(left, f.rush)
			left = maxf(left, dt)
			f.w = clampf(f.w + (1.0 - f.w) * minf(dt / left, 1.0), 0.0, 1.0)
			# Landing spot: where the hip will be at touchdown, plus half the
			# stance ahead of it, out to this foot's side of the line.
			var side := right * f.sgn * width
			var land := centre + vh * left + dir * ahead * clampf(speed / 1.0, 0.0, 1.0) + side
			land.y = f.from.y
			# Straddling a kerb / step edge: move on until the whole sole is on
			# one level (on the step going up, clear of the edge going down).
			var hit := {}
			for i in 4:
				hit = _sole_hit(ground, land + Vector3.UP * 0.3, dir)
				var mid: Dictionary = ground.call(land + Vector3.UP * 0.3)
				if hit.is_empty() or mid.is_empty() or (hit.position as Vector3).y - (mid.position as Vector3).y < 0.03:
					break
				land += dir * 0.07
			if not hit.is_empty():
				land.y = (hit.position as Vector3).y + ANKLE_H
				f.target_n = hit.normal
			if f.w < 0.85 or f.target == Vector3.ZERO:
				f.target = land  # (frozen for the last part: the foot comes down where it's going)
			# Horizontal: an ease from lift to landing with zero world speed at
			# both ends. Relative to the moving hip that is the runner's path:
			# the foot falls back behind as it lifts, passes under the hip
			# mid-swing and reaches ahead late; running it reaches a little
			# past the landing spot and paws back onto it.
			var e := f.w * f.w * (3.0 - 2.0 * f.w)
			# (Sprinting the swing foot covers ~5 m of ground in a third of a
			# second: a rest-to-rest ease left it half a metre behind the hips
			# early and flung it half a metre ahead late – a straight-legged
			# kick out front, with the hips sinking to reach it. Near-steady
			# instead: the leg swings through under the body.)
			e = lerpf(e, f.w, 0.85 * sprint)
			var paw := 0.08 * run * smoothstep(0.55, 0.82, f.w) * (1.0 - smoothstep(0.82, 1.0, f.w))
			var p := f.from.lerp(f.target, e) + dir * paw
			# Height: an early heel kick at a run (the foot folds up behind),
			# a low clearance arc walking; step up early, step down late.
			var up := f.target.y - f.from.y
			var ey := smoothstep(0.0, 0.55, f.w) if up > 0.0 else smoothstep(0.45, 1.0, f.w)
			p.y = f.from.y + up * ey
			# (A sprint's heel comes up behind, but not tucked against the seat
			# for half the stride: that read as running sitting down.)
			var lift_h := lerpf(0.1, 0.3 + 0.04 * sprint, run) * clampf(speed / 1.2, 0.35, 1.0)
			# (Peak skewed early running – the heel kicks up behind – with zero
			# vertical speed at lift and touchdown: no pops.)
			var wk := f.w + 0.15 * f.w * (1.0 - f.w)
			var h_walk := pow(sin(PI * wk), 2.0)
			# Running: up fast behind, still well up as the knee comes through
			# (shin hanging under it), down only at the end.
			# (Heel kicks up fast behind, highest as it passes under the hip,
			# comes down as the knee opens and the foot reaches ahead.)
			var h_run := smoothstep(0.0, 0.32, f.w) * (1.0 - smoothstep(0.48, 1.0, f.w))
			p.y += lift_h * lerpf(h_walk, h_run, run)
			# Never further than the leg reaches from where the hip is now: a
			# foot that gets ahead of its hip waits at full reach and comes
			# down a little short instead of the leg stretching.
			var rel := p - hip
			if rel.length() > LEG_LEN - 0.012:
				p = hip + rel.normalized() * (LEG_LEN - 0.012)
			# ...and never closer than a fully folded leg allows: at a sprint the
			# heel kick carried the ankle right up through the hip joint, where
			# the leg's direction is undefined and the thigh spun ~100° in a
			# frame. Below the hip by at least FOLD_MIN (continuous: no pop).
			var rh := Vector2(rel.x, rel.z).length()
			if rh < FOLD_MIN:
				p.y = minf(p.y, hip.y - sqrt(FOLD_MIN * FOLD_MIN - rh * rh))
			var g := _sole_hit(ground, p, f.heading)
			if not g.is_empty():
				p.y = maxf(p.y, (g.position as Vector3).y + ANKLE_H + 0.01 * sin(PI * f.w))
			f.cur = p
			# Foot pitch: toes stay pointed after the push-off, then come up
			# to meet the ground (heel first walking, flat-ish running).
			var land_pitch := lerpf(0.3, 0.08, run)
			# Mid-swing the foot hangs relaxed off the shin (the rig blends to a
			# shin-relative pose by world_k).
			f.pitch = lerpf(-f.lift_toe, land_pitch, smoothstep(0.35, 1.0, f.w))
			f.world_k = clampf(1.0 - smoothstep(0.0, 0.16, f.w) + smoothstep(0.62, 0.95, f.w), 0.0, 1.0)
			if f.rush < INF:
				f.world_k = 1.0  # a quick step down: the sole is already lined up to land
			# Toes along the travel (a touch out), unless the body is backing
			# or side-stepping: then along where it faces.
			var travel := facing
			if speed > 0.5 and dir.dot(facing) > 0.5:
				travel = (dir + right * f.sgn * 0.08).normalized()
			f.heading = _yaw_to(f.from_heading, travel, e)
			f.toe = 0.0
			if (f.due or f.rush < INF) and f.w > 0.98:
				# Touchdown. (Brought down early: the clock follows this foot.)
				if not f.due:
					phase = 0.0 if f.side == "l" else 0.5
				# (On the spot the landing search chose – never re-probed onto a
				# step edge the heel overhangs.)
				f.planted = true
				f.pos = f.cur
				f.normal = f.target_n
				touchdowns += 1
				last_touchdown = f.cur
				if f.target != Vector3.ZERO and Vector2(f.cur.x - f.target.x, f.cur.z - f.target.z).length() < 0.06:
					f.pos.y = f.target.y
				else:
					var h := _sole_hit(ground, f.cur + Vector3.UP * 0.3, f.heading)
					if not h.is_empty():
						f.pos.y = (h.position as Vector3).y + ANKLE_H
						f.normal = h.normal
				f.cur = f.pos
				f.w = 0.0
				f.due = false
				f.rush = INF
				f.world_k = 1.0
				f.heading = (f.heading - f.normal * f.heading.dot(f.normal)).normalized()
				f.stance_u = 0.0
				f.heel = lerpf(0.28, 0.06, run)


## Leaving a standstill: the foot that's further back along the travel lifts
## first; the clock is set so it's just at toe-off.
func _start(centre: Vector3, _ground: Callable) -> void:
	moving = true
	var l: Foot = feet["l"]
	var r: Foot = feet["r"]
	var first := "l" if (l.pos - r.pos).dot(dir) < 0.0 else "r"
	_style(speed)
	var d := maxf(lerpf(0.62, 0.38, run), 0.55)
	duty = d
	phase = fposmod(d - 0.001 - (0.0 if first == "l" else 0.5), 1.0)
	for f: Foot in [l, r]:
		f.settle = false
		if not f.planted:
			_land_now(f)
	_settle_side = ""


func _land_now(f: Foot) -> void:
	f.planted = true
	f.pos = f.cur
	f.w = 0.0


## Standing: feet stay put; one at a time, a foot well out of its rest spot
## (after a stop, a landing, a turn on the spot) steps back under the hips.
func _stand(dt: float, facing: Vector3, right: Vector3, centre: Vector3, ground: Callable, hips: Dictionary) -> void:
	_stand_t += dt
	for sd in ["l", "r"]:
		var f: Foot = feet[sd]
		if not f.planted and not f.settle:
			# Still in the air from the last stride: just put it down.
			f.settle = true
			f.quick = true
			f.from = f.cur
			f.from_heading = f.heading
			f.w = 0.0
			_settle_side = sd
	# A planted foot the leg can't reach any more (knocked back off a wall)
	# steps in at once.
	for sd in ["l", "r"]:
		var f: Foot = feet[sd]
		if f.planted and f.cur.distance_to(hips[sd]) > LEG_LEN + 0.01:
			f.settle = true
			f.quick = true
			f.planted = false
			f.from = f.cur
			f.from_heading = f.heading
			f.w = 0.0
			_settle_side = sd
	if _settle_side == "" and _stand_t > 0.12:
		var worst := ""
		var far := SETTLE_DIST
		for sd in ["l", "r"]:
			var f: Foot = feet[sd]
			var rest := centre + right * f.sgn * STAND_W
			var off := Vector2(f.pos.x - rest.x, f.pos.z - rest.z).length()
			var twist := absf(f.heading.signed_angle_to(facing, Vector3.UP))
			if off > far or twist > 0.9:
				far = maxf(off, far)
				worst = sd
		if worst != "":
			var f: Foot = feet[worst]
			f.settle = true
			f.quick = false
			f.planted = false
			f.from = f.cur
			f.from_heading = f.heading
			f.w = 0.0
			_settle_side = worst
	for sd in ["l", "r"]:
		var f: Foot = feet[sd]
		if f.planted:
			f.toe = move_toward(f.toe, 0.0, dt * 3.0)
			f.heel = move_toward(f.heel, 0.0, dt * 3.0)
			f.cur = _roll(f.pos, f.heading, f.normal, f.toe)
			f.stance_u = 0.5
			continue
		f.w = minf(f.w + dt / (0.1 if f.quick else SETTLE_TIME), 1.0)
		var rest := centre + right * f.sgn * STAND_W
		rest.y = f.from.y
		var hit: Dictionary = ground.call(rest + Vector3.UP * 0.3)
		if not hit.is_empty():
			rest.y = (hit.position as Vector3).y + ANKLE_H
		var e := smoothstep(0.0, 1.0, f.w)
		var p := f.from.lerp(rest, e)
		p.y = lerpf(f.from.y, rest.y, e) + sin(PI * f.w) * (0.03 if f.quick else 0.07)
		f.cur = p
		f.heading = _yaw_to(f.from_heading, facing, e)
		f.pitch = 0.15 * sin(PI * f.w)
		f.world_k = 1.0
		f.toe = 0.0
		if f.w >= 1.0:
			_plant_at(f, p, ground)
			f.settle = false
			_settle_side = ""
			_stand_t = 0.0


## A locked foot keeps its heading while the body turns over it, pivoting on
## the ball only past ~35° of twist.
func _pivot(f: Foot, facing: Vector3) -> void:
	var face := (facing - f.normal * facing.dot(f.normal)).normalized()
	var ang := f.heading.signed_angle_to(face, f.normal)
	if absf(ang) > 0.6:
		f.heading = f.heading.rotated(f.normal, ang - signf(ang) * 0.6)


## How far forward (+1) / back (-1) the left leg is in the cycle; the right
## leg is the opposite. Peaks at the left foot's touchdown.
func left_forward() -> float:
	if not moving:
		return 0.0
	# Touchdown at phase 0, toe-off at `duty`, back at its furthest there.
	var u := fposmod(phase, 1.0)
	if u < duty:
		return cos(PI * u / duty)          # 1 at touchdown → -1 at toe-off
	return -cos(PI * (u - duty) / (1.0 - duty))  # swinging through


## Step phase 0..1 (0 = a touchdown, either foot).
func step_phase() -> float:
	return fposmod(phase * 2.0, 1.0)


static func _roll(ankle: Vector3, f: Vector3, n: Vector3, toe: float) -> Vector3:
	if toe <= 0.0:
		return ankle
	return ankle + n * sin(toe) * BALL + f * (1.0 - cos(toe)) * BALL


## Turns horizontal direction `a` toward `b` by fraction `t` (safe for
## opposite directions, unlike slerp).
static func _yaw_to(a: Vector3, b: Vector3, t: float) -> Vector3:
	var ah := Vector3(a.x, 0.0, a.z).normalized()
	var bh := Vector3(b.x, 0.0, b.z).normalized()
	if ah.length_squared() < 0.5:
		return bh
	if bh.length_squared() < 0.5:
		return ah
	return ah.rotated(Vector3.UP, ah.signed_angle_to(bh, Vector3.UP) * t)


## Highest ground under the whole sole (heel, ankle, ball): a foot over a
## kerb or step edge rests on the higher side instead of sinking into it.
static func _sole_hit(ground: Callable, at: Vector3, heading: Vector3) -> Dictionary:
	var hd := Vector3(heading.x, 0.0, heading.z).normalized()
	var best: Dictionary = ground.call(at)
	for off: float in [0.13, -0.07]:
		var h: Dictionary = ground.call(at + hd * off)
		if not h.is_empty() and (best.is_empty() or (h.position as Vector3).y > (best.position as Vector3).y + 0.005):
			best = h
	return best
