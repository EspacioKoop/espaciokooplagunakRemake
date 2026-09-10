extends SceneTree

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/orbita_pack/player_batch/manifest.json"))
	check(parsed is Dictionary, "player manifest")
	if not parsed is Dictionary:
		_finish()
		return
	var entries: Array = parsed.get("assets", [])
	check(entries.size() == 10, "ten new models")
	var counts: Dictionary = {"tools": 0, "weapons": 0, "ships": 0}
	for entry: Dictionary in entries:
		var id: String = str(entry.get("id", ""))
		var category: String = str(entry.get("category", ""))
		check(counts.has(category), id + " category")
		if counts.has(category):
			counts[category] += 1
		var packed: PackedScene = load(str(entry.get("resource", ""))) as PackedScene
		check(packed != null, id + " load")
		if packed == null:
			continue
		var model: Node3D = packed.instantiate() as Node3D
		check(model != null, id + " instance")
		if model == null:
			continue
		root.add_child(model)
		await process_frame
		for item: Node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = item as MeshInstance3D
			check(mesh.mesh != null, id + " mesh")
			check(mesh.get_aabb().size.length() > 0.0, id + " bounds")
			check(mesh.global_transform.origin.is_finite(), id + " finite transform")
			for surface: int in range(mesh.mesh.get_surface_count()):
				check(mesh.mesh.surface_get_material(surface) != null, id + " PBR material")
		for socket_name: String in entry.get("required_sockets", []):
			var anchor: Node3D = model.find_child(socket_name, true, false) as Node3D
			check(anchor != null, id + " anchor " + socket_name)
			if anchor != null:
				check(anchor.global_transform.origin.is_finite(), id + " finite anchor")
		var old_poses: Dictionary = {}
		for node_name: String in entry.get("animated_nodes", []):
			var pivot: Node3D = model.find_child(node_name, true, false) as Node3D
			check(pivot != null, id + " pivot " + node_name)
			if pivot != null:
				old_poses[node_name] = pivot.transform
		var clips: int = 0
		for item: Node in model.find_children("*", "AnimationPlayer", true, false):
			var player: AnimationPlayer = item as AnimationPlayer
			for animation_name: StringName in player.get_animation_list():
				if animation_name == &"RESET":
					continue
				clips += 1
				check(player.get_animation(animation_name).length > 0.0, id + " clip duration")
				player.play(animation_name)
				player.advance(0.70)
		check(clips == 1, id + " one imported mechanical cycle")
		for node_name: String in old_poses:
			var pivot: Node3D = model.find_child(node_name, true, false) as Node3D
			var previous: Transform3D = old_poses[node_name]
			check(not pivot.transform.is_equal_approx(previous), id + " real animated movement " + node_name)
		check(model.find_children("*", "Camera3D", true, false).is_empty(), id + " no embedded camera")
		check(model.find_children("*", "Light3D", true, false).is_empty(), id + " no embedded light")
		model.queue_free()
		await process_frame
	check(counts == {"tools": 6, "weapons": 2, "ships": 2}, "6+2+2 exact distribution")
	var viewer_scene: PackedScene = load("res://asset_lab/orbita_pack/player_batch.tscn") as PackedScene
	check(viewer_scene != null, "combined viewer loads")
	if viewer_scene != null:
		var viewer: Node = viewer_scene.instantiate()
		root.add_child(viewer)
		await process_frame
		var combined: Array = viewer.get("entries")
		check(combined.size() == 22, "combined library has 22 models")
		for index: int in range(combined.size()):
			viewer.call("select_asset", index)
			await process_frame
			check(viewer.get("selected_index") == index, "selector " + str(index))
			check(is_instance_valid(viewer.get("model")), "renderable model " + str(index))
			var entry: Dictionary = combined[index]
			viewer.call("set_attachment_view", true)
			if not str(entry.get("attachment_socket", "")).is_empty():
				check(viewer.get("attachment_view") == true, "equipment view " + str(index))
				var mounted: Node3D = viewer.get("model") as Node3D
				var holder: Node3D = viewer.get("holder") as Node3D
				var anchor: Node3D = mounted.find_child(str(entry["attachment_socket"]), true, false) as Node3D
				check(holder.scale.is_equal_approx(Vector3.ONE), "physical metric scale " + str(index))
				check(anchor != null and anchor.global_position.distance_to(holder.global_position) < 0.001, "attachment aligned " + str(index))
			else:
				check(viewer.get("attachment_view") == false, "non-equipment mount rejected " + str(index))
			viewer.call("set_attachment_view", false)
			check(viewer.get("attachment_view") == false, "studio restored " + str(index))
		viewer.call("select_asset", -1)
		check(viewer.get("selected_index") == 21, "negative index rejected")
		viewer.call("select_asset", 999)
		check(viewer.get("selected_index") == 21, "large index rejected")
		viewer.call("_set_motion", false)
		viewer.call("_set_motion", true)
		viewer.call("_reset_camera")
		viewer.queue_free()
		await process_frame
	_finish()

func _finish() -> void:
	for failure: String in failures:
		printerr("ORBITA_ASSERT_FAIL " + failure)
	if failures.is_empty():
		print("ORBITA_PLAYER_GODOT_PASS assets=10 library=22 checks=" + str(checks))
		quit(0)
	else:
		printerr("ORBITA_PLAYER_GODOT_FAIL failures=" + str(failures.size()))
		quit(1)
