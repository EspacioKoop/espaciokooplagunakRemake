extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("COSMOGRAPHY_PERSISTENCE_FAIL " + label)

func catalog() -> Dictionary:
	return {
		"format": "espaciokoop-cosmography", "version": 1,
		"entries": [
			{"id": "real", "type": "plane", "name": {"es": "Espacio real", "en": "Real space"}, "summary": {"es": "Plano de prueba", "en": "Test plane"}, "continuity": "original", "provenance": {"kind": "original", "source": "test", "license": "MIT"}},
			{"id": "sol", "type": "star_system", "parent_id": "real", "name": {"es": "Sol", "en": "Sol"}, "summary": {"es": "Sistema de prueba", "en": "Test system"}, "continuity": "original", "provenance": {"kind": "original", "source": "test", "license": "MIT"}},
			{"id": "tierra", "type": "planet", "parent_id": "sol", "name": {"es": "Tierra", "en": "Earth"}, "summary": {"es": "Planeta de prueba", "en": "Test planet"}, "continuity": "original", "provenance": {"kind": "original", "source": "test", "license": "MIT"}}
		]
	}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var created := CosmographyPersistence.create(catalog(), "fixture-v1")
	check(created.ok, "valid catalog registers")
	var model: CosmographyPersistence = created.model
	check(model.select_location("sol", "tierra").ok, "valid planet selection")
	var encoded := model.serialize()
	var restored := CosmographyPersistence.create(catalog(), "fixture-v1").model
	check(restored.restore(encoded).ok, "round trip restores")
	check(restored.snapshot() == model.snapshot(), "round trip preserves location")
	check(not model.select_location("missing").ok, "unknown system rejected")
	check(not model.select_location("real").ok, "plane cannot be selected as system")
	check(not model.select_location("sol", "missing").ok, "unknown planet rejected")
	check(not model.select_location("sol", "real").ok, "wrong parent/type rejected")
	var invalid_map := catalog()
	invalid_map.entries[1].map_ref = "bad ref"
	check(not CosmographyPersistence.create(invalid_map, "fixture-v1").ok, "catalog map_ref rejected")
	var invalid_parent := catalog()
	invalid_parent.entries[2].parent_id = "real"
	check(not CosmographyPersistence.create(invalid_parent, "fixture-v1").ok, "catalog parent rejected")
	check(not restored.restore(JSON.stringify({"format": "bad"})).ok, "corrupt state rejected")
	check(not restored.restore(JSON.stringify({"format": "lagunak-cosmography-state", "version": 1, "catalog_id": "other", "current_system_id": "sol", "current_planet_id": "tierra"})).ok, "foreign catalog rejected")
	var before := restored.snapshot()
	check(not restored.restore(JSON.stringify({"format": "lagunak-cosmography-state", "version": 1, "catalog_id": "fixture-v1", "current_system_id": "sol", "current_planet_id": "missing"})).ok, "invalid restored planet rejected")
	check(restored.snapshot() == before, "failed restore does not mutate state")
	print("COSMOGRAPHY_PERSISTENCE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures else 0)
