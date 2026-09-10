extends SceneTree
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ASSET_TEST_FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func mesh_checks(node: Node) -> void:
	if node is MeshInstance3D:
		check(node.mesh != null and node.mesh.get_surface_count() > 0, "mesh surfaces " + str(node.name))
		if node.mesh != null:
			check(node.get_aabb().size.is_finite(), "finite bounds")
			for i in node.mesh.get_surface_count():
				check(node.mesh.surface_get_material(i) != null, "material " + str(node.name))
	for child in node.get_children():
		mesh_checks(child)

func run() -> void:
	var tool_scene := load("res://asset_lab/itsasargi_pack/viewer.tscn") as PackedScene
	check(tool_scene != null, "tool scene loads")
	if tool_scene == null:
		quit(1)
		return
	var tools = tool_scene.instantiate()
	root.add_child(tools)
	await process_frame
	check(tools.entries.size() == 10, "ten tools/weapons/ships")
	check(not tools.select_asset(-1) and not tools.select_asset(10), "invalid tool selection")
	for i in range(tools.entries.size()):
		check(tools.select_asset(i), "select tool " + str(i))
		await process_frame
		mesh_checks(tools.current_model)
		for socket in tools.entries[i].sockets:
			var found = tools.current_model.find_child(str(socket.name), true, false)
			check(found is Node3D, "socket imported " + str(socket.name))
			if found is Node3D:
				check(found.global_position.is_finite(), "finite socket")
		check(not tools.players.is_empty(), "mechanism player imported")
		tools.toggle_animation()
		for player in tools.players:
			check(player.is_playing(), "mechanism plays")
			player.advance(1.0)
		tools.toggle_animation()
	root.remove_child(tools)
	tools.queue_free()
	await process_frame
	var planet_scene := load("res://asset_lab/bizi_planets/viewer.tscn") as PackedScene
	check(planet_scene != null, "planet scene loads")
	if planet_scene == null:
		quit(1)
		return
	var lab = planet_scene.instantiate()
	root.add_child(lab)
	await process_frame
	lab.explorer.controls_enabled = false
	check(lab.planets.size() == 2, "two habitable planets")
	check(not lab.select_planet(-1) and not lab.select_planet(2), "invalid planet selections")
	check(not lab.enter_surface(-2) and not lab.enter_surface(14), "invalid POI selections")
	check(not lab.collect_nearby(), "no collection from orbit")
	for index in range(2):
		check(lab.select_planet(index), "select planet")
		var planet: Dictionary = lab.planets[index]
		check(planet.habitable == true, "explicit habitable marker")
		check(lab.enter_surface(-1), "teleport arrival")
		check(lab.surface_model.scale == Vector3.ONE, "surface uses real unscaled metres")
		check(not lab.orbital_model.visible and lab.surface_model.visible, "only one representation shown")
		check(lab.collision_count >= 8, "terrain and props have collision")
		for tick in range(90):
			await physics_frame
		check(lab.explorer.is_on_floor(), "arrival rests on floor")
		check(lab.explorer.up_direction.dot(lab.explorer.global_position.normalized()) > 0.999, "radial up direction")
		var radius: float = planet.radius_m
		var space = lab.get_world_3d().direct_space_state
		# Rays cover all octants, both poles, the equator and intermediate latitudes.
		for lat in range(-90, 91, 15):
			for lon in range(0, 360, 20):
				var a := deg_to_rad(float(lat))
				var b := deg_to_rad(float(lon))
				var direction := Vector3(cos(a)*cos(b), sin(a), cos(a)*sin(b))
				var query := PhysicsRayQueryParameters3D.create(direction*(radius+25), direction*(radius-15), 1)
				var hit: Dictionary = space.intersect_ray(query)
				check(not hit.is_empty(), "closed sphere ray %s %d %d" % [planet.id, lat, lon])
				if not hit.is_empty():
					check(absf(hit.position.length()-radius)<22, "surface radius")
		for i in range(14):
			check(lab.enter_surface(i), "POI entry " + str(i))
			for tick in range(50):
				await physics_frame
			check(lab.explorer.global_position.is_finite(), "POI finite position")
			check(lab.explorer.is_on_floor(), "POI has reachable supporting ground " + str(i))
			check(lab.explorer.global_position.length()>radius-7, "no fall through planet")
		# Pole-crossing orientation uses transported tangents, not a fixed world-up camera.
		for direction in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			var query := PhysicsRayQueryParameters3D.create(direction*(radius+25),direction*(radius-15),1)
			var hit: Dictionary = space.intersect_ray(query)
			if hit.is_empty():
				continue
			check(lab.explorer.teleport_to(hit.position+direction*2.0), "cardinal teleport")
			for tick in range(65):
				await physics_frame
			check(lab.explorer.global_basis.is_finite(), "stable pole basis")
			check(lab.explorer.up_direction.dot(direction)>0.98, "radial pole gravity")
		check(not lab.explorer.teleport_to(Vector3.ZERO), "reject planet centre")
		check(not lab.explorer.activate(Vector3.UP*radius, -1.0), "reject invalid radius")
		var resource: Dictionary = planet.resources[0]
		var point := Vector3(resource.position[0],resource.position[1],resource.position[2])
		check(lab.explorer.teleport_to(point+point.normalized()*0.25), "approach resource")
		check(lab.collect_nearby(), "collect local resource")
		var first_count: int = lab.collected.size()
		check(first_count == 1, "one resource per action")
		check(lab.collected.has(str(resource.socket)), "correct resource id")
		for repeat in range(4):
			lab.collect_nearby()
		check(lab.collected.size()<=2, "cannot duplicate collected resources")
		check(lab.explorer.rescue_count == 0, "no out-of-world rescue needed")
		lab.return_to_orbit()
		check(lab.orbital_model.visible and not lab.surface_model.visible, "return orbital representation")
		check(not lab.explorer.is_physics_processing(), "surface controller inactive in orbit")
		check(not lab.collect_nearby(), "orbital resource collection rejected")
	root.remove_child(lab)
	lab.queue_free()
	await process_frame
	print("ITSASARGI_GODOT_PASS checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
