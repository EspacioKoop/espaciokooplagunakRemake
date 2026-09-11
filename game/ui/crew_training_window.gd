class_name CrewTrainingWindow
extends Window
## A local teaching surface; no connection to the live Session.
var model = CrewTraining.new()
var lessons: OptionButton
var roles: OptionButton
var operations: OptionButton
var form: VBoxContainer
var inputs: Dictionary = {}
var guide: Label
var telemetry: Label
var journal: Label
var feedback: Label
var progress: Label
var progress_bar: ProgressBar
var send_button: Button
var pause_button: Button
var _clock = 0.0

func _ready() -> void:
 transient = true
 exclusive = true
 title = "Escuela de tripulación · simulación local"
 min_size = Vector2i(620, 480)
 size = Vector2i(940, 860)
 theme = ConsoleUI.make_theme()
 close_requested.connect(queue_free)
 var background = PanelContainer.new()
 background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(background)
 var scroll = ScrollContainer.new()
 scroll.follow_focus = true
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 background.add_child(scroll)
 var content = ConsoleUI.column(scroll)
 content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 content.add_child(ConsoleUI.label("Aprende a llevar la Itsaso", 28, ConsoleUI.TEAL))
 content.add_child(ConsoleUI.paragraph("Primera misión guiada y ocho prácticas. Selecciona el puesto, la orden y sus parámetros. La nave real sigue su curso: esta ventana sólo maneja una simulación desechable, sin guardar ni enviar órdenes.", 16))
 lessons = OptionButton.new()
 lessons.name = "Lesson"
 for id in CrewTraining.lesson_ids():
  lessons.add_item(CrewTraining.lesson_name(id))
  lessons.set_item_metadata(lessons.item_count - 1, id)
 content.add_child(lessons)
 lessons.item_selected.connect(_select_lesson)
 var controls = HFlowContainer.new()
 content.add_child(controls)
 controls.add_child(ConsoleUI.button("Reiniciar recorrido", _restart))
 pause_button = ConsoleUI.button("Pausar simulación", _pause)
 controls.add_child(pause_button)
 controls.add_child(ConsoleUI.button("Practicar los cuatro minijuegos", _open_assistance))
 progress = ConsoleUI.paragraph("", 16, ConsoleUI.TEAL)
 content.add_child(progress)
 progress_bar = ProgressBar.new()
 progress_bar.show_percentage = false
 progress_bar.custom_minimum_size.y = 12
 content.add_child(progress_bar)
 guide = ConsoleUI.paragraph("", 18, ConsoleUI.TEXT)
 content.add_child(guide)
 var selectors = GridContainer.new()
 selectors.columns = 2
 content.add_child(selectors)
 selectors.add_child(ConsoleUI.label("Tu puesto"))
 roles = OptionButton.new()
 roles.name = "Role"
 for id in Catalog.ROLES:
  roles.add_item(Catalog.role_name(id))
  roles.set_item_metadata(roles.item_count - 1, id)
 selectors.add_child(roles)
 roles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 roles.item_selected.connect(_select_role)
 selectors.add_child(ConsoleUI.label("Orden"))
 operations = OptionButton.new()
 operations.name = "Operation"
 selectors.add_child(operations)
 operations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 operations.item_selected.connect(_select_operation)
 form = ConsoleUI.column(content)
 send_button = ConsoleUI.button("Ejecutar en la nave de prácticas", _send, true)
 content.add_child(send_button)
 feedback = ConsoleUI.paragraph("Sigue la guía superior; cambiar de puesto no ejecuta ninguna orden.", 16)
 content.add_child(feedback)
 telemetry = ConsoleUI.paragraph("", 16, ConsoleUI.TEXT)
 content.add_child(telemetry)
 journal = ConsoleUI.paragraph("", 15)
 content.add_child(journal)
 content.add_child(ConsoleUI.paragraph("Cambiar de recorrido descarta esa nave de prácticas. Los recorridos completados se recuerdan sólo hasta cerrar esta ventana. Un ejercicio no concede XP, créditos ni recursos a tu campaña.", 15))
 content.add_child(ConsoleUI.button("Cerrar escuela", queue_free))
 _build_operations()
 _refresh()
 roles.grab_focus()

func _select_lesson(index: int) -> void:
 if index < 0 or index >= lessons.item_count: return
 _notice(model.reset(str(lessons.get_item_metadata(index))))
 roles.select(0)
 _build_operations()
 _refresh()

func _restart() -> void:
 _select_lesson(lessons.selected)

func _select_role(index: int) -> void:
 if index < 0 or index >= roles.item_count: return
 _notice(model.select_role(str(roles.get_item_metadata(index))))
 _build_operations()
 _refresh()

func _build_operations() -> void:
 operations.clear()
 for operation in CrewTraining.COMMANDS[model.role]:
  operations.add_item(str(CrewTraining.LABELS[operation]))
  operations.set_item_metadata(operations.item_count - 1, operation)
 operations.select(0)
 _select_operation(0)

func _select_operation(index: int) -> void:
 if index < 0 or index >= operations.item_count: return
 ConsoleUI.clear(form)
 inputs.clear()
 var operation = str(operations.get_item_metadata(index))
 match operation:
  "alert": _choice("level", "Nivel de alerta", [["verde", "Verde"], ["ambar", "Ámbar"], ["roja", "Roja"]])
  "mission_choice": _choice("choice", "Decisión", [["compartir", "Compartir"], ["reservar", "Reservar"]])
  "helm":
   _number("heading", "Rumbo (grados)", 0, 359, 1, 0)
   _number("throttle", "Impulso (−1 a 1)", -1, 1, 0.1, 0)
  "power":
   _system_choice()
   _number("value", "Potencia (0 a 4)", 0, 4, 1, 2)
  "coolant", "repair": _system_choice()
  "shields": _choice("enabled", "Escudos", [[true, "Activados"], [false, "Desactivados"]])
  "undock": form.add_child(ConsoleUI.paragraph("Libera las amarras si la misión sigue activa."))
  _:
   var choices: Array = []
   for contact in model.snapshot().contacts: choices.append([contact.id, contact.name])
   _choice("target", "Contacto", choices)

func _system_choice() -> void:
 var choices: Array = []
 for id in Catalog.SYSTEMS: choices.append([id, Catalog.SYSTEM_NAMES[id]])
 _choice("system", "Sistema", choices)

func _choice(key: String, label: String, choices: Array) -> void:
 var row = ConsoleUI.row(form)
 row.add_child(ConsoleUI.label(label))
 var selector = OptionButton.new()
 selector.name = key
 selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 for pair in choices:
  selector.add_item(str(pair[1]))
  selector.set_item_metadata(selector.item_count - 1, pair[0])
 row.add_child(selector)
 inputs[key] = selector

func _number(key: String, label: String, minimum: float, maximum: float, increment: float, initial: float) -> void:
 var row = ConsoleUI.row(form)
 row.add_child(ConsoleUI.label(label))
 var spinner = SpinBox.new()
 spinner.name = key
 spinner.min_value = minimum
 spinner.max_value = maximum
 spinner.step = increment
 spinner.value = initial
 spinner.custom_minimum_size.x = 150
 row.add_child(spinner)
 inputs[key] = spinner

func _send() -> void:
 if operations.selected < 0: return
 var args = {}
 for key in inputs:
  var input = inputs[key]
  if input is SpinBox:
   input.apply()
   args[key] = input.value
  elif input is OptionButton and input.selected >= 0:
   args[key] = input.get_item_metadata(input.selected)
 _notice(model.order(str(operations.get_item_metadata(operations.selected)), args))
 _refresh()

func _pause() -> void:
 model.set_paused(not model.paused)
 _refresh()

func _notice(result: Dictionary) -> void:
 if feedback == null: return
 feedback.text = ("Correcto: " if result.ok else "No ejecutado: ") + str(result.message)
 feedback.add_theme_color_override("font_color", ConsoleUI.TEAL if result.ok else ConsoleUI.AMBER)

func _process(delta: float) -> void:
 if not visible: return
 model.advance(minf(delta, 2.0))
 _clock += delta
 if _clock >= 0.2:
  _clock = 0.0
  _refresh()

func _refresh() -> void:
 if guide == null: return
 guide.text = model.guidance()
 progress.text = "%d/%d pasos · %d/9 recorridos completados en esta ventana" % [model.step_index, model.step_count(), model.completed.size()]
 progress_bar.max_value = model.step_count()
 progress_bar.value = model.step_index
 pause_button.text = "Reanudar simulación" if model.paused else "Pausar simulación"
 pause_button.disabled = model.phase != "playing"
 send_button.disabled = model.phase != "playing"
 var view = model.snapshot()
 var ship: Dictionary = view.ship
 var lines: Array[String] = [
  ("PAUSADA" if model.paused else "EN MARCHA") + " · Sólo la nave de prácticas",
  "Tiempo %.1f s · X %.0f / Y %.0f · rumbo %.0f° · velocidad %.1f m/s" % [view.time, ship.position[0], ship.position[1], ship.heading, ship.speed],
  "Casco %.0f/%.0f · energía %.0f · combustible %.0f · repuestos %d · sondas %d · torpedos %d" % [ship.hull, ship.max_hull, ship.energy, ship.fuel, ship.parts, ship.probes, ship.torpedoes],
  "Alerta %s · escudos %s · recarga %.1f s" % [str(ship.alert), "activos" if ship.shields_enabled else "bajos", maxf(0, float(ship.weapon_ready) - float(view.time))]
 ]
 for contact in view.contacts:
  var distance = Vector2(float(ship.position[0]), float(ship.position[1])).distance_to(Vector2(float(contact.position[0]), float(contact.position[1])))
  lines.append("%s · %.0f m · %s" % [contact.name, distance, "identificado, casco %.0f" % float(contact.hull) if contact.identified else "sin identificar"])
 if model.role in ["ingenieria", "reparaciones"]:
  for id in Catalog.SYSTEMS:
   var system: Dictionary = ship.systems[id]
   lines.append("%s: potencia %d · integridad %.0f %% · calor %.0f" % [Catalog.SYSTEM_NAMES[id], system.power, system.health, system.heat])
 telemetry.text = "\n".join(lines)
 var events: Array[String] = []
 for event in view.events.slice(maxi(0, view.events.size() - 4)):
  events.append("%s · %s" % [event.source, event.text])
 journal.text = "Bitácora de prácticas\n" + "\n".join(events)
 # Update newly identified labels without rebuilding the form or stealing focus.
 if inputs.has("target"):
  var selector: OptionButton = inputs.target
  for i in selector.item_count:
   for contact in view.contacts:
    if selector.get_item_metadata(i) == contact.id and selector.get_item_text(i) != contact.name:
     selector.set_item_text(i, contact.name)

func _open_assistance() -> void:
 var existing = get_node_or_null("AssistancePractice")
 if is_instance_valid(existing) and not existing.is_queued_for_deletion():
  existing.popup_centered()
  return
 var window = load("res://ui/assistance_training_window.gd").new()
 window.name = "AssistancePractice"
 window.transient = true
 window.exclusive = true
 add_child(window)
 window.popup_centered()

func _unhandled_key_input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
  set_input_as_handled()
  queue_free()
