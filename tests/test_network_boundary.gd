extends SceneTree
## Exercises the real Session RPC endpoints. No production guards are replaced.
const PRIVATE_MARKER = "BOUNDARY_SYNTHETIC_PRIVATE_CONTENT"
const DISPLAY_NAME = "Mismo nombre de prueba"
var session: Node
var case_name = ""
var sync_dir = ""
var checks = 0
var failures = 0
var finished = false
var accepted = false
var disconnected_peer = false
var saw_view = false
var notices: Array = []

func _initialize() -> void:
	call_deferred("run")

func option(flag: String) -> String:
	var args = OS.get_cmdline_user_args()
	var index = args.find(flag)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else ""

func expect(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		printerr("NETWORK_BOUNDARY_FAIL ", case_name, " ", label)
	return value

func delay(seconds: float = 0.05) -> void:
	await create_timer(seconds).timeout

func mark(name: String, value: String = "ready") -> void:
	var path = sync_dir.path_join(name)
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not expect(file != null, "fixture marker opens"): return
	file.store_string(value)
	file.close()
	expect(DirAccess.rename_absolute(path + ".tmp", path) == OK, "fixture marker commits")

func exists(name: String) -> bool:
	return FileAccess.file_exists(sync_dir.path_join(name))

func wait_for(predicate: Callable, seconds: float = 6.0) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await delay()
	return bool(predicate.call())

func finish() -> void:
	if finished: return
	finished = true
	if session != null: session.close_session()
	print("NETWORK_BOUNDARY_RESULT %s checks=%d failures=%d" % [case_name, checks, failures])
	quit(1 if failures else 0)

func run() -> void:
	session = root.get_node("Session")
	session.suppress_saves = true
	case_name = option("--case")
	sync_dir = option("--sync-dir")
	var port = int(option("--port"))
	if not expect(case_name in ["unit", "host", "unauthenticated", "victim", "navigation"], "known case"):
		finish()
		return
	if not expect(DirAccess.dir_exists_absolute(sync_dir), "isolated fixture directory exists"):
		finish()
		return
	create_timer(50.0).timeout.connect(func():
		if not finished:
			expect(false, "Godot watchdog expired")
			finish())
	session.joined.connect(func(): accepted = true)
	session.disconnected.connect(func(): disconnected_peer = true)
	session.updated.connect(func(): saw_view = saw_view or not session.view.is_empty())
	session.notice.connect(func(message, ok): notices.append({"message": message, "ok": ok}))
	match case_name:
		"unit": run_unit()
		"host": await run_host(port)
		"unauthenticated": await run_unauthenticated(port)
		"victim": await run_victim(port)
		"navigation": await run_navigation(port)
	finish()

func packet(value: Dictionary) -> PackedByteArray:
	var raw = JSON.stringify(value).to_utf8_buffer()
	var result = PackedByteArray()
	result.resize(4)
	result.encode_u32(0, raw.size())
	result.append_array(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	return result

func run_unit() -> void:
	session.new_campaign()
	session._rates.clear()
	for i in 20: expect(session._allow_order(98765), "rate allows bounded burst %d" % i)
	for i in 5: expect(not session._allow_order(98765), "rate rejects excess %d" % i)
	expect(session._allow_order(98766), "rate is per peer")
	session._rates[98765] = {"since": Time.get_ticks_msec() - 1001, "count": 200}
	expect(session._allow_order(98765), "rate window recovers")
	session._rates.clear()
	# Parser tests are local calls, NOT evidence of RPC sender authorization.
	var baseline: Dictionary = session.view.duplicate(true)
	session.mode = "client"
	for size in [0, 1, 4, 262145]:
		var invalid = PackedByteArray()
		invalid.resize(size)
		session._snapshot(invalid)
		expect(session.view == baseline, "packet size rejected %d" % size)
	for length in [0, 1, 262145]:
		var invalid = packet(baseline)
		invalid.encode_u32(0, length)
		session._snapshot(invalid)
		expect(session.view == baseline, "declared length rejected %d" % length)
	for field in ["ship", "contacts", "mission"]:
		var malformed = baseline.duplicate(true)
		malformed.erase(field)
		session._snapshot(packet(malformed))
		expect(session.view == baseline, "missing mandatory field rejected " + field)
		malformed[field] = "not the required type"
		session._snapshot(packet(malformed))
		expect(session.view == baseline, "wrong mandatory type rejected " + field)
	var valid = baseline.duplicate(true)
	valid.boundary_positive_control = true
	session._snapshot(packet(valid))
	expect(session.view.get("boundary_positive_control", false), "valid frame accepted")

func run_host(port: int) -> void:
	if not expect(session.host_session(port, OS.get_environment("LAGUNAK_BOUNDARY_KEY")).ok, "host starts"): return
	session.sim.state.campaign_document = {"private_fixture": PRIVATE_MARKER}
	var hidden: Dictionary = session.sim.state.contacts[0].duplicate(true)
	hidden.id = "boundary_hidden"
	hidden.name = PRIVATE_MARKER
	hidden.identified = false
	hidden.known = false
	hidden.position = [2000.0, 2000.0]
	session.sim.state.contacts.append(hidden)
	expect(session.order("destruct_arm", {"confirmation": "ITSASO"}).ok, "private codes fixture armed")
	mark("host.ready")
	var checked_unauthenticated = false
	var checked_navigation = false
	while not exists("stop") and not finished:
		if exists("unauthenticated.done") and not checked_unauthenticated:
			await delay(0.2)
			expect(session.roster.size() == 1, "unauthenticated peer never gets a station")
			expect(session.sim.state.ship.throttle == 0.0, "unauthenticated helm has no effect")
			expect(session.sim.state.ship.systems.armas.power == 2, "unauthenticated power has no effect")
			expect(session.poses.is_empty(), "unauthenticated pose absent")
			checked_unauthenticated = true
			mark("unauthenticated.checked")
		if exists("navigation.attacks") and not checked_navigation:
			var nav = int(FileAccess.get_file_as_string(sync_dir.path_join("navigation.attacks")))
			var victim = int(FileAccess.get_file_as_string(sync_dir.path_join("victim.ready")))
			expect(nav > 1 and victim > 1 and nav != victim, "distinct authenticated peer identities")
			expect(session.roster.get(nav, {}).get("role", "") == "navegacion", "repeated authentication cannot elevate station")
			expect(session.roster.get(victim, {}).get("role", "") == "ingenieria", "victim station unchanged")
			expect(session.role == "mando", "captain station cannot be stolen")
			expect(session.sim.state.ship.systems.armas.power == 2, "claimed role in order ignored")
			expect(is_equal_approx(session.sim.state.ship.throttle, 0.33), "authorized navigation actually changes simulation")
			var task: Dictionary = session.sim.state.cooperation.tasks.get(str(victim), {})
			expect(not task.is_empty(), "victim task survives forged cancellation")
			expect(task.get("moves", -1) == 0 and task.get("accuracy", 0) == -1.0, "forged principal cannot play victim task")
			var public_view: Dictionary = session._telemetry_view()
			expect(not public_view.has("lounge"), "telemetry excludes lounge")
			expect(not public_view.has("campaign_document"), "telemetry excludes campaign document")
			expect(public_view.operations.destruct.codes.is_empty(), "telemetry excludes confirmation codes")
			expect(public_view.cooperation.tasks.is_empty(), "telemetry excludes private tasks")
			checked_navigation = true
			mark("navigation.checked")
		await delay()
	expect(checked_unauthenticated and checked_navigation, "all host phases executed")

func send_before_authentication() -> void:
	# Channel 0 reliable requests precede the automatic wrong-key HMAC response.
	expect(session.rpc_id(1, "_receive_order", "helm", {"heading": 123.0, "throttle": 0.9}) == OK, "unauthenticated helm packet sent")
	expect(session.rpc_id(1, "_receive_order", "power", {"system": "armas", "value": 0}) == OK, "unauthenticated power packet sent")
	expect(session.rpc_id(1, "_request_role", "ingenieria") == OK, "unauthenticated station request sent")
	expect(session.rpc_id(1, "_receive_pose", [1.0, 1.0, 1.0], 0.0) == OK, "unauthenticated pose packet sent")

func run_unauthenticated(port: int) -> void:
	session.multiplayer.connected_to_server.connect(send_before_authentication)
	if not expect(session.join_session("127.0.0.1", port, "incorrect-synthetic-key", "Untrusted probe", "navegacion").ok, "probe transport starts"): return
	expect(await wait_for(func(): return disconnected_peer or accepted), "probe receives authentication outcome")
	expect(disconnected_peer and not accepted, "wrong key rejected and disconnected")
	expect(not saw_view, "unauthenticated peer receives no usable snapshot")
	expect(notices.any(func(item): return not item.ok), "rejection response traverses real connection")

func join_as(port: int, role: String) -> bool:
	if not expect(session.join_session("127.0.0.1", port, OS.get_environment("LAGUNAK_BOUNDARY_KEY"), DISPLAY_NAME, role).ok, "client transport starts"): return false
	return expect(await wait_for(func(): return accepted and not session.view.is_empty()), "authenticated snapshot arrives")

func run_victim(port: int) -> void:
	if not await join_as(port, "ingenieria"): return
	var own_id = str(session.multiplayer.get_unique_id())
	session.order("assist_begin", {"recipient": "navegacion", "mode": "precision"})
	if not expect(await wait_for(func(): return session.view.cooperation.tasks.has(own_id)), "victim receives own private task"): return
	expect(session.view.operations.destruct.codes.keys() == ["ingenieria"], "victim receives only its station code")
	mark("victim.ready", own_id)
	expect(await wait_for(func(): return exists("stop"), 35.0), "victim completes coordinated phase")
	expect(session.role == "ingenieria", "duplicate display name does not change victim station")

func run_navigation(port: int) -> void:
	if not await join_as(port, "navegacion"): return
	var own_id = str(session.multiplayer.get_unique_id())
	var victim_id = FileAccess.get_file_as_string(sync_dir.path_join("victim.ready"))
	expect(own_id != victim_id, "same display name is not an identity")
	expect(not session.view.mission.has("contacts"), "future mission catalogue excluded")
	expect(not session.view.has("campaign_document"), "campaign authoring document excluded")
	expect(session.view.cooperation.tasks.is_empty(), "other principal task excluded")
	expect(session.view.operations.destruct.codes.is_empty(), "other station codes excluded")
	var serialized = JSON.stringify(session.view)
	expect(PRIVATE_MARKER not in serialized, "hidden names and campaign fixture not leaked")
	expect(OS.get_environment("LAGUNAK_BOUNDARY_KEY") not in serialized, "access key not in snapshot")
	expect(session._resume_lounge_ticket not in serialized, "resume ticket not in snapshot")
	session.order("power", {"system": "armas", "value": 0, "role": "ingenieria", "principal": victim_id})
	session.order("assist_input", {"x": 0.5, "y": 0.5, "principal": victim_id, "actor": victim_id})
	session.order("assist_cancel", {"principal": victim_id})
	session.select_role("mando")
	var proof = PackedByteArray()
	proof.resize(32)
	expect(session.rpc_id(1, "_authenticate", proof, "Forged captain", "mando", "") == OK, "post-authentication role overwrite attempted")
	session.order("helm", {"heading": 0.0, "throttle": 0.33})
	expect(await wait_for(func(): return notices.filter(func(item): return not item.ok).size() >= 4 and is_equal_approx(session.view.ship.throttle, 0.33)), "forgeries rejected and legitimate control acknowledged")
	expect(session.role == "navegacion", "client retains authenticated station")
	mark("navigation.attacks", own_id)
	expect(await wait_for(func(): return exists("navigation.checked")), "host verifies effects independently")
