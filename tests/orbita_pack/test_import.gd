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
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/orbita_pack/manifest.json"))
	check(manifest is Dictionary, "manifest dictionary")
	if not manifest is Dictionary:
		_finish()
		return
	var entries: Array = manifest.get("assets", [])
	check(entries.size() == 12, "12 assets")
	for entry: Dictionary in entries:
		var id: String = entry.get("id", "")
		var packed: PackedScene = load(str(entry.get("resource", ""))) as PackedScene
		check(packed != null, id + " PackedScene")
		if packed == null:
			continue
		var model := packed.instantiate() as Node3D
		check(model != null, id + " Node3D")
		if model == null:
			continue
		root.add_child(model)
		await process_frame
		var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), id + " meshes")
		for item: Node in meshes:
			var mesh := item as MeshInstance3D
			check(mesh.mesh != null, id + " mesh resource")
			if mesh.mesh == null:
				continue
			check(mesh.get_aabb().size.length() > 0.0, id + " nonempty bounds")
			check(mesh.global_transform.origin.is_finite(), id + " finite transform")
			for surface: int in range(mesh.mesh.get_surface_count()):
				check(mesh.mesh.surface_get_material(surface) != null, id + " material")
		for anchor: Dictionary in entry.get("sockets", []):
			var expected: String = str(anchor.get("name", ""))
			check(model.find_child(expected, true, false) != null, id + " socket " + expected)
		check(model.find_children("*", "Camera3D", true, false).is_empty(), id + " no camera")
		check(model.find_children("*", "Light3D", true, false).is_empty(), id + " no light")
		var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
		var animation_count: int = 0
		for item: Node in players:
			var player := item as AnimationPlayer
			for name: StringName in player.get_animation_list():
				if name == &"RESET":
					continue
				animation_count += 1
				check(player.get_animation(name).length > 0.0, id + " clip duration")
				player.play(name)
				player.advance(0.5)
				check(player.is_playing(), id + " playable clip")
		check((animation_count > 0) == (not entry.get("animations", []).is_empty()), id + " animations survive import")
		model.queue_free()
		await process_frame
	var viewer_scene := load("res://asset_lab/orbita_pack/viewer.tscn") as PackedScene
	check(viewer_scene != null, "viewer scene")
	if viewer_scene != null:
		var viewer: Node = viewer_scene.instantiate()
		root.add_child(viewer)
		await process_frame
		for index: int in range(entries.size()):
			viewer.call("select_asset", index)
			await process_frame
			check(viewer.get("selected_index") == index, "viewer selects " + str(index))
			check(is_instance_valid(viewer.get("model")), "viewer model " + str(index))
		viewer.call("_set_motion", false)
		viewer.call("_set_motion", true)
		viewer.call("_reset_camera")
		viewer.call("select_asset", -1)
		check(viewer.get("selected_index") == 11, "negative selection rejected")
		viewer.call("select_asset", 99)
		check(viewer.get("selected_index") == 11, "oversized selection rejected")
		viewer.queue_free()
		await process_frame
	_finish()

func _finish() -> void:
	for failure: String in failures:
		printerr("ORBITA_ASSERT_FAIL " + failure)
	if failures.is_empty():
		print("ORBITA_GODOT_PASS assets=12 checks=" + str(checks))
		quit(0)
	else:
		printerr("ORBITA_GODOT_FAIL failures=" + str(failures.size()))
		quit(1)
