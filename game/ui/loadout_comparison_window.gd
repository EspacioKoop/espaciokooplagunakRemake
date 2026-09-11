class_name LoadoutComparisonWindow
extends Window
## Local preview only: never applies a draft, emits commands or reads the clipboard.

var baseline: Dictionary = {}
var source: TextEdit
var report: TextEdit
var status: Label
var dialog: FileDialog
var last_result: Dictionary = {}

func _init() -> void:
 visible = false
 transient = true
 exclusive = true

func _ready() -> void:
 title = "Astillero · comparar montajes"
 size = Vector2i(800, 640)
 min_size = Vector2i(560, 440)
 close_requested.connect(queue_free)
 var margin = MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for edge in ["left", "right", "top", "bottom"]:
  margin.add_theme_constant_override("margin_" + edge, 16)
 add_child(margin)
 var column = ConsoleUI.column(margin, 8)
 column.add_child(ConsoleUI.paragraph("Compara los montajes actuales con un archivo de nave. No importa ni aplica cambios. La estructura no se compara.", 14))
 var actions = ConsoleUI.row(column, 8)
 actions.add_child(ConsoleUI.button("Leer archivo…", _choose_file))
 actions.add_child(ConsoleUI.button("Comparar", _compare_source, true))
 actions.add_child(ConsoleUI.button("Cerrar", queue_free))
 column.add_child(ConsoleUI.label("JSON de nave · lagunak-ship v1/v2 · máximo 64 KiB", 13))
 source = TextEdit.new()
 source.custom_minimum_size.y = 90
 source.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
 source.placeholder_text = "Pega aquí el JSON o elige un archivo local."
 column.add_child(source)
 source.text_changed.connect(_invalidate)
 status = ConsoleUI.paragraph("Elige un archivo o pega su contenido y pulsa Comparar.", 13)
 column.add_child(status)
 report = TextEdit.new()
 report.editable = false
 report.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
 ConsoleUI.expand(report)
 column.add_child(report)
 dialog = FileDialog.new()
 dialog.access = FileDialog.ACCESS_FILESYSTEM
 dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
 dialog.filters = PackedStringArray(["*.json ; Diseño de nave"])
 dialog.file_selected.connect(compare_file)
 add_child(dialog)

func configure(value: Dictionary) -> void:
 baseline = value.duplicate(true)
 if is_node_ready(): _invalidate()

func compare_text(text: String) -> Dictionary:
 last_result = LoadoutComparison.compare_text(baseline, text)
 report.text = LoadoutComparison.plain_report(last_result)
 status.text = "Archivo rechazado; no se ha cambiado nada." if last_result.has("error") else "Comparación lista. No se ha importado ni aplicado nada."
 return last_result.duplicate(true)

func compare_file(path: String) -> void:
 var file = FileAccess.open(path, FileAccess.READ)
 if file == null:
  _file_error("No se pudo abrir el archivo local.")
  return
 if file.get_length() > LoadoutDocument.MAX_BYTES:
  file.close()
  _file_error("El diseño supera 64 KiB.")
  return
 var text = file.get_as_text()
 file.close()
 source.text = text
 compare_text(text)

func _choose_file() -> void:
 dialog.popup_centered_clamped(Vector2i(720, 480))

func _compare_source() -> void:
 compare_text(source.text)

func _invalidate() -> void:
 last_result.clear()
 report.text = ""
 status.text = "Contenido sin comparar. Pulsa Comparar para actualizar el resultado."

func _file_error(message: String) -> void:
 last_result = {"error": message}
 report.text = LoadoutComparison.plain_report(last_result)
 status.text = "Archivo rechazado; no se ha cambiado nada."

func _unhandled_key_input(event: InputEvent) -> void:
 if event.is_action_pressed("ui_cancel"):
  set_input_as_handled()
  queue_free()
