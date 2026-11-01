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

## Emitted at the end of every pose update – what gets drawn this frame.
## (Measure poses here: right after process_frame the capsule has already
## moved for the next frame while the limbs haven't.)
signal posed
## A running/walking foot touched down (the gait's own plant, so sounds match the feet).
signal footstep(pos: Vector3)

const MODEL_PATH := "res://assets/models/character.glb"
const GEAR_PATH := "res://assets/models/gear.glb"
## Gear pieces that ride a bone other than the head (gadgets).
const GEAR_BONES := {"jet_l": "foot_l", "jet_r": "foot_r", "jet_l_fire": "foot_l", "jet_r_fire": "foot_r",
	"glider": "chest", "glider_open": "chest", "chrono": "forearm_l", "magnet": "hips"}

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
var _swing_lead := "l"     # leg that folds/leads on this web (alternates web to web)
var _off_ledge := false    # airborne straight off the ground (jumped / ran off), no web since
var _swan := 0.0           # head-first dive off a building 0..1
var _swan_peak := 0.0      # how deep the current dive got (drives the pull-out tuck)
var _bump_t := 0.0         # wall-contact reaction remaining (s)
var _bump_n := Vector3.ZERO
var _bump_k := 0.0         # its strength 0..1
var _stagger_t := 0.0      # knocked back off a wall on foot (s left)
var _stagger_n := Vector3.ZERO
var _press := 0.0          # leaning on a wall, hands flat on it 0..1
var _press_n := Vector3.ZERO
var _guard_off := {}       # limb root bone -> [upper offset, ang vel, lower offset, ang vel]
var _brace := 0.0          # arms coming up before an impact 0..1
var _brace_n := Vector3.ZERO
var _brace_probe := 0.0
var _getup_down := true    # get-up from face-down (push up) or face-up (sit up, roll onto the feet)
var _getup_off := Vector3.ZERO  # where the ragdoll left the body, relative to the capsule
var _wall_time := 0.0      # wall run / wall tap pose remaining
var _wall_n := Vector3.BACK
var _takeoff_t := 0.0
var _getup_t := 0.0
var _air_t := 0.0
var _was_grounded := true
var _loco := 0.0           # 0..1 how much ground locomotion drives the limbs
var _contact := 0.0        # 0..1 how much the feet are held on the ground (IK), any grounded pose
var _flat := {"l": 0.0, "r": 0.0}  # 0..1 sole laid on the ground (eases in at touchdown)
var _heel := {"l": 0.0, "r": 0.0}  # heel-strike toes-up angle (rad) from the gait
var _lead := "l"           # leg that was driving forward at take-off (it leads the jump)
var _jump_t := 0.0         # time since leaving the ground on a jump (not a web)
var _release_t := 0.0      # launch stretch after letting go of a web (s left)
var _hard_t := 0.0         # hard-landing crouch remaining (s)
var _glide := 0.0          # 0..1 flying forward off a web: chest leads, arms out like wings
var _glide_rope := 0.0     # 0..1 the same lean while swinging forward on the web
var _bank := Vector3.ZERO  # smoothed sideways lean into an air turn (world, horizontal)
var _turn := 0.0           # -1..1 how hard the body is turning (+ = right); head and arms lead it
const HARD_TIME := 0.62
const STUMBLE_TIME := 0.6
var stumble_t := 0.0       # off-balance landing remaining (s); read by tests
var _stumble_side := 1.0
var _stumble_k := 1.0
var _hard_lead := "l"
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
var _gait := Gait.new()      # world-space foot placement (ground locomotion)
var _gait_live := false      # the gait drove the legs this frame
var _floor_t := 0.0         # s since the capsule was last on the floor
var _gait_amp := 0.0         # 0..1 stride amplitude (eases in/out on start/stop)
var _hip_shift := 0.0        # pelvis side-shift over the stance foot (m)
var _settle := {}          # side -> [progress 0..1, from ankle pos]: a small step back under the hips
const SETTLE_DIST := 0.16  # a standing foot further than this from its rest spot steps in
const SETTLE_TIME := 0.28
var _step_off := 0.0       # visual ease after the capsule steps up a kerb
var _grips := {}           # "l"/"r" -> [open_node, grip_node]
var _gear := {}            # headwear model name -> MeshInstance3D on the head pivot
## The outfit being drawn (Shop.look()).
var look_state := {}
var _gadget_on := false
var _scarf: Array[Node3D] = []
var _scarf_pts: Array[Vector3] = []
var _scarf_prev: Array[Vector3] = []


func _ready() -> void:
	_irng.seed = 9137  # idle choices: varied, but repeatable run to run
	var parts := _load_parts()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/player/shaders/character.gdshader")
	_mat = mat
	if skeleton:
		for mi in skeleton.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mat
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
	# Headwear: the hood (part of the character model) and the shop gear
	# (gear.glb) all ride the head; apply_look shows one hat and one face piece.
	var hood: MeshInstance3D = parts.get("hood")
	if hood:
		_gear["hood"] = hood
	if ResourceLoader.exists(GEAR_PATH):
		var g: Node = (load(GEAR_PATH) as PackedScene).instantiate()
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			mi.get_parent().remove_child(mi)
			mi.owner = null
			_gear[String(mi.name).to_lower()] = mi
		g.free()
	for key in _gear:
		var gm: MeshInstance3D = _gear[key]
		gm.transform = Transform3D.IDENTITY
		gm.material_override = mat
		gm.visible = false
		bones[GEAR_BONES.get(key, "head")].add_child(gm)
	apply_look(Shop.look())
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


## Dresses the hero in a Shop.look(): region colours and the headwear.
func apply_look(look: Dictionary) -> void:
	look_state = look
	if _mat:
		for k in [["suit", "suit_color"], ["pants", "pants_color"], ["shoe", "shoe_color"], ["sole", "sole_color"],
				["glove", "glove_color"], ["glow", "glow_color"]]:
			var c: Color = look[k[0]]
			_mat.set_shader_parameter(k[1], Vector3(c.r, c.g, c.b))
	_show_gear()


## A running gadget shows its active pieces (jet flames, open wings).
func set_gadget_active(on: bool) -> void:
	if on != _gadget_on:
		_gadget_on = on
		_show_gear()


func _show_gear() -> void:
	var g: Dictionary = look_state.get("gadget", {})
	var parts: Array = g.get("parts", [])
	var active: Array = g.get("active", [])
	if _gadget_on and g.get("swap", false):
		parts = []
	for key in _gear:
		(_gear[key] as MeshInstance3D).visible = key == look_state.get("head", "hood") \
			or key == look_state.get("face", "") or key in parts or (_gadget_on and key in active)


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
	player.bumped.connect(_on_bumped)
	player.staggered.connect(_on_staggered)
	player.attached.connect(func(_a) -> void:
		_swing_lead = "r" if _swing_lead == "l" else "l"
		_jolt(0.6))
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
	var impact := maxf(speed, player.land_impact if player else 0.0)
	cloth_kick(Vector3.DOWN * clampf(impact * 0.045, 0.0, 0.9))
	_land_squash = clampf(impact / 22.0, 0.15, 1.0)
	var vh := Vector3(player.s.velocity.x, 0, player.s.velocity.z).length() if player else 0.0
	if ragdolling or (player and player.stunned):
		return
	if player and impact > player.params.roll_landing_speed and vh > 8.0:
		_roll_time = 0.55  # shoulder roll to carry a fast landing forward
	elif impact > 12.0 and vh < 3.5:
		# Dropped from height without much run: a three-point landing – lead
		# knee up, the other knee nearly down, one hand to the ground.
		_hard_t = HARD_TIME
		_hard_lead = _lead
	elif player and impact > 6.0 and vh > 3.0:
		# Coming down moving sideways to the way the body faces: off balance –
		# arms thrown out, the torso tips toward the slide and rights itself
		# while the feet catch up (the gait takes the corrective steps).
		var vdir := Vector3(player.s.velocity.x, 0.0, player.s.velocity.z).normalized()
		var side := _facing.cross(vdir).y
		# (Also out of a banked air turn: the body is still leaning into it.)
		var lean := _bank.dot(_facing.cross(Vector3.UP))
		if absf(side) < 0.5 and absf(lean) > 0.12:
			side = signf(lean)
		if absf(side) > 0.5:
			stumble_t = STUMBLE_TIME
			_stumble_side = signf(side)
			_stumble_k = clampf((impact - 6.0) / 10.0, 0.4, 1.0)


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


## Any wall contact: the body physically gives – the upper body is knocked
## back off the surface (spring impulses scaled by the speed into it), the
## head whips, the arms brace toward the wall and the knees absorb.
func _on_bumped(speed: float, n: Vector3) -> void:
	if ragdolling:
		return
	var k := clampf(speed / 12.0, 0.15, 1.0)
	var axis := (global_basis.inverse() * n.cross(Vector3.UP)).normalized()
	if axis.length_squared() < 0.5:
		axis = Vector3.RIGHT
	# Torso bones bend backward on +X: a hit on the chest (normal toward the
	# back) tips the torso back about the axis along the wall.
	_angvel["spine"] += axis * 3.0 * k
	_angvel["chest"] += axis * 4.0 * k
	_angvel["head"] += axis * 7.0 * k
	_angvel["neck"] += axis * 2.5 * k
	for sd in ["l", "r"]:
		_angvel["thigh_" + sd] += Vector3(2.5, 0, 0) * k
		_angvel["shin_" + sd] += Vector3(-3.5, 0, 0) * k
	if speed >= 3.0:
		_bump_t = 0.4
		_bump_n = n
		_bump_k = maxf(k, _bump_k if _bump_t > 0.0 else 0.0)
		_land_squash = maxf(_land_squash, 0.25 * k) if player.is_on_floor() else _land_squash


## Ran into a wall on foot: the head and chest are thrown back off it, the
## arms come up to take it, and the legs back-pedal (Player bounces the body
## back; facing stays on the wall while it does).
func _on_staggered(speed: float, n: Vector3) -> void:
	if ragdolling:
		return
	_stagger_t = Player.STAGGER_TIME + 0.2
	_stagger_n = Vector3(n.x, 0.0, n.z).normalized()
	var k := clampf(speed / 10.0, 0.4, 1.0)
	_angvel["chest"] += Vector3(5.0, 0, 0) * k
	_angvel["head"] += Vector3(9.0, 0, 0) * k
	_angvel["neck"] += Vector3(4.0, 0, 0) * k
	_land_squash = maxf(_land_squash, 0.35 * k)
	_bump_t = 0.5
	_bump_n = n
	_bump_k = 1.0


## Looks ahead along the motion a few times a second: a facade coming up
## fast raises the arms to take it (visual only).
func _update_brace(dt: float, v: Vector3, speed: float, wall_run: bool) -> void:
	_brace_probe -= dt
	var want := _brace if _brace_probe > 0.0 else 0.0
	if _brace_probe <= 0.0:
		_brace_probe = 0.08
		if speed > 7.0 and not wall_run and not ragdolling and is_inside_tree():
			var from := player.global_position + Vector3.UP * 0.4
			var rq := PhysicsRayQueryParameters3D.create(from, from + v * 0.5, Player.BUILDINGS_MASK)
			rq.exclude = [player.get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(rq)
			if not hit.is_empty():
				var n: Vector3 = hit.normal
				var into := -v.dot(n)
				if n.y < 0.6 and into > 6.0:
					var tti := from.distance_to(hit.position) / into
					want = clampf((0.45 - tti) / 0.3, 0.0, 1.0)
					_brace_n = n
	_brace = move_toward(_brace, want, dt * 8.0)


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
	# A landing that turns into a crash must not leave its roll / crouch
	# queued for after the get-up.
	_roll_time = 0.0
	_hard_t = 0.0
	_flip = 0.0
	_swan = 0.0
	_swan_peak = 0.0
	_bump_t = 0.0
	_brace = 0.0
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
		_rot[b] = Quaternion.IDENTITY  # start clean, not from wherever the last life ended
	_prev_vel = player.s.velocity if player else Vector3.ZERO
	_accel = Vector3.ZERO  # the teleport is not an acceleration
	_loco = 0.0
	# Idle life, anticipation and cloth start fresh too (no state leaking
	# from the last life into the next).
	exert = 0.0
	stumble_t = 0.0
	idle_action = ""
	_idle_t = 0.0
	_idle_next = 3.0
	_idle_sink = 0.0
	_gaze = Vector2.ZERO
	_antic = 0.0
	cloth = Vector3.ZERO
	_cloth_v = Vector3.ZERO
	_cloth_air = Vector3.ZERO
	_contact = 0.0
	_was_grounded = false
	for sd in ["l", "r"]:
		_foot_off[sd] = Vector3.ZERO
		_flat[sd] = 0.0
		_toe[sd] = 0.0
		_heel[sd] = 0.0
	_hard_t = 0.0
	_glide = 0.0
	_glide_rope = 0.0
	_bank = Vector3.ZERO
	_turn = 0.0
	_getup_t = 0.0
	_release_t = 0.0
	_takeoff_t = 0.0
	_land_squash = 0.0
	_wall_time = 0.0
	_stagger_t = 0.0
	_press = 0.0
	_guard_off.clear()
	_plant.clear()
	_foot_last.clear()
	_foot_mode.clear()
	_hip_drop = 0.0
	_settle.clear()
	_gait.reset()
	_gait_amp = 0.0
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
		"trick": _trick if _trick != "" else _last_trick_seen, "tricks": tricks_done, "ko": player.knocked_out,
		"glide": snappedf(maxf(_glide, _glide_rope), 0.01), "turn": snappedf(_turn, 0.01)}


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
	_guard_limbs()
	_no_pops(dt)
	_update_scarf(dt)
	_update_cloth(dt)
	_sync_skeleton()
	# Closed hands on the line, and loose fists when running or flying (open
	# flat palms read as waving); open hands when standing.
	# Gliding, the free hands open flat like wing tips.
	var fists := not player.is_on_floor() or player.speed() > 3.5 or ragdolling
	var wing := maxf(_glide, _glide_rope) > 0.5 and not ragdolling
	_set_grip("r", player.line_state != Player.Line.IDLE or (fists and not wing))
	_set_grip("l", (player.line_state == Player.Line.ATTACHED and player.s.tension > 25.0 and _lgrip > 0.5) or (fists and not wing))
	posed.emit()


## Pop guard: no joint's rotation speed may change faster than POP_ACCEL, so
## a pose that jumps between states (a rushed step, a stop against a wall,
## getting up) turns into a quick 2–3 frame move instead of a one-frame snap.
## Upper body only: the legs follow their IK exactly (feet stay planted).
## Motion inside the limit passes through exactly; the ragdoll is physics,
## so it only seeds the state.
const POP_ACCEL := deg_to_rad(80000.0)  # rad/s² (~1330°/s of change per 60 fps frame)
var _pq := {}
var _pw := {}


func _no_pops(dt: float) -> void:
	if dt <= 0.0:
		return
	var lim := POP_ACCEL * dt
	for b in bones:
		if String(b).begins_with("thigh") or String(b).begins_with("shin") or String(b).begins_with("foot") \
				or String(b).begins_with("toe") or b == "hips":
			continue  # (legs follow their IK exactly: feet must stay planted)
		var node := bones[b] as Node3D
		var qt := node.quaternion
		if ragdolling or not _pq.has(b):
			_pq[b] = qt
			_pw[b] = Vector3.ZERO
			continue
		var qp: Quaternion = _pq[b]
		var d := qt * qp.inverse()
		if d.w < 0.0:
			d = -d
		var ang := d.get_angle()
		var wt := d.get_axis() * (ang / dt) if ang > 1e-6 else Vector3.ZERO
		var wp: Vector3 = _pw[b]
		var dw := wt - wp
		if dw.length() > lim:
			var w := wp + dw.normalized() * lim
			var q := (Quaternion(w.normalized(), w.length() * dt) * qp).normalized() if w.length() > 1e-6 else qp
			node.quaternion = q
			_pq[b] = q
			_pw[b] = w
		else:
			_pq[b] = qt
			_pw[b] = wt


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
	_update_exert(dt, hs if player.is_on_floor() else speed, player.is_on_floor())
	var on_rope := player.line_state != Player.Line.IDLE
	# Kerbs and steps down lift the capsule off the floor for a few frames:
	# the body keeps walking through them (animation only) instead of
	# flickering into the air poses.
	_floor_t = 0.0 if player.is_on_floor() else _floor_t + dt
	var grounded := player.is_on_floor() and not s.attached
	if not grounded and _floor_t < 0.12 and v.y > -4.0 and v.y < 2.0 and not on_rope and _was_grounded \
			and not s.attached and _getup_t <= 0.0 and _roll_time <= 0.0:
		# (Only with a floor within a kerb's height under the feet.)
		var at := player.global_position
		var kq := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 1.32, player.collision_mask, [player.get_rid()])
		grounded = not get_world_3d().direct_space_state.intersect_ray(kq).is_empty()
	var attached := player.line_state == Player.Line.ATTACHED
	# Rope load 0..1: taut + tension. Slack line = 0 (body relaxes into flight).
	_load = move_toward(_load, clampf(s.tension / 40.0, 0.0, 1.0) if attached and s.taut else 0.0, dt * 4.0)
	var wall_run := _wall_time > 0.0 and v.y > 1.5 and not on_rope
	_wall_time = maxf(_wall_time - dt, 0.0)
	_takeoff_t = maxf(_takeoff_t - dt, 0.0)
	_release_t = maxf(_release_t - dt, 0.0)
	_hard_t = maxf(_hard_t - dt, 0.0)
	stumble_t = maxf(stumble_t - dt, 0.0)
	if _hard_t > 0.0 and (not player.is_on_floor() or player.controls.move.length() > 0.3 and _hard_t < HARD_TIME * 0.6):
		_hard_t = minf(_hard_t, 0.12)  # off again / running on: rise quickly
	# Getting up: quicker if the player is already pushing the stick.
	_getup_t = maxf(_getup_t - dt * (1.8 if player.controls.move.length() > 0.3 else 1.0), 0.0)
	if _getup_t > 0.2 and Vector3(v.x, 0.0, v.z).length() > 2.5:
		_getup_t = 0.2  # already running off: finish rising in stride
	_bump_t = maxf(_bump_t - dt, 0.0)
	if grounded and not _was_grounded:
		_air_t = 0.0
	if not grounded and _was_grounded and v.y > 6.0 and not on_rope:
		_takeoff_t = 0.3  # push-off: legs extend, arms drive up
		_jump_t = 0.0
	if not grounded and _was_grounded and not on_rope:
		_off_ledge = true  # jumped or ran off: no web since
	if grounded or on_rope or ragdolling:
		_off_ledge = false
	_was_grounded = grounded
	if not grounded:
		_air_t += dt
		_jump_t += dt
	var air := not grounded and not on_rope
	# Off a building with a long way down: a swan dive – the body pitches
	# head-first as the fall steepens, and pulls out (tucks feet-first)
	# in time to land on the feet.
	# (The pull-out starts ~0.6 s before the ground at the current fall speed.)
	var room := _ground_h == INF or _ground_h > 12.0
	var pull := _ground_h < maxf(9.0, -v.y * 0.6)
	var swan_go := air and _off_ledge and _trick == "" and v.y < -1.0 and room and not pull
	_swan = move_toward(_swan, 1.0 if swan_go else 0.0, dt * (1.3 if swan_go else 2.6))
	_swan_peak = maxf(_swan_peak, _swan) if air else 0.0
	_loco = move_toward(_loco, 1.0 if grounded and _getup_t <= 0.0 and _hard_t <= 0.0 and _roll_time <= 0.0
		else 0.0, dt * 6.0)
	# Feet stay on the ground in every grounded pose (landings, crouches,
	# get-ups), not just locomotion – only a roll or a wall run lifts them.
	# (Early in a get-up the feet aren't planted, only kept above the ground.)
	var contact := grounded and _roll_time <= 0.0 and not wall_run
	_contact = move_toward(_contact, 1.0 if contact else 0.0, dt * (12.0 if contact else 8.0))
	for sd in ["l", "r"]:
		_stance_w[sd] = -1.0
		_swing_w[sd] = -1.0
		_heel[sd] = 0.0
	_gait_live = false
	_hip_shift = 0.0

	# --- facing & turn rate -----------------------------------------------
	_stagger_t = maxf(_stagger_t - dt, 0.0)
	if wall_run:
		_facing = _facing.slerp(-_wall_n, 1.0 - exp(-14.0 * dt)).normalized()
	elif _stagger_t > 0.0 and grounded:
		_facing = _facing.slerp(-_stagger_n, 1.0 - exp(-10.0 * dt)).normalized()  # still facing the wall
	elif hs > 1.0:
		# Walking turns follow the path closely (feet and hips stay lined up
		# with where the body is going); at a run the body swings round more.
		var turn_rate := lerpf(10.0, 6.0, clampf((hs - 1.8) / 5.0, 0.0, 1.0)) if grounded else 6.5
		_facing = _facing.slerp(vh.normalized(), 1.0 - exp(-turn_rate * dt)).normalized()
	elif grounded and player.controls.move.length() > 0.1:
		_facing = _facing.slerp(player.controls.move.normalized(), 1.0 - exp(-8.0 * dt)).normalized()
	var ang := atan2(_facing.x, _facing.z)
	_yaw_rate = lerpf(_yaw_rate, wrapf(ang - _prev_facing_angle, -PI, PI) / maxf(dt, 0.001), 1.0 - exp(-6.0 * dt))
	_prev_facing_angle = ang
	var right_w := Vector3.UP.cross(_facing).normalized() * -1.0  # facing × up = right
	var la_w := _accel
	# Turning in the air: the sideways (centripetal) part of the acceleration
	# banks the body into the turn like a glider – the angle a body would
	# lean to hold that turn (atan(a/g)), capped at ~43°.
	var lat := Vector3.ZERO
	if not grounded and hs > 3.0:
		var hd := vh / hs
		var ah := Vector3(la_w.x, 0.0, la_w.z)
		lat = (ah - hd * ah.dot(hd)) / 9.8
		lat = lat.limit_length(0.93) * clampf((hs - 3.0) / 6.0, 0.0, 1.0)
	_bank = _bank.lerp(lat, 1.0 - exp(-7.0 * dt))
	_turn = clampf(_bank.dot(right_w) / 0.7, -1.0, 1.0)
	# Gliding: flying forward off a web (not a jump or a drop off a ledge),
	# with air below – the chest leads, arms spread like wings.
	var glide_go := not grounded and not on_rope and not _off_ledge and _trick == "" \
		and hs > 6.0 and v.y > -16.0 and (_ground_h == INF or _ground_h > 5.0)
	_glide = move_toward(_glide, clampf((hs - 6.0) / 6.0, 0.0, 1.0) if glide_go else 0.0, dt * (2.5 if glide_go else 4.0))
	var rope_go := attached and speed > 7.0
	_glide_rope = move_toward(_glide_rope, clampf((speed - 7.0) / 9.0, 0.0, 1.0) if rope_go else 0.0, dt * 3.0)

	# --- whole-body orientation -------------------------------------------
	var up := Vector3.UP
	var fwd_hint := _facing
	var dive := 0.0
	if grounded:
		# Lean into acceleration (sprint start / braking) and into turns.
		var fa := clampf(la_w.dot(_facing) * 0.007, -0.24, 0.16)
		# Runners lean from the ankles, more as they speed up (a straight line
		# ankle–hip–shoulder, not a bend at the waist).
		var run_lean := 0.04 + 0.17 * clampf((hs - 2.0) / 12.0, 0.0, 1.0) if hs > 1.0 else 0.0
		var bank := clampf(-_yaw_rate * hs * 0.025, -0.35, 0.35)
		if _hard_t > 0.0:
			# Three-point landing: the whole body pitches forward over the knee.
			fa = 0.3 * _hard_k()
		up = (Vector3.UP + _facing * (fa + run_lean) + right_w * bank).normalized()
		if _getup_t > 0.0:
			var gp := _getup_pitch(_getup_u())
			up = (Vector3.UP * cos(gp) + _facing * sin(gp)).normalized()
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
			# Swinging forward: the body leans into the travel, chest first.
			up = (up + fwd_hint * tan(0.38 * _glide_rope)).normalized()
		up = (up + _bank * 0.4).normalized()
	else:
		# Head-first only in a fast, steep descent with real forward speed.
		dive = clampf((-v.y - 20.0) / 12.0, 0.0, 1.0) * clampf((speed - 28.0) / 10.0, 0.0, 1.0) \
			* clampf((hs - 12.0) / 8.0, 0.0, 1.0)
		var lean := clampf(speed / 60.0, 0.0, 0.28)
		up = Vector3.UP.lerp(v.normalized() if speed > 1.0 else Vector3.UP, lean).normalized()
		if v.y < -6.0:
			up = up.lerp(Vector3.UP, 0.5).normalized()  # dropping: feet stay under the body
		if _glide > 0.0 and hs > 0.1:
			# Gliding: pitched ~35° forward over the direction of travel.
			var gl := (Vector3.UP * cos(0.62) + vh / hs * sin(0.62)).normalized()
			up = up.slerp(gl, _glide).normalized()
		up = (up + _bank).normalized()  # banked into the turn
		# Freefall arch: falling fast with height to spare, the body lies
		# belly-down, head toward the travel direction.
		var sky := _skydive(v, dive)
		if sky > 0.0:
			var ahead := (_facing + Vector3.UP * 0.2).normalized()
			up = up.slerp(ahead, sky * 0.8).normalized()
			fwd_hint = fwd_hint.slerp(Vector3.DOWN, sky * 0.9).normalized()
		dive = maxf(dive, smoothstep(0.0, 1.0, _swan))
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
		rate = 9.0  # the phases set the pitch; follow them closely
	if air and _swan_peak > 0.3 and _swan < _swan_peak:
		rate = 9.0  # pulling out of a dive: swing the feet under quickly
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
	if _getup_t > 0.0:
		# The body starts where the ragdoll left it (on the ground) and rises
		# through the phases instead of popping up to standing height.
		var gu := _getup_u()
		var hips := Vector3(0.0, _getup_height(gu), 0.0)
		global_position += _getup_off.lerp(hips, smoothstep(0.0, 0.3, gu))
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
		_pose_getup(q, _getup_u())
	elif _hard_t > 0.0 and grounded:
		bob = -_pose_hard_land(q)
		_plant_both(1.2 * _hard_k())
	elif wall_run:
		_pose_wall_run(q, dt)
	elif grounded:
		bob = _pose_ground(q, dt, hs, la)
		if _stagger_t > 0.0:
			# Thrown back off the wall: chest and head go back, knees give.
			var sk := smoothstep(0.0, 0.12, Player.STAGGER_TIME + 0.2 - _stagger_t) * clampf(_stagger_t / 0.35, 0.0, 1.0)
			q["spine"] = (q["spine"] as Quaternion) * _rx(0.22 * sk)
			q["chest"] = (q["chest"] as Quaternion) * _rx(0.28 * sk)
			q["head"] = (q["head"] as Quaternion) * _rx(0.2 * sk)
			bob -= 0.05 * sk
		if _press > 0.01:
			# Leaning into the wall: the body tips toward it from the ankles.
			q["spine"] = (q["spine"] as Quaternion) * _rx(-0.12 * _press)
			q["chest"] = (q["chest"] as Quaternion) * _rx(-0.1 * _press)
			q["head"] = (q["head"] as Quaternion) * _rx(0.15 * _press)
	elif on_rope:
		_pose_rope(q, dt, body, la, twist, speed)
	else:
		_pose_air(q, v, speed, la, dive, twist)
	if _release_t > 0.0 and air and _trick == "":
		# Release: the whole body extends along the throw – arms flung out
		# wide like wings, chest open, legs long and together, toes pointed –
		# then settles into the glide.
		# (Eases in over a few frames too: limbs never jump into it.)
		var r := smoothstep(0.0, 1.0, _release_t / RELEASE_TIME) * smoothstep(0.0, 0.07, RELEASE_TIME - _release_t)
		_put(q, {
			"spine": _rx(0.2), "chest": _rx(0.14), "neck": _rx(0.06), "head": _rx(0.12),
			"upper_arm_r": _rz(1.55) * _rx(0.35), "upper_arm_l": _rz(-1.5) * _rx(0.25),
			"forearm_r": _rx(0.15), "forearm_l": _rx(0.2),
			"thigh_l": _rx(-0.18) * _rz(-0.03), "thigh_r": _rx(-0.06) * _rz(0.03),
			"shin_l": _rx(-0.2), "shin_r": _rx(-0.35), "foot_l": _rx(-0.65), "foot_r": _rx(-0.6),
		}, r)
	if _takeoff_t > 0.0 and air:
		# Push-off: the lead knee drives up, the take-off leg extends behind
		# with the toes pointed, the opposite arm punches up – a running
		# jump, not a hop. Blends out over 0.3 s into the airborne poses.
		var k := smoothstep(0.0, 1.0, _takeoff_t / 0.3) * smoothstep(0.0, 0.07, 0.3 - _takeoff_t)
		var lead := _lead
		var trail := "r" if lead == "l" else "l"
		var sgn := {"l": -1.0, "r": 1.0}
		_put(q, {
			"spine": _rx(-0.08), "chest": _rx(0.04), "head": _rx(0.1),
			"thigh_" + lead: _rx(1.3) * _rz(0.04 * sgn[lead]), "shin_" + lead: _rx(-1.35),
			"foot_" + lead: _rx(0.1),
			"thigh_" + trail: _rx(-0.42) * _rz(0.03 * sgn[trail]), "shin_" + trail: _rx(-0.3),
			"foot_" + trail: _rx(-0.65),
			# Opposite arm to the lead knee goes high, the other drives back.
			"upper_arm_" + trail: _rx(2.1) * _rz(0.25 * sgn[trail]), "forearm_" + trail: _rx(0.75),
			"upper_arm_" + lead: _rx(-0.55) * _rz(0.3 * sgn[lead]), "forearm_" + lead: _rx(0.95),
		}, k)
	# Reacting to the world: arms come up toward a wall about to be hit
	# (brace), and after any contact they push off it with bent elbows.
	_update_brace(dt, v, speed, wall_run)
	# Pushing on into a wall while standing at it: hands flat on the wall.
	var mv_in := player.controls.move
	var pressing := grounded and player.is_on_wall() and hs < 2.0 and _stagger_t <= 0.0 \
		and mv_in.length() > 0.3 and mv_in.normalized().dot(-player.get_wall_normal()) > 0.45
	if pressing:
		_press_n = Vector3(player.get_wall_normal().x, 0.0, player.get_wall_normal().z).normalized()
		_facing = _facing.slerp(-_press_n, 1.0 - exp(-10.0 * dt)).normalized()
	_press = move_toward(_press, 1.0 if pressing else 0.0, dt * (7.0 if pressing else 4.0))
	var bw := 0.0
	if _bump_t > 0.0:
		bw = _bump_k * smoothstep(0.0, 0.05, 0.4 - _bump_t) * (_bump_t / 0.4)
	var react_w := maxf(maxf(bw, _brace), _press)
	if react_w > 0.01 and not ragdolling:
		var n := _brace_n if _brace > bw else _bump_n
		if _press >= maxf(bw, _brace):
			n = _press_n
		var into := (-n + Vector3.UP * 0.25).normalized()
		var chest_b := (bones["chest"] as Node3D).global_basis.orthonormalized()
		# Reach as far as the wall actually is (the guard pass keeps palms on it).
		var reach := 0.42
		if _press > 0.01:
			var sh := (bones["chest"] as Node3D).global_position
			var wq := PhysicsRayQueryParameters3D.create(sh, sh - n * 1.0, GUARD_MASK, [player.get_rid()])
			var wh := get_world_3d().direct_space_state.intersect_ray(wq)
			reach = clampf(sh.distance_to(wh["position"]) - 0.02, 0.2, 0.53) if not wh.is_empty() else 0.5
		for sd in ["l", "r"]:
			if (sd == "r" and on_rope) or (sd == "l" and _lgrip > 0.5):
				continue
			var sgn := -1.0 if sd == "l" else 1.0
			var ik := _two_bone(chest_b, (into - chest_b.x * sgn * -0.25 * _press).normalized(), reach,
				Vector3(0.75 * sgn, -0.2, 0.6))
			q["upper_arm_" + sd] = (q["upper_arm_" + sd] as Quaternion).slerp(ik[0], react_w)
			q["forearm_" + sd] = (q["forearm_" + sd] as Quaternion).slerp(ik[1], react_w)
		q["head"] = (q["head"] as Quaternion).slerp(_rx(-0.25), react_w * 0.6)  # chin tucks
	# Hip bob (running) – the pelvis rides up and down over the stance leg.
	(bones["hips"] as Node3D).position.y = lerpf((bones["hips"] as Node3D).position.y,
		(BONES["hips"][1] as Vector3).y - 0.9 + bob - _hip_drop, 1.0 - exp(-20.0 * dt))
	(bones["hips"] as Node3D).position.x = lerpf((bones["hips"] as Node3D).position.x, _hip_shift, 1.0 - exp(-12.0 * dt))
	if not _gait_live and _gait.active:
		_gait.reset()  # next time on the feet, start from where they are
		_gait_amp = 0.0

	_reach_next(q, body, dt, air and not on_rope and _trick == "" and _release_t <= 0.0 and _takeoff_t <= 0.0)
	_drive_springs(q, dt, on_rope, grounded)
	if air:
		_ground_t -= dt
		if _ground_t <= 0.0:
			_ground_t = 0.1
			_ground_h = _probe_ground()
	else:
		_ground_h = INF
	if _contact > 0.0 and grounded and not wall_run:
		_plant_feet(dt)
	else:
		_plant.clear()
		_foot_last.clear()
		_foot_mode.clear()
		_hip_drop = move_toward(_hip_drop, 0.0, dt * 1.5)


const GETUP_TIME := 1.05


## Ground: idle → walk → jog → sprint. The feet are placed in the world by
## the Gait (src/player/gait.gd): stance feet locked where they touched down,
## swing feet flying to a landing spot predicted from the real velocity, the
## clock running at a cadence picked from the speed. The legs are solved onto
## those feet in _plant_feet; here the rest of the body is driven from the
## same clock – the pelvis turns with the leg swinging through, drops toward
## the swinging side and shifts over the stance foot (walking), the shoulders
## counter-rotate, the arms swing against the legs (loose and nearly straight
## walking, pumping at ~90° running), the head stays level and steady.
## Returns the pelvis height offset (bob, crouch, landing squash).
func _pose_ground(q: Dictionary, dt: float, hs: float, la: Vector3) -> float:
	var g := _gait
	var space := get_world_3d().direct_space_state
	var ground := func(at: Vector3) -> Dictionary: return _ground_hit(space, at, 2.2)
	var hips_w := {"l": (bones["thigh_l"] as Node3D).global_position, "r": (bones["thigh_r"] as Node3D).global_position}
	if not g.active:
		var ank := {}
		for sd in ["l", "r"]:
			ank[sd] = _plant[sd][0] if _plant.has(sd) else (bones["foot_" + sd] as Node3D).global_position
		g.begin(ank, _facing, ground, player.s.velocity)
	var run0 := g.run
	var crouch := (0.012 + 0.038 * run0 + 0.018 * g.sprint) * clampf(hs / 1.2, 0.0, 1.0)
	var td := g.touchdowns
	g.update(dt, player.s.velocity, _facing, player.global_position, hips_w, ground, crouch)
	if g.touchdowns != td:
		footstep.emit(g.last_touchdown)
	_gait_live = true
	var run := g.run
	var spr := g.sprint
	# Gait amplitude: eases in on the first step and out as the body stops.
	_gait_amp = move_toward(_gait_amp, clampf(hs / 1.1, 0.0, 1.0) if g.moving else 0.0, dt * 3.5)
	var amp := _gait_amp
	var walk := 1.0 - run
	var lf := g.left_forward()  # +1 left leg forward … -1 right leg forward
	var fl: Gait.Foot = g.feet["l"]
	var fr: Gait.Foot = g.feet["r"]
	var sw_l := 0.0 if fl.planted else sin(PI * fl.w)
	var sw_r := 0.0 if fr.planted else sin(PI * fr.w)
	var ps := g.step_phase()
	var brake := clampf(la.z * 0.03, 0.0, 0.5) * clampf(hs / 3.0, 0.0, 1.0)
	var push := clampf(-la.z * 0.02, 0.0, 0.3) * (1.0 - spr)  # pulling away: weight forward
	var pitch := asin(clampf(global_basis.y.normalized().dot(_facing), -0.6, 0.6))

	# --- pelvis: vertical rhythm, turn, list and side shift -----------------
	# Walking the hips vault over the stance leg (highest mid-stance, lowest
	# as the feet change); running they sink into the stance and rise in
	# flight. Kept small: the body glides, it doesn't bounce.
	var duty2 := minf(g.duty * 2.0, 1.0)
	var bob_w := 0.018 * cos(TAU * (ps - 0.32)) - 0.018
	var bob_r := -0.026 * cos(TAU * (ps - duty2 * 0.5)) - 0.012
	var bob := lerpf(bob_w, bob_r, run) * amp
	var hip_yaw := (0.09 + 0.04 * run - 0.03 * spr) * amp
	var list := (sw_l - sw_r) * (0.055 * walk + 0.02 * run) * amp
	_hip_shift = (sw_l - sw_r) * 0.022 * walk * amp
	q["hips"] = _ry(-lf * hip_yaw) * _rz(list)
	# --- torso ---------------------------------------------------------------
	# Forward bend (+ = forward; torso bones tilt back on +X): runners lean a
	# little from the hips on top of the ankle lean; pulling away the weight
	# goes forward, braking it sits back; landing folds.
	var lean := (0.02 * walk + 0.07 * run + 0.05 * spr) * amp + push * 0.5 + _land_squash * 0.45 - brake * 0.4
	var sh_yaw := (0.1 + 0.08 * run) * amp
	q["spine"] = _rx(-lean * 0.55) * _ry(lf * hip_yaw * 0.6) * _rz(-list * 0.8)
	q["chest"] = _rx(-lean * 0.45 + 0.03 * walk) * _ry(lf * (hip_yaw * 0.4 + sh_yaw)) \
		* _rz(-list * 0.4 + lf * 0.03 * run * amp)
	# Head steady: undo the shoulders' turn and the body's lean; a small nod
	# to the step walking.
	q["neck"] = _ry(-lf * sh_yaw * 0.6)
	q["head"] = _ry(-lf * sh_yaw * 0.4) * _rx(lean * 0.85 + pitch * 0.8 + 0.02 + 0.012 * walk * amp * sin(TAU * ps)) \
		* _rz(list * 0.6)
	# --- arms ------------------------------------------------------------------
	# Opposite arm to leg, from the shoulder. Walking: loose, the elbow only
	# softly bent (it flexes a little as the arm comes forward). Running: the
	# elbow holds ~80–90°, opening on the back swing and closing coming
	# through, the hand travelling hip → chest toward the midline.
	var a_amp := (lerpf(0.3, 0.55, run) + 0.3 * spr) * amp
	var a_base := lerpf(0.02, -0.1, run) * amp
	for sd in ["l", "r"]:
		var sdg := 1.0 if sd == "r" else -1.0
		var fwd := lf * sdg  # this arm forward when the opposite leg is
		var arm := a_base + fwd * a_amp
		var fwd_n := maxf(fwd, 0.0)
		var back_n := maxf(-fwd, 0.0)
		var abd := (0.11 + 0.03 * run - 0.07 * run * fwd_n) * sdg
		q["upper_arm_" + sd] = _rx(arm) * _rz(abd) * _ry(-0.18 * sdg)
		var elbow_w := 0.2 + 0.2 * fwd_n * amp
		var elbow_r := 1.3 + 0.15 * spr + 0.25 * fwd_n - 0.3 * back_n
		q["forearm_" + sd] = _rx(lerpf(elbow_w, elbow_r, run * amp) + 0.12 * amp * walk)
		if brake > 0.05:
			# Braking: arms come forward and out to balance the backward lean.
			# (Elbows bent – balancing, not reaching.)
			var bk := clampf(brake * 1.8, 0.0, 0.7)
			q["upper_arm_" + sd] = (q["upper_arm_" + sd] as Quaternion).slerp(_rx(0.4) * _rz(0.35 * sdg) * _ry(-0.2 * sdg), bk)
			q["forearm_" + sd] = (q["forearm_" + sd] as Quaternion).slerp(_rx(1.0), bk)
		if _land_squash > 0.01:
			# Landing: arms come forward to balance the folding hips.
			var ls := clampf(_land_squash * 1.6, 0.0, 1.0)
			q["upper_arm_" + sd] = (q["upper_arm_" + sd] as Quaternion).slerp(_rx(0.85) * _rz(0.4 * sdg), ls)
			q["forearm_" + sd] = (q["forearm_" + sd] as Quaternion).slerp(_rx(0.7), ls)
	# Legs are solved onto the gait's feet in _plant_feet; hold the current
	# pose here so the springs don't fight it.
	for b in ["thigh_l", "thigh_r", "shin_l", "shin_r", "foot_l", "foot_r"]:
		q[b] = _rot[b]
	if amp < 0.35:
		_idle_pose(q, 1.0 - amp / 0.35, dt)
	else:
		_idle_reset()
	_standing = not g.moving
	if stumble_t > 0.0:
		var u := 1.0 - stumble_t / STUMBLE_TIME
		var e := sin(PI * minf(u * 1.4, 1.0)) * _stumble_k
		var sd2 := _stumble_side
		q["spine"] = (q["spine"] as Quaternion) * _rz(0.16 * sd2 * e) * _rx(0.05 * e)
		q["chest"] = (q["chest"] as Quaternion) * _rz(0.1 * sd2 * e)
		q["head"] = (q["head"] as Quaternion) * _rz(-0.14 * sd2 * e)
		for sd in ["l", "r"]:
			var sg := 1.0 if sd == "r" else -1.0
			# The arm on the falling side reaches out further.
			var reach := 0.75 + 0.35 * maxf(sg * sd2, 0.0)
			q["upper_arm_" + sd] = (q["upper_arm_" + sd] as Quaternion).slerp(_rz(sg * reach) * _rx(0.25), e)
			q["forearm_" + sd] = (q["forearm_" + sd] as Quaternion).slerp(_rx(0.35), e)
	# Turning: the head leads toward where the stick points, the chest
	# follows a little – the body visibly decides before it goes.
	var mvd := Vector3(player.controls.move.x, 0.0, player.controls.move.z)
	if mvd.length() > 0.2:
		var lead := clampf(_facing.signed_angle_to(mvd.normalized(), Vector3.UP), -1.0, 1.0)
		q["head"] = _ry(lead * 0.5) * (q["head"] as Quaternion)
		q["neck"] = _ry(lead * 0.15) * (q["neck"] as Quaternion)
		q["chest"] = _ry(lead * 0.12) * (q["chest"] as Quaternion)
	return bob - crouch - _land_squash * 0.18 - push * 0.03 - _idle_sink


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
	# (Not while swinging forward fast: that arm is out as a wing.)
	var two_hands := attached and L > 0.75 and _glide_rope < 0.4
	_lgrip = move_toward(_lgrip, 1.0 if two_hands else 0.0, dt * (3.0 if two_hands else 2.0))
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
	# Line still flying out, or out but slack: nothing is holding the body
	# yet, so it keeps flying (the airborne poses) with only the web arm
	# reaching up the line; the hang takes over as the line comes taut.
	var free := 1.0 - clampf(L * 3.0, 0.0, 1.0)
	if free > 0.01:
		var qa := {}
		for b in BONES:
			qa[b] = Quaternion.IDENTITY
		_pose_air(qa, s.velocity, speed, la, 0.0, twist)
		for b in BONES:
			if b == "upper_arm_r" or b == "forearm_r" or (b.ends_with("_l") and b.contains("arm") and _lgrip > 0.01):
				continue
			q[b] = (q[b] as Quaternion).slerp(qa[b], free * 0.85)
	if attached:
		# The swing has a rhythm, read from the body's real motion: on the way
		# down the body opens and the legs trail long (one knee folded – the
		# lead leg alternates web to web, so no two swings look the same);
		# through the fast bottom of the arc the legs swing through into a
		# loose pike; on the way up the knees drive forward and up into the
		# release (a gymnast's kip) while the free hand reaches ahead for the
		# next web. Turning, the legs swing out wide of the turn.
		var vy := s.velocity.y
		var taut := clampf(L * 1.4, 0.0, 1.0)
		var down := clampf(-vy / 9.0, 0.0, 1.0) * taut
		var up := clampf(vy / 9.0, 0.0, 1.0) * taut
		var fast := clampf((speed - 12.0) / 20.0, 0.0, 1.0)
		var bottom := (1.0 - clampf(absf(vy) / 7.0, 0.0, 1.0)) * taut * (0.75 + 0.25 * fast)
		var ld := _swing_lead
		var tr := "r" if ld == "l" else "l"
		var sg := {"l": -1.0, "r": 1.0}
		_put(q, {
			"thigh_" + ld: _rx(-0.12) * _rz(0.06 * sg[ld]), "thigh_" + tr: _rx(-0.34 - 0.12 * fast) * _rz(0.04 * sg[tr]),
			"shin_" + ld: _rx(-1.05 - 0.2 * fast), "shin_" + tr: _rx(-0.2), "foot_" + ld: _rx(-0.35), "foot_" + tr: _rx(-0.6),
		}, down * 0.85)
		_put(q, {
			"thigh_" + ld: _rx(0.75) * _rz(0.06 * sg[ld]), "thigh_" + tr: _rx(0.42) * _rz(0.05 * sg[tr]),
			"shin_" + ld: _rx(-0.95), "shin_" + tr: _rx(-0.4), "foot_" + ld: _rx(-0.3), "foot_" + tr: _rx(-0.45),
		}, bottom)
		_put(q, {
			"thigh_" + ld: _rx(1.2) * _rz(0.08 * sg[ld]), "thigh_" + tr: _rx(0.72) * _rz(0.06 * sg[tr]),
			"shin_" + ld: _rx(-1.25), "shin_" + tr: _rx(-0.6), "foot_" + ld: _rx(-0.2), "foot_" + tr: _rx(-0.35),
		}, up * 0.9)
		# Centrifugal swing-out: the hips and legs are flung to the outside
		# of a turn (twist follows the yaw rate).
		for sd in ["l", "r"]:
			q["thigh_" + sd] = _rz(-twist * 0.45) * q["thigh_" + sd]
		q["hips"] = q["hips"] * _rz(-twist * 0.2)
		q["spine"] = q["spine"] * _rx(0.16 * down - 0.1 * bottom - 0.18 * up)
		q["head"] = q["head"] * _rx(0.18 * up - 0.06 * down)
		if _lgrip < 0.5:
			# Free hand: out wide for balance on the way down, reaching ahead
			# and up toward the next anchor on the way up.
			var reach_up := up * (1.0 - _lgrip * 2.0)
			var ru := _rx(2.1) * _rz(-0.45)
			var rf := _rx(0.45)
			var tg := player.targeting
			if tg and tg.pick_ok:
				# Toward the web it would actually take next (above the line
				# of travel), not just "up".
				var sh_l := (bones["upper_arm_l"] as Node3D).global_position
				var dn := (tg.pick - sh_l).normalized()
				if dn.y > -0.2:
					var ik_n := _two_bone(chest_basis, dn, 0.5, Vector3(-0.75, -0.2, 0.6))
					ru = ik_n[0]
					rf = ik_n[1]
			q["upper_arm_l"] = (q["upper_arm_l"] as Quaternion).slerp(ru, reach_up * 0.75)
			q["forearm_l"] = (q["forearm_l"] as Quaternion).slerp(rf, reach_up * 0.75)
	# Swinging forward: the body leans into the arc (see the body lean in
	# _update_animated), chest out, head up toward where it's going, and the
	# free arm spreads out wide and a little back like a wing – dipping or
	# lifting with the turn.
	var gw := _glide_rope * (1.0 - _lgrip)
	if gw > 0.01:
		var flap := sin(_time * 2.3) * 0.05
		q["upper_arm_l"] = (q["upper_arm_l"] as Quaternion).slerp(_rz(-1.28 - _turn * 0.3 - flap) * _rx(-0.5) * _ry(0.4), gw * 0.9)
		q["forearm_l"] = (q["forearm_l"] as Quaternion).slerp(_rx(0.3), gw * 0.9)
		q["chest"] = (q["chest"] as Quaternion) * _rx(0.08 * _glide_rope)
		q["head"] = (q["head"] as Quaternion) * _rx(0.22 * _glide_rope) * _ry(-_turn * 0.3)


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
	# The bend plane comes from the pole (p ⊥ d), not from the lower bone's
	# offset: identical while the limb is bent, and still defined when it's
	# straight (a planted leg at full stretch, a sprint's trailing leg),
	# where the offset is numerical noise and the thigh twisted ~70° in a frame.
	var y := -u
	var z := bend_dir * (p - u * p.dot(u))
	z = z.normalized() if z.length_squared() > 1e-8 else Vector3.BACK
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
	if _gait_live:
		_plant_gait(dt)
		return
	var space := get_world_3d().direct_space_state
	var hips := bones["hips"] as Node3D
	var targets := {}
	var normals := {}
	var drop := -1.0
	# (Rising out of a crouch counts: the last part of a hard landing / get-up.)
	if not _standing or _hard_t > HARD_TIME * 0.4 or _getup_t > GETUP_TIME * 0.3:
		_settle.clear()
	elif _settle.is_empty() and _plant.size() == 2:
		# Standing with a foot left out of place (after a landing, a stop or
		# a turn on the spot): step it back under the hips, one foot at a time.
		var worst := ""
		var far := SETTLE_DIST
		for sd in ["l", "r"]:
			var fk0 := (bones["foot_" + sd] as Node3D).global_position
			var lp0: Vector3 = _plant[sd][0]
			var off := Vector2(lp0.x - fk0.x, lp0.z - fk0.z).length()
			if off > far:
				far = off
				worst = sd
		if worst != "":
			_settle[worst] = [0.0, _plant[worst][0]]
			_plant.erase(worst)
	for sd in ["l", "r"]:
		var foot := bones["foot_" + sd] as Node3D
		var fk := foot.global_position
		var hip := (bones["thigh_" + sd] as Node3D).global_position
		var w: float = _stance_w[sd]
		var hit := _ground_hit(space, fk)
		var desired := fk
		var n := Vector3.UP
		if _settle.has(sd):
			# Settle step: lift, carry and set the foot down at its rest spot.
			var st: Array = _settle[sd]
			st[0] = minf(float(st[0]) + dt / SETTLE_TIME, 1.0)
			var e := smoothstep(0.0, 1.0, st[0])
			var gy: float = (hit.position as Vector3).y + ANKLE_H if not hit.is_empty() else (st[1] as Vector3).y
			var rest := Vector3(fk.x, gy, fk.z)
			desired = (st[1] as Vector3).lerp(rest, e) + Vector3.UP * sin(PI * st[0]) * 0.07
			_toe[sd] = sin(PI * st[0]) * 0.25
			if st[0] >= 1.0:
				_settle.erase(sd)
				_plant[sd] = [rest, hit.normal if not hit.is_empty() else Vector3.UP]
			w = -2.0  # neither planted nor reaching for the ground
		elif w >= 0.0 and _plant.has(sd):
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
			var f := _plant_heading(sd, n)
			var toe: float = _toe[sd]
			desired = _roll(lock, f, n, toe)
			# Out of reach with the gait's heel roll: the hips sink (knees
			# flex) rather than the foot rising onto tiptoe mid-stance; the
			# heel only lifts further for what the hips haven't caught yet.
			drop = maxf(drop, desired.distance_to(hip) - (LEG_LEN - 0.005))
			while not _standing and toe < 1.1 and desired.distance_to(hip) > LEG_LEN - 0.01:
				toe += 0.06
				desired = _roll(lock, f, n, toe)
			_toe[sd] = toe
		elif w > -2.0:
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
			# A planted foot settles onto the ground quickly and never hovers
			# visibly while the rest of a re-plant jump eases out.
			fo.y = clampf(fo.y * exp(-24.0 * dt), -0.02, 0.02)
		_foot_off[sd] = fo
		var tgt: Vector3 = desired + _foot_off[sd]
		targets[sd] = tgt
		normals[sd] = n
	_hip_drop = lerpf(_hip_drop, clampf(_hip_drop + drop, 0.0, 0.3), 1.0 - exp(-20.0 * dt))
	var hb := hips.global_basis.orthonormalized()
	var wik := _contact
	for sd in ["l", "r"]:
		var hip := (bones["thigh_" + sd] as Node3D).global_position
		var tgt: Vector3 = targets[sd]
		_foot_last[sd] = tgt
		var d := tgt - hip
		var side := 0.12 if sd == "r" else -0.12
		var ik := _two_bone(hb, d.normalized(), d.length(), Vector3(side, 0.0, -1.0), 0.45, 0.44, -1.0)
		_set_bone("thigh_" + sd, (_rot["thigh_" + sd] as Quaternion).slerp(ik[0], wik))
		_set_bone("shin_" + sd, (_rot["shin_" + sd] as Quaternion).slerp(ik[1], wik))
		# The sole settles onto the ground over a few frames at touchdown
		# (and peels off at lift-off) instead of snapping flat.
		var on: bool = _plant.has(sd) or _stance_w[sd] >= 0.0
		_flat[sd] = move_toward(_flat[sd], 1.0 if on else 0.0, dt * (16.0 if on else 10.0))
		if _flat[sd] > 0.0:
			# Sole on the ground plane, toes along the facing, heel rolled up.
			var n: Vector3 = normals[sd]
			var f := _plant_heading(sd, n) if _plant.has(sd) else (_facing - n * _facing.dot(n)).normalized()
			if f.length_squared() < 0.5:
				continue
			var want := Basis.looking_at(f, n) * Basis(Vector3.RIGHT, _heel[sd] - _toe[sd])
			var shin_b := (bones["shin_" + sd] as Node3D).global_basis.orthonormalized()
			var local := (shin_b.inverse() * want).get_rotation_quaternion()
			_set_bone("foot_" + sd, (_rot["foot_" + sd] as Quaternion).slerp(local, wik * _flat[sd]))


## Locomotion: the legs are solved onto the Gait's feet (world positions),
## and the feet are oriented on the ground (planted: heading, heel strike,
## toe-off roll) or in the air (swing pitch). The hips sink if a planted foot
## would be out of reach. Mirrors the gait into _plant/_stance_w/_toe so
## audits and the other poses read one convention.
func _plant_gait(dt: float) -> void:
	var g := _gait
	var hips := bones["hips"] as Node3D
	var drop := -1.0
	_plant.clear()
	for sd in ["l", "r"]:
		var f: Gait.Foot = g.feet[sd]
		var hip := (bones["thigh_" + sd] as Node3D).global_position
		if f.planted:
			_plant[sd] = [f.pos, f.normal, f.heading]
			_stance_w[sd] = f.stance_u
			drop = maxf(drop, f.out.distance_to(hip) - (LEG_LEN - 0.005))
		else:
			_swing_w[sd] = f.w
			if f.w > 0.15 and f.w < 0.85:
				_lead = sd  # the knee coming through leads if we jump now
			# The hips settle ahead of a touchdown the leg could only just
			# reach (stepping down a kerb, a long stride) – never after it.
			if f.w > 0.55 and not f.settle:
				var down := Vector3(f.out.x, minf(f.out.y, f.target.y), f.out.z)
				drop = maxf(drop, (down.distance_to(hip) - (LEG_LEN - 0.005)) * smoothstep(0.55, 0.9, f.w))
		_toe[sd] = f.toe
		_heel[sd] = f.heel
		_foot_mode[sd] = f.pos if f.planted else null
		_foot_off[sd] = Vector3.ZERO
	_hip_drop = lerpf(_hip_drop, clampf(_hip_drop + drop, 0.0, 0.3), 1.0 - exp(-20.0 * dt))
	var hb := hips.global_basis.orthonormalized()
	for sd in ["l", "r"]:
		var f: Gait.Foot = g.feet[sd]
		# A planted leg is solved at full weight (fading the IK in would drag
		# the foot across the ground); a swinging one fades in from the air
		# pose as contact comes in (landing), so the legs never pop.
		var wik := 1.0 if f.planted else _contact
		var hip := (bones["thigh_" + sd] as Node3D).global_position
		var tgt := f.out
		_foot_last[sd] = tgt
		var d := tgt - hip
		var side := 0.12 if sd == "r" else -0.12
		var ik := _two_bone(hb, d.normalized(), d.length(), Vector3(side, 0.0, -1.0), 0.45, 0.44, -1.0)
		var th: Quaternion = ik[0]
		if not f.planted:
			# A swing leg never reaches back past the hip's range (a hard
			# reversal can leave the lifting foot far behind).
			var td := th * Vector3.DOWN
			var back := atan2(td.z, -td.y)
			if back > 0.82 and td.y < 0.0:
				th = Quaternion(Vector3.RIGHT, back - 0.82) * th
		_set_bone("thigh_" + sd, (_rot["thigh_" + sd] as Quaternion).slerp(th, wik))
		var sh: Quaternion = ik[1]
		if not f.planted and sh.get_angle() > 2.55:
			sh = _rx(-2.55)  # heel kick: the calf meets the hamstring (~145°)
		_set_bone("shin_" + sd, (_rot["shin_" + sd] as Quaternion).slerp(sh, wik))
		var want: Basis
		if f.planted:
			var n := f.normal
			var fh := (f.heading - n * f.heading.dot(n)).normalized()
			if fh.length_squared() < 0.5:
				continue
			want = Basis.looking_at(fh, n) * Basis(Vector3.RIGHT, f.heel - f.toe)
		else:
			var fh := Vector3(f.heading.x, 0.0, f.heading.z).normalized()
			if fh.length_squared() < 0.5:
				continue
			want = Basis.looking_at(fh, Vector3.UP) * Basis(Vector3.RIGHT, f.pitch)
		var shin_b := (bones["shin_" + sd] as Node3D).global_basis.orthonormalized()
		var local := (shin_b.inverse() * want).get_rotation_quaternion()
		if not f.planted and f.world_k < 1.0:
			# Mid-swing: relaxed on the shin, toes a little pointed.
			local = _rx(-0.3 - 0.15 * _gait.run).slerp(local, f.world_k)
		# Ankle range: in the air ~65° pointed, ~45° flexed, a little roll; a
		# planted sole gets more (it must lie on the ground through a deep
		# landing) but never twists round under the shin.
		var eu := local.get_euler()
		if f.planted:
			local = Quaternion.from_euler(Vector3(eu.x, clampf(eu.y, -0.55, 0.55), clampf(eu.z, -0.45, 0.45)))
		else:
			local = Quaternion.from_euler(Vector3(clampf(eu.x, -1.13, 0.8), clampf(eu.y, -0.3, 0.3), clampf(eu.z, -0.3, 0.3)))
		_set_bone("foot_" + sd, (_rot["foot_" + sd] as Quaternion).slerp(local, wik))


## Crouched poses (hard landing): both feet stay planted where they
## touched down; `trail_toe` rolls the trailing foot onto its toes. While a
## three-point landing is still folding down, the trailing foot slides back
## with the dropping knee before it locks.
func _plant_both(trail_toe: float) -> void:
	_standing = true
	for sd in ["l", "r"]:
		_stance_w[sd] = 0.5
		_toe[sd] = trail_toe if sd != _hard_lead else 0.0
	if _hard_t > HARD_TIME * 0.8:
		# Folding into a three-point landing: the trailing knee drops toward
		# the ground, so its foot goes back behind the hips (onto its toes).
		var tr := "r" if _hard_lead == "l" else "l"
		var hip := (bones["thigh_" + tr] as Node3D).global_position
		var back := hip - _facing * 0.4
		_plant[tr] = [Vector3(back.x, player.global_position.y - 0.9 + ANKLE_H, back.z), Vector3.UP]


## Heading of a planted foot: it keeps the direction it landed in while the
## body turns over it, pivoting on the ball only when the twist would pass
## ~35° (no feet spinning flat on the ground through a turn).
func _plant_heading(sd: String, n: Vector3) -> Vector3:
	var face := (_facing - n * _facing.dot(n)).normalized()
	var pl: Array = _plant[sd]
	if pl.size() < 3:
		pl.append(face)
	var f: Vector3 = pl[2]
	var ang := f.signed_angle_to(face, n)
	if absf(ang) > 0.6:
		f = f.rotated(n, ang - signf(ang) * 0.6)
		pl[2] = f
	return f


## Ankle position with the foot rolled `toe` rad (heel up) about its ball.
static func _roll(ankle: Vector3, f: Vector3, n: Vector3, toe: float) -> Vector3:
	if toe <= 0.0:
		return ankle
	return ankle + n * sin(toe) * BALL + f * (1.0 - cos(toe)) * BALL


const GUARD_MASK := 1 | (1 << 1) | (1 << 3) | (1 << 4)  # buildings, street, props
const LIMB_MARGIN := 0.045  # m kept between a limb's surface and the world
const GUARD_W := 18.0  # 1/s: how briskly a fold comes in and eases off


## The last word on every pose (animated or ragdoll): no hand, elbow, foot,
## knee or the head may end a frame inside the world. A limb that would is
## folded back with two-bone IK so its end rests on the surface it met, the
## joint bending away from it – a hand meeting a wall lands flat on it.
func _guard_limbs() -> void:
	if player == null or not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = GUARD_MASK
	q.exclude = [player.get_rid()]
	var chest := bones["chest"] as Node3D
	var hips := bones["hips"] as Node3D
	var dt := get_process_delta_time()
	for sd in ["l", "r"]:
		var sgn := -1.0 if sd == "l" else 1.0
		# The web hand stays on the line (the drawn web bends round edges instead).
		if not (sd == "r" and player.line_state != Player.Line.IDLE and not ragdolling):
			_guard_chain(space, q, chest, "upper_arm_" + sd, "forearm_" + sd, "hand_" + sd, 0.29, 0.26,
				Vector3(0, -0.12, 0), 1.0, false, Vector3(0.75 * sgn, -0.2, 0.6), dt)
		# Feet stand on floors (foot IK owns that): legs are only kept out of
		# walls, and a planted leg is left to the foot IK.
		if (_contact < 0.5 and _getup_t <= 0.0) or ragdolling:
			_guard_chain(space, q, hips, "thigh_" + sd, "shin_" + sd, "foot_" + sd, 0.45, 0.44,
				Vector3(0, -0.04, -0.17), -1.0, true, Vector3(0.12 * sgn, 0.0, -1.0), dt)
	# The head: tipped back toward the chest if it would go through something.
	var neck := (bones["neck"] as Node3D).global_position
	var head := bones["head"] as Node3D
	var top := head.global_position + head.global_basis.y.normalized() * 0.24
	q.from = chest.global_position
	q.to = neck
	if space.intersect_ray(q).is_empty():
		q.from = neck
		q.to = top + (top - neck).normalized() * LIMB_MARGIN
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var n: Vector3 = hit["normal"]
			var axis := (top - neck).cross(n).normalized()
			if axis.length_squared() > 0.5:
				var lb := (bones["neck"] as Node3D).global_basis.orthonormalized()
				_set_bone("head", Quaternion(lb.inverse() * axis, 0.6) * (_rot["head"] as Quaternion))


## One limb chain root → mid → end (+ `tip`, the hand/toe in the end bone's
## frame). The limb keeps the direction its pose gives it; only its reach is
## capped by the distance to whatever lies that way, so the joint bends
## smoothly as a wall gets closer (no frame-to-frame jumps) and the end rests
## on the surface. `walls_only` ignores floors.
func _guard_chain(space: PhysicsDirectSpaceState3D, q: PhysicsRayQueryParameters3D, parent: Node3D, a: String,
		b: String, c: String, la: float, lb: float, tip_local: Vector3, bend: float, walls_only: bool,
		pole: Vector3, _dt: float) -> void:
	var root := (bones[a] as Node3D).global_position
	q.from = parent.global_position
	q.to = root
	if not space.intersect_ray(q).is_empty():
		return  # the root itself is past a surface: nothing a limb fold can do
	var end_n := bones[c] as Node3D
	var tip_p := end_n.global_position + end_n.global_basis.orthonormalized() * tip_local
	var tip := tip_local.length()
	var pb := parent.global_basis.orthonormalized()
	var d := tip_p - root
	var length := d.length()
	if length < 0.05:
		return
	var dir := d / length
	# Along the limb's line (a little past its end, for the margin).
	var hit := _seg_hit(space, q, root, tip_p, walls_only)
	var reach := length
	var n := Vector3.ZERO
	if not hit.is_empty():
		n = hit["normal"]
		var along := ((hit["position"] as Vector3) - root).dot(dir)
		reach = along - LIMB_MARGIN / maxf(-n.dot(dir), 0.25)
	# The bent joint can poke out sideways even when the line is clear.
	var mid := (bones[b] as Node3D).global_position
	var mh := _seg_hit(space, q, root, mid, walls_only)
	if mh.is_empty():
		mh = _seg_hit(space, q, mid, end_n.global_position, walls_only)
	if hit.is_empty() and mh.is_empty():
		_ease_guard(a, b, Quaternion.IDENTITY, Quaternion.IDENTITY, 0.0, _dt)
		return
	if n == Vector3.ZERO:
		n = mh["normal"]
	var min_reach := (0.16 if bend > 0.0 else 0.28) + tip
	reach = clampf(reach, min_reach, length)
	var fold := 1.0 - (reach - min_reach) / maxf(length - min_reach, 0.01)
	var ik := _two_bone(pb, dir, maxf(reach - tip, 0.06), pole + pb.inverse() * n * (0.3 + 0.5 * fold), la, lb, bend)
	_ease_guard(a, b, ik[0], ik[1], 1.0, _dt)


## Shows a fold (want 1) or the plain pose (want 0). The fold is an offset
## on top of the pose, driven by a critically damped spring: a limb swung
## fast into a wall folds within a few frames and eases back out the same
## way, with no jolt in its motion. Display only – the animation and its
## springs carry on from the clean pose.
func _ease_guard(a: String, b: String, ia: Quaternion, ib: Quaternion, want: float, dt: float) -> void:
	var st: Array = _guard_off.get(a, [])
	if st.is_empty():
		if want <= 0.0:
			return
		st = [Quaternion.IDENTITY, Vector3.ZERO, Quaternion.IDENTITY, Vector3.ZERO]
	var idle := true
	for k in 2:
		var bone := a if k == 0 else b
		var pose: Quaternion = _rot[bone]
		var goal := ((ia if k == 0 else ib) * pose.inverse()) if want > 0.0 else Quaternion.IDENTITY
		var off: Quaternion = st[k * 2]
		var vel: Vector3 = st[k * 2 + 1]
		var dq := goal * off.inverse()
		if dq.w < 0.0:
			dq = -dq
		var ang := dq.get_angle()
		var err := dq.get_axis() * ang if ang > 1e-5 else Vector3.ZERO
		vel += (err * GUARD_W * GUARD_W - vel * 2.0 * GUARD_W) * dt
		if vel.length() > 1e-6:
			off = (Quaternion(vel.normalized(), vel.length() * dt) * off).normalized()
		st[k * 2] = off
		st[k * 2 + 1] = vel
		(bones[bone] as Node3D).quaternion = off * pose
		if off.get_angle() > 0.005 or vel.length() > 0.05:
			idle = false
	if want <= 0.0 and idle:
		_guard_off.erase(a)
	else:
		_guard_off[a] = st


func _chain_hit(space: PhysicsDirectSpaceState3D, q: PhysicsRayQueryParameters3D, a: String, b: String, c: String,
		tip_local: Vector3, walls_only: bool) -> Dictionary:
	var root := (bones[a] as Node3D).global_position
	var mid := (bones[b] as Node3D).global_position
	var en := bones[c] as Node3D
	var tip_p := en.global_position + en.global_basis.orthonormalized() * tip_local
	var h := _seg_hit(space, q, root, mid, walls_only)
	if h.is_empty():
		h = _seg_hit(space, q, mid, en.global_position, walls_only)
	if h.is_empty():
		h = _seg_hit(space, q, en.global_position, tip_p, walls_only)
	return h


func _seg_hit(space: PhysicsDirectSpaceState3D, q: PhysicsRayQueryParameters3D, from: Vector3, to: Vector3,
		walls_only := false) -> Dictionary:
	var d := to - from
	if d.length_squared() < 1e-8:
		return {}
	q.from = from
	q.to = to + d.normalized() * LIMB_MARGIN
	var hit := space.intersect_ray(q)
	if walls_only and not hit.is_empty() and (hit["normal"] as Vector3).y > 0.6:
		return {}
	return hit


func _set_bone(b: String, qq: Quaternion) -> void:
	_rot[b] = qq
	(bones[b] as Node3D).quaternion = qq


func _ground_hit(space: PhysicsDirectSpaceState3D, at: Vector3, down := 0.7) -> Dictionary:
	var rq := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * down, player.collision_mask)
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
		"spine": _rx(-0.1) * _ry(twist * 0.3), "chest": _rx(0.0), "neck": _rx(0.0), "head": _rx(0.08),
		# Upper arms out, twisted so the elbows bend the hands up (not forward).
		"upper_arm_" + ld: _rz(1.15 * sg[ld] + drift * 0.04) * _ry(-1.2 * sg[ld]) * _rx(0.1 + react),
		"upper_arm_" + tr: _rz(1.05 * sg[tr] - drift * 0.04) * _ry(-1.2 * sg[tr]) * _rx(0.2 + react),
		"forearm_" + ld: _rx(0.95), "forearm_" + tr: _rx(1.05),
		"thigh_" + ld: _rx(1.05) * _rz(0.06 * sg[ld]), "thigh_" + tr: _rx(0.6) * _rz(0.08 * sg[tr]),
		"shin_" + ld: _rx(-1.45), "shin_" + tr: _rx(-1.25), "foot_" + ld: _rx(-0.2), "foot_" + tr: _rx(-0.35),
	}, 1.0)
	# Rising: still in the stride of the take-off – lead knee up, trailing
	# leg long behind with the toes pointed, chest up, arms carried high.
	_put(q, {
		"spine": _rx(0.06) * _ry(twist * 0.3), "chest": _rx(0.08), "head": _rx(0.06),
		"upper_arm_" + tr: _rx(2.45) * _rz(0.3 * sg[tr]), "forearm_" + tr: _rx(0.45),
		"upper_arm_" + ld: _rx(-0.45) * _rz(0.45 * sg[ld]), "forearm_" + ld: _rx(0.85),
		"thigh_" + ld: _rx(1.15) * _rz(0.04 * sg[ld]), "thigh_" + tr: _rx(-0.3) * _rz(0.04 * sg[tr]),
		"shin_" + ld: _rx(-1.3), "shin_" + tr: _rx(-0.55), "foot_" + ld: _rx(-0.1), "foot_" + tr: _rx(-0.6),
	}, rising * clampf(1.2 - _jump_t * 0.8, 0.0, 1.0) if _jump_t < 2.0 else rising * 0.4)
	# Falling: legs open and reach down (one a little ahead), arms rise up
	# and out for balance with the elbows bent – never a T-pose.
	_put(q, {
		"spine": _rx(0.04), "chest": _rx(0.0), "head": _rx(0.15),
		"upper_arm_" + ld: _rz(1.35 * sg[ld] + drift * 0.08 * sg[ld]) * _ry(-1.1 * sg[ld]) * _rx(0.1),
		"upper_arm_" + tr: _rz(1.3 * sg[tr] - drift * 0.08 * sg[tr]) * _ry(-1.1 * sg[tr]) * _rx(0.0),
		"forearm_" + ld: _rx(1.1), "forearm_" + tr: _rx(1.0),
		# Legs keep moving: a slow, loose cycle with bent knees (a runner's
		# stride in the air), never two straight posts hanging down.
		"thigh_" + ld: _rx(0.75 + cyc * 0.35) * _rz(0.1 * sg[ld]),
		"thigh_" + tr: _rx(0.3 - cyc * 0.35) * _rz(0.12 * sg[tr]),
		"shin_" + ld: _rx(-1.15 - maxf(cyc, 0.0) * 0.35), "shin_" + tr: _rx(-0.85 - maxf(-cyc, 0.0) * 0.35),
		"foot_" + ld: _rx(-0.2), "foot_" + tr: _rx(-0.35),
	}, falling * (1.0 - sky))
	# Glide: chest out and leading, head up looking where it's going, arms
	# spread wide and a little back like wings (elbows soft, palms down), legs
	# long behind with one knee bent and the toes pointed. Banking, the arms
	# tilt with the turn – the inside wing dips, the outside one lifts – the
	# head looks into it and the legs swing out the other way.
	var tn := _turn
	var flap := sin(_time * 2.3) * 0.05  # the wings ride the air a little
	_put(q, {
		"spine": _rx(0.12) * _ry(-tn * 0.18), "chest": _rx(0.14) * _ry(-tn * 0.15), "neck": _rx(0.1),
		"head": _rx(0.32) * _ry(-tn * 0.4) * _rz(tn * 0.12),
		"upper_arm_l": _rz(-1.28 - tn * 0.35 - flap) * _rx(-0.5) * _ry(0.4),
		"upper_arm_r": _rz(1.28 - tn * 0.35 + flap) * _rx(-0.5) * _ry(-0.4),
		"forearm_l": _rx(0.3 + flap), "forearm_r": _rx(0.3 - flap),
		"thigh_" + ld: _rx(-0.08) * _rz(0.06 * sg[ld] - tn * 0.2),
		"thigh_" + tr: _rx(-0.22) * _rz(0.04 * sg[tr] - tn * 0.2),
		"shin_" + ld: _rx(-0.75), "shin_" + tr: _rx(-0.22), "foot_" + ld: _rx(-0.55), "foot_" + tr: _rx(-0.7),
	}, _glide)
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
		"spine": _rx(-0.18), "chest": _rx(-0.06), "head": _rx(-0.1),
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
	# Swan dive off a building: arms spread wide and a little back, back
	# arched, chin up, legs long and together – closing into the streamline
	# above as the fall gets fast.
	var stream := clampf((speed - 20.0) / 14.0, 0.0, 1.0)
	_put(q, {
		"spine": _rx(0.22), "chest": _rx(0.14), "neck": _rx(0.12), "head": _rx(0.25),
		"upper_arm_l": _rz(-1.45 - drift * 0.05) * _rx(-0.25), "upper_arm_r": _rz(1.45 + drift * 0.05) * _rx(-0.25),
		"forearm_l": _rx(0.2), "forearm_r": _rx(0.2),
		"thigh_l": _rx(-0.08) * _rz(0.02), "thigh_r": _rx(-0.12) * _rz(-0.02),
		"shin_l": _rx(-0.12), "shin_r": _rx(-0.3), "foot_l": _rx(-0.75), "foot_r": _rx(-0.7),
	}, smoothstep(0.0, 1.0, _swan) * (1.0 - stream))
	# Pulling out of the dive: a tuck swings the feet under the body.
	if _swan_peak > 0.3 and _swan < _swan_peak:
		var po := sin(PI * clampf(1.0 - _swan / _swan_peak, 0.0, 1.0))
		_put(q, {
			"spine": _rx(-0.45), "chest": _rx(-0.2), "head": _rx(-0.2),
			"thigh_l": _rx(1.6), "thigh_r": _rx(1.5), "shin_l": _rx(-1.9), "shin_r": _rx(-1.8),
			"upper_arm_l": _rx(0.9) * _rz(-0.35), "upper_arm_r": _rx(0.9) * _rz(0.35),
			"forearm_l": _rx(0.9), "forearm_r": _rx(0.9),
		}, po)


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
func _hard_k() -> float:
	var u := 1.0 - _hard_t / HARD_TIME           # 0 → 1 through the landing
	return smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.55, 1.0, u))


## Three-point landing: in fast, hold, then rise. Returns how far the hips drop.
func _pose_hard_land(q: Dictionary) -> float:
	var k := _hard_k()
	var ld := _hard_lead
	var tr := "r" if ld == "l" else "l"
	var sg := {"l": -1.0, "r": 1.0}
	_put(q, {
		"spine": _rx(-0.6), "chest": _rx(-0.3), "neck": _rx(0.3), "head": _rx(0.45),
		"thigh_" + ld: _rx(1.55) * _rz(0.1 * sg[ld]), "shin_" + ld: _rx(-1.95), "foot_" + ld: _rx(0.4),
		"thigh_" + tr: _rx(0.25) * _rz(0.12 * sg[tr]), "shin_" + tr: _rx(-2.2), "foot_" + tr: _rx(-0.5),
		# Hand on the ground on the trailing side, the other arm swept back.
		"upper_arm_" + tr: _rx(0.15) * _rz(0.2 * sg[tr]), "forearm_" + tr: _rx(0.1),
		"upper_arm_" + ld: _rx(-1.1) * _rz(0.6 * sg[ld]), "forearm_" + ld: _rx(0.35),
	}, k)
	# The trailing hand really touches down, just ahead of and outside the shoulder.
	_hand_to_ground(q, tr, 0.12, 0.08, k)
	return 0.48 * k


## IK a hand onto the ground near its shoulder (`fwd`/`out` metres ahead
## and outward), elbow soft and pointing back; blended in by `k`.
func _hand_to_ground(q: Dictionary, sd: String, fwd: float, out: float, k: float) -> void:
	if k <= 0.001:
		return
	var sg := -1.0 if sd == "l" else 1.0
	var sh := (bones["upper_arm_" + sd] as Node3D).global_position
	var right := Vector3.UP.cross(_facing).normalized() * -1.0
	var palm := Vector3(sh.x, player.global_position.y - 0.9 + 0.06, sh.z) + _facing * fwd + right * sg * out
	var d := palm - sh
	var ik := _two_bone((bones["chest"] as Node3D).global_basis.orthonormalized(), d.normalized(),
		minf(d.length(), 0.53), Vector3(0.4 * sg, 0.0, 0.9))
	q["upper_arm_" + sd] = (q["upper_arm_" + sd] as Quaternion).slerp(ik[0], k)
	q["forearm_" + sd] = (q["forearm_" + sd] as Quaternion).slerp(ik[1], k)


## Get-up progress 0..1 (1 = not getting up).
func _getup_u() -> float:
	return 1.0 - _getup_t / GETUP_TIME if _getup_t > 0.0 else 1.0


## Whole-body pitch through the get-up (+ = forward): face-down it goes
## all fours → crouch → standing; face-up, sitting (leaning back) → rolled
## forward onto the feet → standing.
func _getup_pitch(u: float) -> float:
	var crouch := 0.4
	var start := 1.25 if _getup_down else -0.45
	if u < 0.55:
		return lerpf(start, crouch, smoothstep(0.3, 0.55, u))
	return lerpf(crouch, 0.0, smoothstep(0.65, 1.0, u))


## Rig root height relative to standing through the get-up.
func _getup_height(u: float) -> float:
	var low := -0.42 if _getup_down else -0.8
	if u < 0.55:
		return lerpf(low, -0.4, smoothstep(0.3, 0.55, u))
	return lerpf(-0.4, 0.0, smoothstep(0.6, 1.0, u))


func _pose_getup(q: Dictionary, u: float) -> void:
	var wa := 1.0 - smoothstep(0.3, 0.55, u)                          # on the ground
	var wb := smoothstep(0.3, 0.55, u) * (1.0 - smoothstep(0.65, 1.0, u))  # crouch
	if _getup_down:
		# All fours: thighs straight down to the knees, shins along the
		# ground, arms under the shoulders, head up looking ahead.
		_put(q, {
			"spine": _rx(0.08), "chest": _rx(0.05), "neck": _rx(0.3), "head": _rx(0.45),
			"thigh_l": _rx(1.25) * _rz(-0.1), "thigh_r": _rx(1.3) * _rz(0.1),
			"shin_l": _rx(-1.55), "shin_r": _rx(-1.5), "foot_l": _rx(-0.5), "foot_r": _rx(-0.5),
			"upper_arm_l": _rx(1.2) * _rz(-0.15), "upper_arm_r": _rx(1.2) * _rz(0.15),
			"forearm_l": _rx(0.15), "forearm_r": _rx(0.15),
		}, wa)
		for sd in ["l", "r"]:
			_hand_to_ground(q, sd, 0.05, 0.05, wa)
	else:
		# Sitting up: legs out in front (one knee up), leaning back on the
		# hands behind the hips, chin down.
		_put(q, {
			"spine": _rx(-0.25), "chest": _rx(-0.1), "head": _rx(-0.15),
			"thigh_l": _rx(1.1) * _rz(-0.12), "thigh_r": _rx(1.45) * _rz(0.1),
			"shin_l": _rx(-0.35), "shin_r": _rx(-1.5), "foot_l": _rx(-0.2), "foot_r": _rx(0.25),
			"upper_arm_l": _rx(-0.75) * _rz(-0.3), "upper_arm_r": _rx(-0.75) * _rz(0.3),
			"forearm_l": _rx(0.25), "forearm_r": _rx(0.25),
		}, wa)
		for sd in ["l", "r"]:
			_hand_to_ground(q, sd, -0.18, 0.08, wa)
	# Crouch, weight over the feet, arms forward for balance, then rise.
	_put(q, {
		"spine": _rx(-0.35), "chest": _rx(-0.1), "neck": _rx(0.15), "head": _rx(0.3),
		"thigh_l": _rx(1.7) * _rz(-0.1), "thigh_r": _rx(1.6) * _rz(0.1),
		"shin_l": _rx(-2.0), "shin_r": _rx(-1.9), "foot_l": _rx(0.35), "foot_r": _rx(0.35),
		"upper_arm_l": _rx(0.7) * _rz(-0.3), "upper_arm_r": _rx(0.7) * _rz(0.3),
		"forearm_l": _rx(0.6), "forearm_r": _rx(0.6),
	}, wb)
	if u > 0.5:
		_plant_both(0.0)


func _drive_springs(q: Dictionary, dt: float, rope_arm: bool, grounded := true) -> void:
	# Locomotion cycles run faster than the soft "inertia" springs can follow
	# (a sprint is ~16 rad/s): attenuated, lagging limbs make feet skate. So on
	# the ground limbs follow the cycle exactly (blended in by _loco, which
	# ramps over ~0.17 s), while in the air they stay soft and carry momentum.
	# The web arm is near-rigid so its hand stays on the line.
	# Leaving the ground hands the limbs straight to the springs (their
	# velocity already matches the stride), so a take-off never pops.
	var lw := _loco if grounded else 0.0
	for b in BONES:
		var grp := _group(b)
		if rope_arm and (b == "upper_arm_r" or b == "forearm_r"):
			grp = "rope_arm"
		var k: float = SPRINGS[grp][0]
		var c: float = SPRINGS[grp][1]
		var n := 2 if k < 500.0 else 4
		for i in n:
			_spring(b, q[b], k, c, dt / n)
		if lw > 0.0 and (grp == "leg" or grp == "arm"):
			var prev: Quaternion = _rot[b]
			_rot[b] = prev.slerp(q[b], lw)
			# Keep the spring's velocity consistent with the motion it follows
			# (capped: a pose jump must not fling the limb once springs take over).
			var follow := (_ang_delta(prev, _rot[b]) / maxf(dt, 1e-4)).limit_length(18.0)
			_angvel[b] = (_angvel[b] as Vector3).lerp(follow, lw)
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
	# Protective reflex while dropping toward the ground: the arms reach down
	# and a little forward to break the fall (weakly – still a limp body).
	ragdoll.reach.clear()
	ragdoll.reach_k = 0.0
	var fall_v := player.s.velocity.y
	if not hanging and fall_v < -3.0 and not player.is_on_floor():
		var gh := _probe_ground() if _rag_time < 3.0 else INF
		if gh < 4.0:
			var p: Dictionary = ragdoll.pos
			var fwd := Vector3(player.s.velocity.x, 0.0, player.s.velocity.z).normalized() * 0.25
			for sd in ["l", "r"]:
				var sh: Vector3 = p["sh_" + sd]
				ragdoll.reach["wr_" + sd] = Vector3(sh.x, sh.y - 0.6, sh.z) + fwd
			ragdoll.reach_k = 0.06 * clampf(1.0 - gh / 4.0, 0.2, 1.0)
	ragdoll.update(dt, anchor)
	_pose_from_ragdoll(dt)


## Player decided the body has recovered: springs carry it back to a pose.
func _on_stun_ended() -> void:
	ragdolling = false
	_getup_t = GETUP_TIME if player.is_on_floor() else 0.0
	_flip = 0.0
	_body_basis = global_basis.orthonormalized()
	# How did the body come to rest? Chest to the ground: push up onto hands
	# and knees, facing where the head points. On the back: sit up, then roll
	# forward onto the feet, facing the way the legs lie.
	var head := _body_basis.y
	_getup_down = _body_basis.z.dot(Vector3.UP) > 0.0  # back (+Z) faces the sky
	var f := Vector3(head.x, 0.0, head.z) * (1.0 if _getup_down else -1.0)
	if f.length_squared() > 0.01:
		_facing = f.normalized()
	_getup_off = global_position - player.global_position


func _pose_from_ragdoll(dt: float) -> void:
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
		_aim_limb("upper_arm_" + sd, "forearm_" + sd, basis, (p["el_" + sd] as Vector3) - (p["sh_" + sd] as Vector3),
			(p["wr_" + sd] as Vector3) - (p["el_" + sd] as Vector3), 1.0, dt)
		_aim_limb("thigh_" + sd, "shin_" + sd, basis, (p["kn_" + sd] as Vector3) - (p["hip_" + sd] as Vector3),
			(p["an_" + sd] as Vector3) - (p["kn_" + sd] as Vector3), -1.0, dt)


## Poses a two-bone limb from its segment directions (world) so the middle
## joint stays a pure hinge: the upper bone's roll is chosen so the lower
## bone bends in its own bending plane (elbows toward -Z, knees toward +Z,
## like _two_bone) – a ragdolled knee never comes back twisted sideways.
## The simulation can move a limb a long way in one step (a joint-cone clamp,
## a collision push): the visible limb chases it at no more than this rate.
const RAG_LIMB_RATE := 26.0  # rad/s


func _aim_limb(upper: String, lower: String, parent_basis: Basis, d_up: Vector3, d_low: Vector3, bend_dir: float,
		dt := 1.0 / 60.0) -> void:
	if d_up.length_squared() < 1e-6 or d_low.length_squared() < 1e-6:
		return
	var inv := parent_basis.inverse()
	var u := (inv * d_up).normalized()
	var w := (inv * d_low).normalized()
	# Near straight, the bend plane is ill-defined (it would flip frame to
	# frame): keep the roll the limb already has, and only let the bend
	# steer it once the joint is clearly bent.
	var prev_z := Basis(_rot[upper] as Quaternion).z
	prev_z = prev_z - u * prev_z.dot(u)
	if prev_z.length_squared() < 1e-4:
		prev_z = Vector3.BACK - u * u.z
	var z := -bend_dir * (w - u * w.dot(u))
	var bent := smoothstep(0.08, 0.3, z.length())  # sin of the bend angle
	if z.dot(prev_z.normalized()) < -0.2 * z.length():
		# The simulation mirrored the joint across the limb line (its hinge
		# rule): keep the roll the limb has and bend it the normal way – a
		# hand a few cm off the simulated point instead of a half-turn spin.
		z = prev_z
	z = prev_z.normalized().slerp(z.normalized(), bent) if z.length_squared() > 1e-6 else prev_z.normalized()
	var y := -u
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	var uq := Basis(x, y, z).get_rotation_quaternion()
	var lq := _rx(acos(clampf(u.dot(w), -1.0, 1.0)) * bend_dir)
	var cap := RAG_LIMB_RATE * maxf(dt, 1.0 / 120.0)
	for pair in [[upper, uq], [lower, lq]]:
		var cur: Quaternion = _rot[pair[0]]
		var ang := cur.angle_to(pair[1])
		var qq: Quaternion = pair[1] if ang <= cap else cur.slerp(pair[1], cap / ang)
		_rot[pair[0]] = qq
		_angvel[pair[0]] = Vector3.ZERO
		(bones[pair[0]] as Node3D).quaternion = qq


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
## Flying between webs: once the release has played out, the web arm comes
## up toward the anchor the hero will take next – anticipation, so the next
## shot reads before it fires. (Eases in and out; not during tricks, dives or
## the take-off.)
var _antic := 0.0


func _reach_next(q: Dictionary, body: Basis, dt: float, ok: bool) -> void:
	var tg := player.targeting
	var want := 0.0
	var dir := Vector3.ZERO
	var shoulder := (bones["upper_arm_r"] as Node3D).global_position
	if ok and tg and tg.pick_ok and _swan < 0.2 and _air_t > 0.3:
		dir = (tg.pick - shoulder).normalized()
		if dir.y > -0.1:
			want = 0.6
	_antic = move_toward(_antic, want, dt * (2.5 if want > _antic else 4.0))
	if _antic <= 0.01 or dir == Vector3.ZERO:
		return
	var chest_basis := body * Basis(_rot["spine"]) * Basis(_rot["chest"])
	var ik := _two_bone(chest_basis, dir, 0.5, Vector3(0.75, -0.2, 0.6))
	q["upper_arm_r"] = (q["upper_arm_r"] as Quaternion).slerp(ik[0], _antic)
	q["forearm_r"] = (q["forearm_r"] as Quaternion).slerp(ik[1], _antic)


# ------------------------------------------------------------- idle life
## Standing still never freezes: breathing that follows how hard the hero has
## just been working (heavy and fast after a sprint or a long swing, slow when
## rested), weight that settles on one leg and now and then moves over, a gaze
## that wanders to somewhere and holds, and occasional unscripted-looking
## actions picked at random, at random intervals: a glance over the shoulder,
## rolling the shoulders, shaking the arms out, checking the web gauntlet
## (pulling the cuff over it), a neck stretch. Context changes the mix: on a
## roof edge the hero looks down at the drop and sits back from it; high up
## in the wind the body leans into it; winded after a sprint the hero bends
## forward, hands loose, getting their breath back before anything else.
const IDLE_ACTIONS := {
	"glance_back": 2.3, "shoulder_roll": 1.5, "shake_out": 1.3, "gauntlet": 2.6, "neck": 1.8, "look_down": 2.8,
}
var exert := 0.0            # 0..1 how hard the hero has been working (breathing)
var idle_action := ""       # current idle action ("" = none); read by tests
## Off in the shop (the hero holds still for the try-on: breathing only).
var idle_actions := true
var _idle_t := 0.0
var _idle_next := 3.0
var _idle_dur := 1.0
var _idle_side := 1.0
var _breath := 0.0
var _shift := 0.0
var _shift_goal := 1.0
var _shift_next := 4.0
var _gaze := Vector2.ZERO   # current head yaw/pitch offset (rad)
var _gaze_goal := Vector2.ZERO
var _gaze_next := 1.5
var _edge := 0.0            # 0..1 standing at a drop in front
var _edge_probe := 0.0
var _idle_sink := 0.0       # m the hips sink (winded)
var _idle_k := 0.0
var _irng := RandomNumberGenerator.new()


## Starts an idle action now (review tools; the game picks them itself).
func play_idle(action: String, side := 1.0) -> void:
	idle_action = action
	_idle_dur = float(IDLE_ACTIONS.get(action, 2.0))
	_idle_t = 0.0
	_idle_side = side


func _idle_reset() -> void:
	idle_action = ""
	_idle_t = 0.0
	_idle_next = minf(_idle_next, 2.5 + _irng.randf() * 3.0)
	_idle_sink = move_toward(_idle_sink, 0.0, 0.01)
	_idle_k = 0.0


## Work rate → breathing. Called every frame from _update_animated.
func _update_exert(dt: float, speed: float, grounded: bool) -> void:
	var work := 0.0
	if grounded:
		work = clampf((speed - 4.0) / 10.0, 0.0, 1.0) * 0.09
	elif player.s.attached:
		work = 0.05
	exert = clampf(exert + work * dt - (0.07 if speed < 2.0 else 0.0) * dt, 0.0, 1.0)


func _idle_pose(q: Dictionary, k: float, dt: float) -> void:
	_idle_k = k
	var winded := smoothstep(0.45, 0.85, exert)
	# Breathing: rate 0.25 Hz rested → 0.6 Hz winded, slightly irregular.
	_breath += dt * TAU * lerpf(0.24, 0.62, exert) * (0.9 + 0.2 * sin(_time * 0.37))
	var br := sin(_breath)
	var br_amp := lerpf(0.018, 0.05, exert)
	# Weight: on one leg, moving over now and then (not on a timer).
	_shift_next -= dt
	if _shift_next <= 0.0:
		_shift_goal = -_shift_goal if _irng.randf() < 0.8 else _shift_goal * 0.4
		_shift_next = _irng.randf_range(3.5, 9.0)
	_shift = move_toward(_shift, _shift_goal, dt * 0.9)
	var shift := _shift * _shift * (3.0 - 2.0 * absf(_shift)) * signf(_shift)  # eased
	# Edge: is there a drop just ahead? (probed a few times a second)
	_edge_probe -= dt
	if _edge_probe <= 0.0:
		_edge_probe = 0.3
		var from := player.global_position + _facing * 0.85 + Vector3.UP * 0.3
		var eq := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.5, player.collision_mask, [player.get_rid()])
		var at_edge := get_world_3d().direct_space_state.intersect_ray(eq).is_empty()
		_edge = 1.0 if at_edge else 0.0
	var edge_k := _edge
	var high := clampf((player.height_above_ground() - 25.0) / 80.0, 0.0, 1.0)
	# Gaze: pick somewhere to look, ease to it, hold it a while.
	_gaze_next -= dt
	if _gaze_next <= 0.0:
		_gaze_goal = Vector2(_irng.randf_range(-0.75, 0.75), _irng.randf_range(-0.12, 0.1))
		if edge_k > 0.5 and _irng.randf() < 0.5:
			_gaze_goal = Vector2(_irng.randf_range(-0.3, 0.3), -0.42)  # down at the street
		_gaze_next = _irng.randf_range(1.6, 4.5)
	_gaze = _gaze.lerp(_gaze_goal, 1.0 - exp(-2.2 * dt))
	# Occasional actions (not while winded).
	_idle_next -= dt
	if idle_action == "" and _idle_next <= 0.0 and winded < 0.2 and idle_actions:
		var pool := ["glance_back", "shoulder_roll", "shake_out", "gauntlet", "neck"]
		if edge_k > 0.5 or high > 0.3:
			pool += ["look_down", "look_down", "glance_back"]
		else:
			pool += ["gauntlet", "shoulder_roll"]
		var pick: String = pool[_irng.randi_range(0, pool.size() - 1)]
		if pick == "look_down" and edge_k < 0.5:
			pick = "neck"
		idle_action = pick
		_idle_dur = float(IDLE_ACTIONS[pick]) * _irng.randf_range(0.85, 1.2)
		_idle_t = 0.0
		_idle_side = -1.0 if _irng.randf() < 0.5 else 1.0
	var a_u := 0.0
	var env := 0.0
	if idle_action != "":
		_idle_t += dt
		a_u = _idle_t / _idle_dur
		env = smoothstep(0.0, 0.22, a_u) * (1.0 - smoothstep(0.72, 1.0, a_u))
		if a_u >= 1.0:
			idle_action = ""
			_idle_next = _irng.randf_range(3.5, 9.0)
	# --- base: relaxed stance -------------------------------------------------
	var lean_f := -0.015 + 0.03 * edge_k  # sits back from a drop (+ = back for torso bones)
	var wind_f := 0.0
	if high > 0.0:
		# High up in the wind: lean a little into it.
		var w_into := -wind.dot(_facing)  # >0: the air comes from the front
		wind_f = clampf(w_into * 0.012, -0.06, 0.06) * high
	q["hips"] = (q["hips"] as Quaternion).slerp(_rz(shift * 0.06) * _ry(shift * 0.04), k)
	q["spine"] = (q["spine"] as Quaternion).slerp(_rz(-shift * 0.05) * _rx(lean_f - wind_f - winded * 0.42), k)
	q["chest"] = (q["chest"] as Quaternion).slerp(_rx(0.03 + br * br_amp * (1.0 + winded) - winded * 0.26) * _rz(-shift * 0.035)
		* _ry(-shift * 0.05), k)
	q["neck"] = (q["neck"] as Quaternion).slerp(_rx(-0.02 + winded * 0.26), k)
	var head := _ry(_gaze.x * (1.0 - env * 0.8)) * _rz(shift * 0.05) * _rx(_gaze.y * (1.0 - winded) + br * br_amp * 0.3 + winded * 0.3)
	q["head"] = (q["head"] as Quaternion).slerp(head, k)
	# Arms: soft, hanging; shoulders lift with each breath. Winded, they hang
	# forward off the bent body.
	for sd in ["l", "r"]:
		var sdg := 1.0 if sd == "r" else -1.0
		var asym := 0.02 if sd == "l" else 0.0
		q["upper_arm_" + sd] = (q["upper_arm_" + sd] as Quaternion).slerp(
			_rz(sdg * (0.13 + asym + br * br_amp * 0.4)) * _rx(0.05 + winded * 0.62) * _ry(-0.3 * sdg * (1.0 - winded)), k)
		q["forearm_" + sd] = (q["forearm_" + sd] as Quaternion).slerp(_rx(0.28 + asym * 2.0 + br * 0.02 - winded * 0.1), k)
	_idle_sink = lerpf(_idle_sink, winded * 0.085, 1.0 - exp(-3.0 * dt))
	_hip_shift = lerpf(_hip_shift, shift * 0.025, k)
	if env <= 0.0:
		return
	# --- actions ------------------------------------------------------------
	var e := env * k
	var sdg := _idle_side
	var t := _idle_t
	match idle_action:
		"glance_back":
			q["head"] = (q["head"] as Quaternion).slerp(_ry(1.05 * sdg) * _rx(-0.05), e)
			q["neck"] = (q["neck"] as Quaternion).slerp(_ry(0.3 * sdg), e)
			q["chest"] = (q["chest"] as Quaternion).slerp(_ry(0.22 * sdg) * (q["chest"] as Quaternion), e * 0.8)
		"shoulder_roll":
			var r := sin(a_u * TAU)
			var r2 := cos(a_u * TAU)
			for sd in ["l", "r"]:
				var s2 := 1.0 if sd == "r" else -1.0
				q["upper_arm_" + sd] = (q["upper_arm_" + sd] as Quaternion) * _rz(s2 * 0.16 * maxf(r, 0.0) * e) * _rx(-0.22 * r2 * e)
			q["chest"] = (q["chest"] as Quaternion) * _rx(0.07 * r2 * e)
			q["head"] = (q["head"] as Quaternion) * _rz(0.12 * sin(a_u * PI) * sdg * e)
		"shake_out":
			var f := sin(t * 19.0) * e
			var f2 := sin(t * 23.0 + 1.1) * e
			q["upper_arm_l"] = (q["upper_arm_l"] as Quaternion) * _rx(0.07 * f) * _rz(-0.05 * f2)
			q["upper_arm_r"] = (q["upper_arm_r"] as Quaternion) * _rx(0.07 * f2) * _rz(0.05 * f)
			q["forearm_l"] = (q["forearm_l"] as Quaternion) * _rx(0.18 * f2)
			q["forearm_r"] = (q["forearm_r"] as Quaternion) * _rx(0.18 * f)
			q["chest"] = (q["chest"] as Quaternion) * _ry(0.05 * sin(t * 7.0) * e)
		"gauntlet":
			# Raise the launcher arm, look at the wrist, tug the cuff over it
			# with the other hand.
			var tug := maxf(sin(clampf((a_u - 0.35) / 0.4, 0.0, 1.0) * PI * 2.0), 0.0) * e
			q["upper_arm_r"] = (q["upper_arm_r"] as Quaternion).slerp(_rx(0.55) * _rz(0.32) * _ry(0.65), e)
			q["forearm_r"] = (q["forearm_r"] as Quaternion).slerp(_rx(1.75), e)
			q["upper_arm_l"] = (q["upper_arm_l"] as Quaternion).slerp(_rx(0.62 + 0.05 * tug) * _rz(-0.12) * _ry(-0.75), e)
			q["forearm_l"] = (q["forearm_l"] as Quaternion).slerp(_rx(1.45 - 0.12 * tug), e)
			q["head"] = (q["head"] as Quaternion).slerp(_ry(0.32) * _rx(-0.42), e)
			q["neck"] = (q["neck"] as Quaternion).slerp(_rx(-0.12), e)
		"neck":
			var nt := sin(a_u * TAU) * sdg
			q["head"] = (q["head"] as Quaternion).slerp(_rz(0.26 * nt) * _rx(-0.06), e)
			q["neck"] = (q["neck"] as Quaternion).slerp(_rz(0.1 * nt), e)
		"look_down":
			q["head"] = (q["head"] as Quaternion).slerp(_ry(0.25 * sdg) * _rx(-0.55), e)
			q["neck"] = (q["neck"] as Quaternion).slerp(_rx(-0.2), e)
			q["chest"] = (q["chest"] as Quaternion).slerp(_rx(-0.06) * (q["chest"] as Quaternion), e * 0.7)


## Clothing secondary motion (character.gdshader applies it to the hoodie
## hem, sleeves, hood and cords by their cloth weight): one damped spring for
## the fabric's offset, chasing where the air, inertia and gravity would put
## it. Underdamped, so the hem swings past and settles after a stop or a
## landing instead of freezing.
##   * air: wind minus the body's velocity – the hem and hood stream back when
##     running, lift when falling, flap at speed; a breeze that grows with
##     height (and gusts) keeps them alive standing on a roof.
##   * inertia: sudden acceleration leaves the fabric behind.
##   * gravity: upside down (flips, dives) the hem falls toward the sky.
const CLOTH_K := 85.0      # 1/s² (~1.5 Hz)
const CLOTH_C := 6.5       # 1/s (underdamped: a wobble or two)
const CLOTH_MAX := 0.16    # m at weight 1
const WIND_DIR := Vector3(0.78, 0.0, -0.62)
var cloth := Vector3.ZERO  # current offset (world, m at weight 1); read by tests
var _cloth_v := Vector3.ZERO
var _cloth_t := 0.0
var _cloth_air := Vector3.ZERO
var wind := Vector3.ZERO   # ambient wind at the hero (world m/s)


func _update_cloth(dt: float) -> void:
	if _mat == null or dt <= 0.0:
		return
	_cloth_t += dt
	var h := player.height_above_ground() if player else 0.0
	var gust := 0.65 + 0.35 * sin(_cloth_t * 0.37) * sin(_cloth_t * 1.13 + 0.4) + 0.15 * sin(_cloth_t * 2.9)
	wind = WIND_DIR * (1.4 + 5.0 * clampf(h / 140.0, 0.0, 1.0)) * gust
	var air := wind - (player.s.velocity if player else Vector3.ZERO)
	_cloth_air = _cloth_air.lerp(air, 1.0 - exp(-10.0 * dt))
	var a_len := _cloth_air.length()
	var target := Vector3.ZERO
	if a_len > 0.01:
		target = _cloth_air / a_len * 0.14 * (1.0 - exp(-a_len / 13.0))
	target -= _accel.limit_length(40.0) * 0.0016
	var up := (bones["spine"] as Node3D).global_basis.y.normalized()
	target += (Vector3.DOWN + up) * 0.055
	target = target.limit_length(CLOTH_MAX)
	_cloth_v += ((target - cloth) * CLOTH_K - _cloth_v * CLOTH_C) * dt
	cloth += _cloth_v * dt
	cloth = cloth.limit_length(CLOTH_MAX * 1.15)
	_mat.set_shader_parameter("cloth_drag", cloth)
	_mat.set_shader_parameter("cloth_flutter", smoothstep(3.0, 32.0, a_len))
	_mat.set_shader_parameter("cloth_time", _cloth_t)
	_mat.set_shader_parameter("cloth_wind_dir", _cloth_air / maxf(a_len, 0.01))


## Landings and wall hits shake the fabric (the hem bounces and settles).
func cloth_kick(v: Vector3) -> void:
	_cloth_v += v


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
