extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("COSMOGRAPHY_SERVICE_FAIL " + label)

func settle() -> void:
	for _i in 4: await process_frame

func run() -> void:
	var session: Node = root.get_node("Session")
	session.suppress_saves = true
	await settle()
	check(session.cosmography != null and session.cosmography.catalog_ready, "el servicio carga el catálogo empaquetado")
	if session.cosmography == null or not session.cosmography.catalog_ready:
		_finish()
		return
	session.new_campaign()
	await settle()
	var projection: Dictionary = session.view.get("cosmography", {})
	check(projection.get("ready", false), "la sesión proyecta cosmografía en su vista")
	check(projection.get("markers", []).size() == 5, "la vista expone los marcadores cosmográficos")
	var route: Dictionary = session.cosmography.route("itsasargi", "izarren-bidea")
	check(route.get("ok", false), "existe una ruta entre sistemas")
	check(route.get("path", []).size() == 3, "la ruta conserva los tres sistemas del recorrido")
	var selected: Dictionary = session.cosmography.select_location("egunsenti", "egunsenti-puerto")
	check(selected.get("ok", false), "se puede seleccionar sistema y planeta")
	var checkpoint: Dictionary = session.sim.state.duplicate(true)
	check(checkpoint.get("cosmography", {}).get("current_system_id", "") == "egunsenti", "la selección se copia al estado de campaña")
	var restored: Dictionary = session.cosmography.restore_from_state(checkpoint)
	check(restored.get("ok", false), "la ubicación se restaura desde un checkpoint")
	check(session.cosmography.persistence.snapshot().get("current_planet_id", "") == "egunsenti-puerto", "la restauración conserva el planeta")
	var hyg := "proper,dist,mag,spect\nSirius,2.64,-1.46,A1\nVega,7.68,0.03,A0"
	var imported: Dictionary = session.cosmography.validate_import(hyg, 10, "4.3")
	check(imported.get("ok", false), "el importador HYG valida un CSV compatible")
	var entries: Array = imported.get("catalog", {}).get("entries", [])
	check(entries.size() == 3, "el importador HYG conserva dos estrellas y el plano raíz")
	check(entries[1].get("provenance", {}).get("license", "") == "CC BY-SA-4.0", "cada entrada importada conserva su licencia")
	check(str(entries[1].get("provenance", {}).get("source_url", "")).begins_with("https://"), "la procedencia importada exige URL HTTPS")
	var json_import: Dictionary = session.cosmography.validate_import(JSON.stringify(session.cosmography.catalog))
	check(json_import.get("ok", false), "el importador JSON valida el catálogo propio")
	_finish()

func _finish() -> void:
	print("COSMOGRAPHY_SERVICE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
