extends SceneTree

var checks: int = 0
var failures: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FIELDKIT_ASSERT_FAIL ", message)

func _initialize() -> void:
	call_deferred("run_tests")

func transforms(node: Node, output: Dictionary) -> void:
	if node is Node3D:
		output[str(node.get_path())] = (node as Node3D).transform
	for child: Node in node.get_children():
		transforms(child, output)

func run_tests() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/fieldkit_pack/manifest.json"))
	if not parsed is Dictionary:
		check(false, "manifest")
		finish()
		return
	var entries: Array = parsed.get("assets", [])
	check(entries.size() == 10, "exactly ten assets")
	for entry: Dictionary in entries:
		var id: String = entry["id"]
		var scene: Resource = load("res://" + str(entry["scene"]).trim_prefix("game/"))
		check(scene is PackedScene, id + " PackedScene")
		if not scene is PackedScene:
			continue
		var model := (scene as PackedScene).instantiate() as Node3D
		check(model != null, id + " Node3D")
		if model == null:
			continue
		root.add_child(model)
		await process_frame
		check(model.scale.is_equal_approx(Vector3.ONE), id + " unchanged metre scale")
		for socket_name: String in entry["sockets"]:
			var socket_node := model.find_child(socket_name, true, false) as Node3D
			check(socket_node != null, id + " " + socket_name)
			if socket_node != null:
				check(socket_node.global_position.is_finite(), id + " finite socket transform")
		var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), id + " actual meshes")
		var aggregate := AABB()
		var first: bool = true
		for node: Node in meshes:
			var mesh_node := node as MeshInstance3D
			check(mesh_node.mesh != null, id + " mesh resource")
			var local_aabb: AABB = (model.global_transform.affine_inverse() * mesh_node.global_transform) * mesh_node.get_aabb()
			aggregate = local_aabb if first else aggregate.merge(local_aabb)
			first = false
			for surface: int in range(mesh_node.mesh.get_surface_count()):
				check(mesh_node.get_active_material(surface) is BaseMaterial3D, id + " PBR material")
		var dims: Array = entry["dimensions"]
		var expected := Vector3(float(dims[0]), float(dims[1]), float(dims[2]))
		check(aggregate.size.distance_to(expected) < maxf(0.001, expected.length()*0.01), id + " exported dimensions")
		var animation_players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
		check(not animation_players.is_empty(), id + " AnimationPlayer imported")
		var moved: bool = false
		for node: Node in animation_players:
			var player := node as AnimationPlayer
			var clip: StringName = &""
			var clip_count: int = 0
			# Godot recognizes the _cycle suffix, enables looping and strips it.
			# Binary validation separately enforces the authored field_cycle name.
			print("FIELDKIT_IMPORTED_CLIPS ", id, " ", player.get_animation_list())
			for candidate: StringName in player.get_animation_list():
				if candidate == &"RESET":
					continue
				clip_count += 1
				if str(candidate) in ["field", "field_cycle"]:
					clip = candidate
			check(clip_count == 1, id + " exactly one mechanical clip")
			check(not clip.is_empty(), id + " authored or Godot-normalized name")
			if clip.is_empty():
				continue
			var animation := player.get_animation(clip)
			check(animation.length > 1.9, id + " complete animation duration")
			player.play(clip)
			player.advance(0.0)
			var before: Dictionary = {}
			transforms(model, before)
			player.advance(0.5)
			var after: Dictionary = {}
			transforms(model, after)
			for path: String in before:
				if after.has(path) and not (before[path] as Transform3D).is_equal_approx(after[path]):
					moved = true
			player.stop()
		check(moved, id + " clip moves real geometry")
		model.free()
	var viewer_scene: PackedScene = load("res://asset_lab/fieldkit_pack/viewer.tscn")
	var viewer: Node3D = viewer_scene.instantiate()
	root.add_child(viewer)
	await process_frame
	check(viewer.entries.size() == 10, "viewer catalogue")
	check(not viewer.select_asset(-1), "negative selection rejected")
	check(not viewer.select_asset(10), "out of range selection rejected")
	for i: int in range(10):
		viewer.selector.item_selected.emit(i)
		check(viewer.current_index == i, "selector opens " + str(i))
		check(is_instance_valid(viewer.current_model), "selected instance " + str(i))
		viewer.set_animating(false)
		check(not viewer.animating, "pause")
		viewer.set_animating(true)
		viewer.set_equipped(true)
		if i < 8:
			check(viewer.equipped, "equipment mode " + str(i))
			check(viewer.current_model.get_parent() == viewer.camera, "camera attachment")
			check(viewer.current_model.scale.is_equal_approx(Vector3.ONE), "equipment not rescaled")
			var socket_name: String = entries[i]["attachment_socket"]
			var anchor: Node3D = viewer.current_model.find_child(socket_name, true, false)
			var at_hand: Vector3 = viewer.camera.to_local(anchor.global_position)
			check(at_hand.distance_to(Vector3(0.19,-0.18,-0.44)) < 0.0001, "hand socket alignment")
		else:
			check(not viewer.equipped, "ships cannot be equipped as tools")
		viewer.reset_camera()
		check(not viewer.equipped and viewer.floor_mesh.visible, "inspection restored")
	viewer.free()
	await process_frame
	finish()

func finish() -> void:
	if failures == 0:
		print("FIELDKIT_GODOT_PASS assets=10 checks=", checks)
	else:
		print("FIELDKIT_GODOT_FAIL failures=", failures, " checks=", checks)
	quit(0 if failures == 0 else 1)
