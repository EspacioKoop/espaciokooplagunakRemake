class_name AvatarProfile
extends RefCounted
## Cosmetic preferences have no campaign, identity, role or progression authority.

const PATH = "user://avatar.json"
const MAX_BYTES = 512
const SUITS = {"classic": "Itsaso", "tide": "Marea", "ember": "Ascua", "orchid": "Orquídea"}
const VISORS = {"aqua": "Aguamarina", "gold": "Dorado", "ice": "Hielo"}
const GEAR = {"none": "Sin equipo", "survey": "Exploración", "workpack": "Trabajo"}
const SUIT_COLORS = {"classic": Color(0.71, 0.75, 0.72), "tide": Color("2c847e"), "ember": Color("ba683f"), "orchid": Color("8573a1")}
const VISOR_COLORS = {"aqua": Color(0.025, 0.34, 0.37), "gold": Color("a97322"), "ice": Color("719fc4")}

static func defaults() -> Dictionary:
	return {"format": "lagunak-avatar", "version": 1, "suit": "classic", "visor": "aqua", "gear": "none"}

static func validate(value: Variant) -> String:
	if not value is Dictionary: return "El avatar debe ser un objeto."
	if value.size() != 5: return "Campos de avatar no reconocidos."
	for key in defaults():
		if not value.has(key): return "Falta un campo de avatar."
	if not value.format is String or value.format != "lagunak-avatar": return "Formato de avatar no reconocido."
	if not (value.version is int or value.version is float) or value.version != 1: return "Versión de avatar no compatible."
	for entry in [["suit", SUITS], ["visor", VISORS], ["gear", GEAR]]:
		if not value[entry[0]] is String or not entry[1].has(value[entry[0]]): return "Selección de avatar no válida."
	return ""

static func decode(data: PackedByteArray) -> Dictionary:
	if data.is_empty() or data.size() > MAX_BYTES: return {"ok": false, "message": "El avatar supera el tamaño permitido."}
	var value = JSON.parse_string(data.get_string_from_utf8())
	var error = validate(value)
	return {"ok": error.is_empty(), "message": error, "profile": value if error.is_empty() else defaults()}

static func read_profile(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok": true, "message": "Avatar Itsaso.", "profile": defaults()}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "message": "No se pudo leer el avatar.", "profile": defaults()}
	var result = decode(file.get_buffer(MAX_BYTES + 1))
	file.close()
	if not result.ok: result.profile = defaults()
	return result

static func save_profile(value: Variant, path: String = PATH) -> String:
	var error = validate(value)
	if not error.is_empty(): return error
	var temporary = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return "No se pudo guardar el avatar."
	file.store_string(JSON.stringify(value))
	file.flush()
	var status = file.get_error()
	file.close()
	if status != OK:
		DirAccess.remove_absolute(temporary)
		return "No se pudo escribir el avatar."
	# Rename after a complete verified write; invalid input never truncates the old file.
	var verified = read_profile(temporary)
	if not verified.ok or verified.profile != value:
		DirAccess.remove_absolute(temporary)
		return "No se pudo verificar el avatar."
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return "No se pudo reemplazar el avatar guardado."
	return ""
