class_name ShipConfigurationDiff
extends RefCounted
## Read-only authoring comparison. Existing validators remain the rules authority.
## Never compare a whole simulation snapshot or serialize unknown design fields.

const SCOPE = "Solo se compara la estructura: identidad, casco, escudos, movilidad, capacidades clásicas y almacenes. Los montajes y los campos externos quedan fuera; esta comparación no importa ni aplica cambios."
const LABELS = {
 "id": "Identificador", "name": "Nombre", "hull": "Casco máximo",
 "front_shield": "Escudo de proa", "rear_shield": "Escudo de popa",
 "impulse": "Impulso · m/s", "reverse": "Factor de marcha atrás", "turn": "Viraje · grados/s",
 "acceleration": "Aceleración · m/s²", "warp_speed": "Velocidad por nivel warp",
 "jump_range": "Salto máximo · m", "radius": "Radio de colisión · m",
 "beam_arc": "Arco frontal de haces · grados", "beam_range": "Alcance de haces · m",
 "beam_damage": "Daño por pulso", "beam_cycle": "Recarga del haz · s", "missile_range": "Alcance de misiles · m",
 "ammo.homing": "Almacén · guiados", "ammo.nuke": "Almacén · nucleares", "ammo.mine": "Almacén · minas",
 "ammo.emp": "Almacén · EMP", "ammo.hvli": "Almacén · HVLI"
}

static func compare_designs(current: Variant, candidate: Variant) -> Dictionary:
 var error = ShipModel.validate_design(current)
 if not error.is_empty(): return {"error": "Borrador actual: " + error}
 error = ShipModel.validate_design(candidate)
 if not error.is_empty(): return {"error": "Estructura del archivo: " + error}
 var changes: Array = []
 for key in ["id", "name"]:
  _append_change(changes, key, current[key], candidate[key])
 for key in ShipModel.DESIGN_LIMITS:
  _append_change(changes, key, current[key], candidate[key])
 for ammo in ShipOperations.AMMO:
  _append_change(changes, "ammo." + ammo, current.ammo[ammo], candidate.ammo[ammo])
 return {"changes": changes, "fields_compared": 2 + ShipModel.DESIGN_LIMITS.size() + ShipOperations.AMMO.size(), "legacy": false}

static func compare_document(current: Variant, text: String) -> Dictionary:
 var error = ShipModel.validate_design(current)
 if not error.is_empty(): return {"error": "Borrador actual: " + error}
 var decoded = LoadoutDocument.decode(text)
 if decoded.has("error"): return {"error": decoded.error}
 var result = compare_designs(current, decoded.design)
 if not result.has("error"): result.legacy = decoded.legacy
 return result

static func compare_file(current: Variant, path: String) -> Dictionary:
 var error = ShipModel.validate_design(current)
 if not error.is_empty(): return {"error": "Borrador actual: " + error}
 if path.contains("://") and not path.begins_with("user://") and not path.begins_with("res://"):
  return {"error": "Selecciona un archivo local de diseño de nave."}
 var file = FileAccess.open(path, FileAccess.READ)
 if file == null: return {"error": "No se pudo abrir el archivo local."}
 if file.get_length() > LoadoutDocument.MAX_BYTES:
  file.close()
  return {"error": "El diseño supera 64 KiB."}
 # Bound the read even if another process grows the file after get_length().
 var bytes = file.get_buffer(LoadoutDocument.MAX_BYTES + 1)
 file.close()
 if bytes.size() > LoadoutDocument.MAX_BYTES: return {"error": "El diseño supera 64 KiB."}
 return compare_document(current, bytes.get_string_from_utf8())

static func _append_change(changes: Array, path: String, before: Variant, after: Variant) -> void:
 # Exact numeric equality ignores JSON's int/float representation, not small edits.
 if before is String:
  if before == after: return
 elif float(before) == float(after):
  return
 var change = {"path": path, "before": before, "after": after}
 if not before is String: change.difference = float(after) - float(before)
 changes.append(change)

static func to_text(result: Dictionary) -> String:
 if result.has("error"):
  return "No se puede comparar.\n" + str(result.error) + "\n\n" + SCOPE
 var lines = PackedStringArray(["ESTRUCTURA · BORRADOR ACTUAL → ARCHIVO", SCOPE, ""])
 lines.append("Documento de nave v1 (heredado)." if result.legacy else "Comparación de capacidades estructurales.")
 lines.append("%d campos comparados; %d diferencias." % [result.fields_compared, result.changes.size()])
 if result.changes.is_empty(): lines.append("Sin diferencias en la estructura comparada.")
 for change in result.changes:
  lines.append("")
  lines.append("%s [%s]" % [LABELS.get(change.path, change.path), change.path])
  # JSON string escaping keeps embedded newlines/control characters in one value.
  # The UI displays plain text, never BBCode/HTML from imported content.
  lines.append("  Actual:  " + JSON.stringify(change.before, "", true, true))
  lines.append("  Archivo: " + JSON.stringify(change.after, "", true, true))
  if change.has("difference"):
   lines.append("  Cambio:  " + ("+" if change.difference > 0 else "") + JSON.stringify(change.difference, "", true, true))
 return "\n".join(lines)
