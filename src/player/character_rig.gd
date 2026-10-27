class_name CharacterRig
extends Node3D
## Physically reactive character (visual only – never feeds back into the
## Player's physics).
##
##  * Every joint is a spring-damper chasing a pose target, so limbs carry
##    inertia: legs trail on acceleration, arms lag and overshoot, transitions
##    blend on their own instead of snapping between clips.
##  * Targets come from the simulation: rope direction and tension, velocity,
##    local acceleration, turn rate, ground contact.
##  * Swinging: the body hangs from the web hand along the rope, torso twists
##    into turns, knees tuck under load and legs trail at speed.
##  * Free flight: release spin is conserved (visual), fast dives stretch out
##    head-first, JUMP in the air tucks into a flip.
##  * Hard crashes hand the body to a VerletRagdoll, then spring back up.
## Model: assets/models/character.glb (tools/blender/build_character.py) –
## one continuous skinned body on a Skeleton3D whose bones match BONES, plus
## rigid parts (head, hands, fists, sneakers, spool, scarf) parented to the
## pivots. The pivots stay the source of truth (springs, ragdoll, IK all pose
## them); _sync_skeleton() maps them onto the skeleton each frame. The skin
## was bound in an A-pose (ARM_A / LEG_A), so each bone carries a fixed
## correction from "pivot in A-pose" to "skeleton bone at rest".

const MODEL_PATH := "res://assets/models/character.glb"

# Bone layout: name -> [parent, local rest offset, length]
const BONES := {
	"hips": ["", Vector3(0, 0.98, 0), 0.0],
	"spine": ["hips", Vector3(0, 0.06, 0), 0.0],
	"chest": ["spine", Vector3(0, 0.26, 0), 0.0],
	"neck": ["chest", Vector3(0, 0.26, 0), 0.0],
	"head": ["neck", Vector3(0, 0.08, 0), 0.0],
	"upper_arm_l": ["chest", Vector3(-0.2, 0.2, 0), 0.29],
	"forearm_l": ["upper_arm_l", Vector3(0, -0.29, 0), 0.26],
	"hand_l": ["forearm_l", Vector3(0, -0.26, 0), 0.09],
	"upper_arm_r": ["chest", Vector3(0.2, 0.2, 0), 0.29],
	"forearm_r": ["upper_arm_r", Vector3(0, -0.29, 0), 0.26],
	"hand_r": ["forearm_r", Vector3(0, -0.26, 0), 0.09],
	"thigh_l": ["hips", Vector3(-0.1, -0.04, 0), 0.45],
	"shin_l": ["thigh_l", Vector3(0, -0.45, 0), 0.44],
	"foot_l": ["shin_l", Vector3(0, -0.44, 0), 0.0],
	"thigh_r": ["hips", Vector3(0.1, -0.04, 0), 0.45],
	"shin_r": ["thigh_r", Vector3(0, -0.45, 0), 0.44],
	"foot_r": ["shin_r", Vector3(0, -0.44, 0), 0.0],
}
# Spring stiffness (1/s²) and damping (1/s) per joint group.
const SPRINGS := {
	"core": [190.0, 24.0], "head": [240.0, 28.0], "arm": [120.0, 15.0], "leg": [95.0, 13.0], "rope_arm": [1600.0, 80.0],
}
const SCARF_LEN := 0.17
## Bind pose of the skinned body (see build_character.py).
const ARM_A := deg_to_rad(42.0)
const LEG_A := deg_to_rad(5.0)
## The model's feet sit at y = 0; the rig's origin is the capsule centre.
const MODEL_OFFSET := Vector3(0, -0.9, 0)

var player: Player
var bones := {}
var launcher: Node3D  # the web hand; RopeVisual starts here
var ragdoll := VerletRagdoll.new()
var ragdolling := false
var _mat: ShaderMaterial
var skeleton: Skeleton3D
var _skel_idx := {}       # bone name -> skeleton bone index
var _skel_fix := {}       # bone name -> Transform3D (pivot frame -> bone frame)

var _rot := {}      # bone -> Quaternion (current)
var _angvel := {}   # bone -> Vector3 (angular velocity, parent space)
var _body_basis := Basis()
var _facing := Vector3.FORWARD
var _prev_vel := Vector3.ZERO
var _accel := Vector3.ZERO
var _yaw_rate := 0.0
var _prev_facing_angle := 0.0
var _run_phase := 0.0
var _land_squash := 0.0
var _flip := 0.0           # visual somersault angle (rad) about the body's right axis
var _flip_rate := 0.0
var _trick_time := 0.0
var _roll_time := 0.0
var _rag_time := 0.0
var _recover_blend := 0.0
var _time := 0.0
var _load := 0.0           # rope load 0..1 (smoothed)
var _lgrip := 0.0          # free hand on the line 0..1
var _wall_time := 0.0      # wall run / wall tap pose remaining
var _wall_n := Vector3.BACK
var _takeoff_t := 0.0
var _getup_t := 0.0
var _air_t := 0.0
var _was_grounded := true
var _loco := 0.0           # 0..1 how much ground locomotion drives the limbs
var _grips := {}           # "l"/"r" -> [open_node, grip_node]
var _scarf: Array[Node3D] = []
var _scarf_pts: Array[Vector3] = []
var _scarf_prev: Array[Vector3] = []


func _ready() -> void:
	var parts := _load_parts()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/player/shaders/character.gdshader")
	_mat = mat
	if skeleton:
		for mi in skeleton.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mat
	set_suit_color(Progress.current_suit_color())
	for name in BONES:
		var def: Array = BONES[name]
		var pivot := Node3D.new()
		pivot.name = name
		var parent: Node3D = self if def[0] == "" else bones[def[0]]
		parent.add_child(pivot)
		pivot.position = def[1] - Vector3(0, 0.9, 0) * float(def[0] == "")
		bones[name] = pivot
		_rot[name] = Quaternion.IDENTITY
		_angvel[name] = Vector3.ZERO
		var part: MeshInstance3D = parts.get(name)
		if part:
			part.transform = Transform3D.IDENTITY
			part.material_override = mat
			pivot.add_child(part)
		elif parts.is_empty():
			_add_fallback_mesh(name, pivot, def[2])
	for side in ["l", "r"]:
		var grip: MeshInstance3D = parts.get("hand_%s_grip" % side)
		if grip:
			grip.transform = Transform3D.IDENTITY
			grip.material_override = mat
			bones["hand_" + side].add_child(grip)
			grip.visible = false
			_grips[side] = [parts.get("hand_" + side), grip]
	launcher = bones["hand_r"]
	_bind_skeleton()
	for i in (3 if parts.has("scarf_0") else 0):  # optional cloth tail
		var seg := Node3D.new()
		seg.name = "scarf_%d" % i
		seg.top_level = true
		add_child(seg)
		var m: MeshInstance3D = parts.get("scarf_%d" % i)
		if m:
			m.transform = Transform3D.IDENTITY
			m.material_override = mat
			seg.add_child(m)
		_scarf.append(seg)
	if player:
		_connect_player()


## Recolours the jacket (see character.gdshader).
func set_suit_color(c: Color) -> void:
	if _mat:
		_mat.set_shader_parameter("suit_color", Vector3(c.r, c.g, c.b))


func set_player(p: Player) -> void:
	player = p
	if is_inside_tree():
		_connect_player()


func _connect_player() -> void:
	if player.trick.is_connected(_on_trick):
		return
	player.trick.connect(_on_trick)
	player.released.connect(_on_released)
	player.stun_started.connect(_on_stun)
	player.stun_ended.connect(_on_stun_ended)
	player.respawned.connect(_on_respawned)
	player.landed.connect(func(spd, _street): on_landed(spd))
	player.wall_kicked.connect(_on_wall)
	player.attached.connect(func(_a): _jolt(0.6))
	player.rope_snapped.connect(func(spd): _jolt(clampf(spd / 8.0, 0.3, 1.5)))
	ragdoll.exclude = [player.get_rid()]


func _load_parts() -> Dictionary:
	var out := {}
	if not ResourceLoader.exists(MODEL_PATH):
		return out
	var scene: PackedScene = load(MODEL_PATH)
	var inst := scene.instantiate()
	var skel := inst.find_children("*", "Skeleton3D", true, false)
	if not skel.is_empty():
		skeleton = skel[0]
		skeleton.get_parent().remove_child(skeleton)
		skeleton.owner = null
		skeleton.transform = Transform3D(Basis(), MODEL_OFFSET)
		add_child(skeleton)
		for mi in skeleton.find_children("*", "MeshInstance3D", true, false):
			mi.owner = null
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var key := String(child.name).to_lower()
		child.get_parent().remove_child(child)
		child.owner = null
		out[key] = child
	inst.free()
	return out


## Records, per bone, the fixed transform from the pivot's frame (posed in the
## bind A-pose) to the skeleton bone's rest frame, both in rig space.
func _bind_skeleton() -> void:
	if skeleton == null:
		return
	var a_pose := {}
	for b in BONES:
		a_pose[b] = Quaternion.IDENTITY
	a_pose["upper_arm_l"] = _rz(-ARM_A)
	a_pose["upper_arm_r"] = _rz(ARM_A)
	a_pose["thigh_l"] = _rz(-LEG_A)
	a_pose["thigh_r"] = _rz(LEG_A)
	var pivots := _pivot_transforms(a_pose)
	var off := skeleton.transform
	for b in BONES:
		var i := skeleton.find_bone("b_" + b)
		if i < 0:
			continue
		_skel_idx[b] = i
		_skel_fix[b] = (pivots[b] as Transform3D).affine_inverse() * off * skeleton.get_bone_global_rest(i)


## Rig-space transforms of every pivot for the given local rotations.
func _pivot_transforms(rots: Dictionary) -> Dictionary:
	var out := {}
	for b in BONES:  # parents come before children in BONES
		var def: Array = BONES[b]
		var local := Transform3D(Basis(rots[b] as Quaternion), (bones[b] as Node3D).position)
		out[b] = local if def[0] == "" else (out[def[0]] as Transform3D) * local
	return out


## Poses the skinned body from the pivots (called after every pose update).
func _sync_skeleton() -> void:
	if skeleton == null or _skel_idx.is_empty():
		return
	var rots := {}
	for b in BONES:
		rots[b] = (bones[b] as Node3D).quaternion
	var piv := _pivot_transforms(rots)
	var inv_off := skeleton.transform.affine_inverse()
	var glob := {}
	for b in BONES:
		if not _skel_idx.has(b):
			continue
		var g: Transform3D = inv_off * (piv[b] as Transform3D) * (_skel_fix[b] as Transform3D)
		glob[b] = g
		var parent: String = BONES[b][0]
		var local := g if parent == "" else (glob[parent] as Transform3D).affine_inverse() * g
		var i: int = _skel_idx[b]
		skeleton.set_bone_pose_position(i, local.origin)
		skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())


func _add_fallback_mesh(name: String, pivot: Node3D, length: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.12 if name in ["hips", "spine", "chest", "head"] else 0.06
	cm.height = maxf(length, 0.24) + cm.radius
	mi.mesh = cm
	mi.position.y = -length * 0.5 if length > 0.0 else 0.12
	pivot.add_child(mi)


## Facing direction on spawn (horizontal).
func set_facing(dir: Vector3) -> void:
	_facing = Vector3(dir.x, 0, dir.z).normalized()
	_body_basis = Basis.looking_at(_facing, Vector3.UP)


# ------------------------------------------------------------------ events
func on_landed(speed: float) -> void:
	_land_squash = clampf(speed / 25.0, 0.15, 0.9)
	var vh := Vector3(player.s.velocity.x, 0, player.s.velocity.z).length() if player else 0.0
	if player and speed > player.params.roll_landing_speed and vh > 8.0 and not ragdolling:
		_roll_time = 0.55  # shoulder roll to absorb a fast landing
	_flip_rate = 0.0


## Wall run / wall tap: face the wall and run up it while still rising.
func _on_wall() -> void:
	_wall_time = 0.7
	if player.is_on_wall():
		_wall_n = player.get_wall_normal()
	else:
		_wall_n = -Vector3(player.s.velocity.x, 0, player.s.velocity.z).normalized()
	_wall_n = Vector3(_wall_n.x, 0, _wall_n.z).normalized()
	if _wall_n.length_squared() < 0.5:
		_wall_n = -_facing


## The line catching the body: a physical jolt through spine, head and legs
## (spring impulses, so it settles by itself instead of snapping).
func _jolt(strength: float) -> void:
	_angvel["spine"] += Vector3(-2.5, 0, 0) * strength
	_angvel["chest"] += Vector3(-1.5, 0, 0) * strength
	_angvel["head"] += Vector3(3.0, 0, 0) * strength
	for sd in ["l", "r"]:
		_angvel["thigh_" + sd] += Vector3(4.0, 0, 0) * strength
		_angvel["shin_" + sd] += Vector3(-4.0, 0, 0) * strength


func _on_trick() -> void:
	if _trick_time <= 0.0 and not ragdolling:
		_trick_time = 0.6


func _on_released(v: Vector3) -> void:
	# The body was rotating with the rope; that spin carries on after release.
	var r := player.global_position - player.s.anchor
	var omega := r.cross(v) / maxf(r.length_squared(), 1.0)
	var right := _body_basis.x
	_flip_rate = clampf(omega.dot(right), -4.0, 4.0)


func _on_stun(_speed: float) -> void:
	ragdolling = true
	_rag_time = 0.0
	ragdoll.space = get_world_3d().direct_space_state
	var spin := Vector3(randf_range(-3, 3), randf_range(-2, 2), randf_range(-3, 3))
	ragdoll.start(joint_positions(), player.s.velocity * 0.6, spin)


func _on_respawned() -> void:
	ragdolling = false
	_flip = 0.0
	_flip_rate = 0.0
	_trick_time = 0.0
	_roll_time = 0.0
	for b in BONES:
		_angvel[b] = Vector3.ZERO
	_reset_scarf()


func joint_positions() -> Dictionary:
	var g := func(b: String) -> Vector3: return (bones[b] as Node3D).global_position
	var head_top: Vector3 = g.call("head") + (bones["head"] as Node3D).global_basis.y * 0.2
	return {
		"pelvis": g.call("hips"), "chest": g.call("chest"), "neck": g.call("neck"), "head": head_top,
		"sh_l": g.call("upper_arm_l"), "sh_r": g.call("upper_arm_r"), "el_l": g.call("forearm_l"),
		"el_r": g.call("forearm_r"), "wr_l": g.call("hand_l"), "wr_r": g.call("hand_r"),
		"hip_l": g.call("thigh_l"), "hip_r": g.call("thigh_r"), "kn_l": g.call("shin_l"), "kn_r": g.call("shin_r"),
		"an_l": g.call("foot_l"), "an_r": g.call("foot_r"),
	}


# ------------------------------------------------------------------ update
func _process(dt: float) -> void:
	if player == null:
		return
	dt = minf(dt, 1.0 / 20.0)
	_time += dt
	if ragdolling:
		_update_ragdoll(dt)
	else:
		_update_animated(dt)
	_update_scarf(dt)
	_sync_skeleton()
	_set_grip("r", player.line_state != Player.Line.IDLE)
	_set_grip("l", player.line_state == Player.Line.ATTACHED and player.s.tension > 25.0)


func _set_grip(side: String, on: bool) -> void:
	if _grips.has(side) and _grips[side][0] and _grips[side][1]:
		_grips[side][0].visible = not on
		_grips[side][1].visible = on


func _update_animated(dt: float) -> void:
	var s := player.s
	var v := s.velocity
	var acc := (v - _prev_vel) / maxf(dt, 0.001)
	_prev_vel = v
	_accel = _accel.lerp(acc.limit_length(80.0), 1.0 - exp(-10.0 * dt))
	var vh := Vector3(v.x, 0.0, v.z)
	var hs := vh.length()
	var speed := v.length()
	var grounded := player.is_on_floor() and not s.attached
	var on_rope := player.line_state != Player.Line.IDLE
	var attached := player.line_state == Player.Line.ATTACHED
	# Rope load 0..1: taut + tension. Slack line = 0 (body relaxes into flight).
	_load = move_toward(_load, clampf(s.tension / 40.0, 0.0, 1.0) if attached and s.taut else 0.0, dt * 4.0)
	var wall_run := _wall_time > 0.0 and v.y > 1.5 and not on_rope
	_wall_time = maxf(_wall_time - dt, 0.0)
	_takeoff_t = maxf(_takeoff_t - dt, 0.0)
	_getup_t = maxf(_getup_t - dt, 0.0)
	if grounded and not _was_grounded:
		_air_t = 0.0
	if not grounded and _was_grounded and v.y > 6.0 and not on_rope:
		_takeoff_t = 0.3  # push-off: legs extend, arms drive up
	_was_grounded = grounded
	if not grounded:
		_air_t += dt
	var air := not grounded and not on_rope
	_loco = move_toward(_loco, 1.0 if grounded and _getup_t <= 0.0 else 0.0, dt * 6.0)

	# --- facing & turn rate -----------------------------------------------
	if wall_run:
		_facing = _facing.slerp(-_wall_n, 1.0 - exp(-14.0 * dt)).normalized()
	elif hs > 1.0:
		_facing = _facing.slerp(vh.normalized(), 1.0 - exp(-(6.0 if grounded else 3.5) * dt)).normalized()
	elif grounded and player.controls.move.length() > 0.1:
		_facing = _facing.slerp(player.controls.move.normalized(), 1.0 - exp(-8.0 * dt)).normalized()
	var ang := atan2(_facing.x, _facing.z)
	_yaw_rate = lerpf(_yaw_rate, wrapf(ang - _prev_facing_angle, -PI, PI) / maxf(dt, 0.001), 1.0 - exp(-6.0 * dt))
	_prev_facing_angle = ang
	var right_w := Vector3.UP.cross(_facing).normalized() * -1.0  # facing × up = right
	var la_w := _accel

	# --- whole-body orientation -------------------------------------------
	var up := Vector3.UP
	var fwd_hint := _facing
	var dive := 0.0
	if grounded:
		# Lean into acceleration (sprint start / braking) and into turns.
		var fa := clampf(la_w.dot(_facing) * 0.006, -0.15, 0.16)
		var run_lean := 0.1 * clampf(hs / 11.0, 0.0, 1.0)
		var bank := clampf(-_yaw_rate * hs * 0.025, -0.35, 0.35)
		up = (Vector3.UP + _facing * (fa + run_lean) + right_w * bank).normalized()
	elif wall_run:
		up = (Vector3.UP + _wall_n * 0.12).normalized()  # chest to the wall, hips just off it
	elif on_rope:
		var target := s.anchor if attached else player.line_tip
		var rope_dir := (target - player.global_position).normalized()
		# Taut: the line of force runs up through the body. Slack or flying
		# line: mostly upright, reaching toward it.
		var k := 0.35 + 0.65 * _load if attached else 0.3
		up = Vector3.UP.slerp(rope_dir, k).normalized()
		var vt := v - up * v.dot(up)
		if vt.length() > 1.0:
			fwd_hint = vt.normalized()
	else:
		# Head-first only in a fast, steep descent with real forward speed.
		dive = clampf((-v.y - 20.0) / 12.0, 0.0, 1.0) * clampf((speed - 28.0) / 10.0, 0.0, 1.0) \
			* clampf((hs - 12.0) / 8.0, 0.0, 1.0)
		var lean := clampf(speed / 60.0, 0.0, 0.28)
		up = Vector3.UP.lerp(v.normalized() if speed > 1.0 else Vector3.UP, lean).normalized()
		if v.y < -6.0:
			up = up.lerp(Vector3.UP, 0.5).normalized()  # dropping: feet stay under the body
		if dive > 0.0:
			up = up.slerp(v.normalized(), dive * 0.85).normalized()
			fwd_hint = Vector3.DOWN.slerp(_facing, 0.5).normalized()
	var fwd := (fwd_hint - up * fwd_hint.dot(up)).normalized()
	if fwd.length_squared() < 0.01:
		fwd = (_facing - up * _facing.dot(up)).normalized()
	if fwd.length_squared() < 0.01:
		fwd = Vector3.FORWARD
	var want := Basis.looking_at(fwd, up).orthonormalized()
	var rate := 12.0 if grounded else (8.0 if on_rope else 5.0)
	if _getup_t > 0.0:
		rate = 5.0  # rise from the ground, don't pop upright
	if wall_run:
		rate = 14.0
	_body_basis = _body_basis.slerp(want, 1.0 - exp(-rate * dt)).orthonormalized()

	# --- acrobatics (visual only) ------------------------------------------
	if _trick_time > 0.0:
		_trick_time -= dt
		_flip -= TAU / 0.6 * dt  # one forward somersault
	elif _roll_time > 0.0:
		_roll_time -= dt
		_flip -= TAU / 0.55 * dt
	elif air:
		_flip += _flip_rate * dt
		_flip_rate = move_toward(_flip_rate, 0.0, 2.2 * dt)
	if _trick_time <= 0.0 and _roll_time <= 0.0:
		var resid := wrapf(_flip, -PI, PI)
		_flip = resid
		if not air or absf(_flip_rate) < 0.3:
			_flip = lerpf(_flip, 0.0, 1.0 - exp(-(10.0 if not air else 3.0) * dt))
	var body := _body_basis * Basis(Vector3.RIGHT, _flip)
	global_basis = body
	global_position = player.global_position
	var to_local := body.inverse()

	# --- pose targets --------------------------------------------------------
	var la := to_local * _accel
	var lv := to_local * v
	_land_squash = move_toward(_land_squash, 0.0, dt * 2.5)
	var q := {}
	for b in BONES:
		q[b] = Quaternion.IDENTITY
	var twist := clampf(_yaw_rate * 0.12, -0.55, 0.55)
	var bob := 0.0

	if _trick_time > 0.0 or _roll_time > 0.0:
		# Tight tuck for flips and landing rolls.
		q["spine"] = _rx(0.55)
		q["chest"] = _rx(0.35)
		q["neck"] = _rx(0.2)
		q["head"] = _rx(0.3)
		for sd in ["l", "r"]:
			q["thigh_" + sd] = _rx(1.95)
			q["shin_" + sd] = _rx(-2.25)
			q["foot_" + sd] = _rx(0.3)
			q["upper_arm_" + sd] = _rx(1.1) * _rz(0.25 if sd == "r" else -0.25)
			q["forearm_" + sd] = _rx(1.5)
	elif _getup_t > 0.0:
		_pose_getup(q, _getup_t / GETUP_TIME)
	elif wall_run:
		_pose_wall_run(q, dt)
	elif grounded:
		bob = _pose_ground(q, dt, hs, la)
	elif on_rope:
		_pose_rope(q, dt, body, la, twist, speed)
	else:
		_pose_air(q, v, speed, la, dive, twist)
	if _takeoff_t > 0.0 and air:
		# Push-off: hips and knees extend through the jump, arms drive upward.
		var k := _takeoff_t / 0.3
		for sd in ["l", "r"]:
			q["thigh_" + sd] = q["thigh_" + sd].slerp(_rx(-0.15 if sd == "l" else 0.25), k)
			q["shin_" + sd] = q["shin_" + sd].slerp(_rx(-0.1), k)
			q["foot_" + sd] = q["foot_" + sd].slerp(_rx(-0.5), k)
			q["upper_arm_" + sd] = q["upper_arm_" + sd].slerp(_rx(1.3) * _rz(0.2 if sd == "r" else -0.2), k)
	# Hip bob (running) – the pelvis rides up and down over the stance leg.
	(bones["hips"] as Node3D).position.y = lerpf((bones["hips"] as Node3D).position.y,
		(BONES["hips"][1] as Vector3).y - 0.9 + bob, 1.0 - exp(-20.0 * dt))

	_drive_springs(q, dt, on_rope)


const GETUP_TIME := 0.75


## Ground: idle → walk → sprint. Each leg alternates a stance phase, in
## which the thigh sweeps back at exactly the ground speed so the foot stays
## planted (sole held flat, toe-off at the end), and a swing phase that drives
## the knee forward and folds the heel up. Stance is ~60% of a walking cycle and
## ~28% of a sprint (longer flight). The cycle advances with distance.
func _pose_ground(q: Dictionary, dt: float, hs: float, la: Vector3) -> float:
	var stride_len := clampf(0.55 + hs * 0.15, 0.55, 2.2)  # metres per step
	_run_phase += dt * hs * PI / stride_len
	var run := clampf((hs - 2.5) / 5.0, 0.0, 1.0)  # 0 walk … 1 run
	var mv := clampf(hs / 1.2, 0.0, 1.0)            # 0 standing … 1 moving
	var stance := lerpf(0.6, 0.28, run)
	var leg := 0.86
	# Half the hip→ankle sweep covered while the foot is planted.
	var period := TAU / maxf(hs * PI / stride_len, 0.01)
	var a := clampf(hs * stance * period / (2.0 * leg), 0.0, 0.75) * mv
	var brake := clampf(la.z * 0.03, 0.0, 0.5)
	var lean := 0.16 * run + _land_squash * 0.45 - brake * 0.25
	var ph := _run_phase
	var sw := sin(ph)
	q["spine"] = _rx(lean) * _ry(-sw * 0.12 * mv)
	q["chest"] = _ry(-sw * 0.22 * mv) * _rx(0.06 * run)
	q["neck"] = _ry(sw * 0.1 * mv)
	q["head"] = _rx(-lean * 0.7 + 0.04)
	var bob := 0.0
	for i in 2:
		var sd := "l" if i == 0 else "r"
		var u := fposmod((ph + PI * i) / TAU, 1.0)
		var thigh: float
		var knee: float
		var foot: float
		if u < stance:
			var w := u / stance
			thigh = a * (1.0 - 2.0 * w)                 # front → back at ground speed
			knee = 0.1 + (0.12 + 0.3 * run) * sin(PI * w)  # absorbs the load mid-stance
			foot = -thigh + knee - 0.0                   # sole parallel to the ground
			foot += smoothstep(0.75, 1.0, w) * 0.6 * mv  # toe-off
			bob -= (0.025 + 0.02 * run) * sin(PI * w)
		else:
			var w := (u - stance) / (1.0 - stance)
			var e := smoothstep(0.0, 1.0, w)
			var lift := sin(PI * w)
			thigh = -a + 2.0 * a * e + lift * (0.25 + 0.55 * run) * mv  # knee drive
			knee = 0.15 + lift * (0.6 + 1.4 * run) * mv               # heel folds up
			foot = 0.25 * lift - 0.2 * (1.0 - e) * mv                  # toes clear the ground
		q["thigh_" + sd] = _rx(thigh + _land_squash * 0.9 + brake * 0.3)
		q["shin_" + sd] = _rx(-knee - _land_squash * 1.6)
		q["foot_" + sd] = _rx(foot + _land_squash * 0.6)
		# Arms swing against the legs; elbows bend to ~80° when running.
		var asw := -sw * (1.0 if i == 0 else -1.0) * (0.22 + 0.63 * run) * mv - 0.12 * run
		q["upper_arm_" + sd] = _rx(asw) * _rz((0.12 + 0.05 * run) * (1.0 if sd == "r" else -1.0))
		q["forearm_" + sd] = _rx(0.15 + 0.95 * run + 0.15 * mv + maxf(0.0, asw) * 0.35)
	if mv < 0.3:
		# Idle: slow breathing, weight shifting from leg to leg, a glance about.
		var k := 1.0 - mv / 0.3
		var br := sin(_time * 1.5)
		var shift := sin(_time * 0.45)
		q["spine"] = q["spine"].slerp(_rz(shift * 0.035) * _rx(0.02), k)
		q["chest"] = q["chest"].slerp(_rx(br * 0.025) * _rz(-shift * 0.03), k)
		q["head"] = q["head"].slerp(_ry(sin(_time * 0.31) * 0.18) * _rx(0.03 + br * 0.01), k)
		q["thigh_l"] = q["thigh_l"].slerp(_rz(-0.05 - maxf(shift, 0.0) * 0.04) * _rx(0.04), k)
		q["thigh_r"] = q["thigh_r"].slerp(_rz(0.05 - minf(shift, 0.0) * 0.04) * _rx(0.02), k)
		q["shin_l"] = q["shin_l"].slerp(_rx(-0.06 - maxf(-shift, 0.0) * 0.18), k)
		q["shin_r"] = q["shin_r"].slerp(_rx(-0.06 - maxf(shift, 0.0) * 0.18), k)
		q["foot_l"] = q["foot_l"].slerp(Quaternion.IDENTITY, k)
		q["foot_r"] = q["foot_r"].slerp(Quaternion.IDENTITY, k)
		q["upper_arm_l"] = q["upper_arm_l"].slerp(_rz(-0.1 - br * 0.015) * _rx(0.05), k)
		q["upper_arm_r"] = q["upper_arm_r"].slerp(_rz(0.1 + br * 0.015) * _rx(0.05), k)
		q["forearm_l"] = q["forearm_l"].slerp(_rx(0.22), k)
		q["forearm_r"] = q["forearm_r"].slerp(_rx(0.22), k)
	return bob * mv - _land_squash * 0.18


## On the web. The rope arm is solved with two-bone IK so the hand sits on
## the line; under heavy load the free hand joins it. The torso hangs and
## side-bends toward the rope arm, legs stretch out when the line is taut and
## tuck when it goes slack, and lag the body's acceleration.
func _pose_rope(q: Dictionary, dt: float, body: Basis, la: Vector3, twist: float, speed: float) -> void:
	var s := player.s
	var attached := player.line_state == Player.Line.ATTACHED
	var target := s.anchor if attached else player.line_tip
	var L := _load
	q["spine"] = _rx(-0.06 * L + 0.18 * (1.0 - L) * float(attached)) * _ry(twist * 0.5) * _rz(-0.06 * L)
	q["chest"] = _ry(twist * 0.6) * _rz(-0.12 - 0.1 * L) * _rx(-0.05 * L)
	q["neck"] = _rz(0.06 * L)
	q["head"] = _rx(-0.15 - 0.15 * L) * _ry(-twist * 0.4)  # eyes ahead along the swing
	var chest_basis := body * Basis(_rot["spine"]) * Basis(_rot["chest"])
	var shoulder := (bones["upper_arm_r"] as Node3D).global_position
	var reach := (0.29 + 0.26) * lerpf(0.86, 0.985, L if attached else 0.9)
	var dir := (target - shoulder).normalized()
	var ik_r := _two_bone(chest_basis, dir, reach, Vector3(0.75, -0.2, 0.6))
	q["upper_arm_r"] = ik_r[0]
	q["forearm_r"] = ik_r[1]
	# Free arm: counterbalance, or a second hand on the line under heavy load.
	_lgrip = move_toward(_lgrip, 1.0 if attached and L > 0.75 else 0.0, dt * (3.0 if L > 0.75 else 2.0))
	var bal_up := _rz(-0.55 - (1.0 - L) * 0.35) * _rx(clampf(-la.z * 0.025, -0.9, 0.9) + 0.2)
	var bal_fore := _rx(0.7 + (1.0 - L) * 0.3)
	if _lgrip > 0.01:
		var sh_l := (bones["upper_arm_l"] as Node3D).global_position
		var hand_r := shoulder + dir * reach
		var grip := hand_r - dir * 0.11  # just below the web hand
		var dl := grip - sh_l
		var ik_l := _two_bone(chest_basis, dl.normalized(), minf(dl.length(), 0.54), Vector3(-0.75, -0.2, 0.6))
		q["upper_arm_l"] = bal_up.slerp(ik_l[0], _lgrip)
		q["forearm_l"] = bal_fore.slerp(ik_l[1], _lgrip)
	else:
		q["upper_arm_l"] = bal_up
		q["forearm_l"] = bal_fore
	# Legs: stretched along the line when taut, tucked when slack; they lag
	# the body's acceleration (inertia) and trail at speed.
	var trail := clampf(speed / 40.0, 0.0, 1.0)
	var lead := clampf(-la.z * 0.016, -0.6, 0.6)
	var slack := 1.0 - L
	var knee := 0.32 + slack * 0.8 + clampf(la.length() * 0.004, 0.0, 0.25)
	var drift := sin(_time * 1.7) * 0.06  # a little life in the legs
	q["thigh_l"] = _rx(0.3 + slack * 0.7 - trail * 0.3 + lead + drift) * _rz(-0.08)
	q["thigh_r"] = _rx(-0.1 + slack * 0.45 - trail * 0.4 + lead * 0.85 - drift) * _rz(0.06)
	q["shin_l"] = _rx(-knee - 0.35 - 0.2 * slack)
	q["shin_r"] = _rx(-knee * 0.6)
	q["foot_l"] = _rx(0.35 * L + 0.1)
	q["foot_r"] = _rx(0.3 * L + 0.05)


## Two-bone arm IK in the chest frame. `dir` (world) points from the shoulder
## to the target, `dist` is how far away it is; `pole` (chest-local) is where
## the elbow points. Returns [upper_arm quat, forearm quat] (parent-local).
func _two_bone(chest_basis: Basis, dir: Vector3, dist: float, pole: Vector3) -> Array:
	var a := 0.29
	var b := 0.26
	var c := clampf(dist, 0.08, a + b - 0.002)
	var d := (chest_basis.inverse() * dir).normalized()
	var p := (pole - d * pole.dot(d))
	if p.length_squared() < 1e-6:
		p = Vector3.BACK - d * d.z
	p = p.normalized()
	var alpha := acos(clampf((a * a + c * c - b * b) / (2.0 * a * c), -1.0, 1.0))
	var u := (d * cos(alpha) + p * sin(alpha)).normalized()  # shoulder → elbow
	var elbow := u * a
	var w := (d * c - elbow).normalized()                     # elbow → hand
	# Upper-arm frame: bone along -Y, forearm bends toward its -Z (see _rx).
	var y := -u
	var z := -(w - u * w.dot(u))
	z = z.normalized() if z.length_squared() > 1e-6 else Vector3.BACK
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	var upper := Basis(x, y, z).get_rotation_quaternion()
	var bend := acos(clampf(u.dot(w), -1.0, 1.0))
	return [upper, _rx(bend)]


## Ballistic flight. Rising: the lead knee drives up and the other leg
## trails, arms open forward/back for balance. Apex: both knees gather.
## Falling: legs bend and reach for the ground, arms rise and windmill a
## little when dropping fast. Fast steep descents streamline head-first.
func _pose_air(q: Dictionary, v: Vector3, speed: float, la: Vector3, dive: float, twist: float) -> void:
	var rising := clampf(v.y / 10.0, 0.0, 1.0)
	var falling := clampf(-v.y / 14.0, 0.0, 1.0) * (1.0 - dive)
	var apex := 1.0 - clampf(absf(v.y) / 5.0, 0.0, 1.0)
	var fast := clampf((-v.y - 12.0) / 14.0, 0.0, 1.0) * (1.0 - dive)
	var wm := sin(_time * 6.0) * fast * 0.45  # windmill when dropping hard
	if dive > 0.0:
		q["upper_arm_l"] = _rz(-0.25) * _rx(-0.45 * dive)
		q["upper_arm_r"] = _rz(0.25) * _rx(-0.45 * dive)
		q["forearm_l"] = _rx(0.15)
		q["forearm_r"] = _rx(0.15)
		q["thigh_l"] = _rx(0.05)
		q["thigh_r"] = _rx(-0.15)
		q["shin_l"] = _rx(-0.25)
		q["shin_r"] = _rx(-0.45)
		q["head"] = _rx(-0.5 * dive)
		return
	# Legs.
	var lead_t := 0.45 + 1.0 * rising + 0.55 * apex + 0.3 * falling
	var lead_s := -0.55 - 0.8 * rising - 0.5 * apex - 0.35 * falling
	var trail_t := -0.4 * rising + 0.35 * apex + 0.15 * falling
	var trail_s := -0.5 - 0.2 * rising - 0.45 * apex - 0.4 * falling
	q["thigh_l"] = _rx(lead_t + wm * 0.3) * _rz(-0.08)
	q["shin_l"] = _rx(lead_s)
	q["thigh_r"] = _rx(trail_t - wm * 0.3) * _rz(0.06)
	q["shin_r"] = _rx(trail_s)
	q["foot_l"] = _rx(0.25)
	q["foot_r"] = _rx(0.15 + 0.2 * rising)
	# Arms: opposite to the legs while rising, out and up while falling.
	var react := clampf(la.z * 0.02, -0.4, 0.4)
	q["upper_arm_l"] = _rz(-0.35 - 0.75 * falling - wm) * _rx(-0.45 * rising + 0.35 * apex + 0.5 * falling + react)
	q["upper_arm_r"] = _rz(0.35 + 0.75 * falling + wm) * _rx(0.75 * rising + 0.35 * apex + 0.6 * falling + react)
	q["forearm_l"] = _rx(0.5 + 0.2 * apex)
	q["forearm_r"] = _rx(0.6 + 0.3 * rising)
	q["spine"] = _rx(0.12 * apex + 0.08 * falling - 0.08 * rising) * _ry(twist * 0.3)
	q["chest"] = _ry(-0.15 * rising)
	q["head"] = _rx(clampf(-v.y * 0.015, -0.3, 0.35))


## Running up a facade after a head-on hit: quick high-knee steps against the
## wall, arms reaching up alternately.
func _pose_wall_run(q: Dictionary, dt: float) -> void:
	_run_phase += dt * 15.0
	var ph := _run_phase
	q["spine"] = _rx(0.15)
	q["chest"] = _rx(0.05)
	q["head"] = _rx(-0.35)  # looking up the wall
	for i in 2:
		var sd := "l" if i == 0 else "r"
		var s := sin(ph + PI * i)
		q["thigh_" + sd] = _rx(0.9 + s * 0.55)
		q["shin_" + sd] = _rx(-1.0 - maxf(0.0, s) * 0.8)
		q["foot_" + sd] = _rx(-0.3)
		q["upper_arm_" + sd] = _rx(2.2 - s * 0.6) * _rz(0.25 if sd == "r" else -0.25)
		q["forearm_" + sd] = _rx(0.4 + maxf(0.0, -s) * 0.5)


## Getting up after a crash: hands and knees → crouch → stand (k: 1 → 0).
func _pose_getup(q: Dictionary, k: float) -> void:
	var low := clampf((k - 0.35) / 0.65, 0.0, 1.0)  # first part: on the ground
	var crouch := clampf(k / 0.35, 0.0, 1.0) if k < 0.35 else 1.0
	q["spine"] = _rx(0.35 * crouch + 0.5 * low)
	q["chest"] = _rx(0.15 * crouch + 0.2 * low)
	q["head"] = _rx(-0.3 * low)
	for sd in ["l", "r"]:
		var side := 1.0 if sd == "r" else -1.0
		q["thigh_" + sd] = _rx(1.2 * crouch + 0.5 * low + (0.25 if sd == "l" else 0.0) * crouch)
		q["shin_" + sd] = _rx(-1.7 * crouch - 0.5 * low)
		q["foot_" + sd] = _rx(0.5 * crouch)
		q["upper_arm_" + sd] = _rx(0.7 * crouch + 0.4 * low) * _rz(0.15 * side)
		q["forearm_" + sd] = _rx(0.3 + 0.3 * low)


func _drive_springs(q: Dictionary, dt: float, rope_arm: bool) -> void:
	# Locomotion cycles run faster than the soft "inertia" springs can follow
	# (a sprint is ~16 rad/s): attenuated, lagging limbs make feet skate. So on
	# the ground limbs follow the cycle exactly (blended in by _loco, which
	# ramps over ~0.17 s), while in the air they stay soft and carry momentum.
	# The web arm is near-rigid so its hand stays on the line.
	var h := dt * 0.5  # two substeps keeps stiff springs stable at 30 fps
	for b in BONES:
		var grp := _group(b)
		if rope_arm and (b == "upper_arm_r" or b == "forearm_r"):
			grp = "rope_arm"
		var k: float = SPRINGS[grp][0]
		var c: float = SPRINGS[grp][1]
		var n := 2 if k < 500.0 else 4
		for i in n:
			_spring(b, q[b], k, c, dt / n)
		if _loco > 0.0 and (grp == "leg" or grp == "arm"):
			var prev: Quaternion = _rot[b]
			_rot[b] = prev.slerp(q[b], _loco)
			# Keep the spring's velocity consistent with the motion it follows.
			_angvel[b] = (_angvel[b] as Vector3).lerp(_ang_delta(prev, _rot[b]) / maxf(dt, 1e-4), _loco)
		(bones[b] as Node3D).quaternion = _rot[b]


static func _ang_delta(a: Quaternion, b: Quaternion) -> Vector3:
	var d := b * a.inverse()
	if d.w < 0.0:
		d = -d
	var ang := d.get_angle()
	return d.get_axis() * ang if ang > 1e-5 else Vector3.ZERO


func _spring(b: String, target: Quaternion, k: float, c: float, dt: float) -> void:
	var cur: Quaternion = _rot[b]
	var dq := target * cur.inverse()
	if dq.w < 0.0:
		dq = -dq
	var angle := dq.get_angle()
	var err := dq.get_axis() * angle if angle > 1e-5 else Vector3.ZERO
	var w: Vector3 = _angvel[b]
	w += (err * k - w * c) * dt
	w = w.limit_length(30.0)
	if w.length() > 1e-6:
		cur = Quaternion(w.normalized(), w.length() * dt) * cur
	_rot[b] = cur.normalized()
	_angvel[b] = w


static func _group(b: String) -> String:
	if b in ["hips", "spine", "chest", "neck"]:
		return "core"
	if b == "head":
		return "head"
	if b.contains("arm") or b.contains("hand"):
		return "arm"
	return "leg"


# ------------------------------------------------------------------ ragdoll
func _update_ragdoll(dt: float) -> void:
	_rag_time += dt
	var anchor := player.global_position + Vector3(0, 0.08, 0)
	var hanging := player.line_state == Player.Line.ATTACHED
	ragdoll.hand_pin = player.hand_position() if hanging else Vector3.INF
	ragdoll.update(dt, anchor)
	_pose_from_ragdoll()


## Player decided the body has recovered: springs carry it back to a pose.
func _on_stun_ended() -> void:
	ragdolling = false
	_getup_t = GETUP_TIME if player.is_on_floor() else 0.0
	_flip = 0.0
	_flip_rate = 0.0
	_body_basis = global_basis.orthonormalized()


func _pose_from_ragdoll() -> void:
	var p: Dictionary = ragdoll.pos
	var pelvis: Vector3 = p["pelvis"]
	var up: Vector3 = ((p["neck"] as Vector3) - pelvis).normalized()
	var right: Vector3 = (p["sh_r"] as Vector3) - (p["sh_l"] as Vector3)
	right = (right - up * right.dot(up)).normalized()
	if right.length_squared() < 0.5:
		right = global_basis.x
	var basis := Basis(right, up, right.cross(up)).orthonormalized()
	global_basis = basis
	global_position = pelvis - basis * (BONES["hips"][1] - Vector3(0, 0.9, 0))
	for b in ["hips", "spine", "chest", "neck"]:
		_rot[b] = Quaternion.IDENTITY
		_angvel[b] = Vector3.ZERO
		(bones[b] as Node3D).quaternion = Quaternion.IDENTITY
	_aim_bone("head", basis, (p["head"] as Vector3) - (p["neck"] as Vector3), Vector3.UP)
	for sd in ["l", "r"]:
		var ub := _aim_bone("upper_arm_" + sd, basis, (p["el_" + sd] as Vector3) - (p["sh_" + sd] as Vector3), Vector3.DOWN)
		_aim_bone("forearm_" + sd, ub, (p["wr_" + sd] as Vector3) - (p["el_" + sd] as Vector3), Vector3.DOWN)
		var tb := _aim_bone("thigh_" + sd, basis, (p["kn_" + sd] as Vector3) - (p["hip_" + sd] as Vector3), Vector3.DOWN)
		_aim_bone("shin_" + sd, tb, (p["an_" + sd] as Vector3) - (p["kn_" + sd] as Vector3), Vector3.DOWN)


## Rotates `b` so its rest axis points along world `dir`; returns its world basis.
func _aim_bone(b: String, parent_basis: Basis, dir: Vector3, rest_axis: Vector3) -> Basis:
	if dir.length_squared() < 1e-6:
		return parent_basis
	var local := (parent_basis.inverse() * dir).normalized()
	var qq := Quaternion(rest_axis, local)
	_rot[b] = qq
	_angvel[b] = Vector3.ZERO
	(bones[b] as Node3D).quaternion = qq
	return parent_basis * Basis(qq)


# -------------------------------------------------------------------- scarf
func _reset_scarf() -> void:
	_scarf_pts.clear()
	_scarf_prev.clear()


func _update_scarf(dt: float) -> void:
	if _scarf.is_empty():
		return
	var neck := bones["neck"] as Node3D
	var root := neck.global_position + neck.global_basis * Vector3(0, 0.02, 0.08)  # tail ties at the back (+Z = behind)
	if _scarf_pts.size() != 4:
		_scarf_pts.clear()
		_scarf_prev.clear()
		for i in 4:
			var p := root + Vector3.DOWN * SCARF_LEN * i
			_scarf_pts.append(p)
			_scarf_prev.append(p)
	# Airflow pushes the tail back against the direction of travel.
	var wind := -player.s.velocity * 0.9
	var h := minf(dt, 1.0 / 30.0)
	_scarf_pts[0] = root
	_scarf_prev[0] = root
	for i in range(1, 4):
		var p := _scarf_pts[i]
		var vel := (p - _scarf_prev[i]) * 0.9
		_scarf_prev[i] = p
		_scarf_pts[i] = p + vel + (Vector3(0, -9.0, 0) + wind) * h * h
	for it in 3:
		for i in range(1, 4):
			var a := _scarf_pts[i - 1]
			var d := _scarf_pts[i] - a
			if d.length() > 1e-5:
				_scarf_pts[i] = a + d.normalized() * SCARF_LEN
	for i in 3:
		var seg := _scarf[i]
		var a := _scarf_pts[i]
		var dir := (_scarf_pts[i + 1] - a).normalized()
		var side := neck.global_basis.x
		var z := side.cross(-dir).normalized()
		if z.length_squared() < 0.01:
			z = Vector3.FORWARD
		var y := -dir
		seg.global_transform = Transform3D(Basis(y.cross(z).normalized(), y, z).orthonormalized(), a)


static func _rx(a: float) -> Quaternion:
	return Quaternion(Vector3.RIGHT, a)


static func _ry(a: float) -> Quaternion:
	return Quaternion(Vector3.UP, a)


static func _rz(a: float) -> Quaternion:
	return Quaternion(Vector3.BACK, a)
