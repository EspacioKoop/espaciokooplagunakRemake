extends SceneTree
## Integrated application regression. Fixture positioning is not a full ship walk.
var checks = 0
var failures = 0
var app: Control
var session: Node
var evidence_dir = ""

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error("TERMINAL_FAIL " + label)
	return value

func settle() -> void:
	for i in 4: await process_frame

func button_named(text: String, parent: Node = app) -> Button:
	for button in parent.find_children("*", "Button", true, false):
		if button.text == text and button.is_visible_in_tree(): return button
	return null

func interaction_event(device: String) -> InputEvent:
	for binding in InputMap.action_get_events("interact"):
		if (device == "keyboard" and binding is InputEventKey) or (device == "gamepad" and binding is InputEventJoypadButton):
			var event: InputEvent = binding.duplicate()
			event.pressed = true
			if event is InputEventKey: event.echo = false
			if event is InputEventJoypadButton: event.device = 0
			return event
	return null

func prepare_station(zone_index: int) -> WorldDeck:
	if app._page != "deck": app._go("deck")
	await settle()
	var deck: WorldDeck = app._deck
	deck.teleport_zone(zone_index)
	# The actual physics pass computes proximity. Never force _near_station.
	deck.body.position = WorldDeck.ZONES[zone_index].at + Vector3(0, 0.4, 1.0)
	deck.body.velocity = Vector3.ZERO
	for i in 3: await physics_frame
	await process_frame
	root.gui_release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	check(deck._near_station and deck._near_corridor_door < 0 and deck._near_door < 0 and deck._near_interaction.is_empty(), "fixture reaches physical terminal %d" % zone_index)
	check(not deck._controls_blocked() and deck._character_control_active(), "character input is active")
	return deck

func capture(name: String) -> void:
	if evidence_dir.is_empty(): return
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	check(image != null and image.save_png(evidence_dir.path_join(name + ".png")) == OK, "rendered capture " + name)

func open_station(zone_index: int, device: String) -> bool:
	var deck: WorldDeck = await prepare_station(zone_index)
	var event = interaction_event(device)
	if not check(event != null, "mapped interaction exists for " + device): return false
	var role: String = WorldDeck.ZONES[zone_index].role
	root.push_input(event)
	# This assertion fails on the original synchronous app receiver, even when
	# Godot logs a script error yet keeps the process running.
	var attached = is_instance_valid(deck) and deck.is_inside_tree()
	check(attached and app._page == "deck", "source survives input")
	check(root.is_input_handled(), "interaction handled before page disposal")
	await settle()
	check(app._page == "bridge" and session.role == role, "physical terminal opens correct station: " + role + "/" + device)
	check(not is_instance_valid(deck), "departed deck is released after callback")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "pointer released on terminal")
	return app._page == "bridge" and session.role == role

func return_to_deck() -> void:
	var back = button_named("Recorrer la cubierta")
	if check(back != null, "public return-to-deck button exists"):
		back.pressed.emit()
	await settle()
	check(app._page == "deck" and is_instance_valid(app._deck), "public button returns to live deck")

func stale_requests() -> void:
	app._go("deck")
	await settle()
	var previous_role: String = session.role
	app._deck.station_requested.emit("")
	app._deck.station_requested.emit("not-a-station")
	await settle()
	check(app._page == "deck" and session.role == previous_role, "invalid roles ignored")

	app._deck.station_requested.emit("ingenieria")
	app._go("home")
	await settle()
	check(app._page == "home" and session.role == previous_role, "request cannot override a later page change")

	app._go("deck")
	await settle()
	var old_id: int = app._deck.get_instance_id()
	app._deck.station_requested.emit("ingenieria")
	app._go("deck")
	var replacement_id: int = app._deck.get_instance_id()
	await settle()
	check(old_id != replacement_id and app._page == "deck" and app._deck.get_instance_id() == replacement_id and session.role == previous_role, "old deck request cannot open replacement deck")

	app._deck.station_requested.emit("ingenieria")
	app._deck.station_requested.emit("armas")
	await settle()
	check(app._page == "bridge" and session.role == "ingenieria", "duplicate requests produce only the first transition")

	app._go("deck")
	await settle()
	var detached: WorldDeck = app._deck
	var detached_id = detached.get_instance_id()
	detached.get_parent().remove_child(detached)
	app._open_deck_station("mando", detached_id)
	check(app._page == "deck" and session.role == "ingenieria", "detached source ignored")
	app._go("home")
	detached.free()
	await settle()

	app._go("deck")
	await settle()
	var doomed: WorldDeck = app._deck
	doomed.queue_free()
	app._open_deck_station("mando", doomed.get_instance_id())
	check(app._page == "deck" and session.role == "ingenieria", "queued-for-deletion source ignored")
	app._go("home")
	await settle()

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var output_index = args.find("--evidence-dir")
	if output_index >= 0 and output_index + 1 < args.size(): evidence_dir = args[output_index + 1]
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await settle()
	session = root.get_node("Session")
	# Freeze only the simulation clock, not input, physics, render or page logic.
	session.set_process(false)
	app._new_game()
	await settle()
	if "--probe-only" in args:
		await open_station(0, "keyboard")
	else:
		for zone_index in [0, 2, 3, 4, 5, 6]:
			for device in ["keyboard", "gamepad"]:
				var opened = await open_station(zone_index, device)
				if not opened: continue
				if zone_index == 0:
					var autopilot = button_named("Piloto automático")
					if check(autopilot != null, "usable navigation control exists"):
						autopilot.pressed.emit()
						check(session.sim.state.ship.autopilot == "argi", "terminal performs real navigation order")
				if zone_index == 5:
					var alert = button_named("Alerta ambar")
					if check(alert != null, "usable command control exists"):
						alert.pressed.emit()
						check(session.sim.state.ship.alert == "ambar", "terminal performs real alert order")
				var operations: Window = app._open_operations()
				await settle()
				check(operations.visible and operations.get_child(0).get_child(0).role == session.role, "operations window uses requested role")
				operations.close_requested.emit()
				await settle()
				check(not is_instance_valid(operations), "operations window closes safely")
				if zone_index == 0 and device == "keyboard": await capture("terminal-navigation")
				await return_to_deck()
				if zone_index == 0 and device == "keyboard": await capture("terminal-return")
		await stale_requests()
		app._go("deck")
		await settle()
		var role_before: String = session.role
		app._deck.station_requested.emit("mando")
		app.queue_free()
		app._open_deck_station("mando", app._deck.get_instance_id())
		check(session.role == role_before, "closing app ignores pending request")
	if is_instance_valid(app) and not app.is_queued_for_deletion(): app.queue_free()
	await settle()
	print("TERMINAL_TRANSITION_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
