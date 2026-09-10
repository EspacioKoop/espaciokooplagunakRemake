extends SceneTree
const Profile = preload("res://input/control_profile.gd")
var checks = 0
var failures = 0
var controls: Node
var app: Control

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("INPUT_UI_FAIL " + message)
func settle() -> void:
	for i in 4: await process_frame
func key(code: int, pressed: bool = true) -> void:
	var event = Profile.event_for_key(code)
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func pad_button(code: int, pressed: bool = true) -> void:
	var event = InputEventJoypadButton.new()
	event.button_index = code
	event.pressed = pressed
	event.device = 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func pad_axis(code: int, amount: float) -> void:
	var event = InputEventJoypadMotion.new()
	event.axis = code
	event.axis_value = amount
	event.device = 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	Input.use_accumulated_input = false
	root.size = Vector2i(1600, 900)
	controls = root.get_node("Controls")
	controls.commit_profile(Profile.defaults())
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	check(controls._launcher.is_visible_in_tree(), "controls accessible from executable home")
	key(KEY_F9)
	key(KEY_F9, false)
	await settle()
	check(controls.is_settings_open(), "F9 opens real panel")
	check(controls.gameplay_blocked(), "panel blocks gameplay")
	var panel = controls.panel
	check(panel.binding_buttons.size() == Profile.ACTIONS.size() * 2, "every character action has keyboard and pad editors")
	for viewport in [Vector2i(960, 600), Vector2i(1600, 900)]:
		root.size = viewport
		await settle()
		check(panel.get_global_rect().end.x <= root.get_visible_rect().size.x + 1, "panel fits width " + str(viewport))
		check(panel.close_button.get_global_rect().end.y < root.get_visible_rect().size.y, "exit visible at " + str(viewport))
		check(panel.status.get_global_rect().end.y < root.get_visible_rect().size.y, "binding feedback visible at " + str(viewport))
	panel._begin_capture("move_forward", "keyboard")
	await create_timer(0.18).timeout
	key(KEY_S)
	key(KEY_S, false)
	check(panel.waiting_action == "move_forward", "duplicate binding remains in capture with feedback")
	check(controls.profile.bindings.move_forward.key == KEY_W, "duplicate does not mutate controls")
	key(KEY_T)
	key(KEY_T, false)
	check(panel.waiting_action.is_empty() and controls.profile.bindings.move_forward.key == KEY_T, "real keyboard capture remaps action")
	panel._begin_capture("interact", "gamepad")
	await create_timer(0.18).timeout
	pad_button(JOY_BUTTON_Y)
	pad_button(JOY_BUTTON_Y, false)
	check(controls.profile.bindings.interact.pad.code == JOY_BUTTON_Y, "gamepad button capture persists")
	panel._begin_capture("look_down", "gamepad")
	await create_timer(0.18).timeout
	pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.2)
	check(panel.waiting_action == "look_down", "small axis noise ignored during capture")
	pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	check(panel.waiting_action.is_empty() and controls.profile.bindings.look_down.pad.code == JOY_AXIS_TRIGGER_RIGHT, "gamepad axis capture persists")
	panel._begin_capture("sprint", "keyboard")
	key(KEY_ESCAPE)
	key(KEY_ESCAPE, false)
	check(panel.waiting_action.is_empty() and controls.is_settings_open(), "Escape cancels capture without dismissing settings")
	panel._set_option("locale", "en")
	check(TranslationServer.translate("Controles guardados.") == "Controls saved.", "language changes without scene restart")
	check(current_scene == app, "locale preserves running application")
	key(KEY_ESCAPE)
	key(KEY_ESCAPE, false)
	await settle()
	check(not controls.is_settings_open(), "Escape closes panel")
	app._new_game()
	app._go("deck")
	await settle()
	await create_timer(0.35).timeout
	var deck = app._deck
	var has_display = DisplayServer.get_name() != "headless"
	if not has_display: print("INPUT_UI_DISPLAY_LIMIT: headless cannot capture a cursor; physical walking assertions run with --graphical")
	if "--require-display" in OS.get_cmdline_user_args(): check(has_display, "graphical validation requires a display")
	key(KEY_C)
	key(KEY_C, false)
	await settle()
	if has_display: check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "capture action enters character mode")
	var start: Vector3 = deck.body.position
	key(KEY_T)
	await create_timer(0.3).timeout
	key(KEY_T, false)
	if has_display: check(deck.body.position.distance_to(start) > 0.5, "remapped keyboard physically walks character")
	var stopped: Vector3 = deck.body.position
	key(KEY_W)
	await create_timer(0.18).timeout
	key(KEY_W, false)
	check(Vector2(deck.body.position.x - stopped.x, deck.body.position.z - stopped.z).length() < 0.05, "old key no longer moves character")
	start = deck.body.position
	pad_axis(JOY_AXIS_LEFT_Y, -0.6)
	await create_timer(0.3).timeout
	pad_axis(JOY_AXIS_LEFT_Y, 0)
	var half_distance: float = deck.body.position.distance_to(start)
	if has_display: check(half_distance > 0.15 and half_distance < 0.8, "analog stick moves character proportionally")
	var yaw: float = deck.body.rotation.y
	pad_axis(JOY_AXIS_RIGHT_X, 0.8)
	await create_timer(0.2).timeout
	pad_axis(JOY_AXIS_RIGHT_X, 0)
	if has_display: check(absf(deck.body.rotation.y - yaw) > 0.15, "right stick rotates actual camera")
	key(KEY_F9)
	key(KEY_F9, false)
	await settle()
	check(controls.is_settings_open(), "settings opens during captured gameplay")
	start = deck.body.position
	pad_axis(JOY_AXIS_LEFT_Y, -1)
	await create_timer(0.2).timeout
	pad_axis(JOY_AXIS_LEFT_Y, 0)
	check(deck.body.position.distance_to(start) < 0.05, "settings blocks real character movement")
	pad_button(JOY_BUTTON_B)
	pad_button(JOY_BUTTON_B, false)
	await settle()
	check(not controls.is_settings_open(), "gamepad B closes dialog before interior consumes event")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "closing menu leaves safe released pointer")
	pad_button(JOY_BUTTON_START)
	pad_button(JOY_BUTTON_START, false)
	await settle()
	if has_display: check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Start resumes walking without a mouse")
	controls._joy_connection_changed(0, false)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "disconnect releases captured pointer")
	if has_display:
		deck.teleport_zone(10)
		var seat: Dictionary = {}
		for entry in deck._interactions:
			if entry.zone == 10 and entry.kind == "seat":
				seat = entry
				break
		check(not seat.is_empty(), "real terrace seat exists for interaction")
		if not seat.is_empty():
			deck.body.position = seat.position + Vector3(0, 0.4, 0.8)
			await create_timer(0.2).timeout
			pad_button(JOY_BUTTON_START)
			pad_button(JOY_BUTTON_START, false)
			pad_button(JOY_BUTTON_Y)
			pad_button(JOY_BUTTON_Y, false)
			check(deck.seated, "remapped gamepad action sits at a nearby real seat")
			pad_button(JOY_BUTTON_Y)
			pad_button(JOY_BUTTON_Y, false)
			check(not deck.seated, "remapped gamepad action stands up")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	app._go("bridge")
	await settle()
	var autopilot: Button
	for button in app.find_children("*", "Button", true, false):
		if button.text == "Piloto automático": autopilot = button
	check(autopilot != null, "navigation button available to controller focus")
	if autopilot != null:
		autopilot.grab_focus()
		pad_button(JOY_BUTTON_A)
		pad_button(JOY_BUTTON_A, false)
		await settle()
		check(root.get_node("Session").sim.state.ship.autopilot == "argi", "gamepad A activates actual ship autopilot through UI")
	app._go("home")
	await settle()
	root.gui_release_focus()
	pad_button(JOY_BUTTON_A)
	pad_button(JOY_BUTTON_A, false)
	check(root.gui_get_focus_owner() != null, "controller restores focus for UI navigation")
	var old_focus = root.gui_get_focus_owner()
	pad_button(JOY_BUTTON_RIGHT_SHOULDER)
	pad_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	check(root.gui_get_focus_owner() != old_focus, "shoulder button advances actual UI focus")
	controls.commit_profile(Profile.defaults())
	app._ambient.stop()
	app._effects.stop()
	app._ambient.stream = null
	app._effects.stream = null
	app.queue_free()
	await settle()
	print("INPUT_UI_OK ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
