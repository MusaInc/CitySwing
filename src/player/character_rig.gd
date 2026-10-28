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
var _flip := 0.0           # landing-roll angle (rad) about the body's right axis
var _roll_time := 0.0
## Air tricks (visual only). Each: duration, rotations (rad) about the body's
## right (flip, + = backward), up (twist) and forward (cartwheel) axes, and a
## shape the limbs hold through it. Rotation follows an eased curve – slow
## out of the take-off, whipping through the middle, settling upright.
const TRICKS := {
	"front_tuck": {"dur": 0.62, "flip": -TAU, "twist": 0.0, "roll": 0.0, "shape": "tuck"},
	"back_layout": {"dur": 0.85, "flip": TAU, "twist": 0.0, "roll": 0.0, "shape": "layout"},
	"corkscrew": {"dur": 1.0, "flip": -TAU, "twist": TAU, "roll": 0.0, "shape": "twist"},
	"aerial": {"dur": 0.72, "flip": 0.0, "twist": 0.0, "roll": TAU, "shape": "split"},
	"full_twist": {"dur": 0.6, "flip": 0.0, "twist": TAU, "roll": 0.0, "shape": "pencil"},
	"front_pike": {"dur": 0.8, "flip": -TAU, "twist": 0.0, "roll": 0.0, "shape": "pike"},
	"double_front": {"dur": 1.05, "flip": -2.0 * TAU, "twist": 0.0, "roll": 0.0, "shape": "tuck"},
	"double_twist_layout": {"dur": 1.25, "flip": TAU, "twist": 2.0 * TAU, "roll": 0.0, "shape": "twist"},
}
var trick := ""            # current trick ("" = none); read by tests / HUD
var _trick := ""
var _trick_t := 0.0
var _trick_dur := 1.0
var _trick_dir := 1.0      # mirrors twist / cartwheel direction
var _last_trick := ""
var _resid := Quaternion.IDENTITY  # a trick cut short eases out from here
var _ground_h := INF       # height of the capsule bottom above what's below
var _ground_t := 0.0
var _perfect_pending := false
var _last_trick_seen := ""
var tricks_done := 0
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
var _lead := "l"           # leg that was driving forward at take-off (it leads the jump)
var _jump_t := 0.0         # time since leaving the ground on a jump (not a web)
var _release_t := 0.0      # launch stretch after letting go of a web (s left)
const RELEASE_TIME := 0.42
## Foot planting (see _plant_feet).
const ANKLE_H := 0.05      # ankle pivot above the sole
const LEG_LEN := 0.89      # thigh + shin
const BALL := 0.13         # ankle → ball of the foot (toe-off pivot)
var _stance_w := {"l": -1.0, "r": -1.0}  # stance progress 0..1 from the gait, -1 = swing
var _toe := {"l": 0.0, "r": 0.0}         # toe-off roll (rad, heel up)
var _swing_w := {"l": -1.0, "r": -1.0}   # swing progress 0..1, -1 = not swinging
var _standing := false                   # idle: the hips give instead of the heels lifting
var _plant := {}                         # side -> [ankle pos, ground normal] while locked
var _foot_off := {"l": Vector3.ZERO, "r": Vector3.ZERO}  # eases out target jumps
var _foot_last := {}                     # side -> last solved ankle target
var _foot_mode := {}                     # side -> planted ankle pos, or null when free
var _hip_drop := 0.0
var _step_off := 0.0       # visual ease after the capsule steps up a kerb
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
	player.perfect_release.connect(_on_perfect)
	player.stepped_up.connect(func(h: float) -> void: _step_off = minf(_step_off + h, Player.STEP_MAX))
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


## JUMP in the air (or a wall tap): a trick that fits the air time left.
func _on_trick() -> void:
	start_trick()


func _on_released(v: Vector3) -> void:
	_perfect_pending = true  # perfect_release (if any) arrives this tick
	if v.y > -2.0 and v.length() > 8.0:
		# Thrown out of the arc: stretch long, then the stride/gather follows.
		_release_t = RELEASE_TIME
		_jump_t = 0.0


## A perfect release earns a flourish when there is air to do it in.
func _on_perfect(_streak: int) -> void:
	if _air_time_left() > 1.15:
		start_trick()


## Starts a trick chosen for the moment (or `which`). Returns its name.
func start_trick(which := "") -> String:
	if _trick != "" or ragdolling or player.is_on_floor() or player.line_state == Player.Line.ATTACHED:
		return ""
	var left := _air_time_left()
	if which == "":
		which = _choose_trick(left)
	if which == "" or not TRICKS.has(which):
		return ""
	var base: float = TRICKS[which]["dur"]
	# Long air: stretch it a little (slower is more graceful); short: squeeze.
	_trick_dur = clampf(minf(base * 1.25, left - 0.2), base * 0.8, base * 1.25)
	_trick = which
	trick = which
	_trick_t = 0.0
	_trick_dir = -1.0 if randf() < 0.5 else 1.0
	_last_trick = which
	tricks_done += 1
	return which


func _choose_trick(left: float) -> String:
	var v := player.s.velocity
	var right := _body_basis.x
	var lateral := absf(v.dot(right)) / maxf(v.length(), 1.0)
	var weights := {}
	for name in TRICKS:
		var dur: float = TRICKS[name]["dur"]
		if dur * 0.8 > left - 0.2 or name == _last_trick:
			continue
		var w := 1.0
		match name:
			"aerial":
				w = 0.6 + lateral * 4.0
			"front_tuck", "front_pike", "corkscrew":
				w = 1.0 + clampf(v.y / 10.0, 0.0, 1.2)
			"back_layout", "full_twist":
				w = 1.0 + clampf(-v.y / 12.0, 0.0, 1.0)
			"double_front", "double_twist_layout":
				w = 0.4 + 0.6 * float(player.perfect_streak >= 2) + clampf(left - 1.6, 0.0, 1.0)
		weights[name] = w
	var total := 0.0
	for k in weights:
		total += weights[k]
	if total <= 0.0:
		return ""
	var r := randf() * total
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return weights.keys()[-1]


## Seconds until the body would reach the ground below (ballistic estimate).
func _air_time_left() -> float:
	var h := _probe_ground()
	if h == INF:
		return 3.0
	var g := player.params.gravity
	var vy := player.s.velocity.y
	return (vy + sqrt(maxf(vy * vy + 2.0 * g * maxf(h, 0.0), 0.0))) / g


## Height of the capsule's bottom above the surface below (INF: none in 200 m).
func _probe_ground() -> float:
	if not is_inside_tree():
		return INF
	var from := player.global_position
	var rq := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 200.0, player.collision_mask)
	rq.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(rq)
	return INF if hit.is_empty() else from.y - 0.9 - (hit.position as Vector3).y


func _on_stun(speed: float) -> void:
	ragdolling = true
	_rag_time = 0.0
	_trick = ""
	ragdoll.space = get_world_3d().direct_space_state
	if player.knocked_out:
		_knockout_ragdoll(speed)
		return
	var spin := Vector3(randf_range(-3, 3), randf_range(-2, 2), randf_range(-3, 3))
	ragdoll.start(joint_positions(), player.s.velocity * 0.6, spin)


## Wall knockout: the body bounces off the facade, but the limbs still carry
## the speed they had going in, so they slap the wall and fold round; the
## head snaps back off the impact, and the whole body tumbles away from the
## wall, turning about the axis along the facade.
func _knockout_ragdoll(speed: float) -> void:
	var n := player.ko_normal
	var pre := player.ko_velocity
	var joints := joint_positions()
	var extra := {}
	var limb_carry := (pre - player.s.velocity) * 0.55
	for j in ["wr_l", "wr_r", "el_l", "el_r", "an_l", "an_r", "kn_l", "kn_r"]:
		extra[j] = limb_carry * (1.0 if j.begins_with("wr") or j.begins_with("an") else 0.6)
	extra["head"] = n * minf(speed * 0.22, 8.0) + Vector3.UP * 1.5
	extra["neck"] = n * minf(speed * 0.1, 4.0)
	var axis := n.cross(Vector3.UP)
	if axis.length_squared() < 0.01:
		axis = _body_basis.x
	var spin := axis.normalized() * clampf(speed * 0.12, 3.0, 8.0) + Vector3.UP * randf_range(-2.5, 2.5)
	ragdoll.start(joints, player.s.velocity, spin, extra)


func _on_respawned() -> void:
	ragdolling = false
	_flip = 0.0
	_trick = ""
	trick = ""
	_resid = Quaternion.IDENTITY
	_roll_time = 0.0
	for b in BONES:
		_angvel[b] = Vector3.ZERO
	_plant.clear()
	_foot_last.clear()
	_foot_mode.clear()
	_hip_drop = 0.0
	_step_off = 0.0
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


## Compact pose summary for the web debug bridge (browser tests): whether the
## skinned body loaded, how many feet are planted, the worst gap between a
## planted ankle and the ground under it, and how far the web hand is from
## the rope line.
func debug_state() -> Dictionary:
	var gap := 0.0
	if not ragdolling and is_inside_tree():
		var space := get_world_3d().direct_space_state
		for sd in _plant:
			var p := (bones["foot_" + sd] as Node3D).global_position
			var hit := _ground_hit(space, p)
			if not hit.is_empty():
				gap = maxf(gap, absf(p.y - (hit.position as Vector3).y - ANKLE_H))
	var hand_off := -1.0
	if player.line_state == Player.Line.ATTACHED and player.s.taut:
		var sh := (bones["upper_arm_r"] as Node3D).global_position
		var hand := (bones["hand_r"] as Node3D).global_position
		var dir := (player.s.anchor - sh).normalized()
		hand_off = ((hand - sh) - dir * (hand - sh).dot(dir)).length()
	return {"skinned": skeleton != null and not _skel_idx.is_empty(), "planted": _plant.size(),
		"foot_gap": snappedf(gap, 0.001), "hand_line": snappedf(hand_off, 0.001), "ragdoll": ragdolling,
		"trick": _trick if _trick != "" else _last_trick_seen, "tricks": tricks_done, "ko": player.knocked_out}


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
	# Closed hands on the line, and loose fists when running or flying (open
	# flat palms read as waving); open hands when standing.
	var fists := not player.is_on_floor() or player.speed() > 3.5 or ragdolling
	_set_grip("r", player.line_state != Player.Line.IDLE or fists)
	_set_grip("l", (player.line_state == Player.Line.ATTACHED and player.s.tension > 25.0) or fists)


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
	_release_t = maxf(_release_t - dt, 0.0)
	_getup_t = maxf(_getup_t - dt, 0.0)
	if grounded and not _was_grounded:
		_air_t = 0.0
	if not grounded and _was_grounded and v.y > 6.0 and not on_rope:
		_takeoff_t = 0.3  # push-off: legs extend, arms drive up
		_jump_t = 0.0
	_was_grounded = grounded
	if not grounded:
		_air_t += dt
		_jump_t += dt
	var air := not grounded and not on_rope
	_loco = move_toward(_loco, 1.0 if grounded and _getup_t <= 0.0 else 0.0, dt * 6.0)
	for sd in ["l", "r"]:
		_stance_w[sd] = -1.0
		_swing_w[sd] = -1.0

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
		# Runners lean from the ankles, more as they speed up (a straight line
		# ankle–hip–shoulder, not a bend at the waist).
		var run_lean := 0.05 + 0.13 * clampf((hs - 2.0) / 9.0, 0.0, 1.0) if hs > 1.0 else 0.0
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
		# Freefall arch: falling fast with height to spare, the body lies
		# belly-down, head toward the travel direction.
		var sky := _skydive(v, dive)
		if sky > 0.0:
			var ahead := (_facing + Vector3.UP * 0.2).normalized()
			up = up.slerp(ahead, sky * 0.8).normalized()
			fwd_hint = fwd_hint.slerp(Vector3.DOWN, sky * 0.9).normalized()
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
	if _roll_time > 0.0:
		_roll_time -= dt
		_flip -= TAU / 0.55 * dt
	else:
		_flip = lerpf(wrapf(_flip, -PI, PI), 0.0, 1.0 - exp(-10.0 * dt))
	var trick_rot := Quaternion.IDENTITY
	var trick_u := 0.0
	if _trick != "":
		_trick_t += dt
		trick_u = clampf(_trick_t / _trick_dur, 0.0, 1.0)
		trick_rot = _trick_rotation(_trick, trick_u)
		if not air:
			# Caught a web, landed or hit something mid-trick: ease out.
			_resid = (_resid * trick_rot).normalized()
			trick_rot = Quaternion.IDENTITY
			_trick = ""
		elif trick_u >= 1.0:
			_trick = ""  # whole turns: ends exactly upright
	trick = _trick
	if _trick != "":
		_last_trick_seen = _trick  # the bridge samples slowly: keep the last one
	_resid = _resid.slerp(Quaternion.IDENTITY, 1.0 - exp(-9.0 * dt))
	var body := _body_basis * Basis(_resid * trick_rot) * Basis(Vector3.RIGHT, _flip)
	global_basis = body
	_step_off = move_toward(_step_off, 0.0, dt * 2.2) * exp(-8.0 * dt)
	global_position = player.global_position + Vector3.DOWN * _step_off
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

	if _trick != "" and _roll_time <= 0.0:
		_pose_air(q, v, speed, la, dive, twist)
		_pose_trick(q, _trick, trick_u)
	elif _roll_time > 0.0:
		# Tight tuck for landing rolls.
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
	if _release_t > 0.0 and air and _trick == "":
		# Release: the whole body extends along the throw – arms reaching
		# overhead, chest open, legs long and together, toes pointed – then
		# lets the rising stride and the apex gather take over.
		var r := smoothstep(0.0, 1.0, _release_t / RELEASE_TIME)
		_put(q, {
			"spine": _rx(-0.22), "chest": _rx(-0.16), "neck": _rx(-0.08), "head": _rx(-0.22),
			"upper_arm_r": _rx(2.75) * _rz(0.22), "upper_arm_l": _rx(2.55) * _rz(-0.32),
			"forearm_r": _rx(0.2), "forearm_l": _rx(0.35),
			"thigh_l": _rx(-0.18) * _rz(-0.03), "thigh_r": _rx(-0.06) * _rz(0.03),
			"shin_l": _rx(-0.2), "shin_r": _rx(-0.35), "foot_l": _rx(-0.65), "foot_r": _rx(-0.6),
		}, r)
	if _takeoff_t > 0.0 and air:
		# Push-off: the lead knee drives up, the take-off leg extends behind
		# with the toes pointed, the opposite arm punches up – a running
		# jump, not a hop. Blends out over 0.3 s into the airborne poses.
		var k := smoothstep(0.0, 1.0, _takeoff_t / 0.3)
		var lead := _lead
		var trail := "r" if lead == "l" else "l"
		var sgn := {"l": -1.0, "r": 1.0}
		_put(q, {
			"spine": _rx(-0.06), "chest": _rx(-0.08), "head": _rx(-0.12),
			"thigh_" + lead: _rx(1.3) * _rz(0.04 * sgn[lead]), "shin_" + lead: _rx(-1.35),
			"foot_" + lead: _rx(0.1),
			"thigh_" + trail: _rx(-0.42) * _rz(0.03 * sgn[trail]), "shin_" + trail: _rx(-0.3),
			"foot_" + trail: _rx(-0.65),
			# Opposite arm to the lead knee goes high, the other drives back.
			"upper_arm_" + trail: _rx(2.1) * _rz(0.25 * sgn[trail]), "forearm_" + trail: _rx(0.75),
			"upper_arm_" + lead: _rx(-0.55) * _rz(0.3 * sgn[lead]), "forearm_" + lead: _rx(0.95),
		}, k)
	# Hip bob (running) – the pelvis rides up and down over the stance leg.
	(bones["hips"] as Node3D).position.y = lerpf((bones["hips"] as Node3D).position.y,
		(BONES["hips"][1] as Vector3).y - 0.9 + bob - _hip_drop, 1.0 - exp(-20.0 * dt))

	_drive_springs(q, dt, on_rope)
	if air:
		_ground_t -= dt
		if _ground_t <= 0.0:
			_ground_t = 0.1
			_ground_h = _probe_ground()
	else:
		_ground_h = INF
	if _loco > 0.0 and grounded and not wall_run and _getup_t <= 0.0:
		_plant_feet(dt)
	else:
		_plant.clear()
		_foot_last.clear()
		_foot_mode.clear()
		_hip_drop = move_toward(_hip_drop, 0.0, dt * 1.5)


const GETUP_TIME := 0.75


## Ground: idle → walk → sprint. Each leg alternates a stance phase, in
## which the thigh sweeps back at exactly the ground speed so the foot stays
## planted (sole held flat, toe-off at the end), and a swing phase that drives
## the knee forward and folds the heel up. Stance is ~60% of a walking cycle and
## ~28% of a sprint (longer flight). The cycle advances with distance.
func _pose_ground(q: Dictionary, dt: float, hs: float, la: Vector3) -> float:
	var stride_len := clampf(0.45 + hs * 0.15, 0.5, 2.1)  # metres per step
	_run_phase += dt * hs * PI / stride_len
	var run := clampf((hs - 1.8) / 5.0, 0.0, 1.0)  # 0 walk … 1 run
	var mv := clampf(hs / 1.2, 0.0, 1.0)            # 0 standing … 1 moving
	var stance := lerpf(0.58, 0.24, run)
	var leg := 0.86
	# Half the hip→ankle sweep covered while the foot is planted.
	var period := TAU / maxf(hs * PI / stride_len, 0.01)
	var a := clampf(hs * stance * period / (2.0 * leg), 0.0, 0.75) * mv
	var brake := clampf(la.z * 0.03, 0.0, 0.5)
	var lean := 0.16 * run + _land_squash * 0.45 - brake * 0.25
	var ph := _run_phase
	var sw := sin(ph)
	# Pelvis turns with the swinging leg, shoulders counter it, the head
	# stays steady and level (it counters the whole-body lean too).
	q["hips"] = _ry(sw * 0.1 * mv)
	q["spine"] = _rx(lean) * _ry(-sw * 0.1 * mv)
	q["chest"] = _ry(-sw * 0.2 * mv) * _rx(0.06 * run)
	q["neck"] = _ry(sw * 0.12 * mv)
	q["head"] = _rx(-lean * 0.7 - 0.12 * run + 0.04)
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
			foot = -thigh + knee                         # sole parallel to the ground
			_toe[sd] = smoothstep(0.7, 1.0, w) * (0.5 + 0.25 * run) * mv  # toe-off: heel rolls up
			foot -= _toe[sd]
			_stance_w[sd] = w
			bob -= (0.025 + 0.02 * run) * sin(PI * w)
		else:
			var w := (u - stance) / (1.0 - stance)
			var e := smoothstep(0.0, 1.0, w)
			_toe[sd] = 0.0
			_swing_w[sd] = w * mv
			if w > 0.15 and w < 0.85:
				_lead = sd  # the knee coming through leads if we jump now
			var lift := sin(PI * w)
			# Back → front, leaving and arriving at the stance sweep rate, so the
			# foot is already moving back under the body when it touches down.
			var m := -2.0 * a / stance * (1.0 - stance)
			var w2 := w * w
			var w3 := w2 * w
			thigh = -a * (2.0 * w3 - 3.0 * w2 + 1.0) + m * (w3 - 2.0 * w2 + w) \
				+ a * (-2.0 * w3 + 3.0 * w2) + m * (w3 - w2)
			thigh += lift * (0.25 + 0.55 * run) * mv  # knee drive
			knee = 0.15 + lift * (0.6 + 1.4 * run) * mv               # heel folds up
			foot = 0.25 * lift - 0.2 * (1.0 - e) * mv                  # toes clear the ground
		q["thigh_" + sd] = _rx(thigh + _land_squash * 0.9 + brake * 0.3)
		q["shin_" + sd] = _rx(-knee - _land_squash * 1.6)
		q["foot_" + sd] = _rx(foot + _land_squash * 0.6)
		# Arms swing against the legs from the shoulder; the elbow holds near
		# 90° through the stride (closing a little on the forward swing), so
		# the hands travel hip → chin rather than flailing up to the face.
		# Driven from the shoulder, further back than forward at speed; the
		# elbow opens a little on the back swing and closes coming through.
		var asw := -sw * (1.0 if i == 0 else -1.0) * (0.25 + 0.62 * run) * mv - 0.18 * run
		q["upper_arm_" + sd] = _rx(asw) * _rz((0.12 + 0.05 * run) * (1.0 if sd == "r" else -1.0))
		q["forearm_" + sd] = _rx(0.3 + 1.0 * run + 0.15 * mv + asw * 0.35)
		if _land_squash > 0.01:
			# Landing: arms come forward to balance the folding hips.
			var ls := clampf(_land_squash * 1.6, 0.0, 1.0)
			q["upper_arm_" + sd] = q["upper_arm_" + sd].slerp(_rx(0.85) * _rz(0.4 * (1.0 if sd == "r" else -1.0)), ls)
			q["forearm_" + sd] = q["forearm_" + sd].slerp(_rx(0.7), ls)
	_standing = false
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
		_standing = k > 0.5
		if _standing:  # both feet stay where they are
			for sd in ["l", "r"]:
				_stance_w[sd] = 0.5
				_toe[sd] = 0.0
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
	if attached:
		# The swing has a rhythm: on the way down the body opens and the legs
		# trail, through the bottom they whip under, and on the way up the
		# knees drive forward and up into the release (a gymnast's kip).
		var vy := s.velocity.y
		var down := clampf(-vy / 9.0, 0.0, 1.0) * clampf(L * 1.4, 0.0, 1.0)
		var up := clampf(vy / 9.0, 0.0, 1.0) * clampf(L * 1.4, 0.0, 1.0)
		_put(q, {
			"thigh_l": _rx(-0.32) * _rz(-0.06), "thigh_r": _rx(-0.12) * _rz(0.05),
			"shin_l": _rx(-0.45), "shin_r": _rx(-0.22), "foot_l": _rx(-0.45), "foot_r": _rx(-0.5),
		}, down * 0.85)
		_put(q, {
			"thigh_l": _rx(1.05) * _rz(-0.08), "thigh_r": _rx(0.7) * _rz(0.06),
			"shin_l": _rx(-1.05), "shin_r": _rx(-0.6), "foot_l": _rx(-0.2), "foot_r": _rx(-0.3),
		}, up * 0.9)
		q["spine"] = q["spine"] * _rx(-0.14 * down + 0.16 * up)
		q["head"] = q["head"] * _rx(-0.1 * up)


## Two-bone IK in the parent's frame (chest for arms, hips for legs). `dir`
## (world) points from the root joint to the target, `dist` is how far away it
## is; `pole` (parent-local) is where the middle joint points. Elbows bend the
## lower bone toward its -Z (bend = 1), knees toward +Z (bend = -1).
## Returns [upper quat, lower quat] (parent-local).
func _two_bone(chest_basis: Basis, dir: Vector3, dist: float, pole: Vector3,
		a := 0.29, b := 0.26, bend_dir := 1.0) -> Array:
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
	var z := -bend_dir * (w - u * w.dot(u))
	z = z.normalized() if z.length_squared() > 1e-6 else Vector3.BACK
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	var upper := Basis(x, y, z).get_rotation_quaternion()
	var bend := acos(clampf(u.dot(w), -1.0, 1.0))
	return [upper, _rx(bend * bend_dir)]


## Ground contact. A foot entering stance is locked where it touches the
## ground (raycast, so kerbs, steps and slopes work) and the leg is solved
## onto it with two-bone IK until the gait lifts it, the body outruns the
## leg, or it drifts too far from where the gait wants it. Toe-off rolls the
## heel up over the ball of the foot. Swing feet are kept above the ground,
## and the hips drop when a planted foot is out of reach (stepping down).
## Any jump in a foot's target is eased out, so lock and release never pop.
func _plant_feet(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	var hips := bones["hips"] as Node3D
	var targets := {}
	var normals := {}
	var drop := -1.0
	for sd in ["l", "r"]:
		var foot := bones["foot_" + sd] as Node3D
		var fk := foot.global_position
		var hip := (bones["thigh_" + sd] as Node3D).global_position
		var w: float = _stance_w[sd]
		var hit := _ground_hit(space, fk)
		var desired := fk
		var n := Vector3.UP
		if w >= 0.0 and _plant.has(sd):
			var lp: Vector3 = _plant[sd][0]
			var horiz := Vector3(lp.x - fk.x, 0.0, lp.z - fk.z).length()
			if horiz > 0.35 or lp.distance_to(hip) > LEG_LEN + 0.25:
				_plant.erase(sd)  # outran the foot: let it go and re-plant
		if w >= 0.0 and not hit.is_empty():
			if not _plant.has(sd):
				_plant[sd] = [Vector3(fk.x, (hit.position as Vector3).y + ANKLE_H, fk.z), hit.normal]
			var lock: Vector3 = _plant[sd][0]
			n = _plant[sd][1]
			# The heel rolls up about the ball of the foot: for toe-off, and
			# whenever a flat foot would be out of the leg's reach (long
			# running contacts are on the forefoot).
			var f := (_facing - n * _facing.dot(n)).normalized()
			var toe: float = _toe[sd]
			desired = _roll(lock, f, n, toe)
			while not _standing and toe < 1.1 and desired.distance_to(hip) > LEG_LEN - 0.01:
				toe += 0.06
				desired = _roll(lock, f, n, toe)
			_toe[sd] = toe
		else:
			_plant.erase(sd)
			if not hit.is_empty():
				var gy: float = (hit.position as Vector3).y + ANKLE_H
				# Reach down for the ground before contact (a forward-swung leg
				# holds the ankle high), so the lock lands where the foot is.
				desired.y = lerpf(desired.y, gy, smoothstep(0.75, 1.0, _swing_w[sd]))
				desired.y = maxf(desired.y, gy)
				n = hit.normal
		var mode = _plant[sd][0] if _plant.has(sd) else null
		if _foot_last.has(sd) and mode != _foot_mode.get(sd):
			# Locked, released or re-planted: blend the jump away.
			var jump: Vector3 = (_foot_last[sd] as Vector3) - desired
			_foot_off[sd] = jump if jump.length() < 0.6 else Vector3.ZERO
		_foot_mode[sd] = mode
		var fo: Vector3 = _foot_off[sd] * exp(-14.0 * dt)
		if _plant.has(sd):
			fo.y *= exp(-24.0 * dt)  # a planted foot settles onto the ground quickly
		_foot_off[sd] = fo
		var tgt: Vector3 = desired + _foot_off[sd]
		targets[sd] = tgt
		normals[sd] = n
		if _plant.has(sd):
			drop = maxf(drop, desired.distance_to(hip) - (LEG_LEN - 0.005))
	_hip_drop = lerpf(_hip_drop, clampf(_hip_drop + drop, 0.0, 0.3), 1.0 - exp(-20.0 * dt))
	var hb := hips.global_basis.orthonormalized()
	for sd in ["l", "r"]:
		var hip := (bones["thigh_" + sd] as Node3D).global_position
		var tgt: Vector3 = targets[sd]
		_foot_last[sd] = tgt
		var d := tgt - hip
		var side := 0.12 if sd == "r" else -0.12
		var ik := _two_bone(hb, d.normalized(), d.length(), Vector3(side, 0.0, -1.0), 0.45, 0.44, -1.0)
		_set_bone("thigh_" + sd, (_rot["thigh_" + sd] as Quaternion).slerp(ik[0], _loco))
		_set_bone("shin_" + sd, (_rot["shin_" + sd] as Quaternion).slerp(ik[1], _loco))
		if _plant.has(sd) or _stance_w[sd] >= 0.0:
			# Sole on the ground plane, toes along the facing, heel rolled up.
			var n: Vector3 = normals[sd]
			var f := (_facing - n * _facing.dot(n)).normalized()
			if f.length_squared() < 0.5:
				continue
			var want := Basis.looking_at(f, n) * Basis(Vector3.RIGHT, -_toe[sd])
			var shin_b := (bones["shin_" + sd] as Node3D).global_basis.orthonormalized()
			var local := (shin_b.inverse() * want).get_rotation_quaternion()
			_set_bone("foot_" + sd, (_rot["foot_" + sd] as Quaternion).slerp(local, _loco))


## Ankle position with the foot rolled `toe` rad (heel up) about its ball.
static func _roll(ankle: Vector3, f: Vector3, n: Vector3, toe: float) -> Vector3:
	if toe <= 0.0:
		return ankle
	return ankle + n * sin(toe) * BALL - f * (1.0 - cos(toe)) * BALL


func _set_bone(b: String, qq: Quaternion) -> void:
	_rot[b] = qq
	(bones[b] as Node3D).quaternion = qq


func _ground_hit(space: PhysicsDirectSpaceState3D, at: Vector3) -> Dictionary:
	var rq := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * 0.7, player.collision_mask)
	rq.exclude = [player.get_rid()]
	return space.intersect_ray(rq)


## Ballistic flight, blended by phase so it always reads as one body moving:
##  * launch (rising): chest opens, arms sweep back and out, lead knee up;
##  * apex: limbs gather, elbows out for balance;
##  * falling: arms rise out to the sides, legs reach down;
##  * freefall arch (fast fall, height to spare): belly down, arms in a "W",
##    knees bent, toes pointed;
##  * dive (fast, steep): head-first streamline, arms together overhead;
##  * near the ground: legs come under the body to take the landing.
## Elbows and knees always keep some bend – straight "zombie" limbs read wrong.
func _pose_air(q: Dictionary, v: Vector3, speed: float, la: Vector3, dive: float, twist: float) -> void:
	var rising := clampf(v.y / 12.0, 0.0, 1.0)
	var falling := clampf(-v.y / 14.0, 0.0, 1.0)
	var sky := _skydive(v, dive)
	var near := clampf(1.0 - _ground_h / 7.0, 0.0, 1.0) * falling if _ground_h < INF else 0.0
	var react := clampf(la.z * 0.015, -0.3, 0.3)
	var drift := sin(_time * 2.1)  # a little life
	var cyc := sin(_time * 3.4)   # slow airborne leg cycle
	var ld := _lead
	var tr := "r" if ld == "l" else "l"
	var sg := {"l": -1.0, "r": 1.0}
	# Apex / base: knees gathered under, the lead one higher, arms out to the
	# sides with soft elbows – a balanced athletic float.
	_put(q, {
		"spine": _rx(0.1) * _ry(twist * 0.3), "chest": _rx(0.0), "neck": _rx(0.0), "head": _rx(-0.08),
		"upper_arm_" + ld: _rz(1.2 * sg[ld] + drift * 0.04) * _ry(-0.3 * sg[ld]) * _rx(0.15 + react),
		"upper_arm_" + tr: _rz(1.1 * sg[tr] - drift * 0.04) * _ry(-0.3 * sg[tr]) * _rx(0.3 + react),
		"forearm_" + ld: _rx(0.85), "forearm_" + tr: _rx(0.95),
		"thigh_" + ld: _rx(1.05) * _rz(0.06 * sg[ld]), "thigh_" + tr: _rx(0.6) * _rz(0.08 * sg[tr]),
		"shin_" + ld: _rx(-1.45), "shin_" + tr: _rx(-1.25), "foot_" + ld: _rx(-0.2), "foot_" + tr: _rx(-0.35),
	}, 1.0)
	# Rising: still in the stride of the take-off – lead knee up, trailing
	# leg long behind with the toes pointed, chest up, arms carried high.
	_put(q, {
		"spine": _rx(-0.06) * _ry(twist * 0.3), "chest": _rx(-0.08), "head": _rx(-0.15),
		"upper_arm_" + tr: _rx(2.45) * _rz(0.3 * sg[tr]), "forearm_" + tr: _rx(0.45),
		"upper_arm_" + ld: _rx(-0.45) * _rz(0.45 * sg[ld]), "forearm_" + ld: _rx(0.85),
		"thigh_" + ld: _rx(1.15) * _rz(0.04 * sg[ld]), "thigh_" + tr: _rx(-0.3) * _rz(0.04 * sg[tr]),
		"shin_" + ld: _rx(-1.3), "shin_" + tr: _rx(-0.55), "foot_" + ld: _rx(-0.1), "foot_" + tr: _rx(-0.6),
	}, rising * clampf(1.2 - _jump_t * 0.8, 0.0, 1.0) if _jump_t < 2.0 else rising * 0.4)
	# Falling: legs open and reach down (one a little ahead), arms rise up
	# and out for balance with the elbows bent – never a T-pose.
	_put(q, {
		"spine": _rx(0.04), "chest": _rx(0.0), "head": _rx(0.15),
		"upper_arm_" + ld: _rz(1.35 * sg[ld] + drift * 0.08 * sg[ld]) * _ry(-0.55 * sg[ld]) * _rx(0.2),
		"upper_arm_" + tr: _rz(1.3 * sg[tr] - drift * 0.08 * sg[tr]) * _ry(-0.55 * sg[tr]) * _rx(0.1),
		"forearm_" + ld: _rx(1.1), "forearm_" + tr: _rx(1.0),
		# Legs keep moving: a slow, loose cycle with bent knees (a runner's
		# stride in the air), never two straight posts hanging down.
		"thigh_" + ld: _rx(0.75 + cyc * 0.35) * _rz(0.1 * sg[ld]),
		"thigh_" + tr: _rx(0.3 - cyc * 0.35) * _rz(0.12 * sg[tr]),
		"shin_" + ld: _rx(-1.15 - maxf(cyc, 0.0) * 0.35), "shin_" + tr: _rx(-0.85 - maxf(-cyc, 0.0) * 0.35),
		"foot_" + ld: _rx(-0.2), "foot_" + tr: _rx(-0.35),
	}, falling * (1.0 - sky))
	# Freefall arch.
	_put(q, {
		"spine": _rx(-0.3), "chest": _rx(-0.15), "neck": _rx(-0.2), "head": _rx(-0.45),
		# "W": upper arms out level, twisted so the elbows bend toward the
		# head (the chest faces the ground here).
		"upper_arm_l": _rz(-1.45) * _ry(1.57) * _rx(-0.15), "upper_arm_r": _rz(1.45) * _ry(-1.57) * _rx(-0.15),
		"forearm_l": _rx(1.35 + drift * 0.08), "forearm_r": _rx(1.35 - drift * 0.08),
		"thigh_l": _rx(-0.2) * _rz(-0.2), "thigh_r": _rx(-0.2) * _rz(0.2),
		"shin_l": _rx(-1.05), "shin_r": _rx(-0.95), "foot_l": _rx(-0.5), "foot_r": _rx(-0.5),
	}, sky)
	# Landing prep: feet together under the hips and flat, knees soft and
	# ready to take the load, arms out wide and bent, eyes on the spot.
	_put(q, {
		"spine": _rx(0.18), "chest": _rx(0.06), "head": _rx(0.25),
		"upper_arm_l": _rz(-1.0) * _rx(0.3), "upper_arm_r": _rz(1.0) * _rx(0.25),
		"forearm_l": _rx(1.0), "forearm_r": _rx(1.0),
		"thigh_l": _rx(0.55) * _rz(-0.08), "thigh_r": _rx(0.45) * _rz(0.08),
		"shin_l": _rx(-0.75), "shin_r": _rx(-0.65), "foot_l": _rx(0.2), "foot_r": _rx(0.2),
	}, near)
	# Dive: streamlined, arms together overhead, toes pointed.
	_put(q, {
		"spine": _rx(0.08), "chest": _rx(0.0), "neck": _rx(0.15), "head": _rx(-0.35),
		"upper_arm_l": _rx(2.85) * _rz(0.12), "upper_arm_r": _rx(2.85) * _rz(-0.12),
		"forearm_l": _rx(0.15), "forearm_r": _rx(0.15),
		"thigh_l": _rx(0.05) * _rz(0.03), "thigh_r": _rx(-0.05) * _rz(-0.03),
		"shin_l": _rx(-0.15), "shin_r": _rx(-0.25), "foot_l": _rx(-0.7), "foot_r": _rx(-0.7),
	}, dive)


## 0..1 how much the freefall arch applies: falling fast, not diving, with
## room below (it gives way to the landing prep near the ground).
func _skydive(v: Vector3, dive: float) -> float:
	var room := clampf((_ground_h - 8.0) / 8.0, 0.0, 1.0) if _ground_h < INF else 1.0
	return clampf((-v.y - 13.0) / 10.0, 0.0, 1.0) * (1.0 - dive) * room


static func _put(q: Dictionary, pose: Dictionary, w: float) -> void:
	if w <= 0.001:
		return
	for b in pose:
		q[b] = (q[b] as Quaternion).slerp(pose[b], clampf(w, 0.0, 1.0))


## Body rotation of a trick at progress u (0..1), in the body frame.
func _trick_rotation(name: String, u: float) -> Quaternion:
	var t: Dictionary = TRICKS[name]
	var e := u * u * u * (u * (u * 6.0 - 15.0) + 10.0)  # smootherstep: slow–fast–slow
	var r := Quaternion(Vector3.RIGHT, float(t["flip"]) * e)
	if float(t["twist"]) != 0.0:
		r = r * Quaternion(Vector3.UP, float(t["twist"]) * _trick_dir * e)
	if float(t["roll"]) != 0.0:
		r = r * Quaternion(Vector3.BACK, float(t["roll"]) * _trick_dir * e)
	return r


## Limb shapes held through a trick; k rises into it and opens out at the end
## (open early enough to spot the landing).
func _pose_trick(q: Dictionary, name: String, u: float) -> void:
	var k := sin(PI * clampf(u * 1.1, 0.0, 1.0))
	k = sqrt(maxf(k, 0.0))
	var side := _trick_dir
	match TRICKS[name]["shape"]:
		"tuck":
			_put(q, {
				"spine": _rx(0.6), "chest": _rx(0.35), "neck": _rx(0.25), "head": _rx(0.35),
				"thigh_l": _rx(2.05) * _rz(-0.08), "thigh_r": _rx(2.05) * _rz(0.08),
				"shin_l": _rx(-2.3), "shin_r": _rx(-2.3), "foot_l": _rx(-0.4), "foot_r": _rx(-0.4),
				"upper_arm_l": _rx(1.25) * _rz(-0.2), "upper_arm_r": _rx(1.25) * _rz(0.2),
				"forearm_l": _rx(1.55), "forearm_r": _rx(1.55),
			}, k)
		"pike":
			_put(q, {
				"spine": _rx(0.7), "chest": _rx(0.3), "neck": _rx(0.2), "head": _rx(0.3),
				"thigh_l": _rx(1.75), "thigh_r": _rx(1.75), "shin_l": _rx(-0.08), "shin_r": _rx(-0.08),
				"foot_l": _rx(-0.6), "foot_r": _rx(-0.6),
				"upper_arm_l": _rx(1.9) * _rz(-0.1), "upper_arm_r": _rx(1.9) * _rz(0.1),
				"forearm_l": _rx(0.15), "forearm_r": _rx(0.15),
			}, k)
		"layout":
			# Arms sweep overhead out of the take-off, then open to the sides.
			var over := 1.0 - smoothstep(0.15, 0.6, u)
			_put(q, {
				"spine": _rx(-0.18), "chest": _rx(-0.12), "head": _rx(-0.25),
				"thigh_l": _rx(-0.05), "thigh_r": _rx(-0.05), "shin_l": _rx(-0.08), "shin_r": _rx(-0.08),
				"foot_l": _rx(-0.65), "foot_r": _rx(-0.65),
				"upper_arm_l": (_rx(2.7) * _rz(0.1)).slerp(_rz(-1.5) * _rx(-0.1), 1.0 - over),
				"upper_arm_r": (_rx(2.7) * _rz(-0.1)).slerp(_rz(1.5) * _rx(-0.1), 1.0 - over),
				"forearm_l": _rx(0.2), "forearm_r": _rx(0.2),
			}, k)
		"twist", "pencil":
			# Arms pulled tight across the chest spin you faster (and look it).
			var open := 1.0 - smoothstep(0.1, 0.3, u) + smoothstep(0.8, 1.0, u)
			var tight := {
				"spine": _rx(-0.05), "chest": _rx(0.0), "head": _rx(-0.05),
				"thigh_l": _rx(0.02) * _rz(0.04), "thigh_r": _rx(0.02) * _rz(-0.04),
				"shin_l": _rx(-0.06), "shin_r": _rx(-0.1), "foot_l": _rx(-0.7), "foot_r": _rx(-0.7),
				"upper_arm_l": _rz(-0.15) * _rx(0.55) * _ry(0.5), "upper_arm_r": _rz(0.15) * _rx(0.5) * _ry(-0.5),
				"forearm_l": _rx(2.1), "forearm_r": _rx(2.2),
			}
			_put(q, tight, k * (1.0 - clampf(open, 0.0, 1.0) * 0.7))
		"split":
			# Cartwheel: arms and legs wide, a star.
			_put(q, {
				"spine": _rz(-0.08 * side), "chest": _rx(-0.05), "head": _rz(0.1 * side),
				"thigh_l": _rz(-0.95) * _rx(0.1), "thigh_r": _rz(0.95) * _rx(0.1),
				"shin_l": _rx(-0.15), "shin_r": _rx(-0.15), "foot_l": _rx(-0.5), "foot_r": _rx(-0.5),
				"upper_arm_l": _rz(-2.2) * _rx(0.1), "upper_arm_r": _rz(2.2) * _rx(0.1),
				"forearm_l": _rx(0.25), "forearm_r": _rx(0.25),
			}, k)


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
