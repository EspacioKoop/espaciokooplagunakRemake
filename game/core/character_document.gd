class_name CharacterDocument
extends RefCounted
## Portable authored fields, never a savegame or an actor/profile replacement.

const FORMAT = "lagunak-character-template"
const VERSION = 1
const MAX_BYTES = 32 * 1024
const BUDGET = 12
const MAX_SKILL = 4
const MAX_NAME = 32

static func editable_from_profile(profile: Dictionary) -> Dictionary:
	var fields = {"name": profile.get("name", ""), "approach": profile.get("approach", ""),
		"skills": profile.get("skills", {}).duplicate(true)}
	# JSON save reloads and network snapshots can represent integers as floats.
	# A clean reopened draft and a matching acknowledgement must compare equally.
	var result = validate(document(fields))
	return result.document.character if result.ok else fields

static func document(fields: Dictionary) -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "character": fields.duplicate(true)}

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func _exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key in keys:
		if not value.has(key): return false
	return true

static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary: return _error("La plantilla debe ser un objeto JSON.")
	if not _exact_keys(value, ["format", "version", "character"]):
		return _error("Solo se permiten format, version y character; no datos de partida ni referencias.")
	if not value.format is String or value.format != FORMAT:
		return _error("Formato desconocido: se requiere " + FORMAT + ".")
	if not Catalog.finite_number(value.version) or value.version != VERSION:
		return _error("Versión incompatible: solo se admite la versión 1, sin migración implícita.")
	if not value.character is Dictionary: return _error("character debe ser un objeto.")
	var fields: Dictionary = value.character
	if not _exact_keys(fields, ["name", "approach", "skills"]):
		return _error("character solo admite name, approach y skills. La progresión no es importable.")
	if not fields.name is String: return _error("El nombre debe ser texto.")
	var name: String = fields.name
	if name.is_empty() or name.length() > MAX_NAME or name != name.strip_edges():
		return _error("Nombre: entre 1 y 32 caracteres, sin espacios en los extremos.")
	for index in name.length():
		var code = name.unicode_at(index)
		if code < 32 or (code >= 127 and code <= 159):
			return _error("El nombre no admite saltos de línea ni caracteres de control.")
	if not fields.approach is String or fields.approach not in ExpeditionSystems.APPROACHES:
		return _error("Enfoque desconocido: ingenio, temple, empatia o tecnica.")
	if not fields.skills is Dictionary or not _exact_keys(fields.skills, ExpeditionSystems.SKILLS):
		return _error("Se requieren exactamente las cinco habilidades actuales, sin referencias adicionales.")
	var skills: Dictionary = {}
	var total = 0
	for skill in ExpeditionSystems.SKILLS:
		var amount: Variant = fields.skills[skill]
		if not Catalog.finite_number(amount) or amount < 0 or amount > MAX_SKILL or float(amount) != floor(float(amount)):
			return _error("%s debe ser un entero entre 0 y 4." % skill.capitalize())
		skills[skill] = int(amount)
		total += int(amount)
	if total > BUDGET: return _error("Presupuesto excedido: %d/12 puntos. Reduce %d." % [total, total - BUDGET])
	var clean = {"name": name, "approach": fields.approach, "skills": skills}
	return {"ok": true, "message": "Plantilla válida.", "document": document(clean)}

static func command_args(fields: Dictionary) -> Dictionary:
	var result = validate(document(fields))
	if not result.ok: return {}
	var clean: Dictionary = result.document.character
	var args = {"name": clean.name, "approach": clean.approach}
	for skill in ExpeditionSystems.SKILLS: args[skill] = clean.skills[skill]
	return args

static func parse_text(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES: return _error("La plantilla supera el límite de 32 KiB.")
	var grammar = StrictJSON.new()
	var grammar_error = grammar.check(text)
	if not grammar_error.is_empty(): return _error(grammar_error)
	var parser = JSON.new()
	if parser.parse(text) != OK:
		return _error("JSON inválido en línea %d: %s" % [parser.get_error_line(), parser.get_error_message()])
	return validate(parser.data)

static func load_file(path: String) -> Dictionary:
	if path.is_empty(): return _error("Selecciona un archivo JSON.")
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return _error("No se puede abrir la plantilla (%s)." % error_string(FileAccess.get_open_error()))
	var length = file.get_length()
	if length > MAX_BYTES:
		file.close()
		return _error("La plantilla supera el límite de 32 KiB; no se ha leído su contenido.")
	var bytes = file.get_buffer(MAX_BYTES + 1)
	file.close()
	if bytes.size() > MAX_BYTES: return _error("La plantilla creció por encima de 32 KiB durante la lectura.")
	if not _valid_utf8(bytes): return _error("La plantilla no es texto UTF-8 válido.")
	var text = bytes.get_string_from_utf8()
	return parse_text(text)

static func _valid_utf8(bytes: PackedByteArray) -> bool:
	# Reject invalid bytes before Godot's decoder can log an engine error or
	# replace them. Includes overlong forms, UTF-16 surrogates and > U+10FFFF.
	var at = 0
	while at < bytes.size():
		var first = bytes[at]
		if first < 128:
			at += 1
			continue
		var width = 2 if first >= 0xc2 and first <= 0xdf else (3 if first >= 0xe0 and first <= 0xef else (4 if first >= 0xf0 and first <= 0xf4 else 0))
		if width == 0 or at + width > bytes.size(): return false
		for offset in range(1, width):
			if bytes[at + offset] < 0x80 or bytes[at + offset] > 0xbf: return false
		var second = bytes[at + 1]
		if first == 0xe0 and second < 0xa0: return false
		if first == 0xed and second >= 0xa0: return false
		if first == 0xf0 and second < 0x90: return false
		if first == 0xf4 and second >= 0x90: return false
		at += width
	return true

static func _export_path(path: String) -> Dictionary:
	if path.is_empty() or path.begins_with("res://"):
		return _error("No se permite escribir en res://. Elige una carpeta de usuario.")
	if not path.is_absolute_path() or (path.contains("://") and not path.begins_with("user://")):
		return _error("La exportación requiere una ruta absoluta o user://.")
	var absolute = ProjectSettings.globalize_path(path).simplify_path()
	if absolute.get_extension().to_lower() != "json": return _error("La plantilla debe tener extensión .json.")
	var project = ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	if absolute == project or absolute.begins_with(project + "/"):
		return _error("No se permite exportar dentro de los recursos del proyecto.")
	# Disallow symbolic links in every component, including aliases into res://.
	var cursor = absolute
	while cursor != cursor.get_base_dir():
		var parent = DirAccess.open(cursor.get_base_dir())
		if parent != null and parent.is_link(cursor.get_file()):
			return _error("La ruta de exportación no puede contener enlaces simbólicos.")
		cursor = cursor.get_base_dir()
	if not DirAccess.dir_exists_absolute(absolute.get_base_dir()):
		return _error("La carpeta de destino no existe.")
	if DirAccess.dir_exists_absolute(absolute): return _error("El destino es una carpeta, no un archivo.")
	for protected in [ExpeditionSystems.PATH, "user://campaign.json"]:
		var save_path = ProjectSettings.globalize_path(protected).simplify_path()
		if absolute == save_path or absolute.begins_with(save_path + "."):
			return _error("Una plantilla no puede sobrescribir partidas, temporales ni sus copias de seguridad.")
	return {"ok": true, "path": absolute}

static func save_file(path: String, fields: Dictionary) -> Dictionary:
	var result = validate(document(fields))
	if not result.ok: return result
	var destination = _export_path(path)
	if not destination.ok: return destination
	var text = JSON.stringify(result.document, "\t", true) + "\n"
	if text.to_utf8_buffer().size() > MAX_BYTES: return _error("La plantilla supera el límite de 32 KiB.")
	var absolute: String = destination.path
	# Same directory/filesystem: rename replaces atomically where supported.
	# Never delete/move the previous destination to work around a failed rename.
	var temporary = absolute + "." + Crypto.new().generate_random_bytes(12).hex_encode() + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _error("No se puede crear el archivo temporal (%s)." % error_string(FileAccess.get_open_error()))
	file.store_string(text)
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return _error("Falló la escritura; el archivo anterior sigue intacto.")
	var reread = load_file(temporary)
	if not reread.ok or reread.document != result.document:
		DirAccess.remove_absolute(temporary)
		return _error("Falló la verificación del temporal; el archivo anterior sigue intacto.")
	var rename_error = DirAccess.rename_absolute(temporary, absolute)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		return _error("No se pudo sustituir el destino (%s); no se eliminó el archivo anterior." % error_string(rename_error))
	var final = load_file(absolute)
	if not final.ok or final.document != result.document:
		return _error("El destino cambió después de exportarlo; no se puede confirmar la escritura.")
	return {"ok": true, "message": "Plantilla exportada y verificada. No incluye progresión ni identidad de red.", "document": result.document}


class StrictJSON:
	extends RefCounted
	## Godot's decoder accepts trailing commas and repeated keys. Check grammar
	## and decoded object keys before decoding, with a bounded nesting depth.
	var source: String
	var at = 0
	var problem = ""
	var number = RegEx.new()
	var string_token = RegEx.new()

	func check(text: String) -> String:
		source = text
		number.compile("-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?")
		string_token.compile('"(?:[^"\\\\\\x00-\\x1f]|\\\\(?:["\\\\/bfnrt]|u[0-9a-fA-F]{4}))*"')
		if not _value(0):
			return problem if not problem.is_empty() else "JSON estricto inválido cerca del carácter %d." % at
		_space()
		return "Contenido adicional después del JSON." if at != source.length() else ""

	func _space() -> void:
		while at < source.length() and source[at] in [" ", "	", "\n", "\r"]: at += 1

	func _take(token: String) -> bool:
		_space()
		if source.substr(at, token.length()) != token: return false
		at += token.length()
		return true

	func _string() -> String:
		_space()
		var found = string_token.search(source, at)
		if found == null or found.get_start() != at: return ""
		at = found.get_end()
		var token = found.get_string()
		var index = 1
		while index < token.length() - 1:
			if token[index] != "\\":
				index += 1
				continue
			if token[index + 1] != "u":
				index += 2
				continue
			var code = token.substr(index + 2, 4).hex_to_int()
			if code >= 0xd800 and code <= 0xdbff:
				if index + 12 > token.length() - 1 or token.substr(index + 6, 2) != "\\u":
					problem = "Escape Unicode sin pareja de sustitución válida."
					return ""
				var low = token.substr(index + 8, 4).hex_to_int()
				if low < 0xdc00 or low > 0xdfff:
					problem = "Escape Unicode sin pareja de sustitución válida."
					return ""
				index += 12
			elif code >= 0xdc00 and code <= 0xdfff:
				problem = "Escape Unicode de sustitución aislado."
				return ""
			else:
				index += 6
		return token

	func _value(depth: int) -> bool:
		if depth > 16:
			problem = "JSON demasiado anidado (máximo 16 niveles)."
			return false
		_space()
		if at >= source.length(): return false
		match source[at]:
			"{": return _object(depth + 1)
			"[": return _array(depth + 1)
			'"': return not _string().is_empty()
		for literal in ["true", "false", "null"]:
			if _take(literal): return true
		var found = number.search(source, at)
		if found == null or found.get_start() != at: return false
		at = found.get_end()
		return true

	func _object(depth: int) -> bool:
		at += 1
		if _take("}"): return true
		var keys: Dictionary = {}
		while at < source.length():
			var token = _string()
			if token.is_empty(): return false
			var key: Variant = JSON.parse_string(token)
			if not key is String: return false
			if keys.has(key):
				problem = "JSON con clave repetida: " + key.left(48) + "."
				return false
			keys[key] = true
			if not _take(":") or not _value(depth): return false
			if _take("}"): return true
			if not _take(","): return false
		return false

	func _array(depth: int) -> bool:
		at += 1
		if _take("]"): return true
		while at < source.length():
			if not _value(depth): return false
			if _take("]"): return true
			if not _take(","): return false
		return false
