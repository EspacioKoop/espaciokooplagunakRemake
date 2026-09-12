extends SceneTree
## Synthetic catalog only: no HYG download, player save, network or canon decision.


const CosmographyNavigation = preload("res://core/cosmography_navigation.gd")
const CosmographyCatalog = preload("res://core/cosmography_catalog.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	print("COSMOGRAPHY_NAVIGATION_CHECK index=%d ok=%s" % [checks, str(value)])
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
	test_versions(adapter)
	if "--inject-failure" in OS.get_cmdline_user_args():
		check(false, "intentional negative control after the complete suite")
	print("COSMOGRAPHY_NAVIGATION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func test_versions(adapter: CosmographyNavigation) -> void:
	var markers_before := adapter.markers()
	var route_before := adapter.route("earth", "lyra")
	for catalog_version in [1, 1.0]:
		for navigation_version in [1, 1.0]:
			var catalog := fixture()
			var navigation := navigation_fixture()
			catalog.version = catalog_version
			navigation.version = navigation_version
			var opened := CosmographyNavigation.create(catalog, navigation)
			check(opened.ok, "all exact numeric catalog/navigation version combinations accepted")
			if opened.ok:
				check(equivalent(opened.adapter.route("earth", "lyra"), route_before), "numeric version variants preserve route semantics")
	var parsed_catalog: Variant = JSON.parse_string(JSON.stringify(fixture()))
	var parsed_navigation: Variant = JSON.parse_string(JSON.stringify(navigation_fixture()))
	check(typeof(parsed_catalog.version) == TYPE_FLOAT and typeof(parsed_navigation.version) == TYPE_FLOAT, "round-trip uses JSON floats")
	var round_trip := CosmographyNavigation.create(parsed_catalog, parsed_navigation)
	check(round_trip.ok, "round-tripped JSON catalog and navigation accepted")
	if round_trip.ok:
		check(equivalent(round_trip.adapter.markers(), markers_before), "JSON round-trip preserves markers and provenance")
		check(equivalent(round_trip.adapter.route("earth", "lyra"), route_before), "JSON round-trip preserves complete route")
	for version in [1.5, 1.0000000000000002, 0, 2, -1, true, false, "1", "1.0", null, [], [1], {}, {"value": 1}, INF, -INF, NAN]:
		for target in ["catalog", "navigation"]:
			var catalog := fixture()
			var navigation := navigation_fixture()
			if target == "catalog":
				catalog.version = version
			else:
				navigation.version = version
			var catalog_before := var_to_bytes(catalog)
			var navigation_before := var_to_bytes(navigation)
			check(not CosmographyNavigation.create(catalog, navigation).ok, target + " invalid version rejected")
			check(var_to_bytes(catalog) == catalog_before, "rejection cannot mutate catalog input")
			check(var_to_bytes(navigation) == navigation_before, "rejection cannot mutate navigation input")
			check(equivalent(adapter.markers(), markers_before), "rejection preserves live markers")
			check(equivalent(adapter.route("earth", "lyra"), route_before), "rejection preserves live route")
	for invalid in [null, [], {}, {"format": "espaciokoop-cosmography", "entries": []}]:
		check(not CosmographyNavigation.create(invalid, navigation_fixture()).ok, "malformed catalog rejected before shared validation")
	var missing_version := navigation_fixture()
	missing_version.erase("version")
	check(not CosmographyNavigation.create(fixture(), missing_version).ok, "missing navigation version rejected")
	# Mutating inputs after successful creation must not affect the accepted copy.
	var catalog := fixture()
	var navigation := navigation_fixture()
	var opened := CosmographyNavigation.create(catalog, navigation)
	check(opened.ok, "copy isolation fixture opens")
	if opened.ok:
		catalog.entries[2].provenance.source = "changed-input"
		navigation.connections.clear()
		check(equivalent(opened.adapter.route("earth", "lyra"), route_before), "caller mutations cannot alter accepted route")
