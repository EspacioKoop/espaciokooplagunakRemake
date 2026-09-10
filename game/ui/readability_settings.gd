extends Window
## Embedded modal: focus stays here; all content remains reachable by scrolling.
const Profile = preload("res://input/readability_profile.gd")
var service: Node
var status: Label
var preview: Label
var close_button: Button
var reset_button: Button
var scale_buttons: Dictionary = {}
var scroll: ScrollContainer

func _ready() -> void:
	name = "ReadabilitySettings"
	title = "Legibilidad · Tamaño del texto"
	transient = true
	exclusive = true
	min_size = Vector2i(360, 260)
	wrap_controls = false
	theme = ConsoleUI.make_theme()
	close_requested.connect(_close)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	scroll = ScrollContainer.new()
	scroll.name = "ReadabilityScroll"
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	margin.add_child(scroll)
	var body = ConsoleUI.column(scroll, 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(ConsoleUI.paragraph("Tamaño del texto", 24))
	body.add_child(ConsoleUI.paragraph("Se aplica a los textos 2D compatibles y se guarda sólo en este equipo. No cambia la cámara ni los modelos 3D.", 16))
	var group = ButtonGroup.new()
	for percent in Profile.PERCENTAGES:
		var button = ConsoleUI.button("%d %%" % percent, _choose.bind(percent))
		button.name = "TextScale%d" % percent
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = int(service.profile.text_percent) == percent
		button.tooltip_text = "Tamaño del texto: %d %% del original" % percent
		body.add_child(button)
		scale_buttons[percent] = button
	preview = ConsoleUI.paragraph("Vista previa: La tripulación de la Itsaso prepara la próxima guardia. Navegación, ingeniería y comunicaciones comparten un mismo destino.", 18)
	preview.name = "ReadabilityPreview"
	body.add_child(preview)
	status = ConsoleUI.paragraph(service.load_error if not service.load_error.is_empty() else "Ajuste local listo.", 16, ConsoleUI.AMBER)
	body.add_child(status)
	reset_button = ConsoleUI.button("Restaurar tamaño original · 100 %", _choose.bind(100))
	reset_button.name = "ReadabilityReset"
	body.add_child(reset_button)
	close_button = ConsoleUI.button("Volver a controles", _close)
	close_button.name = "ReadabilityClose"
	body.add_child(close_button)
	var focusable: Array = scale_buttons.values() + [reset_button, close_button]
	for index in focusable.size():
		var control: Control = focusable[index]
		control.focus_next = control.get_path_to(focusable[(index + 1) % focusable.size()])
		control.focus_previous = control.get_path_to(focusable[(index + focusable.size() - 1) % focusable.size()])
		control.focus_neighbor_bottom = control.focus_next
		control.focus_neighbor_top = control.focus_previous
	scale_buttons[int(service.profile.text_percent)].call_deferred("grab_focus")

func _choose(percent: int) -> void:
	var error: String = service.commit_text_percent(percent)
	status.text = "Tamaño guardado: %d %%." % percent if error.is_empty() else error
	for value in scale_buttons:
		scale_buttons[value].set_pressed_no_signal(value == int(service.profile.text_percent))

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_F9]):
		set_input_as_handled()
		_close()
	elif event is InputEventKey and event.keycode >= KEY_F1 and event.keycode <= KEY_F12:
		set_input_as_handled()

func _close() -> void:
	hide()
	queue_free()
