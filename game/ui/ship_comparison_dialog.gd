class_name ShipComparisonDialog
extends Window
## A read-only snapshot of the current draft. No Session reference or apply signal.

var source_design: Dictionary = {}
var report: TextEdit
var status: Label
var file_dialog: FileDialog

func _ready() -> void:
 title = "Astillero · comparar estructura"
 size = Vector2i(860, 620)
 min_size = Vector2i(640, 420)
 close_requested.connect(queue_free)
 var margin = MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for edge in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 18)
 add_child(margin)
 var column = ConsoleUI.column(margin, 10)
 column.add_child(ConsoleUI.label("Comparar estructura de nave", 24))
 column.add_child(ConsoleUI.paragraph("La base es el borrador al abrir esta ventana. Para comparar un borrador posterior, cierra y vuelve a abrir. Nada se importa ni se aplica a la misión.", 14))
 var tools = ConsoleUI.row(column)
 tools.add_child(ConsoleUI.button("Elegir archivo local", _choose_file, true))
 tools.add_child(ConsoleUI.button("Cerrar", queue_free))
 status = ConsoleUI.paragraph("Selecciona una nave JSON v1 o v2, de hasta 64 KiB.", 14)
 column.add_child(status)
 report = TextEdit.new()
 report.name = "StructureReport"
 report.editable = false
 report.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
 report.add_theme_font_size_override("font_size", 15)
 ConsoleUI.expand(report)
 column.add_child(report)
 report.text = ShipConfigurationDiff.SCOPE
 file_dialog = FileDialog.new()
 file_dialog.access = FileDialog.ACCESS_FILESYSTEM
 file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
 file_dialog.filters = PackedStringArray(["*.json ; Diseño de nave"])
 file_dialog.file_selected.connect(load_file)
 add_child(file_dialog)

func _choose_file() -> void:
 file_dialog.popup_centered(Vector2i(780, 560))

func load_file(path: String) -> void:
 var result = ShipConfigurationDiff.compare_file(source_design, path)
 # Replace previous results on failure; a stale successful diff is misleading.
 report.text = ShipConfigurationDiff.to_text(result)
 status.text = "Archivo rechazado; el borrador permanece intacto." if result.has("error") else "%d diferencias estructurales. No se ha importado nada." % result.changes.size()
