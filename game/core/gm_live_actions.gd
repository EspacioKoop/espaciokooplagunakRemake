class_name GMLiveActions
extends RefCounted

const KINDS = ["station", "friendly", "hostile", "derelict", "anomaly", "asteroid", "nebula", "planet", "black_hole", "wormhole"]
const EVENTS = ["alert", "message", "damage", "repair", "reinforcements"]

static func _reply(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}

static func _finite_number(value: Variant) -> bool:
	return value is int or value is float and is_finite(float(value))

static func _find_contact(state: Dictionary, id: String) -> Dictionary:
	for contact in state.get("contacts", []):
		if str(contact.get("id", "")) == id:
			return contact
	return {}

static func _valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > 40:
		return false
	for ch in value:
		if not (ch.is_valid_identifier() or ch == "-"):
			return false
	return true

static func spawn_contact(sim: Simulation, args: Dictionary) -> Dictionary:
	if sim.state.is_empty() or sim.state.get("status", "") != "active":
		return _reply(false, "La misión no está activa.")
	var id = str(args.get("id", "")).strip_edges()
	var name = str(args.get("name", "")).strip_edges()
	var kind = str(args.get("kind", "")).strip_edges()
	var x = args.get("x", null)
	var y = args.get("y", null)
	if not _valid_id(id):
		return _reply(false, "Identificador GM no válido.")
	if not _find_contact(sim.state, id).is_empty():
		return _reply(false, "Ya existe un contacto con ese identificador.")
	if name.is_empty() or name.length() > 80:
		return _reply(false, "Nombre de contacto no válido.")
	if kind not in KINDS:
		return _reply(false, "Tipo de contacto no admitido.")
	if not _finite_number(x) or not _finite_number(y) or absf(float(x)) > 100000.0 or absf(float(y)) > 100000.0:
		return _reply(false, "Posición fuera de rango.")
	var contact = {
		"id": id,
		"name": name,
		"kind": kind,
		"position": [float(x), float(y)],
		"known": false,
		"identified": bool(args.get("identified", false)),
		"jammed": false,
		"hull": clampf(float(args.get("hull", 100.0)), 1.0, 1000.0),
		"hailed": false,
		"negotiated": false,
		"rescued": false,
		"salvaged": false,
		"probed": false,
		"pacified": false,
		"attack_at": 0.0,
		"survivors": clampi(int(args.get("survivors", 0)), 0, 500),
		"frequency": clampi(int(args.get("frequency", posmod(id.hash(), 21))), 0, 20)
	}
	sim.state.contacts.append(contact)
	sim.log_event("Dirección", "Contacto creado: %s [%s]." % [name, kind])
	return _reply(true, "Contacto creado.")

static func modify_contact(sim: Simulation, id: String, changes: Dictionary) -> Dictionary:
	if sim.state.is_empty() or sim.state.get("status", "") != "active":
		return _reply(false, "La misión no está activa.")
	var contact = _find_contact(sim.state, id)
	if contact.is_empty():
		return _reply(false, "Contacto desconocido.")
	var allowed = ["name", "kind", "x", "y", "hull", "identified", "jammed", "pacified", "frequency", "survivors"]
	for key in changes:
		if key not in allowed:
			return _reply(false, "Campo GM no permitido: " + str(key))
	if changes.has("name"):
		var name = str(changes.name).strip_edges()
		if name.is_empty() or name.length() > 80: return _reply(false, "Nombre no válido.")
		contact.name = name
	if changes.has("kind"):
		var kind = str(changes.kind)
		if kind not in KINDS: return _reply(false, "Tipo de contacto no admitido.")
		contact.kind = kind
	if changes.has("x") or changes.has("y"):
		var x = changes.get("x", contact.position[0])
		var y = changes.get("y", contact.position[1])
		if not _finite_number(x) or not _finite_number(y) or absf(float(x)) > 100000.0 or absf(float(y)) > 100000.0: return _reply(false, "Posición fuera de rango.")
		contact.position = [float(x), float(y)]
	if changes.has("hull"):
		if not _finite_number(changes.hull): return _reply(false, "Integridad no válida.")
		contact.hull = clampf(float(changes.hull), 0.0, 1000.0)
	if changes.has("identified"): contact.identified = bool(changes.identified)
	if changes.has("jammed"): contact.jammed = bool(changes.jammed)
	if changes.has("pacified"): contact.pacified = bool(changes.pacified)
	if changes.has("frequency"): contact.frequency = clampi(int(changes.frequency), 0, 20)
	if changes.has("survivors"): contact.survivors = clampi(int(changes.survivors), 0, 500)
	sim.log_event("Dirección", "Contacto modificado: " + str(contact.name) + ".")
	return _reply(true, "Contacto modificado.")

static func remove_contact(sim: Simulation, id: String) -> Dictionary:
	if sim.state.is_empty() or sim.state.get("status", "") != "active":
		return _reply(false, "La misión no está activa.")
	for i in sim.state.get("contacts", []).size():
		var contact = sim.state.contacts[i]
		if str(contact.get("id", "")) == id:
			var name = str(contact.get("name", id))
			if sim.state.ship.get("autopilot", "") == id: sim.state.ship.autopilot = ""
			if sim.state.ship.get("docked", "") == id: sim.state.ship.docked = ""
			if sim.state.scan.get("target", "") == id: sim.state.scan = {"target": "", "remaining": 0.0}
			sim.state.contacts.remove_at(i)
			sim.log_event("Dirección", "Contacto retirado: " + name + ".")
			return _reply(true, "Contacto retirado.")
	return _reply(false, "Contacto desconocido.")

static func trigger_event(sim: Simulation, event: String, args: Dictionary = {}) -> Dictionary:
	if sim.state.is_empty() or sim.state.get("status", "") != "active":
		return _reply(false, "La misión no está activa.")
	if event not in EVENTS:
		return _reply(false, "Evento GM desconocido.")
	match event:
		"alert":
			var level = str(args.get("level", ""))
			if level not in ["verde", "amarilla", "roja"]: return _reply(false, "Nivel de alerta no válido.")
			sim.state.ship.alert = level
			sim.log_event("Dirección", "Alerta de la nave: " + level + ".")
			return _reply(true, "Alerta actualizada.")
		"message":
			var text = str(args.get("text", "")).strip_edges()
			if text.is_empty() or text.length() > 240: return _reply(false, "Mensaje GM no válido.")
			sim.log_event("Dirección", text)
			return _reply(true, "Mensaje publicado.")
		"damage":
			var amount = args.get("amount", null)
			if not _finite_number(amount) or float(amount) <= 0 or float(amount) > 1000: return _reply(false, "Daño fuera de rango.")
			sim.state.ship.hull = maxf(0.0, float(sim.state.ship.hull) - float(amount))
			sim.log_event("Dirección", "Daño de escena: -%d casco." % int(amount))
			return _reply(true, "Daño aplicado.")
		"repair":
			var amount = args.get("amount", null)
			if not _finite_number(amount) or float(amount) <= 0 or float(amount) > 1000: return _reply(false, "Reparación fuera de rango.")
			sim.state.ship.hull = minf(float(sim.state.ship.max_hull), float(sim.state.ship.hull) + float(amount))
			sim.log_event("Dirección", "Reparación de escena: +%d casco." % int(amount))
			return _reply(true, "Reparación aplicada.")
		"reinforcements":
			var count = clampi(int(args.get("count", 1)), 1, 12)
			var center = Vector2(float(sim.state.ship.position[0]), float(sim.state.ship.position[1]))
			for i in count:
				var id = "gm-hostile-%d-%d" % [int(sim.state.sequence), i]
				var angle = TAU * float(i) / float(count)
				var pos = center + Vector2(cos(angle), sin(angle)) * 900.0
				spawn_contact(sim, {"id": id, "name": "Refuerzo %02d" % (i + 1), "kind": "hostile", "x": pos.x, "y": pos.y, "identified": true})
			sim.log_event("Dirección", "%d refuerzos hostiles entran en escena." % count)
			return _reply(true, "Refuerzos desplegados.")
	return _reply(false, "Evento no ejecutado.")
