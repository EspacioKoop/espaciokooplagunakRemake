extends SceneTree
var session: Node
var failures = 0
var responses: Array = []
var accepted = false
var closed = false

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("NETWORK_FAIL " + label)

func delay(seconds: float) -> void: await create_timer(seconds).timeout

func run() -> void:
	session = root.get_node("Session")
	var args = OS.get_cmdline_user_args()
	var mode = args[args.find("--case") + 1]
	var port = int(args[args.find("--port") + 1])
	session.notice.connect(func(message, ok): responses.append({"message": message, "ok": ok}))
	session.joined.connect(func(): accepted = true)
	session.disconnected.connect(func(): closed = true)
	if mode == "host":
		check(session.host_session(port, "lagunak-integration-test-key").ok, "host starts")
		print("NETWORK_HOST_READY")
		var maximum = 0
		for i in 90:
			maximum = maxi(maximum, session.roster.size())
			await delay(0.1)
		check(maximum == 3, "host and two authenticated stations")
		check(session.sim.state.ship.throttle == 0.4, "navigation command reaches authority")
		check(session.sim.state.ship.position[0] > 10, "authoritative ship moves")
		check(session.sim.state.ship.systems.armas.power == 4, "engineering command reaches authority")
		check(session.sim.state.ship.systems.sensores.power == 0, "shared power budget")
		check(session.role == "mando", "host station remains reserved")
		check(session.view.operations.destruct.codes.keys() == ["mando"], "host sees only captain confirmation code")
		check(session.view.cooperation.tasks.is_empty(), "host public view does not expose client skill tasks")
	else:
		var role = "navegacion" if mode == "nav" else "ingenieria"
		if mode == "busy": role = "mando"
		var key = "incorrect-test-key" if mode == "bad" else "lagunak-integration-test-key"
		check(session.join_session("127.0.0.1", port, key, "Integration", role).ok, "client starts")
		for i in 45:
			if closed or (accepted and not session.view.is_empty()): break
			await delay(0.1)
		if mode in ["bad", "busy"]:
			check(not accepted, "invalid credential or occupied station denied")
			check(closed, "denied peer disconnected")
		else:
			check(accepted and not session.view.is_empty(), "client receives state")
			if not session.view.is_empty():
				check(not session.view.mission.has("contacts"), "hidden catalogue excluded from RPC state")
			if mode == "nav":
				session.order("power", {"system": "armas", "value": 4})
				await delay(0.3)
				check(responses.any(func(r): return not r.ok and "otro puesto" in r.message), "wrong-role RPC rejected")
				session.order("helm", {"heading": 0.0, "throttle": 0.4})
				await delay(0.4)
				check(session.view.ship.throttle == 0.4, "navigation snapshot acknowledgement")
				check(session.view.operations.destruct.codes.is_empty(), "navigation cannot receive any confirmation code")
				session.select_role("mando")
				await delay(0.3)
				check(session.role == "navegacion", "occupied station cannot be stolen")
				var id = str(session.multiplayer.get_unique_id())
				# Presence is an unreliable stream, just as in the actual deck controller.
				# A single lost datagram must not make this integration check flaky.
				for attempt in 15:
					session.update_pose(Vector3(1, 1, 1), 0)
					await delay(0.1)
					if session.poses.has(id): break
				check(session.poses.has(id), "crew position replicated")
				session.update_pose(Vector3(500, 1, 1), 0)
				await delay(0.3)
				if session.poses.has(id): check(session.poses[id].position[0] == 1, "out-of-range position rejected")
			else:
				session.order("power", {"system": "sensores", "value": 0})
				await delay(0.3)
				session.order("power", {"system": "armas", "value": 4})
				await delay(0.4)
				check(session.view.ship.systems.armas.power == 4, "engineering snapshot acknowledgement")
				session.order("destruct_arm", {"confirmation": "ITSASO"})
				await delay(0.4)
				check(session.view.operations.destruct.codes.keys() == ["ingenieria"], "server routes only the station's code")
				session.order("assist_begin", {"recipient": "navegacion", "mode": "precision"})
				await delay(0.4)
				check(session.view.cooperation.tasks.keys() == [str(session.multiplayer.get_unique_id())], "server routes skill task to authenticated principal")
			await delay(1.0)
	session.close_session()
	print("NETWORK_RESULT ", mode, " failures=", failures)
	quit(1 if failures else 0)
