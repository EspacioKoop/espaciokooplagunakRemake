extends SceneTree
const Cases = preload("res://../tests/test_space_pickups.gd")
var checks = 0
var failures = 0
var session: Node
var directory: String
var responses: Array = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("PICKUP_NET_FAIL " + label)
func delay() -> void: await create_timer(0.05).timeout
func mark(name: String) -> void:
	var file = FileAccess.open(directory.path_join(name), FileAccess.WRITE)
	file.store_string("ready")
	file.close()
func wait_for(predicate: Callable) -> bool:
	for i in 260:
		if predicate.call(): return true
		await delay()
	return false
func exists(name: String) -> bool: return FileAccess.file_exists(directory.path_join(name))

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var mode = args[args.find("--case") + 1]
	var port = int(args[args.find("--port") + 1])
	directory = args[args.find("--coordination") + 1]
	session = root.get_node("Session")
	session.notice.connect(func(message, ok): responses.append({"message": message, "ok": ok}))
	if mode == "host":
		check(session.host_session(port, "space-pickup-test-key").ok, "host opens real ENet")
		check(session.start_mission(0, Cases.mission()).ok, "host selects pickup mission")
		session.sim.state.operations.ammo.homing = 0
		session.sim.state.ship.torpedoes = 0
		session.sim.state.ship.energy = 10
		mark("host-ready")
		check(await wait_for(func(): return exists("client-ready")), "authenticated client ready")
		check(session.roster.size() == 2, "two authenticated crew")
		check(await wait_for(func(): return session.sim.state.facts.has("pickup:box")), "client helm causes actual authoritative collision")
		session.sim.command("navegacion", "helm", {"heading": 0.0, "throttle": 0.0})
		var path = directory.path_join("saved.json")
		check(LocalStorage.save_state(session.sim.state, path).is_empty(), "network host saves consumed pickup")
		var restored = LocalStorage.read_state(path)
		check(restored.has("state"), "network host restores save")
		if restored.has("state"):
			session.sim.state = restored.state
			for i in 5: SpacePickups.collect_path(session.sim, Vector2.ZERO, Vector2(500, 0))
		check(session.sim.state.operations.ammo.homing == 8, "restore and repeated crossings cannot duplicate ammo")
		check(session.sim.contact("box").hull == 0, "pickup remains consumed after restore")
		mark("reloaded")
		check(await wait_for(func(): return exists("client-done")), "client verifies resumed public state")
	else:
		check(session.join_session("127.0.0.1", port, "space-pickup-test-key", "Navegante", "navegacion").ok, "client connects over ENet")
		check(await wait_for(func(): return session.role == "navegacion" and not session.view.is_empty()), "client receives authenticated snapshot")
		check(not session.view.mission.has("contacts"), "full authored mission stays host-only")
		check(not session.view.contacts[0].has("supply_ammo"), "client cannot read authored pickup payload")
		session.order("pickup", {"target": "box"})
		check(await wait_for(func(): return responses.any(func(r): return not r.ok)), "forged remote pickup order denied")
		check(not session.view.facts.has("pickup:box") and session.view.operations.ammo.homing == 0, "rejected order grants nothing before collision")
		mark("client-ready")
		session.order("helm", {"heading": 0.0, "throttle": 1.0})
		check(await wait_for(func(): return exists("reloaded") and session.view.facts.has("pickup:box")), "client receives consumed pickup after host reload")
		check(session.view.contacts[0].hull == 0 and session.view.operations.ammo.homing == 8, "client sees same disappearance and ammo as host")
		check(session.view.ship.energy >= 35, "client sees restored energy")
		mark("client-done")
	# Host closes first; the client waits for the normal disconnect to avoid a teardown race.
	if mode == "host":
		session.close_session()
		mark("host-closed")
	else:
		await wait_for(func(): return exists("host-closed"))
		await delay()
		session.close_session()
	print("SPACE_PICKUP_NETWORK_RESULT ", mode, " checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
