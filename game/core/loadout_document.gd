class_name LoadoutDocument
extends RefCounted
## Authoring boundary only. ShipArmaments remains the runtime and rules authority.

const FORMAT = "lagunak-ship"
const VERSION = 2
const MAX_BYTES = 65536
const MOUNT_FIELDS = ["id", "name", "kind", "arc_center", "arc", "range", "damage", "cycle", "energy"]

static func validate_loadout(value: Variant) -> String:
 var error = ShipArmaments.validate_loadout(value)
 if not error.is_empty(): return error
 if value.has("template") and (not value.template is String or value.template.length() > 64):
  return "Identificador de configuración inválido."
 for mount in value.mounts:
  for key in ["id", "name"]:
   if not mount[key] is String or mount[key].strip_edges().is_empty():
    return "Texto de montaje inválido: " + key
 return ""

static func authored_loadout(value: Dictionary) -> Dictionary:
 # Never serialize a target or a running cooldown as authored content.
 var mounts: Array = []
 for mount in value.mounts:
  var authored: Dictionary = {}
  for key in MOUNT_FIELDS: authored[key] = mount[key]
  mounts.append(authored)
 return {"template": value.get("template", "custom"), "mounts": mounts}

static func default_loadout() -> Dictionary:
 return authored_loadout(ShipArmaments.template("exploracion"))

static func encode(design: Dictionary, loadout: Dictionary) -> Dictionary:
 var error = ShipModel.validate_design(design)
 if error.is_empty(): error = validate_loadout(loadout)
 if not error.is_empty(): return {"error": error}
 var document = {"format": FORMAT, "version": VERSION, "design": design.duplicate(true), "loadout": authored_loadout(loadout)}
 # Match save/mission precision so fractional parameters survive a round trip.
 var text = JSON.stringify(document, "  ", true, true)
 if text.to_utf8_buffer().size() > MAX_BYTES: return {"error": "El diseño supera 64 KiB."}
 return {"text": text}

static func decode(text: String) -> Dictionary:
 if text.to_utf8_buffer().size() > MAX_BYTES: return {"error": "El diseño supera 64 KiB."}
 var parser = JSON.new()
 if parser.parse(text) != OK: return {"error": "El archivo no contiene JSON válido."}
 var document = parser.data
 if not document is Dictionary or document.get("format") != FORMAT or not Catalog.finite_number(document.get("version")) or (document.version != 1 and document.version != VERSION):
  return {"error": "Formato o versión de nave no reconocido."}
 var error = ShipModel.validate_design(document.get("design"))
 if not error.is_empty(): return {"error": error}
 # Version 1 contained structural capabilities only. Its runtime used Itsaso.
 var loadout = default_loadout() if document.version == 1 else document.get("loadout")
 error = validate_loadout(loadout)
 if not error.is_empty(): return {"error": error}
 return {"design": document.design.duplicate(true), "loadout": authored_loadout(loadout), "legacy": document.version == 1}
