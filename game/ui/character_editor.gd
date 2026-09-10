class_name CharacterEditor
extends Window
## A local draft of authored fields. Expedition remains the only profile authority.

const CONFIRM_TIMEOUT = 8.0
const EDITOR_GROUP = "lagunak_character_editor"
const SKILL_NAMES = {"pilotaje": "Pilotaje", "ciencia": "Ciencia", "ingenieria": "Ingeniería", "negociacion": "Negociación", "combate": "Combate"}
const APPROACH_NAMES = {"ingenio": "Ingenio", "temple": "Temple", "empatia": "Empatía", "tecnica": "Técnica"}

var expedition: Node
var fields: Dictionary = {}
var status: Label
var budget_label: Label
var budget_bar: ProgressBar
var apply_button: Button
var import_button: Button
var export_button: Button
var discard_dialog: ConfirmationDialog
var import_dialog: ConfirmationDialog
var file_dialog: FileDialog
var pending = false
var last_apply_state = "idle"
var _baseline: Dictionary = {}
var _submitted: Dictionary = {}
var _staged_import: Dictionary = {}
var _actor = ""
var _mode = ""
var _pending_seconds = 0.0
var _awaiting_snapshot = false
var _loading = false
var _external_change: Label

func _ready() -> void:
	title = "Editar ficha · plantilla personal"
	size = Vector2i(1040, 740)
	min_size = Vector2i(900, 640)
	transient = true
	exclusive = true
	theme = ConsoleUI.make_theme()
	add_to_group(EDITOR_GROUP)
	if expedition == null: expedition = get_tree().root.get_node_or_null("Expedition")
	if expedition != null:
		_actor = expedition.actor_id()
		_mode = _session_mode()
		expedition.updated.connect(_on_updated)
		expedition.notice.connect(_on_notice)
	_build()
	close_requested.connect(request_close)
	var profile = _own_profile()
	if profile.is_empty():
		_set_status("No hay una ficha propia disponible. Cierra y vuelve a abrir F4 tras recibirla.", false)
	else:
		_baseline = CharacterDocument.editable_from_profile(profile)
		_set_fields(_baseline)
		_set_status("Borrador local. Aplicar modifica solo tu nombre, enfoque y habilidades.", true)
	_refresh()
	fields.name.grab_focus()

func _build() -> void:
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 20)
	add_child(margin)
	var body = ConsoleUI.column(margin, 10)
	body.add_child(ConsoleUI.label("TU FICHA · DISEÑO SIN REINICIAR PROGRESO", 23, ConsoleUI.TEAL))
	body.add_child(ConsoleUI.paragraph("La plantilla JSON contiene solo nombre, enfoque y cinco habilidades. Nunca exporta XP, nivel, rasgos, condición, concentración, hitos, ID de actor ni datos de otros tripulantes.", 16))
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ConsoleUI.expand(scroll)
	body.add_child(scroll)
	var form = ConsoleUI.column(scroll, 12)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var identity = ConsoleUI.card(form, "IDENTIDAD EDITABLE")
	var row = ConsoleUI.row(identity, 16)
	var name_box = ConsoleUI.column(row, 6)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_child(ConsoleUI.label("Nombre · 1–32 caracteres, sin espacios en los extremos", 14))
	var name_field = LineEdit.new()
	name_field.max_length = CharacterDocument.MAX_NAME
	name_field.custom_minimum_size.y = 44
	fields.name = name_field
	name_box.add_child(name_field)
	name_field.text_changed.connect(func(_value): _draft_changed())
	var approach_box = ConsoleUI.column(row, 6)
	approach_box.custom_minimum_size.x = 220
	approach_box.add_child(ConsoleUI.label("Enfoque", 14))
	var approach = OptionButton.new()
	approach.custom_minimum_size.y = 44
	for id in ExpeditionSystems.APPROACHES:
		approach.add_item(APPROACH_NAMES[id])
		approach.set_item_metadata(approach.item_count - 1, id)
	approach_box.add_child(approach)
	fields.approach = approach
	approach.item_selected.connect(func(_index): _draft_changed())
	var skills = ConsoleUI.card(form, "HABILIDADES · ENTEROS DE 0 A 4")
	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 16)
	skills.add_child(grid)
	for skill in ExpeditionSystems.SKILLS:
		var box = ConsoleUI.column(grid, 6)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(ConsoleUI.label(SKILL_NAMES[skill], 16))
		var spin = SpinBox.new()
		spin.min_value = 0
		spin.max_value = CharacterDocument.MAX_SKILL
		spin.step = 1
		spin.rounded = true
		spin.custom_minimum_size = Vector2(132, 44)
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(spin)
		fields[skill] = spin
		spin.value_changed.connect(func(_value): _draft_changed())
	budget_label = ConsoleUI.label("", 18)
	skills.add_child(budget_label)
	budget_bar = ProgressBar.new()
	budget_bar.max_value = CharacterDocument.BUDGET
	budget_bar.show_percentage = false
	budget_bar.custom_minimum_size.y = 12
	skills.add_child(budget_bar)
	skills.add_child(ConsoleUI.paragraph("No necesitas gastar los 12 puntos. El límite es compartido; el anfitrión vuelve a validarlo al aplicar.", 14))
	var protection = ConsoleUI.card(form, "LA PARTIDA SIGUE VIVA")
	protection.add_child(ConsoleUI.paragraph("La progresión no forma parte del borrador. Si ganas XP, adquieres rasgos o cambian tu condición, concentración o hitos mientras editas, se conserva su valor vigente al aplicar. Importar y exportar no cambian la partida.", 15))
	_external_change = ConsoleUI.paragraph("", 14, ConsoleUI.AMBER)
	protection.add_child(_external_change)
	var actions = ConsoleUI.row(body, 10)
	import_button = ConsoleUI.button("Importar JSON…", _choose_import)
	export_button = ConsoleUI.button("Exportar plantilla…", _choose_export)
	apply_button = ConsoleUI.button("Aplicar a mi ficha", apply_changes, true)
	actions.add_child(import_button)
	actions.add_child(export_button)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	actions.add_child(apply_button)
	actions.add_child(ConsoleUI.button("Cerrar", request_close))
	status = ConsoleUI.paragraph("", 15)
	status.custom_minimum_size.y = 58
	body.add_child(status)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.title = "¿Cerrar este borrador?"
	discard_dialog.ok_button_text = "Descartar y cerrar"
	discard_dialog.cancel_button_text = "Seguir editando"
	discard_dialog.confirmed.connect(func(): queue_free())
	add_child(discard_dialog)
	import_dialog = ConfirmationDialog.new()
	import_dialog.title = "¿Reemplazar el borrador?"
	import_dialog.dialog_text = "La plantilla es válida. Reemplazará tus cambios locales sin aplicar. La ficha de la partida no cambiará."
	import_dialog.ok_button_text = "Reemplazar borrador"
	import_dialog.cancel_button_text = "Conservar borrador"
	import_dialog.confirmed.connect(_accept_import)
	import_dialog.canceled.connect(func(): _staged_import.clear())
	add_child(import_dialog)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.json ; Plantilla de personaje JSON"])
	file_dialog.use_native_dialog = false
	file_dialog.file_selected.connect(_file_selected)
	add_child(file_dialog)

func _session_mode() -> String:
	var session = get_tree().root.get_node_or_null("Session")
	return str(session.mode) if session != null else "offline"

func _same_actor() -> bool:
	return is_instance_valid(expedition) and expedition.actor_id() == _actor and _session_mode() == _mode

func _own_profile() -> Dictionary:
	if not _same_actor(): return {}
	return expedition.data.get("profiles", {}).get(_actor, {})

func read_document() -> Dictionary:
	var skills: Dictionary = {}
	for skill in ExpeditionSystems.SKILLS: skills[skill] = int(fields[skill].value)
	var approach = ""
	if fields.approach.selected >= 0: approach = str(fields.approach.get_item_metadata(fields.approach.selected))
	return CharacterDocument.document({"name": fields.name.text, "approach": approach, "skills": skills})

func is_dirty() -> bool:
	return not fields.is_empty() and read_document().character != _baseline

func _set_fields(value: Dictionary) -> void:
	_loading = true
	fields.name.text = value.name
	fields.approach.select(ExpeditionSystems.APPROACHES.find(value.approach))
	for skill in ExpeditionSystems.SKILLS: fields[skill].value = value.skills.get(skill, 0)
	_loading = false

func _draft_changed() -> void:
	if _loading: return
	_refresh()
	var result = CharacterDocument.validate(read_document())
	if not result.ok:
		_set_status(result.message, false)
	elif last_apply_state != "timeout":
		_set_status("Cambios locales sin aplicar." if is_dirty() else "Sin cambios locales pendientes.", true)

func _refresh() -> void:
	if fields.is_empty(): return
	var total = 0
	for skill in ExpeditionSystems.SKILLS: total += int(fields[skill].value)
	budget_bar.value = total
	budget_label.text = "%d / 12 puntos · %s" % [total, "%d disponibles" % (12 - total) if total <= 12 else "exceso de %d" % (total - 12)]
	budget_label.add_theme_color_override("font_color", ConsoleUI.TEAL if total <= 12 else ConsoleUI.RED)
	var valid: bool = CharacterDocument.validate(read_document()).ok
	var available = not _baseline.is_empty() and _same_actor()
	apply_button.disabled = pending or not available or not valid or not is_dirty()
	export_button.disabled = pending or not valid
	import_button.disabled = pending
	fields.name.editable = not pending
	fields.approach.disabled = pending
	for skill in ExpeditionSystems.SKILLS: fields[skill].editable = not pending
	title = "Editar ficha · " + ("esperando al anfitrión" if pending else ("cambios sin aplicar" if is_dirty() else "plantilla personal"))
	var current = _own_profile()
	_external_change.text = "La ficha editable cambió fuera del editor. Tu borrador se conserva; aplicar sustituirá solo los campos editables." if not current.is_empty() and CharacterDocument.editable_from_profile(current) != _baseline else "XP, nivel, rasgos, condición, concentración e hitos: protegidos, no editables aquí."
	if not available:
		_external_change.text = "La sesión o tu identidad cambió. Cierra y vuelve a abrir el editor para editar la ficha actual. Puedes exportar el borrador."

func apply_changes() -> void:
	if pending: return
	# Commit a SpinBox's typed text before collecting its numeric value.
	# Untouched SpinBoxes may still have deferred display text from a prior value;
	# applying all of them would roll back programmatic/imported changes.
	for skill in ExpeditionSystems.SKILLS:
		if fields[skill].get_line_edit().has_focus(): fields[skill].apply()
	var result = CharacterDocument.validate(read_document())
	if not result.ok:
		_set_status(result.message, false)
		return
	if not _same_actor() or _baseline.is_empty():
		last_apply_state = "blocked"
		_set_status("La identidad de sesión cambió o no hay ficha. Cierra y vuelve a abrir el editor.", false)
		return
	if not is_dirty():
		_set_status("No hay cambios locales que aplicar.", true)
		return
	_submitted = result.document.character.duplicate(true)
	pending = true
	_awaiting_snapshot = true
	_pending_seconds = 0.0
	last_apply_state = "pending"
	_set_status("Solicitud enviada. Pendiente de un estado concordante del anfitrión (hasta 8 s); aún no confirmada.", true, true)
	_refresh()
	# Set pending first: offline/host emits updated synchronously within command.
	var response: Dictionary = expedition.command("profile_set", CharacterDocument.command_args(_submitted))
	if not response.ok and pending:
		pending = false
		_awaiting_snapshot = false
		last_apply_state = "rejected"
		_set_status(response.message, false)
		_refresh()

func _on_updated() -> void:
	if not is_inside_tree() or is_queued_for_deletion(): return
	if _awaiting_snapshot and _same_actor():
		var current = _own_profile()
		if not current.is_empty() and CharacterDocument.editable_from_profile(current) == _submitted:
			var was_late = last_apply_state == "timeout"
			_baseline = _submitted.duplicate(true)
			pending = false
			_awaiting_snapshot = false
			last_apply_state = "confirmed"
			_set_status(("Confirmación tardía: " if was_late else "Ficha aplicada: ") + "estado concordante recibido; se conserva la progresión vigente." + (" Tu borrador tiene cambios posteriores sin aplicar." if is_dirty() else ""), true)
	_refresh()

func _on_notice(text: String, ok: bool) -> void:
	if not pending: return
	# Notices have no operation/request ID. Neither a generic success nor an
	# unrelated rejection can prove which fields were applied. Await the snapshot.
	_set_status("Aviso: %s\nLa ficha sigue pendiente de un estado concordante; no se declara aplicada." % text, ok, ok)

func _process(delta: float) -> void:
	if fields.is_empty(): return
	if not _same_actor():
		if pending or _awaiting_snapshot:
			pending = false
			_awaiting_snapshot = false
			last_apply_state = "blocked"
			_set_status("Cambió la sesión. No se puede confirmar la solicitud anterior; el borrador se conserva.", false)
		_refresh()
		return
	if not pending: return
	_pending_seconds += delta
	if _pending_seconds >= CONFIRM_TIMEOUT:
		pending = false
		last_apply_state = "timeout"
		_set_status("Sin confirmación tras 8 s. El borrador se conserva. Puedes esperar, exportarlo o reintentar; la solicitud anterior no se ha cancelado y puede llegar tarde.", false)
		_refresh()

func _set_status(text: String, ok: bool, waiting: bool = false) -> void:
	status.text = text
	status.add_theme_color_override("font_color", ConsoleUI.AMBER if waiting else (ConsoleUI.TEAL if ok else ConsoleUI.RED))

func request_close() -> void:
	if discard_dialog.visible or import_dialog.visible or file_dialog.visible: return
	if is_dirty() or pending or _awaiting_snapshot:
		discard_dialog.dialog_text = "Cerrar descartará el borrador local sin aplicar. Exportar una plantilla no aplica la ficha." + ("\nHay una solicitud sin confirmar: cerrar NO la cancela y el anfitrión puede aplicarla después." if pending or _awaiting_snapshot else "")
		discard_dialog.popup_centered(Vector2i(620, 210))
	else:
		queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_F4]:
		get_viewport().set_input_as_handled()
		request_close()

func _choose_import() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Importar plantilla · máximo 32 KiB"
	file_dialog.current_dir = OS.get_user_data_dir()
	file_dialog.current_file = ""
	file_dialog.popup_centered(Vector2i(820, 520))

func _choose_export() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.title = "Exportar solo campos editables · no es una partida"
	file_dialog.current_dir = OS.get_user_data_dir()
	file_dialog.current_file = "plantilla-personaje.json"
	file_dialog.popup_centered(Vector2i(820, 520))

func _file_selected(path: String) -> void:
	if file_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE:
		import_file(path)
	else:
		export_file(path)

func import_file(path: String) -> bool:
	var result = CharacterDocument.load_file(path)
	if not result.ok:
		_set_status(result.message + " El borrador no ha cambiado.", false)
		return false
	return import_document(result.document)

func import_document(value: Variant) -> bool:
	if pending:
		_set_status("Espera a la confirmación o al timeout antes de importar.", false)
		return false
	var result = CharacterDocument.validate(value)
	if not result.ok:
		_set_status(result.message + " El borrador no ha cambiado.", false)
		return false
	_staged_import = result.document.character.duplicate(true)
	if is_dirty() and _staged_import != read_document().character:
		import_dialog.popup_centered(Vector2i(620, 210))
	else:
		_accept_import()
	return true

func _accept_import() -> void:
	if _staged_import.is_empty() or pending: return
	_set_fields(_staged_import)
	_staged_import.clear()
	_refresh()
	_set_status("Plantilla importada al borrador. Revisa los valores y pulsa Aplicar; la progresión de la partida no se importa.", true)

func export_file(path: String) -> Dictionary:
	var result = CharacterDocument.save_file(path, read_document().character)
	_set_status(result.message, result.ok)
	return result
