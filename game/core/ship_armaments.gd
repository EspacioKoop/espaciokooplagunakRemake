class_name ShipArmaments
extends Node
## Multi-mount weapon layer. The host owns cooldowns, targeting and damage.
## Loadout state lives inside Simulation.ship so saves and normal ENet snapshots carry it.

signal updated
signal notice(text: String, ok: bool)

const MAX_MOUNTS = 8
const MOUNT_KINDS = ["beam", "turret", "rail", "emp"]
const TEMPLATES = {
 "exploracion": {
  "name": "Exploración Itsaso",
  "mounts": [
   {"id": "proa", "name": "Haz de proa", "kind": "beam", "arc_center": 0.0, "arc": 120.0, "range": 650.0, "damage": 18.0, "cycle": 1.0, "energy": 10.0},
   {"id": "dorsal", "name": "Torreta dorsal", "kind": "turret", "arc_center": 0.0, "arc": 360.0, "range": 520.0, "damage": 10.0, "cycle": 1.25, "energy": 6.0}
  ]
 },
 "escolta": {
  "name": "Escolta",
  "mounts": [
   {"id": "proa_babor", "name": "Haz proa babor", "kind": "beam", "arc_center": -18.0, "arc": 105.0, "range": 720.0, "damage": 16.0, "cycle": 0.9, "energy": 9.0},
   {"id": "proa_estribor", "name": "Haz proa estribor", "kind": "beam", "arc_center": 18.0, "arc": 105.0, "range": 720.0, "damage": 16.0, "cycle": 0.9, "energy": 9.0},
   {"id": "torreta_babor", "name": "Torreta de babor", "kind": "turret", "arc_center": -90.0, "arc": 210.0, "range": 560.0, "damage": 11.0, "cycle": 1.1, "energy": 6.0},
   {"id": "torreta_estribor", "name": "Torreta de estribor", "kind": "turret", "arc_center": 90.0, "arc": 210.0, "range": 560.0, "damage": 11.0, "cycle": 1.1, "energy": 6.0}
  ]
 },
 "ciencia": {
  "name": "Ciencia y contención",
  "mounts": [
   {"id": "torreta_omni", "name": "Torreta omnidireccional", "kind": "turret", "arc_center": 0.0, "arc": 360.0, "range": 500.0, "damage": 8.0, "cycle": 1.2, "energy": 5.0},
   {"id": "emisor_emp", "name": "Emisor EMP", "kind": "emp", "arc_center": 0.0, "arc": 180.0, "range": 430.0, "damage": 4.0, "cycle": 4.0, "energy": 16.0}
  ]
 },
 "artilleria": {
  "name": "Artillería pesada",
  "mounts": [
   {"id": "rail_proa", "name": "Cañón de riel", "kind": "rail", "arc_center": 0.0, "arc": 42.0, "range": 1100.0, "damage": 34.0, "cycle": 3.2, "energy": 18.0},
   {"id": "torreta_popa", "name": "Torreta de popa", "kind": "turret", "arc_center": 180.0, "arc": 190.0, "range": 500.0, "damage": 10.0, "cycle": 1.25, "energy": 6.0}
  ]
 }
}

var _window: Window
var _auto_clock = 0.0

func _ready() -> void:
 set_process_unhandled_key_input(true)

func _session() -> Node:
 return get_tree().root.get_node_or_null("Session")

func _authority() -> bool:
 var session = _session()
 return session == null or session.mode != "client"

static func template(template_id: String) -> Dictionary:
 var source: Dictionary = TEMPLATES.get(template_id, TEMPLATES.exploracion)
 var result = {"template": template_id if TEMPLATES.has(template_id) else "exploracion", "mounts": source.mounts.duplicate(true)}
 for mount in result.mounts:
  mount.ready_at = 0.0
  mount.auto_target = ""
 return result

static func validate_loadout(value: Variant) -> String:
 if not value is Dictionary or not value.get("mounts") is Array: return "Configuración de montajes inválida."
 if value.mounts.is_empty() or value.mounts.size() > MAX_MOUNTS: return "La nave necesita entre 1 y 8 montajes."
 var ids: Array = []
 for mount in value.mounts:
  if not mount is Dictionary: return "Montaje inválido."
  var id = str(mount.get("id", ""))
  if id.is_empty() or id.length() > 32 or id in ids: return "Identificador de montaje inválido o repetido."
  ids.append(id)
  if str(mount.get("name", "")).is_empty() or str(mount.get("name", "")).length() > 48: return "Nombre de montaje inválido."
  if mount.get("kind") not in MOUNT_KINDS: return "Tipo de montaje desconocido."
  for field in ["arc_center", "arc", "range", "damage", "cycle", "energy"]:
   if not Catalog.finite_number(mount.get(field)): return "Parámetro de montaje inválido: " + field
  if absf(float(mount.arc_center)) > 180 or float(mount.arc) <= 0 or float(mount.arc) > 360: return "Arco de montaje fuera de rango."
  if float(mount.range) < 50 or float(mount.range) > 3000 or float(mount.damage) < 0 or float(mount.damage) > 100: return "Prestación de montaje fuera de rango."
  if float(mount.cycle) < 0.1 or float(mount.cycle) > 30 or float(mount.energy) < 0 or float(mount.energy) > 40: return "Ciclo o energía de montaje fuera de rango."
  if mount.has("ready_at") and (not Catalog.finite_number(mount.ready_at) or float(mount.ready_at) < 0): return "Recarga de montaje inválida."
  if mount.has("auto_target") and not mount.auto_target is String: return "Blanco automático inválido."
 return ""

func ensure() -> Dictionary:
 var session = _session()
 if session == null or session.sim.state.is_empty(): return {}
 var ship: Dictionary = session.sim.state.ship
 if not ship.has("loadout") or not validate_loadout(ship.loadout).is_empty():
  var authored = session.sim.state.mission.get("ship_loadout", {})
  ship.loadout = authored.duplicate(true) if authored is Dictionary and validate_loadout(authored).is_empty() else template("exploracion")
  for mount in ship.loadout.mounts:
   if not mount.has("ready_at"): mount.ready_at = 0.0
   if not mount.has("auto_target"): mount.auto_target = ""
 return ship.loadout

func command(operation: String, args: Dictionary = {}) -> Dictionary:
 if args.size() > 6: return _result(false, "Demasiados parámetros de armamento.")
 var session = _session()
 if session != null and session.mode == "client":
  _receive_command.rpc_id(1, operation, args)
  return _result(true, "Orden de armamento enviada al anfitrión.")
 var response = _perform(operation, args, session.role if session != null else "armas")
 notice.emit(response.message, response.ok)
 if response.ok:
  updated.emit()
  if session != null: session._refresh_view()
 return response

@rpc("any_peer", "call_remote", "reliable", 3)
func _receive_command(operation: String, args: Dictionary) -> void:
 var session = _session()
 if session == null or session.mode != "host": return
 var peer = multiplayer.get_remote_sender_id()
 if not session.roster.has(peer): return
 var response = _perform(operation, args, str(session.roster[peer].role))
 _response.rpc_id(peer, response.message, response.ok)
 if response.ok:
  updated.emit()
  session._refresh_view()

@rpc("authority", "call_remote", "reliable", 3)
func _response(text: String, ok: bool) -> void:
 notice.emit(text, ok)
 updated.emit()

func _perform(operation: String, args: Dictionary, role: String) -> Dictionary:
 var session = _session()
 if session == null or session.sim.state.is_empty(): return _result(false, "No hay nave activa.")
 var loadout = ensure()
 if loadout.is_empty(): return _result(false, "No hay configuración de armamento.")
 if operation == "template":
  if role not in ["mando", "armas"]: return _result(false, "Mando o Armas configuran los montajes.")
  if session.sim.state.ship.docked.is_empty() and session.sim.state.time > 0.5: return _result(false, "Los montajes sólo se reconfiguran atracados o antes de zarpar.")
  var template_id = str(args.get("template", ""))
  if template_id not in TEMPLATES: return _result(false, "Plantilla de armamento desconocida.")
  session.sim.state.ship.loadout = template(template_id)
  return _result(true, "Configuración aplicada: " + TEMPLATES[template_id].name + ".")
 if role != "armas": return _result(false, "Esta orden pertenece al puesto de Armas.")
 var mount = _mount(str(args.get("mount", "")))
 if mount.is_empty(): return _result(false, "Selecciona un montaje válido.")
 if operation == "auto_target":
  var target_id = str(args.get("target", ""))
  if target_id.is_empty():
   mount.auto_target = ""
   return _result(true, "Fuego automático desactivado en " + mount.name + ".")
  var target = session.sim.contact(target_id)
  if not _valid_target(target): return _result(false, "El blanco automático debe ser hostil, identificado y activo.")
  mount.auto_target = target_id
  return _result(true, mount.name + " seguirá al blanco mientras permanezca en arco.")
 if operation == "fire": return _fire_mount(session.sim, mount, str(args.get("target", "")), false)
 return _result(false, "Orden de montaje desconocida.")

func _mount(id: String) -> Dictionary:
 var loadout = ensure()
 for mount in loadout.get("mounts", []):
  if mount.id == id: return mount
 return {}

func _valid_target(target: Dictionary) -> bool:
 return not target.is_empty() and bool(target.get("identified", false)) and target.get("kind") == "hostile" and float(target.get("hull", 0)) > 0 and not bool(target.get("pacified", false))

func _in_arc(ship: Dictionary, mount: Dictionary, position: Array) -> bool:
 if float(mount.arc) >= 359.9: return true
 var relative = wrapf(ShipModel.angle_error(ship, ShipModel.bearing(ship, position)) - float(mount.arc_center), -180.0, 180.0)
 return absf(relative) <= float(mount.arc) * 0.5

func _fire_mount(sim, mount: Dictionary, target_id: String, automatic: bool) -> Dictionary:
 var target = sim.contact(target_id)
 if not _valid_target(target): return _result(false, "Selecciona un hostil identificado y activo.")
 var ship: Dictionary = sim.state.ship
 if ShipModel.efficiency(ship, "armas") <= 0: return _result(false, "Sistema de armas inoperativo.")
 if sim.distance_to(target) > float(mount.range): return _result(false, "Blanco fuera del alcance de " + mount.name + ".")
 if not _in_arc(ship, mount, target.position): return _result(false, "Blanco fuera del arco de " + mount.name + ".")
 if float(mount.ready_at) > sim.state.time: return _result(false, "Montaje recargando.")
 if float(ship.energy) < float(mount.energy): return _result(false, "Energía insuficiente para el montaje.")
 ship.energy -= float(mount.energy)
 var efficiency = ShipModel.efficiency(ship, "armas")
 var damage = float(mount.damage) * efficiency
 if int(sim.state.operations.beam_frequency) == int(target.get("frequency", -1)) and mount.kind in ["beam", "turret"]: damage *= 1.2
 target.hull = maxf(0.0, float(target.hull) - damage)
 if mount.kind == "emp":
  target.attack_at = maxf(float(target.get("attack_at", 0.0)), sim.state.time + 12.0)
  target.jammed = false
 mount.ready_at = sim.state.time + float(mount.cycle) / maxf(0.25, efficiency)
 ship.systems.armas.heat = minf(120.0, float(ship.systems.armas.heat) + (7.0 if mount.kind == "rail" else 3.5))
 if target.hull <= 0:
  sim.fact("defeat", target.id)
  mount.auto_target = ""
 sim.log_event("Armas", "%s: %s sobre %s · integridad %d%%." % ["AUTO" if automatic else "FUEGO", mount.name, target.name, int(target.hull)])
 return _result(true, "%s impacta. Integridad del blanco: %d%%." % [mount.name, int(target.hull)])

func _process(delta: float) -> void:
 var session = _session()
 if session == null or not _authority() or session.sim.state.is_empty(): return
 ensure()
 _auto_clock += delta
 if _auto_clock < 0.2: return
 _auto_clock = 0.0
 var changed = false
 for mount in session.sim.state.ship.loadout.mounts:
  var target_id = str(mount.get("auto_target", ""))
  if target_id.is_empty(): continue
  var target = session.sim.contact(target_id)
  if not _valid_target(target):
   mount.auto_target = ""
   changed = true
   continue
  if float(mount.ready_at) <= session.sim.state.time and session.sim.distance_to(target) <= float(mount.range) and _in_arc(session.sim.state.ship, mount, target.position):
   var response = _fire_mount(session.sim, mount, target_id, true)
   changed = changed or response.ok
 if changed:
  updated.emit()
  session._refresh_view()

func _unhandled_key_input(event: InputEvent) -> void:
 if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_F7: return
 if _window != null and is_instance_valid(_window):
  _window.queue_free()
  _window = null
 else:
  _window = ArmamentConsole.new()
  _window.armaments = self
  get_tree().root.add_child(_window)
  _window.close_requested.connect(func(): _window.queue_free(); _window = null)
  _window.popup_centered()
 get_viewport().set_input_as_handled()

func _result(ok: bool, message: String) -> Dictionary:
 return {"ok": ok, "message": message}
