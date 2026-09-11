extends SceneTree
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("PORTU_TEST_FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func tick(count: int) -> void:
	for i in range(count):
		await physics_frame

func screenshot(name: String) -> void:
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty(), "actual frame " + name)
	if image != null and not image.is_empty():
		check(image.save_png(ProjectSettings.globalize_path("res://../build/portu/" + name + ".png")) == OK, "write screenshot")

func run() -> void:
	root.size = Vector2i(1600, 900)
	var scene := load("res://asset_lab/portu_environments/viewer.tscn") as PackedScene
	check(scene != null, "library scene loads")
	if scene == null:
		quit(1)
		return
	var lab = scene.instantiate()
	root.add_child(lab)
	await process_frame
	lab.walker.controls_enabled = false
	var capturing := OS.get_cmdline_user_args().has("--capture")
	var physics_rate := Engine.physics_ticks_per_second
	check(physics_rate > 0, "positive actual project physics rate")
	check(lab.entries.size() == 8, "eight destination templates")
	check(not lab.select_environment(-1) and not lab.select_environment(8), "invalid selection is rejected")
	for i in range(8):
		check(lab.select_environment(i), "instantiate environment " + str(i))
		await process_frame
		var room = lab.current_room
		check(room.ready_ok and room.collision_count >= 6, "real room collisions")
		check(room.scale == Vector3.ONE, "one-to-one metre scale")
		for socket in lab.entries[i].sockets:
			var anchor = room.find_child(str(socket.name), true, false)
			check(anchor is Node3D, "named anchor " + str(socket.name))
			if anchor is Node3D:
				var expected := Vector3(socket.position[0], socket.position[1], socket.position[2])
				check(anchor.global_position.distance_to(expected)<0.005, "authored anchor coordinates")
		if capturing:
			lab.enter_overview()
			await screenshot("overview_" + str(i))
			lab.enter_walk()
			room.toggle_door(Vector3(0, 0.1, 12))
			await tick(physics_rate)
			lab.walker.place(Vector3(0, 1, 7))
			await tick(physics_rate * 2)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			await screenshot("walk_" + str(i))
			continue
		check(not room.toggle_door(Vector3(10, 1, 15)), "distant door operation rejected")
		check(not room.toggle_door(Vector3(NAN, 0, 0)), "non-finite interaction rejected")
		check(not lab.walker.place(Vector3(0, -5, 0)), "invalid floor spawn rejected")
		lab.enter_walk()
		await tick(physics_rate * 2)
		check(lab.walker.is_on_floor(), "arrival grounded")
		check(not room.door_open, "arrival door closed")
		lab.walker.test_motion = Vector2(0, -1)
		await tick(physics_rate * 2)
		lab.walker.test_motion = Vector2.ZERO
		check(lab.walker.position.z>=10.15 and lab.walker.position.z<11.5, "closed door blocks actual walking")
		check(room.toggle_door(lab.walker.global_position), "nearby door opens")
		await tick(physics_rate)
		check(room.door_open, "open state")
		check(absf(room.doors[0].position.x-room.rest_x[0])>2.0, "left leaf moved")
		check(absf(room.doors[1].position.x-room.rest_x[1])>2.0, "right leaf moved")
		check(not room.toggle_door(Vector3(0, .1, 10)), "closure refuses occupied aperture")
		# This project runs at 30 physics Hz, independently of --fixed-fps 60.
		# Walk until the far route marker, with a measured ten-second deadline.
		# The old 300-tick assumption walked 40 m and continued out of the exit.
		var destination = room.marker("route_4")
		check(destination != null, "far destination anchor exists")
		var destination_z: float = destination.global_position.z if destination != null else -14.0
		lab.walker.test_motion = Vector2(0, -1)
		var elapsed_ticks: int = 0
		while lab.walker.global_position.z > destination_z and elapsed_ticks < physics_rate * 10:
			await physics_frame
			elapsed_ticks += 1
		lab.walker.test_motion = Vector2.ZERO
		await tick(1)
		print("PORTU_TRAVERSE id=", lab.entries[i].id, " physics_hz=", physics_rate, " ticks=", elapsed_ticks, " end=", lab.walker.global_position, " rescues=", lab.walker.rescued)
		check(lab.walker.global_position.z <= destination_z + 0.05, "walk through door to far destination")
		check(lab.walker.global_position.z > -16.5, "stop inside the exit, not outside the room")
		check(lab.walker.is_on_floor(), "traversal grounded")
		check(lab.walker.rescued == 0, "no out-of-world rescue")
		for route in range(5):
			var anchor = room.marker("route_" + str(route))
			check(anchor != null, "route marker")
			if anchor != null:
				check(lab.walker.place(anchor.global_position+Vector3.UP*.5), "route entry")
				await tick(physics_rate)
				check(lab.walker.is_on_floor(), "route has supporting floor")
		lab.enter_overview()
		check(not lab.walker.is_physics_processing(), "walker disabled in overview")
	root.remove_child(lab)
	lab.queue_free()
	await process_frame
	if capturing:
		print("PORTU_CAPTURE_PASS checks=", checks, " failures=", failures, " captures=16")
	else:
		print("PORTU_RUNTIME_PASS checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
