class_name NamedSaveStore
extends RefCounted
## Fixed private store; labels never become paths. No network or player credentials.

const DIRECTORY = "user://named-saves"
const RECOVERY = "user://named-save-recovery.lagunak"
const MAX_SLOTS = 32
const EXTENSION = ".lagunak"

static func can_manage(session: Node) -> bool:
	return session != null and session.mode in ["offline", "host"] and not session.suppress_saves

static func capture(session: Node, expedition: Node, label: String) -> Dictionary:
	if not can_manage(session) or expedition == null: return CampaignCheckpoint.failure("Los guardados pertenecen al equipo anfitrión.")
	var checkpoint = {"label": label, "saved_at": Time.get_unix_time_from_system(), "state": session.sim.state.duplicate(true), "expedition": expedition.data.duplicate(true), "event_cursor": expedition.checkpoint_cursor()}
	var encoded = CampaignCheckpoint.encode(checkpoint)
	if not encoded.ok: return encoded
	return {"ok": true, "checkpoint": checkpoint}

static func id_for(label: String) -> String:
	return label.to_lower().sha256_text() if CampaignCheckpoint.valid_label(label) else ""

static func _valid_id(id: String) -> bool:
	if id.length() != 64: return false
	for character in id:
		if character not in "0123456789abcdef": return false
	return true

static func _path(id: String) -> String:
	return DIRECTORY.path_join(id + EXTENSION) if _valid_id(id) else ""

static func _local_path(path: String) -> String:
	if path.is_empty() or path.begins_with("res://") or ("://" in path and not path.begins_with("user://")) or (not path.begins_with("user://") and not path.is_absolute_path()): return ""
	for index in path.length():
		if path.unicode_at(index) < 32: return ""
	var normalized = path.replace("\\", "/")
	if normalized.begins_with("//") or ".." in normalized.split("/"): return ""
	return ProjectSettings.globalize_path(normalized).simplify_path()

static func _is_link(path: String) -> bool:
	var current = path
	while not current.is_empty():
		var parent = current.get_base_dir()
		if parent == current: break
		var directory = DirAccess.open(parent)
		if directory != null and directory.is_link(current.get_file()): return true
		current = parent
	return false

static func _store_ready() -> String:
	if _is_link(ProjectSettings.globalize_path(DIRECTORY)): return "La carpeta de guardados no puede ser un enlace simbólico."
	if DirAccess.make_dir_recursive_absolute(DIRECTORY) != OK: return "No se pudo abrir la carpeta de guardados."
	if OS.get_name() in ["Linux", "macOS"] and FileAccess.set_unix_permissions(DIRECTORY, 448) != OK: return "No se pudieron proteger los guardados locales."
	return ""

static func read_file(path: String) -> Dictionary:
	var absolute = _local_path(path)
	if absolute.is_empty() or _is_link(absolute): return CampaignCheckpoint.failure("Selecciona un archivo local regular, no una URL o un enlace.")
	var file = FileAccess.open(absolute, FileAccess.READ)
	if file == null: return CampaignCheckpoint.failure("No se pudo leer el archivo local.")
	if file.get_length() > CampaignCheckpoint.MAX_BYTES:
		file.close()
		return CampaignCheckpoint.failure("El checkpoint supera 4 MiB.")
	var bytes = file.get_buffer(file.get_length())
	file.close()
	# Reject malformed UTF-8 before Godot's permissive decoder can replace bytes.
	var hashing = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	var digest = hashing.finish().hex_encode()
	if not _utf8(bytes): return {"ok": false, "message": "El archivo no contiene UTF-8 válido.", "digest": digest}
	var result = CampaignCheckpoint.decode(bytes.get_string_from_utf8())
	result.digest = digest
	return result

static func _utf8(bytes: PackedByteArray) -> bool:
	var index = 0
	while index < bytes.size():
		var first = bytes[index]
		if first == 0: return false
		if first < 128:
			index += 1
			continue
		var length = 2 if first >= 194 and first <= 223 else (3 if first >= 224 and first <= 239 else (4 if first >= 240 and first <= 244 else 0))
		if length == 0 or index + length > bytes.size(): return false
		for step in range(1, length):
			if bytes[index + step] < 128 or bytes[index + step] > 191: return false
		var second = bytes[index + 1]
		if (first == 224 and second < 160) or (first == 237 and second > 159) or (first == 240 and second < 144) or (first == 244 and second > 143): return false
		index += length
	return true

static func read_slot(id: String) -> Dictionary:
	if id == "recovery": return read_file(RECOVERY)
	var path = _path(id)
	if path.is_empty(): return CampaignCheckpoint.failure("Identificador de guardado inválido.")
	if _is_link(ProjectSettings.globalize_path(DIRECTORY)): return CampaignCheckpoint.failure("Carpeta de guardados no válida.")
	var result = read_file(path)
	if result.ok and id_for(result.checkpoint.label) != id: return {"ok": false, "message": "El nombre del guardado no coincide con su identificador.", "digest": result.digest}
	return result

static func list_entries() -> Array:
	var entries: Array = []
	if _is_link(ProjectSettings.globalize_path(DIRECTORY)): return entries
	var directory = DirAccess.open(DIRECTORY)
	if directory != null:
		var files = directory.get_files()
		files.sort()
		for filename in files:
			if entries.size() >= MAX_SLOTS: break
			if not filename.ends_with(EXTENSION): continue
			var id = filename.trim_suffix(EXTENSION)
			if not _valid_id(id): continue
			var result = read_slot(id)
			entries.append({"id": id, "ok": result.ok, "label": result.checkpoint.label if result.ok else "Guardado dañado · " + id.left(8), "saved_at": result.checkpoint.saved_at if result.ok else 0.0, "message": result.get("message", "")})
	entries.sort_custom(func(a, b): return a.saved_at > b.saved_at if a.saved_at != b.saved_at else a.id < b.id)
	if FileAccess.file_exists(RECOVERY):
		var result = read_slot("recovery")
		entries.push_front({"id": "recovery", "ok": result.ok, "label": "Recuperación anterior a la última carga", "saved_at": result.checkpoint.saved_at if result.ok else 0.0, "message": result.get("message", "")})
	return entries

static func _write(path: String, text: String, expected_digest: String = "") -> Dictionary:
	var absolute = _local_path(path)
	if absolute.is_empty() or _is_link(absolute) or DirAccess.dir_exists_absolute(absolute): return CampaignCheckpoint.failure("Destino local no válido.")
	if FileAccess.file_exists(absolute):
		if expected_digest.is_empty() or FileAccess.get_sha256(absolute) != expected_digest: return CampaignCheckpoint.failure("El archivo ya existe o ha cambiado. No se ha sobrescrito.")
	elif not expected_digest.is_empty(): return CampaignCheckpoint.failure("El archivo seleccionado ya no existe.")
	var temporary = absolute + ".tmp-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return CampaignCheckpoint.failure("No se pudo crear el archivo temporal.")
	if OS.get_name() in ["Linux", "macOS"] and FileAccess.set_unix_permissions(temporary, 384) != OK:
		file.close()
		DirAccess.remove_absolute(temporary)
		return CampaignCheckpoint.failure("No se pudieron proteger los datos del archivo.")
	file.store_string(text)
	file.flush()
	var error = file.get_error()
	file.close()
	var changed = (FileAccess.file_exists(absolute) and (expected_digest.is_empty() or FileAccess.get_sha256(absolute) != expected_digest)) or (not FileAccess.file_exists(absolute) and not expected_digest.is_empty())
	if error != OK or changed or DirAccess.rename_absolute(temporary, absolute) != OK:
		DirAccess.remove_absolute(temporary)
		return CampaignCheckpoint.failure("No se pudo finalizar la escritura; el archivo anterior se conserva.")
	return {"ok": true, "message": "Archivo guardado en este equipo."}

static func store(checkpoint: Dictionary, expected_digest: String = "") -> Dictionary:
	var encoded = CampaignCheckpoint.encode(checkpoint)
	if not encoded.ok: return encoded
	var error = _store_ready()
	if not error.is_empty(): return CampaignCheckpoint.failure(error)
	var id = id_for(checkpoint.label)
	if not FileAccess.file_exists(_path(id)):
		var entries = list_entries().filter(func(item): return item.id != "recovery")
		if entries.size() >= MAX_SLOTS: return CampaignCheckpoint.failure("Hay 32 guardados. Exporta o elimina uno antes de crear otro.")
	var result = _write(_path(id), encoded.text, expected_digest)
	if result.ok: result.id = id
	return result

static func export_slot(id: String, destination: String) -> Dictionary:
	var source = read_slot(id)
	if not source.ok: return source
	var absolute = _local_path(destination)
	var managed = ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/") + "/"
	# Exports cannot replace any app data or create a shadow slot in its private store.
	if absolute.is_empty() or absolute.to_lower().begins_with(managed.to_lower()): return CampaignCheckpoint.failure("Exporta a una carpeta externa a los datos privados del juego.")
	if not absolute.to_lower().ends_with(EXTENSION): return CampaignCheckpoint.failure("Usa la extensión .lagunak.")
	var encoded = CampaignCheckpoint.encode(source.checkpoint)
	return _write(absolute, encoded.text) if encoded.ok else encoded

static func remove_slot(id: String, expected_digest: String) -> Dictionary:
	var path = _path(id)
	if path.is_empty() or expected_digest.is_empty() or _is_link(ProjectSettings.globalize_path(DIRECTORY)) or _is_link(ProjectSettings.globalize_path(path)): return CampaignCheckpoint.failure("Guardado no válido para eliminar.")
	if FileAccess.get_sha256(path) != expected_digest: return CampaignCheckpoint.failure("El guardado ha cambiado; vuelve a seleccionarlo.")
	if DirAccess.remove_absolute(path) != OK: return CampaignCheckpoint.failure("No se pudo eliminar el guardado.")
	return {"ok": true, "message": "Guardado eliminado."}

static func preserve_recovery(checkpoint: Dictionary) -> Dictionary:
	var encoded = CampaignCheckpoint.encode(checkpoint)
	if not encoded.ok: return encoded
	var previous = FileAccess.get_sha256(RECOVERY) if FileAccess.file_exists(RECOVERY) else ""
	return _write(RECOVERY, encoded.text, previous)

static func install(checkpoint: Dictionary) -> Dictionary:
	# Stage both native files and back up existing disk bytes before replacing either.
	# Handled I/O failures roll back. The separate recovery checkpoint also preserves
	# the prior live state; a power loss between the two renames is not atomic.
	var error = CampaignCheckpoint.validate(checkpoint)
	if not error.is_empty(): return CampaignCheckpoint.failure(error)
	var prepared = LocalStorage.prepare_state(checkpoint.state)
	if not prepared.has("state"): return CampaignCheckpoint.failure(prepared.error)
	var state: Dictionary = prepared.state
	var payload = JSON.stringify(state, "", true, true)
	var flight = JSON.stringify({"format": "lagunak-save", "version": 1, "sha256": payload.sha256_text(), "payload": payload})
	if flight.to_utf8_buffer().size() > LocalStorage.MAX_BYTES: return CampaignCheckpoint.failure("El guardado de vuelo supera el límite nativo.")
	var expedition_document: Dictionary = checkpoint.expedition.duplicate(true)
	expedition_document._event_cursor = checkpoint.event_cursor.duplicate(true)
	var documents = {"user://campaign.json": flight, ExpeditionSystems.PATH: JSON.stringify(expedition_document, "\t", false, true)}
	var originals: Dictionary = {}
	var staged: Dictionary = {}
	for target in documents:
		var absolute = ProjectSettings.globalize_path(target)
		if _is_link(absolute) or DirAccess.dir_exists_absolute(absolute):
			_clean_staged(staged)
			return CampaignCheckpoint.failure("Un destino de campaña no es un archivo regular.")
		if FileAccess.file_exists(target):
			var file = FileAccess.open(target, FileAccess.READ)
			if file == null or file.get_length() > CampaignCheckpoint.MAX_BYTES:
				if file != null: file.close()
				_clean_staged(staged)
				return CampaignCheckpoint.failure("No se pudo preservar el archivo de campaña anterior.")
			originals[target] = file.get_buffer(file.get_length())
			file.close()
		else: originals[target] = null
		var temporary = target + ".restore-" + Crypto.new().generate_random_bytes(8).hex_encode()
		var write = _write(temporary, documents[target])
		if not write.ok:
			_clean_staged(staged)
			return write
		staged[target] = temporary
	for target in originals:
		if originals[target] == null: continue
		var backup = target + ".before-named-load"
		if _is_link(ProjectSettings.globalize_path(backup)) or DirAccess.dir_exists_absolute(backup) or DirAccess.copy_absolute(target, backup, 384) != OK:
			_clean_staged(staged)
			return CampaignCheckpoint.failure("No se pudo conservar la copia previa de disco.")
	var replaced: Array = []
	for target in staged:
		if DirAccess.rename_absolute(staged[target], target) != OK:
			var rollback_ok = true
			for original in replaced:
				if originals[original] == null:
					rollback_ok = DirAccess.remove_absolute(original) == OK and rollback_ok
				else:
					var file = FileAccess.open(original, FileAccess.WRITE)
					if file == null: rollback_ok = false; continue
					file.store_buffer(originals[original]); file.flush()
					rollback_ok = file.get_error() == OK and rollback_ok
					file.close()
			_clean_staged(staged)
			return CampaignCheckpoint.failure("No se pudo cargar. La partida en memoria no ha cambiado." + (" Recupera el checkpoint anterior antes de reiniciar." if not rollback_ok else ""))
		replaced.append(target)
	return {"ok": true, "state": state}

static func _clean_staged(staged: Dictionary) -> void:
	for path in staged.values():
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
