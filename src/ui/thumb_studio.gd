class_name ThumbStudio
extends SubViewport
## Shop thumbnails rendered from the real character: a small isolated studio
## (own World3D: key + fill light, soft dark backdrop) holding a CharacterRig
## posed relaxed. Each item is shown on the rig with only its slot changed,
## framed for its category, rendered once (one item per frame, queued) and
## cached for the session – the grid never renders anything per frame.
## Web items show the launcher hand in their colour; gadgets the whole body.

signal ready_thumb(id: String, tex: Texture2D)

const SIZE := 192
## Framing per slot: [look-at height above the feet, camera distance, yaw].
const FRAME := {
	"suit": [1.28, 1.25, 0.35], "pants": [0.62, 1.55, 0.3], "shoes": [0.12, 0.85, 0.75],
	"gloves": [0.98, 0.7, -1.25], "head": [1.66, 0.72, 0.3], "face": [1.68, 0.6, 0.15],
	"web": [1.0, 0.62, -1.4], "gadget": [1.05, 2.1, 2.5],
}

static var cache := {}       # item id -> Texture2D (session lifetime)

var _rig: CharacterRig
var _cam: Camera3D
var _web: MeshInstance3D
var _web_mat: StandardMaterial3D
var _queue: Array[String] = []
var _busy := false


func _init() -> void:
	size = Vector2i(SIZE, SIZE)
	own_world_3d = true
	transparent_bg = false
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	msaa_3d = Viewport.MSAA_2X


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.11, 0.1, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.68)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.95, 0.88)
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -140, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)
	_rig = CharacterRig.new()
	add_child(_rig)
	_rig.position = Vector3(0, 0.9, 0)
	_rig.rotation.y = PI  # face the camera (+Z)
	# A short web line from the launcher hand (shown for web items only).
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.011
	cyl.bottom_radius = 0.011
	cyl.height = 1.6
	_web_mat = StandardMaterial3D.new()
	_web_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.material = _web_mat
	_web = MeshInstance3D.new()
	_web.mesh = cyl
	add_child(_web)
	var hand := Vector3(-0.31, 0.86, 0.07)
	var dir := Vector3(-0.35, 1.0, 0.5).normalized()
	_web.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), hand + dir * 0.8)
	_web.visible = false
	_cam = Camera3D.new()
	_cam.fov = 32.0
	add_child(_cam)
	_cam.current = true
	_pose()


## A relaxed stand: arms down and a little out, elbows soft.
func _pose() -> void:
	var q := {"upper_arm_l": Basis.from_euler(Vector3(0.05, 0.25, -0.16)), "upper_arm_r": Basis.from_euler(Vector3(0.05, -0.25, 0.16)),
		"forearm_l": Basis.from_euler(Vector3(0.3, 0, 0)), "forearm_r": Basis.from_euler(Vector3(0.3, 0, 0))}
	for b in _rig.bones:
		(_rig.bones[b] as Node3D).quaternion = (q[b] as Basis).get_rotation_quaternion() if q.has(b) else Quaternion.IDENTITY
	_rig._sync_skeleton()


## Queues `id` (no-op if cached or queued). Results arrive via ready_thumb.
func request(id: String) -> void:
	if cache.has(id) or id in _queue:
		return
	_queue.append(id)
	if not _busy:
		_run()


func _run() -> void:
	_busy = true
	while not _queue.is_empty():
		var id: String = _queue.pop_front()
		var it := Shop.item(id)
		if it.is_empty():
			continue
		var slot: String = it["slot"]
		var lk := Shop.look({slot: id})
		_rig.apply_look(lk)
		_web.visible = slot == "web"
		if _web.visible:
			_web_mat.albedo_color = Color(1.0, 0.45, 0.85) if lk.get("rainbow", false) else (lk["web"] as Color)
		var fr: Array = FRAME.get(slot, [1.0, 2.6, 0.3])
		var aim := Vector3(0.0, float(fr[0]), 0.0)
		if slot in ["gloves", "web"]:
			aim.x = -0.32  # the launcher (right) hand, seen from the front
		var yaw: float = fr[2]
		var dir := Vector3(sin(yaw), 0.18, cos(yaw)).normalized()
		_cam.global_position = aim + dir * float(fr[1])
		_cam.look_at(aim, Vector3.UP)
		render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var img := get_texture().get_image() if get_texture() else null
		if img and not img.is_empty():
			var tex := ImageTexture.create_from_image(img)
			cache[id] = tex
			ready_thumb.emit(id, tex)
	_busy = false
