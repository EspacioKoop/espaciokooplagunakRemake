extends SceneTree
## Verify the actual registered script and JSON boundaries, not a copied validator.
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("STORAGE_RUNTIME_FAIL " + label)

func run() -> void:
	var registered: GDScript = LocalStorage
	var explicit: GDScript = load("res://core/storage.gd")
	var disk_hash = FileAccess.get_sha256("res://core/storage.gd")
	var source_hash = registered.source_code.sha256_text()
	check(registered.resource_path == "res://core/storage.gd", "registered class path")
	check(registered == explicit, "global class resolves to the production resource")
	check(source_hash == disk_hash, "loaded source matches disk")
	var expected = OS.get_environment("STORAGE_EXPECTED_SHA256")
	check(expected.length() == 64 and disk_hash == expected, "runner and engine use identical source")
	print("STORAGE_RUNTIME_SOURCE " + JSON.stringify({"path": registered.resource_path, "sha256": disk_hash, "loaded_sha256": source_hash, "engine": Engine.get_version_info().string}))
	for size in [0, 1, 599, 600, 601, 4096]:
		var items: Array = []
		items.resize(size)
		var mapping: Dictionary = {}
		for index in size:
			mapping[str(index)] = index
		var before_array = var_to_bytes(items)
		var before_map = var_to_bytes(mapping)
		var array_ok = LocalStorage.validate_json(items)
		var map_ok = LocalStorage.validate_json(mapping)
		print("STORAGE_RUNTIME_BOUNDARY " + JSON.stringify({"size": size, "array": array_ok, "dictionary": map_ok}))
		check(array_ok == (size <= 600), "array boundary %d" % size)
		check(map_ok == (size <= 600), "dictionary boundary %d" % size)
		check(var_to_bytes(items) == before_array, "array input unchanged")
		check(var_to_bytes(mapping) == before_map, "dictionary input unchanged")
		check(LocalStorage.validate_json(JSON.parse_string(JSON.stringify(items))) == (size <= 600), "decoded array boundary")
		check(LocalStorage.validate_json(JSON.parse_string(JSON.stringify(mapping))) == (size <= 600), "decoded dictionary boundary")
	print("STORAGE_RUNTIME_RESULT " + JSON.stringify({"checks": checks, "failures": failures, "passed": failures == 0, "source_sha256": disk_hash}))
	quit(1 if failures else 0)
