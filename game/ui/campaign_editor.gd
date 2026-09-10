class_name CampaignEditor
extends Window
signal campaign_requested(document: Dictionary)
signal mission_preview_requested(mission: Dictionary)

var document: Dictionary = {}
var selected = 0
var fields: Dictionary = {}
var mission_list: ItemList
var status: Label
var details: Label
var dependencies: VBoxContainer
var dependency_fields: Dictionary = {}
var linear: CheckBox
var file_dialog: FileDialog
var mission_window: Window
var mission_editor: MissionEditor
var _history: Array = []
var _saved_text = ""
var _file_action = "open"

func _ready() -> void:
	title = "Taller de campañas"
	size = Vector2i(1280, 800)
	min_size = Vector2i(1000, 650)
	transient = true
	exclusive = true
	if document.is_empty(): document = CampaignDocument.create()
	document = document.duplicate(true)
	_saved_text = JSON.stringify(document, "", true, true)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 22)
	add_child(margin)
	var root = ConsoleUI.column(margin, 12)
	root.add_child(ConsoleUI.label("Diseña una expedición compartida", 28))
	var toolbar = ConsoleUI.row(root, 8)
	toolbar.add_child(ConsoleUI.button("Nueva campaña", _new_document))
	toolbar.add_child(ConsoleUI.button("Abrir JSON", _open))
	toolbar.add_child(ConsoleUI.button("Deshacer", _undo))
	toolbar.add_child(ConsoleUI.button("Guardar copia local", _save_local, true))
	toolbar.add_child(ConsoleUI.button("Exportar JSON", _export))
	toolbar.add_child(ConsoleUI.button("Jugar campaña", _play_campaign, true))
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ConsoleUI.expand(scroll)
	root.add_child(scroll)
	var body = ConsoleUI.row(scroll, 18)
	ConsoleUI.expand(body)
	var left = ConsoleUI.column(body, 8)
	left.custom_minimum_size.x = 325
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for field in [["id", "IDENTIFICADOR"], ["title", "TÍTULO"], ["description", "PRESENTACIÓN"]]:
		left.add_child(ConsoleUI.label(field[1], 13, ConsoleUI.MUTED))
		var edit: Control = TextEdit.new() if field[0] == "description" else LineEdit.new()
		if edit is TextEdit:
			edit.custom_minimum_size.y = 90
			edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		left.add_child(edit)
		fields[field[0]] = edit
	left.add_child(ConsoleUI.label("MISIONES · ORDEN DE LA EXPEDICIÓN", 13, ConsoleUI.TEAL))
	var order = ConsoleUI.row(left, 6)
	order.add_child(ConsoleUI.button("Subir", _move.bind(-1)))
	order.add_child(ConsoleUI.button("Bajar", _move.bind(1)))
	order.add_child(ConsoleUI.button("Eliminar", _delete))
	mission_list = ItemList.new()
	mission_list.custom_minimum_size.y = 160
	mission_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(mission_list)
	mission_list.item_selected.connect(func(index): selected = index; _refresh_selection())
	var right = ConsoleUI.column(body, 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size.x = 400
	var add = ConsoleUI.row(right, 8)
	add.add_child(ConsoleUI.button("Añadir misión", _add_mission, true))
	add.add_child(ConsoleUI.button("Importar misión JSON", _import_mission))
	right.add_child(ConsoleUI.button("Editar misión seleccionada", _edit_mission, true))
	details = ConsoleUI.paragraph("", 18)
	details.custom_minimum_size.y = 130
	right.add_child(details)
	right.add_child(ConsoleUI.label("REQUISITOS PARA DESBLOQUEAR", 13, ConsoleUI.TEAL))
	linear = CheckBox.new()
	linear.text = "Ruta lineal: completar la misión anterior"
	right.add_child(linear)
	linear.toggled.connect(func(value):
		for field in dependency_fields.values(): field.disabled = value)
	var dependency_scroll = ScrollContainer.new()
	dependency_scroll.custom_minimum_size.y = 110
	dependency_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(dependency_scroll)
	dependencies = ConsoleUI.column(dependency_scroll, 4)
	dependencies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(ConsoleUI.button("Aplicar requisitos", _apply_dependencies))
	right.add_child(ConsoleUI.paragraph("Desmarca la ruta lineal y marca las misiones necesarias. Sin ninguna marcada, esta etapa estará disponible desde el inicio. Sólo se ofrecen misiones anteriores, para evitar ciclos.", 15))
	right.add_child(ConsoleUI.paragraph("El taller reutiliza el mapa, los objetivos y el astillero del editor de misiones. La campaña guarda todo el contenido: no depende de archivos externos ni de Foundry.", 15, ConsoleUI.MUTED))
	status = ConsoleUI.paragraph("", 15)
	root.add_child(status)
	root.add_child(ConsoleUI.button("Cerrar taller", _close))
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.json ; Contenido JSON"])
	file_dialog.file_selected.connect(_file_selected)
	add_child(file_dialog)
	close_requested.connect(_close)
	_refresh()

func _message(text: String, good: bool = false) -> void:
	status.text = text
	status.add_theme_color_override("font_color", ConsoleUI.TEAL if good else ConsoleUI.AMBER)

func _refresh() -> void:
	for key in fields: fields[key].text = document[key]
	mission_list.clear()
	for i in document.missions.size(): mission_list.add_item("%02d · %s" % [i + 1, document.missions[i].title])
	selected = clampi(selected, 0, document.missions.size() - 1)
	mission_list.select(selected)
	_refresh_selection()

func _refresh_selection() -> void:
	var mission: Dictionary = document.missions[selected]
	details.text = "%s\nID: %s\n%s\n%d contactos · %d objetivos · %d créditos" % [mission.title, mission.id, mission.sector, mission.contacts.size(), mission.objectives.size(), mission.get("reward", 0)]
	linear.set_pressed_no_signal(not mission.has("requires"))
	for child in dependencies.get_children():
		dependencies.remove_child(child)
		child.queue_free()
	dependency_fields.clear()
	if selected == 0: dependencies.add_child(ConsoleUI.paragraph("Primera misión: disponible desde el inicio.", 14, ConsoleUI.MUTED))
	for i in selected:
		var previous: Dictionary = document.missions[i]
		var field = CheckBox.new()
		field.text = "%02d · %s" % [i + 1, previous.title]
		field.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		field.tooltip_text = previous.id
		field.disabled = linear.button_pressed
		field.button_pressed = previous.id in mission.get("requires", [])
		dependencies.add_child(field)
		dependency_fields[previous.id] = field

func _metadata() -> bool:
	var candidate = document.duplicate(true)
	for key in fields: candidate[key] = fields[key].text.strip_edges()
	return _accept(CampaignDocument.checked(candidate), false)

func _accept(result: Dictionary, refresh: bool = true) -> bool:
	if result.has("error"):
		_message(result.error)
		return false
	if document != result.document:
		_history.append(document.duplicate(true))
		if _history.size() > 40: _history.pop_front()
		document = result.document.duplicate(true)
	if refresh: _refresh()
	_message("Campaña válida · %d misiones. Guarda o exporta para conservar los cambios." % document.missions.size(), true)
	return true

func _confirm(text: String, action: Callable) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = text
	dialog.title = "Confirmar cambio"
	dialog.confirmed.connect(func(): dialog.queue_free(); action.call())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(570, 180))

func _new_document() -> void:
	_confirm("¿Crear otra campaña? Los cambios no guardados se descartarán.", func():
		selected = 0
		_accept({"document": CampaignDocument.create()}))

func _add_mission() -> void:
	if not _metadata(): return
	var candidate = document.duplicate(true)
	candidate.missions.append(CampaignDocument.new_mission())
	if _accept(CampaignDocument.checked(candidate)):
		selected = document.missions.size() - 1
		_refresh()

func _delete() -> void:
	if not _metadata(): return
	_confirm("¿Eliminar la misión seleccionada? Puedes recuperarla con Deshacer.", func(): _accept(CampaignDocument.remove_mission(document, selected)))

func _move(offset: int) -> void:
	if not _metadata(): return
	var result = CampaignDocument.move_mission(document, selected, offset)
	if result.has("document"): selected += offset
	_accept(result)

func _undo() -> void:
	if _history.is_empty(): return
	document = _history.pop_back()
	_refresh()
	_message("Cambio deshecho.", true)

func _apply_dependencies() -> void:
	if not _metadata(): return
	var mission: Dictionary = document.missions[selected].duplicate(true)
	if linear.button_pressed: mission.erase("requires")
	else:
		mission.requires = []
		for id in dependency_fields:
			if dependency_fields[id].button_pressed: mission.requires.append(id)
	_accept(CampaignDocument.replace_mission(document, selected, mission))

func _edit_mission() -> void:
	if not _metadata(): return
	mission_window = Window.new()
	mission_window.title = "Misión de campaña · " + document.missions[selected].title
	mission_window.size = Vector2i(1500, 810)
	mission_window.transient = true
	mission_window.exclusive = true
	var box = ConsoleUI.column(mission_window, 8)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bar = ConsoleUI.row(box, 12)
	bar.add_child(ConsoleUI.button("Aplicar a la campaña", _apply_mission, true))
	bar.add_child(ConsoleUI.button("Cancelar edición", _cancel_mission))
	bar.add_child(ConsoleUI.label("Aplicar conserva contactos, objetivos, diseño y requisitos.", 14))
	mission_editor = MissionEditor.new()
	mission_editor.mission = document.missions[selected].duplicate(true)
	ConsoleUI.expand(mission_editor)
	box.add_child(mission_editor)
	mission_editor.play_requested.connect(func(mission): mission_preview_requested.emit(mission))
	mission_window.close_requested.connect(_cancel_mission)
	add_child(mission_window)
	mission_window.popup_centered()

func _apply_mission() -> void:
	# Commit the currently focused field using the existing editor's callbacks.
	var focus = mission_window.gui_get_focus_owner()
	if focus != null: focus.release_focus()
	var result = CampaignDocument.replace_mission(document, selected, mission_editor.mission)
	if _accept(result): mission_window.queue_free()
	else: mission_editor._status.text = result.error

func _cancel_mission() -> void:
	var focus = mission_window.gui_get_focus_owner()
	if focus != null: focus.release_focus()
	if mission_editor.mission == document.missions[selected]: mission_window.queue_free()
	else:
		var dialog = ConfirmationDialog.new()
		dialog.dialog_text = "¿Descartar los cambios de esta misión?"
		dialog.confirmed.connect(mission_window.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		mission_window.add_child(dialog)
		dialog.popup_centered()

func _directory() -> String:
	return ProjectSettings.globalize_path("user://campaigns")

func _choose_file(action: String, save: bool = false) -> void:
	_file_action = action
	DirAccess.make_dir_recursive_absolute(_directory())
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.current_dir = _directory()
	file_dialog.current_file = document.id + ".json" if save else ""
	file_dialog.popup_centered_ratio(0.8)

func _open() -> void:
	_confirm("¿Abrir otra campaña? Los cambios no guardados se descartarán.", func(): _choose_file("open"))

func _import_mission() -> void:
	if _metadata(): _choose_file("mission")

func _export() -> void:
	if _metadata(): _choose_file("export", true)

func _file_selected(path: String) -> void:
	if _file_action == "export":
		_write(path)
	elif _file_action == "mission":
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null: _message("No se pudo abrir la misión."); return
		if file.get_length() > 256 * 1024: file.close(); _message("La misión supera 256 KiB."); return
		var parser = JSON.new()
		var parse_error = parser.parse(file.get_as_text())
		file.close()
		if parse_error != OK: _message("JSON de misión inválido."); return
		var mission = parser.data
		var error = Catalog.validate_mission(mission)
		if not error.is_empty(): _message(error); return
		var candidate = document.duplicate(true)
		candidate.missions.append(mission)
		if _accept(CampaignDocument.checked(candidate)):
			selected = document.missions.size() - 1
			_refresh()
	else:
		if _accept(CampaignDocument.read_document(path)):
			_saved_text = JSON.stringify(document, "", true, true)

func _write(path: String) -> void:
	if not _metadata(): return
	var error = CampaignDocument.write_document(document, path)
	if error.is_empty():
		_saved_text = JSON.stringify(document, "", true, true)
		_message("Campaña guardada: " + path.get_file(), true)
	else: _message(error)

func _save_local() -> void:
	if not _metadata(): return
	DirAccess.make_dir_recursive_absolute(_directory())
	_write("user://campaigns/" + document.id + ".json")

func _play_campaign() -> void:
	if _metadata(): campaign_requested.emit(document.duplicate(true))

func _close() -> void:
	var pending = JSON.stringify(document, "", true, true) != _saved_text
	for key in fields: pending = pending or fields[key].text != document[key]
	if pending: _confirm("Hay cambios sin guardar. ¿Cerrar el taller y descartarlos?", queue_free)
	else: queue_free()
