class_name AssistanceConsole
extends VBoxContainer
## A training instance uses only its disposable model, never Session.order/notice.
var training: AssistanceTraining
var panel: Control
var controls: VBoxContainer
var readout: Label
var status: Label
var start_button: Button
var consume_button: Button
var chooser: OptionButton
var recipient: OptionButton
var current_id = ""
var task: Dictionary = {}
var _state_view: Dictionary = {}
var _clock = 0.0

func _ready() -> void:
 add_child(ConsoleUI.label("Ayudar a otro puesto" if training == null else "Practicar una asistencia", 27))
 add_child(ConsoleUI.paragraph("Resuelve un reto y ofrece una propuesta. El titular conserva el control de sus órdenes.", 16))
 if training == null:
  var practice_button = ConsoleUI.button("Entrenamiento seguro · sin órdenes a la partida", _open_training)
  practice_button.name = "OpenAssistanceTraining"
  add_child(practice_button)
  var school_button = ConsoleUI.button("Escuela de tripulación · primera misión y ocho puestos", _open_crew_school)
  school_button.name = "OpenCrewTraining"
  add_child(school_button)
 var options = ConsoleUI.row(self)
 chooser = OptionButton.new()
 for label in ["Temporización", "Secuencia", "Precisión", "Puzle de circuitos"]: chooser.add_item(label)
 options.add_child(chooser)
 recipient = OptionButton.new()
 for role in Catalog.ROLES:
  if role != _current_role():
   recipient.add_item(Catalog.role_name(role))
   recipient.set_item_metadata(recipient.item_count - 1, role)
 options.add_child(recipient)
 if training != null:
  chooser.select(Cooperation.MODES.find(training.lesson_mode))
  chooser.item_selected.connect(_training_mode_changed)
  for i in recipient.item_count:
   if recipient.get_item_metadata(i) == AssistanceTraining.RECIPIENT: recipient.select(i)
 start_button = ConsoleUI.button("Comenzar reto", func(): _send("assist_begin", {"recipient": recipient.get_item_metadata(recipient.selected), "mode": Cooperation.MODES[chooser.selected]}), true)
 options.add_child(start_button)
 options.add_child(ConsoleUI.button("Cancelar", _send.bind("assist_cancel", {})))
 readout = ConsoleUI.paragraph("Elige a quién ayudar y cómo.", 17, ConsoleUI.TEAL)
 add_child(readout)
 panel = Control.new()
 panel.custom_minimum_size.y = 235
 panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 add_child(panel)
 panel.draw.connect(_draw_panel)
 panel.gui_input.connect(_panel_input)
 controls = ConsoleUI.column(self)
 status = ConsoleUI.paragraph("", 16)
 add_child(status)
 consume_button = ConsoleUI.button("Aplicar la primera propuesta para mi puesto" if training == null else "Aplicar como Ingeniería · sólo simulación", _consume)
 add_child(consume_button)
 if training == null: Session.notice.connect(_notice)
 _refresh()

func _open_crew_school() -> void:
 if training != null: return
 var existing = get_node_or_null("CrewSchool")
 if is_instance_valid(existing) and not existing.is_queued_for_deletion():
  existing.popup_centered()
  return
 var window = load("res://ui/crew_training_window.gd").new()
 window.name = "CrewSchool"
 add_child(window)
 window.popup_centered()

func _open_training() -> void:
 if training != null: return
 var existing = get_node_or_null("AssistanceTraining")
 if is_instance_valid(existing) and not existing.is_queued_for_deletion():
  existing.popup_centered()
  return
 # Lazy load avoids a dependency cycle: the window reuses this console.
 var window = load("res://ui/assistance_training_window.gd").new()
 window.name = "AssistanceTraining"
 add_child(window)
 window.popup_centered()

func _training_mode_changed(index: int) -> void:
 if training == null or index < 0 or index >= Cooperation.MODES.size(): return
 var response = training.reset(Cooperation.MODES[index], training.practice_seed)
 _notice(response.message, response.ok)
 _refresh()

func _current_role() -> String:
 return AssistanceTraining.HELPER if training != null else Session.role

func _notice(message: String, ok: bool) -> void:
 status.text = message
 status.add_theme_color_override("font_color", ConsoleUI.TEAL if ok else ConsoleUI.RED)

func _principal() -> String:
 if training != null: return AssistanceTraining.PRINCIPAL
 return "local" if Session.mode == "offline" else str(Session.multiplayer.get_unique_id())

func _send(operation: String, args: Dictionary) -> void:
 var response = training.order(operation, args) if training != null else Session.order(operation, args)
 _notice(response.message, response.ok)
 _refresh()

func _consume() -> void:
 if training != null:
  var response = training.apply_proposal()
  _notice(response.message, response.ok)
  _refresh()
  return
 for id in Session.view.get("cooperation", {}).get("tokens", {}):
  if Session.view.cooperation.tokens[id].recipient == Session.role:
   _send("assist_consume", {"id": id})
   return
 _notice("Todavía no tienes propuestas pendientes.", false)

func _process(delta: float) -> void:
 if training != null: training.advance(delta)
 _clock += delta
 if _clock > 0.05: _clock = 0; _refresh()

func _refresh() -> void:
 _state_view = training.snapshot() if training != null else Session.view
 task = _state_view.get("cooperation", {}).get("tasks", {}).get(_principal(), {})
 var id = task.get("id", "")
 start_button.disabled = not task.is_empty() or (training != null and training.phase != "ready")
 chooser.disabled = not task.is_empty()
 recipient.disabled = not task.is_empty() or training != null
 if training != null: consume_button.disabled = training.phase != "proposal"
 if current_id != id:
  current_id = id
  ConsoleUI.clear(controls)
  if not task.is_empty():
   chooser.select(Cooperation.MODES.find(task.mode))
   for i in recipient.item_count:
    if recipient.get_item_metadata(i) == task.recipient: recipient.select(i)
   if task.mode == "secuencia":
    var row = ConsoleUI.row(controls)
    for i in 4: row.add_child(ConsoleUI.button(str(i + 1), _send.bind("assist_input", {"value": i})))
   elif task.mode == "puzzle":
    var grid = GridContainer.new()
    grid.columns = 3
    controls.add_child(grid)
    for i in 9: grid.add_child(ConsoleUI.button("Casilla %d" % (i + 1), _send.bind("assist_input", {"value": i})))
   elif task.mode == "temporizacion": controls.add_child(ConsoleUI.button("Detener cursor", _send.bind("assist_input", {}), true))
   controls.add_child(ConsoleUI.button("Enviar resultado", _send.bind("assist_finish", {}), true))
 if not task.is_empty():
  var message = "%s · para %s · %.1f s" % [task.mode.capitalize(), Catalog.role_name(task.recipient), maxf(0, task.expires - _state_view.time)]
  if task.mode == "secuencia":
   if not task.sequence.is_empty(): message += "\nMemoriza: " + " · ".join(task.sequence.map(func(value): return str(int(value) + 1)))
   else: message += "\nReproduce la secuencia: %d / 5 entradas." % task.progress
  elif task.mode == "puzzle": message += "\nCada casilla alterna ella misma y sus vecinas. Reproduce el patrón de arriba."
  elif task.mode == "precision": message += "\nPulsa en el centro de la diana. Solo tienes un intento."
  else: message += "\nDetén el cursor dentro de la franja indicada."
  readout.text = message
 elif training != null:
  readout.text = "Simulación local · %s · semilla %d" % [Catalog.role_name(AssistanceTraining.RECIPIENT), training.practice_seed]
 else:
  var pending = 0
  for token in _state_view.get("cooperation", {}).get("tokens", {}).values():
   if token.recipient == Session.role: pending += 1
  readout.text = "Elige un reto. Propuestas pendientes para tu puesto: %d." % pending
 panel.queue_redraw()

func _draw_panel() -> void:
 panel.draw_rect(Rect2(Vector2.ZERO, panel.size), ConsoleUI.BG)
 if task.is_empty(): return
 if task.mode == "temporizacion":
  var y = panel.size.y * 0.5
  var width = panel.size.x - 60
  panel.draw_line(Vector2(30, y), Vector2(30 + width, y), ConsoleUI.LINE, 12)
  panel.draw_rect(Rect2(Vector2(30 + (task.center[0] - 0.18) * width, y - 18), Vector2(0.36 * width, 36)), Color("246c60"))
  var cursor_x = 30 + Cooperation.cursor(task, _state_view.time) * width
  panel.draw_line(Vector2(cursor_x, y - 30), Vector2(cursor_x, y + 30), ConsoleUI.AMBER, 4)
 elif task.mode == "precision":
  var center = Vector2(task.center[0] * panel.size.x, task.center[1] * panel.size.y)
  var ellipse = PackedVector2Array()
  for i in 65: ellipse.append(center + Vector2(cos(i * TAU / 64.0) * panel.size.x * 0.16, sin(i * TAU / 64.0) * panel.size.y * 0.16))
  panel.draw_polyline(ellipse, ConsoleUI.TEAL, 2, true)
  panel.draw_circle(center, 7, ConsoleUI.AMBER)
 elif task.mode == "puzzle":
  for i in 9:
   var offset = Vector2((i % 3) * 48 + 35, (i / 3) * 48 + 30)
   panel.draw_rect(Rect2(offset, Vector2(36, 36)), ConsoleUI.TEAL if int(task.target[i]) else ConsoleUI.LINE)
   panel.draw_rect(Rect2(offset + Vector2(230, 0), Vector2(36, 36)), ConsoleUI.AMBER if int(task.board[i]) else ConsoleUI.LINE)
  panel.draw_string(ThemeDB.fallback_font, Vector2(35, 205), "PATRÓN OBJETIVO                         TU CIRCUITO", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ConsoleUI.MUTED)

func _panel_input(event: InputEvent) -> void:
 if not task.is_empty() and task.mode == "precision" and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
  if panel.size.x <= 0 or panel.size.y <= 0: return
  _send("assist_input", {"x": event.position.x / panel.size.x, "y": event.position.y / panel.size.y})
