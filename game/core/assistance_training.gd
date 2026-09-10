class_name AssistanceTraining
extends RefCounted
## Disposable, local-only exercises. Never receives a Session or a campaign save.
const HELPER = "mando"
const RECIPIENT = "ingenieria"
const PRINCIPAL = "training-helper"
const MAX_SEED = 2147483647
const INSTRUCTIONS = {
 "temporizacion": "Detén el cursor cerca del centro de la franja. Sólo puedes detenerlo una vez; después, envía el resultado.",
 "secuencia": "Memoriza los cinco números durante tres segundos. Cuando se oculten, repítelos en orden y envía el resultado.",
 "precision": "Pulsa cerca del centro de la diana. Tienes un único intento; después, envía el resultado.",
 "puzzle": "Cada casilla alterna su luz y las vecinas. Haz que tu circuito coincida con el patrón objetivo y envía el resultado."
}

var lesson_mode = "temporizacion"
var practice_seed = 1
var phase = "ready"
var completed_modes: Array[String] = []
var _sim: Simulation

func _init() -> void:
 reset(lesson_mode, practice_seed)

func reset(mode: String, seed_value: Variant) -> Dictionary:
 if mode not in Cooperation.MODES:
  return _result(false, "Elige uno de los cuatro retos.")
 if not Catalog.finite_number(seed_value) or float(seed_value) != floorf(float(seed_value)) or float(seed_value) < 1 or float(seed_value) > MAX_SEED:
  return _result(false, "La semilla debe ser un entero entre 1 y %d." % MAX_SEED)
 lesson_mode = mode
 practice_seed = int(seed_value)
 _sim = Simulation.new()
 _sim.start(Catalog.missions()[0])
 # Fixed public stock content, no player data. The native task generator uses
 # run_id/sequence/next_id, so repeating a recipe reproduces the same challenge.
 _sim.state.run_id = "assistance-training-%d" % practice_seed
 _sim.state.sequence = 0
 phase = "ready"
 return _result(true, "Entrenamiento reiniciado. No se ha enviado ninguna orden a la partida.")

func snapshot() -> Dictionary:
 return _sim.snapshot(HELPER, PRINCIPAL)

func order(operation: String, args: Dictionary = {}) -> Dictionary:
 if operation not in Cooperation.COMMANDS:
  return _result(false, "El entrenamiento sólo admite acciones de asistencia.")
 if operation == "assist_begin":
  if phase != "ready":
   return _result(false, "Repite la semilla o cambia de reto para empezar de nuevo.")
  if args.get("mode") != lesson_mode or args.get("recipient") != RECIPIENT:
   return _result(false, "En esta práctica Mando ayuda a Ingeniería con el reto elegido.")
 var response: Dictionary = _sim.command(HELPER, operation, args, PRINCIPAL)
 if not response.ok:
  return response
 match operation:
  "assist_begin": phase = "playing"
  "assist_cancel": phase = "cancelled"
  "assist_finish": phase = "proposal" if not _sim.state.cooperation.tokens.is_empty() else "retry"
 return response

func apply_proposal() -> Dictionary:
 if phase != "proposal" or _sim.state.cooperation.tokens.is_empty():
  return _result(false, "Primero resuelve el reto y envía su resultado.")
 var id: String = str(_sim.state.cooperation.tokens.keys()[0])
 # Real authority check and real coolant order, but on the disposable ship.
 var response: Dictionary = _sim.command(RECIPIENT, "assist_consume", {"id": id}, "training-recipient")
 if response.ok:
  phase = "complete"
  if lesson_mode not in completed_modes: completed_modes.append(lesson_mode)
 return response

func advance(seconds: float) -> bool:
 if not is_finite(seconds) or seconds < 0 or seconds > 180:
  return false
 if phase not in ["playing", "proposal"]:
  return true
 # Only the native assistance clock advances; no enemies, heat or movement.
 _sim.state.time += seconds
 Cooperation.tick(_sim.state)
 if phase == "playing" and _sim.state.cooperation.tasks.is_empty(): phase = "expired"
 if phase == "proposal" and _sim.state.cooperation.tokens.is_empty(): phase = "expired"
 return true

func guidance() -> String:
 match phase:
  "ready": return "1/3 · Comienza el reto. " + str(INSTRUCTIONS[lesson_mode])
  "playing": return "1/3 · " + str(INSTRUCTIONS[lesson_mode])
  "proposal": return "2/3 · Reto superado: sólo hay una propuesta. La refrigeración aún no ha cambiado. Pulsa «Aplicar como Ingeniería» para que el destinatario la acepte en esta simulación."
  "complete": return "3/3 · Ingeniería ha aceptado la propuesta: motores con %.0f unidades de refrigeración. Prácticas completadas: %d/4. La nave real no ha recibido órdenes de este panel." % [float(_sim.state.operations.coolant.motores), completed_modes.size()]
  "retry": return "El resultado no alcanzó el mínimo: no hay propuesta ni cambio en la nave de práctica. Repite la semilla para probar el mismo reto."
  "expired": return "El reto o la propuesta han caducado con los plazos del juego real. Repite la semilla para volver a intentarlo."
  "cancelled": return "Práctica cancelada. Repite la semilla para comenzar otra vez."
 return ""

func _result(ok: bool, message: String) -> Dictionary:
 return {"ok": ok, "message": message}
