class_name ScorePanel
extends Window
var score: ReactiveScore
var enabled: CheckBox
var volume: HSlider
var mode_menu: OptionButton
var status: Label
var _syncing = false

func _ready() -> void:
	title = "Música de a bordo"
	min_size = Vector2i(440, 300)
	transient = true
	exclusive = true
	unresizable = false
	theme = ConsoleUI.make_theme()
	close_requested.connect(hide)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 20)
	add_child(margin)
	var column = ConsoleUI.column(margin, 12)
	enabled = CheckBox.new()
	enabled.text = "Activar música procedural"
	column.add_child(enabled)
	column.add_child(ConsoleUI.label("Volumen de música", 17))
	volume = HSlider.new()
	volume.max_value = 100
	volume.step = 1
	volume.custom_minimum_size.y = 32
	column.add_child(volume)
	mode_menu = OptionButton.new()
	mode_menu.add_item("Automática · sigue a la nave y la cubierta")
	for value in ScoreComposer.THEMES: mode_menu.add_item(ScoreComposer.TITLES[value])
	column.add_child(mode_menu)
	status = ConsoleUI.label("", 15, ConsoleUI.TEAL)
	column.add_child(status)
	column.add_child(ConsoleUI.paragraph("El volumen general sigue controlando toda la mezcla. Puedes apagar sólo la música y conservar los avisos de la nave.", 15))
	column.add_child(ConsoleUI.button("Cerrar", hide))
	enabled.toggled.connect(func(_value): _apply())
	volume.value_changed.connect(func(_value): _apply())
	mode_menu.item_selected.connect(func(_value): _apply())
	score.changed.connect(sync)
	sync()

func sync() -> void:
	if enabled == null: return
	_syncing = true
	enabled.button_pressed = score.preferences.enabled
	volume.value = score.preferences.volume
	mode_menu.select((["auto"] + ScoreComposer.THEMES).find(score.preferences.mode))
	status.text = "Ahora: " + str(ScoreComposer.TITLES[score.current_theme]) if score.preferences.enabled else "Música desactivada"
	_syncing = false

func _apply() -> void:
	if _syncing: return
	var error = score.update_preferences({"version": 1, "enabled": enabled.button_pressed, "volume": volume.value, "mode": (["auto"] + ScoreComposer.THEMES)[mode_menu.selected]}, "--test" not in OS.get_cmdline_user_args())
	if not error.is_empty(): status.text = error
