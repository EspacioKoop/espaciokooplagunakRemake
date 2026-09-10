extends SceneTree
## File barriers coordinate the test only; all game actions use real ENet RPCs.
var session
var seats
var failures = 0
var checks = 0
var joined = false
var mode = ""
var directory = ""
var responses: Array = []
var catalog: Dictionary
var _transmit_pose = Vector3.ZERO
var _pose_active = false
var _pose_sent_at = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("SEATS_NET_FAIL " + mode + " " + label)
func wait_for(condition: Callable, seconds: float = 8.0) -> bool:
	for i in int(seconds * 20):
		if condition.call(): return true
		await create_timer(0.05).timeout
	return bool(condition.call())
func marker(name: String) -> String: return directory.path_join(name)
func mark(name: String, text: String = "ready") -> void:
	var temporary = marker(name) + ".pending"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	DirAccess.rename_absolute(temporary, marker(name))
func reached(name: String) -> bool: return FileAccess.file_exists(marker(name))
func phase(name: String) -> void:
	check(await wait_for(func(): return reached(name)), "phase " + name)
func _stream_pose() -> void:
	if not _pose_active or session.mode != "client" or not joined: return
	var now = Time.get_ticks_msec()
	if now - _pose_sent_at < 100: return
	_pose_sent_at = now
	session.update_pose(_transmit_pose, 0.0)
func echoed_position() -> bool:
	var peer = str(seats.local_peer())
	var pose: Dictionary = session.poses.get(peer, {})
	if pose.is_empty(): return false
	return Vector3(pose.position[0], pose.position[1], pose.position[2]).distance_to(_transmit_pose) < 0.01
func place(id: String) -> void:
	_transmit_pose = catalog[id].approach + Vector3(0, 0.2, 0)
	_pose_active = true
	check(await wait_for(echoed_position), "host echoes approach position before reservation")
func run() -> void:
	session = root.get_node("Session")
	seats = root.get_node("SeatPresence")
	catalog = PhysicalSeatCatalog.all_seats()
	physics_frame.connect(_stream_pose)
	var args = OS.get_cmdline_user_args()
	mode = args[args.find("--case") + 1]
	var port = int(args[args.find("--port") + 1])
	directory = args[args.find("--barriers") + 1]
	session.joined.connect(func(): joined = true)
	seats.result_received.connect(func(ok, message): responses.append({"ok": ok, "message": message}))
	if mode.begins_with("legacy_"): await legacy_case(port)
	elif mode == "host": await host_case(port)
	elif mode == "unauthenticated": await unauthenticated_case(port)
	else: await client_case(port)
	session.close_session()
	print("SHARED_SEATS_NETWORK_RESULT ", mode, " checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
func host_case(port: int) -> void:
	check(session.host_session(port, "physical-seats-test-key").ok, "host starts without opening deck")
	session.update_pose(catalog.seat_7_0.approach, 0.0)
	check(seats.request_sit("seat_7_0").ok, "host reserves own nearby seat")
	print("SHARED_SEATS_NETWORK_READY")
	check(await wait_for(func(): return reached("player_ready") and reached("rival_ready") and reached("unauthenticated_done")), "all peers attempted authentication")
	check(session.roster.size() == 3 and seats._subscribers.size() == 2, "only authenticated opt-in clients subscribe")
	check(seats.occupant("seat_7_0") == 1 and seats._occupants.size() == 1, "unauthenticated requests cannot evict host or reserve seat")
	mark("race")
	check(await wait_for(func(): return reached("player_raced") and reached("rival_raced")), "two actual clients raced")
	var winner = seats.occupant("seat_7_1")
	check(winner > 1 and seats._occupants.size() == 2, "atomic race yields exactly one occupant")
	mark("winner", str(winner))
	check(await wait_for(func(): return reached("player_observed") and reached("rival_observed")), "all peers agree on winner and anchor")
	mark("stand")
	check(await wait_for(func(): return seats.occupant("seat_7_1") == 0), "winner stand releases on host")
	mark("handover")
	check(await wait_for(func(): return seats.occupant("seat_7_1") > 1 and seats.occupant("seat_7_1") != winner), "previous loser can claim freed seat")
	check(await wait_for(func(): return reached("player_negative") and reached("rival_negative")), "negative authenticated requests complete")
	check(seats.occupant("seat_7_0") == 1, "clients cannot release host by requesting stand or changing seat id")
	mark("zone")
	check(await wait_for(func(): return reached("player_zone_seen") and reached("rival_zone_seen")), "all clients acknowledge zone release before next phase")
	if seats.occupant("seat_7_1") != 0:
		print("SEATS_ZONE_DIAGNOSTIC occupants=", seats._occupants, " positions=", session.poses)
	check(seats.occupant("seat_7_1") == 0, "legacy position update to another zone releases seat")
	mark("disconnect")
	check(await wait_for(func(): return reached("disconnect_reserved")), "client reserves before disconnect")
	check(await wait_for(func(): return reached("disconnected") and seats.occupant("seat_7_1") == 0), "disconnect releases physical seat")
	mark("reconnect")
	check(await wait_for(func(): return reached("reconnected")), "client reconnects")
	check(seats.occupant("seat_7_1") == 0, "reconnect does not resurrect physical reservation")
	check(seats.occupant("seat_7_0") == 1, "host reservation survives all client lifecycle changes")
	mark("done")
	await create_timer(0.4).timeout
	session.close_session()
	check(seats._occupants.is_empty(), "closing transport clears seat ownership")
func client_case(port: int) -> void:
	var role = "navegacion" if mode == "player" else "ingenieria"
	check(session.join_session("127.0.0.1", port, "physical-seats-test-key", mode, role).ok, "client starts")
	check(await wait_for(func(): return joined and seats.occupant("seat_7_0") == 1), "late authenticated client receives occupied seat snapshot")
	var peer = seats.local_peer()
	check(not seats.seat_for(1).is_empty() and seats.seat_for(1).anchor == catalog.seat_7_0.anchor, "host anchored seat has canonical presentation")
	check(seats._occupants.values().all(func(value): return value is int), "public packet contains only occupant IDs")
	await place("seat_7_1")
	mark(mode + "_ready")
	await phase("race")
	seats.request_sit("seat_7_1")
	check(await wait_for(func(): return not responses.is_empty()), "reservation RPC response")
	mark(mode + "_raced")
	await phase("winner")
	var winner = int(FileAccess.get_file_as_string(marker("winner")))
	check(await wait_for(func(): return seats.occupant("seat_7_1") == winner), "replicated race result agrees")
	check(bool(responses[0].ok) == (winner == peer), "only winner gets successful reservation")
	check(seats.seat_for(winner).anchor == catalog.seat_7_1.anchor, "every client resolves same physical anchor")
	mark(mode + "_observed")
	await phase("stand")
	if peer == winner: seats.request_stand()
	await phase("handover")
	if peer != winner: seats.request_sit("seat_7_1")
	check(await wait_for(func(): return seats.occupant("seat_7_1") > 1 and seats.occupant("seat_7_1") != winner), "seat hands over consistently")
	var new_owner = seats.occupant("seat_7_1")
	if peer == winner:
		# Stand is always about the sender; it has no target peer argument.
		seats.request_stand()
		seats._receive_request.rpc_id(1, 1, 1, "sit", "seat_7_1") # replay
		seats._receive_request.rpc_id(1, 999, 900, "sit", "seat_7_2") # unsupported schema
		seats.request_sit("seat_7_0|1") # forged identity in invalid ID
		seats.request_sit("seat_10_0") # far seat without pose update
		await create_timer(0.3).timeout
		check(seats.occupant("seat_7_1") == new_owner and seats.occupant("seat_7_0") == 1, "replay forged identity and stand cannot affect another occupant")
		check(seats.occupant("seat_10_0") == 0 and seats.occupant("seat_7_2") == 0, "far seat and unsupported version rejected")
	mark(mode + "_negative")
	await phase("zone")
	if peer != winner:
		# Keep the real unreliable 10Hz movement stream alive until host echo.
		_transmit_pose = Vector3(80, 0.2, 80)
		check(await wait_for(echoed_position), "host echoes new zone position")
	check(await wait_for(func(): return seats.occupant("seat_7_1") == 0), "zone release reaches all clients")
	mark(mode + "_zone_seen")
	await phase("disconnect")
	if mode == "player":
		await place("seat_7_1")
		seats.request_sit("seat_7_1")
		check(await wait_for(func(): return seats.occupant("seat_7_1") == peer), "reserve before disconnect")
		mark("disconnect_reserved")
		await create_timer(0.15).timeout
		_pose_active = false
		session.close_session()
		check(seats._occupants.is_empty(), "local close clears client projection")
		joined = false
		mark("disconnected")
		await phase("reconnect")
		check(session.join_session("127.0.0.1", port, "physical-seats-test-key", mode, role).ok, "reconnect starts")
		check(await wait_for(func(): return joined and seats.occupant("seat_7_0") == 1), "reconnect receives fresh occupied snapshot")
		check(seats.seat_for(seats.local_peer()).is_empty(), "reconnected peer is standing")
		mark("reconnected")
	await phase("done")
func unauthenticated_case(port: int) -> void:
	# Use a real transport but never a valid Session proof. Send before handshake.
	var peer = ENetMultiplayerPeer.new()
	check(peer.create_client("127.0.0.1", port, 3) == OK, "raw peer connects")
	session.mode = "client"
	session.access_key = "deliberately-wrong-test-key"
	root.multiplayer.multiplayer_peer = peer
	check(await wait_for(func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, 2.0), "raw ENet connected")
	seats._hello.rpc_id(1, 1)
	seats._receive_request.rpc_id(1, 1, 1, "stand", "")
	seats._receive_request.rpc_id(1, 1, 2, "sit", "seat_7_1")
	await create_timer(0.3).timeout
	check(not joined and seats._occupants.is_empty(), "unauthenticated peer receives no seating state")
	mark("unauthenticated_done")

func legacy_case(port: int) -> void:
	if mode == "legacy_host":
		check(session.host_session(port, "legacy-physical-test-key").ok, "legacy host starts")
		check(session.roster[1].get("seat_protocol") == 1, "host announces only its own seating capability")
		seats.queue_free()
		await process_frame
		check(not session.roster[1].has("seat_protocol"), "removing optional component removes capability")
		print("SHARED_SEATS_NETWORK_READY")
		check(await wait_for(func(): return reached("legacy_pose")), "legacy client exchanged gameplay state")
		check(session.poses.values().any(func(pose): return is_equal_approx(float(pose.position[0]), 75.0) and is_equal_approx(float(pose.position[2]), 2.65)), "legacy position and yaw channel still works")
		mark("legacy_done")
		await create_timer(0.3).timeout
	else:
		check(session.join_session("127.0.0.1", port, "legacy-physical-test-key", mode, "navegacion").ok, "new client joins old host")
		check(await wait_for(func(): return joined and session.roster.size() == 2), "legacy host authenticates normally")
		check(not seats._hello_sent and not seats._negotiated, "missing capability emits no unknown-node RPC")
		check(not seats.request_sit("seat_7_0").ok, "unsupported seat request rejected locally without RPC")
		# Malformed/unknown capability must also remain silent.
		for value in ["1", 2, -1, null, {"version": 1}]:
			session.roster["1"].seat_protocol = value
			seats._hello_host()
			check(not seats._hello_sent, "malformed capability ignored")
		for tick in 3:
			session.update_pose(Vector3(75, 0.2, 2.65), 0.0)
			await create_timer(0.1).timeout
		mark("legacy_pose")
		await phase("legacy_done")
