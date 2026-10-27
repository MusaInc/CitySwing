class_name VerletRagdoll
extends RefCounted
## Lightweight ragdoll for crash reactions: 16 joint particles, distance
## constraints (rigid torso, fixed bone lengths, minimum spans that stop
## elbows/knees folding flat), swept-ray collision against buildings/street,
## and the pelvis softly pinned to the physics capsule. Visual only – the
## Player's CharacterBody stays the single source of truth for movement.
## Only runs while a crash is in progress (~1–3 s), never for idle bodies.

const STEP := 1.0 / 60.0
const ITERATIONS := 6
const GRAVITY := Vector3(0, -19.0, 0)
const MASK := 1 | (1 << 1) | (1 << 3)

const NAMES := ["pelvis", "chest", "neck", "head", "sh_l", "sh_r", "el_l", "el_r", "wr_l", "wr_r",
	"hip_l", "hip_r", "kn_l", "kn_r", "an_l", "an_r"]

var pos := {}
var prev := {}
var links: Array = []   # [a, b, rest, kind] kind: 0 = exact, 1 = min-only
var _acc := 0.0
var space: PhysicsDirectSpaceState3D
## While dangling from the web, the web hand's wrist is held here (INF = free).
var hand_pin := Vector3.INF
var exclude: Array[RID] = []


## joints: name -> world position (from the current pose); vel: body velocity.
func start(joints: Dictionary, vel: Vector3, spin: Vector3) -> void:
	pos.clear()
	prev.clear()
	links.clear()
	var c: Vector3 = joints["pelvis"]
	for n in NAMES:
		var p: Vector3 = joints[n]
		pos[n] = p
		# Initial velocity: body velocity plus a little tumble about the pelvis.
		prev[n] = p - (vel + spin.cross(p - c)) * STEP
	for pair in [["pelvis", "chest"], ["chest", "neck"], ["neck", "head"], ["chest", "sh_l"], ["chest", "sh_r"],
			["sh_l", "sh_r"], ["pelvis", "sh_l"], ["pelvis", "sh_r"], ["pelvis", "hip_l"], ["pelvis", "hip_r"],
			["hip_l", "hip_r"], ["chest", "hip_l"], ["chest", "hip_r"], ["neck", "sh_l"], ["neck", "sh_r"],
			["head", "sh_l"], ["head", "sh_r"], ["sh_l", "hip_r"], ["sh_r", "hip_l"]]:
		_link(pair[0], pair[1], 0)
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
		pos["pelvis"] = (pos["pelvis"] as Vector3).lerp(anchor, 0.35)
		if hand_pin != Vector3.INF:
			pos["wr_r"] = (pos["wr_r"] as Vector3).lerp(hand_pin, 0.6)
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
