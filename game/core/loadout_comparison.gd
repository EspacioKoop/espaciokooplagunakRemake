class_name LoadoutComparison
extends RefCounted
## Read-only authoring diff. Validation and migration belong to LoadoutDocument.

const FIELD_NAMES = {
 "name": "Nombre", "kind": "Tipo", "arc_center": "Orientación (°)",
 "arc": "Arco (°)", "range": "Alcance (m)", "damage": "Daño",
 "cycle": "Ciclo (s)", "energy": "Energía"
}

static func compare_text(current: Variant, text: String) -> Dictionary:
 var incoming = LoadoutDocument.decode(text)
 if incoming.has("error"): return {"error": incoming.error}
 var result = compare(current, incoming.loadout)
 if result.has("error"): return result
 result["legacy"] = incoming.legacy
 return result

static func compare(current: Variant, incoming: Variant) -> Dictionary:
 var error = LoadoutDocument.validate_loadout(current)
 if not error.is_empty(): return {"error": "Montajes actuales: " + error}
 error = LoadoutDocument.validate_loadout(incoming)
 if not error.is_empty(): return {"error": "Montajes propuestos: " + error}
 # This whitelist deliberately excludes target, cooldown and other runtime data.
 var before = LoadoutDocument.authored_loadout(current)
 var after = LoadoutDocument.authored_loadout(incoming)
 var left: Dictionary = {}
 var right: Dictionary = {}
 var old_ids: Array = []
 var new_ids: Array = []
 for mount in before.mounts:
  left[mount.id] = mount
  old_ids.append(mount.id)
 for mount in after.mounts:
  right[mount.id] = mount
  new_ids.append(mount.id)
 var changes: Array = []
 var added = 0
 var removed = 0
 var modified = 0
 var template_changed = before.template != after.template
 if template_changed:
  changes.append({"change": "template", "before": before.template, "after": after.template})
 for id in old_ids:
  if not right.has(id):
   removed += 1
   changes.append({"change": "removed", "id": id, "mount": left[id].duplicate(true)})
  else:
   var fields: Array = []
   for field in LoadoutDocument.MOUNT_FIELDS:
    if field == "id": continue
    if left[id][field] != right[id][field]:
     fields.append({"field": field, "before": left[id][field], "after": right[id][field]})
   if not fields.is_empty():
    modified += 1
    changes.append({"change": "modified", "id": id, "fields": fields})
 for id in new_ids:
  if not left.has(id):
   added += 1
   changes.append({"change": "added", "id": id, "mount": right[id].duplicate(true)})
 # Inserting/removing a mount does not count every shifted mount as reordered.
 var common_before: Array = []
 var common_after: Array = []
 for id in old_ids:
  if right.has(id): common_before.append(id)
 for id in new_ids:
  if left.has(id): common_after.append(id)
 var reordered = common_before != common_after
 if reordered:
  changes.append({"change": "order", "before": old_ids, "after": new_ids})
 return {"changes": changes, "added": added, "removed": removed, "modified": modified,
  "reordered": reordered, "template_changed": template_changed, "equal": changes.is_empty(), "legacy": false}

static func plain_report(result: Dictionary) -> String:
 if result.has("error"): return "No se pudo comparar. " + str(result.error)
 var lines = PackedStringArray([
  "COMPARACIÓN DE MONTAJES · actual → archivo",
  "Solo lectura. No cambia la misión ni la nave en juego.",
  "No compara estructura, casco, escudos ni almacenes de munición."
 ])
 if result.get("legacy", false):
  lines.append("AVISO: archivo v1; no contiene montajes. Se compara su configuración de exploración por defecto.")
 lines.append("")
 lines.append("Añadidos: %d · eliminados: %d · modificados: %d" % [result.added, result.removed, result.modified])
 if result.equal: lines.append("Sin diferencias en los montajes ni en la etiqueta de configuración.")
 for change in result.changes:
  lines.append("")
  match change.change:
   "template":
    lines.append("Etiqueta de configuración: %s → %s" % [_literal(change.before), _literal(change.after)])
   "added", "removed":
    lines.append(("AÑADIDO " if change.change == "added" else "ELIMINADO ") + _literal(change.id))
    for field in LoadoutDocument.MOUNT_FIELDS:
     if field != "id": lines.append("  %s: %s" % [FIELD_NAMES.get(field, field), _literal(change.mount[field])])
   "modified":
    lines.append("MODIFICADO " + _literal(change.id))
    for field in change.fields:
     lines.append("  %s: %s → %s" % [FIELD_NAMES.get(field.field, field.field), _literal(field.before), _literal(field.after)])
   "order":
    lines.append("ORDEN: %s → %s" % [_literal(change.before), _literal(change.after)])
 return "\n".join(lines)

static func _literal(value: Variant) -> String:
 # Quoting also escapes newlines/control characters in user-authored labels.
 # Full precision must not hide tiny but valid changes to cycles or arcs.
 return JSON.stringify(value, "", true, true)
