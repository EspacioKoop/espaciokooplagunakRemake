extends SceneTree
var failures = 0
var checks = 0
var app: Control

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("UI_FAIL " + label)

func settle() -> void:
	for i in 4: await process_frame

func run() -> void:
	root.size = Vector2i(1600, 900)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await settle()
	var session = root.get_node("Session")
	app._new_game()
	await settle()
	check(session.role == "navegacion", "new game selects navigation")
	var autopilot: Button
	for button in app.find_children("*", "Button", true, false):
		if button.text == "Piloto automático": autopilot = button
	check(autopilot != null, "navigation control exists")
	if autopilot != null: autopilot.pressed.emit()
	check(session.sim.state.ship.autopilot == "argi", "navigation button issues real order")
	for role in Catalog.ROLES:
		app._choose_role(role)
		await settle()
		check(session.role == role and app._last_role == role, "station controls " + role)
		check(app._footer.get_global_rect().end.y <= 900, "station layout stays inside actual window: " + role)
	for page in ["home", "bridge", "deck", "atlas", "campaign", "editor", "sessions", "settings"]:
		app._go(page)
		await settle()
		check(app._footer.get_global_rect().end.y <= root.get_visible_rect().size.y + 1, "footer within viewport on " + page)
		check(app._content.get_global_rect().end.x <= root.get_visible_rect().size.x + 1, "content width on " + page)
		if page == "deck":
			var zones = app._deck.get_script().get_script_constant_map().ZONES
			for index in zones.size():
				app._deck.teleport_zone(index)
				await create_timer(0.5).timeout
				check(app._deck.body.is_on_floor(), "walkable floor " + zones[index].name)
		if page == "editor":
			var editor = app._editor
			editor._new_mission()
			editor._add_contact(Vector2(250, 300))
			check(editor.mission.contacts.size() == 2, "editor adds contact")
			var id: String = editor.mission.contacts.back().id
			editor._move_contact(id, Vector2(600, 400))
			check(editor.mission.contacts.back().position == [600.0, 400.0], "editor moves contact")
			editor._undo_change()
			check(editor.mission.contacts.back().position == [250.0, 300.0], "editor undo restores coordinates")
			editor._save()
			var path = "user://missions/" + editor.mission.id + ".json"
			check(FileAccess.file_exists(path), "editor writes mission")
			editor._load_file(ProjectSettings.globalize_path(path))
			check(Catalog.validate_mission(editor.mission).is_empty(), "saved mission reopens")
			editor._open_ship_design()
			await settle()
			var design_editor: ShipDesignEditor
			for child in editor.get_children():
				if child is ShipDesignEditor: design_editor = child
			check(design_editor != null, "native ship design window opens")
			design_editor.fields.hull.value = 175
			design_editor._apply_design()
			await settle()
			check(editor.mission.ship_design.hull == 175, "design controls update authored mission")
			var authored = Simulation.new()
			authored.start(editor.mission)
			check(authored.state.ship.max_hull == 175, "edited design changes actual playable ship")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	session.select_role("ingenieria")
	var operations = app._open_operations()
	await settle()
	var console = operations.get_child(0).get_child(0)
	console.action_menu.item_selected.emit(console.definitions.find("coolant_level"))
	for i in console.fields.system.item_count:
		if console.fields.system.get_item_metadata(i) == "armas": console.fields.system.select(i)
	console.fields.value.value = 3.0
	for button in console.find_children("*", "Button", true, false):
		if button.text == "Ejecutar orden": button.pressed.emit()
	check(session.sim.state.operations.coolant.armas == 3.0, "native operations form applies actual coolant")
	operations.queue_free()
	await settle()
	session.select_role("mando")
	var assistance = app._open_assistance()
	await settle()
	var aid = assistance.get_child(0).get_child(0).get_child(0)
	aid.chooser.select(2)
	for i in aid.recipient.item_count:
		if aid.recipient.get_item_metadata(i) == "ingenieria": aid.recipient.select(i)
	aid.start_button.pressed.emit()
	await settle()
	check(session.sim.state.cooperation.tasks.local.mode == "precision", "native assistance button starts selected skill task")
	check(aid.chooser.disabled and aid.recipient.disabled, "active challenge displays locked actual selections")
	var task: Dictionary = session.sim.state.cooperation.tasks.local
	var click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(task.center[0] * aid.panel.size.x, task.center[1] * aid.panel.size.y)
	aid.panel.gui_input.emit(click)
	var before_assistance: Dictionary = session.sim.state.ship.duplicate(true)
	for button in aid.find_children("*", "Button", true, false):
		if button.text == "Enviar resultado": button.pressed.emit()
	check(session.sim.state.cooperation.tokens.size() == 1, "native precision input creates proposal")
	check(session.sim.state.ship == before_assistance, "native helper does not directly operate the ship")
	session.select_role("ingenieria")
	for button in aid.find_children("*", "Button", true, false):
		if button.text == "Aplicar la primera propuesta para mi puesto": button.pressed.emit()
	check(session.sim.state.operations.coolant.motores > 0 and session.sim.state.cooperation.tokens.is_empty(), "native recipient consumes proposal exactly once")
	assistance.queue_free()
	await settle()
	var hamachi_suite = load(get_script().resource_path.get_base_dir().path_join("test_hamachi_ui.gd"))
	var hamachi_result: Dictionary = await hamachi_suite.verify(self, app)
	check(hamachi_result.checks > 0 and hamachi_result.failures == 0, "Hamachi helper and production launcher UI")
	app._ambient.stop()
	app._effects.stop()
	app._ambient.stream = null
	app._effects.stream = null
	app.queue_free()
	await settle()
	var score_suite = load(get_script().resource_path.get_base_dir().path_join("test_reactive_score.gd"))
	var score_result: Dictionary = await score_suite.verify(self)
	check(score_result.failures == 0, "procedural music synthesis, privacy and native controls")
	print("UI_OK ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
