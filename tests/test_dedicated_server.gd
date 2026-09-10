extends SceneTree
var checks = 0
var failures = 0
var session: Node
var accepted = false
var closed = false

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("DEDICATED_FAIL " + message)

func run() -> void:
	session = root.get_node("Session")
	session.joined.connect(func(): accepted = true)
	session.disconnected.connect(func(): closed = true)
	var mode = OS.get_environment("LAGUNAK_TEST_MODE")
	var key = FileAccess.get_file_as_string(OS.get_environment("LAGUNAK_KEY_FILE")).strip_edges()
	if mode == "bad": key = "synthetic-wrong-key"
	check(session.join_session(OS.get_environment("LAGUNAK_TEST_ADDRESS"), int(OS.get_environment("LAGUNAK_TEST_PORT")), key, "Dedicated fixture", "mando").ok, "native client starts")
	var deadline = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline and not closed and (not accepted or session.view.is_empty()): await process_frame
	if mode == "bad":
		check(not accepted and closed and session.view.is_empty(), "wrong key receives no snapshot")
	else:
		check(accepted and not session.view.is_empty(), "authenticated client receives native state")
		if not session.view.is_empty():
			check(session.role == "mando", "dedicated host leaves Mando available")
			check(session.roster.get("1", {}).get("role", "missing") == "", "server is observer")
			check(not session.view.mission.has("contacts") and not session.view.has("campaign_document"), "future content remains private")
			check(not session.start_mission(1).ok, "client cannot bypass campaign authority")
			if mode == "resume":
				check(session.view.run_id == OS.get_environment("LAGUNAK_TEST_RUN"), "same run restored")
				check(session.view.ship.alert == "roja", "last native order persisted")
			else:
				session.order("alert", {"level": "roja"})
				deadline = Time.get_ticks_msec() + 3000
				while Time.get_ticks_msec() < deadline and session.view.ship.alert != "roja": await process_frame
				check(session.view.ship.alert == "roja", "native authority applies Mando order")
			print("DEDICATED_RUN " + session.view.run_id)
	session.close_session()
	await create_timer(0.2).timeout
	print("DEDICATED_CLIENT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
