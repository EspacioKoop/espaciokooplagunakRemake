extends SceneTree

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FRONTIER_TEST_FAIL: " + message)


func signature(instance: Node) -> String:
	var parts: Array[String] = []
	for node: Node in instance.find_children("*", "Node3D", true, false):
		parts.append(str((node as Node3D).transform))
	# Inspect skeletons explicitly; their animation is stored in bone properties,
	# not in the Node3D transform of the imported rig node.
	for node: Node in instance.find_children("*", "Skeleton3D", true, false):
		var skeleton: Skeleton3D = node as Skeleton3D
		skeleton.force_update_all_bone_transforms()
		for index: int in range(skeleton.get_bone_count()):
			parts.append(str(skeleton.get_bone_pose_rotation(index)))
			parts.append(str(skeleton.get_bone_pose_position(index)))
			parts.append(str(skeleton.get_bone_global_pose(index)))
	return "|".join(parts)


func _run() -> void:
	var raw: String = FileAccess.get_file_as_string("res://assets/models/frontier_pack/manifest.json")
	var manifest: Variant = JSON.parse_string(raw)
	check(manifest is Dictionary, "Manifest imports")
	if not manifest is Dictionary:
		quit(1)
		return
	var entries: Array = manifest.get("assets", [])
	check(entries.size() == 24, "All 24 resources are present")
	for entry: Dictionary in entries:
		var identifier: String = str(entry["id"])
		var scene: PackedScene = load(str(entry["glb"])) as PackedScene
		check(scene != null, identifier + " imports as PackedScene")
		if scene == null:
			continue
		var instance: Node = scene.instantiate()
		check(instance is Node3D, identifier + " has Node3D root")
		root.add_child(instance)
		await process_frame
		var meshes: Array[Node] = instance.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), identifier + " contains mesh instances")
		for child: Node in meshes:
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			check(mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0, identifier + " contains renderable surfaces")
			check(mesh_instance.get_aabb().size.is_finite() and mesh_instance.get_aabb().size.length() > 0, identifier + " has finite bounds")
		for anchor: String in entry.get("sockets", []):
			check(instance.find_child(anchor, true, false) != null, identifier + " socket " + anchor)
		var players: Array[Node] = instance.find_children("*", "AnimationPlayer", true, false)
		var expected: Array = entry.get("animations", [])
		if not expected.is_empty():
			check(not players.is_empty(), identifier + " imports AnimationPlayer")
			var names: Array[String] = []
			for player_node: Node in players:
				var player: AnimationPlayer = player_node as AnimationPlayer
				player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				player.active = true
				for animation_name: StringName in player.get_animation_list():
					if animation_name == &"RESET":
						continue
					names.append(str(animation_name))
					var animation: Animation = player.get_animation(animation_name)
					check(animation.length > 0 and animation.get_track_count() > 0, identifier + " nonempty clip " + str(animation_name))
					player.stop()
					player.play(animation_name)
					player.advance(0.0)
					# Skeleton updates are deferred; allow one frame before observing
					# the pose, while manual mode keeps animation time deterministic.
					await process_frame
					var before: String = signature(instance)
					player.advance(minf(animation.length * 0.31, 0.63))
					await process_frame
					var after: String = signature(instance)
					check(before != after, identifier + " clip moves imported scene: " + str(animation_name))
					if before == after:
						for track_index: int in range(animation.get_track_count()):
							if animation.track_get_key_count(track_index) > 1:
								print("ANIMATION_DIAGNOSTIC ", identifier, " ", animation_name, " ", animation.track_get_path(track_index), " keys=", animation.track_get_key_count(track_index))
					player.stop()
			check(names.size() >= expected.size(), identifier + " preserves animation clip count")
		if int(entry.get("skins", 0)) > 0:
			var skeletons: Array[Node] = instance.find_children("*", "Skeleton3D", true, false)
			check(not skeletons.is_empty(), identifier + " imports skeleton")
			for skeleton_node: Node in skeletons:
				check((skeleton_node as Skeleton3D).get_bone_count() >= int(entry["joints"]), identifier + " preserves bones")
		root.remove_child(instance)
		instance.free()
		await process_frame
	var gallery_scene: PackedScene = load("res://asset_lab/frontier_pack/showcase.tscn") as PackedScene
	check(gallery_scene != null, "Gallery scene parses")
	if gallery_scene != null:
		var gallery_instance: Node = gallery_scene.instantiate()
		root.add_child(gallery_instance)
		await process_frame
		var gallery_entries: Array = gallery_instance.get("entries")
		check(gallery_entries.size() == 24, "Gallery loads complete catalogue")
		for index: int in range(24):
			gallery_instance.call("_select_asset", index)
			await process_frame
			var displayed_model: Variant = gallery_instance.get("model")
			check(is_instance_valid(displayed_model), "Gallery selects asset " + str(index))
		gallery_instance.call("_select_asset", -1)
		gallery_instance.call("_select_asset", 999)
		check(int(gallery_instance.get("selected_index")) == 23, "Out-of-range selection does not mutate state")
		root.remove_child(gallery_instance)
		gallery_instance.free()
	print("FRONTIER_GODOT_RESULT " + JSON.stringify({"checks": checks, "failures": failures, "assets": entries.size(), "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
