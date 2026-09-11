class_name GMLiveState
extends RefCounted
## Optional v1 contact-membership delta. Source missions remain immutable.
const VERSION = 1
const MAX_CONTACTS = 48
const MAX_ADDED = 128
const MAX_AUDIT = 128
const OPERATIONS = ["spawn", "modify", "remove", "alert", "message", "damage", "repair", "reinforcements", "add_interior_trigger", "modify_interior_trigger", "remove_interior_trigger", "interior_trigger"]

static func defaults() -> Dictionary:
	return {"version": VERSION, "added": [], "removed": [], "audit": []}

static func number(value: Variant, low: float, high: float, integral: bool = false) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]: return false
	var n = float(value)
	return is_finite(n) and n >= low and n <= high and (not integral or n == floorf(n))

static func identifier(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 60: return false
	for ch in value:
		if ch not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	return true

static func protected_target(state: Dictionary, id: String) -> bool:
	for objective in state.get("mission", {}).get("objectives", []):
		if objective.get("target", "") == id: return true
	return false

static func all_ids(state: Dictionary) -> Array:
	var ids: Array = []
	for c in state.get("mission", {}).get("contacts", []): ids.append(c.id)
	ids.append_array(state.get("gm_live", {}).get("added", []))
	return ids

static func validate(state: Dictionary) -> String:
	var source = state.get("mission", {}).get("contacts")
	var contacts = state.get("contacts")
	if not source is Array or not contacts is Array or contacts.size() > MAX_CONTACTS:
		return "Lista de contactos de escena inválida."
	var original: Array = []
	for c in source:
		if not c is Dictionary or not c.get("id") is String or c.id in original:
			return "Catálogo fuente de contactos inválido."
		original.append(c.id)
	var expected = original.duplicate()
	if state.has("gm_live"):
		var data = state.gm_live
		if not data is Dictionary or data.size() != 4 or not data.has_all(["version", "added", "removed", "audit"]):
			return "Cabecera de dirección en vivo inválida."
		if not number(data.version, VERSION, VERSION, true): return "Versión de dirección en vivo incompatible."
		if not data.added is Array or data.added.size() > MAX_ADDED or not data.removed is Array or data.removed.size() > MAX_ADDED + MAX_CONTACTS:
			return "Registro de contactos de dirección demasiado grande."
		for id in data.added:
			if not identifier(id) or id in expected: return "Identificador añadido duplicado o inválido."
			expected.append(id)
		var known = expected.duplicate()
		for id in data.removed:
			if not id is String or id not in expected or protected_target(state, id):
				return "Retirada de contacto inválida o protegida por un objetivo."
			expected.erase(id)
		if not data.audit is Array or data.audit.size() > MAX_AUDIT: return "Auditoría de dirección inválida."
		var previous = -1.0
		for item in data.audit:
			if not item is Dictionary or item.size() != 4 or not item.has_all(["seq", "time", "operation", "target"]): return "Entrada de auditoría inválida."
			if not number(item.seq, 0, float(state.get("sequence", 0)), true) or float(item.seq) <= previous: return "Secuencia de auditoría inválida."
			if not number(item.time, 0, float(state.get("time", 0))): return "Tiempo de auditoría inválido."
			if not item.operation is String or item.operation not in OPERATIONS: return "Operación de auditoría desconocida."
			if not item.target is String or (not item.target.is_empty() and item.target not in known): return "Destino de auditoría inválido."
			previous = float(item.seq)
	var actual: Array = []
	for c in contacts:
		if not c is Dictionary or not c.get("id") is String or c.id in actual or c.id not in expected:
			return "Contacto vivo duplicado, no declarado o inválido."
		if c.has("visual_model") and (not c.visual_model is String or not RuntimeAssetLibrary.compatible(c.visual_model, str(c.get("kind", "")))):
			return "Modelo visual desconocido o incompatible."
		actual.append(c.id)
	if actual.size() != expected.size(): return "Falta un contacto de misión o de dirección."
	return ""

static func ensure(state: Dictionary) -> void:
	if not state.has("gm_live"): state.gm_live = defaults()
