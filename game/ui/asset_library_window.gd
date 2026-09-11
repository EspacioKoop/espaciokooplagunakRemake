class_name AssetLibraryWindow
extends Window
## Native consumer of the curated library. Preview does not grant game abilities.
var search: LineEdit
var listing: ItemList
var details: Label
var preview: AssetPreview
var _rows: Array = []
var _shown: Array = []

func _ready() -> void:
	title = "Biblioteca 3D · recursos del proyecto"
	size = Vector2i(1140, 720)
	min_size = Vector2i(700, 480)
	transient = true
	exclusive = true
	theme = ConsoleUI.make_theme()
	close_requested.connect(queue_free)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 20)
	add_child(margin)
	var body = ConsoleUI.column(margin, 12)
	body.add_child(ConsoleUI.label("BIBLIOTECA 3D", 25, ConsoleUI.TEAL))
	body.add_child(ConsoleUI.paragraph("Modelos reales del repositorio. Inspección local: no cambia la campaña, el inventario ni las capacidades de tu personaje.", 15))
	search = LineEdit.new()
	search.placeholder_text = "Buscar nombre, colección, categoría o identificador…"
	search.name = "AssetSearch"
	search.max_length = 128
	body.add_child(search)
	var split = HSplitContainer.new()
	ConsoleUI.expand(split)
	body.add_child(split)
	listing = ItemList.new()
	listing.name = "AssetList"
	listing.custom_minimum_size.x = 300
	listing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(listing)
	var right = ConsoleUI.column(split, 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview = AssetPreview.new()
	preview.name = "AssetPreview"
	right.add_child(preview)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 130
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right.add_child(scroll)
	details = ConsoleUI.paragraph("", 14)
	details.name = "AssetDetails"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(details)
	var controls = ConsoleUI.row(body, 10)
	var animate = CheckButton.new()
	animate.text = "Reproducir animaciones disponibles"
	animate.toggled.connect(func(value): preview.set_animation(value))
	controls.add_child(animate)
	controls.add_child(ConsoleUI.button("Recentrar", preview.reset_view))
	controls.add_child(ConsoleUI.button("Cerrar biblioteca", queue_free))
	listing.item_selected.connect(func(index):
		animate.set_pressed_no_signal(false)
		select_asset(index))
	search.text_changed.connect(func(_value):
		animate.set_pressed_no_signal(false)
		_filter())
	_rows = RuntimeAssetLibrary.entries()
	_filter()
	search.grab_focus()

func _filter() -> void:
	_shown.clear()
	listing.clear()
	var query = search.text.strip_edges().to_lower()
	for row in _rows:
		if not query.is_empty() and not (row.title + " " + row.category + " " + row.id).to_lower().contains(query): continue
		_shown.append(row)
		listing.add_item(row.title)
		listing.set_item_tooltip(listing.item_count - 1, row.id + " · " + row.category)
	if not _shown.is_empty():
		listing.select(0)
		select_asset(0)
	else:
		details.text = "No hay modelos que coincidan con la búsqueda."
		if is_instance_valid(preview.model): preview.model.visible = false

func select_asset(index: int) -> void:
	if index < 0 or index >= _shown.size(): return
	var row: Dictionary = _shown[index]
	if not preview.show_asset(row.id):
		details.text = "No se pudo cargar este recurso. Comprueba su instalación."
		return
	var dimensions = preview.extent.size
	details.text = "%s\n%s · %s\n%s\nDimensiones de recurso: %.3f × %.3f × %.3f\nGLB: %s\nBlender: %s\nLicencia: %s\nBotón derecho: girar · rueda: acercar/alejar" % [
		row.title, row.id, row.category, row.description,
		dimensions.x, dimensions.y, dimensions.z, row.resource, row.source, row.license]

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()
	elif event is InputEventKey and event.keycode >= KEY_F1 and event.keycode <= KEY_F12:
		set_input_as_handled()
