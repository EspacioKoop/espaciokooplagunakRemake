class_name LocalStorage
extends RefCounted

const MAX_BYTES = 2 * 1024 * 1024

static func validate_json(value: Variant, depth: int = 0) -> bool:
	if depth > 18: return false
	if value is Dictionary:
		if value.size() > 600: return false
		for k in value:
			if not (k is String or k is StringName) or str(k).length() > 128 or not validate_json(value[k], depth + 1): return false
	elif value is Array:
		if value.size() > 600: return false
		for item in value:
			if not validate_json(item, depth + 1): return false
	elif value is String or value is StringName:
		return str(value).length() <= 8000
	elif value is bool or value == null: return true
	elif not Catalog.finite_number(value): return false
	return true

static func validate_state(value: Variant) -> String:
	if not value is Dictionary or not validate_json(value): return "Estructura de guardado inválida."
	for k in ["version", "mission", "campaign", "time", "status", "objective", "facts", "events", "sequence", "ship", "contacts", "scan", "repair"]:
		if not value.has(k): return "Falta " + k
	if value.version != 1 or value.status not in ["active", "won", "lost"]: return "Versión o estado no compatible."
	if not Catalog.validate_mission(value.mission).is_empty(): return "Misión dañada."
	if value.has("campaign_document"):
		var campaign_error = CampaignDocument.validate(value.campaign_document)
		if not campaign_error.is_empty(): return campaign_error
		var authored = CampaignDocument.playable_missions(value.campaign_document)
		if not authored.any(func(mission): return mission == value.mission): return "La misión no pertenece al documento de campaña guardado."
	for k in ["campaign", "facts", "ship", "scan", "repair"]:
		if not value[k] is Dictionary: return "Objeto inválido: " + k
	if not value.contacts is Array or not value.events is Array or value.events.size() > 200: return "Contactos o bitácora inválidos."
	if not Catalog.finite_number(value.objective) or value.objective < 0 or value.objective > value.mission.objectives.size() or value.objective != floorf(value.objective): return "Objetivo inválido."
	for k in ["time", "sequence"]:
		if not Catalog.finite_number(value[k]) or value[k] < 0: return "Contador inválido."
	if value.has("operations"):
		var error = ShipOperations.validate(value.operations, not value.ship.has("design"))
		if not error.is_empty(): return error
	if value.has("cooperation"):
		if not value.cooperation is Dictionary or not ShipOperations.number(value.cooperation, "next_id", 1, 1e9, true): return "Asistencia guardada inválida."
	var ship: Dictionary = value.ship
	for k in ["position", "heading", "speed", "throttle", "autopilot", "docked", "hull", "max_hull", "shield", "shields_enabled", "energy", "fuel", "torpedoes", "probes", "parts", "alert", "coolant", "boost_until", "weapon_ready", "assist", "systems"]:
		if not ship.has(k): return "Nave incompleta: " + k
	if not ship.position is Array or ship.position.size() != 2: return "Posición inválida."
	for coordinate in ship.position:
		if not Catalog.finite_number(coordinate) or absf(coordinate) > 14000: return "Posición fuera de rango."
	for k in ["heading", "hull", "max_hull", "shield", "energy", "fuel", "torpedoes", "probes", "parts", "boost_until", "weapon_ready"]:
		if not Catalog.finite_number(ship[k]) or ship[k] < 0 or ship[k] > 100000: return "Recurso inválido: " + k
	if not ShipOperations.number(ship, "speed", -100000, 100000) or not ShipOperations.number(ship, "throttle", -1, 1): return "Velocidad o impulso inválidos."
	if ship.max_hull < 1 or ship.hull > ship.max_hull or ship.energy > 100 or ship.fuel > 100 or ship.shield > 100.001: return "Recurso fuera de rango."
	for k in ["autopilot", "docked", "alert", "coolant"]:
		if not ship[k] is String: return "Identificador inválido."
	if not ship.shields_enabled is bool or not ship.assist is Dictionary or not ship.systems is Dictionary: return "Sistema inválido."
	for until in ship.assist.values():
		if not Catalog.finite_number(until): return "Asistencia inválida."
	var systems = Catalog.SYSTEMS if ship.has("design") else ShipModel.LEGACY_SYSTEMS
	for system in systems:
		if not ship.systems.get(system) is Dictionary: return "Falta un sistema."
		for k in ["power", "heat", "health"]:
			if not Catalog.finite_number(ship.systems[system].get(k)): return "Sistema incompleto."
		var s: Dictionary = ship.systems[system]
		if s.power < 0 or s.power > 4 or s.power != floorf(s.power) or s.heat < 0 or s.heat > 120 or s.health < 0 or s.health > 100: return "Sistema fuera de rango."
	var power = 0
	for system in systems: power += int(ship.systems[system].power)
	if power > (ShipModel.POWER_BUDGET if ship.has("design") else 8): return "Presupuesto de potencia excedido."
	if ship.has("design"):
		var error = ShipModel.validate_ship(ship)
		if not error.is_empty(): return error
		if value.has("operations"):
			for ammo in ShipOperations.AMMO:
				var stored = int(value.operations.ammo[ammo])
				for tube in value.operations.tubes:
					if tube.ammo == ammo: stored += 1
				if stored > ship.design.ammo[ammo]: return "Munición superior a la capacidad de diseño."
	for task in [value.scan, value.repair]:
		if not Catalog.finite_number(task.get("remaining")) or task.remaining < 0 or task.remaining > 30: return "Tarea inválida."
	if not value.scan.get("target") is String or not value.repair.get("system") is String: return "Tarea incompleta."
	var ids: Array = []
	for c in value.contacts:
		if not c is Dictionary or not c.get("id") is String or c.id in ids: return "Contacto dañado."
		ids.append(c.id)
		for k in ["name", "kind"]:
			if not c.get(k) is String: return "Contacto incompleto."
		if not c.get("position") is Array or c.position.size() != 2: return "Posición de contacto dañada."
		for coordinate in c.position:
			if not Catalog.finite_number(coordinate) or absf(coordinate) > 14000: return "Contacto fuera de rango."
		for k in ["identified", "jammed", "known", "hailed", "negotiated", "rescued", "salvaged", "probed", "pacified"]:
			if not c.get(k) is bool: return "Indicador de contacto dañado."
		if c.has("frequency") and not ShipOperations.number(c, "frequency", 0, 20, true): return "Frecuencia de contacto dañada."
		for k in ["hull", "attack_at", "survivors"]:
			if not Catalog.finite_number(c.get(k)) or c[k] < 0: return "Recurso de contacto dañado."
		if c.kind not in Catalog.CONTACT_KINDS or not SpacePhysics.validate_contact(c).is_empty(): return "Objeto espacial dañado."
	var pickup_error = SpacePickups.validate_state(value)
	if not pickup_error.is_empty(): return pickup_error
	var scene_error = GMLiveState.validate(value)
	if not scene_error.is_empty(): return scene_error
	for id in [ship.autopilot, ship.docked, value.scan.target]:
		if not id.is_empty() and id not in ids: return "Referencia de contacto inválida."
	if value.repair.system != "" and value.repair.system not in Catalog.SYSTEMS: return "Reparación inválida."
	var campaign: Dictionary = value.campaign
	if not campaign.get("completed") is Array or not campaign.get("decisions") is Dictionary: return "Campaña inválida."
	for id in campaign.completed:
		if not id is String: return "Progreso inválido."
	for k in ["credits", "reputation", "survivors", "upgrades"]:
		if not Catalog.finite_number(campaign.get(k)) or campaign[k] < 0 or campaign[k] > 1000000: return "Campaña incompleta."
	if campaign.upgrades > 4: return "Mejoras fuera de rango."
	for event in value.events:
		if not event is Dictionary or not event.get("text") is String or not event.get("source") is String or not Catalog.finite_number(event.get("seq")) or not Catalog.finite_number(event.get("time")): return "Bitácora dañada."
	return ""

static func save_state(state: Dictionary, path: String = "user://campaign.json") -> String:
	var issue = validate_state(state)
	if not issue.is_empty(): return issue
	var payload = JSON.stringify(state, "", true, true)
	var envelope = JSON.stringify({"format": "lagunak-save", "version": 1, "sha256": payload.sha256_text(), "payload": payload})
	if envelope.to_utf8_buffer().size() > MAX_BYTES: return "Guardado demasiado grande."
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return "No se pudo abrir el archivo temporal."
	file.store_string(envelope)
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK: return "No se pudo escribir el guardado."
	if FileAccess.file_exists(path) and read_state(path).has("state"):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak")) != OK: return "No se pudo conservar la copia anterior."
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) != OK: return "No se pudo finalizar el guardado."
	return ""

static func read_state(path: String = "user://campaign.json") -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": "No existe un guardado legible."}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"error": "Guardado demasiado grande."}
	var parser = JSON.new()
	var parse_error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK: return {"error": "Cabecera de guardado inválida."}
	var envelope = parser.data
	if not envelope is Dictionary or envelope.get("format") != "lagunak-save" or envelope.get("version") != 1 or not envelope.get("payload") is String or not envelope.get("sha256") is String: return {"error": "Cabecera de guardado inválida."}
	if envelope.payload.sha256_text() != envelope.sha256: return {"error": "La integridad del guardado no coincide."}
	if parser.parse(envelope.payload) != OK: return {"error": "Contenido de guardado inválido."}
	var state = parser.data
	var issue = validate_state(state)
	if issue.is_empty():
		ShipModel.initialize(state)
		ShipOperations.initialize(state)
		Cooperation.initialize(state)
		# Transient assistance is deliberately cancelled on restore.
		state.cooperation = {"next_id": state.cooperation.next_id, "tasks": {}, "tokens": {}, "cooldowns": {}}
	return {"state": state} if issue.is_empty() else {"error": issue}
