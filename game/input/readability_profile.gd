extends RefCounted
## Independent, local-only preferences. Never part of a campaign or snapshot.
const FORMAT = "lagunak-readability"
const VERSION = 1
const PERCENTAGES = [100, 115, 130, 150]
const MAX_BYTES = 1024

static func defaults() -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "text_percent": 100}

static func validate(value: Variant) -> String:
	if not value is Dictionary: return "El perfil de legibilidad debe ser un objeto."
	if value.size() != 3 or not value.has_all(["format", "version", "text_percent"]):
		return "El perfil de legibilidad tiene campos desconocidos o incompletos."
	if not value.format is String or value.format != FORMAT:
		return "Formato de legibilidad no reconocido."
	if typeof(value.version) not in [TYPE_INT, TYPE_FLOAT] or float(value.version) != float(VERSION):
		return "Versión de legibilidad no compatible."
	if typeof(value.text_percent) not in [TYPE_INT, TYPE_FLOAT]:
		return "El tamaño del texto debe ser un número."
	# JSON numbers are floats; Array membership distinguishes them from integers.
	# Bound and check integrality before conversion, without truncating fractions.
	var percent = float(value.text_percent)
	if not is_finite(percent) or percent < 100.0 or percent > 150.0:
		return "Elige un tamaño de texto de 100, 115, 130 o 150 %."
	if percent != floorf(percent) or int(percent) not in PERCENTAGES:
		return "Elige un tamaño de texto de 100, 115, 130 o 150 %."
	return ""

static func _local_path(path: String) -> bool:
	return path.begins_with("user://") and not path.contains("..") and not path.contains("\\") and path.ends_with(".json")

static func load_file(path: String) -> Dictionary:
	var fallback = {"profile": defaults(), "error": ""}
	if not _local_path(path):
		fallback.error = "La configuración sólo puede leerse del directorio local del juego."
		return fallback
	if not FileAccess.file_exists(path): return fallback
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		fallback.error = "No se pudo leer la configuración de legibilidad."
		return fallback
	if file.get_length() > MAX_BYTES:
		file.close()
		fallback.error = "La configuración de legibilidad supera el límite de tamaño."
		return fallback
	var text = file.get_as_text()
	file.close()
	var parser = JSON.new()
	if parser.parse(text) != OK:
		fallback.error = "La configuración de legibilidad no contiene JSON válido."
		return fallback
	var error = validate(parser.data)
	if not error.is_empty():
		fallback.error = error
		return fallback
	return {"profile": {"format": FORMAT, "version": VERSION, "text_percent": int(parser.data.text_percent)}, "error": ""}

static func save_file(path: String, value: Variant) -> Error:
	if not _local_path(path) or not validate(value).is_empty(): return ERR_INVALID_PARAMETER
	var document = defaults()
	document.text_percent = int(value.text_percent)
	var temporary = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(document, "\t") + "\n")
	file.flush()
	var error = file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK: DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	return error
