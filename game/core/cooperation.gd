class_name Cooperation
extends RefCounted
## Seeded skill tasks create proposals; only the receiving station applies them.
const COMMANDS = ["assist_begin", "assist_input", "assist_finish", "assist_cancel", "assist_consume"]
const MODES = ["temporizacion", "secuencia", "precision", "puzzle"]

static func initialize(state: Dictionary) -> void:
 if not state.has("cooperation"): state.cooperation = {"next_id": 1, "tasks": {}, "tokens": {}, "cooldowns": {}}

static func cursor(task: Dictionary, time: float) -> float:
 return pingpong((time - task.started) / 1.6 + task.phase, 1.0)

static func flip(board: Array, index: int) -> void:
 for offset in [0, -3, 3, -1, 1]:
  var neighbor = index + offset
  if neighbor < 0 or neighbor >= 9: continue
  if abs(offset) == 1 and neighbor / 3 != index / 3: continue
  board[neighbor] = 1 - int(board[neighbor])

static func perform(sim, role: String, operation: String, args: Dictionary, principal: String) -> Dictionary:
 var state: Dictionary = sim.state
 var coop: Dictionary = state.cooperation
 if operation == "assist_begin":
  var recipient = str(args.get("recipient", ""))
  var mode = str(args.get("mode", ""))
  if recipient not in Catalog.ROLES or recipient == role or mode not in MODES: return ShipOperations.result(false, "Selecciona otro puesto y uno de los cuatro retos.")
  var system = str(args.get("system", "motores"))
  if system not in Catalog.SYSTEMS: return ShipOperations.result(false, "Sistema de asistencia desconocido.")
  if coop.tasks.has(principal) or float(coop.cooldowns.get(principal, 0)) > state.time: return ShipOperations.result(false, "Ya tienes una asistencia o debes esperar a que termine su descanso.")
  if coop.tasks.size() >= 8 or coop.tokens.size() >= 16: return ShipOperations.result(false, "Hay demasiadas asistencias pendientes.")
  var rng = RandomNumberGenerator.new()
  rng.seed = int((str(state.get("run_id", "")) + ":" + str(coop.next_id) + ":" + str(state.sequence)).hash())
  var sequence: Array = []
  for i in 5: sequence.append(rng.randi_range(0, 3))
  var target: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0]
  for i in 5: flip(target, rng.randi_range(0, 8))
  if target == [0, 0, 0, 0, 0, 0, 0, 0, 0]: flip(target, 4)
  coop.tasks[principal] = {"id": "ayuda-%d" % coop.next_id, "helper": role, "recipient": recipient, "mode": mode, "system": system, "started": state.time, "expires": state.time + 45.0,
   "sequence": sequence, "progress": 0, "failed": false, "target": target, "board": [0, 0, 0, 0, 0, 0, 0, 0, 0], "center": [rng.randf_range(0.2, 0.8), rng.randf_range(0.2, 0.8)], "phase": rng.randf(), "accuracy": -1.0, "moves": 0}
  coop.next_id += 1
  return ShipOperations.result(true, "Reto iniciado. Un éxito propondrá una ayuda al titular del otro puesto.")
 if operation == "assist_consume":
  var id = str(args.get("id", ""))
  var token: Dictionary = coop.tokens.get(id, {})
  if token.is_empty() or token.recipient != role or token.expires <= state.time: return ShipOperations.result(false, "La propuesta no existe, ha caducado o pertenece a otro puesto.")
  var proposal: Dictionary = token.args.duplicate(true)
  if token.operation == "helm": proposal.heading = state.ship.heading
  var response = sim.command(role, token.operation, proposal, principal)
  if response.ok: coop.tokens.erase(id)
  return response
 if not coop.tasks.has(principal): return ShipOperations.result(false, "No tienes un reto en curso.")
 var task: Dictionary = coop.tasks[principal]
 if task.helper != role: return ShipOperations.result(false, "Vuelve al puesto desde el que empezaste la ayuda o cancélala.")
 if operation == "assist_cancel":
  coop.tasks.erase(principal)
  coop.cooldowns[principal] = state.time + 3.0
  return ShipOperations.result(true, "Asistencia cancelada sin modificar la nave.")
 if task.expires <= state.time: return ShipOperations.result(false, "El reto ha caducado.")
 if operation == "assist_input":
  if task.moves >= 100: return ShipOperations.result(false, "Se agotó el número de intentos del reto.")
  if task.mode == "secuencia":
   if state.time < task.started + 3.0: return ShipOperations.result(false, "Observa la secuencia antes de responder.")
   if not ShipOperations.number(args, "value", 0, 3, true) or task.progress >= task.sequence.size(): return ShipOperations.result(false, "Entrada de secuencia inválida.")
   task.failed = task.failed or int(args.value) != int(task.sequence[task.progress])
   task.progress += 1
  elif task.mode == "puzzle":
   if not ShipOperations.number(args, "value", 0, 8, true): return ShipOperations.result(false, "Casilla fuera del panel.")
   flip(task.board, int(args.value))
  elif task.mode == "temporizacion":
   if task.accuracy >= 0: return ShipOperations.result(false, "Ya has detenido el cursor.")
   task.accuracy = clampf(1.0 - absf(cursor(task, state.time) - task.center[0]) / 0.18, 0, 1)
  elif task.mode == "precision":
   if task.accuracy >= 0 or not ShipOperations.number(args, "x", 0, 1) or not ShipOperations.number(args, "y", 0, 1): return ShipOperations.result(false, "Se permite un único disparo dentro del panel.")
   task.accuracy = clampf(1.0 - Vector2(args.x - task.center[0], args.y - task.center[1]).length() / 0.16, 0, 1)
  task.moves += 1
  return ShipOperations.result(true, "Entrada registrada.")
 if operation != "assist_finish": return ShipOperations.result(false, "Acción de asistencia desconocida.")
 var accuracy: float = task.accuracy
 if task.mode == "secuencia":
  if task.progress < task.sequence.size(): return ShipOperations.result(false, "Introduce toda la secuencia antes de enviar.")
  accuracy = 1.0 if not task.failed else 0.0
 elif task.mode == "puzzle": accuracy = 1.0 if task.board == task.target else 0.0
 elif accuracy < 0: return ShipOperations.result(false, "Resuelve el reto antes de enviar.")
 coop.tasks.erase(principal)
 coop.cooldowns[principal] = state.time + 5.0
 if accuracy < 0.45: return ShipOperations.result(true, "Reto terminado sin éxito. La nave no ha cambiado.")
 var tier = 2 if accuracy >= 0.8 else 1
 var proposal = {}
 var action = ""
 if task.recipient == "ingenieria":
  action = "coolant_level"
  var current: float = state.operations.coolant[task.system]
  var used = 0.0
  for value in state.operations.coolant.values(): used += float(value)
  proposal = {"system": task.system, "value": minf(current + tier, current + maxf(0, 8.0 - used))}
 elif task.recipient == "navegacion":
  action = "helm"
  proposal = {"heading": state.ship.heading, "throttle": minf(1.0, state.ship.throttle + tier * 0.15)}
 if action.is_empty():
  sim.log_event("Asistencia", "%s ha ayudado a %s. Ventaja narrativa, sin órdenes automáticas." % [Catalog.role_name(role), Catalog.role_name(task.recipient)])
  return ShipOperations.result(true, "Ayuda narrativa registrada en la bitácora.")
 coop.tokens[task.id] = {"recipient": task.recipient, "helper": role, "operation": action, "args": proposal, "expires": state.time + 120.0, "tier": tier}
 return ShipOperations.result(true, "Propuesta disponible para %s durante 120 segundos. El titular decide si la aplica." % Catalog.role_name(task.recipient))

static func tick(state: Dictionary) -> void:
 var coop: Dictionary = state.cooperation
 for principal in coop.tasks.keys():
  if coop.tasks[principal].expires <= state.time:
   coop.tasks.erase(principal)
   coop.cooldowns[principal] = state.time + 5.0
 for id in coop.tokens.keys():
  if coop.tokens[id].expires <= state.time: coop.tokens.erase(id)
 for id in coop.cooldowns.keys():
  if coop.cooldowns[id] < state.time: coop.cooldowns.erase(id)

static func redact(state: Dictionary, principal: String) -> void:
 if not state.has("cooperation"): return
 var tasks: Dictionary = state.cooperation.tasks
 var own: Dictionary = tasks.get(principal, {})
 state.cooperation.tasks = {principal: own} if not own.is_empty() else {}
 state.cooperation.cooldowns = {}
 if not own.is_empty() and state.time >= own.started + 3.0: own.sequence = []
