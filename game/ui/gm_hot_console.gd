class_name GMHotConsole
extends Window

var simulation: Simulation
var notice: Label
var contact_id: LineEdit
var contact_name: LineEdit
var contact_kind: OptionButton
var pos_x: SpinBox
var pos_y: SpinBox
var event_kind: OptionButton
var event_value: LineEdit

func setup(sim: Simulation) -> void:
	simulation = sim

func _ready() -> void:
	title = "Dirección en vivo"
	size = Vector2i(760, 560)
	transient = true
	exclusive = true
	close_requested.connect(queue_free)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	add_child(margin)
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var heading = Label.new()
	heading.text = "CONSOLA CALIENTE DEL GM"
	heading.add_theme_font_size_override("font_size", 24)
	root.add_child(heading)
	var explanation = Label.new()
	explanation.text = "Crea y altera contactos de la misión viva o dispara eventos de escena. Todas las acciones pasan por validación y quedan en la bitácora."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(explanation)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	root.add_child(grid)
	contact_id = _field(grid, "ID contacto")
	contact_name = _field(grid, "Nombre")
	var kind_label = Label.new(); kind_label.text = "Tipo"; grid.add_child(kind_label)
	contact_kind = OptionButton.new()
	for kind in GMLiveActions.KINDS: contact_kind.add_item(kind)
	grid.add_child(contact_kind)
	var x_label = Label.new(); x_label.text = "X"; grid.add_child(x_label)
	pos_x = SpinBox.new(); pos_x.min_value = -100000; pos_x.max_value = 100000; pos_x.step = 10; grid.add_child(pos_x)
	var y_label = Label.new(); y_label.text = "Y"; grid.add_child(y_label)
	pos_y = SpinBox.new(); pos_y.min_value = -100000; pos_y.max_value = 100000; pos_y.step = 10; grid.add_child(pos_y)

	var contact_buttons = HBoxContainer.new()
	root.add_child(contact_buttons)
	contact_buttons.add_child(_button("Crear contacto", _spawn))
	contact_buttons.add_child(_button("Mover/renombrar", _modify))
	contact_buttons.add_child(_button("Retirar", _remove))

	root.add_child(HSeparator.new())
	var event_row = HBoxContainer.new()
	event_row.add_theme_constant_override("separation", 10)
	root.add_child(event_row)
	event_kind = OptionButton.new()
	for event in GMLiveActions.EVENTS: event_kind.add_item(event)
	event_row.add_child(event_kind)
	event_value = LineEdit.new()
	event_value.placeholder_text = "valor: roja / mensaje / cantidad"
	event_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_row.add_child(event_value)
	event_row.add_child(_button("Ejecutar evento", _trigger_event))

	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(notice)

func _field(parent: GridContainer, label_text: String) -> LineEdit:
	var label = Label.new()
	label.text = label_text
	parent.add_child(label)
	var field = LineEdit.new()
	parent.add_child(field)
	return field

func _button(text: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button

func _show(result: Dictionary) -> void:
	notice.text = ("✓ " if result.get("ok", false) else "✕ ") + str(result.get("message", ""))

func _spawn() -> void:
	if simulation == null: return
	_show(GMLiveActions.spawn_contact(simulation, {
		"id": contact_id.text,
		"name": contact_name.text,
		"kind": contact_kind.get_item_text(contact_kind.selected),
		"x": pos_x.value,
		"y": pos_y.value,
		"identified": true
	}))

func _modify() -> void:
	if simulation == null: return
	_show(GMLiveActions.modify_contact(simulation, contact_id.text.strip_edges(), {
		"name": contact_name.text,
		"x": pos_x.value,
		"y": pos_y.value
	}))

func _remove() -> void:
	if simulation == null: return
	_show(GMLiveActions.remove_contact(simulation, contact_id.text.strip_edges()))

func _trigger_event() -> void:
	if simulation == null: return
	var event = event_kind.get_item_text(event_kind.selected)
	var value = event_value.text.strip_edges()
	var args: Dictionary = {}
	match event:
		"alert": args.level = value
		"message": args.text = value
		"damage", "repair": args.amount = value.to_float()
		"reinforcements": args.count = maxi(1, value.to_int())
	_show(GMLiveActions.trigger_event(simulation, event, args))
