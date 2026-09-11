class_name CosmographyService
extends Node
## Campaign-facing bridge for the validated cosmography contracts.
## It keeps catalog data read-only and stores only the selected location in saves.

const CATALOG_PATH := "res://data/cosmography_catalog.json"
const NAVIGATION_PATH := "res://data/cosmography_navigation.json"
const CATALOG_ID := "lagunak-homebrew-v1"

var catalog: Dictionary = {}
var navigation: Dictionary = {}
var adapter: CosmographyNavigation
var persistence: CosmographyPersistence
var session: Node
var catalog_ready := false
var last_error := ""

func _ready() -> void:
	_load_catalog()

func bind_session(value: Node) -> void:
	session = value

func _load_catalog() -> void:
	var catalog_data: Variant = _read_json(CATALOG_PATH)
	var navigation_data: Variant = _read_json(NAVIGATION_PATH)
	if not catalog_data is Dictionary or not navigation_data is Dictionary:
		last_error = "No se pudo leer el catálogo cosmográfico empaquetado."
		return
	var created: Dictionary = CosmographyNavigation.create(catalog_data, navigation_data)
	if not created.get("ok", false):
		last_error = str(created.get("error", "Catálogo cosmográfico inválido."))
		return
	var stored: Dictionary = CosmographyPersistence.create(catalog_data, CATALOG_ID)
	if not stored.get("ok", false):
		last_error = str(stored.get("error", "No se pudo crear la persistencia cosmográfica."))
		return
	catalog = catalog_data
	navigation = navigation_data
	adapter = created.get("adapter") as CosmographyNavigation
	persistence = stored.get("model") as CosmographyPersistence
	var initial: Dictionary = persistence.select_location("itsasargi", "itsasargi-principal")
	if not initial.get("ok", false):
		last_error = str(initial.get("error", "No se pudo seleccionar la ubicación inicial."))
		return
	catalog_ready = true

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	var text := file.get_as_text()
	file.close()
	return JSON.parse_string(text)

func select_location(system_id: String, planet_id: String = "") -> Dictionary:
	if not catalog_ready: return {"ok": false, "message": last_error if not last_error.is_empty() else "La cosmografía no está lista."}
	var result: Dictionary = persistence.select_location(system_id, planet_id)
	if result.get("ok", false): _sync_to_session()
	return result

func route(from_id: String, to_id: String) -> Dictionary:
	if not catalog_ready: return {"ok": false, "error": last_error if not last_error.is_empty() else "La cosmografía no está lista."}
	return adapter.route(from_id, to_id)

func validate_import(content: String, maximum: int = 450, hyg_version: String = "4.x") -> Dictionary:
	return CosmographyCatalog.import_text(content, maximum, hyg_version)

func sync_to_state(state: Dictionary) -> void:
	if catalog_ready: state["cosmography"] = persistence.snapshot()

func restore_from_state(state: Dictionary) -> Dictionary:
	if not catalog_ready: return {"ok": false, "message": last_error if not last_error.is_empty() else "La cosmografía no está lista."}
	if not state.get("cosmography") is Dictionary:
		_sync_to_session()
		return {"ok": true, "message": "Ubicación cosmográfica inicial."}
	var restored: Dictionary = persistence.restore(JSON.stringify(state.cosmography))
	if restored.get("ok", false): return restored
	return {"ok": false, "message": str(restored.get("error", "Estado cosmográfico inválido."))}

func snapshot() -> Dictionary:
	if not catalog_ready: return {"ready": false, "error": last_error}
	return {
		"ready": true,
		"catalog_id": CATALOG_ID,
		"location": persistence.snapshot(),
		"markers": adapter.markers(),
		"routes": navigation.connections.duplicate(true)
	}

func _sync_to_session() -> void:
	if session != null and session.get("sim") is Simulation and not session.sim.state.is_empty():
		sync_to_state(session.sim.state)
