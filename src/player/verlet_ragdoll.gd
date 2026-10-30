class_name VerletRagdoll
extends RefCounted
## Lightweight ragdoll for crash reactions: 16 joint particles, distance
## constraints (rigid torso, fixed bone lengths, minimum spans that stop
## elbows/knees folding flat), anatomical joint limits (knees and elbows only
## hinge the right way; hips and shoulders stay inside a cone of motion),
## swept-ray collision against buildings/street,
## and the pelvis softly pinned to the physics capsule. Visual only – the
## Player's CharacterBody stays the single source of truth for movement.
## Only runs while a crash is in progress (~1–3 s), never for idle bodies.

const STEP := 1.0 / 60.0
const ITERATIONS := 8
const GRAVITY := Vector3(0, -19.0, 0)
const MASK := 1 | (1 << 1) | (1 << 3) | (1 << 4)  # buildings, street, props

const NAMES := ["pelvis", "chest", "neck", "head", "sh_l", "sh_r", "el_l", "el_r", "wr_l", "wr_r",
	"hip_l", "hip_r", "kn_l", "kn_r", "an_l", "an_r"]

var pos := {}
var prev := {}
var links: Array = []   # [a, b, rest, kind] kind: 0 = exact, 1 = min-only
const TORSO := ["pelvis", "chest", "neck", "head", "sh_l", "sh_r", "hip_l", "hip_r"]
var _torso_rest := {}   # torso particle -> offset in the torso frame (rigid shape)
var _acc := 0.0
var space: PhysicsDirectSpaceState3D
## While dangling from the web, the web hand's wrist is held here (INF = free).
var hand_pin := Vector3.INF
## Protective reflex: particle -> world point it is pulled toward (weakly),
## e.g. the wrists reaching for the ground to break a fall. Set per update.
var reach := {}
var reach_k := 0.0
var exclude: Array[RID] = []


## joints: name -> world position (from the current pose); vel: body velocity;
## part_vel: optional extra velocity per particle (e.g. whiplash on impact).
func start(joints: Dictionary, vel: Vector3, spin: Vector3, part_vel := {}) -> void:
	pos.clear()
	prev.clear()
	links.clear()
	var c: Vector3 = joints["pelvis"]
	for n in NAMES:
		var p: Vector3 = joints[n]
		pos[n] = p
		# Initial velocity: body velocity plus a little tumble about the pelvis.
		prev[n] = p - (vel + spin.cross(p - c) + (part_vel.get(n, Vector3.ZERO) as Vector3)) * STEP
	for pair in [["pelvis", "chest"], ["chest", "neck"], ["neck", "head"], ["chest", "sh_l"], ["chest", "sh_r"],
			["sh_l", "sh_r"], ["pelvis", "sh_l"], ["pelvis", "sh_r"], ["pelvis", "hip_l"], ["pelvis", "hip_r"],
			["hip_l", "hip_r"], ["chest", "hip_l"], ["chest", "hip_r"], ["neck", "sh_l"], ["neck", "sh_r"],
			["head", "sh_l"], ["head", "sh_r"], ["sh_l", "hip_r"], ["sh_r", "hip_l"]]:
		_link(pair[0], pair[1], 0)
	var f := _torso_frame()
	for n in TORSO:
		_torso_rest[n] = f.affine_inverse() * (pos[n] as Vector3)
	for limb in [["sh_l", "el_l", "wr_l"], ["sh_r", "el_r", "wr_r"], ["hip_l", "kn_l", "an_l"], ["hip_r", "kn_r", "an_r"]]:
		_link(limb[0], limb[1], 0)
		_link(limb[1], limb[2], 0)
		# Joint limit: the limb can bend but never fold completely shut.
		var full: float = (pos[limb[0]] as Vector3).distance_to(pos[limb[1]]) + (pos[limb[1]] as Vector3).distance_to(pos[limb[2]])
		links.append([limb[0], limb[2], full * 0.45, 1])


func _link(a: String, b: String, kind: int) -> void:
	links.append([a, b, (pos[a] as Vector3).distance_to(pos[b]), kind])


## Advances the simulation; `anchor` is where the pelvis should stay (capsule).
func update(dt: float, anchor: Vector3) -> void:
	_acc = minf(_acc + dt, STEP * 4.0)
	while _acc >= STEP:
		_acc -= STEP
		_step(anchor)


func _step(anchor: Vector3) -> void:
	for n in NAMES:
		var p: Vector3 = pos[n]
		var v: Vector3 = (p - prev[n]) * 0.985  # air damping
		prev[n] = p
		var np := p + v + GRAVITY * STEP * STEP
		var c := _collide(p, np)
		if c != np:
			prev[n] = c - (c - p) * 0.3  # contact: friction + mostly inelastic
		pos[n] = c
	for it in ITERATIONS:
		# Soft pin: the body stays with the physics capsule.
		pos["pelvis"] = (pos["pelvis"] as Vector3).lerp(anchor, 0.25)
		if hand_pin != Vector3.INF:
			pos["wr_r"] = (pos["wr_r"] as Vector3).lerp(hand_pin, 0.6)
		for n in reach:
			pos[n] = (pos[n] as Vector3).lerp(reach[n], reach_k)
		for l in links:
			var a: Vector3 = pos[l[0]]
			var b: Vector3 = pos[l[1]]
			var d := b - a
			var len := d.length()
			if len < 1e-5:
				continue
			var rest: float = l[2]
			if l[3] == 1 and len >= rest:
				continue
			var corr := d * ((len - rest) / len) * 0.5
			pos[l[0]] = a + corr
			pos[l[1]] = b - corr
	# The torso is one rigid piece: snap its particles to the rest shape in the
	# frame they currently define.
	var f := _torso_frame()
	for n in TORSO:
		pos[n] = f * (_torso_rest[n] as Vector3)
	_joint_limits(f)
	# Limbs, root to tip: bones end every step at exactly their length – never
	# stretched or squashed, whatever collisions or the pelvis pin did.
	for l in links:
		if l[3] != 0 or (l[0] in TORSO and l[1] in TORSO):
			continue
		var a2: Vector3 = pos[l[0]]
		var d2: Vector3 = (pos[l[1]] as Vector3) - a2
		if d2.length() > 1e-5:
			pos[l[1]] = a2 + d2.normalized() * float(l[2])
	# Hinges last: mirroring a knee/elbow across its limb line keeps both bone
	# lengths, so nothing after this can bend them the wrong way again.
	var fw := -_torso_frame().basis.z
	for sd in ["l", "r"]:
		_hinge("hip_" + sd, "kn_" + sd, "an_" + sd, fw)
		_hinge("sh_" + sd, "el_" + sd, "wr_" + sd, -fw)
	_project_out(anchor)


## Body thickness: how far each joint's surface reaches past its particle.
const RADIUS := {"pelvis": 0.13, "chest": 0.15, "neck": 0.07, "head": 0.13, "sh_l": 0.08, "sh_r": 0.08}
const LIMB_RADIUS := 0.06


## Last step: constraints, joint limits and hinges move particles after
## their swept collision, so the torso (with its thickness) can end up in a
## wall. The whole body is shifted out rigidly – bone lengths and hinges stay
## exact; limbs are kept out of the world by CharacterRig._guard_limbs.
func _project_out(anchor: Vector3) -> void:
	if space == null:
		return
	var push := Vector3.ZERO
	for n in TORSO:
		var p: Vector3 = (pos[n] as Vector3) + push
		var r: float = RADIUS.get(n, LIMB_RADIUS)
		var d := p - anchor
		if d.length_squared() < 1e-6:
			continue
		var q := PhysicsRayQueryParameters3D.create(anchor, p + d.normalized() * r, MASK, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var target: Vector3 = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * r
		var nrm: Vector3 = hit["normal"]
		push += nrm * maxf((target - p).dot(nrm), 0.0)
	if push == Vector3.ZERO:
		return
	for n in NAMES:
		pos[n] = (pos[n] as Vector3) + push
		prev[n] = (prev[n] as Vector3) + push * 0.7  # most of the push is not new velocity


## Hip/shoulder cones, in the torso frame
## (x right, y up, z back).
func _joint_limits(f: Transform3D) -> void:
	var b := f.basis
	var fwd := -b.z
	for sd in ["l", "r"]:
		var side := -1.0 if sd == "l" else 1.0
		# Hip: thigh may swing forward up to ~120° but only ~30° back, ~50° out
		# and barely across the body.
		_cone("hip_" + sd, "kn_" + sd, b, Vector3(0.75, 0.5, 0.5), side)
		# Shoulder: wide, but not far behind the back.
		_cone("sh_" + sd, "el_" + sd, b, Vector3(1.0, 1.0, 0.7), side)
		# Knee bends backward (shin behind the thigh line); elbow bends forward
		# (elbow sits behind the shoulder→wrist line).


## Keeps `tip` inside a cone around the root: limits = (max |x| outward-ish,
## max y up, max z back) for the unit direction in the torso frame.
func _cone(root: String, tip: String, b: Basis, lim: Vector3, side: float) -> void:
	var r: Vector3 = pos[root]
	var d: Vector3 = (pos[tip] as Vector3) - r
	var len := d.length()
	if len < 1e-5:
		return
	var l := b.inverse() * (d / len)
	var across := -l.x * side  # toward the other side of the body
	var changed := false
	if l.y > lim.y:
		l.y = lim.y
		changed = true
	if l.z > lim.z:
		l.z = lim.z
		changed = true
	if absf(l.x) > lim.x:
		l.x = signf(l.x) * lim.x
		changed = true
	if across > 0.35:
		l.x = -0.35 * side
		changed = true
	if changed:
		pos[tip] = r + (b * l.normalized()) * len


## The middle joint must sit on the `bend` side of the root→end line.
func _hinge(root: String, mid: String, end: String, bend: Vector3) -> void:
	var a: Vector3 = pos[root]
	var m: Vector3 = pos[mid]
	var e: Vector3 = pos[end]
	var ax := e - a
	if ax.length_squared() < 1e-6:
		return
	var closest := a + ax * clampf((m - a).dot(ax) / ax.length_squared(), 0.0, 1.0)
	var off := m - closest
	var b := bend - ax.normalized() * bend.dot(ax.normalized())
	if off.dot(b) < 0.0:
		pos[mid] = closest - off  # mirror the joint to the side it can bend
		# ...and drop its velocity, or it keeps driving back across the line
		# and the limb flips side to side (visibly spinning about itself).
		prev[mid] = pos[mid]


func _torso_frame() -> Transform3D:
	var p: Vector3 = pos["pelvis"]
	var up: Vector3 = ((pos["neck"] as Vector3) - p).normalized()
	var right: Vector3 = (pos["sh_r"] as Vector3) - (pos["sh_l"] as Vector3)
	right = (right - up * right.dot(up)).normalized()
	if right.length_squared() < 0.5:
		right = up.cross(Vector3.FORWARD).normalized()
	return Transform3D(Basis(right, up, right.cross(up)), p)


func _collide(from: Vector3, to: Vector3) -> Vector3:
	if space == null:
		return to
	var q := PhysicsRayQueryParameters3D.create(from, to + (to - from).normalized() * 0.06, MASK, exclude)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return to
	var n: Vector3 = hit["normal"]
	return (hit["position"] as Vector3) + n * 0.06


## Largest relative error of the exact-length links (tests: no stretching).
func max_stretch() -> float:
	var worst := 0.0
	for l in links:
		if l[3] == 0:
			var len := (pos[l[0]] as Vector3).distance_to(pos[l[1]])
			worst = maxf(worst, absf(len - l[2]) / l[2])
	return worst
