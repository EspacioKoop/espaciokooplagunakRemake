class_name GMHotConsole
extends Window
## Host-local, run-bound editor. A client receives neither this view nor its audit.
const TriggerSystem = preload("res://core/interior_triggers.gd")
var session: Node
var run_id = ""
var notice: Label
var listing: ItemList
var contact_id: LineEdit
var contact_name: LineEdit
var contact_kind: OptionButton
var pos_x: SpinBox
var pos_y: SpinBox
var hull: SpinBox
var survivors: SpinBox
var frequency: SpinBox
var identified: CheckButton
var jammed: CheckButton
var pacified: CheckButton
var visual: OptionButton
var event_kind: OptionButton
var event_value: LineEdit
var trigger_listing: ItemList
var trigger_id: LineEdit
var trigger_zone: OptionButton
var trigger_event_type: OptionButton
var trigger_action: OptionButton
var trigger_value: LineEdit
var trigger_target: LineEdit
var trigger_one_shot: CheckButton
var audit: Label
var _selected_id = ""
var _selected_trigger_id = ""
var _initial_values: Dictionary = {}
var _ids: Array = []
var _trigger_ids: Array = []
var _confirmation: ConfirmationDialog
var _pending: Callable

func setup(authority: Node) -> void:
	session = authority
	run_id = str(session.sim.state.get("run_id", "")) if GMLiveActions.can_direct(session) else ""

func _ready() -> void:
	title = "Dirección en vivo · autoridad local"
	size = Vector2i(1060, 740)
	min_size = Vector2i(720, 480)
	transient = true
	exclusive = true
	theme = ConsoleUI.make_theme()
	close_requested.connect(queue_free)
	if not _authorized():
		queue_free()
		return
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 20)
	add_child(margin)
	var body = ConsoleUI.column(margin, 12)
	body.add_child(ConsoleUI.label("DIRECCIÓN EN VIVO", 26, ConsoleUI.TEAL))
	body.add_child(ConsoleUI.paragraph("Sólo el anfitrión. Cambios reales en la misión activa; se conservan al guardar. Los objetivos y la fuente de la campaña quedan protegidos.", 15))
	var split = HSplitContainer.new()
	ConsoleUI.expand(split)
	body.add_child(split)
	var left = ConsoleUI.column(split, 8)
	left.custom_minimum_size.x = 270
	listing = ItemList.new()
	listing.name = "GMContacts"
	ConsoleUI.expand(listing)
	left.add_child(listing)
	listing.item_selected.connect(_select)
	left.add_child(ConsoleUI.button("Actualizar contactos", _refresh_list))
	left.add_child(ConsoleUI.button("Nuevo contacto", _new_contact))
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	var form = ConsoleUI.column(scroll, 10)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 7)
	form.add_child(grid)
	contact_id = _field(grid, "Identificador")
	contact_id.name = "GMContactID"
	contact_name = _field(grid, "Nombre")
	contact_kind = OptionButton.new()
	for kind in GMLiveActions.KINDS:
		contact_kind.add_item(Catalog.CONTACT_NAMES[Catalog.CONTACT_KINDS.find(kind)])
		contact_kind.set_item_metadata(contact_kind.item_count - 1, kind)
	_row(grid, "Tipo", contact_kind)
	contact_kind.item_selected.connect(func(_index): _models(""))
	pos_x = _number(grid, "Posición X", -14000, 14000, 1)
	pos_y = _number(grid, "Posición Y", -14000, 14000, 1)
	hull = _number(grid, "Integridad", 0, 1000, 1)
	survivors = _number(grid, "Supervivientes", 0, 500, 1)
	frequency = _number(grid, "Frecuencia", 0, 20, 1)
	identified = _flag(grid, "Identificado")
	jammed = _flag(grid, "Interferencia")
	pacified = _flag(grid, "Pacificado")
	visual = OptionButton.new()
	visual.name = "GMVisualModel"
	visual.custom_minimum_size.x = 340
	_row(grid, "Modelo visual", visual)
	form.add_child(ConsoleUI.paragraph("El modelo sólo cambia la representación espacial. No concede armas, inventario, físicas o interiores del recurso.", 14))
	var buttons = ConsoleUI.row(form, 8)
	var create = ConsoleUI.button("Crear", _spawn)
	create.name = "GMSpawn"
	buttons.add_child(create)
	var modify = ConsoleUI.button("Aplicar cambios", _modify)
	modify.name = "GMModify"
	buttons.add_child(modify)
	var remove = ConsoleUI.button("Retirar", _request_remove)
	remove.name = "GMRemove"
	buttons.add_child(remove)
	form.add_child(HSeparator.new())
	var event_row = ConsoleUI.row(form, 8)
	event_kind = OptionButton.new()
	for label in ["Alerta", "Mensaje público", "Daño de casco", "Reparación", "Refuerzos"]:
		event_kind.add_item(label)
	event_row.add_child(event_kind)
	event_value = LineEdit.new()
	event_value.placeholder_text = "verde / ambar / roja"
	event_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_row.add_child(event_value)
	event_kind.item_selected.connect(func(index):
		event_value.placeholder_text = ["verde / ambar / roja", "Texto público · hasta 240 caracteres", "Cantidad: 0,001–1000", "Cantidad: 0,001–1000", "Cantidad entera: 1–12"][index])
	event_row.add_child(ConsoleUI.button("Ejecutar", _trigger_event))
	form.add_child(HSeparator.new())
	form.add_child(ConsoleUI.label("TRIGGERS DE INTERIOR · HOST", 18, ConsoleUI.TEAL))
	trigger_listing = ItemList.new()
	trigger_listing.name = "GMInteriorTriggers"
	trigger_listing.custom_minimum_size.y = 120
	trigger_listing.item_selected.connect(_select_trigger)
	form.add_child(trigger_listing)
	var trigger_grid = GridContainer.new()
	trigger_grid.columns = 2
	trigger_grid.add_theme_constant_override("h_separation", 14)
	trigger_grid.add_theme_constant_override("v_separation", 7)
	form.add_child(trigger_grid)
	trigger_id = _field(trigger_grid, "Identificador")
	trigger_id.name = "GMTriggerID"
	trigger_zone = OptionButton.new()
	trigger_zone.add_item("Cualquier zona")
	trigger_zone.set_item_metadata(0, -1)
	for zone_index in WorldDeck.ZONES.size():
		trigger_zone.add_item(WorldDeck.ZONES[zone_index].name)
		trigger_zone.set_item_metadata(trigger_zone.item_count - 1, zone_index)
	_row(trigger_grid, "Zona", trigger_zone)
	trigger_event_type = OptionButton.new()
	for event_type in TriggerSystem.TRIGGER_EVENTS: trigger_event_type.add_item(event_type)
	_row(trigger_grid, "Evento", trigger_event_type)
	trigger_action = OptionButton.new()
	var trigger_actions = ["alert", "message", "damage", "repair", "reinforcements", "fact", "custom"]
	var trigger_action_labels = ["Alerta", "Mensaje público", "Daño", "Reparación", "Refuerzos", "Registrar hecho", "Personalizado"]
	for index in trigger_actions.size():
		trigger_action.add_item(trigger_action_labels[index])
		trigger_action.set_item_metadata(index, trigger_actions[index])
	_row(trigger_grid, "Consecuencia", trigger_action)
	trigger_value = _field(trigger_grid, "Valor")
	trigger_value.name = "GMTriggerValue"
	trigger_target = _field(trigger_grid, "Interacción (opcional)")
	trigger_target.name = "GMTriggerTarget"
	trigger_one_shot = CheckButton.new()
	trigger_one_shot.text = "Sólo una vez por partida"
	trigger_one_shot.button_pressed = true
	_row(trigger_grid, "Repetición", trigger_one_shot)
	var trigger_buttons = ConsoleUI.row(form, 8)
	trigger_buttons.add_child(ConsoleUI.button("Nuevo trigger", _new_trigger))
	trigger_buttons.add_child(ConsoleUI.button("Crear / aplicar", _save_trigger))
	trigger_buttons.add_child(ConsoleUI.button("Retirar trigger", _remove_trigger))
	form.add_child(ConsoleUI.paragraph("Los triggers se validan en el anfitrión, se guardan con la partida y disparan al entrar, salir, interactuar o sentarse. Un cliente nunca ejecuta ni ve la auditoría privada.", 14))
	audit = ConsoleUI.paragraph("", 13, ConsoleUI.MUTED)
	audit.name = "GMAudit"
	form.add_child(audit)
	notice = ConsoleUI.paragraph("", 15, ConsoleUI.AMBER)
	notice.name = "GMNotice"
	body.add_child(notice)
	var footer = ConsoleUI.row(body, 8)
	footer.add_child(ConsoleUI.button("Guardar partida", _save))
	footer.add_child(ConsoleUI.button("Cerrar", queue_free))
	_confirmation = ConfirmationDialog.new()
	_confirmation.title = "Confirmar cambio en la misión"
	_confirmation.ok_button_text = "Aplicar cambio"
	_confirmation.cancel_button_text = "Cancelar"
	_confirmation.confirmed.connect(func():
		if _pending.is_valid() and _authorized(): _pending.call()
		_pending = Callable())
	_confirmation.canceled.connect(func(): _pending = Callable())
	add_child(_confirmation)
	_refresh_list()
	_new_contact()

func _authorized() -> bool:
	return GMLiveActions.can_direct(session) and not run_id.is_empty() and session.sim.state.get("run_id", "") == run_id

func _process(_delta: float) -> void:
	if not _authorized(): queue_free()

func _row(grid: GridContainer, title_text: String, control: Control) -> void:
	grid.add_child(ConsoleUI.label(title_text, 15, ConsoleUI.MUTED))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)

func _field(grid: GridContainer, label_text: String) -> LineEdit:
	var field = LineEdit.new()
	field.max_length = 80
	_row(grid, label_text, field)
	return field

func _number(grid: GridContainer, label_text: String, low: float, high: float, step_value: float) -> SpinBox:
	var field = SpinBox.new()
	field.min_value = low
	field.max_value = high
	field.step = step_value
	_row(grid, label_text, field)
	return field

func _flag(grid: GridContainer, label_text: String) -> CheckButton:
	var field = CheckButton.new()
	_row(grid, label_text, field)
	return field

func _models(selected: String) -> void:
	if not is_instance_valid(visual): return
	visual.clear()
	visual.add_item("Modelo predeterminado")
	visual.set_item_metadata(0, "")
	var kind = str(contact_kind.get_selected_metadata())
	for row in RuntimeAssetLibrary.entries():
		if kind not in row.contact_kinds: continue
		visual.add_item(row.title)
		var index = visual.item_count - 1
		visual.set_item_metadata(index, row.id)
		if row.id == selected: visual.select(index)

func _new_contact() -> void:
	_selected_id = ""
	listing.deselect_all()
	contact_id.editable = true
	var serial = int(session.sim.state.sequence)
	var proposed = "gm_%d" % serial
	while proposed in GMLiveState.all_ids(session.sim.state):
		serial += 1
		proposed = "gm_%d" % serial
	contact_id.text = proposed
	contact_name.text = "Contacto de escena"
	contact_kind.select(GMLiveActions.KINDS.find("friendly"))
	pos_x.value = clampf(session.sim.state.ship.position[0] + 1000, -14000, 14000)
	pos_y.value = session.sim.state.ship.position[1]
	hull.value = 100
	survivors.value = 0
	frequency.value = 0
	identified.button_pressed = false
	jammed.button_pressed = false
	pacified.button_pressed = false
	_models("")
	contact_name.grab_focus()

func _select(index: int) -> void:
	if not _authorized() or index < 0 or index >= _ids.size(): return
	var contact = session.sim.contact(_ids[index])
	if contact.is_empty(): _refresh_list(); return
	_selected_id = contact.id
	contact_id.text = contact.id
	contact_id.editable = false
	contact_name.text = contact.name
	contact_kind.select(maxi(0, GMLiveActions.KINDS.find(contact.kind)))
	pos_x.value = contact.position[0]
	pos_y.value = contact.position[1]
	hull.value = contact.hull
	survivors.value = contact.survivors
	frequency.value = contact.get("frequency", 0)
	identified.button_pressed = contact.identified
	jammed.button_pressed = contact.jammed
	pacified.button_pressed = contact.pacified
	_models(str(contact.get("visual_model", "")))
	_initial_values = _values()
	_initial_values.jammed = jammed.button_pressed
	_initial_values.pacified = pacified.button_pressed

func _refresh_list() -> void:
	if not _authorized(): return
	_ids.clear()
	listing.clear()
	for contact in session.sim.state.contacts:
		_ids.append(contact.id)
		listing.add_item(("%s · " % contact.id) + contact.name + (" [objetivo]" if GMLiveState.protected_target(session.sim.state, contact.id) else ""))
		if contact.id == _selected_id: listing.select(listing.item_count - 1)
	var lines: PackedStringArray = ["Registro local de dirección (no se envía a la tripulación):"]
	for item in session.sim.state.get("gm_live", {}).get("audit", []).slice(-6):
		lines.append("#%d · %s · %s" % [item.seq, item.operation, item.target])
	audit.text = "\n".join(lines)
	_refresh_triggers()

func _refresh_triggers() -> void:
	if trigger_listing == null or not _authorized(): return
	_trigger_ids.clear()
	trigger_listing.clear()
	for trigger in TriggerSystem.list_triggers(session.sim):
		_trigger_ids.append(str(trigger.id))
		var zone_name = "Cualquier zona" if int(trigger.zone) < 0 else WorldDeck.ZONES[int(trigger.zone)].name
		trigger_listing.add_item("%s · %s · %s%s" % [trigger.id, zone_name, trigger.event_type, " ✓" if trigger.fired else ""])
		if trigger.id == _selected_trigger_id: trigger_listing.select(trigger_listing.item_count - 1)

func _new_trigger() -> void:
	_selected_trigger_id = ""
	if trigger_listing != null: trigger_listing.deselect_all()
	if trigger_id == null: return
	var serial := int(session.sim.state.sequence)
	var proposed := "interior_%d" % serial
	while TriggerSystem.list_triggers(session.sim).any(func(item): return str(item.get("id", "")) == proposed):
		serial += 1
		proposed = "interior_%d" % serial
	trigger_id.text = proposed
	trigger_zone.select(0)
	trigger_event_type.select(0)
	trigger_action.select(0)
	trigger_value.text = ""
	trigger_target.text = ""
	trigger_one_shot.button_pressed = true

func _select_trigger(index: int) -> void:
	if index < 0 or index >= _trigger_ids.size() or not _authorized(): return
	var wanted = _trigger_ids[index]
	for trigger in TriggerSystem.list_triggers(session.sim):
		if str(trigger.get("id", "")) != wanted: continue
		_selected_trigger_id = wanted
		trigger_id.text = wanted
		for zone_index in trigger_zone.item_count:
			if int(trigger_zone.get_item_metadata(zone_index)) == int(trigger.zone): trigger_zone.select(zone_index)
		trigger_event_type.select(maxi(0, TriggerSystem.TRIGGER_EVENTS.find(str(trigger.event_type))))
		for action_index in trigger_action.item_count:
			if str(trigger_action.get_item_metadata(action_index)) == str(trigger.consequence.action): trigger_action.select(action_index)
		trigger_value.text = str(trigger.consequence.value)
		trigger_target.text = str(trigger.get("target_id", ""))
		trigger_one_shot.button_pressed = bool(trigger.one_shot)
		return

func _trigger_payload() -> Dictionary:
	var action = str(trigger_action.get_selected_metadata())
	var raw_value = trigger_value.text.strip_edges()
	var value: Variant = raw_value
	if action in ["damage", "repair"]: value = raw_value.to_float()
	elif action == "reinforcements": value = raw_value.to_int()
	var payload: Dictionary = {
		"id": trigger_id.text.strip_edges(),
		"zone": int(trigger_zone.get_selected_metadata()),
		"event_type": str(trigger_event_type.get_item_text(trigger_event_type.selected)),
		"consequence": {"action": action, "value": value},
		"one_shot": trigger_one_shot.button_pressed
	}
	if not trigger_target.text.strip_edges().is_empty(): payload.target_id = trigger_target.text.strip_edges()
	return payload

func _save_trigger() -> void:
	if not _authorized(): return
	var payload = _trigger_payload()
	var result: Dictionary
	if _selected_trigger_id.is_empty():
		result = GMLiveActions.dispatch(session, "add_interior_trigger", payload, run_id)
	else:
		var changes = payload.duplicate(true)
		changes.erase("id")
		result = GMLiveActions.dispatch(session, "modify_interior_trigger", {"id": _selected_trigger_id, "changes": changes}, run_id)
	notice.text = ("✓ " if result.ok else "✕ ") + result.message
	if result.ok: _selected_trigger_id = str(payload.id)
	_refresh_list()

func _remove_trigger() -> void:
	if _selected_trigger_id.is_empty(): return
	_dispatch("remove_interior_trigger", {"id": _selected_trigger_id})
	_selected_trigger_id = ""
	_new_trigger()

func _dispatch(operation: String, args: Dictionary) -> void:
	if not _authorized():
		queue_free()
		return
	var result = GMLiveActions.dispatch(session, operation, args, run_id)
	notice.text = ("✓ " if result.ok else "✕ ") + result.message
	_refresh_list()

func _values() -> Dictionary:
	# Commit any edited SpinBox text before reading its numeric value.
	for number in [pos_x, pos_y, hull, survivors, frequency]: number.apply()
	return {"name": contact_name.text, "kind": str(contact_kind.get_selected_metadata()),
		"x": pos_x.value, "y": pos_y.value, "hull": hull.value,
		"survivors": survivors.value, "frequency": frequency.value,
		"identified": identified.button_pressed, "jammed": jammed.button_pressed,
		"pacified": pacified.button_pressed, "visual_model": str(visual.get_selected_metadata())}

func _spawn() -> void:
	if not _selected_id.is_empty():
		notice.text = "Pulsa «Nuevo contacto» antes de crear otro."
		return
	var values = _values()
	values.id = contact_id.text
	_dispatch("spawn", values)

func _modify() -> void:
	if _selected_id.is_empty():
		notice.text = "Selecciona un contacto antes de aplicar cambios."
		return
	var values = _values()
	values.jammed = jammed.button_pressed
	values.pacified = pacified.button_pressed
	for key in values.keys():
		if values[key] == _initial_values.get(key): values.erase(key)
	_dispatch("modify", {"id": _selected_id, "changes": values})
	if not values.is_empty() and _authorized() and not session.sim.contact(_selected_id).is_empty():
		_select(_ids.find(_selected_id))

func _confirm(message: String, callback: Callable) -> void:
	_pending = callback
	_confirmation.dialog_text = message
	_confirmation.popup_centered_clamped(Vector2i(570, 170), 0.9)

func _request_remove() -> void:
	if _selected_id.is_empty(): return
	_confirm("¿Retirar este contacto de la misión? Los objetivos protegidos no se pueden retirar.", _dispatch.bind("remove", {"id": _selected_id}))

func _trigger_event() -> void:
	var event = GMLiveActions.EVENTS[event_kind.selected]
	var value = event_value.text.strip_edges()
	var args: Dictionary = {}
	match event:
		"alert": args.level = value
		"message": args.text = value
		"damage", "repair":
			if not value.is_valid_float(): notice.text = "Introduce una cantidad numérica válida (punto decimal)."; return
			args.amount = value.to_float()
		"reinforcements":
			if not value.is_valid_int(): notice.text = "Introduce un número entero."; return
			args.count = value.to_int()
	if event == "damage":
		_confirm("¿Aplicar daño de casco a la nave? Puede terminar la misión.", _dispatch.bind(event, args))
	else: _dispatch(event, args)

func _save() -> void:
	if not _authorized(): return
	var result = session.save_game()
	notice.text = ("✓ " if result.ok else "✕ ") + result.message

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()
	elif event is InputEventKey and event.keycode >= KEY_F1 and event.keycode <= KEY_F12:
		set_input_as_handled()
