class_name SessionReport
extends RefCounted
## Read-only projection. Never serialize Session.sim.state or an entire save.
## No network, credentials, profiles, inventory, contacts or authored objectives.

const FORMAT = "lagunak-session-report"
const VERSION = 1
const MAX_EVENTS = 200
const MAX_CHRONICLE = 300
const MAX_ITEMS = 256
const MAX_BYTES = 2097152
const FACTIONS = ["itsasargi", "burdin", "haize", "itzal"]

static func capture(view: Dictionary, expedition: Dictionary, generated_at: String = "") -> Dictionary:
	var mission = view.get("mission")
	if not mission is Dictionary or _text(mission.get("id"), 80).is_empty() or _text(mission.get("title"), 160).is_empty():
		return _error("No hay una misión disponible para exportar.")
	var campaign = view.get("campaign", {})
	if not campaign is Dictionary:
		return _error("El resumen de campaña no es válido.")
	var omitted = {"events": 0, "chronicle": 0, "completed": 0, "decisions": 0}
	var events = _records(view.get("events", []), MAX_EVENTS, false, omitted)
	var chronicle = _records(expedition.get("chronicle", []), MAX_CHRONICLE, true, omitted)
	var completed: Array = []
	var raw_completed = campaign.get("completed", [])
	if raw_completed is Array:
		for i in mini(raw_completed.size(), MAX_ITEMS):
			var identifier = _text(raw_completed[i], 80)
			if identifier.is_empty():
				omitted.completed += 1
			else:
				completed.append(identifier)
		omitted.completed += maxi(0, raw_completed.size() - MAX_ITEMS)
	else:
		omitted.completed += 1
	var decisions: Array = []
	var raw_decisions = campaign.get("decisions", {})
	if raw_decisions is Dictionary:
		var count = 0
		for key in raw_decisions:
			count += 1
			if count > MAX_ITEMS:
				omitted.decisions += 1
				continue
			var identifier = _text(key, 80)
			var choice = _text(raw_decisions[key], 160)
			if identifier.is_empty() or choice.is_empty():
				omitted.decisions += 1
			else:
				decisions.append({"mission": identifier, "choice": choice})
		decisions.sort_custom(func(a, b): return a.mission < b.mission)
	else:
		omitted.decisions += 1
	var factions: Array = []
	var raw_factions = expedition.get("factions", {})
	if raw_factions is Dictionary:
		for identifier in FACTIONS:
			var entry = raw_factions.get(identifier)
			if entry is Dictionary:
				factions.append({"id": identifier, "reputation": _integer(entry.get("reputation"), -100, 100)})
	var stamp = generated_at if not generated_at.is_empty() else Time.get_datetime_string_from_system(true, true) + "Z"
	var document = {
		"format": FORMAT, "version": VERSION, "generated_at_utc": _text(stamp, 40),
		"scope": {
			"history_complete": false,
			"description": "Misión actual y crónica retenida; no es un guardado ni un replay.",
			"events_clock": "mission_seconds", "chronicle_clock": "unix_seconds",
			"events_limit": MAX_EVENTS, "chronicle_limit": MAX_CHRONICLE,
			"omitted_records": omitted
		},
		"mission": {
			"id": _text(mission.get("id"), 80), "title": _text(mission.get("title"), 160),
			"sector": _text(mission.get("sector", mission.get("id")), 80),
			"status": _text(view.get("status"), 32),
			"elapsed_seconds": _number(view.get("time"), 0.0, 1000000000000.0),
			"objectives_completed": _integer(view.get("objective"), 0, 1000000)
		},
		"campaign": {
			"completed": completed, "decisions": decisions,
			"credits": _integer(campaign.get("credits"), 0, 1000000000000),
			"reputation": _integer(campaign.get("reputation"), -1000000, 1000000),
			"survivors": _integer(campaign.get("survivors"), 0, 1000000000),
			"upgrades": _integer(campaign.get("upgrades"), 0, 1000000)
		},
		"factions": factions, "events": events, "chronicle": chronicle
	}
	var json_text = JSON.stringify(document, "\t", true) + "\n"
	var markdown = _markdown(document)
	if json_text.to_utf8_buffer().size() > MAX_BYTES or markdown.to_utf8_buffer().size() > MAX_BYTES:
		return _error("El informe supera el límite de 2 MiB.")
	return {"ok": true, "document": document, "json": json_text, "markdown": markdown, "message": "Vista previa local preparada."}

static func _records(value: Variant, limit: int, historical: bool, omitted: Dictionary) -> Array:
	var result: Array = []
	var key = "chronicle" if historical else "events"
	if not value is Array:
		omitted[key] += 1
		return result
	omitted[key] += maxi(0, value.size() - limit)
	for i in range(maxi(0, value.size() - limit), value.size()):
		var entry = value[i]
		if not entry is Dictionary:
			omitted[key] += 1
			continue
		var text = _text(entry.get("text"), 2048)
		var timestamp = _number(entry.get("time"), 0.0, 1000000000000.0)
		if text.is_empty() or timestamp == null:
			omitted[key] += 1
			continue
		var projected = {"time": timestamp, "source": _text(entry.get("source"), 80), "text": text}
		if historical:
			projected.sector = _text(entry.get("sector"), 80)
		else:
			var sequence = _integer(entry.get("seq"), 1, 1000000000000)
			if sequence == null:
				omitted[key] += 1
				continue
			projected.seq = sequence
		result.append(projected)
	return result

static func _text(value: Variant, maximum: int) -> String:
	if not value is String:
		return ""
	var result = ""
	for character in value.left(maximum):
		var code = character.unicode_at(0)
		if code in [9, 10, 13]:
			result += " "
		elif code >= 32 and code != 127 and not (code >= 128 and code <= 159) and not (code >= 8234 and code <= 8238) and not (code >= 8294 and code <= 8297):
			result += character
	return result.strip_edges()

static func _number(value: Variant, minimum: float, maximum: float) -> Variant:
	if not (value is int or value is float) or not is_finite(float(value)):
		return null
	if float(value) < minimum or float(value) > maximum:
		return null
	return float(value)

static func _integer(value: Variant, minimum: int, maximum: int) -> Variant:
	var number = _number(value, float(minimum), float(maximum))
	if number == null or float(number) != floorf(float(number)):
		return null
	return int(number)

static func _md(value: Variant) -> String:
	var text = str(value) if value != null else "No disponible"
	text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
	for character in ["\\", "`", "*", "_", "[", "]", "#", "!", "|", "~"]:
		text = text.replace(character, "\\" + character)
	return text

static func _markdown(doc: Dictionary) -> String:
	var lines: Array[String] = [
		"# Crónica de sesión · Espaciokoop Lagunak", "",
		"Generado (UTC): " + _md(doc.generated_at_utc), "",
		"> Misión actual y crónica retenida. No es un historial completo, un guardado ni un replay.",
		"> Revisa los nombres y textos de juego antes de compartir. Los números no disponibles no se inventan.", "",
		"## Misión", "",
		"**" + _md(doc.mission.title) + "** · " + _md(doc.mission.id), "",
		"Sector: " + _md(doc.mission.sector),
		"Estado: " + _md(doc.mission.status),
		"Tiempo de misión (s): " + _md(doc.mission.elapsed_seconds),
		"Objetivos completados: " + _md(doc.mission.objectives_completed), "",
		"## Balance de campaña", "",
		"Créditos: " + _md(doc.campaign.credits),
		"Reputación: " + _md(doc.campaign.reputation),
		"Supervivientes acumulados: " + _md(doc.campaign.survivors),
		"Refuerzos de casco: " + _md(doc.campaign.upgrades), "",
		"### Hitos: misiones completadas", ""
	]
	for identifier in doc.campaign.completed:
		lines.append("- " + _md(identifier))
	if doc.campaign.completed.is_empty(): lines.append("Sin misiones completadas registradas.")
	lines.append_array(["", "### Decisiones", ""])
	for entry in doc.campaign.decisions:
		lines.append("- " + _md(entry.mission) + ": " + _md(entry.choice))
	if doc.campaign.decisions.is_empty(): lines.append("Sin decisiones registradas.")
	lines.append_array(["", "### Reputación por facción", ""])
	for entry in doc.factions:
		lines.append("- " + _md(entry.id) + ": " + _md(entry.reputation))
	if doc.factions.is_empty(): lines.append("Sin datos de facciones disponibles.")
	lines.append_array(["", "## Bitácora de la misión actual", "", "El tiempo de esta sección son segundos de simulación desde el inicio de esta misión.", ""])
	for entry in doc.events:
		lines.append("- #%d · %.2f s · %s: %s" % [entry.seq, entry.time, _md(entry.source), _md(entry.text)])
	if doc.events.is_empty(): lines.append("Sin eventos retenidos.")
	lines.append_array(["", "## Crónica persistente retenida", "", "El tiempo de esta sección son segundos Unix (UTC). Se conserva el orden registrado; no se mezcla con el reloj de misión.", ""])
	for entry in doc.chronicle:
		lines.append("- %.3f · %s · %s: %s" % [entry.time, _md(entry.sector), _md(entry.source), _md(entry.text)])
	if doc.chronicle.is_empty(): lines.append("Sin registros de crónica retenidos.")
	lines.append_array(["", "## Alcance y límites", "",
		"Hasta %d eventos y %d registros de crónica disponibles en esta captura. Los buffers del juego pueden haber descartado registros anteriores." % [MAX_EVENTS, MAX_CHRONICLE],
		"Los hitos son las misiones completadas, no las fichas privadas de personajes. No se incluyen contactos, objetivos futuros, inventarios, perfiles, cartas, dados ni credenciales.",
		"Campos de texto limitados (80–2048 caracteres); controles y saltos de línea se normalizan. Campos numéricos inválidos: null en JSON / No disponible en Markdown.",
		"Registros omitidos por límite o estructura inválida: eventos=%d, crónica=%d, hitos=%d, decisiones=%d." % [doc.scope.omitted_records.events, doc.scope.omitted_records.chronicle, doc.scope.omitted_records.completed, doc.scope.omitted_records.decisions], ""])
	return "\n".join(lines)

static func write_new(path: String, text: String, kind: String) -> Dictionary:
	if kind not in ["md", "json"] or path.get_extension().to_lower() != kind:
		return _error("Elige un archivo .md o .json del formato seleccionado.")
	var normalized = path.replace("\\", "/")
	if normalized.begins_with("res://") or (not normalized.begins_with("user://") and not normalized.is_absolute_path()) or ".." in normalized.split("/") or ("://" in normalized and not normalized.begins_with("user://")):
		return _error("El destino debe ser una ruta local explícita, fuera de los recursos del juego.")
	if text.is_empty() or text.to_utf8_buffer().size() > MAX_BYTES:
		return _error("El texto está vacío o supera el límite de 2 MiB.")
	var absolute = ProjectSettings.globalize_path(normalized)
	if not DirAccess.dir_exists_absolute(absolute.get_base_dir()):
		return _error("La carpeta de destino no existe.")
	if FileAccess.file_exists(absolute) or DirAccess.dir_exists_absolute(absolute):
		return _error("Ya existe ese destino. Elige otro nombre: no se sobrescriben archivos.")
	var temporary = absolute + ".tmp-" + Crypto.new().generate_random_bytes(12).hex_encode()
	if FileAccess.file_exists(temporary):
		return _error("No se pudo reservar un archivo temporal nuevo.")
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _error("No se pudo abrir el destino local: " + error_string(FileAccess.get_open_error()))
	file.store_string(text)
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return _error("No se pudo completar la escritura: " + error_string(error))
	if FileAccess.file_exists(absolute) or DirAccess.dir_exists_absolute(absolute):
		DirAccess.remove_absolute(temporary)
		return _error("El destino apareció durante la exportación. Elige otro nombre.")
	error = DirAccess.rename_absolute(temporary, absolute)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return _error("No se pudo finalizar la exportación: " + error_string(error))
	return {"ok": true, "path": absolute, "message": "Informe guardado localmente en " + absolute}

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
