class_name AssistanceTrainingWindow
extends Window

var training = AssistanceTraining.new()
var console: AssistanceConsole
var seed_input: SpinBox
var guide: Label
var progress: Label

func _ready() -> void:
 title = "Entrenamiento de asistencia · simulación local"
 min_size = Vector2i(640, 480)
 size = Vector2i(960, 800)
 theme = ConsoleUI.make_theme()
 close_requested.connect(queue_free)
 var background = PanelContainer.new()
 background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(background)
 var scroll = ScrollContainer.new()
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 background.add_child(scroll)
 var content = ConsoleUI.column(scroll)
 content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 content.add_child(ConsoleUI.label("Campo de prácticas", 28, ConsoleUI.TEAL))
 content.add_child(ConsoleUI.paragraph("Mando ayuda a Ingeniería en una nave desechable. No se guardan resultados ni se envían órdenes a la red. La partida real sigue su curso; este panel no la pausa.", 16))
 var row = ConsoleUI.row(content)
 row.add_child(ConsoleUI.label("Semilla"))
 seed_input = SpinBox.new()
 seed_input.min_value = 1
 seed_input.max_value = AssistanceTraining.MAX_SEED
 seed_input.step = 1
 seed_input.value = training.practice_seed
 seed_input.custom_minimum_size.x = 150
 row.add_child(seed_input)
 row.add_child(ConsoleUI.button("Repetir semilla", restart))
 row.add_child(ConsoleUI.button("Siguiente semilla", _next_seed))
 guide = ConsoleUI.paragraph(training.guidance(), 17, ConsoleUI.AMBER)
 content.add_child(guide)
 progress = ConsoleUI.paragraph("", 15)
 content.add_child(progress)
 console = AssistanceConsole.new()
 console.name = "TrainingConsole"
 console.training = training
 content.add_child(console)
 content.add_child(ConsoleUI.button("Cerrar entrenamiento", queue_free))
 console.start_button.grab_focus()
 _refresh_guidance()

func restart() -> void:
 seed_input.apply()
 _reset_recipe(seed_input.value)

func _reset_recipe(value: float) -> void:
 var response = training.reset(Cooperation.MODES[console.chooser.selected], value)
 console._notice(response.message, response.ok)
 console._refresh()
 _refresh_guidance()

func _next_seed() -> void:
 seed_input.value = 1 if training.practice_seed >= AssistanceTraining.MAX_SEED else training.practice_seed + 1
 # Programmatic value changes need no text submission; apply() could restore
 # the previous edit text before SpinBox refreshes it.
 _reset_recipe(seed_input.value)

func _process(_delta: float) -> void:
 _refresh_guidance()

func _refresh_guidance() -> void:
 if guide == null: return
 guide.text = training.guidance()
 progress.text = "Completadas en este entrenamiento: %d/4 · Se conserva el resultado de cada modo hasta cerrar esta ventana." % training.completed_modes.size()

func _unhandled_key_input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
  set_input_as_handled()
  queue_free()
