extends SceneTree


const CosmographyPersistence = preload("res://core/cosmography_persistence.gd")

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	print("COSMOGRAPHY_PERSISTENCE_CHECK index=%d ok=%s" % [checks, str(value)])
	if not value:
		failures += 1
		push_error("COSMOGRAPHY_PERSISTENCE_FAIL " + label)

func equivalent(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a, "", true, true)) == JSON.parse_string(JSON.stringify(b, "", true, true))

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
	if not created.ok:
		print("COSMOGRAPHY_PERSISTENCE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
		quit(1)
		return
	var model: CosmographyPersistence = created.model
	check(model.select_location("sol", "tierra").ok, "valid planet selection")
	var encoded := model.serialize()
	var restored: CosmographyPersistence = CosmographyPersistence.create(catalog(), "fixture-v1").model
	check(restored.restore(encoded).ok, "round trip restores")
	check(equivalent(restored.snapshot(), model.snapshot()), "round trip preserves location")
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
	check(equivalent(restored.snapshot(), before), "failed restore does not mutate state")
	test_versions(model)
	test_restore_boundaries(model)
	if "--inject-failure" in OS.get_cmdline_user_args():
		check(false, "intentional negative control after the complete suite")
	print("COSMOGRAPHY_PERSISTENCE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures else 0)

func test_versions(model: CosmographyPersistence) -> void:
	var before := model.snapshot()
	for version in [1, 1.0]:
		var valid := catalog()
		valid.version = version
		check(CosmographyPersistence.create(valid, "fixture-v1").ok, "exact numeric catalog version accepted")
		var document := before.duplicate(true)
		document.version = version
		check(model._validate_state(document).is_empty(), "exact numeric state version accepted")
		check(model.restore(JSON.stringify(document)).ok, "exact numeric state JSON restores")
		check(equivalent(model.snapshot(), before), "positive JSON equivalence")
	var parsed_catalog: Variant = JSON.parse_string(JSON.stringify(catalog()))
	check(typeof(parsed_catalog.version) == TYPE_FLOAT, "exercise real JSON numeric conversion")
	check(CosmographyPersistence.create(parsed_catalog, "fixture-v1").ok, "parsed JSON catalog accepted")
	var saved: Variant = JSON.parse_string(model.serialize())
	check(equivalent(saved, model.snapshot()), "serialized state preserves JSON semantics")
	for version in [1.5, 1.0000000000000002, 0, 2, -1, true, false, "1", "1.0", null, [], [1], {}, {"value": 1}, INF, -INF, NAN]:
		var invalid := catalog()
		invalid.version = version
		var input_before := var_to_bytes(invalid)
		check(not CosmographyPersistence.create(invalid, "fixture-v1").ok, "invalid catalog version rejected by create")
		check(not model.register_catalog(invalid, "replacement").ok, "invalid catalog version rejected by register")
		check(var_to_bytes(invalid) == input_before, "rejected catalog input untouched including non-finite values")
		check(equivalent(model.catalog, catalog()), "rejected registration preserves catalog")
		check(equivalent(model.snapshot(), before), "rejected registration preserves location and catalog ID")
		var document := before.duplicate(true)
		document.version = version
		input_before = var_to_bytes(document)
		check(not model._validate_state(document).is_empty(), "invalid state version rejected before conversion")
		check(var_to_bytes(document) == input_before, "state validation is read-only")
		# Non-finite numbers are not JSON values: raw overflow tokens are tested below.
		if not (typeof(version) == TYPE_FLOAT and not is_finite(version)):
			check(not model.restore(JSON.stringify(document, "", true, true)).ok, "invalid state version JSON rejected")
			check(equivalent(model.snapshot(), before), "version rejection preserves state")
	for token in ["1", "1.0", "1e0"]:
		check(model.restore(version_json(token)).ok, "equivalent numeric JSON token restores")
	for token in ["1.5", "1.0000000000000002", "true", "false", "\"1\"", "null", "[]", "{}", "1e309", "-1e309", "NaN", "Infinity", "-Infinity"]:
		check(not model.restore(version_json(token)).ok, "raw invalid version rejected without engine diagnostics")
		check(equivalent(model.snapshot(), before), "raw invalid version leaves state unchanged")

func version_json(token: String) -> String:
	return '{"format":"lagunak-cosmography-state","version":%s,"catalog_id":"fixture-v1","current_system_id":"sol","current_planet_id":"tierra"}' % token

func test_restore_boundaries(model: CosmographyPersistence) -> void:
	var before := model.snapshot()
	for raw in ["", "{", "not json", "[]", "null", "true", "1", "\"text\"", " ".repeat(CosmographyPersistence.MAX_SERIALIZED_BYTES + 1)]:
		check(not model.restore(raw).ok, "malformed or oversized state rejected")
		check(equivalent(model.snapshot(), before), "malformed rejection is atomic")
	for key in before.keys():
		var missing := before.duplicate(true)
		missing.erase(key)
		check(not model.restore(JSON.stringify(missing)).ok, "every state field is required")
		check(equivalent(model.snapshot(), before), "missing-field rejection is atomic")
	for key in ["catalog_id", "current_system_id", "current_planet_id"]:
		for invalid in [true, 1, [], {}, null]:
			var document := before.duplicate(true)
			document[key] = invalid
			check(not model.restore(JSON.stringify(document)).ok, "location strings are not coerced")
			check(equivalent(model.snapshot(), before), "typed field rejection is atomic")
	var extra := before.duplicate(true)
	extra.unexpected = true
	check(not model.restore(JSON.stringify(extra)).ok, "unknown state field rejected")
	check(equivalent(model.snapshot(), before), "unknown field rejection is atomic")
	for invalid in [null, [], {}, {"format": "espaciokoop-cosmography", "entries": []}]:
		check(not model.register_catalog(invalid, "replacement").ok, "malformed catalog rejected safely")
		check(equivalent(model.snapshot(), before) and equivalent(model.catalog, catalog()), "malformed catalog rejection is atomic")
