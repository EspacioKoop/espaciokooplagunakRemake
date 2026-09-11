extends SceneTree
## Synthetic catalog only: no HYG download, player save, network or canon decision.

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("COSMOGRAPHY_NAVIGATION_FAIL " + label)

func equivalent(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a, "", true, true)) == JSON.parse_string(JSON.stringify(b, "", true, true))

func localized(es: String, en: String) -> Dictionary:
	return {"es": es, "en": en}

func provenance(source: String, license: String = "MIT") -> Dictionary:
	return {"kind": "original", "source": source, "license": license}

func entry(id: String, type: String, name: String, parent_id: String, map_ref: String, source: String) -> Dictionary:
	var result := {
		"id": id,
		"type": type,
		"name": localized(name, name),
		"summary": localized("Nodo sintético de prueba.", "Synthetic test node."),
		"continuity": "homebrew",
		"provenance": provenance(source)
	}
	if not parent_id.is_empty():
		result.parent_id = parent_id
	if not map_ref.is_empty():
		result.map_ref = map_ref
	return result

func fixture() -> Dictionary:
	return {
		"format": "espaciokoop-cosmography",
		"version": 1,
		"entries": [
			entry("home", "plane", "Hogar", "", "map-home", "synthetic-home"),
			entry("sol", "star_system", "Sol", "home", "map-sol", "synthetic-sol"),
			entry("earth", "planet", "Tierra", "sol", "map-earth", "synthetic-earth"),
			entry("auri", "star_system", "Auri", "home", "map-auri", "synthetic-auri"),
			entry("lyra", "planet", "Lyra", "auri", "map-lyra", "synthetic-lyra")
		]
	}

func navigation_fixture() -> Dictionary:
	return {
		"format": "espaciokoop-cosmography-navigation",
		"version": 1,
		"connections": [
			{"id": "home-sol", "from_id": "home", "to_id": "sol", "map_ref": "route-home-sol", "bidirectional": true},
			{"id": "sol-earth", "from_id": "sol", "to_id": "earth", "map_ref": "route-sol-earth", "bidirectional": true},
			{"id": "sol-auri", "from_id": "sol", "to_id": "auri", "map_ref": "route-sol-auri", "bidirectional": true},
			{"id": "auri-lyra", "from_id": "auri", "to_id": "lyra", "map_ref": "route-auri-lyra", "bidirectional": true}
		]
	}

func run() -> void:
	var catalog := fixture()
	var navigation := navigation_fixture()
	var catalog_before := catalog.duplicate(true)
	var navigation_before := navigation.duplicate(true)
	check(CosmographyCatalog.validate(catalog).is_empty(), "hierarchical fixture validates")
	var created := CosmographyNavigation.create(catalog, navigation)
	check(created.ok, "read adapter opens validated catalog and connections")
	if not created.ok:
		print("COSMOGRAPHY_NAVIGATION_RESULT checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	var adapter: CosmographyNavigation = created.adapter
	check(equivalent(catalog, catalog_before), "opening is read-only for catalog input")
	check(equivalent(navigation, navigation_before), "opening is read-only for navigation input")
	var earth_marker := adapter.marker("earth")
	check(earth_marker.ok, "marker resolves existing planet")
	check(earth_marker.marker.map_ref == "map-earth", "marker exposes stable map_ref")
	check(earth_marker.marker.provenance.source == "synthetic-earth", "marker preserves entry provenance")
	check(adapter.markers().size() == 5, "all mapped catalog entries are readable markers")
	var route := adapter.route("earth", "lyra")
	check(route.ok, "route crosses system hierarchy")
	check(route.path == ["earth", "sol", "auri", "lyra"], "route follows shortest connected path")
	check(route.edges.size() == 3, "route carries one map_ref per connection")
	check(route.edges[1].map_ref == "route-sol-auri", "route preserves connection map_ref")
	check(route.markers[0].provenance.source == "synthetic-earth", "route preserves origin provenance")
	check(route.markers[-1].provenance.source == "synthetic-lyra", "route preserves destination provenance")
	check(adapter.route("lyra", "earth").ok, "bidirectional connection is readable in reverse")
	var returned_marker: Dictionary = earth_marker.marker
	returned_marker.provenance.source = "MUTATED_OUTPUT_ONLY"
	returned_marker.map_ref = "mutated-map"
	check(adapter.marker("earth").marker.map_ref == "map-earth", "marker output cannot mutate adapter")
	check(adapter.marker("earth").marker.provenance.source == "synthetic-earth", "provenance output cannot mutate adapter")
	var returned_route: Dictionary = route
	returned_route.edges[0].map_ref = "mutated-route"
	check(adapter.route("earth", "lyra").edges[0].map_ref == "route-sol-earth", "route output cannot mutate adapter")
	for bad in [null, [], {}, {"format": "other", "version": 1, "connections": []}]:
		check(not CosmographyNavigation.create(catalog, bad).ok, "reject malformed navigation document")
	var bad := navigation.duplicate(true)
	bad.connections[0].map_ref = "../private"
	check(not CosmographyNavigation.create(catalog, bad).ok, "reject unsafe connection map_ref")
	bad = navigation.duplicate(true)
	bad.connections[0].to_id = "missing"
	check(not CosmographyNavigation.create(catalog, bad).ok, "reject missing endpoint")
	bad = navigation.duplicate(true)
	bad.connections[1].id = bad.connections[0].id
	check(not CosmographyNavigation.create(catalog, bad).ok, "reject duplicate connection ID")
	bad = navigation.duplicate(true)
	bad.connections[0].bidirectional = "yes"
	check(not CosmographyNavigation.create(catalog, bad).ok, "reject non-boolean direction")
	bad = navigation.duplicate(true)
	bad.connections[0].from_id = bad.connections[0].to_id
	check(not CosmographyNavigation.create(catalog, bad).ok, "reject self-loop")
	var no_marker_catalog := catalog.duplicate(true)
	no_marker_catalog.entries[2].erase("map_ref")
	check(CosmographyCatalog.validate(no_marker_catalog).is_empty(), "catalog may contain non-mapped entries")
	check(not CosmographyNavigation.create(no_marker_catalog, navigation).ok, "navigation requires map_ref at connected endpoints")
	var disconnected := navigation.duplicate(true)
	disconnected.connections.remove_at(2)
	disconnected.connections.remove_at(2)
	var disconnected_adapter := CosmographyNavigation.create(catalog, disconnected)
	check(disconnected_adapter.ok, "disconnected valid graph opens")
	if disconnected_adapter.ok:
		check(not disconnected_adapter.adapter.route("earth", "lyra").ok, "unreachable destination is rejected")
	check(not adapter.marker("missing").ok, "unknown marker is rejected")
	check(not adapter.route("earth", "missing").ok, "unknown route endpoint is rejected")
	print("COSMOGRAPHY_NAVIGATION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
