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
		if node is Skeleton3D:
			var skeleton := node as Skeleton3D
			for index: int in range(skeleton.get_bone_count()):
				parts.append(str(skeleton.get_bone_pose(index)))
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
		var scene := load(str(entry["glb"])) as PackedScene
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
			var mesh := child as MeshInstance3D
			check(mesh.mesh != null and mesh.mesh.get_surface_count() > 0, identifier + " contains renderable surfaces")
			check(mesh.get_aabb().size.is_finite() and mesh.get_aabb().size.length() > 0, identifier + " has finite bounds")
		for anchor: String in entry.get("sockets", []):
			check(instance.find_child(anchor, true, false) != null, identifier + " socket " + anchor)
		var players: Array[Node] = instance.find_children("*", "AnimationPlayer", true, false)
		var expected: Array = entry.get("animations", [])
		if not expected.is_empty():
			check(not players.is_empty(), identifier + " imports AnimationPlayer")
			var names: Array[String] = []
			var changed: bool = false
			for player_node: Node in players:
				var player := player_node as AnimationPlayer
				for animation_name: StringName in player.get_animation_list():
					if animation_name == &"RESET":
						continue
					names.append(str(animation_name))
					var animation: Animation = player.get_animation(animation_name)
					check(animation.length > 0 and animation.get_track_count() > 0, identifier + " nonempty clip " + str(animation_name))
					player.play(animation_name)
					player.seek(0.0, true)
					player.advance(0.0)
					var before: String = signature(instance)
					player.seek(minf(animation.length * 0.31, 0.63), true)
					player.advance(0.0)
					changed = changed or before != signature(instance)
					player.stop()
			check(names.size() >= expected.size(), identifier + " preserves animation clip count")
			check(changed, identifier + " animation changes transforms or bone poses")
		if int(entry.get("skins", 0)) > 0:
			var skeletons: Array[Node] = instance.find_children("*", "Skeleton3D", true, false)
			check(not skeletons.is_empty(), identifier + " imports skeleton")
			for skeleton: Node in skeletons:
				check((skeleton as Skeleton3D).get_bone_count() >= int(entry["joints"]), identifier + " preserves bones")
		root.remove_child(instance)
		instance.free()
		await process_frame
	# Parse and instantiate the real gallery, including all of its UI controls.
	var lab_scene := load("res://asset_lab/frontier_pack/showcase.tscn") as PackedScene
	check(lab_scene != null, "Gallery scene parses")
	if lab_scene != null:
		var lab: Node = lab_scene.instantiate()
		root.add_child(lab)
		await process_frame
		check(lab.get("entries").size() == 24, "Gallery loads complete catalogue")
		for index: int in range(24):
			lab.call("_select_asset", index)
			await process_frame
			check(is_instance_valid(lab.get("model")), "Gallery selects asset " + str(index))
		lab.call("_select_asset", -1)
		lab.call("_select_asset", 999)
		check(int(lab.get("selected_index")) == 23, "Out-of-range selection does not mutate state")
		root.remove_child(lab)
		lab.free()
	print("FRONTIER_GODOT_RESULT " + JSON.stringify({"checks": checks, "failures": failures, "assets": entries.size(), "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
