class_name AccessibilityProfile
extends RefCounted

## Full persistent profile for game accessibility options (text scaling, colorblind filters, reduced motion, captions).

const FORMAT = "lagunak-accessibility"
const VERSION = 1
const COLORBLIND_MODES = ["none", "protanopia", "deuteranopia", "tritanopia", "grayscale"]
const MAX_BYTES = 2048

static func defaults() -> Dictionary:
	return {
		"format": FORMAT,
		"version": VERSION,
		"text_percent": 100,
		"colorblind_mode": "none",
		"global_reduced_motion": false,
		"sound_captions": true
	}

static func validate(value: Variant) -> String:
	if not value is Dictionary: return "El perfil de accesibilidad debe ser un objeto."
	if not value.has_all(["format", "version", "text_percent", "colorblind_mode", "global_reduced_motion"]):
		return "El perfil de accesibilidad tiene campos incompletos."
	if not value.format is String or value.format != FORMAT:
		return "Formato de accesibilidad no reconocido."
	if typeof(value.version) not in [TYPE_INT, TYPE_FLOAT] or float(value.version) != float(VERSION):
		return "Versión de accesibilidad no compatible."
	var percent = float(value.text_percent)
	if not is_finite(percent) or percent < 90.0 or percent > 160.0:
		return "Tamaño de texto fuera de rango permitido."
	if not value.colorblind_mode is String or value.colorblind_mode not in COLORBLIND_MODES:
		return "Modo de daltonismo no válido."
	if not value.global_reduced_motion is bool:
		return "Opción de movimiento reducido debe ser booleana."
	return ""

static func _local_path(path: String) -> bool:
	return path.begins_with("user://") and not path.contains("..") and not path.contains("\\") and path.ends_with(".json")

static func load_file(path: String) -> Dictionary:
	var fallback = {"profile": defaults(), "error": ""}
	if not _local_path(path):
		fallback.error = "Ruta de configuración no permitida."
		return fallback
	if not FileAccess.file_exists(path): return fallback
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		fallback.error = "No se pudo abrir el perfil de accesibilidad."
		return fallback
	if file.get_length() > MAX_BYTES:
		file.close()
		fallback.error = "Perfil de accesibilidad demasiado grande."
		return fallback
	var text = file.get_as_text()
	file.close()
	var parser = JSON.new()
	if parser.parse(text) != OK:
		fallback.error = "Perfil de accesibilidad no contiene JSON válido."
		return fallback
	var error = validate(parser.data)
	if not error.is_empty():
		fallback.error = error
		return fallback
	var prof = defaults()
	prof.text_percent = int(parser.data.text_percent)
	prof.colorblind_mode = str(parser.data.colorblind_mode)
	prof.global_reduced_motion = bool(parser.data.global_reduced_motion)
	prof.sound_captions = bool(parser.data.get("sound_captions", true))
	return {"profile": prof, "error": ""}

static func save_file(path: String, value: Variant) -> Error:
	if not _local_path(path) or not validate(value).is_empty(): return ERR_INVALID_PARAMETER
	var doc = defaults()
	doc.text_percent = int(value.text_percent)
	doc.colorblind_mode = str(value.colorblind_mode)
	doc.global_reduced_motion = bool(value.global_reduced_motion)
	doc.sound_captions = bool(value.get("sound_captions", true))
	var temp = path + ".tmp"
	var file = FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(doc, "\t") + "\n")
	file.flush()
	var err = file.get_error()
	file.close()
	if err == OK:
		err = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path))
	if err != OK: DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
	return err
