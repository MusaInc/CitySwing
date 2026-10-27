class_name PrototypeWorld
extends Node3D
## Milestone-1 test range: a street plane and a deliberate set of towers –
## an easy launch line, a wide gap that needs a big swing, and a narrow
## technical slot. Also used by the automated swing tests.

const TOWERS := [
	# x, z, width, depth, height
	[0, 0, 18, 18, 30],      # spawn rooftop
	[-16, -60, 16, 16, 70],
	[18, -100, 14, 20, 85],
	[-14, -150, 18, 14, 60],
	[16, -200, 14, 14, 90],
	[-12, -250, 16, 18, 75],
	[14, -300, 16, 16, 95],
	[-16, -350, 14, 14, 70],
	[12, -440, 20, 20, 110],  # after the wide gap
	[-30, -500, 10, 30, 80],  # narrow slot pair
	[-6, -505, 10, 30, 80],
	[10, -580, 22, 22, 50],
]

static func add_box(parent: Node3D, center: Vector3, size: Vector3, color: Color, grappleable := true,
		street := false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = (1 << 3) if street else (1 | (1 << 1) if grappleable else 1)
	body.collision_mask = 0
	if street:
		body.add_to_group("street")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	body.position = center
	return body


func _ready() -> void:
	add_box(self, Vector3(0, -0.5, -300), Vector3(600, 1, 1000), Color(0.32, 0.33, 0.36), false, true)
	var palette := [Color(0.82, 0.74, 0.62), Color(0.55, 0.62, 0.72), Color(0.72, 0.5, 0.42), Color(0.6, 0.66, 0.6)]
	for i in TOWERS.size():
		var t: Array = TOWERS[i]
		add_box(self, Vector3(t[0], t[4] * 0.5, t[1]), Vector3(t[2], t[4], t[3]), palette[i % palette.size()])


## Autopilot goal: a point down the central corridor ahead of the player.
func bot_goal(p: Node3D) -> Vector3:
	return Vector3(2.0, 0.0, p.global_position.z - 80.0)


func spawn_point() -> Vector3:
	return Vector3(0, 31.0, 4.0)
