extends Node
## Asset regressions the motion tests cannot detect: missing textures, emergency
## primitive bodies underneath a skin, broken weights and absent grip morphs.

func test_courier_skin_has_textures_uvs_normalized_weights_and_mobile_budget(t) -> void:
	var rig := CharacterRig.new()
	add_child(rig)
	t.check(rig.skeleton != null, "default courier has a gameplay skeleton")
	var triangles := 0
	var invalid_weights := 0
	var textured := 0
	var normal_mapped := 0
	var occluded := 0
	var variants := 0
	for mi in rig.skeleton.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		variants += int(not mi.visible)
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			# The budget is what one outfit draws: the faces, tops and masks
			# not worn are hidden (and cost no draw calls).
			if mi.visible:
				triangles += (indices.size() if indices.size() > 0 else vertices.size()) / 3
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			t.check(weights.size() == vertices.size() * 4, "four skin influences per vertex")
			for i in range(0, weights.size(), 4):
				var total := weights[i] + weights[i + 1] + weights[i + 2] + weights[i + 3]
				if not is_finite(total) or absf(total - 1.0) > 0.015:
					invalid_weights += 1
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			t.check(uv.size() == vertices.size(), "authored surface UVs survive export")
			if String(mi.name) == "Courier_Trainers":
				var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
				var sole_vertices := 0
				var upper_vertices := 0
				for coordinate in uv2:
					sole_vertices += int(coordinate.y > 0.9)
					upper_vertices += int(coordinate.y < 0.1)
				t.check(sole_vertices > 20 and upper_vertices > 20, "exported trainers separate sole and upper regions")
			var material := mi.get_surface_override_material(surface) as ShaderMaterial
			t.check(material != null, "surface uses the texture-preserving hero shader")
			if material:
				textured += int(material.get_shader_parameter("albedo_map") is Texture2D)
				normal_mapped += int(material.get_shader_parameter("normal_map") is Texture2D)
				occluded += int(material.get_shader_parameter("ao_map") is Texture2D)
	t.check(invalid_weights == 0, "all skin weights are finite and normalized")
	t.check(triangles > 20000 and triangles < 50000, "hero triangle budget (drawn): %d" % triangles)
	t.check(variants >= 15, "faces, tops and masks ship as hidden variants (%d)" % variants)
	t.check(textured >= 3 and normal_mapped >= 2 and occluded >= 5, "PBR textures and baked AO retained")
	var fallback := 0
	for pivot in rig.bones.values():
		for child in pivot.get_children():
			if child is MeshInstance3D and child.visible:
				fallback += 1
	t.check(fallback == 0, "no emergency primitive body is added beneath the skin")
	t.note("%d triangles; %d textured, %d normal-mapped, %d AO surfaces" % [triangles, textured, normal_mapped, occluded])
	rig.queue_free()
	await get_tree().process_frame


func test_courier_tints_are_instance_local_and_grips_are_continuous(t) -> void:
	var first := CharacterRig.new()
	var second := CharacterRig.new()
	add_child(first)
	add_child(second)
	first.set_suit_color(Color(0.8, 0.1, 0.09))
	var first_tint := Vector3.ZERO
	var second_tint := Vector3.ZERO
	for entry in first._hero_materials:
		if entry.region == "suit":
			first_tint = entry.material.get_shader_parameter("tint")
	for entry in second._hero_materials:
		if entry.region == "suit":
			second_tint = entry.material.get_shader_parameter("tint")
	t.check(not first_tint.is_equal_approx(second_tint), "shop preview cannot recolour another character")
	first.apply_look(Shop.look({"shoes": "shoes_gum"}))
	for entry in first._hero_materials:
		if entry.region == "shoe":
			var upper: Vector3 = entry.material.get_shader_parameter("tint")
			var sole: Vector3 = entry.material.get_shader_parameter("sole_tint")
			t.check(not sole.is_equal_approx(upper), "purchased sole and upper colours remain independent")
	t.check(is_instance_valid(first._glove_mesh), "authored gloves have grip shapes")
	if is_instance_valid(first._glove_mesh):
		await get_tree().process_frame
		first._set_grip("r", true)
		var index := first._glove_mesh.find_blend_shape_by_name("Grip_r")
		var amount := first._glove_mesh.get_blend_shape_value(index)
		t.check(amount > 0.0 and amount < 1.0, "grip eases in rather than swapping meshes")
		t.check(first._glove_mesh.find_blend_shape_by_name("Grip_l") >= 0, "both hands can grasp")
	first.queue_free()
	second.queue_free()
	await get_tree().process_frame
