extends SceneTree

var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed: PackedScene = load("res://asset_lab/lantegi_pack/viewer.tscn") as PackedScene
	check(packed != null, "Viewer scene must import")
	if packed == null:
		quit(1)
		return
	var lab: Node = packed.instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame
	check(lab.entries.size() == 10, "Ten entries in real inspector")
	for index in range(lab.entries.size()):
		check(lab.select_asset(index), "Select asset %d" % index)
		await process_frame
		var model: Node3D = lab.current_model
		var entry: Dictionary = lab.entries[index]
		check(model != null and model.is_inside_tree(), "Model instantiated")
		for socket in entry["sockets"]:
			var anchor: Node3D = model.find_child(str(socket["name"]), true, false) as Node3D
			check(anchor != null, "Missing socket " + str(socket["name"]))
			if anchor != null:
				check(anchor.global_position.is_finite(), "Nonfinite anchor")
		var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), "Model contains meshes")
		for node in meshes:
			var mesh := node as MeshInstance3D
			check(mesh.mesh != null and mesh.mesh.get_surface_count() > 0, "Mesh surfaces")
			for surface in range(mesh.mesh.get_surface_count()):
				check(mesh.get_active_material(surface) != null, "PBR material survives import")
		var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
		check(not players.is_empty(), "Mechanical animation imported")
		var moved: bool = false
		for node in players:
			var player := node as AnimationPlayer
			for clip in player.get_animation_list():
				if clip == "RESET":
					continue
				check(player.get_animation(clip).length > 0.1, "Animation duration")
				player.play(clip)
				player.seek(0.0, true)
				var before: Dictionary = {}
				for part in model.find_children("*", "Node3D", true, false):
					before[part.get_instance_id()] = part.transform
				player.seek(0.8, true)
				for part in model.find_children("*", "Node3D", true, false):
					var initial: Transform3D = before[part.get_instance_id()]
					if not initial.is_equal_approx(part.transform):
						moved = true
		check(moved, "Animation changes rigid geometry " + str(entry["id"]))
	var previous: int = lab.selected
	check(not lab.select_asset(-1), "Reject negative selection")
	check(not lab.select_asset(100), "Reject excessive selection")
	check(lab.selected == previous, "Invalid selection preserves current model")
	lab.toggle_animation()
	check(not lab.playing, "Pause")
	lab.toggle_animation()
	check(lab.playing, "Resume")
	lab.queue_free()
	await process_frame
	print("LANTEGI_GODOT_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
