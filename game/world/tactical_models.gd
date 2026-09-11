class_name TacticalModels
extends RefCounted
## Presentation bindings only. Pack manifests remain authoritative; no copied geometry.
## All paths are fixed bindings, never paths received from a save or peer.

const NAVIGATOR = "res://assets/models/frontier_pack/crew_navigator.glb"
const ENGINEER = "res://assets/models/frontier_pack/crew_engineer.glb"
const SYNTHETIC = "res://assets/models/frontier_pack/crew_synthetic.glb"
const WARDEN = "res://assets/models/frontier_pack/enemy_warden.glb"
const DRONE = "res://assets/models/orbita_pack/lapa_drone.glb"
const SIDEARM = "res://assets/models/fieldkit_pack/txinparta_sidearm.glb"
const CARBINE = "res://assets/models/fieldkit_pack/tximista_carbine.glb"
const DISPERSER = "res://assets/models/orbita_pack/player_batch/ezpal_coil_dispenser.glb"
const CRATE = "res://assets/models/frontier_pack/cargo_crate.glb"
const BODIES = {"navigator": NAVIGATOR, "engineer": ENGINEER, "synthetic": SYNTHETIC, "warden": WARDEN, "drone": DRONE}
const WEAPONS = {"pistola": SIDEARM, "carabina": CARBINE, "escopeta": DISPERSER}

static var _scenes: Dictionary = {}

static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene
	assert(_scenes[path] != null, "Registered model must import as PackedScene")
	return _scenes[path]

static func body_key(unit: Dictionary) -> String:
	if unit.get("team") == "enemy":
		var id = str(unit.get("id", ""))
		if id.ends_with("_centinela"): return "warden"
		if id.ends_with("_enjambre"): return "drone"
		return "synthetic"
	if unit.get("weapon") == "escopeta": return "engineer"
	if unit.get("weapon") == "carabina": return "synthetic"
	return "navigator"

static func find_socket(node: Node, socket_name: String) -> Node3D:
	if node.name == socket_name and node is Node3D: return node
	for child in node.get_children():
		var found = find_socket(child, socket_name)
		if found != null: return found
	return null

static func relative_transform(ancestor: Node3D, descendant: Node3D) -> Transform3D:
	var result = Transform3D.IDENTITY
	var current: Node = descendant
	while current != null and current != ancestor:
		if current is Node3D: result = current.transform * result
		current = current.get_parent()
	assert(current == ancestor, "Socket must belong to the instantiated model")
	return result

static func create_unit(unit: Dictionary) -> Node3D:
	var pawn = Node3D.new()
	pawn.name = "TacticalPawn"
	var key = body_key(unit)
	var scene: PackedScene = _scene(BODIES[key])
	var body: Node3D = scene.instantiate()
	body.name = "Body"
	pawn.add_child(body)
	pawn.set_meta("body_resource", scene.resource_path)
	# Both the character and its equipment stay at the authored metre scale.
	# Imported hand sockets are children of BoneAttachment3D, so gear follows bones.
	var hand = find_socket(body, "Socket_Hand_R")
	var weapon_id = str(unit.get("weapon", ""))
	if hand != null and WEAPONS.has(weapon_id):
		var weapon_scene: PackedScene = _scene(WEAPONS[weapon_id])
		var weapon: Node3D = weapon_scene.instantiate()
		var grip = find_socket(weapon, "socket_grip")
		assert(grip != null, "The registered weapon needs its authored grip socket")
		weapon.name = "Equipment"
		weapon.transform = relative_transform(weapon, grip).affine_inverse()
		hand.add_child(weapon)
		pawn.set_meta("weapon_resource", weapon_scene.resource_path)
	return pawn

static func create_cover() -> Node3D:
	var scene: PackedScene = _scene(CRATE)
	var cover: Node3D = scene.instantiate()
	cover.name = "Cover"
	cover.scale = Vector3.ONE * 1.7
	cover.rotation.y = PI
	cover.set_meta("asset_resource", CRATE)
	return cover

static func geometry_bounds(root: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect_bounds(root, Transform3D.IDENTITY, boxes)
	if boxes.is_empty(): return AABB()
	var result: AABB = boxes[0]
	for i in range(1, boxes.size()): result = result.merge(boxes[i])
	return result

static func _collect_bounds(node: Node, transform: Transform3D, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		boxes.append(transform * node.get_aabb())
	for child in node.get_children():
		_collect_bounds(child, transform * child.transform if child is Node3D else transform, boxes)
