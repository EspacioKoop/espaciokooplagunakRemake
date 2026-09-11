class_name PickupModel
extends RefCounted
## Existing collection assets; visual scale does not change the host pickup radius.

const SUPPLY = "res://assets/models/frontier_pack/cargo_crate.glb"
const ARTIFACT = "res://assets/models/frontier_pack/mineral_cluster.glb"

static func create(kind: String) -> Node3D:
	if kind not in SpacePickups.KINDS: return null
	var scene: PackedScene = load(SUPPLY if kind == "supplydrop" else ARTIFACT)
	var root = Node3D.new()
	root.name = "SupplyDrop" if kind == "supplydrop" else "Artifact"
	var visual: Node3D = scene.instantiate()
	root.add_child(visual)
	var bounds = TacticalModels.geometry_bounds(visual)
	var extent = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	assert(extent > 0, "Pickup asset must contain geometry")
	var factor = (2.0 if kind == "supplydrop" else 2.5) / extent
	visual.scale = Vector3.ONE * factor
	visual.position = -bounds.get_center() * factor
	root.set_meta("asset_resource", scene.resource_path)
	return root
