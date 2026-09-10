extends SceneTree
## Real Session RPCs; shared files synchronise phases, never carry game state.
const CREW = ["navegacion", "ingenieria", "armas", "sensores", "comunicaciones", "enlace", "reparaciones"]
const TEST_KEY = "alert-regression-synthetic-key"
const WAIT_SECONDS = 18.0
var session: Node
var mode = ""
var sync_dir = ""
var port = 0
var failures = 0
var checks = 0
var accepted = false
var responses: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error("ALERT_FAIL %s: %s" % [mode, label])
	return condition

func option(name: String) -> String:
	var args = OS.get_cmdline_user_args()
	var index = args.find(name)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else ""

func wait_for(predicate: Callable, label: String) -> bool:
	var deadline = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await create_timer(0.05).timeout
	return check(false, "timeout: " + label)

func mark(name: String) -> void:
	var file = FileAccess.open(sync_dir.path_join(name), FileAccess.WRITE)
	if not check(file != null, "write phase " + name): return
	file.store_string("ready\n")
	file.close()

func marked(name: String) -> bool:
	return FileAccess.file_exists(sync_dir.path_join(name))

func all_marked(phase: String) -> bool:
	for crew_role in CREW:
		if not marked(phase + "." + crew_role): return false
	return true

func has_role(crew_role: String) -> bool:
	for entry in session.roster.values():
		if entry.role == crew_role: return true
	return false

func alert_is(level: String) -> bool:
	return accepted and session.view.get("ship", {}).get("alert", "") == level

func assert_view(level: String) -> void:
	check(session.view.get("ship", {}).get("alert", "") == level, "shared alert " + level)
	check(session.role == mode, "authenticated station preserved")
	check(not session.view.get("mission", {}).has("contacts"), "late join does not disclose source contact catalogue")
	check(not session.view.has("campaign_document"), "authoring document remains private")

func connect_client() -> bool:
	accepted = false
	responses.clear()
	var result = session.join_session("127.0.0.1", port, TEST_KEY, "AlertTest-" + mode, mode)
	if not check(result.ok, "ENet connection starts"): return false
	return await wait_for(func(): return accepted and not session.view.is_empty(), "authenticated snapshot")

func reject_order(args: Dictionary, level: String) -> bool:
	responses.clear()
	session.order("alert", args)
	if not await wait_for(func(): return not responses.is_empty(), "authoritative rejection"): return false
	check(not responses[0].ok, "non-captain alert order rejected by host")
	# Wait for a subsequent server view, not just the pre-order local value.
	var previous_time = float(session.view.get("time", -1.0))
	if not await wait_for(func(): return float(session.view.get("time", -1.0)) > previous_time, "post-rejection snapshot"): return false
	check(alert_is(level), "rejected order did not change shared alert")
	return true

func run_host() -> void:
	if not check(session.host_session(port, TEST_KEY).ok, "host starts"): return
	check(session.role == "mando", "captain remains authoritative")
	check(session.order("alert", {"level": "roja"}).ok, "captain sets red before anyone joins")
	check(session.view.ship.alert == "roja", "captain view is red")
	var before = session.sim.state.duplicate(true)
	check(not session.order("alert", {"level": "not-a-level"}).ok, "unknown alert rejected")
	check(session.sim.state == before, "invalid captain order is atomic")
	print("ALERT_HOST_READY roja")
	if not await wait_for(func(): return all_marked("red"), "all seven late stations see red"): return
	check(session.roster.size() == 8, "all eight stations authenticated")
	check(session.sim.state.ship.alert == "roja", "seven peers cannot override captain")
	mark("disconnect")
	if not await wait_for(func(): return marked("left.navegacion") and not has_role("navegacion"), "navigation removed from host roster"): return
	check(session.order("alert", {"level": "ambar"}).ok, "captain changes alert while navigator is offline")
	check(session.view.ship.alert == "ambar", "captain sees amber")
	mark("reconnect")
	if not await wait_for(func(): return all_marked("amber"), "live peers and reconnected navigator see amber"): return
	check(session.roster.size() == 8, "reconnected navigator has one reserved station")
	check(session.sim.state.ship.alert == "ambar", "reconnection did not restore stale red")
	check(session.order("alert", {"level": "verde"}).ok, "captain sets green live")
	check(session.view.ship.alert == "verde", "captain sees green")
	if not await wait_for(func(): return all_marked("green"), "all stations see green"): return
	mark("finish")
	if not await wait_for(func(): return session.roster.size() == 1, "clients disconnect cleanly"): return
	check(session.sim.state.ship.alert == "verde", "disconnects preserve host alert")

func run_client() -> void:
	if not await connect_client(): return
	# The first accepted snapshot must already contain red, not a later replay.
	assert_view("roja")
	if not await reject_order({"level": "verde"}, "roja"): return
	if not await reject_order({"level": "verde", "role": "mando", "principal": "1"}, "roja"): return
	mark("red." + mode)
	if mode == "navegacion":
		if not await wait_for(func(): return marked("disconnect"), "host requests one reconnection"): return
		session.close_session()
		accepted = false
		mark("left.navegacion")
		if not await wait_for(func(): return marked("reconnect"), "host changed alert while disconnected"): return
		if not await connect_client(): return
		assert_view("ambar")
	else:
		if not await wait_for(func(): return alert_is("ambar"), "live amber snapshot"): return
		assert_view("ambar")
	mark("amber." + mode)
	if not await wait_for(func(): return alert_is("verde"), "live green snapshot"): return
	assert_view("verde")
	mark("green." + mode)
	await wait_for(func(): return marked("finish"), "host acknowledged all green snapshots")

func run() -> void:
	mode = option("--case")
	sync_dir = option("--sync-dir")
	port = int(option("--port"))
	if not check(mode == "host" or mode in CREW, "known process case") or not check(DirAccess.dir_exists_absolute(sync_dir), "existing isolated phase directory") or not check(port >= 1024 and port <= 65535, "valid UDP port"):
		quit(1)
		return
	session = root.get_node("Session")
	session.suppress_saves = true
	session.notice.connect(func(message, ok): responses.append({"message": message, "ok": ok}))
	session.joined.connect(func(): accepted = true)
	if mode == "host": await run_host()
	else: await run_client()
	session.close_session()
	print("ALERT_RESULT %s checks=%d failures=%d" % [mode, checks, failures])
	quit(1 if failures else 0)
