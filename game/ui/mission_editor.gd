class_name MissionEditor
extends Control
signal play_requested(mission: Dictionary)

const KINDS = ["station", "friendly", "hostile", "derelict", "anomaly", "beacon"]
const KIND_NAMES = ["Estación", "Aliado", "Hostil", "Nave averiada", "Anomalía", "Baliza"]
const GOALS = ["navigate", "dock", "hail", "scan", "salvage", "rescue", "defeat", "repair_target", "choice", "probe"]
const GOAL_NAMES = ["Llegar", "Atracar", "Contactar", "Escanear", "Recuperar", "Rescatar", "Neutralizar", "Reparar estación", "Decidir", "Lanzar sonda"]
var mission: Dictionary = {}
var _undo: Array = []
var _selected = -1
var _selected_goal = -1
var _syncing = false
var _map: Radar
var _json: CodeEdit
var _contacts: ItemList
var _goals: ItemList
var _fields: Dictionary = {}
var _status: Label
var _kind: OptionButton
var _goal_kind: OptionButton
var _goal_target: OptionButton
var _dialog: FileDialog

func _ready() -> void:
	var root = ConsoleUI.column(self)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var toolbar = ConsoleUI.row(root)
	toolbar.add_child(ConsoleUI.label("Taller de misiones", 28))
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	toolbar.add_child(ConsoleUI.button("Nueva", _new_mission))
	toolbar.add_child(ConsoleUI.button("Abrir JSON", _open_dialog))
	toolbar.add_child(ConsoleUI.button("Deshacer", _undo_change))
	toolbar.add_child(ConsoleUI.button("Guardar", _save, true))
	toolbar.add_child(ConsoleUI.button("Probar misión", _play))
	var body = ConsoleUI.row(root, 16)
	ConsoleUI.expand(body)
	var left = _scroll_side(body, 290)
	left.add_child(ConsoleUI.label("DATOS DE LA MISIÓN", 13, ConsoleUI.MUTED))
	for field in [["id", "Identificador"], ["title", "Título"], ["sector", "Sector"]]:
		left.add_child(ConsoleUI.label(field[1], 14, ConsoleUI.MUTED))
		var edit = LineEdit.new()
		left.add_child(edit)
		_fields[field[0]] = edit
		edit.text_submitted.connect(_set_text.bind(field[0]))
		edit.focus_exited.connect(func(): _set_text(edit.text, field[0]))
	left.add_child(ConsoleUI.label("Briefing", 14, ConsoleUI.MUTED))
	var briefing = TextEdit.new()
	briefing.custom_minimum_size.y = 105
	briefing.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	left.add_child(briefing)
	_fields.briefing = briefing
	briefing.focus_exited.connect(func(): _set_text(briefing.text, "briefing"))
	var reward_row = ConsoleUI.row(left)
	reward_row.add_child(ConsoleUI.label("Recompensa", 14))
	var reward = SpinBox.new()
	reward.max_value = 10000
	reward.step = 10
	reward_row.add_child(reward)
	_fields.reward = reward
	reward.value_changed.connect(func(value):
		if not _syncing:
			_checkpoint()
			mission.reward = int(value)
			_validate())
	left.add_child(ConsoleUI.label("CONTACTOS DEL SECTOR", 13, ConsoleUI.MUTED))
	_contacts = ItemList.new()
	_contacts.custom_minimum_size.y = 175
	left.add_child(_contacts)
	_contacts.item_selected.connect(func(index): _selected = index; _refresh())
	_kind = OptionButton.new()
	for name in KIND_NAMES: _kind.add_item(name)
	left.add_child(_kind)
	left.add_child(ConsoleUI.paragraph("Pulsa en un espacio libre del mapa para añadir el tipo elegido. Arrastra un contacto para moverlo.", 14))
	left.add_child(ConsoleUI.button("Eliminar contacto", _delete_contact))
	var center = ConsoleUI.column(body)
	ConsoleUI.expand(center)
	var modes = ConsoleUI.row(center)
	modes.add_child(ConsoleUI.button("Mapa", func(): _map.show(); _json.hide()))
	modes.add_child(ConsoleUI.button("JSON", func(): _json.text = JSON.stringify(mission, "  "); _json.show(); _map.hide()))
	modes.add_child(ConsoleUI.button("Aplicar JSON", _apply_json))
	_map = Radar.new()
	_map.editable = true
	_map.show_labels = true
	_map.range_m = 2200
	ConsoleUI.expand(_map)
	center.add_child(_map)
	_map.empty_clicked.connect(_add_contact)
	_map.contact_selected.connect(func(id):
		for i in mission.contacts.size():
			if mission.contacts[i].id == id: _selected = i
		_refresh())
	_map.contact_moved.connect(_move_contact)
	_json = CodeEdit.new()
	_json.custom_minimum_size.x = 300
	ConsoleUI.expand(_json)
	center.add_child(_json)
	_json.hide()
	center.add_child(ConsoleUI.label("Rueda · Zoom    Origen · Posición inicial de la nave", 13, ConsoleUI.MUTED))
	var right = _scroll_side(body, 300)
	right.add_child(ConsoleUI.label("CONTACTO SELECCIONADO", 13, ConsoleUI.MUTED))
	var contact_name = LineEdit.new()
	contact_name.placeholder_text = "Nombre del contacto"
	right.add_child(contact_name)
	_fields.contact_name = contact_name
	contact_name.text_submitted.connect(_rename_contact)
	contact_name.focus_exited.connect(func(): _rename_contact(contact_name.text))
	for axis in ["x", "y"]:
		var row = ConsoleUI.row(right)
		row.add_child(ConsoleUI.label("Coordenada " + axis.to_upper(), 14, ConsoleUI.MUTED))
		var spin = SpinBox.new()
		spin.min_value = -12000
		spin.max_value = 12000
		spin.step = 25
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spin)
		_fields[axis] = spin
		spin.value_changed.connect(_coordinate.bind(0 if axis == "x" else 1))
	for flag in [["known", "Identificado al comenzar"], ["jammed", "Interferencia de comunicaciones"]]:
		var check = CheckBox.new()
		check.text = flag[1]
		check.add_theme_font_size_override("font_size", 14)
		right.add_child(check)
		_fields[flag[0]] = check
		check.toggled.connect(_flag.bind(flag[0]))
	right.add_child(ConsoleUI.label("OBJETIVOS EN ORDEN", 13, ConsoleUI.MUTED))
	_goals = ItemList.new()
	_goals.custom_minimum_size.y = 150
	right.add_child(_goals)
	_goals.item_selected.connect(func(index): _selected_goal = index; _refresh())
	var ordering = ConsoleUI.row(right, 6)
	ordering.add_child(ConsoleUI.button("Subir", func(): _reorder(-1)))
	ordering.add_child(ConsoleUI.button("Bajar", func(): _reorder(1)))
	ordering.add_child(ConsoleUI.button("Quitar", _delete_goal))
	var goal_text = LineEdit.new()
	goal_text.placeholder_text = "Texto del objetivo seleccionado"
	right.add_child(goal_text)
	_fields.goal_text = goal_text
	goal_text.text_submitted.connect(_goal_text)
	goal_text.focus_exited.connect(func(): _goal_text(goal_text.text))
	_goal_kind = OptionButton.new()
	for name in GOAL_NAMES: _goal_kind.add_item(name)
	right.add_child(_goal_kind)
	_goal_target = OptionButton.new()
	right.add_child(_goal_target)
	right.add_child(ConsoleUI.button("Añadir objetivo", _add_goal))
	right.add_child(ConsoleUI.paragraph("Alcances: llegar 250 m · atracar 190 m · analizar y contactar 900 m · rescatar, recuperar y reparar 300 m. Las decisiones requieren negociación.", 13))
	_status = ConsoleUI.paragraph("", 14)
	root.add_child(_status)
	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.filters = PackedStringArray(["*.json ; Misiones JSON"])
	_dialog.file_selected.connect(_load_file)
	add_child(_dialog)
	set_mission(Catalog.missions()[0] if mission.is_empty() else mission)

func _scroll_side(parent: Node, width: float) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.x = width
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var box = ConsoleUI.column(scroll, 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box

func set_mission(value: Dictionary) -> void:
	mission = value.duplicate(true)
	_selected = 0 if not mission.contacts.is_empty() else -1
	_selected_goal = 0 if not mission.objectives.is_empty() else -1
	if is_node_ready(): _refresh()

func _checkpoint() -> void:
	if _syncing: return
	_undo.append(mission.duplicate(true))
	if _undo.size() > 60: _undo.pop_front()

func _refresh() -> void:
	_syncing = true
	for key in ["id", "title", "sector", "briefing"]: _fields[key].text = mission[key]
	_fields.reward.set_value_no_signal(mission.get("reward", 100))
	_contacts.clear()
	_goal_target.clear()
	for c in mission.contacts:
		_contacts.add_item(c.name)
		_goal_target.add_item(c.name)
		_goal_target.set_item_metadata(_goal_target.item_count - 1, c.id)
	_selected = mini(_selected, mission.contacts.size() - 1)
	if _selected >= 0:
		_contacts.select(_selected)
		var c: Dictionary = mission.contacts[_selected]
		_fields.contact_name.text = c.name
		_fields.x.set_value_no_signal(c.position[0])
		_fields.y.set_value_no_signal(c.position[1])
		_fields.known.set_pressed_no_signal(c.get("known", false))
		_fields.jammed.set_pressed_no_signal(c.get("jammed", false))
		_map.selected = c.id
	else:
		_fields.contact_name.text = ""
		_map.selected = ""
	_goals.clear()
	for i in mission.objectives.size():
		var goal: Dictionary = mission.objectives[i]
		_goals.add_item("%02d · %s" % [i + 1, goal.text])
		_goals.set_item_tooltip(i, goal.text)
	_selected_goal = mini(_selected_goal, mission.objectives.size() - 1)
	if _selected_goal >= 0:
		_goals.select(_selected_goal)
		_fields.goal_text.text = mission.objectives[_selected_goal].text
	else: _fields.goal_text.text = ""
	_map.data = {"ship": {"position": [0, 0], "heading": 0}, "contacts": mission.contacts}
	_syncing = false
	_validate()

func _validate() -> bool:
	var issue = Catalog.validate_mission(mission)
	_status.text = "Misión válida · %d contactos · %d objetivos · Guardado local en la carpeta de misiones." % [mission.contacts.size(), mission.objectives.size()] if issue.is_empty() else issue
	_status.add_theme_color_override("font_color", ConsoleUI.TEAL if issue.is_empty() else ConsoleUI.AMBER)
	return issue.is_empty()

func _set_text(text: String, field: String) -> void:
	if _syncing or mission.get(field, "") == text: return
	_checkpoint()
	mission[field] = text.strip_edges()
	_validate()

func _rename_contact(text: String) -> void:
	if _syncing or _selected < 0 or mission.contacts[_selected].name == text: return
	_checkpoint()
	mission.contacts[_selected].name = text.left(80)
	_refresh()

func _coordinate(value: float, axis: int) -> void:
	if _syncing or _selected < 0: return
	_checkpoint()
	mission.contacts[_selected].position[axis] = value
	_refresh()

func _flag(value: bool, key: String) -> void:
	if _syncing or _selected < 0: return
	_checkpoint()
	mission.contacts[_selected][key] = value
	_validate()

func _add_contact(position: Vector2) -> void:
	if mission.contacts.size() >= 48: return
	_checkpoint()
	var id = "contact_" + str(Time.get_ticks_usec())
	mission.contacts.append({"id": id, "name": KIND_NAMES[_kind.selected] + " " + str(mission.contacts.size() + 1), "kind": KINDS[_kind.selected], "position": [snappedf(clampf(position.x, -12000, 12000), 25), snappedf(clampf(position.y, -12000, 12000), 25)], "known": false, "jammed": false})
	_selected = mission.contacts.size() - 1
	_refresh()

func _move_contact(id: String, position: Vector2) -> void:
	_checkpoint()
	for c in mission.contacts:
		if c.id == id: c.position = [snappedf(clampf(position.x, -12000, 12000), 25), snappedf(clampf(position.y, -12000, 12000), 25)]
	_refresh()

func _delete_contact() -> void:
	if _selected < 0: return
	_checkpoint()
	var id: String = mission.contacts[_selected].id
	mission.contacts.remove_at(_selected)
	mission.objectives = mission.objectives.filter(func(goal): return goal.target != id)
	_refresh()

func _add_goal() -> void:
	if _goal_target.item_count == 0 or mission.objectives.size() >= 24: return
	_checkpoint()
	mission.objectives.append({"type": GOALS[_goal_kind.selected], "target": _goal_target.get_item_metadata(_goal_target.selected), "text": GOAL_NAMES[_goal_kind.selected] + " · " + _goal_target.get_item_text(_goal_target.selected)})
	_selected_goal = mission.objectives.size() - 1
	_refresh()

func _goal_text(text: String) -> void:
	if _syncing or _selected_goal < 0 or mission.objectives[_selected_goal].text == text: return
	_checkpoint()
	mission.objectives[_selected_goal].text = text.left(500)
	_validate()

func _delete_goal() -> void:
	if _selected_goal < 0: return
	_checkpoint()
	mission.objectives.remove_at(_selected_goal)
	_refresh()

func _reorder(offset: int) -> void:
	var next = _selected_goal + offset
	if _selected_goal < 0 or next < 0 or next >= mission.objectives.size(): return
	_checkpoint()
	var goal = mission.objectives[_selected_goal]
	mission.objectives.remove_at(_selected_goal)
	mission.objectives.insert(next, goal)
	_selected_goal = next
	_refresh()

func _undo_change() -> void:
	if not _undo.is_empty(): set_mission(_undo.pop_back())

func _new_mission() -> void:
	_checkpoint()
	set_mission({"id": "custom_" + str(int(Time.get_unix_time_from_system())), "title": "Una nueva ruta", "sector": "Sector por explorar", "briefing": "Describe aquí la situación y el cometido de la tripulación.", "reward": 100, "contacts": [{"id": "faro", "name": "Faro de llegada", "kind": "beacon", "position": [650, 0], "known": true}], "objectives": [{"type": "navigate", "target": "faro", "text": "Llega a menos de 250 m del faro."}]})

func _apply_json() -> void:
	if _json.text.to_utf8_buffer().size() > 256 * 1024:
		_status.text = "El JSON supera 256 KiB."
		return
	var parsed = JSON.parse_string(_json.text)
	var error = Catalog.validate_mission(parsed)
	if not error.is_empty(): _status.text = error; return
	_checkpoint()
	set_mission(parsed)

func _open_dialog() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://missions"))
	_dialog.current_dir = ProjectSettings.globalize_path("user://missions")
	_dialog.popup_centered_ratio(0.75)

func _load_file(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: _status.text = "No se pudo abrir la misión."; return
	if file.get_length() > 256 * 1024: file.close(); _status.text = "El archivo supera 256 KiB."; return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	var error = Catalog.validate_mission(parsed)
	if not error.is_empty(): _status.text = error; return
	_checkpoint()
	set_mission(parsed)

func _save() -> void:
	if not _validate(): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://missions"))
	var path = "user://missions/" + mission.id + ".json"
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: _status.text = "No se pudo abrir el archivo de destino."; return
	file.store_string(JSON.stringify(mission, "  ", true, true))
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) != OK:
		_status.text = "No se pudo completar el guardado."
		return
	_status.text = "Guardada: " + ProjectSettings.globalize_path(path)

func _play() -> void:
	if _validate(): play_requested.emit(mission.duplicate(true))
