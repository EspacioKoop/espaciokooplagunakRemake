class_name MissionBriefingWindow
extends Window
## Root-owned so refreshing or closing the crew console cannot destroy a dialog.

const WINDOW_GROUP = "mission_briefing_windows"
var session: Node
var station_menu: OptionButton
var format_menu: OptionButton
var preview: TextEdit
var status: Label
var save_button: Button
var file_dialog: FileDialog
var prepared: Dictionary = {}
var _pending: Dictionary = {}

static func open_for(tree: SceneTree) -> MissionBriefingWindow:
	for window in tree.get_nodes_in_group(WINDOW_GROUP):
		if window is MissionBriefingWindow and not window.is_queued_for_deletion():
			window.grab_focus()
			return window
	var window = MissionBriefingWindow.new()
	window.session = tree.root.get_node_or_null("Session")
	tree.root.add_child(window)
	window.popup_centered(Vector2i(1000, 720))
	return window

func _ready() -> void:
	add_to_group(WINDOW_GROUP)
	title = "Briefing de misión · preparación por puesto"
	size = Vector2i(1000, 720)
	min_size = Vector2i(680, 480)
	transient = true
	theme = ConsoleUI.make_theme()
	close_requested.connect(queue_free)
	if session == null: session = get_tree().root.get_node_or_null("Session")
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 18)
	add_child(margin)
	var body = ConsoleUI.column(margin, 12)
	body.add_child(ConsoleUI.label("PREPARAR LA MISIÓN", 24, ConsoleUI.TEAL))
	body.add_child(ConsoleUI.paragraph("Elige una guía de puesto sin cambiar tu asiento ni tus permisos. Solo se incluye texto visible de la misión actual; no contactos, bitácora, fichas ni claves.", 15))
	var controls = ConsoleUI.row(body, 10)
	controls.add_child(ConsoleUI.label("Puesto", 15, ConsoleUI.MUTED))
	station_menu = OptionButton.new()
	for role in Catalog.ROLES:
		station_menu.add_item(Catalog.role_name(role))
		station_menu.set_item_metadata(station_menu.item_count - 1, role)
	if session != null:
		var initial = Catalog.ROLES.find(str(session.role))
		station_menu.select(maxi(0, initial))
	controls.add_child(station_menu)
	format_menu = OptionButton.new()
	for item in [["Markdown (.md)", "md"], ["HTML imprimible (.html)", "html"], ["Datos JSON (.json)", "json"]]:
		format_menu.add_item(item[0])
		format_menu.set_item_metadata(format_menu.item_count - 1, item[1])
	controls.add_child(format_menu)
	controls.add_child(ConsoleUI.button("Actualizar", refresh_preview))
	station_menu.item_selected.connect(func(_index: int): refresh_preview())
	format_menu.item_selected.connect(func(_index: int): refresh_preview())
	preview = TextEdit.new()
	preview.editable = false
	preview.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(preview)
	body.add_child(ConsoleUI.paragraph("Vista previa en Markdown. Para imprimir: guarda como HTML, abre ese archivo local en tu navegador y usa Imprimir. El juego no abre el navegador ni envía el documento a ningún servicio.", 13))
	var actions = ConsoleUI.row(body, 10)
	save_button = ConsoleUI.button("Guardar briefing…", choose_file, true)
	actions.add_child(save_button)
	actions.add_child(ConsoleUI.button("Cerrar", queue_free))
	status = ConsoleUI.label("", 13, ConsoleUI.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	file_dialog = FileDialog.new()
	file_dialog.title = "Guardar briefing local (no sobrescribe archivos)"
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.file_selected.connect(save_selected)
	file_dialog.canceled.connect(cancel_save)
	add_child(file_dialog)
	refresh_preview()

func refresh_preview() -> void:
	prepared = {}
	preview.text = ""
	save_button.disabled = true
	if not is_instance_valid(session) or not session.view is Dictionary:
		_set_status("No hay una sesión disponible.", false)
		return
	var role = str(station_menu.get_item_metadata(station_menu.selected))
	var extension = str(format_menu.get_item_metadata(format_menu.selected))
	# Session.view is already recipient-scoped; the builder further allowlists it.
	prepared = MissionBriefing.render(session.view, role, extension)
	if not prepared.ok:
		_set_status(prepared.message, false)
		return
	var readable = MissionBriefing.render(session.view, role, "md")
	preview.text = readable.text
	save_button.disabled = false
	_set_status("Instantánea preparada. Actualiza para incorporar cambios de objetivos. Revisa el texto antes de compartirlo.", true)

func choose_file() -> void:
	if prepared.get("ok") != true: return
	# The chosen file always receives the previewed instant, not a later update.
	_pending = prepared.duplicate(true)
	var extension = str(_pending.extension)
	file_dialog.filters = PackedStringArray(["*.%s ; Briefing %s" % [extension, extension.to_upper()]])
	var folder = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder): folder = ProjectSettings.globalize_path("user://")
	file_dialog.current_dir = folder
	var role = str(station_menu.get_item_metadata(station_menu.selected))
	file_dialog.current_file = "briefing_%s_%d_%d.%s" % [role, int(Time.get_unix_time_from_system()), Time.get_ticks_msec(), extension]
	file_dialog.popup_centered(Vector2i(840, 540))

func save_selected(path: String) -> Dictionary:
	var result = MissionBriefing.write_new(path, _pending)
	_pending = {}
	_set_status(result.message, result.ok)
	return result

func cancel_save() -> void:
	_pending = {}
	_set_status("Exportación cancelada. No se ha escrito ningún archivo.", true)

func _set_status(text: String, ok: bool) -> void:
	status.text = text
	status.add_theme_color_override("font_color", ConsoleUI.MUTED if ok else ConsoleUI.RED)
