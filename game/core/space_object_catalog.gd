class_name SpaceObjectCatalog
extends RefCounted
## Authoritative allowlist for authored space-object templates.
##
## The catalog is deliberately separate from ship_templates.json: PR #25 owns
## the 38 ship variants, while this file covers the still-missing station
## templates and their production contact/visual bridge.

const INDEX := "res://data/space_object_templates.json"
const FORMAT := "lagunak-space-object-templates"
const VERSION := 1
const MAX_TEMPLATES := 64
const MAX_DECISIONS := 64

static var _loaded := false
static var _document: Dictionary = {}
static var _entries: Dictionary = {}
static var _error := ""

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(INDEX):
		_error = "No existe el catálogo de objetos espaciales."
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	if not parsed is Dictionary:
		_error = "El catálogo de objetos espaciales no es un objeto JSON."
		return
	if parsed.get("format") != FORMAT or parsed.get("version") != VERSION:
		_error = "Formato/versiones incompatibles en el catálogo de objetos espaciales."
		return
	if not parsed.get("templates") is Array or parsed.templates.is_empty() or parsed.templates.size() > MAX_TEMPLATES:
		_error = "El catálogo de objetos espaciales no contiene una lista válida de plantillas."
		return
	if not parsed.get("decisions") is Array or parsed.decisions.size() > MAX_DECISIONS:
		_error = "Las decisiones del catálogo de objetos espaciales no son válidas."
		return
	var records := {}
	for record in parsed.templates:
		var record_error = _validate_record(record, true)
		if not record_error.is_empty():
			_error = record_error
			return
		if records.has(record.id):
			_error = "Plantilla de objeto espacial duplicada."
			return
		records[record.id] = record.duplicate(true)
	for decision in parsed.decisions:
		if not decision is Dictionary or not decision.get("id") is String or decision.id.is_empty() or not decision.get("source_name") is String or decision.source_name.is_empty() or decision.get("decision") != "exclude" or not decision.get("reason") is String or decision.reason.is_empty():
			_error = "Decisión de catálogo incompleta."
			return
		if records.has(decision.id):
			_error = "Una decisión reutiliza el ID de una plantilla incluida."
			return
	_document = parsed.duplicate(true)
	_entries = records

static func validation_error() -> String:
	_load()
	return _error

static func entries() -> Array:
	_load()
	return _entries.values().duplicate(true)

static func entry(template_id: String) -> Dictionary:
	_load()
	return _entries.get(template_id, {}).duplicate(true)

static func ids() -> Array[String]:
	_load()
	var result: Array[String] = []
	for record in entries():
		result.append(record.id)
	result.sort()
	return result

static func contact_from_template(template_id: String, contact_id: String, position: Array, known := true) -> Dictionary:
	var record = entry(template_id)
	if record.is_empty():
		return {"error": "Plantilla de objeto espacial desconocida."}
	if not _valid_identifier(contact_id) or position.size() != 2 or not _finite_number(position[0]) or not _finite_number(position[1]):
		return {"error": "Contacto de objeto espacial inválido."}
	return {
		"id": contact_id,
		"name": record.title,
		"kind": record.kind,
		"position": [float(position[0]), float(position[1])],
		"known": known,
		"space_object_template": record.id,
		"visual_model": record.visual_model,
		"space_object_hull_capacity": record.hull_capacity,
		"space_object_shields": record.shield_quadrants.duplicate(true)
	}

static func validate_contact(contact: Dictionary) -> String:
	if contact.has("space_object_template"):
		if not contact.space_object_template is String or contact.space_object_template.is_empty():
			return "La plantilla de objeto espacial debe ser texto."
		var record = entry(contact.space_object_template)
		if record.is_empty():
			return "Plantilla de objeto espacial desconocida."
		if contact.get("kind", "") != record.kind:
			return "La plantilla de objeto espacial no coincide con el tipo de contacto."
		if not contact.has("visual_model") or contact.visual_model != record.visual_model:
			return "La plantilla de objeto espacial requiere su recurso visual allowlistado."
	if contact.has("visual_model"):
		if not contact.visual_model is String or contact.visual_model.is_empty():
			return "El recurso visual del contacto debe ser texto."
		if not RuntimeAssetLibrary.compatible(contact.visual_model, str(contact.get("kind", ""))):
			return "El recurso visual no es compatible con el tipo de contacto."
	if contact.has("space_object_hull_capacity") and not _bounded_number(contact.space_object_hull_capacity, 0, 5000):
		return "La capacidad de casco del objeto espacial está fuera de rango."
	if contact.has("space_object_shields"):
		if not contact.space_object_shields is Array or contact.space_object_shields.is_empty() or contact.space_object_shields.size() > 4:
			return "El objeto espacial admite entre 1 y 4 cuadrantes de escudo."
		for shield in contact.space_object_shields:
			if not _bounded_number(shield, 0, 5000):
				return "El escudo del objeto espacial está fuera de rango."
	return ""

static func production_visual(template_id: String) -> String:
	return str(entry(template_id).get("visual_model", ""))

static func _validate_record(record: Variant, included: bool) -> String:
	if not record is Dictionary:
		return "Plantilla de objeto espacial inválida."
	for key in ["id", "source_name", "title", "kind", "role", "visual_model", "decision", "reason"]:
		if not record.has(key) or not record[key] is String or record[key].is_empty():
			return "Falta el campo de plantilla: " + key
	if not _valid_identifier(record.id) or record.kind != "station" or record.decision != "include":
		return "Identidad o decisión inválida en plantilla de objeto espacial."
	if not _bounded_number(record.get("hull_capacity", -1), 1, 5000) or not _bounded_number(record.get("radius_m", -1), 5, 2000):
		return "Capacidad o radio inválido en plantilla de objeto espacial."
	if not record.get("shield_quadrants") is Array or record.shield_quadrants.is_empty() or record.shield_quadrants.size() > 4:
		return "Los cuadrantes de una plantilla deben estar entre 1 y 4."
	for shield in record.shield_quadrants:
		if not _bounded_number(shield, 0, 5000):
			return "Escudo inválido en plantilla de objeto espacial."
	if not RuntimeAssetLibrary.compatible(record.visual_model, record.kind):
		return "El recurso visual de plantilla no está allowlistado para estaciones."
	return ""

static func _valid_identifier(value: Variant) -> bool:
	if not value is String:
		return false
	var expression := RegEx.new()
	expression.compile("^[a-zA-Z0-9_-]{1,64}$")
	return expression.search(value) != null

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _bounded_number(value: Variant, minimum: float, maximum: float) -> bool:
	return _finite_number(value) and float(value) >= minimum and float(value) <= maximum
