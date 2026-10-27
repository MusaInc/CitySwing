class_name CharacterRig
extends Node3D
## Articulated, physics-driven character. Every joint is posed each frame from
## the simulation – rope direction, rope tension, velocity, acceleration, ground
## contact – so the body hangs, tucks, reaches and flails because of the motion,
## never from a pre-baked clip. Limb meshes come from assets/models/character.glb
## (Blender-generated; one object per bone, origin at the joint, pointing -Y);
## capsules are used if the asset is missing.

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

var player: Player
var bones := {}
var _body_basis := Basis()
var _facing := Vector3.FORWARD
var _prev_vel := Vector3.ZERO
var _accel := Vector3.ZERO
var _run_phase := 0.0
var _land_squash := 0.0
var _tuck := 0.0
var _flail := 0.0
var _time := 0.0
var _rot := {}  # bone -> current Quaternion (smoothed)


func _ready() -> void:
	var parts := _load_parts()
	for name in BONES:
		var def: Array = BONES[name]
		var pivot := Node3D.new()
		pivot.name = name
		var parent: Node3D = self if def[0] == "" else bones[def[0]]
		parent.add_child(pivot)
		pivot.position = def[1] - Vector3(0, 0.9, 0) * float(def[0] == "")
		bones[name] = pivot
		_rot[name] = Quaternion.IDENTITY
		var part: Node3D = parts.get(name)
		if part:
			part.transform = Transform3D.IDENTITY
			pivot.add_child(part)
		elif parts.is_empty():
			_add_fallback_mesh(name, pivot, def[2])


func _load_parts() -> Dictionary:
	var out := {}
	if not ResourceLoader.exists(MODEL_PATH):
		return out
	var scene: PackedScene = load(MODEL_PATH)
	var inst := scene.instantiate()
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var key := String(child.name).to_lower()
		if BONES.has(key):
			child.get_parent().remove_child(child)
			child.owner = null
			out[key] = child
	inst.free()
	return out


func _add_fallback_mesh(name: String, pivot: Node3D, length: float) -> void:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.25, 0.3)
	if name == "head":
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.26
		mi.mesh = sm
		mi.position.y = 0.1
		mat.albedo_color = Color(0.85, 0.66, 0.52)
	elif name in ["spine", "chest", "hips"]:
		var bm := CapsuleMesh.new()
		bm.radius = 0.17 if name != "hips" else 0.15
		bm.height = 0.36 if name == "chest" else 0.3
		mi.mesh = bm
		mi.position.y = 0.12
		mat.albedo_color = Color(0.9, 0.35, 0.2) if name == "chest" else Color(0.18, 0.2, 0.26)
	elif length > 0.0:
		var cm := CapsuleMesh.new()
		cm.radius = 0.06 if name.contains("arm") else 0.08
		cm.height = length + cm.radius
		mi.mesh = cm
		mi.position.y = -length * 0.5
		mat.albedo_color = Color(0.9, 0.35, 0.2) if name.contains("arm") else Color(0.18, 0.2, 0.26)
	else:
		return
	mi.material_override = mat
	pivot.add_child(mi)


func _process(dt: float) -> void:
	if player == null:
		return
	_time += dt
	var s := player.s
	var v := s.velocity
	var acc := (v - _prev_vel) / maxf(dt, 0.001)
	_prev_vel = v
	_accel = _accel.lerp(acc, 1.0 - exp(-8.0 * dt))
	var vh := Vector3(v.x, 0.0, v.z)
	var grounded := player.is_on_floor() and not s.attached

	# --- Whole-body orientation -------------------------------------------
	if vh.length() > 0.8:
		_facing = _facing.slerp(vh.normalized(), 1.0 - exp(-6.0 * dt)).normalized()
	elif player.controls.move.length() > 0.1:
		_facing = _facing.slerp(player.controls.move.normalized(), 1.0 - exp(-8.0 * dt)).normalized()
	var up := Vector3.UP
	if player.line_state == Player.Line.ATTACHED and s.taut:
		# Hang along the rope: the line of force runs through the body.
		up = (s.anchor - player.global_position).normalized().lerp(Vector3.UP, 0.25).normalized()
	elif not grounded:
		# Free flight: lean into the direction of travel, more at speed.
		var lean := clampf(v.length() / 40.0, 0.0, 0.55)
		up = Vector3.UP.lerp(v.normalized() if v.length() > 1.0 else Vector3.UP, lean).normalized()
	var fwd := (_facing - up * _facing.dot(up)).normalized()
	if fwd.length_squared() < 0.01:
		fwd = Vector3.FORWARD
	var want := Basis.looking_at(fwd, up)
	_body_basis = _body_basis.slerp(want.orthonormalized(), 1.0 - exp(-10.0 * dt)).orthonormalized()
	global_basis = _body_basis
	var to_local := _body_basis.inverse()

	# --- Limb drives -------------------------------------------------------
	var speed := v.length()
	var local_acc := to_local * _accel
	_tuck = lerpf(_tuck, clampf(s.tension / 60.0, 0.0, 1.0) if s.attached else 0.0, 1.0 - exp(-5.0 * dt))
	var falling := not grounded and not s.attached and v.y < -8.0
	_flail = lerpf(_flail, clampf((-v.y - 8.0) / 20.0, 0.0, 1.0) if falling else 0.0, 1.0 - exp(-3.0 * dt))
	_land_squash = move_toward(_land_squash, 0.0, dt * 3.0)

	var q := {}
	for b in BONES:
		q[b] = Quaternion.IDENTITY

	if grounded:
		var hs := vh.length()
		_run_phase += dt * (2.0 + hs * 0.85)
		var stride := clampf(hs / 11.0, 0.0, 1.0)
		var sw := sin(_run_phase) * 0.9 * stride
		q["thigh_l"] = _rx(sw)
		q["thigh_r"] = _rx(-sw)
		q["shin_l"] = _rx(-maxf(0.0, -cos(_run_phase)) * 1.2 * stride - _land_squash)
		q["shin_r"] = _rx(-maxf(0.0, cos(_run_phase)) * 1.2 * stride - _land_squash)
		q["upper_arm_l"] = _rx(-sw * 0.9) * _rz(-0.15)
		q["upper_arm_r"] = _rx(sw * 0.9) * _rz(0.15)
		q["forearm_l"] = _rx(0.9 * stride + 0.2)
		q["forearm_r"] = _rx(0.9 * stride + 0.2)
		q["spine"] = _rx(0.18 * stride + _land_squash * 0.5)
		q["thigh_l"] = q["thigh_l"] * _rx(_land_squash * 0.8)
		q["thigh_r"] = q["thigh_r"] * _rx(_land_squash * 0.8)
	else:
		var air := clampf(speed / 30.0, 0.0, 1.0)
		if player.line_state == Player.Line.ATTACHED:
			# Rope arm locked toward the anchor; free arm balances against the swing.
			var dir: Vector3 = to_local * (s.anchor - player.hand_position()).normalized()
			q["upper_arm_r"] = Quaternion(Vector3.DOWN, dir.normalized())
			q["forearm_r"] = _rx(0.05)
			q["upper_arm_l"] = _rx(clampf(local_acc.z * 0.03, -0.8, 0.8)) * _rz(-0.5 - _tuck * 0.4)
			q["forearm_l"] = _rx(0.8)
			# Legs tuck under load at the bottom of the arc, extend at the ends.
			var swing_lead := clampf(-local_acc.z * 0.02, -0.6, 0.6)
			q["thigh_l"] = _rx(0.4 + _tuck * 0.9 + swing_lead)
			q["thigh_r"] = _rx(0.1 + _tuck * 0.6 + swing_lead)
			q["shin_l"] = _rx(-0.6 - _tuck * 1.1)
			q["shin_r"] = _rx(-0.3 - _tuck * 0.8)
			q["spine"] = _rx(0.15 * _tuck)
		elif player.line_state == Player.Line.FLYING:
			var dir2: Vector3 = to_local * (player.line_tip - player.hand_position()).normalized()
			q["upper_arm_r"] = Quaternion(Vector3.DOWN, dir2.normalized())
			q["upper_arm_l"] = _rz(-0.7)
			q["thigh_l"] = _rx(0.5)
			q["shin_l"] = _rx(-0.9)
			q["thigh_r"] = _rx(0.1)
			q["shin_r"] = _rx(-0.4)
		else:
			# Ballistic: streamlined at speed, arms out for balance, flail when dropping.
			var spread := 0.9 - air * 0.5 + _flail * 0.6
			var fl := sin(_time * 11.0) * _flail * 0.6
			q["upper_arm_l"] = _rz(-spread - fl) * _rx(-0.3 * air)
			q["upper_arm_r"] = _rz(spread + fl) * _rx(-0.3 * air)
			q["forearm_l"] = _rx(0.4 + fl)
			q["forearm_r"] = _rx(0.4 - fl)
			var rising := clampf(v.y / 10.0, -1.0, 1.0)
			q["thigh_l"] = _rx(0.6 * maxf(rising, 0.0) + 0.15 + fl * 0.5)
			q["thigh_r"] = _rx(0.2 * maxf(rising, 0.0) - 0.1 - fl * 0.5)
			q["shin_l"] = _rx(-0.8 * maxf(rising, 0.0) - 0.3)
			q["shin_r"] = _rx(-0.2 - 0.3 * air)
			q["spine"] = _rx(-0.1 * air)
		q["head"] = _rx(clampf(-v.y * 0.01, -0.3, 0.3))

	var k := 1.0 - exp(-18.0 * dt)
	for b in BONES:
		_rot[b] = (_rot[b] as Quaternion).slerp(q[b], k)
		(bones[b] as Node3D).quaternion = _rot[b]


func on_landed(speed: float) -> void:
	_land_squash = clampf(speed / 25.0, 0.15, 0.9)


static func _rx(a: float) -> Quaternion:
	return Quaternion(Vector3.RIGHT, a)


static func _rz(a: float) -> Quaternion:
	return Quaternion(Vector3.BACK, a)
