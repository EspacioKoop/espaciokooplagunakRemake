class_name CosmographyPersistence
extends RefCounted
## Standalone persistence contract for CosmographyCatalog v1.
## Does not own ExpeditionSystems, Atlas, UI or navigation.

const CosmographyCatalog = preload("res://core/cosmography_catalog.gd")

const FORMAT := "lagunak-cosmography-state"
const VERSION := 1
const MAX_SERIALIZED_BYTES := 64 * 1024

var catalog: Dictionary = {}
var state: Dictionary = {
	"format": FORMAT,
	"version": VERSION,
	"catalog_id": "",
	"current_system_id": "",
	"current_planet_id": ""
}

static func create(catalog_data: Variant, catalog_id: String) -> Dictionary:
	var model = load("res://core/cosmography_persistence.gd").new()
	var result = model.register_catalog(catalog_data, catalog_id)
	if not result.ok:
		return result
	return {"ok": true, "model": model}

func register_catalog(catalog_data: Variant, catalog_id: String) -> Dictionary:
	if not catalog_id is String or catalog_id.strip_edges().is_empty():
		return _fail("catalog_id obligatorio.")
	# Guard before the shared validator: its legacy int() check is coercive.
	if not catalog_data is Dictionary or not _valid_version(catalog_data.get("version")):
		return _fail("Catálogo: versión cosmográfica no compatible.")
	var catalog_error := CosmographyCatalog.validate(catalog_data)
	if not catalog_error.is_empty():
		return _fail("Catálogo inválido: " + catalog_error)
	catalog = catalog_data.duplicate(true)
	state.catalog_id = catalog_id.strip_edges()
	state.current_system_id = ""
	state.current_planet_id = ""
	return {"ok": true}

func select_location(system_id: String, planet_id: String = "") -> Dictionary:
	if catalog.is_empty():
		return _fail("No hay catálogo registrado.")
	var lookup := CosmographyCatalog.by_id(catalog)
	if not lookup.has(system_id):
		return _fail("El sistema cosmográfico no existe.")
	if lookup[system_id].type != "star_system":
		return _fail("La ubicación principal debe ser un sistema estelar.")
	if not planet_id.is_empty():
		if not lookup.has(planet_id):
			return _fail("El planeta cosmográfico no existe.")
		if lookup[planet_id].type != "planet" or str(lookup[planet_id].parent_id) != system_id:
			return _fail("El planeta no pertenece al sistema seleccionado.")
	state.current_system_id = system_id
	state.current_planet_id = planet_id
	return {"ok": true}

func serialize() -> String:
	return JSON.stringify(state)

func restore(serialized: String) -> Dictionary:
	if serialized.to_utf8_buffer().size() > MAX_SERIALIZED_BYTES:
		return _fail("Estado cosmográfico demasiado grande.")
	var parser := JSON.new()
	if parser.parse(serialized) != OK:
		return _fail("Estado cosmográfico: JSON inválido.")
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return _fail("Estado cosmográfico inválido.")
	var validation := _validate_state(parsed)
	if not validation.is_empty():
		return _fail(validation)
	if str(parsed.catalog_id) != str(state.catalog_id):
		return _fail("El estado pertenece a otro catálogo.")
	if catalog.is_empty():
		return _fail("No hay catálogo registrado.")
	var selected := select_location(str(parsed.current_system_id), str(parsed.current_planet_id))
	if not selected.ok:
		return selected
	return {"ok": true}

func snapshot() -> Dictionary:
	return state.duplicate(true)

func _validate_state(value: Variant) -> String:
	if not value is Dictionary:
		return "Estado cosmográfico: debe ser un objeto."
	for key in value.keys():
		if key not in ["format", "version", "catalog_id", "current_system_id", "current_planet_id"]:
			return "Campo de estado no permitido: " + str(key)
	for key in ["format", "version", "catalog_id", "current_system_id", "current_planet_id"]:
		if not value.has(key):
			return "Falta campo de estado: " + key
	if value.format != FORMAT or not _valid_version(value.version):
		return "Formato o versión de estado no compatible."
	for key in ["catalog_id", "current_system_id", "current_planet_id"]:
		if not value[key] is String:
			return "Campo de estado inválido: " + key
	if str(value.catalog_id).strip_edges().is_empty():
		return "catalog_id no puede estar vacío."
	if str(value.current_system_id).is_empty():
		return "current_system_id no puede estar vacío."
	return ""

static func _valid_version(value: Variant) -> bool:
	# JSON represents numbers as floats. Do not coerce strings/bools or truncate.
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(value) and value == VERSION

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
