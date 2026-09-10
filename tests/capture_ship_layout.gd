extends SceneTree
## Graphical regression on the actual app, with an isolated --test session.
var app: Control
var deck: WorldDeck
var checks = 0
var failures = 0
var output = ""

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SHIP_LAYOUT_UI_FAIL " + label)

func settle(frames: int = 8) -> void:
	for i in frames: await physics_frame

func capture(name: String) -> void:
	# Leave the map tooltip before capturing, without altering the UI itself.
	Input.warp_mouse(Vector2(16, 16))
	var motion = InputEventMouseMotion.new()
	motion.position = Vector2(16, 16)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await settle(4)
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	check(image.save_png(output.path_join(name + ".png")) == OK, "capture " + name)

func click(point: Vector2) -> void:
	Input.warp_mouse(point)
	await settle(2)
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await settle(3)

func run() -> void:
	output = OS.get_environment("SHIP_LAYOUT_CAPTURE_DIR")
	if DisplayServer.get_name() == "headless" or output.is_empty():
		push_error("Graphical display and SHIP_LAYOUT_CAPTURE_DIR are required.")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create capture directory.")
		quit(1)
		return
	Input.use_accumulated_input = false
	root.size = Vector2i(1600, 900)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	app._new_game()
	root.get_node("Session").paused = true
	app._go("deck")
	await settle(18)
	deck = app._deck
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var original: Vector3 = deck.body.position
	var gate_states = deck._corridors.doors.map(func(door): return door.open)
	var target = deck._map.global_position + deck._map._point(ShipDeckLayout.ZONES[2].at)
	await click(target)
	check(deck._map.destination == 2, "real pointer click selects engineering route")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "map click does not capture the mouse")
	check(deck.body.position.distance_to(original) < 0.01, "map click does not move player")
	check(deck._corridors.doors.map(func(door): return door.open) == gate_states, "map click does not change hatches")
	await capture("01_bridge_and_plan")
	await RenderingServer.frame_post_draw
	var rect = deck._map.get_global_rect()
	var map_image = root.get_texture().get_image().get_region(Rect2i(Vector2i(rect.position), Vector2i(rect.size)))
	check(map_image.save_png(output.path_join("02_live_plan.png")) == OK, "capture live map region")
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	Input.flush_buffered_events()
	await settle(2)
	check(deck._map.destination == -1 and not deck._map.has_focus(), "Escape clears route and releases map focus")
	escape.pressed = false
	Input.parse_input_event(escape)
	deck.teleport_zone(1)
	deck.body.position = Vector3(0, 0.4, -15)
	deck.body.look_at(Vector3(0, 0.4, 12))
	await settle(18)
	deck._map.select_destination(2)
	await capture("03_longitudinal_hall")
	deck.teleport_zone(2)
	await settle(18)
	await capture("04_aft_engineering")
	root.size = Vector2i(960, 600)
	await settle(10)
	# The app uses a stretched logical canvas. Compare screen-space bounds to
	# the physical window, not unscaled 1600x900 canvas coordinates to 960x600.
	var transform = root.get_screen_transform() * deck._map.get_global_transform_with_canvas()
	var bounds: Rect2 = transform * Rect2(Vector2.ZERO, deck._map.size)
	var window_bounds = Rect2(Vector2(root.position), Vector2(root.size))
	print("SHIP_LAYOUT_SCREEN_BOUNDS ", bounds, " window=", window_bounds)
	check(window_bounds.grow(1.0).encloses(bounds), "map remains on screen at minimum desktop resolution")
	check(app.get_global_rect().encloses(deck._map.get_global_rect()), "map also remains inside logical UI bounds")
	await capture("05_minimum_resolution")
	app._ambient.stop()
	app._effects.stop()
	app._ambient.stream = null
	app._effects.stream = null
	app.queue_free()
	await settle(2)
	print("SHIP_LAYOUT_UI_TESTS ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
