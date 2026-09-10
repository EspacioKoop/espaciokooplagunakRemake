extends SceneTree
var checks := 0
var failures := 0
var capture := false
var lab

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("BIZIGAI_TEST_FAIL: ", message)

func settle(frames: int) -> void:
	for i in range(frames):
		await physics_frame

func count_static(node: Node) -> int:
	var total := 1 if node is StaticBody3D else 0
	for child in node.get_children():
		total += count_static(child)
	return total

func screenshot(filename: String) -> void:
	if not capture:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var directory := ProjectSettings.globalize_path("res://../docs/images/bizigai_pack")
	DirAccess.make_dir_recursive_absolute(directory)
	check(image.get_width() == 1600 and image.get_height() == 900, "capture dimensions")
	check(image.save_png(directory.path_join(filename)) == OK, "capture saved")

func _run() -> void:
	root.size = Vector2i(1600,900)
	Engine.time_scale = 4.0
	var packed: PackedScene = load("res://asset_lab/bizigai_pack/lab.tscn")
	check(packed != null, "lab scene loads")
	if packed == null:
		quit(1)
		return
	lab = packed.instantiate()
	root.add_child(lab)
	await process_frame
	await settle(3)
	check(lab.worlds.size() == 2, "two worlds")
	if lab.worlds.size() != 2:
		quit(1)
		return
	check(not lab.select_world(-1), "negative world rejected")
	check(not lab.select_world(2), "out of bounds world rejected")
	check(not lab.set_representation("invalid"), "unknown tier rejected")
	for wi in range(2):
		check(lab.select_world(wi), "world selection")
		var world: Dictionary = lab.worlds[wi]
		var ident: String = world["id"].get_slice("/", 1)
		check(world["habitable"] and world["breathable_atmosphere"], "habitable metadata")
		for tier in ["orbital", "approach", "surface"]:
			check(lab.set_representation(tier), "tier loads " + tier)
			await settle(3)
			check(count_static(lab.model) >= 22 if tier == "surface" else count_static(lab.model) == 0, "collision tier " + tier)
			for poi in world["pois"]:
				var arrival: Node3D = lab.model.find_child(poi["arrival_node"], true, false)
				check(arrival != null, "arrival anchor present")
				if arrival != null:
					var p: Array = poi["arrival_m"]
					check(arrival.global_position.distance_to(Vector3(p[0],p[1],p[2])) < 0.01, "same coordinates in " + tier)
			if tier == "orbital":
				await screenshot(ident + "_orbital.png")
		check(not lab.teleport_to_poi(-1), "negative arrival rejected")
		check(not lab.teleport_to_poi(16), "arrival out of bounds rejected")
		for i in range(16):
			check(lab.teleport_to_poi(i), "teleport " + str(i))
			await settle(28)
			check(lab.walker.position.is_finite(), "finite walker")
			check(lab.walker.is_on_floor(), "grounded at " + str(i))
			check(lab.walker.basis.y.dot(lab.walker.position.normalized()) > 0.999, "radial up at " + str(i))
			check(lab.walker.position.length() > float(world["radius_m"])-25, "arrival outside core")
		lab.teleport_to_poi(0)
		await settle(28)
		await screenshot(ident + "_surface.png")
		# Coverage of the actual imported terrain collision, not of the authoring formula.
		lab.walker.enabled = false
		var space: PhysicsDirectSpaceState3D = lab.get_world_3d().direct_space_state
		var radius := float(world["radius_m"])
		var directions: Array[Vector3] = [Vector3.UP,Vector3.DOWN,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]
		for i in range(720):
			var y := 1.0 - 2.0 * (float(i) + 0.5) / 720.0
			var a := float(i) * PI * (3.0-sqrt(5.0))
			directions.append(Vector3(sqrt(1-y*y)*sin(a),y,sqrt(1-y*y)*cos(a)))
		for axis in range(3):
			for i in range(180):
				var a := float(i) * TAU / 180.0
				var d := Vector3(sin(a),cos(a),0)
				if axis == 1:
					d = Vector3(0,sin(a),cos(a))
				elif axis == 2:
					d = Vector3(sin(a),0,cos(a))
				directions.append(d)
		for d in directions:
			var query := PhysicsRayQueryParameters3D.create(d*(radius+65.0), d*(radius-35.0), 1)
			var hit := space.intersect_ray(query)
			check(not hit.is_empty(), "closed spherical collision coverage")
			if not hit.is_empty():
				check(hit["position"].length() > radius-25.0, "surface not hidden floor")
		# Control basis must remain defined at both poles, including parallel heading inputs.
		for d in [Vector3.UP,Vector3.DOWN,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
			lab.walker.position = d*(radius+2)
			check(lab.walker.align_to_surface(d), "pole-safe tangent frame")
			check(absf(lab.walker.basis.determinant()-1.0)<0.001, "orthonormal frame")
			check(lab.walker.basis.y.dot(d)>0.999, "correct polar up")
		check(not lab.walker.place_at(Vector3.ZERO,Vector3.FORWARD), "reject core spawn")
		# Walk through the open arches and onward over curved imported terrain.
		lab.teleport_to_poi(5)
		await settle(28)
		var start: Vector3 = lab.walker.position
		lab.walker.test_drive = true
		lab.walker.drive_override = Vector2(0,1)
		await settle(140)
		lab.walker.drive_override = Vector2.ZERO
		await settle(12)
		check(lab.walker.position.distance_to(start)>20.0, "actual walking displacement")
		check(start.normalized().angle_to(lab.walker.position.normalized())>0.07, "actual radial orientation change")
		check(lab.walker.is_on_floor(), "grounded after curved walk")
		lab.walker.test_drive = false
		check(lab.set_representation("orbital"), "return to orbital")
		check(not lab.walker.enabled, "walker stops in orbit")
		check(count_static(lab.model)==0, "no orbital collision bodies")
	lab.queue_free()
	await process_frame
	Engine.time_scale = 1.0
	print("BIZIGAI_GODOT_PASS checks=",checks," failures=",failures," capture=",capture)
	quit(0 if failures==0 else 1)
