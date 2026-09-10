class_name SessionReportDialog
extends Window
## A frozen projection of the caller's visible state, never a live save object.

var report: Dictionary = {}
var preview: TextEdit
var status: Label
var format_choice: OptionButton
var save_button: Button
var file_dialog: FileDialog
var _pending_kind = "md"

func configure(view: Dictionary, expedition: Dictionary) -> void:
	report = SessionReport.capture(view, expedition)
	if is_node_ready():
		_refresh_preview()

func _ready() -> void:
	title = "Exportar crónica de sesión"
	size = Vector2i(900, 560)
	min_size = Vector2i(680, 400)
	transient = true
	exclusive = true
	theme = ConsoleUI.make_theme()
	close_requested.connect(queue_free)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)
	var column = ConsoleUI.column(margin, 10)
	column.add_child(ConsoleUI.label("CRÓNICA DE SESIÓN", 23, ConsoleUI.TEAL))
	column.add_child(ConsoleUI.paragraph("Exportación local: no se envía nada a Internet. Revisa los nombres y textos de juego antes de compartir el archivo.", 14))
	column.add_child(ConsoleUI.paragraph("Captura fija de la misión y los registros retenidos (hasta 200 eventos y 300 entradas de crónica). No es el historial completo, un guardado ni un replay.", 13, ConsoleUI.MUTED))
	var row = ConsoleUI.row(column)
	row.add_child(ConsoleUI.label("Formato", 14))
	format_choice = OptionButton.new()
	format_choice.add_item("Markdown · lectura e impresión")
	format_choice.add_item("JSON · documento versionado")
	format_choice.item_selected.connect(func(_index): _refresh_preview())
	row.add_child(format_choice)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	save_button = ConsoleUI.button("Guardar archivo…", _choose_path, true)
	save_button.name = "SaveSessionReport"
	row.add_child(save_button)
	row.add_child(ConsoleUI.button("Cerrar", queue_free))
	preview = TextEdit.new()
	preview.name = "SessionReportPreview"
	preview.editable = false
	preview.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	ConsoleUI.expand(preview)
	column.add_child(preview)
	status = ConsoleUI.label("Elige un nombre nuevo: no se sobrescriben archivos existentes.", 13, ConsoleUI.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	file_dialog = FileDialog.new()
	file_dialog.name = "SessionReportFileDialog"
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.title = "Guardar informe local con nombre nuevo"
	file_dialog.size = Vector2i(760, 440)
	file_dialog.file_selected.connect(_save_selected)
	add_child(file_dialog)
	_refresh_preview()

func _kind() -> String:
	return "json" if format_choice != null and format_choice.selected == 1 else "md"

func _refresh_preview() -> void:
	if preview == null:
		return
	var valid = bool(report.get("ok", false))
	save_button.disabled = not valid
	format_choice.disabled = not valid
	preview.text = str(report.get("json" if _kind() == "json" else "markdown", "")) if valid else ""
	if not valid:
		_show_result({"ok": false, "message": report.get("message", "Abre una misión antes de exportar.")})

func _choose_path() -> void:
	if not report.get("ok", false):
		return
	var directory = ProjectSettings.globalize_path("user://session-reports")
	var error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		_show_result({"ok": false, "message": "No se pudo crear la carpeta local: " + error_string(error)})
		return
	_pending_kind = _kind()
	file_dialog.clear_filters()
	file_dialog.add_filter("*." + _pending_kind, "Informe " + _pending_kind.to_upper())
	file_dialog.current_dir = directory
	var stamp = Time.get_datetime_string_from_system(true).replace(":", "-")
	file_dialog.current_file = "sesion-" + stamp + "-" + str(Time.get_ticks_msec()) + "." + _pending_kind
	file_dialog.popup_centered()

func save_to(path: String, kind: String) -> Dictionary:
	if not report.get("ok", false) or kind not in ["md", "json"]:
		var invalid = {"ok": false, "message": "No hay un informe válido del formato solicitado."}
		_show_result(invalid)
		return invalid
	var result = SessionReport.write_new(path, str(report.get("json" if kind == "json" else "markdown", "")), kind)
	_show_result(result)
	return result

func _save_selected(path: String) -> void:
	save_to(path, _pending_kind)

func _show_result(result: Dictionary) -> void:
	if status == null:
		return
	status.text = str(result.get("message", "No se pudo exportar."))
	status.add_theme_color_override("font_color", ConsoleUI.TEAL if result.get("ok", false) else ConsoleUI.RED)
