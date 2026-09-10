class_name OperationsConsole
extends VBoxContainer
## Native controls for operations that need an expanded console.
var role = "navegacion"
var selected_target = ""
var status: Label
var readout: Label
var form: VBoxContainer
var action_menu: ItemList
var fields: Dictionary = {}
var current_operation = ""
var definitions: Array = []
var _timer = 0.0

const FORMS = {
 "warp": ["Velocidad warp", "La energía y el combustible sostienen el viaje. Nivel 0 desactiva warp.", [["level", "Nivel warp", 0, 4, 1]]],
 "jump": ["Salto espacial", "El salto carga 5 segundos y consume 40 de energía y toda la carga de maniobra.", [["distance", "Distancia (m)", 100, 3000, 100]]],
 "strafe": ["Desplazamiento lateral", "Un valor negativo desplaza hacia babor; positivo, hacia estribor.", [["amount", "Intensidad lateral", -1, 1, 0.1]]],
 "request_dock": ["Aproximación de atraque", "El piloto conduce hasta la estación y engancha las amarras al reducir la velocidad.", [["target", "Estación", "contact"]]],
 "abort_dock": ["Cancelar aproximación", "Detiene la maniobra antes de atracar. Para soltar amarras utiliza Desatracar.", []],
 "route_follow": ["Seguir punto de ruta", "Navegación sigue un punto trazado por Enlace y frena al llegar.", [["id", "Punto de ruta", "waypoint"]]],
 "auto_repair": ["Reparación automática", "Los equipos se desplazan al sistema más deteriorado; consumen repuestos al reparar.", [["enabled", "Reparación automática", "bool"]]],
 "coolant_level": ["Distribuir refrigerante", "Reparte un total de 8 unidades entre los sistemas.", [["system", "Sistema", "system"], ["value", "Refrigerante", 0, 8, 0.5]]],
 "shield_frequency": ["Frecuencia de escudos", "Los escudos caen durante los 5 segundos de recalibración. Después debes activarlos.", [["frequency", "Frecuencia", 0, 20, 1]]],
 "weapon_target": ["Fijar haces automáticos", "Armas disparará pulsos al blanco identificado cuando esté en alcance y haya energía.", [["target", "Blanco (vacío para detener)", "contact_optional"]]],
 "beam_frequency": ["Frecuencia de haces", "Ajusta la frecuencia del haz a la vulnerabilidad registrada por Sensores.", [["frequency", "Frecuencia", 0, 20, 1]]],
 "tube_load": ["Cargar tubo", "La carga tarda 4 segundos y retira una unidad del almacén.", [["tube", "Tubo lanzador", "tube"], ["ammo", "Munición", "ammo"]]],
 "tube_unload": ["Descargar tubo", "Devuelve al almacén la munición que queda en el tubo.", [["tube", "Tubo lanzador", "tube"]]],
 "tube_fire": ["Disparar tubo", "Guiado: 38 daño. Nuclear: área de 90. EMP: inhibe 18 s. HVLI: 20 daño. Mina: proximidad.", [["tube", "Tubo lanzador", "tube"], ["target", "Blanco", "contact"]]],
 "shields": ["Activar escudos", "Protege la integridad de la nave. No se puede activar durante una recalibración.", [["enabled", "Escudos activados", "bool"]]],
 "scan_cancel": ["Cancelar escaneo", "Libera Sensores para analizar otro contacto.", []],
 "database_record": ["Archivar descubrimiento", "Conserva un contacto identificado en la base científica de la campaña.", [["target", "Contacto identificado", "contact"]]],
 "comm_open": ["Abrir comunicación", "Abre un diálogo con un contacto a menos de 900 m.", [["target", "Interlocutor", "contact"]]],
 "comm_close": ["Cerrar comunicación", "Cierra el canal activo conservando la conversación.", []],
 "comm_message": ["Transmitir mensaje", "Envía un mensaje de texto al interlocutor del canal abierto.", [["text", "Mensaje", "text"]]],
 "comm_reply": ["Responder al interlocutor", "Elige una respuesta del diálogo actual; una tregua requiere identificación y escudos bajos.", [["reply", "Respuesta", "reply"]]],
 "waypoint_add": ["Trazar punto de ruta", "La marcación y la distancia se miden desde la nave.", [["name", "Nombre", "text"], ["bearing", "Marcación (°)", -360, 360, 1], ["distance", "Distancia (m)", 0, 12000, 25]]],
 "waypoint_move": ["Mover punto de ruta", "Corrige un punto ya trazado sin crear otro.", [["id", "Punto", "waypoint"], ["bearing", "Marcación (°)", -360, 360, 1], ["distance", "Distancia (m)", 0, 12000, 25]]],
 "waypoint_remove": ["Retirar punto de ruta", "Si Navegación lo estaba siguiendo, la nave frenará.", [["id", "Punto", "waypoint"]]],
 "science_link": ["Enlazar sonda con Sensores", "Comparte con Sensores el alcance y la vista de una sonda desplegada.", [["target", "Contacto con sonda", "contact"]]],
 "science_unlink": ["Cerrar enlace de sonda", "Devuelve el origen de los sensores a la nave.", []],
 "alert": ["Nivel de alerta", "La declaración de alerta se comparte con toda la tripulación.", [["level", "Alerta", "alert"]]],
 "crew_move": ["Desplegar equipo de reparación", "El equipo recorre la cubierta y repara al llegar. Puedes cambiar su destino en marcha.", [["crew", "Equipo", "crew"], ["system", "Sala de destino", "system"]]],
 "destruct_arm": ["Armar autodestrucción", "Escribe ITSASO para armar. Mando, Ingeniería y Armas deben confirmar antes de iniciar la cuenta de 15 segundos.", [["confirmation", "Confirmación", "text"]]],
 "destruct_cancel": ["Cancelar autodestrucción", "Cancela la secuencia y elimina las confirmaciones de todos los puestos.", []],
 "destruct_confirm": ["Confirmar autodestrucción", "Introduce el código de tu puesto, visible en la lectura de abajo. En red se necesitan tres personas distintas.", [["code", "Código del puesto", "text"]]]
}

func _ready() -> void:
 add_child(ConsoleUI.label("Operaciones · " + Catalog.role_name(role), 27))
 var body = ConsoleUI.row(self, 16)
 ConsoleUI.expand(body)
 action_menu = ItemList.new()
 action_menu.custom_minimum_size = Vector2(290, 360)
 body.add_child(action_menu)
 var scroll = ScrollContainer.new()
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 ConsoleUI.expand(scroll)
 body.add_child(scroll)
 form = ConsoleUI.column(scroll)
 form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 for operation in ShipOperations.PERMISSIONS.get(role, []):
  if FORMS.has(operation):
   definitions.append(operation)
   action_menu.add_item(FORMS[operation][0])
 action_menu.item_selected.connect(_select)
 status = ConsoleUI.paragraph("Las órdenes se validan en el anfitrión y afectan a la nave compartida.", 15, ConsoleUI.TEAL)
 add_child(status)
 var output = ScrollContainer.new()
 output.custom_minimum_size.y = 165
 output.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 add_child(output)
 readout = ConsoleUI.paragraph("", 14)
 output.add_child(readout)
 if not definitions.is_empty(): action_menu.select(0); _select(0)
 Session.notice.connect(_notice)
 _refresh_readout()

func _notice(message: String, ok: bool) -> void:
 status.text = message
 status.add_theme_color_override("font_color", ConsoleUI.TEAL if ok else ConsoleUI.RED)

func _select(index: int) -> void:
 ConsoleUI.clear(form)
 fields.clear()
 current_operation = definitions[index]
 var definition: Array = FORMS[current_operation]
 form.add_child(ConsoleUI.label(definition[0], 23))
 form.add_child(ConsoleUI.paragraph(definition[1], 16))
 for spec in definition[2]:
  form.add_child(ConsoleUI.label(spec[1], 14, ConsoleUI.MUTED))
  if spec.size() == 5:
   var value = SpinBox.new()
   value.min_value = spec[2]
   value.max_value = spec[3]
   value.step = spec[4]
   value.value = clampf(1, spec[2], spec[3])
   form.add_child(value)
   fields[spec[0]] = value
  elif spec[2] == "text":
   var value = LineEdit.new()
   value.max_length = 80
   value.custom_minimum_size.y = 40
   form.add_child(value)
   fields[spec[0]] = value
  elif spec[2] == "bool":
   var value = CheckButton.new()
   value.text = "Desactivado"
   value.toggled.connect(func(enabled): value.text = "Activado" if enabled else "Desactivado")
   form.add_child(value)
   fields[spec[0]] = value
  else:
   var value = OptionButton.new()
   for item in _options(spec[2]):
    value.add_item(item[1])
    value.set_item_metadata(value.item_count - 1, item[0])
    if item[0] == selected_target: value.select(value.item_count - 1)
   form.add_child(value)
   fields[spec[0]] = value
 form.add_child(ConsoleUI.button("Ejecutar orden", _execute, true))

func _options(kind: String) -> Array:
 var values: Array = []
 var view: Dictionary = Session.view
 var o: Dictionary = view.get("operations", {})
 if kind in ["contact", "contact_optional"]:
  if kind == "contact_optional": values.append(["", "Sin blanco · detener fuego automático"])
  for c in view.get("contacts", []): values.append([c.id, c.name])
 elif kind == "waypoint":
  for point in o.get("waypoints", []): values.append([point.id, point.name])
 elif kind == "system":
  for system in Catalog.SYSTEMS: values.append([system, system.capitalize()])
 elif kind == "tube":
  values = [[0, "Tubo 1"], [1, "Tubo 2"]]
 elif kind == "ammo":
  for ammo in ShipOperations.AMMO: values.append([ammo, {"homing": "Guiado", "nuke": "Nuclear", "mine": "Mina", "emp": "Pulso EMP", "hvli": "HVLI"}[ammo]])
 elif kind == "crew":
  for team in o.get("crews", []): values.append([team.id, team.id.capitalize()])
 elif kind == "alert":
  for level in ["verde", "ambar", "roja"]: values.append([level, level.capitalize()])
 elif kind == "reply":
  for reply in o.get("comms", {}).get("replies", []): values.append([reply, {"estado": "Solicitar estado", "suministros": "Pedir suministros", "alto_el_fuego": "Proponer tregua"}.get(reply, reply)])
 return values

func _execute() -> void:
 var args = {}
 for key in fields:
  var field = fields[key]
  if field is SpinBox: args[key] = field.value
  elif field is LineEdit: args[key] = field.text
  elif field is CheckButton: args[key] = field.button_pressed
  elif field is OptionButton:
   if field.selected < 0: status.text = "No hay una opción disponible para " + key + "."; return
   args[key] = field.get_item_metadata(field.selected)
 var response = Session.order(current_operation, args)
 status.text = response.message
 status.add_theme_color_override("font_color", ConsoleUI.TEAL if response.ok else ConsoleUI.RED)
 _refresh_readout()

func _process(delta: float) -> void:
 _timer += delta
 if _timer >= 0.2: _timer = 0.0; _refresh_readout()

func _refresh_readout() -> void:
 var o: Dictionary = Session.view.get("operations", {})
 if o.is_empty(): return
 var lines = ["Warp %d · Maniobra %d%% · Salto %.1f s · Calibración %.1f s" % [o.warp, o.maneuver, o.jump.remaining, o.calibration]]
 if role == "armas":
  for i in o.tubes.size(): lines.append("Tubo %d: %s · %.1f s" % [i + 1, o.tubes[i].ammo if not o.tubes[i].ammo.is_empty() else "vacío", o.tubes[i].remaining])
  var stores = []
  for ammo in ShipOperations.AMMO: stores.append("%s: %d" % [{"homing": "Guiados", "nuke": "Nucleares", "mine": "Minas", "emp": "EMP", "hvli": "HVLI"}[ammo], o.ammo[ammo]])
  lines.append("Almacén · " + " · ".join(stores))
 elif role == "reparaciones":
  for team in o.crews: lines.append("%s → %s · posición (%.1f, %.1f) · trabajo %.1f / 5 s" % [team.id, team.destination if not team.destination.is_empty() else "en espera", team.position[0], team.position[1], team.work])
 elif role == "ingenieria":
  var circuits = []
  for system in Catalog.SYSTEMS: circuits.append("%s: %.1f" % [system.capitalize(), o.coolant[system]])
  lines.append("Refrigerante · " + " · ".join(circuits))
 elif role == "comunicaciones":
  for message in o.comms.messages.slice(-6): lines.append(message.speaker + ": " + message.text)
 elif role in ["enlace", "navegacion"]:
  for point in o.waypoints: lines.append("%s · %s (%.0f, %.0f)" % [point.id, point.name, point.position[0], point.position[1]])
 elif role == "sensores":
  for entry in o.database.values(): lines.append("%s · %s · frecuencia %d" % [entry.name, entry.kind, entry.frequency])
 var destruct: Dictionary = o.destruct
 if destruct.armed:
  lines.append("AUTODESTRUCCIÓN · %d/3 confirmaciones · %s" % [destruct.confirmed.size(), "esperando confirmaciones" if destruct.remaining < 0 else "%.1f segundos" % destruct.remaining])
  if destruct.codes.has(role): lines.append("Código de tu puesto: " + str(destruct.codes[role]))
 readout.text = "\n".join(lines)
