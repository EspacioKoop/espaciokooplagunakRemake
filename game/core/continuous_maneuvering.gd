class_name ContinuousManeuvering
extends Node
## Sustained lateral thrusters for Navigation. This complements the legacy instant strafe order.
## The input itself is transient; resulting inertia lives in ship.drift and is already saved/networked.

signal updated
signal notice(text: String, ok: bool)

const MAX_AXIS = 1.0
const MAX_LATERAL_SPEED = 82.0
const LATERAL_ACCELERATION = 68.0
const STABILIZATION = 54.0
const MANEUVER_COST_PER_ACCEL = 0.055
const ENERGY_COST_PER_SECOND = 2.4

var axis = 0.0
var controller = ""
var _window: Window
var _sync_clock = 0.0

func _ready() -> void:
 set_process_unhandled_key_input(true)

func _session() -> Node:
 return get_tree().root.get_node_or_null("Session")

func _authority() -> bool:
 var session = _session()
 return session == null or session.mode != "client"

func command(value: float) -> Dictionary:
 if not is_finite(value) or value < -MAX_AXIS or value > MAX_AXIS: return _result(false, "Empuje lateral fuera de rango.")
 var session = _session()
 if session == null: return _result(false, "No hay sesión de navegación.")
 if session.role != "navegacion": return _result(false, "Los propulsores laterales pertenecen a Navegación.")
 if session.mode == "client":
  axis = value
  controller = str(multiplayer.get_unique_id())
  _receive_axis.rpc_id(1, value)
  updated.emit()
  return _result(true, _axis_message(value))
 return _set_axis(value, "self" if session.mode == "offline" else "1", session)

@rpc("any_peer", "call_remote", "reliable", 3)
func _receive_axis(value: float) -> void:
 var session = _session()
 if session == null or session.mode != "host" or not is_finite(value) or value < -MAX_AXIS or value > MAX_AXIS: return
 var peer_id = multiplayer.get_remote_sender_id()
 if not session.roster.has(peer_id) or str(session.roster[peer_id].get("role", "")) != "navegacion": return
 var response = _set_axis(value, str(peer_id), session)
 _response.rpc_id(peer_id, response.message, response.ok, axis)

@rpc("authority", "call_remote", "reliable", 3)
func _response(text: String, ok: bool, authoritative_axis: float) -> void:
 if ok: axis = authoritative_axis
 notice.emit(text, ok)
 updated.emit()

@rpc("authority", "call_remote", "unreliable", 3)
func _sync(authoritative_axis: float) -> void:
 axis = authoritative_axis
 updated.emit()

func _set_axis(value: float, actor: String, session: Node) -> Dictionary:
 if session.sim.state.is_empty() or session.sim.state.status != "active": return _result(false, "Inicia una misión antes de maniobrar.")
 if not session.sim.state.ship.docked.is_empty() and not is_zero_approx(value): return _result(false, "La nave está atracada.")
 axis = value
 controller = actor if not is_zero_approx(value) else ""
 updated.emit()
 var response = _result(true, _axis_message(value))
 notice.emit(response.message, true)
 return response

func _axis_message(value: float) -> String:
 if is_zero_approx(value): return "Propulsores laterales centrados; estabilización automática activa."
 return "Empuje lateral %s al %d%%." % ["estribor" if value > 0 else "babor", int(absf(value) * 100.0)]

func lateral_speed(ship: Dictionary) -> float:
 var side = Vector2.from_angle(deg_to_rad(float(ship.heading)) + PI * 0.5)
 return Vector2(float(ship.drift[0]), float(ship.drift[1])).dot(side)

func _process(delta: float) -> void:
 if not _authority(): return
 var session = _session()
 if session == null or session.sim.state.is_empty() or session.sim.state.status != "active":
  axis = 0.0
  controller = ""
  return
 if session.mode == "host" and not controller.is_empty() and controller != "1":
  var peer_id = int(controller)
  if not session.roster.has(peer_id) or peer_id not in multiplayer.get_peers():
   axis = 0.0
   controller = ""
 var ship: Dictionary = session.sim.state.ship
 if not ship.docked.is_empty(): axis = 0.0
 var efficiency = ShipModel.efficiency(ship, "maniobra")
 var drift = Vector2(float(ship.drift[0]), float(ship.drift[1]))
 var side = Vector2.from_angle(deg_to_rad(float(ship.heading)) + PI * 0.5)
 var current = drift.dot(side)
 var target = axis * MAX_LATERAL_SPEED * efficiency
 var rate = LATERAL_ACCELERATION * efficiency if not is_zero_approx(axis) else STABILIZATION * maxf(0.35, efficiency)
 var next = move_toward(current, target, rate * delta)
 var acceleration_delta = absf(next - current)
 if not is_zero_approx(axis):
  var maneuver_cost = acceleration_delta * MANEUVER_COST_PER_ACCEL
  var energy_cost = ENERGY_COST_PER_SECOND * absf(axis) * delta
  if efficiency <= 0.0 or float(session.sim.state.operations.maneuver) <= maneuver_cost or float(ship.energy) <= energy_cost:
   axis = 0.0
   controller = ""
   target = 0.0
   next = move_toward(current, 0.0, STABILIZATION * maxf(0.35, efficiency) * delta)
  else:
   session.sim.state.operations.maneuver = maxf(0.0, float(session.sim.state.operations.maneuver) - maneuver_cost)
   ship.energy = maxf(0.0, float(ship.energy) - energy_cost)
 drift += side * (next - current)
 drift = drift.limit_length(5000.0)
 ship.drift = [drift.x, drift.y]
 _sync_clock += delta
 if session.mode == "host" and _sync_clock >= 0.2:
  _sync_clock = 0.0
  _sync.rpc(axis)
 updated.emit()

func _unhandled_key_input(event: InputEvent) -> void:
 if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_F8: return
 if _window != null and is_instance_valid(_window):
  _window.queue_free()
  _window = null
 else:
  _window = ManeuverConsole.new()
  _window.thrusters = self
  get_tree().root.add_child(_window)
  _window.close_requested.connect(func(): _window.queue_free(); _window = null)
  _window.popup_centered()
 get_viewport().set_input_as_handled()

func _result(ok: bool, message: String) -> Dictionary:
 return {"ok": ok, "message": message}
