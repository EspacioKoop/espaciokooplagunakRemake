class_name PickupModel
extends RefCounted

static func create(kind: String) -> Node3D:
	var root = Node3D.new()
	var body = MeshInstance3D.new()
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("72d9df") if kind == "supplydrop" else Color("bb9bde")
	material.metallic = 0.65
	material.roughness = 0.3
	if kind == "supplydrop":
		var box = BoxMesh.new()
		box.size = Vector3(2.0, 1.2, 1.5)
		body.mesh = box
	else:
		var crystal = CylinderMesh.new()
		crystal.top_radius = 0.0
		crystal.bottom_radius = 1.0
		crystal.height = 2.5
		crystal.radial_segments = 4
		body.mesh = crystal
	body.material_override = material
	root.add_child(body)
	return root
