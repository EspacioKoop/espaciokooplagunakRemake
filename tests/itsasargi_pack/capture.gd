extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	for tick in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://../build/itsasargi/" + name + ".png")
	if image == null or image.is_empty() or image.save_png(path) != OK:
		push_error("ASSET_CAPTURE_FAILED " + name)
		quit(1)

func run() -> void:
	root.size = Vector2i(1600, 900)
	var tools = load("res://asset_lab/itsasargi_pack/viewer.tscn").instantiate()
	root.add_child(tools)
	await process_frame
	tools.select_asset(0)
	await capture("itsasargi_tool")
	tools.select_asset(9)
	await capture("itsasargi_ship")
	root.remove_child(tools)
	tools.queue_free()
	await process_frame
	var lab = load("res://asset_lab/bizi_planets/viewer.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	lab.explorer.controls_enabled = false
	for index in range(2):
		lab.select_planet(index)
		await capture("bizi_" + str(index) + "_orbit")
		lab.enter_surface(-1)
		for tick in range(90):
			await physics_frame
		# Aim toward the actual authored arrival landmark, while retaining radial up.
		var landmark = lab.surface_model.find_child("poi_landing", true, false)
		if landmark != null:
			var up: Vector3 = lab.explorer.global_position.normalized()
			var forward: Vector3 = (landmark.global_position - lab.explorer.global_position).slide(up).normalized()
			if forward.length_squared() > 0.1:
				lab.explorer.global_basis = Basis(forward.cross(up).normalized(), up, -forward)
		lab.explorer.view_camera.rotation.x = -0.10
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await capture("bizi_" + str(index) + "_surface")
		lab.return_to_orbit()
	root.remove_child(lab)
	lab.queue_free()
	await process_frame
	print("ITSASARGI_CAPTURE_PASS six real Godot captures")
	quit(0)
