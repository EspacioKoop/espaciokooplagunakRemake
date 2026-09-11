extends SceneTree
## Real transport regression: authenticated delivery, rejected peers and ENet teardown.
var session: Node
var thrusters: Node
var fleet: Node
var checks = 0
var failures = 0
var axis_updates = 0
var fleet_updates = 0
var accepted = false
var disconnected = false
var case_name = ""
var coordination = ""
const KEY = "aux-rpc-integration-key"
const AXIS = 0.625

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error("AUX_RPC_FAIL " + case_name + ": " + label)
	return value

func delay(seconds: float) -> void:
	await create_timer(seconds).timeout

func publish(name: String, data: Dictionary = {}) -> void:
	var destination = coordination.path_join(name + ".json")
	var file = FileAccess.open(destination + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	if DirAccess.rename_absolute(destination + ".tmp", destination) != OK:
		check(false, "cannot publish " + name)

func wait_for(name: String, seconds: float = 8.0) -> bool:
	var until = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not FileAccess.file_exists(coordination.path_join(name + ".json")):
		if Time.get_ticks_msec() >= until:
			return check(false, "timed out waiting for " + name)
		await delay(0.02)
	return true

func read_peer(name: String) -> int:
	var data = JSON.parse_string(FileAccess.get_file_as_string(coordination.path_join(name + ".json")))
	return int(data.id)

func wait_for_host_connections(member: int, guest: int) -> bool:
	# A client-side ready file is not a host-side ENet acknowledgement. Poll the
	# real host until both transports and the guest challenge are observable.
	var until = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until:
		if session.roster.has(member) and session._peer_active(member) and session._peer_active(guest) and session._challenges.has(guest):
			return check(true, "host observes both transports and the unauthenticated challenge")
		await delay(0.02)
	print("AUX_RPC_STAGE ", JSON.stringify({"member_active": session._peer_active(member), "guest_active": session._peer_active(guest), "member_in_roster": session.roster.has(member), "guest_challenged": session._challenges.has(guest)}))
	return check(false, "host never acknowledged both client-ready transports")

func send_auxiliary_updates() -> void:
	# Advance production emitters with automatic processing disabled, so a
	# client's updated signals unambiguously count real RPC delivery.
	thrusters._process(0.21)
	fleet._process(0.51)

func run() -> void:
	var args = OS.get_cmdline_user_args()
	case_name = args[args.find("--case") + 1]
	coordination = args[args.find("--coordination") + 1]
	var port = int(args[args.find("--port") + 1])
	session = root.get_node("Session")
	thrusters = root.get_node("Thrusters")
	fleet = root.get_node("Fleet")
	session.set_physics_process(false)
	thrusters.set_process(false)
	fleet.set_process(false)
	thrusters.updated.connect(func(): axis_updates += 1)
	fleet.updated.connect(func(): fleet_updates += 1)
	session.joined.connect(func(): accepted = true)
	session.disconnected.connect(func(): disconnected = true)
	if case_name == "host":
		await run_host(port)
	elif case_name == "member":
		await run_member(port)
	else:
		await run_guest(port)
	session.close_session()
	var result = {"case": case_name, "checks": checks, "failures": failures,
		"axis_updates": axis_updates, "fleet_updates": fleet_updates}
	publish(case_name + "-result", result)
	print("AUX_RPC_RESULT ", JSON.stringify(result))
	quit(1 if failures else 0)

func run_host(port: int) -> void:
	if not check(session.host_session(port, KEY).ok, "host starts real ENet server"): return
	session.sim.state.contacts.clear()
	thrusters.axis = AXIS
	thrusters.controller = "1"
	publish("host-ready")
	if not await wait_for("member-ready") or not await wait_for("guest-ready"): return
	var member = read_peer("member-ready")
	var guest = read_peer("guest-ready")
	if not await wait_for_host_connections(member, guest): return
	check(session.roster.has(member) and session.roster.size() == 2, "only host and authenticated member are in roster")
	check(not session.roster.has(guest), "transport-only guest has no authenticated principal")
	check(session._peer_active(member) and session._peer_active(guest), "both remote ENet connections are really active")
	for tick in 16:
		send_auxiliary_updates()
		await delay(0.05)
	publish("burst-finished")
	if not await wait_for("guest-observed") or not await wait_for("member-observed"): return
	publish("reject-guest")
	var deadline = Time.get_ticks_msec() + 5000
	while not FileAccess.file_exists(coordination.path_join("guest-rejected.json")) and Time.get_ticks_msec() < deadline:
		send_auxiliary_updates()
		await delay(0.025)
	check(await wait_for("guest-rejected", 1.0), "invalid proof causes a real client disconnect")
	check(not session.roster.has(guest), "rejected guest never enters authenticated roster")
	check(session.roster.has(member) and session._peer_active(member), "legitimate member survives guest rejection")
	for tick in 8:
		send_auxiliary_updates()
		await delay(0.05)
	publish("rejection-finished")
	if not await wait_for("member-after-rejection"): return
	# Reproduce the narrow state from the flaky CI failure with a real socket.
	# ENet has reset the packet peer but the authenticated roster has not drained.
	var packet: ENetPacketPeer = session.multiplayer.multiplayer_peer.get_peer(member)
	packet.peer_disconnect_now()
	check(packet.get_state() == ENetPacketPeer.STATE_DISCONNECTED and not packet.is_active(), "real ENet peer is reset and has no active transport")
	check(session.roster.has(member), "authenticated roster still contains the closing peer")
	check(not session._peer_active(member), "Session rejects the stale transport as an active recipient")
	send_auxiliary_updates()
	publish("teardown-finished")
	await wait_for("member-finished")

func run_member(port: int) -> void:
	if not check(session.join_session("127.0.0.1", port, KEY, "Member", "navegacion").ok, "member starts normal Session authentication"): return
	var deadline = Time.get_ticks_msec() + 8000
	while not accepted and Time.get_ticks_msec() < deadline:
		await delay(0.02)
	if not check(accepted, "member completes host challenge/proof"): return
	publish("member-ready", {"id": session.multiplayer.get_unique_id()})
	if not await wait_for("burst-finished"): return
	await delay(0.25)
	check(axis_updates >= 3 and is_equal_approx(thrusters.axis, AXIS), "authenticated member receives the authoritative maneuver axis")
	check(fleet_updates >= 3, "authenticated member receives fleet notifications")
	publish("member-observed")
	var before_axis = axis_updates
	var before_fleet = fleet_updates
	if not await wait_for("rejection-finished"): return
	await delay(0.15)
	check(axis_updates > before_axis and fleet_updates > before_fleet, "both streams continue through guest rejection and disconnect")
	publish("member-after-rejection")
	if not await wait_for("teardown-finished"): return
	# peer_disconnect_now may not notify the remote; local cleanup is deliberate.
	session.close_session()
	publish("member-finished")

func run_guest(port: int) -> void:
	var peer = ENetMultiplayerPeer.new()
	if not check(peer.create_client("127.0.0.1", port, 3) == OK, "guest creates a real unauthenticated ENet connection"): return
	# Keep Session offline: its existing _challenge handler ignores the challenge
	# and never submits credentials. The socket remains genuinely connected.
	session.multiplayer.multiplayer_peer = peer
	var deadline = Time.get_ticks_msec() + 8000
	while peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED and Time.get_ticks_msec() < deadline:
		await delay(0.02)
	if not check(peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "guest transport connects without credentials"): return
	publish("guest-ready", {"id": session.multiplayer.get_unique_id()})
	if not await wait_for("burst-finished"): return
	await delay(0.25)
	check(not accepted, "guest never receives acceptance")
	check(axis_updates == 0 and is_zero_approx(thrusters.axis), "unauthenticated guest receives no maneuver axis RPC")
	check(fleet_updates == 0, "unauthenticated guest receives no fleet status RPC")
	publish("guest-observed")
	if not await wait_for("reject-guest"): return
	session.mode = "client"
	session._authenticate.rpc_id(1, PackedByteArray(), "Guest", "ingenieria", "")
	deadline = Time.get_ticks_msec() + 5000
	while not disconnected and Time.get_ticks_msec() < deadline:
		await delay(0.02)
	check(disconnected and not accepted, "bad proof is rejected and disconnected by the real host")
	check(axis_updates == 0 and fleet_updates == 0, "no auxiliary RPC leaks during rejection teardown")
	publish("guest-rejected")
