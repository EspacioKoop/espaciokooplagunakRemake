class_name GMLiveActions
extends RefCounted
## Host-local authoring, never a network command or a replacement mission source.
const KINDS = ["station", "friendly", "hostile", "derelict", "anomaly", "beacon", "asteroid", "nebula", "planet", "blackhole", "wormhole"]
const EVENTS = ["alert", "message", "damage", "repair", "reinforcements"]
const SPAWN_FIELDS = ["id", "name", "kind", "x", "y", "identified", "jammed", "pacified", "hull", "survivors", "frequency", "visual_model"]
const EDIT_FIELDS = ["name", "kind", "x", "y", "hull", "identified", "jammed", "pacified", "frequency", "survivors", "visual_model"]

static func _reply(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}

static func can_direct(session: Node) -> bool:
	return is_instance_valid(session) and session.get("mode") in ["offline", "host"] and session.get("sim") is Simulation and not session.sim.state.is_empty() and session.sim.state.get("status") == "active"

static func dispatch(session: Node, operation: String, args: Dictionary, expected_run: String = "") -> Dictionary:
	if not can_direct(session): return _reply(false, "Sólo el anfitrión local puede dirigir una misión activa.")
	if not expected_run.is_empty() and session.sim.state.get("run_id", "") != expected_run:
		return _reply(false, "La misión ha cambiado. Vuelve a abrir la consola.")
	var result: Dictionary
	match operation:
		"spawn": result = spawn_contact(session.sim, args)
		"modify":
			if args.size() != 2 or not args.get("id") is String or not args.get("changes") is Dictionary: return _reply(false, "Modificación inválida.")
			result = modify_contact(session.sim, args.id, args.changes)
		"remove":
			if args.size() != 1 or not args.get("id") is String: return _reply(false, "Retirada inválida.")
			result = remove_contact(session.sim, args.id)
		"add_interior_trigger":
			var trigger_args = args.duplicate(true)
			trigger_args["one_shot"] = bool(args.get("one_shot", true))
			result = InteriorTriggers.register_trigger(session.sim, trigger_args)
		"modify_interior_trigger":
			if args.size() != 2 or not args.get("id") is String or not args.get("changes") is Dictionary: return _reply(false, "Modificación de trigger inválida.")
			result = InteriorTriggers.update_trigger(session.sim, args.id, args.changes)
		"remove_interior_trigger":
			if args.size() != 1 or not args.get("id") is String: return _reply(false, "Retirada de trigger inválida.")
			result = InteriorTriggers.remove_trigger(session.sim, str(args.get("id", "")))
		_: result = trigger_event(session.sim, operation, args)
	if result.ok:
		if operation in ["add_interior_trigger", "modify_interior_trigger", "remove_interior_trigger"]:
			_audit(session.sim, operation, "", "Configuración de trigger de interior actualizada.")
		session._refresh_view()
	return result

static func _active(sim: Simulation) -> String:
	if sim == null or sim.state.is_empty() or sim.state.get("status") != "active": return "La misión no está activa."
	return GMLiveState.validate(sim.state)

static func _text(value: Variant, maximum: int) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.length() > maximum: return false
	for ch in value:
		if ch.unicode_at(0) < 32 or ch.unicode_at(0) == 127: return false
	return true

static func _fields(args: Dictionary, spawning: bool) -> String:
	var allowed = SPAWN_FIELDS if spawning else EDIT_FIELDS
	if args.is_empty(): return "No hay cambios que aplicar."
	for key in args:
		if not (key is String or key is StringName) or str(key) not in allowed: return "Campo de dirección no permitido."
	if spawning and not args.has_all(["id", "name", "kind", "x", "y"]): return "Contacto incompleto."
	if args.has("id") and not GMLiveState.identifier(args.id): return "Identificador no válido."
	if args.has("name") and not _text(args.name, 80): return "Nombre no válido."
	if args.has("kind") and (not args.kind is String or args.kind not in KINDS): return "Tipo de contacto no admitido."
	for field in ["x", "y"]:
		if args.has(field) and not GMLiveState.number(args[field], -14000, 14000): return "Posición fuera de rango."
	if args.has("hull") and not GMLiveState.number(args.hull, 1 if spawning else 0, 1000): return "Integridad fuera de rango."
	for field in ["identified", "jammed", "pacified"]:
		if args.has(field) and not args[field] is bool: return "Indicador de contacto no válido."
	if args.has("frequency") and not GMLiveState.number(args.frequency, 0, 20, true): return "Frecuencia no válida."
	if args.has("survivors") and not GMLiveState.number(args.survivors, 0, 500, true): return "Supervivientes no válidos."
	if args.has("visual_model") and not args.visual_model is String: return "Modelo visual no válido."
	return ""

static func _audit(sim: Simulation, operation: String, target: String, public_message: String) -> void:
	GMLiveState.ensure(sim.state)
	# Identifiers of hidden contacts must never enter the public event stream.
	sim.log_event("Dirección", public_message)
	sim.state.gm_live.audit.append({"seq": sim.state.sequence, "time": sim.state.time, "operation": operation, "target": target})
	while sim.state.gm_live.audit.size() > GMLiveState.MAX_AUDIT: sim.state.gm_live.audit.pop_front()

static func spawn_contact(sim: Simulation, args: Dictionary) -> Dictionary:
	var error = _active(sim)
	if error.is_empty(): error = _fields(args, true)
	if not error.is_empty(): return _reply(false, error)
	if args.id in GMLiveState.all_ids(sim.state): return _reply(false, "Ese identificador ya se ha utilizado en esta misión.")
	if sim.state.contacts.size() >= GMLiveState.MAX_CONTACTS or sim.state.get("gm_live", {}).get("added", []).size() >= GMLiveState.MAX_ADDED:
		return _reply(false, "Se ha alcanzado el límite de contactos de escena.")
	var contact = {"id": args.id, "name": args.name.strip_edges(), "kind": args.kind,
		"position": [float(args.x), float(args.y)], "known": false,
		"identified": args.get("identified", false), "jammed": args.get("jammed", false),
		"hull": float(args.get("hull", 100.0)), "hailed": false, "negotiated": false,
		"rescued": false, "salvaged": false, "probed": false, "pacified": args.get("pacified", false),
		"attack_at": 0.0, "survivors": int(args.get("survivors", 0)),
		"frequency": int(args.get("frequency", posmod(args.id.hash(), 21)))}
	if args.has("visual_model"):
		if not RuntimeAssetLibrary.compatible(args.visual_model, contact.kind): return _reply(false, "Modelo incompatible con el tipo de contacto.")
		if not args.visual_model.is_empty(): contact.visual_model = args.visual_model
	error = SpacePhysics.validate_contact(contact)
	if not error.is_empty(): return _reply(false, error)
	GMLiveState.ensure(sim.state)
	sim.state.gm_live.added.append(args.id)
	sim.state.contacts.append(contact)
	_audit(sim, "spawn", args.id, "Contacto de escena creado.")
	return _reply(true, "Contacto creado: " + contact.name + ".")

static func modify_contact(sim: Simulation, id: String, changes: Dictionary) -> Dictionary:
	var error = _active(sim)
	if error.is_empty(): error = _fields(changes, false)
	if not error.is_empty(): return _reply(false, error)
	var contact = sim.contact(id)
	if contact.is_empty(): return _reply(false, "Contacto desconocido.")
	var candidate: Dictionary = contact.duplicate(true)
	for raw_key in changes:
		var key = str(raw_key)
		match key:
			"x": candidate.position[0] = float(changes.x)
			"y": candidate.position[1] = float(changes.y)
			"name": candidate.name = changes.name.strip_edges()
			_: candidate[key] = changes[key]
	if GMLiveState.protected_target(sim.state, id) and candidate.kind != contact.kind:
		return _reply(false, "Un objetivo protege el tipo de este contacto.")
	if contact.kind in SpacePickups.KINDS or candidate.kind in SpacePickups.KINDS:
		return _reply(false, "Los recogibles conservan sus reglas de consumo; no se alteran desde esta consola.")
	if candidate.has("visual_model") and not RuntimeAssetLibrary.compatible(candidate.visual_model, candidate.kind):
		return _reply(false, "Modelo incompatible con el tipo de contacto.")
	if GMLiveState.protected_target(sim.state, id) and candidate.hull <= 0 and candidate.kind != "hostile":
		return _reply(false, "No se puede destruir un contacto necesario para un objetivo.")
	error = SpacePhysics.validate_contact(candidate)
	if not error.is_empty(): return _reply(false, error)
	contact.assign(candidate)
	_audit(sim, "modify", id, "Contacto de escena modificado.")
	if candidate.kind == "hostile" and candidate.hull <= 0:
		sim.fact("defeat", id)
		sim.advance_objectives()
	return _reply(true, "Contacto modificado: " + candidate.name + ".")

static func remove_contact(sim: Simulation, id: String) -> Dictionary:
	var error = _active(sim)
	if not error.is_empty(): return _reply(false, error)
	var contact = sim.contact(id)
	if contact.is_empty(): return _reply(false, "Contacto desconocido.")
	if GMLiveState.protected_target(sim.state, id): return _reply(false, "Un objetivo de misión necesita este contacto; no se puede retirar.")
	GMLiveState.ensure(sim.state)
	sim.state.gm_live.removed.append(id)
	if sim.state.ship.get("autopilot", "") == id:
		sim.state.ship.autopilot = ""
		sim.state.ship.throttle = 0.0
	if sim.state.ship.get("docked", "") == id: sim.state.ship.docked = ""
	if sim.state.scan.get("target", "") == id: sim.state.scan = {"target": "", "remaining": 0.0}
	if sim.state.operations.get("docking", "") == id: sim.state.operations.docking = ""
	for field in ["weapon_target", "science_link"]:
		if sim.state.operations.get(field, "") == id: sim.state.operations[field] = ""
	if sim.state.operations.get("comms", {}).get("target", "") == id:
		sim.state.operations.comms = {"target": "", "messages": [], "replies": []}
	for mount in sim.state.ship.get("loadout", {}).get("mounts", []):
		if mount.get("auto_target", "") == id: mount.auto_target = ""
	for other in sim.state.contacts:
		if other.get("ai_objective", "") == id:
			other.ai_objective = ""
			other.ai_order = "hold"
	for tube in sim.state.operations.get("tubes", []):
		if tube.get("target", "") == id: tube.target = ""
	sim.state.contacts.erase(contact)
	_audit(sim, "remove", id, "Contacto de escena retirado.")
	return _reply(true, "Contacto retirado: " + contact.name + ".")

static func trigger_event(sim: Simulation, event: String, args: Dictionary = {}) -> Dictionary:
	var error = _active(sim)
	if not error.is_empty(): return _reply(false, error)
	if event not in EVENTS: return _reply(false, "Evento de dirección desconocido.")
	var field = {"alert": "level", "message": "text", "damage": "amount", "repair": "amount", "reinforcements": "count"}[event]
	if args.size() != 1 or not args.has(field): return _reply(false, "Parámetros de evento inválidos.")
	match event:
		"alert":
			if not args.level is String or args.level not in ["verde", "ambar", "roja"]: return _reply(false, "Nivel de alerta no válido.")
			sim.state.ship.alert = args.level
			_audit(sim, event, "", "Alerta de la nave: " + args.level + ".")
		"message":
			if not _text(args.text, 240): return _reply(false, "Mensaje de dirección no válido.")
			_audit(sim, event, "", args.text.strip_edges())
		"damage", "repair":
			if not GMLiveState.number(args.amount, 0.001, 1000): return _reply(false, "Cantidad fuera de rango.")
			var amount = float(args.amount)
			sim.state.ship.hull = clampf(float(sim.state.ship.hull) + (amount if event == "repair" else -amount), 0.0, float(sim.state.ship.max_hull))
			_audit(sim, event, "", "%s de escena: %.2f casco." % ["Reparación" if event == "repair" else "Daño", amount])
			if sim.state.ship.hull <= 0:
				sim.state.status = "lost"
				sim.state.ship.throttle = 0.0
				sim.state.ship.speed = 0.0
				sim.log_event("Mando", "Nave perdida por un evento de dirección.")
		"reinforcements":
			if not GMLiveState.number(args.count, 1, 12, true): return _reply(false, "Se requieren entre 1 y 12 refuerzos enteros.")
			# Plan and validate the entire batch off-state. No partial deployment.
			var staged = Simulation.new()
			staged.state = sim.state.duplicate(true)
			var count = int(args.count)
			var center = Vector2(float(sim.state.ship.position[0]), float(sim.state.ship.position[1]))
			for i in count:
				var id = "gm-reinforcement-%d-%d" % [int(staged.state.sequence), i]
				var position = center + Vector2.from_angle(TAU * i / count) * 900.0
				var result = spawn_contact(staged, {"id": id, "name": "Refuerzo %02d" % (i + 1), "kind": "hostile", "x": position.x, "y": position.y, "identified": true})
				if not result.ok: return result
			_audit(staged, event, "", "%d refuerzos hostiles entran en escena." % count)
			sim.state = staged.state
	return _reply(true, "Evento de escena aplicado.")
