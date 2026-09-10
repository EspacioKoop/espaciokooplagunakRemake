extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var session = root.get_node("Session")
	session.new_campaign()
	var result = session.telemetry.start("http://localhost:30000", 29184)
	if not result.is_empty(): push_error(result); quit(1); return
	session.telemetry.token = "lagunak-telemetry-test-only"
	print("TELEMETRY_READY")
	await create_timer(20).timeout
	quit()
