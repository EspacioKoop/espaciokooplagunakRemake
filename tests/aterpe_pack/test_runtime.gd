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
	var packed: PackedScene = load("res://asset_lab/aterpe_pack/viewer.tscn") as PackedScene
	check(packed != null, "Aterpe scene imports")
	if packed == null:
		quit(1)
		return
	var lab: Node = packed.instantiate()
	root.add_child(lab)
	await process_frame
	check(lab.entries.size() == 2, "Two habitable planets")
	for planet_index in range(2):
		check(lab.select_planet(planet_index), "Select planet")
		check(lab._orbital_model("approach"), "Approach model loads")
		check(lab._orbital_model("orbit"), "Orbital model loads")
		check(not lab._orbital_model("../../private"), "Reject invalid LOD")
		check(await lab.land(0), "Teleport from orbit")
		var planet: Node3D = lab.surface
		lab.walker.enabled = false
		check(planet.ready_for_landing, "Complete landable surface")
		check(planet.terrain_bodies == 96, "96 physical terrain sectors")
		check(planet.structure_bodies == 16, "16 physical places")
		var radius: float = planet.radius()
		# Global coverage with Fibonacci rays; includes the far hemisphere, not just a landing patch.
		for i in range(512):
			var y: float = 1.0 - 2.0 * (float(i) + 0.5) / 512.0
			var angle: float = float(i) * 2.399963229728653
			var side: float = sqrt(1.0 - y * y)
			var direction := Vector3(cos(angle) * side, y, sin(angle) * side)
			var hit: Dictionary = planet.ground(direction, 1)
			check(not hit.is_empty(), "Full sphere collision ray %d" % i)
			if not hit.is_empty():
				var point: Vector3 = hit["position"]
				check(absf(point.length() - radius) < 12.0, "Ground close to design radius")
				var normal: Vector3 = hit["normal"]
				check(normal.dot(direction) > 0.55, "Outward walkable terrain normal")
		for axis in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			check(not planet.ground(axis).is_empty(), "Pole/axis collision")
		check(planet.ground(Vector3.ZERO).is_empty(), "Reject zero ray")
		check(planet.ground(Vector3(NAN, 0, 0)).is_empty(), "Reject NaN ray")
		check(planet.ground(Vector3.UP, 0).is_empty(), "Reject collision mask zero")
		check(planet.marker(-1) == null and planet.marker(16) == null, "Reject bad POI index")
		check(planet.marker(0, "secret") == null, "Reject unsupported anchor role")
		for poi_index in range(16):
			check(await lab.land(poi_index), "Land at all named places")
			var start: Vector3 = lab.walker.global_position
			lab.walker.use_scripted_input = true
			lab.walker.scripted_input = Vector2(0.3, 0.7)
			for frame in range(18):
				await physics_frame
			check(lab.walker.global_position.is_finite(), "Walker finite at every POI")
			check(lab.walker.global_position.length() > radius - 12.0, "No fall through site")
			check(lab.walker.global_position.distance_to(start) < 6.0, "No teleport while walking")
			check(lab.walker.up_direction.dot(lab.walker.global_position.normalized()) > 0.99, "Radial orientation")
			lab.walker.enabled = false
		# Real capsule motion at cube-face seams and poles.
		for direction in [Vector3(1, 0, 1).normalized(), Vector3(-1, 1, 0).normalized(), Vector3(0, -1, -1).normalized(), Vector3.UP, Vector3.DOWN]:
			var hit: Dictionary = planet.ground(direction)
			if hit.is_empty():
				check(false, "Seam collision")
				continue
			var forward: Vector3 = direction.cross(Vector3.RIGHT)
			if forward.length_squared() < 0.1:
				forward = direction.cross(Vector3.FORWARD)
			check(lab.walker.place(hit["position"] + direction * 1.08, direction, forward), "Place at seam/pole")
			lab.walker.scripted_input = Vector2(0, 1)
			lab.walker.enabled = true
			var before: Vector3 = lab.walker.global_position
			for frame in range(40):
				await physics_frame
			check(before.distance_to(lab.walker.global_position) > 0.3, "Movement around seam/pole")
			check(lab.walker.global_position.length() > radius - 10.0, "Seam/pole retains ground")
			lab.walker.enabled = false
		var before_invalid: Vector3 = lab.walker.global_position
		check(not lab.walker.place(Vector3(NAN, 0, 0), Vector3.UP, Vector3.FORWARD), "Reject invalid placement")
		check(lab.walker.global_position == before_invalid, "Invalid pose preserves state")
		check(not await lab.land(-1), "Reject invalid teleport")
		check(not await lab.land(16), "Reject excessive teleport")
		lab.return_to_orbit()
		check(not lab.on_surface and not lab.walker.enabled and lab.surface == null, "Return removes surface collision")
		await physics_frame
	check(not lab.select_planet(-1) and not lab.select_planet(2), "Reject invalid planet")
	lab.queue_free()
	await process_frame
	print("ATERPE_GODOT_PASS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
