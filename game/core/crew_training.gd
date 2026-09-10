class_name CrewTraining
extends RefCounted
## The school owns a disposable native Simulation. No Session, storage or network.
const FIRST_MISSION = "first_mission"
const STEP = 0.05
const MAX_SECONDS = 900.0
const COMMANDS = {
 "mando": ["alert", "mission_choice"],
 "navegacion": ["helm", "autopilot", "dock", "undock"],
 "ingenieria": ["power", "coolant", "shields"],
 "armas": ["fire", "missile"],
 "sensores": ["scan"],
 "comunicaciones": ["hail", "negotiate"],
 "enlace": ["probe", "rescue", "salvage"],
 "reparaciones": ["repair", "repair_target"]
}
const LABELS = {
 "alert": "Nivel de alerta", "mission_choice": "Decisión de Mando",
 "helm": "Rumbo e impulso", "autopilot": "Piloto automático", "dock": "Atracar", "undock": "Desatracar",
 "power": "Repartir potencia", "coolant": "Dirigir refrigeración", "shields": "Activar o bajar escudos",
 "fire": "Disparar haces", "missile": "Lanzar torpedo guiado", "scan": "Analizar contacto",
 "hail": "Abrir canal", "negotiate": "Negociar paso", "probe": "Lanzar sonda", "rescue": "Rescatar supervivientes",
 "salvage": "Recuperar materiales", "repair": "Reparar sistema", "repair_target": "Reparar estación"
}
var lesson = FIRST_MISSION
var role = "mando"
var phase = "playing"
var paused = false
var step_index = 0
var completed: Array[String] = []
var accepted_orders = 0
var rejected_orders = 0
var _sim: Simulation
var _steps: Array = []
var _armed = false
var _accumulator = 0.0
var _origin = Vector2.ZERO

func _init() -> void:
 reset(FIRST_MISSION)

static func lesson_ids() -> Array:
 return [FIRST_MISSION] + Catalog.ROLES

static func lesson_name(id: String) -> String:
 return "Primera misión guiada · Itsasoratu" if id == FIRST_MISSION else "Práctica · " + Catalog.role_name(id)

func reset(id: String) -> Dictionary:
 if id not in lesson_ids(): return _reply(false, "Recorrido desconocido.")
 var mission: Dictionary
 if id == FIRST_MISSION:
  var missions = Catalog.missions()
  if missions.is_empty() or missions[0].get("id") != "itsasoratu":
   return _reply(false, "El catálogo no contiene la primera misión esperada.")
  mission = missions[0].duplicate(true)
 else:
  mission = _practice_mission(id)
 var error = Catalog.validate_mission(mission)
 if not error.is_empty(): return _reply(false, error)
 var simulation = Simulation.new()
 simulation.start(mission)
 if id == "reparaciones": simulation.state.ship.systems.motores.health = 30.0
 lesson = id
 role = "mando"
 phase = "playing"
 paused = false
 step_index = 0
 accepted_orders = 0
 rejected_orders = 0
 _sim = simulation
 _steps = _lesson_steps(id)
 _armed = false
 _accumulator = 0.0
 _origin = Vector2.ZERO
 return _reply(true, "Recorrido reiniciado. Sólo cambia la nave de prácticas.")

func select_role(id: String) -> Dictionary:
 if id not in Catalog.ROLES: return _reply(false, "Puesto desconocido.")
 role = id
 return _reply(true, Catalog.role_name(role) + ": " + str(Catalog.DESCRIPTIONS[role]))

func set_paused(value: bool) -> void:
 paused = value if phase == "playing" else true

func current_step() -> Dictionary:
 return _steps[step_index].duplicate(true) if step_index < _steps.size() else {}

func step_count() -> int:
 return _steps.size()

func snapshot() -> Dictionary:
 return _sim.snapshot(role, "crew-training")

func order(operation: String, args: Dictionary = {}) -> Dictionary:
 if phase != "playing": return _reply(false, "Reinicia el recorrido para seguir practicando.")
 # The native authority remains the validator; the school additionally limits
 # its command surface. No RPC, live campaign import or arbitrary dispatch.
 if operation not in COMMANDS.get(role, []):
  rejected_orders += 1
  return _reply(false, "Esta orden pertenece a otro puesto. Selecciona el indicado por la guía.")
 var result: Dictionary = _sim.command(role, operation, args, "crew-training")
 if not result.ok:
  rejected_orders += 1
  return result
 accepted_orders += 1
 var step: Dictionary = _steps[step_index]
 if role == step.role and operation == step.operation and _matches(args, step.args):
  _armed = true
 _evaluate()
 return result

func advance(seconds: Variant) -> bool:
 if not Catalog.finite_number(seconds) or float(seconds) < 0.0 or float(seconds) > 2.0: return false
 if paused or phase != "playing": return true
 _accumulator += float(seconds)
 # Fixed native ticks avoid frame-rate-dependent teaching conditions. At most
 # 40 ticks per call; pausing never catches up wall-clock time on resume.
 while _accumulator + 0.0000001 >= STEP and phase == "playing":
  _accumulator = maxf(0.0, _accumulator - STEP)
  _sim.tick(STEP)
  _evaluate()
  if phase == "playing" and float(_sim.state.time) >= MAX_SECONDS:
   phase = "expired"
   paused = true
 return true

func guidance() -> String:
 if phase == "complete":
  return "Recorrido completado con las reglas del juego. %d órdenes aceptadas; %d rechazadas. Puedes repetirlo o elegir otro puesto. Nada se transfiere a tu campaña." % [accepted_orders, rejected_orders]
 if phase == "lost": return "La nave de prácticas se ha perdido. Reinicia: no has perdido progreso ni recursos de tu campaña."
 if phase == "expired": return "La práctica ha alcanzado su límite de tiempo simulado. Reinicia el recorrido; la campaña no se ha modificado."
 var step = current_step()
 return "%d/%d · %s\nPuesto: %s. %s" % [step_index + 1, _steps.size(), step.title, Catalog.role_name(step.role), step.help]

func _evaluate() -> void:
 if _sim.state.status == "lost":
  phase = "lost"
  paused = true
  return
 if phase != "playing" or not _armed or not _satisfied(_steps[step_index]): return
 step_index += 1
 _armed = false
 _origin = Vector2(float(_sim.state.ship.position[0]), float(_sim.state.ship.position[1]))
 if step_index == _steps.size():
  phase = "complete"
  paused = true
  if lesson not in completed: completed.append(lesson)

func _satisfied(step: Dictionary) -> bool:
 var ship: Dictionary = _sim.state.ship
 var target: Dictionary = _sim.contact(str(step.args.get("target", "")))
 match step.rule:
  "accepted": return true
  "fact": return _sim.state.facts.has(str(step.fact))
  "arrival": return not target.is_empty() and _sim.distance_to(target) < 190.0 and absf(float(ship.speed)) <= 35.0
  "travel": return Vector2(float(ship.position[0]), float(ship.position[1])).distance_to(_origin) > 12.0
  "stopped": return absf(float(ship.speed)) < 1.0
  "scan": return not target.is_empty() and _sim.state.facts.has("scan:" + str(target.id))
  "repair": return _sim.state.repair.system.is_empty() and float(ship.systems.motores.health) >= float(step.health)
  "negotiated": return not target.is_empty() and bool(target.negotiated)
  "defeat": return not target.is_empty() and float(target.hull) <= 0.0
  "won": return _sim.state.status == "won"
 return false

static func _matches(actual: Dictionary, expected: Dictionary) -> bool:
 for key in expected:
  if not actual.has(key) or actual[key] != expected[key]: return false
 return true

static func _step(title: String, seat: String, operation: String, args: Dictionary, rule: String, help: String, extra: Dictionary = {}) -> Dictionary:
 var result = {"title": title, "role": seat, "operation": operation, "args": args, "rule": rule, "help": help}
 result.merge(extra)
 return result

static func _lesson_steps(id: String) -> Array:
 match id:
  FIRST_MISSION:
   return [
    _step("Sal hacia el faro", "navegacion", "autopilot", {"target": "argi"}, "fact", "Elige Piloto automático y Faro Argi. Ejecuta y espera hasta estar a menos de 250 m. El simulador mueve y frena la nave; no hay teletransporte.", {"fact": "navigate:argi"}),
    _step("Identifica la señal", "sensores", "scan", {"target": "argi"}, "scan", "Elige Analizar contacto y Faro Argi. Ejecuta y mantén el alcance de 900 m mientras termina el análisis."),
    _step("Comunica el regreso", "comunicaciones", "hail", {"target": "kaia"}, "fact", "Elige Abrir canal y Puerto Kaia. La nave debe encontrarse a menos de 900 m del puerto.", {"fact": "hail:kaia"}),
    _step("Aproximación al puerto", "navegacion", "autopilot", {"target": "kaia"}, "arrival", "Elige Piloto automático y Puerto Kaia. Espera al frenado: menos de 190 m y 35 m/s. Los valores se ven debajo."),
    _step("Completa la primera misión", "navegacion", "dock", {"target": "kaia"}, "won", "Elige Atracar y Puerto Kaia. La misión original completa sus cuatro objetivos y calcula su recompensa sólo en esta nave desechable.")]
  "mando":
   return [
    _step("Prepara a la tripulación", "mando", "alert", {"level": "ambar"}, "accepted", "Selecciona Nivel de alerta: ámbar. No modifica automáticamente las órdenes de los demás puestos."),
    _step("Declara una emergencia", "mando", "alert", {"level": "roja"}, "accepted", "Cambia la alerta a roja y comprueba el estado compartido de la nave de prácticas."),
    _step("Vuelve a la normalidad", "mando", "alert", {"level": "verde"}, "accepted", "Restablece la alerta verde. Las decisiones narrativas exigen antes un acuerdo de Comunicaciones; se practican en ese recorrido.")]
  "navegacion":
   return [
    _step("Impulso manual", "navegacion", "helm", {"heading": 0, "throttle": 0.4}, "travel", "Selecciona Rumbo e impulso: rumbo 0° e impulso 0,4. Avanza al menos 12 m; la velocidad tiene aceleración."),
    _step("Frena antes de atracar", "navegacion", "helm", {"heading": 0, "throttle": 0}, "stopped", "Ordena impulso 0 con rumbo 0°. Espera hasta bajar de 1 m/s: una orden de parada no elimina la inercia al instante."),
    _step("Aproximación automática", "navegacion", "autopilot", {"target": "port"}, "arrival", "Traza Piloto automático hacia Puerto de prácticas y espera a menos de 190 m y 35 m/s."),
    _step("Amarra la nave", "navegacion", "dock", {"target": "port"}, "won", "Atraca en Puerto de prácticas. En una misión activa, Desatracar permite continuar después; aquí el atraque finaliza el ejercicio.")]
  "ingenieria":
   return [
    _step("Libera potencia", "ingenieria", "power", {"system": "sensores", "value": 0}, "accepted", "Repartir potencia: selecciona Sensores y 0. Hay 20 unidades compartidas; aumentar otro sistema antes de liberar potencia se rechaza."),
    _step("Refuerza el impulso", "ingenieria", "power", {"system": "motores", "value": 4}, "accepted", "Asigna 4 unidades a Impulso. Ahora hay presupuesto disponible, pero la sobrecarga genera calor."),
    _step("Controla el calor", "ingenieria", "coolant", {"system": "motores"}, "accepted", "Dirige refrigeración a Impulso. Observa potencia, integridad y temperatura en el estado de sistemas."),
    _step("Baja los escudos", "ingenieria", "shields", {"enabled": false}, "accepted", "Selecciona escudos desactivados. Es un requisito para negociar, pero deja el casco expuesto."),
    _step("Recupera la protección", "ingenieria", "shields", {"enabled": true}, "accepted", "Activa de nuevo los escudos. Esta práctica no modifica el reparto real de tu nave.")]
  "armas":
   return [
    _step("Pulso al blanco identificado", "armas", "fire", {"target": "target"}, "accepted", "Dispara haces al Blanco de prácticas. Está identificado y delante de la nave. El pulso consume energía y activa una recarga."),
    _step("Torpedo guiado", "armas", "missile", {"target": "target"}, "accepted", "Espera a que la recarga llegue a cero y lanza un torpedo guiado al blanco. El almacén pierde una unidad."),
    _step("Confirma la neutralización", "armas", "missile", {"target": "target"}, "defeat", "Repite torpedos guiados al mismo blanco, respetando la recarga, hasta integridad cero. La lección no termina por pulsar el botón: exige la derrota real.")]
  "sensores":
   return [
    _step("Revela un eco", "sensores", "scan", {"target": "signal"}, "scan", "Selecciona el contacto Eco 02 y analiza. Su nombre se oculta hasta completar el escaneo; mantén el alcance de 900 m."),
    _step("Analiza otro contacto", "sensores", "scan", {"target": "wreck"}, "scan", "Analiza el Eco 03. Un solo análisis puede estar activo a la vez; no confundas empezar el análisis con completarlo.")]
  "comunicaciones":
   return [
    _step("Abre el canal", "comunicaciones", "hail", {"target": "envoy"}, "fact", "Abre un canal con la Delegación de prácticas. Está identificada a menos de 900 m.", {"fact": "hail:envoy"}),
    _step("Coordina la diplomacia", "ingenieria", "shields", {"enabled": false}, "accepted", "Cambia a Ingeniería y baja escudos. Comunicaciones no puede hacerlo por su cuenta: cada puesto conserva su autoridad."),
    _step("Acuerda el paso", "comunicaciones", "negotiate", {"target": "envoy"}, "negotiated", "Vuelve a Comunicaciones y negocia con la delegación. Se exigen identificación, canal abierto, alcance y escudos bajos."),
    _step("Mando decide", "mando", "mission_choice", {"choice": "compartir"}, "won", "Cambia a Mando y elige Compartir. La decisión queda registrada en la campaña de prácticas, nunca en tu partida.")]
  "enlace":
   return [
    _step("Despliega una sonda", "enlace", "probe", {"target": "wreck"}, "fact", "Lanza una sonda al Pecio de prácticas. Su alcance es 2500 m y cada contacto acepta una sola sonda.", {"fact": "probe:wreck"}),
    _step("Rescata primero", "enlace", "rescue", {"target": "wreck"}, "fact", "Rescata al pecio identificado a menos de 300 m. Sus seis supervivientes se contabilizan en el estado del ejercicio.", {"fact": "rescue:wreck"}),
    _step("Recupera los materiales", "enlace", "salvage", {"target": "wreck"}, "fact", "Recupera materiales del mismo pecio. Una segunda recuperación del mismo contacto se rechaza.", {"fact": "salvage:wreck"})]
  "reparaciones":
   return [
    _step("Despliega drones", "reparaciones", "repair", {"system": "motores"}, "repair", "Repara Impulso: empieza al 30 %. Se consumen dos repuestos y los drones necesitan tiempo. Espera hasta alcanzar el 65 %.", {"health": 65.0}),
    _step("Completa la reparación", "reparaciones", "repair", {"system": "motores"}, "repair", "Repara Impulso de nuevo y espera al 100 %. Un sistema íntegro no admite reparaciones innecesarias.", {"health": 100.0}),
    _step("Repara una instalación", "reparaciones", "repair_target", {"target": "port"}, "fact", "Selecciona Reparar estación y Puerto de prácticas: está a menos de 300 m y necesita cinco repuestos.", {"fact": "repair_target:port"})]
 return []

static func _practice_mission(id: String) -> Dictionary:
 var contacts: Array = [{"id": "port", "name": "Puerto de prácticas", "kind": "station", "position": [0, 270], "known": true, "hull": 50}]
 var objective = {"type": "dock", "target": "port", "text": "Atracar al terminar la práctica de navegación."}
 match id:
  "sensores":
   contacts.append({"id": "signal", "name": "Señal de prácticas", "kind": "beacon", "position": [500, 0]})
   contacts.append({"id": "wreck", "name": "Pecio de prácticas", "kind": "derelict", "position": [-500, 0]})
  "enlace": contacts.append({"id": "wreck", "name": "Pecio de prácticas", "kind": "derelict", "position": [250, 0], "known": true})
  "armas": contacts.append({"id": "target", "name": "Blanco de prácticas", "kind": "hostile", "position": [450, 0], "known": true})
  "comunicaciones":
   contacts.append({"id": "envoy", "name": "Delegación de prácticas", "kind": "friendly", "position": [500, 0], "known": true})
   objective = {"type": "choice", "target": "envoy", "text": "Mando toma una decisión tras negociar el paso."}
 return {"id": "training_" + id, "title": lesson_name(id), "sector": "Escuela local", "briefing": "Escenario público desechable: practica sin tocar la campaña.", "reward": 0, "contacts": contacts, "objectives": [objective]}

static func _reply(ok: bool, message: String) -> Dictionary:
 return {"ok": ok, "message": message}
