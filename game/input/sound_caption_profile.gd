class_name SoundCaptionProfile
extends RefCounted
## Tiny local-only preference document. It is not part of campaign saves or RPCs.

const PATH = "user://sound_captions.json"
const MAX_BYTES = 4096
const DEFAULTS = {"version": 1, "enabled": true, "duration": 5.0}

static func normalize(value: Variant) -> Dictionary:
	var result = DEFAULTS.duplicate()
	if not value is Dictionary: return result
	var version: Variant = value.get("version")
	if not (version is int or version is float) or not is_finite(float(version)) or version != 1: return result
	if value.get("enabled") is bool: result.enabled = value.enabled
	var duration: Variant = value.get("duration")
	if (duration is int or duration is float) and is_finite(float(duration)) and duration >= 2.0 and duration <= 12.0:
		result.duration = float(duration)
	return result

static func _local_path(path: String) -> bool:
	return path.begins_with("user://") and path.trim_prefix("user://") == path.get_file() and path.ends_with(".json") and not path.contains("..") and not path.contains("\\")

static func read_profile(path: String = PATH) -> Dictionary:
	if not _local_path(path): return DEFAULTS.duplicate()
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return DEFAULTS.duplicate()
	if file.get_length() > MAX_BYTES:
		file.close()
		return DEFAULTS.duplicate()
	var text = file.get_as_text()
	file.close()
	var parser = JSON.new()
	if parser.parse(text) != OK: return DEFAULTS.duplicate()
	return normalize(parser.data)

static func write_profile(value: Dictionary, path: String = PATH) -> Error:
	if not _local_path(path): return ERR_INVALID_PARAMETER
	if value.size() != 3 or not value.get("enabled") is bool: return ERR_INVALID_PARAMETER
	var version: Variant = value.get("version")
	var duration: Variant = value.get("duration")
	if not (version is int or version is float) or not is_finite(float(version)) or version != 1: return ERR_INVALID_PARAMETER
	if not (duration is int or duration is float) or not is_finite(float(duration)) or duration < 2.0 or duration > 12.0: return ERR_INVALID_PARAMETER
	var temporary = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(normalize(value)))
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return error
	error = DirAccess.rename_absolute(temporary, path)
	if error != OK: DirAccess.remove_absolute(temporary)
	return error
