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
## Limb meshes come from assets/models/character.glb (one object per bone,
## origin at the joint, pointing -Y).

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
	"core": [190.0, 24.0], "head": [240.0, 28.0], "arm": [120.0, 15.0], "leg": [95.0, 13.0], "rope_arm": [420.0, 40.0],
}
const SCARF_LEN := 0.17

var player: Player
var bones := {}
var launcher: Node3D  # the web hand; RopeVisual starts here
var ragdoll := VerletRagdoll.new()
var ragdolling := false
var _mat: ShaderMaterial

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
var _grips := {}           # "l"/"r" -> [open_node, grip_node]
var _scarf: Array[Node3D] = []
var _scarf_pts: Array[Vector3] = []
var _scarf_prev: Array[Vector3] = []


func _ready() -> void:
	var parts := _load_parts()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/player/shaders/character.gdshader")
	_mat = mat
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
	for i in 3:
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
	ragdoll.exclude = [player.get_rid()]


func _load_parts() -> Dictionary:
	var out := {}
	if not ResourceLoader.exists(MODEL_PATH):
		return out
	var scene: PackedScene = load(MODEL_PATH)
	var inst := scene.instantiate()
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var key := String(child.name).to_lower()
		child.get_parent().remove_child(child)
		child.owner = null
		out[key] = child
	inst.free()
	return out


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
	var speed := v.length()
	var grounded := player.is_on_floor() and not s.attached
	var swinging := player.line_state == Player.Line.ATTACHED and s.taut
	var air := not grounded and not swinging

	# --- facing & turn rate -----------------------------------------------
	if vh.length() > 1.0:
		_facing = _facing.slerp(vh.normalized(), 1.0 - exp(-(5.0 if grounded else 3.5) * dt)).normalized()
	elif grounded and player.controls.move.length() > 0.1:
		_facing = _facing.slerp(player.controls.move.normalized(), 1.0 - exp(-8.0 * dt)).normalized()
	var ang := atan2(_facing.x, _facing.z)
	_yaw_rate = lerpf(_yaw_rate, wrapf(ang - _prev_facing_angle, -PI, PI) / maxf(dt, 0.001), 1.0 - exp(-6.0 * dt))
	_prev_facing_angle = ang

	# --- whole-body orientation -------------------------------------------
	var up := Vector3.UP
	var fwd_hint := _facing
	var dive := 0.0
	if swinging:
		# Hang from the web hand: the line of tension runs up through the body.
		up = (s.anchor - player.global_position).normalized()
		var vt := v - up * v.dot(up)
		if vt.length() > 1.0:
			fwd_hint = vt.normalized()
	elif player.line_state == Player.Line.FLYING:
		up = Vector3.UP.lerp((player.line_tip - player.global_position).normalized(), 0.35).normalized()
	elif air:
		dive = clampf((-v.y - 14.0) / 16.0, 0.0, 1.0) * clampf((speed - 18.0) / 12.0, 0.0, 1.0)
		var lean := clampf(speed / 45.0, 0.0, 0.45)
		up = Vector3.UP.lerp(v.normalized() if speed > 1.0 else Vector3.UP, lean).normalized()
		if dive > 0.0:
			# Fast dive: stretch out head-first along the velocity.
			up = up.slerp(v.normalized(), dive * 0.85).normalized()
			fwd_hint = Vector3.DOWN.slerp(_facing, 0.5).normalized()
	var fwd := (fwd_hint - up * fwd_hint.dot(up)).normalized()
	if fwd.length_squared() < 0.01:
		fwd = (_facing - up * _facing.dot(up)).normalized()
	if fwd.length_squared() < 0.01:
		fwd = Vector3.FORWARD
	var want := Basis.looking_at(fwd, up).orthonormalized()
	var rate := 12.0 if grounded else (8.0 if swinging else 5.0)
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
		# Unwind smoothly to the nearest upright orientation.
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
	var tuck := clampf(s.tension / 55.0, 0.0, 1.0) if swinging else 0.0
	_land_squash = move_toward(_land_squash, 0.0, dt * 2.5)
	var q := {}
	for b in BONES:
		q[b] = Quaternion.IDENTITY
	var twist := clampf(_yaw_rate * 0.12, -0.55, 0.55)

	if _trick_time > 0.0 or _roll_time > 0.0:
		# Tight tuck for flips and landing rolls.
		q["spine"] = _rx(0.5)
		q["chest"] = _rx(0.3)
		q["head"] = _rx(0.4)
		for sd in ["l", "r"]:
			q["thigh_" + sd] = _rx(1.9)
			q["shin_" + sd] = _rx(-2.3)
			q["upper_arm_" + sd] = _rx(1.2) * _rz(0.3 if sd == "r" else -0.3)
			q["forearm_" + sd] = _rx(1.4)
	elif grounded:
		var hs := vh.length()
		_run_phase += dt * (2.0 + hs * 0.85)
		var stride := clampf(hs / 11.0, 0.0, 1.0)
		var sw := sin(_run_phase) * 0.95 * stride
		var lean := 0.12 * stride + _land_squash * 0.4
		q["spine"] = _rx(lean)
		q["chest"] = _ry(-sw * 0.25) * _rx(0.05 * stride)
		q["head"] = _rx(-lean * 0.8)
		q["thigh_l"] = _rx(sw + _land_squash * 0.9)
		q["thigh_r"] = _rx(-sw + _land_squash * 0.9)
		q["shin_l"] = _rx(-maxf(0.0, -cos(_run_phase)) * 1.3 * stride - _land_squash * 1.6 - 0.05)
		q["shin_r"] = _rx(-maxf(0.0, cos(_run_phase)) * 1.3 * stride - _land_squash * 1.6 - 0.05)
		q["foot_l"] = _rx(_land_squash * 0.6)
		q["foot_r"] = _rx(_land_squash * 0.6)
		q["upper_arm_l"] = _rx(-sw * 0.9) * _rz(-0.12 - 0.1 * (1.0 - stride))
		q["upper_arm_r"] = _rx(sw * 0.9) * _rz(0.12 + 0.1 * (1.0 - stride))
		q["forearm_l"] = _rx(0.35 + 1.0 * stride)
		q["forearm_r"] = _rx(0.35 + 1.0 * stride)
		if hs < 0.5:  # idle: weight shift and breathing
			var br := sin(_time * 1.6) * 0.03
			q["chest"] = _rx(br)
			q["thigh_l"] = _rz(-0.04)
			q["thigh_r"] = _rz(0.06)
			q["shin_l"] = _rx(-0.08)
	elif swinging or player.line_state == Player.Line.FLYING:
		var target := s.anchor if swinging else player.line_tip
		# Rope arm: shoulder aims straight up the line (simple IK; the line of
		# force passes through the hand, so the arm is nearly straight).
		var chest_basis := body * Basis(_rot["spine"]) * Basis(_rot["chest"])
		var shoulder := (bones["upper_arm_r"] as Node3D).global_position
		var dir: Vector3 = chest_basis.inverse() * (target - shoulder).normalized()
		q["upper_arm_r"] = Quaternion(Vector3.DOWN, dir.normalized())
		q["forearm_r"] = _rx(0.08 + 0.25 * (1.0 - tuck))
		# Free arm counter-balances against the swing.
		q["upper_arm_l"] = _rz(-0.55 - tuck * 0.35) * _rx(clampf(-la.z * 0.025, -0.9, 0.9) + 0.2)
		q["forearm_l"] = _rx(0.7 + tuck * 0.4)
		# Torso: hangs, twists into turns, curls under load.
		q["spine"] = _rx(0.12 * tuck) * _ry(twist * 0.5)
		q["chest"] = _ry(twist * 0.6) * _rz(-0.12)
		q["head"] = _rx(-0.25 * tuck) * _ry(-twist * 0.4)
		# Legs: trail behind at speed, swing forward through the bottom of the
		# arc (where load peaks), knees bend with changing velocity.
		var trail := clampf(speed / 40.0, 0.0, 1.0)
		var lead := clampf(-la.z * 0.018, -0.7, 0.7)
		var knee := 0.35 + tuck * 0.9 + clampf(la.length() * 0.008, 0.0, 0.5)
		q["thigh_l"] = _rx(0.35 + tuck * 0.8 - trail * 0.45 + lead) * _rz(-0.06)
		q["thigh_r"] = _rx(0.05 + tuck * 0.55 - trail * 0.55 + lead * 0.8) * _rz(0.05)
		q["shin_l"] = _rx(-knee - 0.35)
		q["shin_r"] = _rx(-knee * 0.7)
		q["foot_l"] = _rx(0.3)
		q["foot_r"] = _rx(0.2)
	else:
		var rising := clampf(v.y / 12.0, -1.0, 1.0)
		var flail := clampf((-v.y - 10.0) / 15.0, 0.0, 1.0) * (1.0 - dive)
		var fl := sin(_time * 10.0) * flail * 0.5
		if dive > 0.0:
			# Streamlined: arms swept back along the body, legs long and together.
			var sweep := dive
			q["upper_arm_l"] = _rz(-0.18) * _rx(-0.3 * sweep)
			q["upper_arm_r"] = _rz(0.18) * _rx(-0.3 * sweep)
			q["forearm_l"] = _rx(0.1)
			q["forearm_r"] = _rx(0.1)
			q["thigh_l"] = _rx(-0.08 * sweep)
			q["thigh_r"] = _rx(-0.12 * sweep)
			q["shin_l"] = _rx(-0.15)
			q["shin_r"] = _rx(-0.25)
			q["head"] = _rx(-0.5 * sweep)
		else:
			# Release / ballistic: open up when rising, arms out for balance,
			# limbs reacting to the body's acceleration.
			var spread := 0.95 - clampf(speed / 40.0, 0.0, 0.5) + flail * 0.5
			q["upper_arm_l"] = _rz(-spread - fl) * _rx(-0.35 * maxf(rising, 0.0) + clampf(la.z * 0.02, -0.5, 0.5))
			q["upper_arm_r"] = _rz(spread + fl) * _rx(-0.35 * maxf(rising, 0.0) + clampf(la.z * 0.02, -0.5, 0.5))
			q["forearm_l"] = _rx(0.45 + fl)
			q["forearm_r"] = _rx(0.45 - fl)
			q["thigh_l"] = _rx(0.7 * maxf(rising, 0.0) + 0.2 + fl * 0.6)
			q["thigh_r"] = _rx(0.15 * maxf(rising, 0.0) - 0.15 - fl * 0.6)
			q["shin_l"] = _rx(-1.0 * maxf(rising, 0.0) - 0.45)
			q["shin_r"] = _rx(-0.35 - 0.3 * clampf(speed / 30.0, 0.0, 1.0))
			q["spine"] = _rx(-0.12 * clampf(speed / 30.0, 0.0, 1.0)) * _ry(twist * 0.3)
			q["head"] = _rx(clampf(-v.y * 0.012, -0.35, 0.35))

	_drive_springs(q, dt, swinging or player.line_state == Player.Line.FLYING)


func _drive_springs(q: Dictionary, dt: float, rope_arm: bool) -> void:
	var h := dt * 0.5  # two substeps keeps stiff springs stable at 30 fps
	for b in BONES:
		var grp := _group(b)
		if rope_arm and b == "upper_arm_r":
			grp = "rope_arm"
		var k: float = SPRINGS[grp][0]
		var c: float = SPRINGS[grp][1]
		for i in 2:
			_spring(b, q[b], k, c, h)
		(bones[b] as Node3D).quaternion = _rot[b]


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
	var root := neck.global_position + neck.global_basis * Vector3(0, 0.04, -0.08)
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
