extends SceneTree
const Profile = preload("res://input/control_profile.gd")
var checks = 0
var failures = 0

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("INPUT_FAIL " + message)

func run() -> void:
	Input.use_accumulated_input = false
	var defaults = Profile.defaults()
	check(Profile.validate(defaults).is_empty(), "defaults valid")
	check(Profile.validate(JSON.parse_string(JSON.stringify(defaults))).is_empty(), "JSON numeric round trip valid")
	var invalids: Array = [null, [], {}, "profile"]
	for sample in invalids: check(not Profile.validate(sample).is_empty(), "reject wrong root type")
	for field in ["version", "locale", "mouse_sensitivity", "gamepad_sensitivity", "deadzone", "invert_y", "bindings"]:
		var value = defaults.duplicate(true)
		value.erase(field)
		check(not Profile.validate(value).is_empty(), "reject missing " + field)
	for entry in [["version", 2], ["version", 1.5], ["locale", "xx"], ["invert_y", 1], ["mouse_sensitivity", NAN], ["mouse_sensitivity", INF], ["mouse_sensitivity", 0], ["gamepad_sensitivity", 99], ["deadzone", 0.9]]:
		var value = defaults.duplicate(true)
		value[entry[0]] = entry[1]
		check(not Profile.validate(value).is_empty(), "reject invalid " + str(entry[0]))
	for key in [KEY_ESCAPE, KEY_F9, KEY_1, KEY_F5, -1, 1.5, "W"]:
		var value = defaults.duplicate(true)
		value.bindings.move_forward.key = key
		check(not Profile.validate(value).is_empty(), "reject unsafe key " + str(key))
	var duplicate = defaults.duplicate(true)
	duplicate.bindings.move_forward.key = KEY_S
	check(not Profile.validate(duplicate).is_empty(), "reject duplicate key")
	duplicate = defaults.duplicate(true)
	duplicate.bindings.move_forward.pad = duplicate.bindings.move_back.pad.duplicate()
	check(not Profile.validate(duplicate).is_empty(), "reject duplicate controller input")
	for pad in [{}, {"kind": "axis", "code": 0, "direction": 0}, {"kind": "axis", "code": 8, "direction": 1}, {"kind": "button", "code": -1}, {"kind": "button", "code": 1.5}, {"kind": "button", "code": 0, "secret": "no"}]:
		var value = defaults.duplicate(true)
		value.bindings.interact.pad = pad
		check(not Profile.validate(value).is_empty(), "reject malformed pad")
	var service = root.get_node("Controls")
	check(service.load_error.is_empty(), "first launch has clean default profile")
	for action in Profile.ACTIONS:
		check(InputMap.has_action(action), "action installed: " + action)
		check(InputMap.action_get_events(action).size() == 2, "keyboard plus controller: " + action)
		check(is_equal_approx(InputMap.action_get_deadzone(action), 0.2), "deadzone installed: " + action)
	check(service.rebind("move_forward", "keyboard", KEY_T).is_empty(), "remap forward")
	var ev = Profile.event_for_key(KEY_T)
	ev.pressed = true
	Input.parse_input_event(ev.duplicate())
	Input.flush_buffered_events()
	check(Input.is_action_pressed("move_forward"), "real remapped keyboard event enters InputMap")
	check(service.movement_vector().y < -0.99, "remapped movement exposed to character")
	ev.pressed = false
	Input.parse_input_event(ev.duplicate())
	Input.flush_buffered_events()
	var old = Profile.event_for_key(KEY_W)
	old.pressed = true
	Input.parse_input_event(old.duplicate())
	Input.flush_buffered_events()
	check(not Input.is_action_pressed("move_forward"), "old keyboard key removed")
	old.pressed = false
	Input.parse_input_event(old.duplicate())
	Input.flush_buffered_events()
	var saved = Profile.load_file(service.profile_path)
	check(saved.error.is_empty() and saved.profile.bindings.move_forward.key == KEY_T, "profile persists to disk")
	var before: Dictionary = service.profile.duplicate(true)
	check(not service.rebind("move_forward", "keyboard", KEY_S).is_empty(), "conflict refused")
	check(service.profile == before, "invalid remap leaves live profile intact")
	check(Profile.load_file(service.profile_path).profile == before, "invalid remap leaves persisted profile intact")
	var path = service.profile_path
	service.profile_path = "user://missing_directory/controls.json"
	check(not service.rebind("move_forward", "keyboard", KEY_G).is_empty(), "save failure reported")
	check(service.profile == before, "save failure leaves live InputMap unchanged")
	service.profile_path = path
	var candidate: Dictionary = service.profile.duplicate(true)
	candidate.deadzone = 0.3
	candidate.mouse_sensitivity = 2.0
	candidate.gamepad_sensitivity = 1.5
	candidate.invert_y = true
	candidate.locale = "en"
	check(service.commit_profile(candidate).is_empty(), "apply camera and locale")
	check(is_equal_approx(InputMap.action_get_deadzone("move_forward"), 0.3), "changed deadzone applied")
	check(service.mouse_look(Vector2(10, 10)).is_equal_approx(Vector2(0.044, -0.044)), "mouse sensitivity and inversion effective")
	check(TranslationServer.translate("Teclado y mando") == "Keyboard and gamepad", "English translation loads")
	Input.action_press("look_down", 1.0)
	check(service.look_vector().y < -3.2, "gamepad sensitivity and inversion effective")
	Input.action_release("look_down")
	var corrupt = "user://input-corrupt.json"
	var file = FileAccess.open(corrupt, FileAccess.WRITE)
	file.store_string("{broken JSON")
	file.close()
	var recovered = Profile.load_file(corrupt)
	check(not recovered.error.is_empty() and recovered.profile == defaults, "corrupt file safely resets profile")
	file = FileAccess.open(corrupt, FileAccess.WRITE)
	file.store_string("x".repeat(Profile.MAX_BYTES + 1))
	file.close()
	check(not Profile.load_file(corrupt).error.is_empty(), "oversized file rejected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupt))
	check(service.commit_profile(defaults).is_empty(), "restore defaults")
	check(TranslationServer.translate("Teclado y mando") == "Teclado y mando", "Spanish live reset")
	print("INPUT_CONTROLS_OK ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
