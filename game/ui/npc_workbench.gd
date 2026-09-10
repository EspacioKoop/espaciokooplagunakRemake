class_name NpcWorkbench
extends Window
## Local authoring only. No calls to campaign, peers, profiles or Foundry.

var seed_field: LineEdit
var challenge_field: OptionButton
var preview: TextEdit
var status: Label
var export_button: Button
var text_button: Button
var file_dialog: FileDialog
var document: Dictionary = {}
var _file_mode = ""
var _loading = false

func _ready() -> void:
	title = "Taller de NPC · fichas locales"
	size = Vector2i(880, 700)
	min_size = Vector2i(620, 480)
	transient = true
	exclusive = true
	theme = ConsoleUI.make_theme()
	close_requested.connect(queue_free)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)
	var body = ConsoleUI.column(margin, 10)
	body.add_child(ConsoleUI.label("GENERADOR DE NPC", 24, ConsoleUI.TEAL))
	body.add_child(ConsoleUI.paragraph("Misma semilla y VD, misma ficha. Herramienta de dirección local: no modifica la partida ni envía datos.", 15))
	var form = ConsoleUI.row(body, 10)
	form.add_child(ConsoleUI.label("Semilla", 15))
	seed_field = LineEdit.new()
	seed_field.name = "Seed"
	seed_field.max_length = 10
	seed_field.custom_minimum_size.x = 160
	seed_field.text = "1"
	form.add_child(seed_field)
	seed_field.text_changed.connect(func(_text): _mark_dirty())
	seed_field.text_submitted.connect(func(_text): generate_preview())
	form.add_child(ConsoleUI.label("VD", 15))
	challenge_field = OptionButton.new()
	challenge_field.name = "Challenge"
	for value in NpcGenerator.challenges():
		var label = "1/8" if value == 0.125 else "1/4" if value == 0.25 else "1/2" if value == 0.5 else str(int(value))
		challenge_field.add_item(label)
		challenge_field.set_item_metadata(challenge_field.item_count - 1, value)
	challenge_field.select(4)
	form.add_child(challenge_field)
	challenge_field.item_selected.connect(func(_index): _mark_dirty())
	var generate_button = ConsoleUI.button("Generar ficha", generate_preview, true)
	generate_button.name = "GenerateNpc"
	form.add_child(generate_button)
	preview = TextEdit.new()
	preview.name = "NpcSheet"
	preview.editable = false
	preview.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	preview.custom_minimum_size.y = 160
	ConsoleUI.expand(preview)
	body.add_child(preview)
	var actions = HFlowContainer.new()
	body.add_child(actions)
	var import_button = ConsoleUI.button("Abrir ficha JSON…", func(): _choose_file("import"))
	actions.add_child(import_button)
	export_button = ConsoleUI.button("Exportar JSON…", func(): _choose_file("json"))
	actions.add_child(export_button)
	text_button = ConsoleUI.button("Exportar texto…", func(): _choose_file("text"))
	actions.add_child(text_button)
	actions.add_child(ConsoleUI.button("Cerrar", queue_free))
	status = ConsoleUI.paragraph("", 14)
	status.custom_minimum_size.y = 46
	body.add_child(status)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = false
	file_dialog.file_selected.connect(_file_selected)
	add_child(file_dialog)
	generate_preview()
	seed_field.grab_focus()

func _set_status(message: String, success: bool) -> void:
	status.text = message
	status.add_theme_color_override("font_color", ConsoleUI.TEAL if success else ConsoleUI.AMBER)

func _mark_dirty() -> void:
	if _loading: return
	export_button.disabled = true
	text_button.disabled = true
	_set_status("Parámetros cambiados. Genera la nueva ficha antes de exportar.", false)

func generate_preview() -> bool:
	var seed_text = seed_field.text
	if seed_text.is_empty() or seed_text.length() > 10:
		return _reject_seed()
	for index in seed_text.length():
		var code = seed_text.unicode_at(index)
		if code < 48 or code > 57: return _reject_seed()
	var result = NpcGenerator.generate(seed_text.to_int(), challenge_field.get_selected_metadata())
	if not result.ok:
		_mark_dirty()
		_set_status(result.error, false)
		return false
	_accept_document(result.document)
	return true

func _reject_seed() -> bool:
	_mark_dirty()
	_set_status("Escribe una semilla entera entre 0 y 2147483647, solo con cifras.", false)
	return false

func _accept_document(value: Dictionary) -> void:
	document = value.duplicate(true)
	_loading = true
	seed_field.text = str(document.recipe.seed)
	for index in challenge_field.item_count:
		if challenge_field.get_item_metadata(index) == document.recipe.challenge:
			challenge_field.select(index)
			break
	_loading = false
	preview.text = NpcGenerator.describe(document)
	export_button.disabled = false
	text_button.disabled = false
	_set_status("Ficha reproducible lista. Exportar guarda solo este NPC; no una partida ni datos de la tripulación.", true)

func _choose_file(mode: String) -> void:
	if mode != "import" and export_button.disabled: return
	_file_mode = mode
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if mode == "import" else FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.filters = PackedStringArray(["*.txt ; Ficha NPC legible"]) if mode == "text" else PackedStringArray(["*.json ; Ficha NPC versionada"])
	file_dialog.current_file = "" if mode == "import" else "npc-%d.%s" % [document.recipe.seed, "txt" if mode == "text" else "json"]
	file_dialog.popup_centered_clamped(Vector2i(780, 560), 0.9)

func _file_selected(path: String) -> void:
	if _file_mode == "import":
		import_file(path)
	else:
		export_file(path, _file_mode == "text")

func import_file(path: String) -> bool:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_status("No se ha podido abrir el archivo.", false)
		return false
	var length = file.get_length()
	if length <= 0 or length > NpcGenerator.MAX_BYTES:
		file.close()
		_set_status("La ficha debe ocupar entre 1 byte y 64 KiB.", false)
		return false
	var bytes = file.get_buffer(length)
	var read_error = file.get_error()
	file.close()
	if bytes.size() != length or (read_error != OK and read_error != ERR_FILE_EOF):
		_set_status("No se ha podido leer la ficha completa.", false)
		return false
	var result = NpcGenerator.decode_bytes(bytes)
	if not result.ok:
		_set_status(result.error + " Se conserva la ficha anterior.", false)
		return false
	_accept_document(result.document)
	return true

func export_file(path: String, as_text: bool = false) -> bool:
	if document.is_empty() or export_button.disabled:
		_set_status("Genera la ficha antes de exportar.", false)
		return false
	var valid = NpcGenerator.validate_document(document)
	if not valid.ok:
		_set_status(valid.error, false)
		return false
	var content = NpcGenerator.describe(valid.document) if as_text else JSON.stringify(valid.document, "  ", true)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("No se ha podido crear el archivo. Comprueba la carpeta y sus permisos.", false)
		return false
	file.store_string(content + "\n")
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		_set_status("La escritura no se ha completado. El archivo puede estar incompleto.", false)
		return false
	_set_status("Ficha exportada al archivo elegido. No se ha enviado ningún dato a la red.", true)
	return true
