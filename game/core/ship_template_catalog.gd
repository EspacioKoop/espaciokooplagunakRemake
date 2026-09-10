class_name ShipTemplateCatalog
extends RefCounted
## Authored configurations only. Runtime state remains owned by Session/Armaments.

const PATH = "res://data/ship_templates.json"
const NOTICE = "Adaptación de capacidades y haces; interiores, tubos y salto conservan los límites del remake. Escudo único dividido entre proa y popa."

static func entries() -> Array:
 var value = JSON.parse_string(FileAccess.get_file_as_string(PATH))
 if not value is Dictionary or value.get("format") != 1 or not value.get("templates") is Array: return []
 return value.templates

static func configuration(id: String) -> Dictionary:
 for record in entries():
  if record is Dictionary and record.get("id") == id: return from_record(record)
 return {"error": "Plantilla de nave desconocida."}

static func from_record(record: Dictionary) -> Dictionary:
 for field in ["id", "name"]:
  if not record.get(field) is String or record[field].is_empty(): return {"error": "Identidad de plantilla inválida."}
 if not record.get("shields") is Array or record.shields.size() not in [1, 2]: return {"error": "Sectores de escudo no representables."}
 if not record.get("speed") is Array or record.speed.size() != 3: return {"error": "Movimiento de plantilla inválido."}
 for value in record.shields + record.speed:
  if not Catalog.finite_number(value): return {"error": "Capacidad de plantilla inválida."}
 if not record.get("ammo") is Dictionary or not record.get("beams") is Array: return {"error": "Armamento de plantilla inválido."}
 var design = ShipModel.standard_design()
 design.id = record.id
 design.name = record.name
 design.hull = record.get("hull")
 design.front_shield = record.shields[0] if record.shields.size() == 2 else record.shields[0] / 2.0
 design.rear_shield = record.shields[1] if record.shields.size() == 2 else record.shields[0] / 2.0
 design.impulse = record.speed[0]
 design.turn = record.speed[1]
 design.acceleration = record.speed[2]
 design.warp_speed = record.get("warp_speed", 0)
 design.jump_range = 0.0
 # Each original beam exists once, in the modular loadout. Disable the legacy beam.
 design.beam_arc = 0.0
 design.beam_range = 0.0
 design.beam_damage = 0.0
 for ammo in ShipOperations.AMMO: design.ammo[ammo] = record.ammo.get(ammo, 0)
 var loadout = {"template": record.id, "mounts": []}
 for beam in record.beams:
  if not beam is Dictionary: return {"error": "Haz de plantilla inválido."}
  for field in ["index", "arc", "direction", "range", "cycle", "damage"]:
   if not Catalog.finite_number(beam.get(field)): return {"error": "Parámetro de haz inválido."}
  if beam.index < 0 or beam.index > 15 or floorf(beam.index) != beam.index: return {"error": "Índice de haz inválido."}
  loadout.mounts.append({"id": "beam_%d" % beam.index, "name": "Haz %d" % (beam.index + 1), "kind": "beam", "arc_center": fposmod(beam.direction + 180.0, 360.0) - 180.0, "arc": beam.arc, "range": beam.range, "cycle": beam.cycle, "damage": beam.damage, "energy": 10.0})
 var error = ShipModel.validate_design(design)
 if error.is_empty(): error = LoadoutDocument.validate_loadout(loadout)
 if not error.is_empty(): return {"error": error}
 return {"design": design, "loadout": loadout}
