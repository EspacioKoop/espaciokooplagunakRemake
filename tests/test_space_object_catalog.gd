extends SceneTree

const SpaceObjectCatalog = preload("res://core/space_object_catalog.gd")
const Catalog = preload("res://core/catalog.gd")
const Simulation = preload("res://core/simulation.gd")
const LocalStorage = preload("res://core/storage.gd")
const MissionEditor = preload("res://ui/mission_editor.gd")
const RuntimeAssetLibrary = preload("res://core/runtime_asset_library.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SPACE_OBJECT_FAIL " + label)

func equivalent(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a, "", true, true)) == JSON.parse_string(JSON.stringify(b, "", true, true))

func station_mission() -> Dictionary:
	var station = SpaceObjectCatalog.contact_from_template("large_station", "yard", [650, 0], true)
	var beacon = {"id": "start", "name": "Baliza", "kind": "beacon", "position": [0, 0], "known": true}
	return {"id": "station_catalog_test", "title": "Catálogo de estaciones", "sector": "Prueba", "briefing": "Comprobar una estación catalogada.", "reward": 25,
		"contacts": [beacon, station], "objectives": [{"type": "dock", "target": "yard", "text": "Atraca en la estación catalogada."}]}

func run() -> void:
	check(SpaceObjectCatalog.validation_error().is_empty(), "station catalog parses")
	var records = SpaceObjectCatalog.entries()
	check(records.size() == 4, "four original station templates are included")
	check(SpaceObjectCatalog.ids() == ["huge_station", "large_station", "medium_station", "small_station"], "station IDs are deterministic")
	for record in records:
		check(record.decision == "include" and record.kind == "station", "included station decision " + record.id)
		check(record.shield_quadrants.size() >= 1 and record.shield_quadrants.size() <= 4, "station shield sectors are bounded " + record.id)
		check(RuntimeAssetLibrary.compatible(record.visual_model, "station"), "station visual is allowlisted " + record.id)
		var model = RuntimeAssetLibrary.contact_model(record.visual_model, "station", record.radius_m)
		check(model != null, "station visual instantiates " + record.id)
		if model != null:
			check(SpaceObjectCatalog.production_visual(record.id) == record.visual_model, "production visual bridge " + record.id)
			check(RuntimeAssetLibrary.bounds(model).size.length() > 0, "station visual has geometry " + record.id)
			model.free()
	var built = SpaceObjectCatalog.contact_from_template("small_station", "built_station", [200, -100], true)
	check(not built.has("error") and SpaceObjectCatalog.validate_contact(built).is_empty(), "template builds a valid station contact")
	var authored = station_mission()
	check(Catalog.validate_mission(authored).is_empty(), "editor contract accepts catalogued station")
	var bad = authored.duplicate(true)
	bad.contacts[1].visual_model = "base/asteroid"
	check(not Catalog.validate_mission(bad).is_empty(), "incompatible station visual rejected")
	bad = authored.duplicate(true)
	bad.contacts[1].kind = "hostile"
	check(not Catalog.validate_mission(bad).is_empty(), "template/contact kind mismatch rejected")
	bad = authored.duplicate(true)
	bad.contacts[1].space_object_template = "missing_station"
	check(not Catalog.validate_mission(bad).is_empty(), "unknown station template rejected")
	bad = authored.duplicate(true)
	bad.contacts[1].space_object_shields = [1, 2, 3, 4, 5]
	check(not Catalog.validate_mission(bad).is_empty(), "fifth shield sector rejected")
	bad = authored.duplicate(true)
	bad.contacts[1].space_object_hull_capacity = 5001
	check(not Catalog.validate_mission(bad).is_empty(), "oversized station capacity rejected")
	var campaign = Catalog.missions()
	var campaign_stations := 0
	for mission in campaign:
		check(Catalog.validate_mission(mission).is_empty(), "campaign still validates " + mission.id)
		for contact in mission.contacts:
			if contact.kind == "station":
				campaign_stations += 1
				check(contact.has("space_object_template") and not SpaceObjectCatalog.entry(contact.space_object_template).is_empty(), "campaign station resolves " + mission.id)
				check(RuntimeAssetLibrary.compatible(contact.visual_model, contact.kind), "campaign station visual resolves " + mission.id)
	check(campaign_stations == 6, "all six playable missions use station content")
	var sim := Simulation.new()
	sim.start(authored)
	check(sim.state.mission.id == "station_catalog_test", "simulation starts with catalogued station")
	var runtime_station: Dictionary = sim.contact("yard")
	check(runtime_station.get("space_object_template") == "large_station", "runtime contact keeps station template")
	check(runtime_station.get("visual_model") == "orbita/solar_array", "runtime contact keeps production visual")
	var save_path := "user://space-object-catalog-test.json"
	check(LocalStorage.save_state(sim.state, save_path).is_empty(), "station mission saves")
	var loaded = LocalStorage.read_state(save_path)
	check(loaded.has("state"), "station mission reloads")
	if loaded.has("state"):
		check(loaded.state.contacts[1].space_object_template == "large_station", "reload keeps station template")
		check(loaded.state.contacts[1].visual_model == "orbita/solar_array", "reload keeps station visual")
		check(LocalStorage.validate_state(loaded.state).is_empty(), "reloaded station state validates")
	var editor := MissionEditor.new()
	root.add_child(editor)
	await process_frame
	editor.set_mission(authored)
	editor._json.text = JSON.stringify(authored, "  ")
	editor._apply_json()
	check(editor.mission.contacts[1].space_object_template == "large_station", "mission editor imports station reference")
	check(editor._validate(), "mission editor validates station reference")
	editor._save()
	var editor_path: String = "user://missions/" + str(authored.id) + ".json"
	var saved_editor = JSON.parse_string(FileAccess.get_file_as_string(editor_path))
	check(saved_editor is Dictionary and saved_editor.contacts[1].space_object_template == "large_station", "mission editor saves station reference")
	check(saved_editor.contacts[1].visual_model == "orbita/solar_array", "mission editor saves visual reference")
	for path in [save_path, save_path + ".bak", editor_path, editor_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	editor.queue_free()
	print("SPACE_OBJECT_CATALOG_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
