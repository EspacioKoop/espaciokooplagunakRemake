extends SceneTree
var failures = 0
var checks = 0
var app: Control
var controls: Node
var hud: Control

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("TOUCH_FAIL " + label)
func settle() -> void:
	for i in 4: await process_frame
func physics_settle() -> void:
	for i in 6: await physics_frame
func touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func drag(index: int, position: Vector2, relative: Vector2) -> void:
	var event = InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func tap(position: Vector2) -> void:
	touch(0, position, true)
	await process_frame
	touch(0, position, false)
	await settle()

func run() -> void:
	Input.use_accumulated_input = false
	Input.emulate_mouse_from_touch = true
	root.size = Vector2i(1600, 900)
	controls = root.get_node("Controls")
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	hud = controls.touch
	check(hud.enabled == DisplayServer.is_touchscreen_available(), "automatic detection preserves desktop default")
	check(not hud.visible, "HUD stays hidden outside a playable deck")
	app._new_game()
	app._go("deck")
	await settle()
	controls.open_settings()
	await settle()
	var checkbox = controls.panel.find_child("TouchControlsToggle", true, false)
	check(checkbox != null, "settings exposes explicit desktop touch activation")
	if not checkbox.button_pressed: await tap(checkbox.get_global_rect().get_center())
	check(hud.enabled, "actual screen tap enables touch mode")
	await tap(controls.panel.close_button.get_global_rect().get_center())
	check(not controls.is_settings_open(), "actual screen tap closes settings")
	check(hud.visible and not hud.walking, "deck offers touch walk button with menus usable")
	for dimensions in [Vector2i(960, 600), Vector2i(1600, 900), Vector2i(900, 1200)]:
		root.size = dimensions
		await settle()
		for region in hud.regions().values():
			check(region.position.x >= 0 and region.position.y >= 0 and region.end.x <= hud.size.x and region.end.y <= hud.size.y, "touch region stays inside viewport " + str(dimensions))
	root.size = Vector2i(1600, 900)
	await settle()
	var area = hud.regions()
	await tap(area.mode.get_center())
	check(hud.walking and controls.character_control_active(), "screen walk mode activates without cursor capture")
	var deck = app._deck
	deck.teleport_zone(9)
	deck.body.position = Vector3(0, 0.4, 250)
	deck.body.rotation.y = 0
	await physics_settle()
	var origin: Vector2 = area.move.get_center()
	var start: Vector3 = deck.body.position
	touch(1, origin, true)
	drag(1, origin + Vector2(0, -39), Vector2(0, -39))
	await physics_settle()
	check(Vector2(deck.body.position.x - start.x, deck.body.position.z - start.z).length() > 0.1, "touch stick physically moves character")
	check(absf(Vector2(deck.body.velocity.x, deck.body.velocity.z).length() - 1.55) < 0.15, "touch stick preserves analog movement: movement=%s velocity=%s" % [hud.movement, deck.body.velocity])
	var look: Vector2 = area.look.position + Vector2(100, 80)
	var yaw: float = deck.body.rotation.y
	touch(2, look, true)
	drag(2, look + Vector2(70, 15), Vector2(70, 15))
	await physics_settle()
	check(absf(deck.body.rotation.y - yaw) > 0.1, "second finger turns actual character camera while walking")
	check(hud.movement.y < -0.4, "look finger does not steal movement finger")
	touch(3, origin, true)
	drag(3, origin + Vector2(78, 0), Vector2(78, 0))
	check(hud.movement.x == 0, "second movement pointer cannot steal stick")
	touch(3, Vector2.ZERO, false)
	touch(2, Vector2.ZERO, false)
	var paused_yaw: float = deck.body.rotation.y
	await physics_settle()
	check(is_equal_approx(deck.body.rotation.y, paused_yaw), "released look does not drift")
	touch(4, area.sprint.get_center(), true)
	await physics_settle()
	check(controls.action_pressed("sprint") and Vector2(deck.body.velocity.x, deck.body.velocity.z).length() > 2.3, "held touch sprint uses actual existing movement speed: movement=%s velocity=%s sprint=%s" % [hud.movement, deck.body.velocity, controls.action_pressed("sprint")])
	Input.action_press("sprint")
	touch(4, Vector2.ZERO, false)
	check(Input.is_action_pressed("sprint") and controls.action_pressed("sprint"), "touch release preserves physical sprint held separately")
	Input.action_release("sprint")
	touch(1, Vector2.ZERO, false, true)
	await physics_settle()
	check(hud.movement == Vector2.ZERO and deck.body.velocity.length() < 0.05, "canceled stick stops movement")
	var before = hud.movement
	drag(17, origin, Vector2(500, 500))
	touch(-1, origin, true)
	touch(99, origin, true)
	touch(5, Vector2(NAN, 0), true)
	check(hud.movement == before and hud._pointers.is_empty(), "orphan malformed and out-of-range pointers ignored")
	deck.teleport_zone(11)
	var lights: Dictionary = {}
	for entry in deck._interactions:
		if entry.zone == 11 and entry.kind == "lights": lights = entry
	check(not lights.is_empty(), "real studio light interaction exists")
	if not lights.is_empty():
		deck.body.position = lights.position + Vector3(0, 0.4, 1.0)
		await physics_settle()
		check(deck._near_interaction.get("id", "") == lights.id, "character physically reaches studio controls")
		var previous: int = deck._studio_mode
		await tap(area.interact.get_center())
		check(deck._studio_mode == (previous + 1) % 4, "screen interact emits existing InputMap action exactly once")
	if DisplayServer.get_name() != "headless" and not OS.get_environment("TOUCH_CAPTURE_PATH").is_empty():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OS.get_environment("TOUCH_CAPTURE_PATH")) == OK, "real graphical touch HUD screenshot")
	await tap(area.settings.get_center())
	check(controls.is_settings_open() and not hud.walking, "HUD opens settings without emulated click closing it again")
	check(controls.movement_vector() == Vector2.ZERO, "settings blocks touch movement")
	await tap(controls.panel.close_button.get_global_rect().get_center())
	check(not controls.is_settings_open() and not hud.walking, "touch exits settings with neutral input")
	await tap(area.mode.get_center())
	touch(6, origin, true)
	drag(6, origin + Vector2(50, 0), Vector2(50, 0))
	hud._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not hud.walking and hud._pointers.is_empty() and hud.movement == Vector2.ZERO, "focus loss cancels all touch input")
	await tap(area.mode.get_center())
	app._go("bridge")
	await settle()
	check(not hud.visible and not hud.walking, "leaving deck hides controls and cancels ownership")
	hud.set_enabled(false)
	app._go("deck")
	await settle()
	check(not hud.visible, "explicit desktop disable restores normal interface")
	app._ambient.stop()
	app._effects.stop()
	app._ambient.stream = null
	app._effects.stream = null
	app.queue_free()
	await settle()
	print("TOUCH_CONTROLS_OK ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
