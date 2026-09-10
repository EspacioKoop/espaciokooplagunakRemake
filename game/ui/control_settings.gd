extends Control
signal closed
const Profile = preload("res://input/control_profile.gd")
var controls: Node
var status: Label
var close_button: Button
var binding_buttons = {}
var waiting_action = ""
var waiting_device = ""
var _capture_clock = 0.0
var _capture_guard = 0.0
var _scroll: ScrollContainer
var _locale: OptionButton
var _mouse: HSlider
var _pad: HSlider
var _deadzone: HSlider
var _invert: CheckBox
var _value_labels = {}

func _ready() -> void:
	name = "ControlSettings"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = ConsoleUI.make_theme()
	var shade = ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.96)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column = ConsoleUI.column(margin, 10)
	var heading = ConsoleUI.row(column)
	heading.add_child(ConsoleUI.label("Teclado y mando", 28))
	var space = Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(space)
	close_button = ConsoleUI.button("Volver", func(): closed.emit())
	heading.add_child(close_button)
	column.add_child(ConsoleUI.paragraph("Controlar personaje activa la cámara. Liberar ratón vuelve a menús. F9 siempre recupera este panel.", 16))
	column.add_child(ConsoleUI.paragraph("Menús: cruceta y A; LB / RB cambia el foco. Los atajos de otras pantallas conservan sus teclas.", 16))
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	column.add_child(_scroll)
	var body = ConsoleUI.column(_scroll, 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var options = GridContainer.new()
	options.columns = 2
	options.add_theme_constant_override("h_separation", 20)
	options.add_theme_constant_override("v_separation", 8)
	body.add_child(options)
	options.add_child(ConsoleUI.label("Pantalla táctil", 17))
	var touch_toggle = CheckBox.new()
	touch_toggle.name = "TouchControlsToggle"
	touch_toggle.text = "Mostrar controles táctiles (esta sesión)"
	touch_toggle.button_pressed = controls.touch != null and controls.touch.enabled
	touch_toggle.toggled.connect(func(value): controls.touch.set_enabled(value))
	options.add_child(touch_toggle)
	options.add_child(ConsoleUI.label("Idioma de controles", 17))
	_locale = OptionButton.new()
	_locale.add_item("Español")
	_locale.add_item("English")
	_locale.select(0 if controls.profile.locale == "es" else 1)
	_locale.item_selected.connect(func(index): _set_option("locale", "es" if index == 0 else "en"))
	options.add_child(_locale)
	_mouse = _slider(options, "Sensibilidad del ratón", 0.2, 3.0, 0.1, controls.profile.mouse_sensitivity, "mouse_sensitivity")
	_pad = _slider(options, "Sensibilidad del mando", 0.2, 3.0, 0.1, controls.profile.gamepad_sensitivity, "gamepad_sensitivity")
	_deadzone = _slider(options, "Zona muerta", 0.05, 0.6, 0.05, controls.profile.deadzone, "deadzone")
	options.add_child(ConsoleUI.label("Mirada vertical", 17))
	_invert = CheckBox.new()
	_invert.text = "Invertir eje Y"
	_invert.button_pressed = controls.profile.invert_y
	_invert.toggled.connect(func(value): _set_option("invert_y", value))
	options.add_child(_invert)
	body.add_child(ConsoleUI.paragraph("Cada cambio se guarda al instante. Para intercambiar dos controles, asigna primero uno libre.", 16))
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 5)
	body.add_child(grid)
	for title in ["Acción", "Teclado", "Mando"]: grid.add_child(ConsoleUI.label(title, 18, ConsoleUI.TEAL))
	for action in Profile.ACTIONS:
		grid.add_child(ConsoleUI.label(Profile.LABELS[action], 16))
		for device in ["keyboard", "gamepad"]:
			var button = ConsoleUI.button(controls.binding_label(action, device), _begin_capture.bind(action, device))
			button.name = action + "_" + device
			button.custom_minimum_size = Vector2(175, 38)
			button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			grid.add_child(button)
			binding_buttons[action + ":" + device] = button
	status = ConsoleUI.paragraph(controls.load_error if not controls.load_error.is_empty() else "Perfil de controles listo.", 16, ConsoleUI.AMBER)
	status.custom_minimum_size.y = 44
	column.add_child(status)
	var footer = ConsoleUI.row(column)
	footer.add_child(ConsoleUI.button("Restaurar controles", _reset))
	footer.add_child(ConsoleUI.button("Cancelar asignación", _cancel_capture))
	footer.add_child(ConsoleUI.paragraph("Cámara y controles del personaje. La traducción de campaña y otras pantallas sigue pendiente.", 15))
	close_button.call_deferred("grab_focus")

func _slider(parent: Node, title: String, low: float, high: float, step_value: float, value: float, field: String) -> HSlider:
	parent.add_child(ConsoleUI.label(title, 17))
	var row = HBoxContainer.new()
	parent.add_child(row)
	var slider = HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step_value
	slider.value = value
	slider.custom_minimum_size.x = 180
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var number = ConsoleUI.label("%.2f" % value, 16)
	number.custom_minimum_size.x = 50
	_value_labels[field] = number
	row.add_child(number)
	slider.value_changed.connect(func(next):
		number.text = "%.2f" % next
		_set_option(field, next))
	return slider

func _set_option(field: String, value: Variant) -> void:
	var candidate: Dictionary = controls.profile.duplicate(true)
	candidate[field] = value
	var error: String = controls.commit_profile(candidate)
	status.text = "Controles guardados." if error.is_empty() else error
	if not error.is_empty(): _sync_options()

func _sync_options() -> void:
	_locale.select(0 if controls.profile.locale == "es" else 1)
	_mouse.set_value_no_signal(controls.profile.mouse_sensitivity)
	_pad.set_value_no_signal(controls.profile.gamepad_sensitivity)
	_deadzone.set_value_no_signal(controls.profile.deadzone)
	_invert.set_pressed_no_signal(controls.profile.invert_y)
	for field in _value_labels: _value_labels[field].text = "%.2f" % float(controls.profile[field])

func _reset() -> void:
	_cancel_capture()
	var error: String = controls.commit_profile(Profile.defaults())
	status.text = "Controles restaurados." if error.is_empty() else error
	if error.is_empty():
		_sync_options()
		_update_bindings()

func _begin_capture(action: String, device: String) -> void:
	waiting_action = action
	waiting_device = device
	_capture_clock = 10.0
	_capture_guard = 0.15
	status.text = "Pulsa una tecla o entrada de mando. Escape cancela; espera 10 s para salir."

func _cancel_capture() -> void:
	waiting_action = ""
	waiting_device = ""
	if status != null: status.text = "Asignación cancelada."

func _process(delta: float) -> void:
	_capture_guard = maxf(0, _capture_guard - delta)
	if not waiting_action.is_empty():
		_capture_clock -= delta
		if _capture_clock <= 0: _cancel_capture()

func capture_event(event: InputEvent) -> bool:
	if not waiting_action.is_empty():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_capture()
			return true
		if _capture_guard > 0: return not event is InputEventMouseMotion
		var value: Variant = null
		if waiting_device == "keyboard" and event is InputEventKey and event.pressed and not event.echo:
			value = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		elif waiting_device == "gamepad" and event is InputEventJoypadButton and event.pressed:
			value = Profile.button(event.button_index)
		elif waiting_device == "gamepad" and event is InputEventJoypadMotion and absf(event.axis_value) >= 0.7:
			value = Profile.axis(event.axis, -1 if event.axis_value < 0 else 1)
		if value != null:
			var error: String = controls.rebind(waiting_action, waiting_device, value)
			if error.is_empty():
				_cancel_capture()
				_update_bindings()
				status.text = "Controles guardados."
			else: status.text = error
		# Mouse remains available for the cancel/close buttons.
		return event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion
	if event.is_action_pressed("release_pointer") or event.is_action_pressed("controls_settings") or (event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_F9]):
		closed.emit()
		return true
	# Suppress legacy function-key shortcuts while this modal is open.
	return event is InputEventKey and event.keycode >= KEY_F1 and event.keycode <= KEY_F12

func _update_bindings() -> void:
	for action in Profile.ACTIONS:
		for device in ["keyboard", "gamepad"]:
			binding_buttons[action + ":" + device].text = controls.binding_label(action, device)
