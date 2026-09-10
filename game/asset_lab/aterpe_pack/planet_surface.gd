extends Node3D
## Runtime wrapper for a full-scale habitable GLB. No session/campaign authority.
## Collision layers: terrain = 1, POI structures = 2. Far LODs never collide.

@export_enum("kare", "suharri") var planet_slug: String = "kare"
var entry: Dictionary = {}
var terrain_bodies: int = 0
var structure_bodies: int = 0
var ready_for_landing: bool = false

func _ready() -> void:
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/aterpe_pack/manifest.json"))
	if not document is Dictionary or document.get("schema_version") != 1 or not document.get("planets") is Array:
		push_error("Invalid Aterpe planet catalogue")
		return
	for item in document["planets"]:
		if item is Dictionary and item.get("slug") == planet_slug:
			entry = item
			break
	if entry.is_empty() or not bool(entry.get("habitable", false)) or not is_finite(float(entry.get("radius_metres", 0))) or float(entry.get("radius_metres", 0)) <= 0:
		push_error("Missing habitable planet metadata")
		return
	var visual: Node = get_node_or_null("Visual")
	if visual == null:
		push_error("Missing detailed planet model")
		return
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var layer: int = _collision_layer(mesh)
		if layer == 0 or mesh.mesh == null:
			continue
		var shape: ConcavePolygonShape3D = mesh.mesh.create_trimesh_shape()
		if shape == null or shape.get_faces().is_empty():
			push_error("Invalid planetary collision mesh")
			return
		var body := StaticBody3D.new()
		body.name = "SurfaceCollision"
		body.collision_layer = layer
		body.collision_mask = 0
		mesh.add_child(body)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		if layer == 1:
			terrain_bodies += 1
		else:
			structure_bodies += 1
	ready_for_landing = terrain_bodies == int(entry["terrain_chunks"]) and structure_bodies >= 16
	if not ready_for_landing:
		push_error("Planet collision coverage incomplete: %d terrain / %d structures" % [terrain_bodies, structure_bodies])

func _collision_layer(node: Node) -> int:
	var current: Node = node
	while current != null and current != self:
		if str(current.name).begins_with("chunk_"):
			return 1
		if str(current.name).begins_with("poi_"):
			return 2
		current = current.get_parent()
	return 0

func radius() -> float:
	return float(entry.get("radius_metres", 0.0))

func marker(index: int, role: String = "arrival") -> Node3D:
	if entry.is_empty() or index < 0 or index >= entry["pois"].size():
		return null
	if role not in ["arrival", "departure", "resource", "quest", "encounter", "landing"]:
		return null
	var anchors: Dictionary = entry["pois"][index]["anchors"]
	if not anchors.has(role):
		return null
	return find_child(str(anchors[role]["node_name"]), true, false) as Node3D

func ground(local_direction: Vector3, mask: int = 1) -> Dictionary:
	if not ready_for_landing or not local_direction.is_finite() or local_direction.length_squared() < 0.000001 or mask < 1 or mask > 3:
		return {}
	var normal: Vector3 = local_direction.normalized()
	var start: Vector3 = to_global(normal * (radius() + 40.0))
	var finish: Vector3 = to_global(normal * (radius() - 30.0))
	var query := PhysicsRayQueryParameters3D.create(start, finish, mask)
	query.hit_back_faces = false
	return get_world_3d().direct_space_state.intersect_ray(query)

func surface_spawn(index: int) -> Dictionary:
	var anchor: Node3D = marker(index, "arrival")
	if anchor == null:
		return {}
	var local_direction: Vector3 = to_local(anchor.global_position).normalized()
	var hit: Dictionary = ground(local_direction, 3)
	if hit.is_empty():
		return {}
	var up: Vector3 = (global_basis * local_direction).normalized()
	var forward: Vector3 = -anchor.global_basis.z
	forward = (forward - up * forward.dot(up)).normalized()
	return {"position": hit["position"] + up * 1.08, "up": up, "forward": forward}
