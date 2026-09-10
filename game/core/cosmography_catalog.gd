class_name CosmographyCatalog
extends RefCounted
## Pure standalone implementation of the original cosmography v1 contract.
## No Foundry, filesystem, network or scene dependency.

const FORMAT = "espaciokoop-cosmography"
const VERSION = 1
const MAX_ENTRIES = 2000
const MAX_SERIALIZED_BYTES = 1024 * 1024
const TYPES = ["plane", "star_system", "planet"]
const CONTINUITIES = ["original", "homebrew", "spelljammer-5e", "spelljammer-legacy"]
const PROVENANCE_KINDS = ["original", "cc", "user_supplied"]
const ENTRY_KEYS = ["id", "type", "parent_id", "name", "summary", "continuity", "provenance", "map_ref"]
const ID_PATTERN = "^[a-z0-9][a-z0-9_-]{0,63}$"

static func empty_catalog() -> Dictionary:
 return {"format": FORMAT, "version": VERSION, "entries": []}

static func validate(catalog: Variant) -> String:
 if not catalog is Dictionary: return "$: debe ser un objeto."
 if JSON.stringify(catalog).to_utf8_buffer().size() > MAX_SERIALIZED_BYTES: return "$: el catálogo supera 1 MiB."
 for key in catalog.keys():
  if key not in ["format", "version", "entries"]: return "$: campo no permitido: " + str(key)
 for key in ["format", "version", "entries"]:
  if not catalog.has(key): return "$: falta " + key
 if catalog.format != FORMAT or int(catalog.version) != VERSION: return "$: formato o versión cosmográfica no compatible."
 if not catalog.entries is Array or catalog.entries.size() > MAX_ENTRIES: return "entries: se permiten hasta 2000 entradas."
 var by_id: Dictionary = {}
 for index in catalog.entries.size():
  var entry = catalog.entries[index]
  var error = _validate_entry(entry, index)
  if not error.is_empty(): return error
  if by_id.has(entry.id): return "entries[%d].id: ID duplicado." % index
  by_id[entry.id] = entry
 for index in catalog.entries.size():
  var entry: Dictionary = catalog.entries[index]
  if entry.type == "plane": continue
  if not by_id.has(entry.parent_id): return "entries[%d].parent_id: el padre no existe." % index
  var expected = "plane" if entry.type == "star_system" else "star_system"
  if by_id[entry.parent_id].type != expected: return "entries[%d].parent_id: el padre debe ser %s." % [index, expected]
 return ""

static func _validate_entry(entry: Variant, index: int) -> String:
 var path = "entries[%d]" % index
 if not entry is Dictionary: return path + ": debe ser un objeto."
 for key in entry.keys():
  if key not in ENTRY_KEYS: return path + ": campo no permitido: " + str(key)
 for key in ["id", "type", "name", "summary", "continuity", "provenance"]:
  if not entry.has(key): return path + ": falta " + key
 if not _valid_id(entry.id): return path + ".id: ID portable no válido."
 if entry.type not in TYPES: return path + ".type: tipo cosmográfico no admitido."
 if entry.type == "plane" and entry.has("parent_id"): return path + ".parent_id: un plano no admite padre."
 if entry.type != "plane" and (not entry.has("parent_id") or not _valid_id(entry.parent_id)): return path + ".parent_id: padre obligatorio o inválido."
 var name_error = _localized(entry.name, path + ".name", 120)
 if not name_error.is_empty(): return name_error
 var summary_error = _localized(entry.summary, path + ".summary", 600)
 if not summary_error.is_empty(): return summary_error
 if entry.continuity not in CONTINUITIES: return path + ".continuity: continuidad no admitida."
 var provenance_error = _provenance(entry.provenance, path + ".provenance")
 if not provenance_error.is_empty(): return provenance_error
 if entry.has("map_ref") and not _valid_id(entry.map_ref): return path + ".map_ref: ID de mapa no válido."
 return ""

static func _valid_id(value: Variant) -> bool:
 if not value is String: return false
 var regex = RegEx.new()
 regex.compile(ID_PATTERN)
 return regex.search(value) != null

static func _localized(value: Variant, path: String, maximum: int) -> String:
 if not value is Dictionary or value.keys().size() != 2 or not value.has("es") or not value.has("en"): return path + ": texto localizado requiere es/en."
 for language in ["es", "en"]:
  var text = value[language]
  if not text is String or text.is_empty() or text.length() > maximum or text != text.strip_edges(): return path + "." + language + ": texto inválido."
  if "<" in text or ">" in text or "\u0000" in text: return path + "." + language + ": texto inseguro."
 return ""

static func _provenance(value: Variant, path: String) -> String:
 if not value is Dictionary: return path + ": procedencia obligatoria."
 for key in value.keys():
  if key not in ["kind", "source", "license", "source_url"]: return path + ": campo de procedencia desconocido."
 for key in ["kind", "source", "license"]:
  if not value.has(key): return path + ": falta " + key
 if value.kind not in PROVENANCE_KINDS: return path + ".kind: procedencia no admitida."
 if not _plain(value.source, 160) or not _plain(value.license, 80): return path + ": fuente o licencia inválida."
 if value.has("source_url"):
  if not _plain(value.source_url, 500) or not str(value.source_url).begins_with("https://") or "@" in str(value.source_url).split("//", false, 1)[-1].split("/", false, 1)[0]: return path + ".source_url: debe ser HTTPS sin credenciales."
 elif value.kind == "cc": return path + ".source_url: contenido CC necesita URL de fuente."
 return ""

static func _plain(value: Variant, maximum: int) -> bool:
 return value is String and not value.is_empty() and value.length() <= maximum and value == value.strip_edges() and "<" not in value and ">" not in value

static func import_text(content: String, maximum: int = 450, hyg_version: String = "4.x") -> Dictionary:
 var trimmed = content.strip_edges()
 if trimmed.begins_with("{"):
  var parsed = JSON.parse_string(trimmed)
  if not parsed is Dictionary: return {"ok": false, "error": "JSON cosmográfico inválido."}
  var error = validate(parsed)
  return {"ok": error.is_empty(), "catalog": parsed if error.is_empty() else {}, "error": error}
 if _looks_like_hyg(content):
  var converted = from_hyg(content, maximum, hyg_version)
  var error = validate(converted)
  return {"ok": error.is_empty(), "catalog": converted if error.is_empty() else {}, "error": error}
 return {"ok": false, "error": "Formato no reconocido: se esperaba CSV HYG o JSON cosmográfico v1."}

static func _looks_like_hyg(content: String) -> bool:
 var lines = content.split("\n", false, 1)
 if lines.is_empty(): return false
 var header: Array = _csv_row(str(lines[0]).trim_suffix("\r"))
 var lowered: Array = []
 for value in header: lowered.append(str(value).strip_edges().to_lower())
 for required in ["proper", "dist", "mag", "spect"]:
  if required not in lowered: return false
 return true

static func from_hyg(content: String, maximum: int = 450, hyg_version: String = "4.x") -> Dictionary:
 maximum = clampi(maximum, 0, MAX_ENTRIES - 1)
 var lines = content.split("\n", false)
 var catalog = empty_catalog()
 catalog.entries.append({
  "id": "espacio-real", "type": "plane",
  "name": {"es": "Espacio real", "en": "Real space"},
  "summary": {"es": "Plano raíz del cielo real importado desde un catálogo estelar aportado por la persona usuaria.", "en": "Root plane for the real sky imported from a user-supplied stellar catalogue."},
  "continuity": "original",
  "provenance": {"kind": "original", "source": "Espaciokoop Lagunak Remake", "license": "GPL-2.0-or-later"}
 })
 if lines.is_empty(): return catalog
 var headers = _csv_row(str(lines[0]).trim_suffix("\r"))
 var indexes: Dictionary = {}
 for i in headers.size(): indexes[str(headers[i]).strip_edges().to_lower()] = i
 var stars: Array = []
 for line_index in range(1, lines.size()):
  var line = str(lines[line_index]).trim_suffix("\r")
  if line.strip_edges().is_empty(): continue
  var row = _csv_row(line)
  var proper = _cell(row, indexes, "proper").strip_edges()
  if proper.is_empty(): continue
  var dist_text = _cell(row, indexes, "dist").strip_edges()
  var mag_text = _cell(row, indexes, "mag").strip_edges()
  var spect = _cell(row, indexes, "spect").strip_edges()
  var dist = dist_text.to_float() if dist_text.is_valid_float() else -1.0
  var mag = mag_text.to_float() if mag_text.is_valid_float() else 99.0
  stars.append({"proper": proper, "dist": dist, "mag": mag, "spect": spect})
 stars.sort_custom(func(a, b): return float(a.mag) < float(b.mag))
 var used: Dictionary = {"espacio-real": true}
 for i in mini(maximum, stars.size()):
  var star: Dictionary = stars[i]
  var base = "hyg-" + _slug(star.proper)
  var id = base
  var suffix = 2
  while used.has(id):
   id = base.left(60) + "-" + str(suffix)
   suffix += 1
  used[id] = true
  var es_parts: Array[String] = []
  var en_parts: Array[String] = []
  if not str(star.spect).is_empty():
   es_parts.append("Tipo espectral " + str(star.spect))
   en_parts.append("Spectral type " + str(star.spect))
  if float(star.dist) > 0:
   es_parts.append("%.2f años luz" % (float(star.dist) * 3.26156))
   en_parts.append("%.2f light-years" % (float(star.dist) * 3.26156))
  if float(star.mag) < 90:
   es_parts.append("magnitud aparente %.2f" % float(star.mag))
   en_parts.append("apparent magnitude %.2f" % float(star.mag))
  if es_parts.is_empty():
   es_parts.append("Estrella con nombre propio registrada en HYG")
   en_parts.append("Properly named star recorded in HYG")
  catalog.entries.append({
   "id": id, "type": "star_system", "parent_id": "espacio-real",
   "name": {"es": star.proper, "en": star.proper},
   "summary": {"es": ". ".join(es_parts) + ".", "en": ". ".join(en_parts) + "."},
   "continuity": "original",
   "provenance": {"kind": "cc", "source": "HYG Database %s (AstroNexus)" % hyg_version.left(24), "license": "CC BY-SA-4.0", "source_url": "https://codeberg.org/astronexus/hyg"}
  })
 return catalog

static func _cell(row: Array, indexes: Dictionary, key: String) -> String:
 var index = int(indexes.get(key, -1))
 return str(row[index]) if index >= 0 and index < row.size() else ""

static func _slug(value: String) -> String:
 var source = value.to_lower()
 var result = ""
 for i in source.length():
  var ch = source.substr(i, 1)
  if ch >= "a" and ch <= "z" or ch >= "0" and ch <= "9": result += ch
  elif ch in [" ", "-", "_", ".", "/"] and not result.ends_with("-"): result += "-"
 result = result.trim_prefix("-").trim_suffix("-")
 if result.is_empty(): result = "estrella"
 return result.left(58)

static func _csv_row(line: String) -> Array:
 var result: Array = []
 var current = ""
 var quoted = false
 var i = 0
 while i < line.length():
  var ch = line.substr(i, 1)
  if ch == "\"":
   if quoted and i + 1 < line.length() and line.substr(i + 1, 1) == "\"":
    current += "\""
    i += 2
    continue
   quoted = not quoted
  elif ch == "," and not quoted:
   result.append(current)
   current = ""
  else:
   current += ch
  i += 1
 result.append(current)
 return result

static func by_id(catalog: Dictionary) -> Dictionary:
 var result: Dictionary = {}
 for entry in catalog.get("entries", []): result[entry.id] = entry
 return result

static func children(catalog: Dictionary, parent_id: String) -> Array:
 var result: Array = []
 for entry in catalog.get("entries", []):
  if str(entry.get("parent_id", "")) == parent_id: result.append(entry)
 return result

static func ancestry(catalog: Dictionary, id: String) -> Array:
 var lookup = by_id(catalog)
 if not lookup.has(id): return []
 var result: Array = []
 var cursor = id
 var guard = 0
 while lookup.has(cursor) and guard < 8:
  result.push_front(lookup[cursor])
  cursor = str(lookup[cursor].get("parent_id", ""))
  if cursor.is_empty(): break
  guard += 1
 return result
