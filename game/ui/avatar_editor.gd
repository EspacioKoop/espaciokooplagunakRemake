class_name AvatarEditor
extends Window

var service: Node
var fields: Dictionary = {}
var preview: AvatarPortrait
var portrait: AvatarPortrait
var status: Label

func _ready() -> void:
	title = "Mi avatar"
	initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	size = Vector2i(760, 600)
	min_size = Vector2i(620, 520)
	theme = ConsoleUI.make_theme()
	close_requested.connect(queue_free)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 20)
	add_child(margin)
	var column = ConsoleUI.column(margin, 8)
	column.add_child(ConsoleUI.label("Tu presencia a bordo", 26))
	column.add_child(ConsoleUI.paragraph("Elige tu traje, visor y equipo. Se conservan al reiniciar y se comparten con la tripulación conectada.", 15))
	var row = ConsoleUI.row(column, 20)
	ConsoleUI.expand(row)
	preview = AvatarPortrait.new()
	ConsoleUI.expand(preview)
	preview.custom_minimum_size = Vector2(220, 220)
	row.add_child(preview)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x = 280
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(scroll)
	var settings = ConsoleUI.column(scroll, 8)
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait = AvatarPortrait.new()
	portrait.portrait = true
	portrait.custom_minimum_size = Vector2(100, 96)
	settings.add_child(portrait)
	for entry in [["suit", "Traje", AvatarProfile.SUITS], ["visor", "Visor", AvatarProfile.VISORS], ["gear", "Equipo cosmético", AvatarProfile.GEAR]]:
		settings.add_child(ConsoleUI.label(entry[1], 14))
		var choice = OptionButton.new()
		choice.custom_minimum_size.y = 36
		for key in entry[2]:
			choice.add_item(entry[2][key])
			choice.set_item_metadata(choice.item_count - 1, key)
		choice.item_selected.connect(func(_index): _preview())
		settings.add_child(choice)
		fields[entry[0]] = choice
	var turn_row = ConsoleUI.row(settings)
	turn_row.add_child(ConsoleUI.button("↶ Girar", func(): preview.turn(-PI / 4)))
	turn_row.add_child(ConsoleUI.button("Girar ↷", func(): preview.turn(PI / 4)))
	status = ConsoleUI.paragraph(service.load_message, 14)
	column.add_child(status)
	var actions = ConsoleUI.row(column)
	actions.add_child(ConsoleUI.button("Restablecer Itsaso", func(): set_profile(AvatarProfile.defaults())))
	actions.add_child(ConsoleUI.button("Cancelar", queue_free))
	actions.add_child(ConsoleUI.button("Guardar avatar", _save, true))
	set_profile(service.local_profile)
	fields.suit.grab_focus()

func set_profile(value: Dictionary) -> void:
	for key in fields:
		for index in fields[key].item_count:
			if fields[key].get_item_metadata(index) == value[key]: fields[key].select(index)
	_preview()

func read_profile() -> Dictionary:
	var value = AvatarProfile.defaults()
	for key in fields: value[key] = fields[key].get_selected_metadata()
	return value

func _preview() -> void:
	var value = read_profile()
	preview.set_profile(value)
	portrait.set_profile(value)

func _save() -> void:
	var result = service.save_local(read_profile())
	status.text = result.message
	status.add_theme_color_override("font_color", ConsoleUI.TEAL if result.ok else ConsoleUI.RED)
