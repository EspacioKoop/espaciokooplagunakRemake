class_name CampaignDocument
extends RefCounted
## Authored content only. Progress remains owned by Simulation.campaign.

const FORMAT = "lagunak-campaign"
const VERSION = 1
const MAX_BYTES = 512 * 1024
const MAX_MISSIONS = 24

static func valid_id(value: Variant) -> bool:
	if not value is String: return false
	var pattern = RegEx.new()
	pattern.compile("^[a-zA-Z0-9_-]{1,64}$")
	return pattern.search(value) != null

static func validate(value: Variant) -> String:
	# Reserve the extra level added by state.campaign_document on persistence.
	if not value is Dictionary or not LocalStorage.validate_json(value, 1): return "Estructura de campaña inválida."
	if value.get("format") != FORMAT or not Catalog.finite_number(value.get("version")) or value.version != VERSION: return "Formato o versión de campaña no compatible."
	if not valid_id(value.get("id")): return "Identificador de campaña inválido."
	for field in ["title", "description"]:
		if not value.get(field) is String or value[field].strip_edges().is_empty() or value[field].length() > 4000: return "Texto de campaña inválido: " + field
	if not value.get("missions") is Array or value.missions.is_empty() or value.missions.size() > MAX_MISSIONS: return "La campaña necesita entre 1 y 24 misiones."
	if JSON.stringify(value, "", true, true).to_utf8_buffer().size() > MAX_BYTES: return "La campaña supera 512 KiB."
	var preceding: Array = []
	for mission in value.missions:
		var error = Catalog.validate_mission(mission)
		if not error.is_empty(): return "Misión %d: %s" % [preceding.size() + 1, error]
		if mission.id in preceding: return "Identificador de misión duplicado: " + mission.id
		if mission.has("requires"):
			if not mission.requires is Array or mission.requires.size() > MAX_MISSIONS: return "Dependencias de misión inválidas."
			var unique: Array = []
			for dependency in mission.requires:
				if not dependency is String or dependency not in preceding or dependency in unique: return "Cada dependencia debe ser única y señalar una misión anterior: " + mission.id
				unique.append(dependency)
		preceding.append(mission.id)
	return ""

static func create() -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "id": "campaign_" + Crypto.new().generate_random_bytes(6).hex_encode(), "title": "Una nueva expedición", "description": "Traza las misiones que compartirá la tripulación.", "missions": [new_mission()]}

static func new_mission() -> Dictionary:
	return {"id": "mission_" + Crypto.new().generate_random_bytes(6).hex_encode(), "title": "Rumbo al faro", "sector": "Mar de Argi", "briefing": "Acerca la Itsaso al faro de llegada para abrir la siguiente etapa.", "reward": 100, "contacts": [{"id": "faro", "name": "Faro de llegada", "kind": "beacon", "position": [650, 0], "known": true}], "objectives": [{"type": "navigate", "target": "faro", "text": "Llega a menos de 250 m del faro."}]}

static func runtime_id(document: Dictionary, mission_id: String) -> String:
	# The source identifiers are preserved in exported content; only gameplay
	# identifiers are namespaced, without truncation collisions or built-in IDs.
	return "custom_" + (document.id + ":" + mission_id).sha256_text().left(56)

static func playable_missions(document: Dictionary) -> Array:
	var result: Array = document.missions.duplicate(true)
	for mission in result:
		mission.id = runtime_id(document, mission.id)
		mission.erase("requires")
	return result

static func unlocked(document: Dictionary, index: int, completed: Array) -> bool:
	if index < 0 or index >= document.missions.size(): return false
	var mission: Dictionary = document.missions[index]
	# Absence keeps the classic linear campaign. Explicit [] enables a root.
	var dependencies: Array = mission.get("requires", [] if index == 0 else [document.missions[index - 1].id])
	for dependency in dependencies:
		if runtime_id(document, dependency) not in completed: return false
	return true

static func replace_mission(document: Dictionary, index: int, mission: Dictionary) -> Dictionary:
	if index < 0 or index >= document.missions.size(): return {"error": "Misión inexistente."}
	var candidate = document.duplicate(true)
	var old_id: String = candidate.missions[index].id
	candidate.missions[index] = mission.duplicate(true)
	if mission.get("id") != old_id:
		for item in candidate.missions:
			if item.get("requires") is Array:
				for i in item.requires.size():
					if item.requires[i] == old_id: item.requires[i] = mission.get("id")
	return checked(candidate)

static func remove_mission(document: Dictionary, index: int) -> Dictionary:
	if index < 0 or index >= document.missions.size(): return {"error": "Misión inexistente."}
	var candidate = document.duplicate(true)
	var id: String = candidate.missions[index].id
	for mission in candidate.missions:
		if id in mission.get("requires", []): return {"error": "Otra misión depende de esta. Edita primero sus requisitos."}
	candidate.missions.remove_at(index)
	return checked(candidate)

static func move_mission(document: Dictionary, index: int, offset: int) -> Dictionary:
	var target = index + offset
	if index < 0 or index >= document.missions.size() or target < 0 or target >= document.missions.size(): return {"error": "No se puede mover más en esa dirección."}
	var candidate = document.duplicate(true)
	var mission = candidate.missions.pop_at(index)
	candidate.missions.insert(target, mission)
	return checked(candidate)

static func checked(document: Variant) -> Dictionary:
	var error = validate(document)
	return {"document": document.duplicate(true)} if error.is_empty() else {"error": error}

static func decode(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES: return {"error": "El archivo supera 512 KiB."}
	var parser = JSON.new()
	if parser.parse(text) != OK: return {"error": "JSON inválido en la línea %d: %s" % [parser.get_error_line() + 1, parser.get_error_message()]}
	return checked(parser.data)

static func read_document(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": "No se pudo abrir la campaña."}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"error": "El archivo supera 512 KiB."}
	var text = file.get_as_text()
	file.close()
	return decode(text)

static func write_document(document: Dictionary, path: String) -> String:
	var error = validate(document)
	if not error.is_empty(): return error
	var text = JSON.stringify(document, "  ", true, true)
	if text.to_utf8_buffer().size() > MAX_BYTES: return "El archivo supera 512 KiB."
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return "No se pudo abrir el archivo temporal."
	file.store_string(text)
	file.flush()
	var status = file.get_error()
	file.close()
	if status != OK: return "No se pudo escribir la campaña."
	if FileAccess.file_exists(path) and read_document(path).has("document"):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak")) != OK: return "No se pudo conservar la copia anterior."
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) != OK: return "No se pudo finalizar el guardado."
	return ""
