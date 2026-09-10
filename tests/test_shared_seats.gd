extends SceneTree
var failures = 0
var checks = 0
var session
var seats
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("SEATS_FAIL " + label)
func run() -> void:
	session = root.get_node("Session")
	seats = root.get_node("SeatPresence")
	var catalog = PhysicalSeatCatalog.all_seats()
	check(catalog.size() == 8, "eight physical seats derive from leisure interactions")
	for id in catalog:
		var seat: Dictionary = catalog[id]
		check(PhysicalSeatCatalog.reachable(seat, seat.approach), "physical approach " + id)
		check(not PhysicalSeatCatalog.reachable(seat, seat.approach + Vector3(0, 2, 0)), "reject elevated approach " + id)
		check(not PhysicalSeatCatalog.reachable(seat, Vector3(NAN, 0, 0)), "reject nonfinite position " + id)
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	session.new_campaign()
	app._go("deck")
	await process_frame
	var deck = app._deck
	deck.teleport_zone(10)
	var seat: Dictionary = catalog.seat_10_0
	check(not seats.request_sit("seat_10_0").ok, "distant local player cannot teleport into seat")
	check(not seats.request_sit("missing").ok, "unknown seat rejected")
	deck.body.position = seat.approach + Vector3(0, 0.2, 0)
	deck.body.velocity = Vector3.ZERO
	await create_timer(0.3).timeout
	var standing: Vector3 = deck.body.position
	deck.interact()
	check(deck.seated and seats.occupant("seat_10_0") == 1, "executable interaction reserves seat")
	check(deck.body.position == seat.anchor and deck.body.collision_mask == 0, "body physically anchors to catalog seat")
	var anchor: Vector3 = deck.body.position
	deck._apply_look(Vector2(2, 0.2))
	check(deck.body.position == anchor and is_equal_approx(deck.body.rotation.y, seat.yaw), "looking does not rotate or slide seated body")
	check(not is_zero_approx(deck.camera.rotation.y), "seated player can turn head")
	check(not seats.request_sit("seat_10_1").ok, "cannot reserve two seats")
	deck.interact()
	check(not deck.seated and seats.occupant("seat_10_0") == 0, "standing releases immediately")
	check(deck.body.position == standing and deck.body.collision_mask == 1, "standing restores reachable approach and collision")
	check(is_zero_approx(deck.camera.rotation.y) and is_equal_approx(deck.camera.position.y, 1.65), "standing restores camera")
	deck.interact()
	check(deck.seated, "can sit again")
	deck.teleport_zone(8)
	check(not deck.seated and seats.occupant("seat_10_0") == 0 and deck.zone == 8, "changing zone releases without reanchoring")
	# A late accepted-sit packet must not undo a zone transition while its
	# reliable stand cancellation is awaiting acknowledgement.
	var destination: Vector3 = deck.body.position
	deck._seat_requested = true
	deck._leaving_seat = true
	deck._sync_seat()
	check(deck._leaving_seat, "empty old projection does not acknowledge pending cancellation")
	seats._occupants[seat.id] = 1
	seats.changed.emit()
	check(not deck.seated and deck.body.position == destination, "late sit snapshot cannot reanchor after zone change")
	seats.request_finished.emit("sit", true, "Sentado")
	check(deck._leaving_seat and not deck._seat_requested and not deck.seated, "sit response does not acknowledge stand cancellation")
	seats._occupants.clear()
	seats.request_finished.emit("stand", true, "De pie")
	check(not deck._leaving_seat and not deck.seated, "only stand response completes cancellation")
	deck.teleport_zone(10)
	deck.body.position = seat.approach
	check(seats.request_sit("seat_10_0").ok, "reserve for deck close")
	app._go("bridge")
	await process_frame
	check(seats.occupant("seat_10_0") == 0, "closing deck releases reservation")
	app._go("deck")
	await process_frame
	deck = app._deck
	deck.teleport_zone(10)
	session.poses[2] = {"position": [seat.approach.x, 0.2, seat.approach.z], "yaw": 1.0}
	check(seats._command(2, "sit", seat.id).ok, "host logic accepts remote trusted position")
	deck._update_avatars(session)
	var remote: Node3D = deck._avatars[2]
	check(remote.position == seat.anchor + Vector3(0, -0.4, 0) and bool(remote.get_meta("physical_seat_pose")), "real deck renderer applies replicated sitting posture")
	session.poses[2] = {"position": [seat.approach.x + 4, 0.2, seat.approach.z], "yaw": 2.0}
	deck._update_avatars(session)
	check(remote.position == seat.anchor + Vector3(0, -0.4, 0), "walking packets cannot displace a reserved sitting avatar")
	seats._command(2, "stand", "")
	deck._update_avatars(session)
	check(not bool(remote.get_meta("physical_seat_pose")) and is_equal_approx(remote.rotation.y, 2.0), "standing resumes Session position and yaw compatibility")
	session.poses.clear()
	deck._update_avatars(session)
	check(deck._avatars.is_empty(), "disconnected avatar removed from actual scene")
	var crew = SpaceView.model("crew")
	root.add_child(crew)
	var mesh: MeshInstance3D = crew.find_child("crew", true, false)
	var standing_mesh = mesh.mesh
	var source_bounds = standing_mesh.get_aabb()
	PhysicalSeatCatalog.apply_pose(crew, true)
	check(mesh.mesh != standing_mesh, "shared seated pose bends actual mesh")
	check(mesh.mesh.get_surface_count() == standing_mesh.get_surface_count(), "seated mesh preserves material surfaces")
	check(mesh.mesh.get_aabb().position.z < source_bounds.position.z - 0.2, "seated knees project forward")
	PhysicalSeatCatalog.apply_pose(crew, false)
	check(mesh.mesh == standing_mesh, "standing restores untouched crew fallback mesh")
	crew.queue_free()
	app.queue_free()
	await process_frame
	print("SHARED_SEATS_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
