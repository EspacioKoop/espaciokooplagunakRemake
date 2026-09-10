class_name Simulation
extends RefCounted
## Deterministic, authoritative simulation. No scene, network or Foundry dependency.

var state: Dictionary = {}

func start(mission: Dictionary, carry: Dictionary = {}, base_hull: float = 100.0) -> void:
	assert(Catalog.validate_mission(mission).is_empty())
	var campaign = carry.get("campaign", {"completed": [], "credits": 0, "reputation": 0, "survivors": 0, "decisions": {}, "upgrades": 0}).duplicate(true)
	var maximum = base_hull + int(campaign.upgrades) * 15.0
	state = {"version": 1, "mission": mission.duplicate(true), "campaign": campaign, "time": 0.0, "status": "active", "objective": 0, "facts": {}, "events": [], "sequence": 0,
		"scan": {"target": "", "remaining": 0.0}, "repair": {"system": "", "remaining": 0.0},
		"ship": {"position": [0.0, 0.0], "heading": 0.0, "speed": 0.0, "throttle": 0.0, "autopilot": "", "docked": "", "hull": maximum, "max_hull": maximum, "shield": 100.0, "shields_enabled": true,
		"energy": 100.0, "fuel": 100.0, "torpedoes": 10, "probes": 4, "parts": 24, "alert": "verde", "coolant": "", "boost_until": 0.0, "weapon_ready": 0.0, "assist": {}, "systems": {}}, "contacts": []}
	for system in Catalog.SYSTEMS:
		state.ship.systems[system] = {"power": 2, "heat": 10.0, "health": 100.0}
	for original in mission.contacts:
		var c: Dictionary = original.duplicate(true)
		c.merge({"identified": c.get("known", false), "jammed": false, "known": false, "hull": 100.0, "hailed": false, "negotiated": false, "rescued": false, "salvaged": false, "probed": false, "pacified": false, "attack_at": 0.0, "survivors": 6}, false)
		state.contacts.append(c)
	log_event("Misión iniciada", mission.title)

func contact(id: String) -> Dictionary:
	for c in state.get("contacts", []):
		if c.id == id:
			return c
	return {}

func distance_to(c: Dictionary) -> float:
	if c.is_empty():
		return INF
	return Vector2(state.ship.position[0], state.ship.position[1]).distance_to(Vector2(c.position[0], c.position[1]))

func reply(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}

func command(role: String, operation: String, args: Dictionary = {}) -> Dictionary:
	if state.is_empty() or state.status != "active":
		return reply(false, "La misión no está activa.")
	if operation not in Catalog.PERMISSIONS.get(role, []):
		return reply(false, "Esta orden pertenece a otro puesto.")
	if args.size() > 8:
		return reply(false, "Demasiados parámetros.")
	for key in args:
		if not key is String or not (args[key] is String or args[key] is bool or Catalog.finite_number(args[key])):
			return reply(false, "Parámetro no válido.")
		if args[key] is String and args[key].length() > 80:
			return reply(false, "Parámetro demasiado largo.")
	var ship: Dictionary = state.ship
	var c: Dictionary = contact(str(args.get("target", "")))
	var system = str(args.get("system", ""))
	var message = "Orden ejecutada."
	if operation in ["autopilot", "dock", "fire", "missile", "scan", "hail", "negotiate", "probe", "salvage", "rescue", "repair_target"] and c.is_empty():
		return reply(false, "Selecciona un contacto del sector.")
	if operation in ["power", "coolant", "repair"] and system not in Catalog.SYSTEMS:
		return reply(false, "Sistema desconocido.")
	match operation:
		"helm":
			if not Catalog.finite_number(args.get("heading")) or not Catalog.finite_number(args.get("throttle")) or float(args.throttle) < 0 or float(args.throttle) > 1 or absf(float(args.heading)) > 36000:
				return reply(false, "Rumbo o impulso fuera de rango.")
			if not ship.docked.is_empty(): return reply(false, "Desatraca antes de maniobrar.")
			ship.heading = fposmod(float(args.heading), 360.0)
			ship.throttle = float(args.throttle)
			ship.autopilot = ""
			message = "Rumbo %03d° · impulso %d%%" % [ship.heading, ship.throttle * 100]
		"autopilot":
			if not ship.docked.is_empty(): return reply(false, "Desatraca primero.")
			if c.hull <= 0: return reply(false, "Ese contacto ya no está activo.")
			ship.autopilot = c.id
			ship.throttle = 1.0
			message = "Ruta trazada hacia el contacto. Frenado automático a 115 m."
		"dock":
			if c.kind != "station" or distance_to(c) > 190 or absf(ship.speed) > 35:
				return reply(false, "Atraca a menos de 190 m y por debajo de 35 m/s.")
			ship.docked = c.id
			ship.throttle = 0.0
			ship.speed = 0.0
			ship.autopilot = ""
			fact("dock", c.id)
			message = "Atraque confirmado. Servicios de reparación y suministro activos."
		"undock":
			if ship.docked.is_empty(): return reply(false, "La nave ya está en vuelo.")
			ship.docked = ""
			message = "Amarras liberadas."
		"boost":
			if not ship.docked.is_empty() or ship.energy < 25 or ship.boost_until > state.time:
				return reply(false, "Impulso no disponible: necesita 25 de energía y estar en vuelo.")
			ship.energy -= 25
			ship.boost_until = state.time + 3.0
			message = "Sobrealimentación de motores durante 3 segundos."
		"power":
			if not Catalog.finite_number(args.get("value")) or float(args.value) != floorf(float(args.value)) or int(args.value) < 0 or int(args.value) > 4:
				return reply(false, "Potencia entre 0 y 4 unidades enteras.")
			var total = int(args.value)
			for other in Catalog.SYSTEMS:
				if other != system: total += int(ship.systems[other].power)
			if total > 8: return reply(false, "El reactor dispone de 8 unidades. Reduce otro sistema primero.")
			ship.systems[system].power = int(args.value)
			message = "%s: %d unidades de potencia." % [system.capitalize(), args.value]
		"coolant":
			ship.coolant = system
			message = "Refrigeración dirigida a " + system + "."
		"shields":
			if not args.get("enabled") is bool: return reply(false, "Estado de escudos no válido.")
			ship.shields_enabled = args.enabled
			message = "Escudos activados." if args.enabled else "Escudos bajados."
		"scan":
			if distance_to(c) > 900 or ship.systems.sensores.power < 1: return reply(false, "Escaneo: alcance 900 m y Sensores con potencia.")
			if c.jammed and not c.hailed: return reply(false, "Interferencia: Comunicaciones debe abrir un canal.")
			if not state.scan.target.is_empty(): return reply(false, "Ya hay un escaneo en curso.")
			state.scan = {"target": c.id, "remaining": 2.5 if c.probed else 5.0}
			message = "Escaneando contacto… Mantén el alcance."
		"hail":
			if distance_to(c) > 900: return reply(false, "Fuera del alcance de comunicaciones: 900 m.")
			c.hailed = true
			fact("hail", c.id)
			message = "Canal abierto. Interferencia compensada para este contacto."
		"negotiate":
			if distance_to(c) > 900 or not c.identified or not c.hailed or ship.shields_enabled:
				return reply(false, "Negociación: contacto identificado, canal abierto, escudos bajos y alcance 900 m.")
			c.negotiated = true
			c.pacified = true
			message = "Acuerdo de paso aceptado. Mando puede decidir."
		"probe":
			if ship.probes < 1 or distance_to(c) > 2500 or c.probed: return reply(false, "Sonda no disponible: alcance 2500 m, una por contacto.")
			ship.probes -= 1
			c.probed = true
			fact("probe", c.id)
			message = "Sonda desplegada. El análisis de este contacto será más rápido."
		"salvage", "rescue":
			if not c.identified or distance_to(c) > 300 or c.hull <= 0: return reply(false, "Identifica el contacto y acércate a menos de 300 m.")
			if operation == "rescue":
				if c.kind != "derelict" or c.rescued: return reply(false, "No hay un rescate pendiente.")
				c.rescued = true
				message = "%d supervivientes a bordo." % int(c.survivors)
			else:
				if c.kind not in ["derelict", "anomaly"] or c.salvaged: return reply(false, "No quedan materiales recuperables.")
				c.salvaged = true
				ship.parts = mini(40, int(ship.parts) + 5)
				message = "Cinco repuestos recuperados."
			fact(operation, c.id)
		"repair_target":
			if c.kind != "station" or distance_to(c) > 300 or ship.parts < 5: return reply(false, "Reparación exterior: estación a menos de 300 m y 5 repuestos.")
			if state.facts.has("repair_target:" + c.id): return reply(false, "Esta reparación ya está completada.")
			ship.parts -= 5
			c.hull = 100.0
			fact("repair_target", c.id)
			message = "Suministro de la estación restablecido."
		"repair":
			if ship.parts < 2 or not state.repair.system.is_empty(): return reply(false, "Drones ocupados o menos de 2 repuestos.")
			if ship.systems[system].health >= 100: return reply(false, "El sistema no necesita reparación.")
			ship.parts -= 2
			state.repair = {"system": system, "remaining": 5.0}
			message = "Drones reparando " + system + "."
		"fire", "missile":
			if not c.identified or c.kind != "hostile" or c.pacified or c.hull <= 0: return reply(false, "Solo se puede disparar a un hostil identificado y activo.")
			var reach = 900 if operation == "missile" else 600
			if distance_to(c) > reach or ship.systems.armas.power < 1: return reply(false, "Blanco fuera de alcance o Armas sin potencia.")
			if ship.weapon_ready > state.time: return reply(false, "Armas recargando.")
			if operation == "missile" and ship.torpedoes < 1: return reply(false, "Sin torpedos.")
			if operation == "fire" and ship.energy < 12: return reply(false, "El pulso necesita 12 de energía.")
			if operation == "missile": ship.torpedoes -= 1
			else: ship.energy -= 12
			var efficiency = 0.7 + 0.15 * ship.systems.armas.power
			c.hull = maxf(0, c.hull - (34.0 if operation == "missile" else 18.0) * efficiency)
			ship.weapon_ready = state.time + (3.0 if operation == "missile" else 1.0)
			ship.systems.armas.heat = minf(120, ship.systems.armas.heat + 4)
			if c.hull <= 0: fact("defeat", c.id)
			message = "Impacto confirmado. Integridad del blanco: %d%%." % c.hull
		"alert":
			if args.get("level") not in ["verde", "ambar", "roja"]: return reply(false, "Nivel de alerta desconocido.")
			ship.alert = args.level
			message = "Alerta " + args.level + "."
		"mission_choice":
			var envoy = contact("haize")
			if args.get("choice") not in ["compartir", "reservar"] or envoy.is_empty() or not envoy.negotiated: return reply(false, "Primero acuerda el paso con Haize desde Comunicaciones.")
			if state.facts.has("choice:haize"): return reply(false, "La decisión ya está registrada.")
			state.campaign.decisions.haize = args.choice
			fact("choice", "haize")
			message = "Decisión registrada: " + args.choice + "."
		"assist":
			if ship.energy < 15 or ship.assist.get(role, 0.0) > state.time: return reply(false, "Asistencia requiere 15 de energía y no puede acumularse.")
			ship.energy -= 15
			ship.assist[role] = state.time + 8.0
			ship.shield = minf(100.0, ship.shield + 15.0)
			message = "Asistencia: 15 puntos de escudo y refuerzo del reactor durante 8 segundos."
	log_event(Catalog.role_name(role), message)
	advance_objectives()
	return reply(true, message)

func fact(kind: String, target: String) -> void:
	state.facts[kind + ":" + target] = true

func tick(delta: float) -> void:
	if state.is_empty() or state.status != "active" or delta <= 0 or not is_finite(delta): return
	delta = minf(delta, 0.1)
	state.time += delta
	var ship: Dictionary = state.ship
	for key in Catalog.SYSTEMS:
		var s: Dictionary = ship.systems[key]
		s.heat = clampf(s.heat + ((s.power - 2) * 1.7 - (8.0 if ship.coolant == key else 0.0)) * delta, 0.0, 120.0)
		if s.heat > 95: s.health = maxf(10, s.health - (s.heat - 95) * 0.08 * delta)
	var assisted = false
	for until in ship.assist.values():
		if float(until) > state.time: assisted = true
	ship.energy = minf(100, ship.energy + (6.0 if assisted else 3.0) * delta)
	if ship.shields_enabled and ship.systems.escudos.power > 0:
		ship.shield = minf(100, ship.shield + ship.systems.escudos.power * 0.8 * delta)
	if not ship.docked.is_empty():
		ship.hull = minf(ship.max_hull, ship.hull + 5 * delta)
		ship.fuel = minf(100, ship.fuel + 8 * delta)
		ship.energy = minf(100, ship.energy + 10 * delta)
		for s in ship.systems.values(): s.health = minf(100, s.health + 3 * delta)
	else:
		var speed_limit = 160.0 * (0.25 + 0.375 * ship.systems.motores.power) * ship.systems.motores.health / 100.0
		if ship.boost_until > state.time: speed_limit *= 2.0
		var desired_speed = speed_limit * ship.throttle
		if not ship.autopilot.is_empty():
			var target = contact(ship.autopilot)
			if target.is_empty() or target.hull <= 0:
				ship.autopilot = ""
				ship.throttle = 0.0
				desired_speed = 0.0
			else:
				var offset = Vector2(target.position[0] - ship.position[0], target.position[1] - ship.position[1])
				ship.heading = fposmod(rad_to_deg(offset.angle()), 360.0)
				desired_speed = minf(speed_limit, maxf(0, (offset.length() - 115) * 1.5))
		if ship.fuel <= 0: desired_speed = minf(desired_speed, 8.0)
		ship.speed = move_toward(ship.speed, desired_speed, 85 * delta)
		var velocity = Vector2.from_angle(deg_to_rad(ship.heading)) * ship.speed * delta
		ship.position = [clampf(ship.position[0] + velocity.x, -14000, 14000), clampf(ship.position[1] + velocity.y, -14000, 14000)]
		ship.fuel = maxf(0, ship.fuel - absf(ship.speed) * delta * 0.00032)
	for c in state.contacts:
		if c.hull <= 0: continue
		var distance = distance_to(c)
		if distance < 250: fact("navigate", c.id)
		if c.kind == "hostile" and not c.pacified and distance < 700 and ship.docked.is_empty():
			if distance > 320:
				var direction = Vector2(ship.position[0] - c.position[0], ship.position[1] - c.position[1]).normalized() * 28.0 * delta
				c.position = [c.position[0] + direction.x, c.position[1] + direction.y]
			if distance < 600 and c.attack_at <= state.time:
				c.attack_at = state.time + 3.0
				var damage = 9.0
				if ship.shields_enabled:
					var absorbed = minf(ship.shield, damage)
					ship.shield -= absorbed
					damage -= absorbed
				ship.hull = maxf(0, ship.hull - damage)
				if damage > 0: ship.systems.motores.health = maxf(10, ship.systems.motores.health - 1.5)
	if not state.scan.target.is_empty():
		var target = contact(state.scan.target)
		if target.is_empty() or distance_to(target) > 900 or ship.systems.sensores.power == 0:
			state.scan = {"target": "", "remaining": 0.0}
			log_event("Sensores", "Escaneo interrumpido: alcance o potencia insuficiente.")
		else:
			state.scan.remaining -= delta * (0.5 + 0.25 * ship.systems.sensores.power)
			if state.scan.remaining <= 0:
				target.identified = true
				fact("scan", target.id)
				state.scan = {"target": "", "remaining": 0.0}
				log_event("Sensores", "Contacto identificado: " + target.name + ".")
	if not state.repair.system.is_empty():
		state.repair.remaining -= delta
		if state.repair.remaining <= 0:
			ship.systems[state.repair.system].health = minf(100, ship.systems[state.repair.system].health + 35)
			state.repair = {"system": "", "remaining": 0.0}
			log_event("Control de daños", "Reparación completada: +35 de integridad de sistema.")
	if ship.hull <= 0:
		state.status = "lost"
		ship.throttle = 0.0
		log_event("Mando", "Nave perdida. Puedes volver a intentar la misión desde Campaña.")
	else: advance_objectives()

func advance_objectives() -> void:
	while state.status == "active" and state.objective < state.mission.objectives.size():
		var goal: Dictionary = state.mission.objectives[int(state.objective)]
		if not state.facts.has(goal.type + ":" + str(goal.get("target", "haize"))): break
		log_event("Objetivo completado", goal.text)
		state.objective += 1
	if state.status == "active" and state.objective >= state.mission.objectives.size():
		state.status = "won"
		state.ship.throttle = 0.0
		state.ship.speed = 0.0
		if state.mission.id not in state.campaign.completed:
			state.campaign.completed.append(state.mission.id)
			state.campaign.credits += int(state.mission.get("reward", 100))
			state.campaign.reputation += 1
			for c in state.contacts:
				if c.rescued: state.campaign.survivors += int(c.survivors)
		log_event("Misión cumplida", "La tripulación ha completado " + state.mission.title + ".")

func purchase_upgrade() -> Dictionary:
	if state.is_empty() or state.status != "won" or state.ship.docked.is_empty(): return reply(false, "Las mejoras se instalan al terminar una misión y atracar.")
	if state.campaign.credits < 120 or state.campaign.upgrades >= 4: return reply(false, "Necesitas 120 créditos. Máximo: 4 refuerzos.")
	state.campaign.credits -= 120
	state.campaign.upgrades += 1
	state.ship.max_hull += 15
	state.ship.hull = minf(state.ship.max_hull, state.ship.hull + 15)
	log_event("Astillero", "Refuerzo instalado: +15 de integridad máxima.")
	return reply(true, "Refuerzo de casco instalado.")

func log_event(source: String, message: String) -> void:
	state.sequence += 1
	state.events.append({"seq": state.sequence, "time": state.time, "source": source, "text": message})
	if state.events.size() > 200: state.events.pop_front()

func snapshot() -> Dictionary:
	var safe: Dictionary = state.duplicate(true)
	if safe.is_empty(): return safe
	safe.mission.erase("contacts")
	for i in safe.contacts.size():
		var c: Dictionary = safe.contacts[i]
		if not c.identified:
			safe.contacts[i] = {"id": c.id, "name": "Eco %02d" % (i + 1), "kind": "unknown", "position": c.position, "identified": false, "hull": 100.0, "hailed": c.hailed, "probed": c.probed, "jammed": c.jammed}
	return safe
