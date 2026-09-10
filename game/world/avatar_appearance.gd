class_name AvatarAppearance
extends RefCounted
## Only per-instance materials and cosmetic children change; mesh resources and
## the root transform remain available to movement and seating systems.

static func apply(avatar: Node3D, value: Variant) -> void:
	var profile: Dictionary = value if AvatarProfile.validate(value).is_empty() else AvatarProfile.defaults()
	if avatar.get_meta("avatar_profile", {}) == profile: return
	avatar.set_meta("avatar_profile", profile.duplicate(true))
	var previous = avatar.get_node_or_null("AvatarGear")
	if previous != null:
		avatar.remove_child(previous)
		previous.queue_free()
	for mesh in avatar.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var original = mesh.mesh.surface_get_material(surface)
			mesh.set_surface_override_material(surface, null)
			if not original is StandardMaterial3D: continue
			var name: String = original.resource_name
			var is_suit = name.begins_with("Cerámica") and profile.suit != "classic"
			var is_visor = name.begins_with("Pantalla") and profile.visor != "aqua"
			if not is_suit and not is_visor: continue
			var material = original.duplicate() as StandardMaterial3D
			material.albedo_color = AvatarProfile.SUIT_COLORS[profile.suit] if is_suit else AvatarProfile.VISOR_COLORS[profile.visor]
			if is_visor: material.emission = material.albedo_color * 0.7
			mesh.set_surface_override_material(surface, material)
	if profile.gear == "none": return
	var gear = Node3D.new()
	gear.name = "AvatarGear"
	avatar.add_child(gear)
	if profile.gear == "survey":
		_box(gear, "Scanner", Vector3(0.13, 0.13, 0.1), Vector3(0.32, 1.4, -0.14), Color("293a47"))
		_box(gear, "ScannerLens", Vector3(0.08, 0.06, 0.012), Vector3(0.32, 1.4, -0.197), AvatarProfile.VISOR_COLORS[profile.visor])
		_box(gear, "Antenna", Vector3(0.025, 0.31, 0.025), Vector3(0.32, 1.59, -0.12), Color("bccac7"))
	else:
		_box(gear, "Pack", Vector3(0.43, 0.54, 0.2), Vector3(0, 1.13, 0.25), Color("344652"))
		for side in [-1, 1]:
			_box(gear, "Strap" + str(side), Vector3(0.055, 0.48, 0.025), Vector3(side * 0.17, 1.2, -0.17), Color("e7ae56"))

static func _box(parent: Node3D, name: String, dimensions: Vector3, at: Vector3, color: Color) -> void:
	var instance = MeshInstance3D.new()
	instance.name = name
	var mesh = BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.position = at
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	instance.material_override = material
	parent.add_child(instance)
