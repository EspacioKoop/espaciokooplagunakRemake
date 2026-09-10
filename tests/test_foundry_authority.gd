extends SceneTree
var checks = 0
var failures = 0
var session: Node
var authority: FoundryAuthority

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func command(grant: Dictionary, operation: String, args: Dictionary = {}) -> Dictionary:
	return authority.dispatch(grant, {"run_id": grant.context.run_id, "sequence": grant.sequence, "operation": operation, "args": args})

func run() -> void:
	session = root.get_node("Session")
	session.suppress_saves = true
	var expedition = root.get_node("Expedition")
	expedition.data = expedition._default_data()
	var args = OS.get_cmdline_user_args()
	if "--foundry-peer" in args:
		var role = args[args.find("--foundry-peer") + 1]
		session.join_session("127.0.0.1", int(OS.get_environment("FOUNDRY_TEST_UDP")), "synthetic-foundry-network", role, role)
		await create_timer(45).timeout
		quit(); return
	session.new_campaign()
	authority = session.telemetry.authority
	var raw: Dictionary = session.sim.state
	raw.campaign_document = {"secret": "CANARY_CAMPAIGN"}
	raw.secret = "CANARY_TOP"
	raw.ship.secret = "CANARY_SHIP"
	raw.ship.systems.reactor.secret = "CANARY_SYSTEM"
	raw.contacts[0].secret = "CANARY_CONTACT"
	raw.contacts[3].name = "CANARY_HIDDEN"
	var profile: Dictionary = expedition.profile("self")
	profile.name = "Own synthetic crew"
	profile.secret = "CANARY_PROFILE"
	profile.milestones = ["CANARY_MILESTONE"]
	expedition.profile("other").name = "CANARY_OTHER"
	expedition.inventory("self").secret = "CANARY_INVENTORY"
	var issued = authority.issue("foundryAlice", 1, true)
	check(issued.ok and issued.token.length() == 64, "host-issued capability")
	var grant = authority.authenticate(issued.token, "foundryAlice")
	var safe = authority.view(grant)
	check(safe.crew.name == "Own synthetic crew" and safe.identity.role == "mando", "own existing profile projection")
	check(not "CANARY" in JSON.stringify(safe), "positive schema excludes all canaries including hidden contact and private data")
	check(authority.authenticate(issued.token, "foundryBob").is_empty(), "token bound to user label")
	check(authority.authenticate("forged", "foundryAlice").is_empty(), "invalid credential")
	check(not authority.issue("../user", 1).ok and not authority.issue("valid", 987).ok, "invalid user and unconnected principal")
	check(command(grant, "power", {"system": "reactor", "value": 1}).status == 403, "mando cannot use engineering")
	check(command(grant, "self_destruct", {}).status == 403, "no dangerous passthrough")
	check(command(grant, "alert", {"level": "roja", "role": "mando"}).status == 400, "extra role argument rejected")
	check(command(grant, "alert", {"level": {}}).status == 400, "nested data rejected")
	grant.count = 0
	var envelope = {"run_id": grant.context.run_id, "sequence": grant.sequence, "operation": "alert", "args": {"level": "ambar"}}
	check(authority.dispatch(grant, envelope).body.ok and session.sim.state.ship.alert == "ambar", "authority mutates real simulation")
	check(authority.dispatch(grant, envelope).status == 409, "replay cannot execute twice")
	check(authority.dispatch(grant, {"run_id": "old", "sequence": grant.sequence, "operation": "alert", "args": {"level": "verde"}}).status == 409, "stale mission denied")
	grant.count = 5
	check(command(grant, "alert", {"level": "roja"}).status == 429, "rate limited")
	var rotated = authority.issue("foundryAlice", 1, false)
	check(authority.authenticate(issued.token, "foundryAlice").is_empty(), "rotation revokes previous token")
	grant = authority.authenticate(rotated.token, "foundryAlice")
	check(command(grant, "alert", {"level": "roja"}).status == 403, "read-only grant cannot command")
	grant.until = Time.get_ticks_msec() - 1
	check(authority.authenticate(rotated.token, "foundryAlice").is_empty(), "expiry enforced")
	issued = authority.issue("foundryAlice", 1, true)
	session.select_role("ingenieria")
	session.select_role("mando")
	check(authority.authenticate(issued.token, "foundryAlice").is_empty(), "switching role away and back irrevocably revokes")
	issued = authority.issue("foundryAlice", 1, true)
	session.new_campaign()
	check(authority.authenticate(issued.token, "foundryAlice").is_empty(), "mission change revokes")
	for role in Catalog.ROLES:
		session.select_role(role)
		issued = authority.issue("stationUser", 1, true)
		grant = authority.authenticate(issued.token, "stationUser")
		check(not authority.commands(grant).is_empty(), "usable operations for " + role)
		for operation in authority.commands(grant): check(operation in Catalog.PERMISSIONS[role], "role permission for " + operation)
	issued = authority.issue("stationUser", 1, true)
	session.mode = "client"
	check(authority.authenticate(issued.token, "stationUser").is_empty() and not authority.issue("stationUser", 1, true).ok, "native client cannot grant or execute authority")
	session.mode = "offline"
	session.select_role("mando")
	# Exercise the native UI wiring without a display or clipboard use.
	var panel = FoundryAccessPanel.new()
	root.add_child(panel)
	panel.setup(session.telemetry)
	panel.user_id.text = "uiUser"
	panel._issue()
	check(panel.credential.text.length() == 64 and authority.grants().size() == 1, "native panel grants access")
	panel.hide()
	panel.queue_free()
	authority.clear()
	print("FOUNDRY_UNIT checks=%d failures=%d" % [checks, failures])
	if failures: quit(1); return
	if "--foundry-server" not in args: quit(); return
	# Two actual authenticated ENet peers provide distinct station identities.
	session.host_session(int(OS.get_environment("FOUNDRY_TEST_UDP")), "synthetic-foundry-network")
	print("FOUNDRY_HOST_READY")
	var deadline = Time.get_ticks_msec() + 10000
	while session.roster.size() < 3 and Time.get_ticks_msec() < deadline: await process_frame
	if session.roster.size() != 3: push_error("Missing ENet peers"); quit(1); return
	var ready: Dictionary = {"users": {}}
	check(session.telemetry.start("http://localhost:30000", int(OS.get_environment("FOUNDRY_TEST_HTTP"))).is_empty(), "HTTP listen")
	ready.legacy = session.telemetry.token
	for peer_id in session.roster:
		var role: String = session.roster[peer_id].role
		var user = "foundry_" + role
		expedition.profile(str(peer_id)).name = "Crew " + role
		ready.users[role] = authority.issue(user, int(peer_id), role != "ingenieria")
		ready.users[role].user = user
	var file = FileAccess.open(OS.get_environment("FOUNDRY_TEST_READY"), FileAccess.WRITE)
	file.store_string(JSON.stringify(ready))
	file.close()
	print("FOUNDRY_HTTP_READY")
	await create_timer(35).timeout
	quit()
