extends RefCounted
## Called by the canonical test_leisure suite, not an unexecuted side test.

static func run(runner: SceneTree) -> void:
	var deck = runner.deck
	var layout = preload("res://world/ship_deck_layout.gd")
	var hull = PackedVector2Array(layout.HULL)
	runner.check(WorldDeck.ZONES == layout.ZONES, "deck and map share one room coordinate contract")
	runner.check(layout.ZONES[0].at.z < -20 and layout.ZONES[2].at.z > 20, "glazed bow contains bridge; engineering is at stern")
	runner.check(layout.ZONES[3].at.x < 0 and layout.ZONES[6].at.x > 0, "quarters and medbay flank the habitable spine")
	for i in layout.SHIP_COUNT:
		runner.check(deck._zone_models[i].position.is_equal_approx(layout.ZONES[i].at), "room model uses shared position %d" % i)
		runner.check(is_equal_approx(deck._zone_models[i].rotation.y, layout.ROOM_YAW[i]), "room opening faces its portal %d" % i)
		for corner in layout.room_polygon(i):
			runner.check(Geometry2D.is_point_in_polygon(corner, hull), "room %d fits inside the hull envelope" % i)
		for other in range(i + 1, layout.SHIP_COUNT):
			runner.check(Geometry2D.intersect_polygons(layout.room_polygon(i), layout.room_polygon(other)).is_empty(), "rooms %d/%d do not overlap" % [i, other])
		var screen: Vector2 = deck._map._point(layout.ZONES[i].at)
		runner.check(deck._map._world(screen).distance_to(layout.ZONES[i].at) < 0.001, "map inverse agrees with room %d" % i)
	var horizontal: float = deck._map._point(Vector3(10, 0, 0)).distance_to(deck._map._point(Vector3.ZERO))
	var vertical: float = deck._map._point(Vector3(0, 0, 10)).distance_to(deck._map._point(Vector3.ZERO))
	runner.check(is_equal_approx(horizontal, vertical), "map preserves metric proportions rather than stretching axes")
	for link in deck._corridors.links:
		var delta: Vector3 = link.finish - link.start
		runner.check(absf(delta.x) < 0.001 or absf(delta.z) < 0.001, "connector is straight and orthogonal")
		runner.check(link.length < 8.0, "short vestibule replaces an oversized diagonal branch")
		runner.check(link.finish.is_equal_approx(layout.entry(link.target)), "corridor terminates at the authored room opening")
		for corner in layout.corridor_polygon(link):
			runner.check(Geometry2D.is_point_in_polygon(corner, hull), "corridor fits inside the hull")
		var middle: Vector3 = (link.start + link.finish) * 0.5
		runner.check(layout.zone_for(middle, link.target) == 1, "connector remains circulation until actual room entry")
	for source in layout.SHIP_COUNT:
		for target in layout.SHIP_COUNT:
			var route: PackedVector3Array = layout.route(layout.spawn(source), target)
			if source == target:
				runner.check(route.is_empty(), "no route needed inside destination")
				continue
			runner.check(route.size() >= 2, "walking route exists %d to %d" % [source, target])
			for segment in range(1, route.size()):
				for sample in 11:
					var point = route[segment - 1].lerp(route[segment], sample / 10.0)
					runner.check(layout.contains(point), "route %d/%d stays on real room/corridor footprints" % [source, target])
	runner.check(layout.route(Vector3.ZERO, -1).is_empty() and layout.route(Vector3.ZERO, 7).is_empty(), "invalid and social route targets rejected")
	runner.check(layout.zone_for(Vector3.ZERO, 9) == 9, "social zone identity is not replaced by ship detection")
	runner.check(not layout.contains(Vector3(100, 0, 0)) and not layout.contains(Vector3(0, 10, 0)), "off-deck positions are not projected as crew inside ship")
	var before: Vector3 = deck.body.position
	var gates: Array = deck._corridors.doors.map(func(door): return door.open)
	deck._map.select_destination(2)
	runner.check(deck._map.destination == 2 and deck.body.position == before, "route selection never teleports")
	runner.check(deck._corridors.doors.map(func(door): return door.open) == gates, "route selection never opens hatches")
	deck._map.select_destination(-1)
	for i in layout.SHIP_COUNT:
		deck.teleport_zone(i)
		await runner.settle(18)
		runner.check(deck.body.is_on_floor() and deck.zone == i, "rotated arrival has reachable floor in " + layout.ZONES[i].name)
	var previous_motion: bool = deck.reduced_motion
	var controls = runner.root.get_node("Controls")
	var previous_touch: bool = controls.touch.enabled
	var previous_walking: bool = controls.touch.walking
	var previous_paused: bool = runner.session.paused
	controls.touch.set_enabled(true)
	controls.touch.walking = true
	runner.session.paused = true
	deck.reduced_motion = true
	for index in deck._corridors.doors.size():
		var door: Dictionary = deck._corridors.doors[index]
		var normal = Vector3(sin(door.yaw), 0, cos(door.yaw))
		for side in [-1.0, 1.0]:
			var point: Vector3 = door.position + normal * side * 1.2
			runner.check(deck._corridors.near_door(point, 1) == index, "hatch %d is operable from side %s" % [index, side])
			runner.check(deck._corridors.destination_for(index, point) == (door.target if side < 0 else door.source), "hatch label names the destination on this side")
		deck.body.position = door.position - normal * 1.2 + Vector3(0, 0.4, 0)
		deck.body.velocity = Vector3.ZERO
		await runner.settle(12)
		runner.check(deck._corridors.set_open(index, false), "empty hatch can close")
		await runner.settle(3)
		runner.check(deck.body.test_move(deck.body.global_transform, normal * 2.0), "closed hatch has real collision %d" % index)
		runner.check(is_equal_approx(door.panel.position.y, 1.35), "reduced motion closes without tween")
		deck._corridors.set_open(index, true)
		await runner.settle(3)
		runner.check(door.collider.disabled, "open hatch releases its collider %d" % index)
		# A horizontal test_move may report the supporting floor at the hallway
		# seam. Require actual movement across each open portal instead: this also
		# detects blockers, fall recovery and discontinuities, not just its flag.
		var crossed: bool = await preload("res://../tests/test_ship_corridors.gd").walk(runner, door.position + normal * 0.8, "open hatch crossing %d" % index)
		runner.check(crossed, "open hatch provides real physical passage %d" % index)
		deck.body.position = door.position + Vector3(0, 0.1, 0)
		deck.body.velocity = Vector3.ZERO
		runner.check(not deck._corridors.set_open(index, false) and door.open, "hatch refuses to close onto a player %d" % index)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	controls.touch.set_enabled(previous_touch)
	controls.touch.walking = previous_walking
	runner.session.paused = previous_paused
	deck.reduced_motion = previous_motion
	deck.teleport_zone(0)
	await runner.settle(3)
