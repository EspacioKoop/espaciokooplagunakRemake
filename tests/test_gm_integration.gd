extends SceneTree

var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("GM_INTEGRATION_FAIL " + label)

func settle() -> void:
	for i in 4:
		await process_frame

func run() -> void:
	root.size = Vector2i(1600, 900)
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await settle()
	
	var session = root.get_node("Session")
	app._new_game()
	await settle()
	
	check(GMLiveActions.can_direct(session), "host authority allows GM direction")
	
	var gm_btn = app._refs.get("gm_button")
	check(gm_btn != null, "GM button exists in header")
	check(gm_btn != null and gm_btn.visible, "GM button is visible for host")
	check(gm_btn != null and not gm_btn.disabled, "GM button is enabled for host")
	
	# Open GM Console
	app._open_gm_console()
	await settle()
	
	check(app._gm_window != null, "GM window instance exists")
	check(is_instance_valid(app._gm_window), "GM window is valid")
	check(app._gm_window.is_inside_tree(), "GM window is inside tree")
	
	var console = app._gm_window as GMHotConsole
	check(console != null, "GM window is GMHotConsole class")
	
	if console != null:
		check(console.listing != null, "GM console listing exists")
		check(console.contact_id != null, "GM console contact ID field exists")
		
		# Execute GM alert event
		console.event_kind.select(0) # Alerta
		console.event_value.text = "roja"
		console._trigger_event()
		await settle()
		
		var alert = session.sim.state.get("ship", {}).get("alert", "")
		check(alert == "roja", "GM event applied red alert to simulation state")
		
		console.queue_free()
		await settle()
	
	app._ambient.stop()
	app._effects.stop()
	app._ambient.stream = null
	app._effects.stream = null
	app.queue_free()
	await settle()
	
	print("GM_INTEGRATION_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
