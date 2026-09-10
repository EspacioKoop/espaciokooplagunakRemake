extends SceneTree

func _initialize() -> void:
	call_deferred("capture_assets")

func capture_assets() -> void:
	var output: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--fieldkit-output="):
			output = arg.trim_prefix("--fieldkit-output=")
	if output.is_empty():
		push_error("Explicit output directory required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var scene: PackedScene = load("res://asset_lab/fieldkit_pack/viewer.tscn")
	var viewer: Node3D = scene.instantiate()
	root.add_child(viewer)
	await process_frame
	var count: int = 0
	for index: int in range(10):
		if not viewer.select_asset(index):
			push_error("Fieldkit selection failed")
			quit(1)
			return
		viewer.set_animating(false)
		viewer.set_equipped(false)
		for frame: int in range(6):
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var error: Error = image.save_png(output.path_join("asset_%02d.png" % index))
		if error != OK:
			push_error("Could not write asset evidence")
			quit(1)
			return
		count += 1
		if index < 8:
			viewer.set_equipped(true)
			for frame: int in range(6):
				await process_frame
			await RenderingServer.frame_post_draw
			image = root.get_texture().get_image()
			error = image.save_png(output.path_join("equipped_%02d.png" % index))
			if error != OK:
				push_error("Could not write equipment evidence")
				quit(1)
				return
			count += 1
	viewer.free()
	await process_frame
	print("FIELDKIT_CAPTURE_PASS frames=", count)
	quit(0)
