extends Node
## InputMap is the only source of active bindings; this service owns preferences.
signal profile_changed

const Profile = preload("res://input/control_profile.gd")
const SettingsPanel = preload("res://ui/control_settings.gd")
var profile: Dictionary = Profile.defaults()
var profile_path = "user://controls-v1.json"
var last_device = "keyboard"
var load_error = ""
var panel: Control
var _layer: CanvasLayer
var _launcher: Button
var _focus_before: WeakRef

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Test processes never overwrite a person's normal preferences.
	if "--test" in OS.get_cmdline_user_args(): profile_path = "user://controls-test-v1.json"
	var loaded = Profile.load_file(profile_path)
	profile = loaded.profile
	load_error = loaded.error
	Profile.install(profile)
	TranslationServer.set_locale(profile.locale)
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_select", JOY_BUTTON_X], ["ui_cancel", JOY_BUTTON_B], ["ui_up", JOY_BUTTON_DPAD_UP], ["ui_down", JOY_BUTTON_DPAD_DOWN], ["ui_left", JOY_BUTTON_DPAD_LEFT], ["ui_right", JOY_BUTTON_DPAD_RIGHT], ["ui_focus_next", JOY_BUTTON_RIGHT_SHOULDER], ["ui_focus_prev", JOY_BUTTON_LEFT_SHOULDER]]:
		var event = InputEventJoypadButton.new()
		event.button_index = pair[1]
		event.device = -1
		if not InputMap.action_has_event(pair[0], event): InputMap.action_add_event(pair[0], event)
	call_deferred("_create_launcher")
	Input.joy_connection_changed.connect(_joy_connection_changed)

func _create_launcher() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)
	_launcher = Button.new()
	_launcher.name = "ControlSettingsLauncher"
	_launcher.text = "Controles · F9"
	_launcher.tooltip_text = "Configurar teclado y mando"
	_launcher.theme = ConsoleUI.make_theme()
	_launcher.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_launcher.offset_left = -198
	_launcher.offset_right = -16
	_launcher.offset_top = -51
	_launcher.offset_bottom = -8
	_launcher.pressed.connect(open_settings)
	_layer.add_child(_launcher)

func _process(_delta: float) -> void:
	if _launcher != null:
		_launcher.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not is_settings_open()

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadButton or absf(event.axis_value) > float(profile.deadzone): last_device = "gamepad"
	elif event is InputEventKey or event is InputEventMouseButton: last_device = "keyboard"
	if is_settings_open():
		if panel.capture_event(event): get_viewport().set_input_as_handled()
		return
	# F9 is a fixed recovery shortcut in addition to the chosen binding.
	if event.is_action_pressed("controls_settings") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9):
		open_settings()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (event is InputEventJoypadButton or event.is_action("ui_accept")) and not Profile.ACTIONS.any(func(action): return event.is_action(action)):
		# Forward bound actions to the character; unused UI buttons must not click a background menu.
		get_viewport().set_input_as_handled()
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and event is InputEventJoypadButton and event.pressed:
		if get_viewport().gui_get_focus_owner() == null:
			_focus_first()
			# Initial A focuses; the next A deliberately activates that control.
			if event.button_index == JOY_BUTTON_A: get_viewport().set_input_as_handled()

func _focus_first() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		for child in get_tree().root.get_children():
			if child.name == "Lagunak": scene = child
	if scene == null: return
	for control in scene.find_children("*", "Control", true, false):
		if control.is_visible_in_tree() and control.focus_mode == Control.FOCUS_ALL and not (control is BaseButton and control.disabled):
			control.grab_focus()
			return

func _joy_connection_changed(_device: int, connected: bool) -> void:
	if not connected:
		for action in Profile.ACTIONS: Input.action_release(action)
		# A disconnected controller must never strand a captured pointer.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func gameplay_blocked() -> bool:
	if is_settings_open(): return true
	var focus = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return true
	if get_viewport().get_embedded_subwindows().any(func(window): return window.visible and window.exclusive): return true
	return false

func movement_vector() -> Vector2:
	if gameplay_blocked(): return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back", float(profile.deadzone))

func look_vector() -> Vector2:
	if gameplay_blocked(): return Vector2.ZERO
	var value = Input.get_vector("look_left", "look_right", "look_up", "look_down", float(profile.deadzone)) * float(profile.gamepad_sensitivity) * 2.2
	if profile.invert_y: value.y = -value.y
	return value

func mouse_look(relative: Vector2) -> Vector2:
	if gameplay_blocked(): return Vector2.ZERO
	var value = relative * 0.0022 * float(profile.mouse_sensitivity)
	if profile.invert_y: value.y = -value.y
	return value

func action_pressed(action: String) -> bool:
	return not gameplay_blocked() and InputMap.has_action(action) and Input.is_action_pressed(action)

func binding_label(action: String, device: String = "") -> String:
	if not profile.bindings.has(action): return ""
	var entry: Dictionary = profile.bindings[action]
	if (last_device if device.is_empty() else device) == "gamepad":
		if entry.pad.kind == "button":
			var names = {JOY_BUTTON_A: "A / Cross", JOY_BUTTON_B: "B / Circle", JOY_BUTTON_X: "X / Square", JOY_BUTTON_Y: "Y / Triangle", JOY_BUTTON_BACK: "Back / Select", JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_LEFT_SHOULDER: "LB / L1", JOY_BUTTON_RIGHT_SHOULDER: "RB / R1"}
			return names.get(int(entry.pad.code), tr("Botón %d") % (int(entry.pad.code) + 1))
		var names = ["LX", "LY", "RX", "RY", "LT", "RT"]
		return names[int(entry.pad.code)] + ("−" if int(entry.pad.direction) < 0 else "+")
	return OS.get_keycode_string(int(entry.key))

func is_settings_open() -> bool:
	return is_instance_valid(panel) and panel.is_visible_in_tree()

func open_settings() -> void:
	if is_settings_open(): return
	if _layer == null: _create_launcher()
	var focus = get_viewport().gui_get_focus_owner()
	_focus_before = weakref(focus) if focus != null else null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for action in Profile.ACTIONS: Input.action_release(action)
	panel = SettingsPanel.new()
	panel.controls = self
	_layer.add_child(panel)
	panel.closed.connect(close_settings)

func close_settings() -> void:
	if panel != null:
		panel.queue_free()
		panel = null
	# Stay released: the player deliberately resumes using C / Start or a click.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var old_focus = _focus_before.get_ref() if _focus_before != null else null
	if is_instance_valid(old_focus) and old_focus.is_visible_in_tree(): old_focus.grab_focus()

func commit_profile(candidate: Dictionary) -> String:
	var error = Profile.validate(candidate)
	if not error.is_empty(): return error
	if Profile.save_file(profile_path, candidate) != OK: return "No se pudieron guardar los controles."
	profile = Profile.normalize(candidate)
	Profile.install(profile)
	TranslationServer.set_locale(profile.locale)
	profile_changed.emit()
	return ""

func rebind(action: String, device: String, value: Variant) -> String:
	if action not in Profile.ACTIONS or device not in ["keyboard", "gamepad"]: return "Asignación no válida."
	var candidate = profile.duplicate(true)
	candidate.bindings[action]["key" if device == "keyboard" else "pad"] = value
	return commit_profile(candidate)
