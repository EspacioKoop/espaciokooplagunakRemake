class_name PhysicalSeatCatalog
extends RefCounted
## Physical metadata is derived from the same interactions used by the deck.
## No player positions, private table state or occupancy live in this catalog.
const APPROACH_RADIUS = 1.25
const HEIGHT_TOLERANCE = 0.75

static func all_seats() -> Dictionary:
	var zones: Array = load("res://world/interior.gd").get_script_constant_map().ZONES
	var result: Dictionary = {}
	for zone in [7, 10]:
		for entry in LeisurePlaces.interactions(zone):
			if entry.kind != "seat": continue
			result[entry.id] = {"id": entry.id, "zone": zone, "approach": zones[zone].at + entry.position,
				"anchor": zones[zone].at + entry.seat + Vector3(0, 0.1, 0), "yaw": 0.0}
	return result

static func reachable(seat: Dictionary, position: Vector3) -> bool:
	if not position.is_finite() or seat.is_empty(): return false
	var offset: Vector3 = position - seat.approach
	return Vector2(offset.x, offset.z).length() <= APPROACH_RADIUS and absf(offset.y) <= HEIGHT_TOLERANCE

static func in_zone(seat: Dictionary, position: Vector3) -> bool:
	if not position.is_finite(): return false
	var zones: Array = load("res://world/interior.gd").get_script_constant_map().ZONES
	var offset: Vector3 = position - zones[seat.zone].at
	return absf(offset.x) < 16.0 and absf(offset.z) < 14.0 and absf(offset.y) < 5.0

static func pose_vertex(vertex: Vector3) -> Vector3:
	# Two rigid leg segments around the hip and knee. The root is lowered 0.4m.
	if vertex.y >= 0.9: return vertex
	if vertex.y <= 0.5: return vertex + Vector3(0, 0.4, -0.4)
	return Vector3(vertex.x, 0.9 + vertex.z, vertex.y - 0.9)

static func apply_pose(avatar: Node3D, sitting: bool) -> void:
	if bool(avatar.get_meta("physical_seat_pose", false)) == sitting: return
	avatar.set_meta("physical_seat_pose", sitting)
	for node in avatar.find_children("*", "MeshInstance3D", true, false):
		# Only deform the original crew mesh, never cosmetic accessories.
		if node.name != "crew": continue
		if not node.has_meta("standing_mesh"): node.set_meta("standing_mesh", node.mesh)
		if sitting and not node.has_meta("sitting_mesh"):
			node.set_meta("sitting_mesh", _seated_mesh(node.get_meta("standing_mesh")))
		node.mesh = node.get_meta("sitting_mesh" if sitting else "standing_mesh")

static func _seated_mesh(source: Mesh) -> ArrayMesh:
	var result = ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays = source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var builder = SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in range(0, indices.size(), 3):
			var polygon: Array = []
			for corner in 3:
				var v = indices[index + corner]
				polygon.append({"v": vertices[v], "uv": uvs[v], "n": normals[v]})
			# Split triangles at both bends before deforming so a long straight
			# trouser leg actually has a knee instead of stretching diagonally.
			var fragments: Array = [polygon]
			for height in [0.5, 0.9]:
				var split: Array = []
				for piece in fragments:
					for above in [false, true]:
						var clipped = _clip(piece, height, above)
						if clipped.size() >= 3: split.append(clipped)
				fragments = split
			for piece in fragments:
				for triangle in range(1, piece.size() - 1):
					for corner in [piece[0], piece[triangle], piece[triangle + 1]]:
						builder.set_uv(corner.uv)
						builder.add_vertex(pose_vertex(corner.v))
		builder.generate_normals()
		builder.set_material(source.surface_get_material(surface))
		builder.commit(result)
	return result

static func _clip(polygon: Array, height: float, above: bool) -> Array:
	var result: Array = []
	for i in polygon.size():
		var a: Dictionary = polygon[i]
		var b: Dictionary = polygon[(i + 1) % polygon.size()]
		var inside_a: bool = a.v.y >= height if above else a.v.y < height
		var inside_b: bool = b.v.y >= height if above else b.v.y < height
		if inside_a: result.append(a)
		if inside_a != inside_b:
			var weight: float = (height - a.v.y) / (b.v.y - a.v.y)
			result.append({"v": a.v.lerp(b.v, weight), "uv": a.uv.lerp(b.uv, weight), "n": a.n.lerp(b.n, weight)})
	return result
