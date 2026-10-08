class_name NamedSaveWindow
extends Window
## Explicit local file actions. Every handler rechecks authority, not only its button.
signal restored

var session: Node
var expedition: Node
var slots: ItemList
var preview: TextEdit
var name_edit: LineEdit
var status: Label
var buttons: Dictionary = {}
var confirmation: ConfirmationDialog
var files: FileDialog
var _selected = ""
var _digest = ""
var _selected_valid = false
var _incoming: Dictionary = {}
var _pending: Callable
var _file_action = ""
var _export_id = ""
var _last_mode = ""

func _ready() -> void:
	if session == null: session = get_tree().root.get_node("Session")
	expedition = get_tree().root.get_node("Expedition")
	title = "Guardados de campaña"
	size = Vector2i(1080, 780)
	min_size = Vector2i(780, 540)
	exclusive = true
	transient = true
	theme = ConsoleUI.make_theme()
	close_requested.connect(queue_free)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 18)
	add_child(margin)
	var root = ConsoleUI.column(margin, 12)
	root.add_child(ConsoleUI.label("GUARDADOS DE CAMPAÑA", 25, ConsoleUI.TEAL))
	root.add_child(ConsoleUI.paragraph("Pon nombre a tu progreso o llévalo a otro equipo mediante un archivo local. Importar no cambia la partida abierta.", 15))
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ConsoleUI.expand(scroll)
	root.add_child(scroll)
	var content = ConsoleUI.column(scroll, 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body = ConsoleUI.row(content, 14)
	body.custom_minimum_size.y = 260
	slots = ItemList.new()
	slots.name = "NamedSaveList"
	slots.custom_minimum_size = Vector2(300, 260)
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots.item_selected.connect(_select)
	body.add_child(slots)
	preview = TextEdit.new()
	preview.name = "NamedSavePreview"
	preview.editable = false
	preview.add_theme_color_override("font_readonly_color", ConsoleUI.TEXT)
	preview.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	preview.custom_minimum_size = Vector2(390, 260)
	ConsoleUI.expand(preview)
	body.add_child(preview)
	content.add_child(ConsoleUI.label("Nombre para un guardado nuevo o una importación", 15))
	name_edit = LineEdit.new()
	name_edit.name = "NamedSaveName"
	name_edit.max_length = CampaignCheckpoint.MAX_LABEL
	name_edit.placeholder_text = "Por ejemplo: Antes del salto"
	name_edit.text_changed.connect(func(_text): _permissions())
	content.add_child(name_edit)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	for item in [["save", "Guardar partida actual", _save_new], ["load", "Cargar seleccionado…", _ask_load], ["replace", "Sustituir seleccionado…", _ask_replace], ["export", "Exportar seleccionado…", _choose_export], ["import", "Importar archivo…", _choose_import], ["accept_import", "Guardar importación", _accept_import], ["delete", "Eliminar seleccionado…", _ask_delete], ["refresh", "Actualizar lista", _reload]]:
		var button = ConsoleUI.button(item[1], item[2])
		button.name = "NamedSave_" + item[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons[item[0]] = button
		grid.add_child(button)
	var privacy = ConsoleUI.paragraph("El archivo contiene fichas y secretos del director. Compártelo sólo con alguien de confianza; no es un informe público ni se envía a ningún servicio.", 14, ConsoleUI.TEXT)
	privacy.name = "NamedSavePrivacy"
	root.add_child(privacy)
	status = ConsoleUI.paragraph("Hasta 32 guardados. Para cargar, cierra primero la sesión de red.", 14)
	status.name = "NamedSaveStatus"
	root.add_child(status)
	root.add_child(ConsoleUI.button("Cerrar", queue_free))
	confirmation = ConfirmationDialog.new()
	confirmation.name = "NamedSaveConfirmation"
	confirmation.title = "Confirmar operación local"
	confirmation.confirmed.connect(_confirm_pending)
	confirmation.canceled.connect(func(): _pending = Callable())
	add_child(confirmation)
	files = FileDialog.new()
	files.name = "NamedSaveFileDialog"
	files.access = FileDialog.ACCESS_FILESYSTEM
	files.filters = PackedStringArray(["*.lagunak ; Campaña completa de Lagunak"])
	files.size = Vector2i(820, 500)
	files.file_selected.connect(_file_selected)
	add_child(files)
	session.updated.connect(_session_updated)
	_last_mode = session.mode
	_reload()

func _allowed() -> bool:
	if NamedSaveStore.can_manage(session): return true
	_incoming.clear()
	_selected = ""
	_digest = ""
	if preview != null: preview.text = ""
	if slots != null: slots.clear()
	_show({"ok": false, "message": "Los clientes no gestionan guardados del anfitrión."})
	return false

func _session_updated() -> void:
	if session.mode != _last_mode:
		_last_mode = session.mode
		_pending = Callable()
		_incoming.clear()
		files.hide()
		confirmation.hide()
		_reload()
	_permissions()

func _permissions() -> void:
	var allowed = NamedSaveStore.can_manage(session)
	var selected = allowed and not _selected.is_empty() and not _digest.is_empty()
	var valid_name = CampaignCheckpoint.valid_label(name_edit.text)
	for button in buttons.values(): button.disabled = not allowed
	buttons.save.disabled = not allowed or not valid_name or session.sim.state.is_empty()
	buttons.load.disabled = not selected or not _selected_valid or session.mode != "offline"
	buttons.replace.disabled = not selected or not _selected_valid or _selected == "recovery" or session.sim.state.is_empty()
	buttons.export.disabled = not selected or not _selected_valid
	buttons.delete.disabled = not selected or _selected == "recovery"
	buttons.accept_import.disabled = not allowed or _incoming.is_empty() or not valid_name
	name_edit.editable = allowed

func _reload() -> void:
	_incoming.clear()
	_selected_valid = false
	slots.clear()
	_selected = ""
	_digest = ""
	preview.text = "Selecciona un guardado para ver su contenido."
	if _allowed():
		for entry in NamedSaveStore.list_entries():
			var prefix = "" if entry.ok else "[Dañado] "
			slots.add_item(prefix + entry.label)
			slots.set_item_metadata(slots.item_count - 1, entry.id)
	_permissions()

func _select(index: int) -> void:
	if not _allowed() or index < 0 or index >= slots.item_count: return
	_incoming.clear()
	_selected = str(slots.get_item_metadata(index))
	var loaded = NamedSaveStore.read_slot(_selected)
	_digest = loaded.get("digest", "")
	_selected_valid = loaded.ok
	preview.text = CampaignCheckpoint.summary(loaded.checkpoint) if loaded.ok else loaded.message
	_show({"ok": loaded.ok, "message": "Guardado validado. Cargar sustituirá la partida actual y conservará una recuperación." if loaded.ok else loaded.message})
	_permissions()

func _show(result: Dictionary) -> void:
	if status == null: return
	status.text = str(result.get("message", "Operación completada."))
	status.add_theme_color_override("font_color", ConsoleUI.TEAL if result.get("ok", false) else ConsoleUI.RED)

func _save_new() -> void:
	if not _allowed(): return
	var captured = NamedSaveStore.capture(session, expedition, name_edit.text)
	if not captured.ok: _show(captured); return
	var result = NamedSaveStore.store(captured.checkpoint)
	if result.ok: _reload()
	_show(result)

func _ask(message: String, action: Callable) -> void:
	_pending = action
	confirmation.dialog_text = message
	confirmation.popup_centered(Vector2i(700, 230))

func _confirm_pending() -> void:
	var action = _pending
	_pending = Callable()
	if _allowed() and action.is_valid(): action.call()

func _ask_load() -> void:
	if not _allowed() or _selected.is_empty() or _digest.is_empty(): return
	var id = _selected
	var digest = _digest
	_ask("¿Cargar este guardado? Se sustituirá la campaña abierta, incluidas las fichas e inventarios. Se conservará un checkpoint de recuperación.\n\nLas partidas de mesa, combates y minijuegos en curso se cancelarán.", func():
		var result = session.restore_named_save(id, digest)
		_show(result)
		if result.ok:
			restored.emit()
			queue_free())

func _ask_replace() -> void:
	if not _allowed() or _selected.is_empty() or _selected == "recovery": return
	var selected = NamedSaveStore.read_slot(_selected)
	if not selected.ok: _show(selected); return
	var label = str(selected.checkpoint.label)
	var digest = _digest
	_ask("¿Sustituir «%s» por el progreso actual? El contenido anterior de ese guardado se reemplazará." % label, func():
		var captured = NamedSaveStore.capture(session, expedition, label)
		if not captured.ok: _show(captured); return
		var result = NamedSaveStore.store(captured.checkpoint, digest)
		if result.ok: _reload()
		_show(result))

func _ask_delete() -> void:
	if not _allowed() or _selected.is_empty() or _selected == "recovery": return
	var id = _selected
	var digest = _digest
	_ask("¿Eliminar el guardado seleccionado? No se borrará la campaña abierta ni la copia de recuperación.", func():
		var result = NamedSaveStore.remove_slot(id, digest)
		if result.ok: _reload()
		_show(result))

func _choose_import() -> void:
	if not _allowed(): return
	_file_action = "import"
	files.title = "Importar campaña a un guardado nuevo"
	files.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	files.popup_centered()

func _choose_export() -> void:
	if not _allowed() or _selected.is_empty() or _digest.is_empty(): return
	_export_id = _selected
	_file_action = "export"
	files.title = "Exportar campaña local: utiliza un archivo nuevo"
	files.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	files.current_file = "campana.lagunak"
	files.popup_centered()

func _file_selected(path: String) -> void:
	if not _allowed(): return
	if _file_action == "export":
		_show(NamedSaveStore.export_slot(_export_id, path))
		return
	if _file_action != "import": return
	var imported = NamedSaveStore.read_file(path)
	_incoming.clear()
	if imported.ok:
		_incoming = imported.checkpoint.duplicate(true)
		name_edit.text = _incoming.label
		preview.text = "IMPORTACIÓN PENDIENTE — la partida no ha cambiado\n\n" + CampaignCheckpoint.summary(_incoming)
		_show({"ok": true, "message": "Revisa la importación, elige un nombre libre y pulsa Guardar importación."})
	else: _show(imported)
	_permissions()

func _accept_import() -> void:
	if not _allowed() or _incoming.is_empty(): return
	var checkpoint = _incoming.duplicate(true)
	checkpoint.label = name_edit.text
	var result = NamedSaveStore.store(checkpoint)
	if result.ok:
		_incoming.clear()
		_reload()
	_show(result)
