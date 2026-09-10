class_name ShipOperations
extends RefCounted
## Native station operations. The host owns resources, timers and permissions.

const PERMISSIONS = {
 "mando": ["destruct_confirm"],
 "navegacion": ["warp", "jump", "strafe", "request_dock", "abort_dock", "route_follow"],
 "ingenieria": ["auto_repair", "coolant_level", "shield_frequency", "destruct_arm", "destruct_cancel", "destruct_confirm"],
 "armas": ["shields", "weapon_target", "beam_frequency", "tube_load", "tube_unload", "tube_fire", "destruct_confirm"],
 "sensores": ["scan_cancel", "database_record"],
 "comunicaciones": ["comm_open", "comm_close", "comm_message", "comm_reply"],
 "enlace": ["waypoint_add", "waypoint_move", "waypoint_remove", "science_link", "science_unlink", "alert"],
 "reparaciones": ["crew_move"]
}
const AMMO = ["homing", "nuke", "mine", "emp", "hvli"]
const ROOM_POSITIONS = {"reactor": [0.0, 12.0], "motores": [-10.0, 12.0], "maniobra": [-8.0, 6.0], "warp": [-5.0, 12.0], "salto": [5.0, 12.0], "escudos": [10.0, -6.0], "escudos_popa": [10.0, 12.0], "armas": [-10.0, -12.0], "misiles": [-10.0, -8.0], "sensores": [10.0, -12.0]}
const CONFIRMERS = ["mando", "ingenieria", "armas"]

static func initialize(state: Dictionary) -> void:
 if state.has("operations"): return
 state.operations = {"warp": 0, "maneuver": 100.0, "jump": {"remaining": 0.0, "distance": 0.0}, "docking": "", "shield_frequency": 0, "calibration": 0.0, "auto_repair": false,
  "beam_frequency": 0, "weapon_target": "", "science_link": "", "route": "", "waypoints": [], "next_waypoint": 1, "coolant": {"motores": 0.0, "escudos": 0.0, "armas": 0.0, "sensores": 0.0},
  "tubes": [{"ammo": "", "remaining": 0.0}, {"ammo": "", "remaining": 0.0}], "ammo": {"homing": 8, "nuke": 2, "mine": 4, "emp": 4, "hvli": 12}, "mines": [],
  "crews": [{"id": "equipo-1", "position": [0.0, 0.0], "destination": "", "work": 0.0}, {"id": "equipo-2", "position": [0.0, 0.0], "destination": "", "work": 0.0}],
  "comms": {"target": "", "messages": [], "replies": []}, "database": {},
  "destruct": {"armed": false, "codes": {}, "confirmed": {}, "principals": [], "remaining": -1.0}}
 for system in Catalog.SYSTEMS: state.operations.coolant[system] = 0.0
 if state.ship.has("design"): state.operations.ammo = state.ship.design.ammo.duplicate(true)

static func number(args: Dictionary, field: String, low: float, high: float, integer: bool = false) -> bool:
 var value = args.get(field)
 return Catalog.finite_number(value) and float(value) >= low and float(value) <= high and (not integer or float(value) == floorf(float(value)))

static func result(ok: bool, message: String) -> Dictionary:
 return {"ok": ok, "message": message}

static func perform(sim, role: String, operation: String, args: Dictionary, principal: String) -> Dictionary:
 var s: Dictionary = sim.state
 var ship: Dictionary = s.ship
 var o: Dictionary = s.operations
 var c: Dictionary = sim.contact(str(args.get("target", "")))
 var message = ""
 match operation:
  "warp":
   if not number(args, "level", 0, 4, true): return result(false, "El nivel warp debe ser un entero entre 0 y 4.")
   if int(args.level) > 0 and (not ship.docked.is_empty() or ship.fuel < 5 or ship.energy < 20 or o.jump.remaining > 0 or ship.throttle < 0 or ship.design.warp_speed <= 0 or ShipModel.efficiency(ship, "warp") <= 0): return result(false, "Warp requiere motor operativo, vuelo hacia delante, 5 de combustible y 20 de energía.")
   o.warp = int(args.level)
   message = "Motor warp ajustado al nivel %d." % o.warp
  "jump":
   if not number(args, "distance", 100, ship.design.jump_range): return result(false, "Distancia de salto fuera de la capacidad de esta nave.")
   if not ship.docked.is_empty() or o.jump.remaining > 0 or o.maneuver < 100 or ship.energy < 40 or ShipModel.efficiency(ship, "salto") <= 0: return result(false, "Salto requiere motor operativo, 100% de carga, 40 de energía y vuelo libre.")
   ship.energy -= 40
   o.maneuver = 0.0
   o.warp = 0
   ship.autopilot = ""
   ship.throttle = 0.0
   o.jump = {"remaining": 5.0, "distance": float(args.distance)}
   message = "Salto cargando durante 5 segundos. Mantén el rumbo."
  "strafe":
   if not number(args, "amount", -1, 1) or is_zero_approx(float(args.amount)): return result(false, "Selecciona un desplazamiento lateral entre −1 y 1, distinto de cero.")
   var cost = absf(float(args.amount)) * 30.0
   if not ship.docked.is_empty() or o.maneuver < cost or ship.energy < cost / 3 or ShipModel.efficiency(ship, "maniobra") <= 0: return result(false, "Maniobra inoperativa, sin carga suficiente o nave atracada.")
   o.maneuver -= cost
   ship.energy -= cost / 3
   var direction = Vector2.from_angle(deg_to_rad(ship.heading) + PI / 2) * float(args.amount) * 90
   ship.position = [clampf(ship.position[0] + direction.x, -14000, 14000), clampf(ship.position[1] + direction.y, -14000, 14000)]
   message = "Maniobra lateral ejecutada; carga consumida: %d%%." % cost
  "request_dock":
   if c.is_empty() or c.kind != "station" or c.hull <= 0 or sim.distance_to(c) > 2500: return result(false, "Selecciona una estación activa a menos de 2500 m.")
   if not ship.docked.is_empty(): return result(false, "La nave ya está atracada.")
   o.docking = c.id
   o.warp = 0
   ship.autopilot = c.id
   ship.throttle = 1.0
   message = "Aproximación de atraque iniciada. Puedes cancelarla antes de enganchar las amarras."
  "abort_dock":
   if o.docking.is_empty(): return result(false, "No hay aproximación de atraque que cancelar.")
   o.docking = ""
   ship.autopilot = ""
   ship.throttle = 0.0
   message = "Aproximación cancelada. Frenado de la nave."
  "auto_repair":
   if not args.get("enabled") is bool: return result(false, "Selecciona el estado de reparación automática.")
   o.auto_repair = args.enabled
   message = "Reparación automática " + ("activada." if args.enabled else "desactivada.")
  "coolant_level":
   var system = str(args.get("system", ""))
   if system not in Catalog.SYSTEMS or not number(args, "value", 0, 8): return result(false, "Sistema o refrigerante fuera de rango: 0–8.")
   var total = float(args.value)
   for key in o.coolant:
    if key != system: total += o.coolant[key]
   if total > 8: return result(false, "El circuito dispone de 8 unidades de refrigerante.")
   o.coolant[system] = float(args.value)
   ship.coolant = ""
   message = "Refrigerante de %s: %.1f / 8." % [system, args.value]
  "shield_frequency", "beam_frequency":
   if not number(args, "frequency", 0, 20, true): return result(false, "La frecuencia debe estar entre 0 y 20.")
   o[operation] = int(args.frequency)
   if operation == "shield_frequency":
    o.calibration = 5.0
    ship.shields_enabled = false
   message = "Escudos recalibrándose durante 5 segundos; vuelve a subirlos al terminar." if operation == "shield_frequency" else "Frecuencia del haz ajustada a %d." % args.frequency
  "weapon_target":
   if str(args.get("target", "")).is_empty():
    o.weapon_target = ""
    return result(true, "Fuego automático desactivado.")
   if c.is_empty() or not c.identified or c.kind != "hostile" or c.hull <= 0 or c.pacified: return result(false, "Selecciona un hostil identificado y activo.")
   o.weapon_target = c.id
   message = "Haces automáticos fijados al blanco identificado."
  "tube_load", "tube_unload", "tube_fire":
   if not number(args, "tube", 0, 1, true): return result(false, "Selecciona el tubo 1 o el tubo 2.")
   var tube: Dictionary = o.tubes[int(args.tube)]
   if operation == "tube_load":
    var ammo = str(args.get("ammo", ""))
    if ammo not in AMMO or not tube.ammo.is_empty() or o.ammo.get(ammo, 0) < 1: return result(false, "Tubo ocupado o sin munición del tipo elegido.")
    o.ammo[ammo] -= 1
    tube.ammo = ammo
    tube.remaining = 4.0
    message = "Tubo %d cargando %s: 4 segundos." % [int(args.tube) + 1, ammo]
   elif operation == "tube_unload":
    if tube.ammo.is_empty(): return result(false, "El tubo ya está vacío.")
    o.ammo[tube.ammo] += 1
    tube.ammo = ""
    tube.remaining = 0.0
    message = "Munición devuelta al almacén."
   else:
    if tube.ammo.is_empty() or tube.remaining > 0 or ShipModel.efficiency(ship, "misiles") <= 0: return result(false, "Tubo sin cargar o sistema de misiles inoperativo.")
    if tube.ammo == "mine" and o.mines.size() >= 64: return result(false, "Hay demasiadas minas desplegadas.")
    if tube.ammo != "mine" and (c.is_empty() or not c.identified or c.kind != "hostile" or c.pacified or c.hull <= 0 or sim.distance_to(c) > ship.design.missile_range): return result(false, "El tubo necesita un hostil identificado dentro del alcance de esta nave.")
    var ammo: String = tube.ammo
    if ammo == "mine": o.mines.append({"position": ship.position.duplicate(), "armed_at": s.time + 3.0})
    elif ammo == "emp": c.attack_at = s.time + 18.0
    elif ammo == "nuke":
     for enemy in s.contacts:
      if enemy.kind == "hostile" and not enemy.pacified and Vector2(enemy.position[0], enemy.position[1]).distance_to(Vector2(c.position[0], c.position[1])) < 300: _damage(sim, enemy, 90)
    else: _damage(sim, c, 38 if ammo == "homing" else 20)
    tube.ammo = ""
    tube.remaining = 0.0
    ship.systems.misiles.heat = minf(120, ship.systems.misiles.heat + 8)
    message = "Tubo %d disparado: %s." % [int(args.tube) + 1, ammo]
  "scan_cancel":
   if s.scan.target.is_empty(): return result(false, "No hay un análisis en curso.")
   s.scan = {"target": "", "remaining": 0.0}
   message = "Análisis cancelado."
  "database_record":
   if c.is_empty() or not c.identified: return result(false, "Solo puedes archivar contactos identificados.")
   var entry = {"name": c.name, "kind": c.kind, "sector": s.mission.sector, "hull": c.hull, "position": c.position.duplicate(), "frequency": int(c.get("frequency", 0))}
   o.database[c.id] = entry
   if not s.campaign.has("discoveries"): s.campaign.discoveries = {}
   s.campaign.discoveries[s.mission.id + ":" + c.id] = entry.duplicate(true)
   message = "Contacto archivado en la base científica y en los descubrimientos de campaña."
  "comm_open":
   if c.is_empty() or c.hull <= 0 or sim.distance_to(c) > 900: return result(false, "Selecciona un contacto activo a menos de 900 m.")
   o.comms.target = c.id
   c.hailed = true
   sim.fact("hail", c.id)
   o.comms.replies = ["estado", "suministros", "alto_el_fuego"] if c.kind in ["station", "friendly", "hostile"] else ["estado"]
   _message(o, c.name if c.identified else "Contacto", "Canal abierto. ¿Qué necesita la Itsaso?")
   message = "Canal de comunicaciones abierto."
  "comm_close":
   if o.comms.target.is_empty(): return result(false, "No hay un canal abierto.")
   o.comms.target = ""
   o.comms.replies = []
   message = "Canal de comunicaciones cerrado."
  "comm_message", "comm_reply":
   var partner = sim.contact(o.comms.target)
   if partner.is_empty() or partner.hull <= 0 or sim.distance_to(partner) > 900: return result(false, "Abre un canal con un contacto en alcance.")
   if operation == "comm_message":
    var content = str(args.get("text", "")).strip_edges()
    if content.is_empty(): return result(false, "El mensaje no puede estar vacío.")
    _message(o, "Itsaso", content)
    _message(o, partner.name if partner.identified else "Contacto", "Recibido. Mantendremos abierto el canal.")
   else:
    var choice = str(args.get("reply", ""))
    if choice not in o.comms.replies: return result(false, "Esa respuesta no pertenece al diálogo abierto.")
    if choice == "alto_el_fuego":
     if not partner.identified or ship.shields_enabled: return result(false, "Identifica al interlocutor y baja los escudos para negociar.")
     partner.pacified = true
     partner.negotiated = true
     _message(o, partner.name, "Aceptamos la tregua. Podéis continuar vuestro viaje.")
    elif choice == "suministros": _message(o, partner.name, "Atracad en una estación para reparar casco y reponer combustible y energía.")
    else: _message(o, partner.name if partner.identified else "Contacto", "Integridad del casco: %d%%." % partner.hull)
   message = "Respuesta registrada en el canal."
  "waypoint_add", "waypoint_move":
   if not number(args, "bearing", -360, 360) or not number(args, "distance", 0, 12000): return result(false, "Usa una marcación entre −360° y 360° y una distancia de 0 a 12000 m.")
   var offset = Vector2.from_angle(deg_to_rad(float(args.bearing))) * float(args.distance)
   var position = [ship.position[0] + offset.x, ship.position[1] + offset.y]
   if absf(position[0]) > 14000 or absf(position[1]) > 14000: return result(false, "El punto queda fuera del sector.")
   if operation == "waypoint_add":
    if o.waypoints.size() >= 16: return result(false, "El sector admite hasta 16 puntos de ruta.")
    var id = "ruta-%d" % o.next_waypoint
    o.next_waypoint += 1
    o.waypoints.append({"id": id, "name": str(args.get("name", id)).left(40), "position": position})
   else:
    var waypoint = find_waypoint(o, str(args.get("id", "")))
    if waypoint.is_empty(): return result(false, "Ese punto de ruta no existe.")
    waypoint.position = position
   message = "Punto de ruta guardado en el mapa compartido."
  "waypoint_remove":
   var waypoint = find_waypoint(o, str(args.get("id", "")))
   if waypoint.is_empty(): return result(false, "Ese punto de ruta no existe.")
   if o.route == waypoint.id: o.route = ""; ship.throttle = 0.0
   o.waypoints.erase(waypoint)
   message = "Punto de ruta retirado."
  "route_follow":
   var waypoint = find_waypoint(o, str(args.get("id", "")))
   if waypoint.is_empty() or not ship.docked.is_empty(): return result(false, "Selecciona una ruta válida y desatraca.")
   o.route = waypoint.id
   ship.autopilot = ""
   ship.throttle = 1.0
   message = "Siguiendo punto de ruta: " + waypoint.name + "."
  "science_link":
   if c.is_empty() or not c.probed: return result(false, "Selecciona un contacto con una sonda desplegada.")
   o.science_link = c.id
   message = "Sensores recibe la vista de la sonda desplegada."
  "science_unlink":
   o.science_link = ""
   message = "Sensores vuelve al radar de la nave."
  "crew_move":
   var team: Dictionary = {}
   for candidate in o.crews:
    if candidate.id == args.get("crew"): team = candidate
   var destination = str(args.get("system", ""))
   if team.is_empty() or destination not in Catalog.SYSTEMS: return result(false, "Selecciona un equipo y una sala de sistemas válidos.")
   team.destination = destination
   team.work = 0.0
   message = "%s se desplaza hasta %s. La reparación empieza al llegar." % [team.id, destination]
  "destruct_arm":
   if args.get("confirmation") != "ITSASO": return result(false, "Para armar la secuencia escribe ITSASO. Tres puestos deben confirmar después.")
   if o.destruct.armed: return result(false, "La secuencia ya está armada.")
   var codes = {}
   var rng = RandomNumberGenerator.new()
   rng.randomize()
   for station in CONFIRMERS: codes[station] = str(rng.randi_range(1000, 9999))
   o.destruct = {"armed": true, "codes": codes, "confirmed": {}, "principals": [], "remaining": -1.0}
   message = "Secuencia armada. Mando, Ingeniería y Armas deben confirmar su propio código."
  "destruct_cancel":
   if not o.destruct.armed: return result(false, "La secuencia no está armada.")
   o.destruct = {"armed": false, "codes": {}, "confirmed": {}, "principals": [], "remaining": -1.0}
   message = "Secuencia de autodestrucción cancelada."
  "destruct_confirm":
   if not o.destruct.armed or role not in CONFIRMERS or o.destruct.confirmed.has(role): return result(false, "No hay una confirmación pendiente para tu puesto.")
   if str(args.get("code", "")) != str(o.destruct.codes.get(role, "")): return result(false, "El código no coincide con el de tu puesto.")
   if principal != "local" and principal in o.destruct.principals: return result(false, "En red cada confirmación necesita una persona distinta.")
   o.destruct.confirmed[role] = true
   o.destruct.principals.append(principal)
   if o.destruct.confirmed.size() == 3: o.destruct.remaining = 15.0
   message = "Confirmación registrada: %d / 3." % o.destruct.confirmed.size()
  _: return result(false, "Orden operativa desconocida.")
 return result(true, message)

static func find_waypoint(o: Dictionary, id: String) -> Dictionary:
 for point in o.waypoints:
  if point.id == id: return point
 return {}

static func _message(o: Dictionary, speaker: String, text: String) -> void:
 o.comms.messages.append({"speaker": speaker, "text": text})
 if o.comms.messages.size() > 40: o.comms.messages.pop_front()

static func _damage(sim, c: Dictionary, damage: float) -> void:
 c.hull = maxf(0, c.hull - damage)
 if c.hull <= 0: sim.fact("defeat", c.id)

static func tick(sim, delta: float) -> void:
 var s: Dictionary = sim.state
 var ship: Dictionary = s.ship
 var o: Dictionary = s.operations
 o.maneuver = minf(100, o.maneuver + 4.0 * ShipModel.efficiency(ship, "maniobra") * delta)
 o.calibration = maxf(0, o.calibration - delta)
 if o.calibration > 0: ship.shields_enabled = false
 if o.warp > 0:
  ship.energy = maxf(0, ship.energy - o.warp * 4.0 * delta)
  ship.fuel = maxf(0, ship.fuel - o.warp * 0.08 * delta)
  if ship.energy < 5 or ship.fuel <= 0 or not ship.docked.is_empty() or ShipModel.efficiency(ship, "warp") <= 0: o.warp = 0
 if o.jump.remaining > 0:
  o.jump.remaining = maxf(0, o.jump.remaining - ShipModel.efficiency(ship, "salto") * delta)
  if o.jump.remaining <= 0:
   var offset = Vector2.from_angle(deg_to_rad(ship.heading)) * o.jump.distance
   ship.position = [clampf(ship.position[0] + offset.x, -14000, 14000), clampf(ship.position[1] + offset.y, -14000, 14000)]
   sim.log_event("Navegación", "Salto completado: %d m." % o.jump.distance)
 if not o.route.is_empty():
  var waypoint = find_waypoint(o, o.route)
  if waypoint.is_empty() or not ship.docked.is_empty(): o.route = ""
  else:
   var offset = Vector2(waypoint.position[0] - ship.position[0], waypoint.position[1] - ship.position[1])
   ship.target_heading = fposmod(rad_to_deg(offset.angle()), 360.0)
   ship.throttle = clampf((offset.length() - 20) / 200, 0, 1)
   if offset.length() < 30:
    o.route = ""
    ship.throttle = 0.0
    sim.log_event("Navegación", "Punto de ruta alcanzado: " + waypoint.name)
 if not o.docking.is_empty():
  var station = sim.contact(o.docking)
  if station.is_empty() or station.hull <= 0: o.docking = ""; ship.autopilot = ""; ship.throttle = 0.0
  elif sim.distance_to(station) < 160 and ship.speed < 35:
   var docked = sim.command("navegacion", "dock", {"target": station.id})
   if docked.ok: o.docking = ""
 for system in Catalog.SYSTEMS: ship.systems[system].heat = maxf(0, ship.systems[system].heat - float(o.coolant[system]) * 2.0 * delta)
 for tube in o.tubes: tube.remaining = maxf(0, tube.remaining - ShipModel.efficiency(ship, "misiles") * delta)
 for mine in o.mines.duplicate():
  if mine.armed_at > s.time: continue
  for enemy in s.contacts:
   if enemy.kind == "hostile" and enemy.hull > 0 and not enemy.pacified and Vector2(enemy.position[0], enemy.position[1]).distance_to(Vector2(mine.position[0], mine.position[1])) < 150:
    _damage(sim, enemy, 65)
    o.mines.erase(mine)
    sim.log_event("Armas", "Mina detonada contra un contacto hostil.")
    break
 for team in o.crews:
  if o.auto_repair and (team.destination.is_empty() or ship.systems[team.destination].health >= 100):
   var weakest = ""
   var health = 100.0
   for system in Catalog.SYSTEMS:
    if ship.systems[system].health < health: health = ship.systems[system].health; weakest = system
   team.destination = weakest
  if team.destination.is_empty(): continue
  var target: Array = ROOM_POSITIONS[team.destination]
  var position = Vector2(team.position[0], team.position[1]).move_toward(Vector2(target[0], target[1]), 3.0 * delta)
  team.position = [position.x, position.y]
  if position.distance_to(Vector2(target[0], target[1])) < 0.1 and ship.parts >= 2 and ship.systems[team.destination].health < 100:
   team.work += delta
   if team.work >= 5:
    team.work = 0.0
    ship.parts -= 2
    ship.systems[team.destination].health = minf(100, ship.systems[team.destination].health + 25)
    sim.log_event("Control de daños", "%s reparó %s: +25 de integridad." % [team.id, team.destination])
 if not o.weapon_target.is_empty():
  var target = sim.contact(o.weapon_target)
  if target.is_empty() or target.hull <= 0 or target.pacified: o.weapon_target = ""
  elif ship.weapon_ready <= s.time and ship.energy >= 12 and sim.distance_to(target) <= ship.design.beam_range and ShipModel.efficiency(ship, "armas") > 0 and ShipModel.in_beam_arc(ship, target.position):
   sim.command("armas", "fire", {"target": target.id})
 if o.destruct.armed and o.destruct.remaining >= 0:
  o.destruct.remaining = maxf(0, o.destruct.remaining - delta)
  if o.destruct.remaining <= 0:
   ship.hull = 0.0
   o.destruct.armed = false
   o.destruct.codes = {}
   for c in s.contacts:
    if sim.distance_to(c) < 800: _damage(sim, c, 200)
   sim.log_event("Mando", "Secuencia de autodestrucción completada.")

static func redact(state: Dictionary, role: String) -> void:
 if not state.has("operations"): return
 var destruct: Dictionary = state.operations.destruct
 var code = str(destruct.codes.get(role, ""))
 destruct.codes = {role: code} if not role.is_empty() and not code.is_empty() else {}
 destruct.erase("principals")

static func validate(value: Variant, legacy: bool = false) -> String:
 if not value is Dictionary: return "Operaciones de nave inválidas."
 var reference = {"ship": {}}
 initialize(reference)
 if value.keys().size() != reference.operations.keys().size(): return "Contrato de operaciones incompleto."
 for key in reference.operations:
  if not value.has(key) or typeof(value[key]) != typeof(reference.operations[key]) and not (Catalog.finite_number(value[key]) and Catalog.finite_number(reference.operations[key])): return "Campo de operaciones inválido: " + key
 for field in ["warp", "maneuver", "shield_frequency", "calibration", "beam_frequency", "next_waypoint"]:
  if not Catalog.finite_number(value[field]) or value[field] < 0 or value[field] > 100000: return "Contador de operaciones inválido."
 if value.warp > 4 or value.maneuver > 100 or value.shield_frequency > 20 or value.beam_frequency > 20: return "Operaciones fuera de rango."
 if value.tubes.size() != 2 or value.crews.size() != 2 or value.waypoints.size() > 16 or value.mines.size() > 64: return "Colección de operaciones inválida."
 for tube in value.tubes:
  if not tube is Dictionary or tube.get("ammo") not in AMMO + [""] or not number(tube, "remaining", 0, 4): return "Tubo inválido."
 for ammo in AMMO:
  if not number(value.ammo, ammo, 0, 1000, true): return "Munición inválida."
 var coolant = 0.0
 for system in Catalog.SYSTEMS:
  if legacy and system not in ShipModel.LEGACY_SYSTEMS: continue
  if not number(value.coolant, system, 0, 8): return "Refrigerante inválido."
  coolant += value.coolant[system]
 if coolant > 8: return "Presupuesto de refrigerante excedido."
 if not number(value.jump, "remaining", 0, 5) or not number(value.jump, "distance", 0, 10000): return "Salto inválido."
 var identifiers = []
 for point in value.waypoints:
  if not point is Dictionary or not point.get("id") is String or point.id in identifiers or not point.get("name") is String or not valid_position(point.get("position")): return "Punto de ruta inválido."
  identifiers.append(point.id)
 identifiers = []
 for team in value.crews:
  if not team is Dictionary or team.get("id") not in ["equipo-1", "equipo-2"] or team.id in identifiers or team.get("destination") not in Catalog.SYSTEMS + [""] or not valid_position(team.get("position")) or not number(team, "work", 0, 5): return "Equipo de reparación inválido."
  identifiers.append(team.id)
 for mine in value.mines:
  if not mine is Dictionary or not valid_position(mine.get("position")) or not number(mine, "armed_at", 0, 1e12): return "Mina inválida."
 var d = value.destruct
 if not d.get("armed") is bool or not d.get("codes") is Dictionary or not d.get("confirmed") is Dictionary or not d.get("principals") is Array or not number(d, "remaining", -1, 15): return "Secuencia inválida."
 if d.armed and d.codes.size() != 3: return "Secuencia incompleta."
 for role in d.codes:
  if role not in CONFIRMERS or not d.codes[role] is String or not d.codes[role].is_valid_int() or d.codes[role].length() != 4: return "Código de secuencia inválido."
 for role in d.confirmed:
  if role not in CONFIRMERS or d.confirmed[role] != true: return "Confirmación inválida."
 if not value.comms.get("target") is String or not value.comms.get("messages") is Array or not value.comms.get("replies") is Array or value.comms.messages.size() > 40: return "Canal inválido."
 for reply in value.comms.replies:
  if reply not in ["estado", "suministros", "alto_el_fuego"]: return "Respuesta de diálogo inválida."
 for entry in value.database.values():
  if not entry is Dictionary or not entry.get("name") is String or not entry.get("kind") is String or not entry.get("sector") is String or not valid_position(entry.get("position")) or not number(entry, "hull", 0, 100000) or not number(entry, "frequency", 0, 20, true): return "Registro científico inválido."
 for message in value.comms.messages:
  if not message is Dictionary or not message.get("speaker") is String or not message.get("text") is String: return "Mensaje inválido."
 return ""

static func valid_position(value: Variant) -> bool:
 return value is Array and value.size() == 2 and Catalog.finite_number(value[0]) and Catalog.finite_number(value[1]) and absf(value[0]) <= 14000 and absf(value[1]) <= 14000
