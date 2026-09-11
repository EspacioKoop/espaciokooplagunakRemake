class_name RuntimeAssetLibrary
extends RefCounted
## A read-only allowlist; saved/network model IDs can never become file paths.
const INDEX = "res://data/runtime_asset_library.json"
static var _entries: Dictionary = {}

static func _load_index() -> void:
	if not _entries.is_empty(): return
	if not FileAccess.file_exists(INDEX): return
	var document = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	if not document is Dictionary or document.get("format") != "lagunak-runtime-assets" or document.get("version") != 1:
		return
	if not document.get("assets") is Array or document.assets.size() > 512: return
	var parsed = {}
	for entry in document.assets:
		if not entry is Dictionary or not entry.get("id") is String or parsed.has(entry.id): return
		if not entry.get("resource") is String or not entry.resource.begins_with("res://assets/models/") or not entry.resource.ends_with(".glb") or entry.resource.contains("..") or entry.resource.contains("\\"): return
		if not entry.get("contact_kinds") is Array: return
		parsed[entry.id] = entry.duplicate(true)
	_entries = parsed

static func entries() -> Array:
	_load_index()
	return _entries.values().duplicate(true)

static func entry(id: String) -> Dictionary:
	_load_index()
	return _entries.get(id, {}).duplicate(true)

static func compatible(id: String, kind: String) -> bool:
	if id.is_empty(): return true
	var item = entry(id)
	return not item.is_empty() and kind in item.contact_kinds

static func instantiate(id: String) -> Node3D:
	var item = entry(id)
	if item.is_empty() or not ResourceLoader.exists(item.resource, "PackedScene"): return null
	var scene = load(item.resource) as PackedScene
	if scene == null: return null
	return scene.instantiate() as Node3D

static func bounds(node: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect(node, Transform3D.IDENTITY, boxes)
	if boxes.is_empty(): return AABB()
	var total = boxes[0]
	for box in boxes: total = total.merge(box)
	return total

static func _collect(node: Node, parent_transform: Transform3D, boxes: Array[AABB]) -> void:
	var transform = parent_transform
	if node is Node3D: transform = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		boxes.append(transform * node.mesh.get_aabb())
	for child in node.get_children(): _collect(child, transform, boxes)

static func contact_model(id: String, kind: String, radius: float) -> Node3D:
	if id.is_empty() or not compatible(id, kind) or not is_finite(radius) or radius <= 0: return null
	var model = instantiate(id)
	if model == null: return null
	var box = bounds(model)
	var reach = box.size.length() * 0.5
	if reach <= 0 or not is_finite(reach):
		model.free()
		return null
	# SpaceView displays simulation metres at 0.04. Fit the existing collision
	# envelope visually, without changing collision, mass, damage or ship rules.
	var wrapper = Node3D.new()
	var fit = maxf(0.2, radius * 0.04) / reach
	wrapper.add_child(model)
	model.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * fit), -box.get_center() * fit) * model.transform
	return wrapper
