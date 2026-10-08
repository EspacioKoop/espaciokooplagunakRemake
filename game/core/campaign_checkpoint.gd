class_name CampaignCheckpoint
extends RefCounted
## One portable document for both existing durable stores. Never a network snapshot.

const FORMAT = "lagunak-campaign-checkpoint"
const VERSION = 1
const MAX_BYTES = 4 * 1024 * 1024
const MAX_LABEL = 48

static func failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func valid_label(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > MAX_LABEL or value != value.strip_edges(): return false
	for index in value.length():
		var code = value.unicode_at(index)
		if code < 32 or (code >= 127 and code <= 159) or (code >= 0x200b and code <= 0x200f) or (code >= 0x202a and code <= 0x202e) or (code >= 0x2060 and code <= 0x206f) or code == 0xfeff: return false
	return true

static func _keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size(): return false
	for key in keys:
		if not value.has(key): return false
	return true

static func _number(value: Variant, low: float, high: float, integral: bool = false) -> bool:
	return Catalog.finite_number(value) and value >= low and value <= high and (not integral or floorf(value) == value)

static func _text(value: Variant, maximum: int = 128) -> bool:
	return (value is String or value is StringName) and not value.is_empty() and value.length() <= maximum

static func _position(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0], -14000, 14000) and _number(value[1], -14000, 14000)

static func validate_expedition(value: Variant) -> String:
	if not LocalStorage.validate_json(value) or not _keys(value, ["format", "version", "factions", "profiles", "inventory", "atlas", "bestiary", "chronicle", "director"]): return "Estructura de expedición inválida."
	if value.format != ExpeditionSystems.FORMAT or not _number(value.version, 1, 1, true): return "Versión de expedición incompatible."
	for key in ["factions", "profiles", "inventory", "atlas", "bestiary", "director"]:
		if not value[key] is Dictionary: return "Objeto de expedición inválido: " + key
	if not _keys(value.factions, ExpeditionSystems.FACTIONS.keys()): return "Catálogo de facciones incompleto."
	for faction in value.factions.values():
		if not _keys(faction, ["reputation", "encounters", "trades"]): return "Facción inválida."
		if not _number(faction.reputation, -100, 100, true) or not _number(faction.encounters, 0, 1e12, true) or not _number(faction.trades, 0, 1e12, true): return "Contadores de facción inválidos."
	for actor in value.profiles:
		var profile: Variant = value.profiles[actor]
		if not _text(actor) or not _keys(profile, ["name", "approach", "focus", "skills", "traits", "level", "xp", "condition", "milestones"]): return "Ficha de tripulación inválida."
		if not CharacterDocument.validate(CharacterDocument.document({"name": profile.name, "approach": profile.approach, "skills": profile.skills})).ok: return "Campos de ficha inválidos."
		if not _number(profile.focus, 0, CrewSystem.MAX_FOCUS, true) or not _number(profile.level, 1, CrewSystem.MAX_LEVEL, true) or not _number(profile.xp, 0, 1e12, true) or not _number(profile.condition, 0, 100, true): return "Progresión de ficha inválida."
		if not profile.traits is Array or profile.traits.size() > 3 or not profile.milestones is Array or profile.milestones.size() > 20: return "Rasgos o hitos inválidos."
		var seen = {}
		for trait_id in profile.traits:
			if not trait_id is String or not CrewSystem.TRAITS.has(trait_id) or seen.has(trait_id): return "Rasgo desconocido o repetido."
			seen[trait_id] = true
		for milestone in profile.milestones:
			if not _text(milestone, 8000): return "Hito inválido."
	for actor in value.inventory:
		var stock: Variant = value.inventory[actor]
		if not _text(actor) or not _keys(stock, ExpeditionSystems.COMMODITIES.keys()): return "Inventario inválido."
		for amount in stock.values():
			if not _number(amount, 0, 1e12, true): return "Cantidad de inventario inválida."
	if not _keys(value.atlas, ["sectors", "markers"]) or not value.atlas.sectors is Dictionary or not value.atlas.markers is Array or value.atlas.markers.size() > 128: return "Atlas persistente inválido."
	for sector_id in value.atlas.sectors:
		var sector: Variant = value.atlas.sectors[sector_id]
		if not _text(sector_id) or not _keys(sector, ["visits", "contacts", "first_seen"]) or not sector.contacts is Dictionary: return "Sector archivado inválido."
		if not _number(sector.visits, 0, 1e12, true) or not _number(sector.first_seen, 0, 1e12): return "Contadores de sector inválidos."
		for id in sector.contacts:
			var contact: Variant = sector.contacts[id]
			if not _text(id) or not _keys(contact, ["name", "kind", "position"]) or not _text(contact.name, 8000) or contact.kind not in Catalog.CONTACT_KINDS or not _position(contact.position): return "Contacto archivado inválido."
	var markers = {}
	for marker in value.atlas.markers:
		if not _keys(marker, ["id", "sector", "label", "position", "author"]): return "Marcador inválido."
		for key in ["id", "sector", "label", "author"]:
			if not _text(marker[key]): return "Texto de marcador inválido."
		if not _position(marker.position) or markers.has(marker.id): return "Posición o identidad de marcador inválida."
		markers[marker.id] = true
	for kind in value.bestiary:
		var entry: Variant = value.bestiary[kind]
		if kind not in Catalog.CONTACT_KINDS or not _keys(entry, ["sightings", "names"]) or not _number(entry.sightings, 0, 1e12, true) or not entry.names is Array: return "Bestiario inválido."
		for contact_name in entry.names:
			if not _text(contact_name, 8000): return "Nombre de bestiario inválido."
	if not value.chronicle is Array or value.chronicle.size() > 300: return "Crónica inválida."
	for event in value.chronicle:
		if not _keys(event, ["time", "sector", "source", "text"]) or not _number(event.time, 0, 1e12) or not _text(event.sector) or not _text(event.source, 32) or not _text(event.text, 300): return "Entrada de crónica inválida."
	var director: Dictionary = value.director
	if not _keys(director, ["tempo", "auto_events", "threat", "spawned"]) or not _number(director.tempo, 0.25, 3) or not director.auto_events is bool or not _number(director.threat, 0, 1e12) or not _number(director.spawned, 0, 1e12, true): return "Estado de dirección inválido."
	return ""

static func valid_cursor(value: Variant) -> bool:
	return _keys(value, ["run", "sequence"]) and value.run is String and value.run.length() <= 128 and _number(value.sequence, 0, 9e15, true)

static func validate(value: Variant) -> String:
	if not _keys(value, ["label", "saved_at", "state", "expedition", "event_cursor"]): return "Checkpoint incompleto."
	if not valid_label(value.label) or not _number(value.saved_at, 0, 1e12) or not valid_cursor(value.event_cursor): return "Nombre, fecha o cursor inválidos."
	var error = LocalStorage.validate_state(value.state)
	if not error.is_empty(): return error
	return validate_expedition(value.expedition)

static func encode(value: Dictionary) -> Dictionary:
	var error = validate(value)
	if not error.is_empty(): return failure(error)
	var payload = JSON.stringify(value, "", true, true)
	var text = JSON.stringify({"format": FORMAT, "version": VERSION, "sha256": payload.sha256_text(), "payload": payload})
	if text.to_utf8_buffer().size() > MAX_BYTES: return failure("El checkpoint supera 4 MiB.")
	# Every export must also satisfy the import grammar; no write-only saves.
	var decoded = decode(text)
	if not decoded.ok: return decoded
	return {"ok": true, "text": text}

static func decode(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES: return failure("El checkpoint supera 4 MiB.")
	var grammar = CharacterDocument.StrictJSON.new()
	if not grammar.check(text).is_empty(): return failure("Cabecera JSON no válida o ambigua.")
	var parser = JSON.new()
	if parser.parse(text) != OK: return failure("Cabecera JSON inválida.")
	var envelope: Variant = parser.data
	if not _keys(envelope, ["format", "version", "sha256", "payload"]) or envelope.format != FORMAT or not _number(envelope.version, VERSION, VERSION, true) or not envelope.payload is String or not envelope.sha256 is String: return failure("Se requiere un archivo completo de campaña .lagunak (versión 1).")
	if envelope.payload.sha256_text() != envelope.sha256: return failure("La integridad del checkpoint no coincide.")
	grammar = CharacterDocument.StrictJSON.new()
	if not grammar.check(envelope.payload).is_empty() or parser.parse(envelope.payload) != OK: return failure("Contenido JSON no válido o ambiguo.")
	var checkpoint: Variant = parser.data
	var error = validate(checkpoint)
	if not error.is_empty(): return failure(error)
	return {"ok": true, "checkpoint": checkpoint, "digest": text.sha256_text()}

static func summary(value: Dictionary) -> String:
	var state: Dictionary = value.state
	return "%s\nGuardado: %s UTC\nMisión: %s\nSector: %s\nMisiones completadas: %d\nCréditos: %d · Supervivientes: %d\nFichas: %d · Inventarios: %d\nCrónica: %d entradas · Marcadores: %d\n\nIncluye vuelo, progreso, campañas personalizadas y los datos persistentes de expedición.\nNo incluye claves de red, apariencia local, manos de mesa ni combates o minijuegos transitorios." % [value.label, Time.get_datetime_string_from_unix_time(int(value.saved_at), true), state.mission.title, state.mission.sector, state.campaign.completed.size(), state.campaign.credits, state.campaign.survivors, value.expedition.profiles.size(), value.expedition.inventory.size(), value.expedition.chronicle.size(), value.expedition.atlas.markers.size()]
