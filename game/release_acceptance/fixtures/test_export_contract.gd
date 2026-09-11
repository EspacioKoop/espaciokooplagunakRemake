extends SceneTree
## Read the embedded release metadata and resources, never a loose project.
var checks = 0
var failures = 0

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("EXPORT_CONTRACT_FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var expected = ""
	var fixtures_hash = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--expected-version="):
			expected = argument.trim_prefix("--expected-version=")
		if argument.begins_with("--expected-fixtures="):
			fixtures_hash = argument.trim_prefix("--expected-fixtures=")
	check(not expected.is_empty(), "explicit version required")
	check(ProjectSettings.get_setting("application/config/version", "") == expected, "embedded application version matches package")
	check(OS.has_feature("template") and not OS.has_feature("editor"), "actual exported application, not editor")
	check(DisplayServer.get_name() != "headless", "real display available")
	for path in ["res://main.tscn", "res://ui/tactical_board_3d.gd", "res://ui/sound_captions.gd", "res://world/ship_deck_layout.gd", "res://data/runtime_asset_library.json", "res://assets/models/itsasargi_pack/manifest.json", "res://assets/models/bizi_planets/manifest.json", "res://assets/models/portu_environments/manifest.json", "res://assets/models/orbita_pack/player_batch/manifest.json"]:
		check(ResourceLoader.exists(path) if not path.ends_with(".json") else FileAccess.file_exists(path), "embedded resource exists: " + path)
	check(fixtures_hash.length() == 64 and fixtures_hash.is_valid_hex_number(), "explicit fixture manifest hash required")
	check(FileAccess.get_sha256("res://data/release_acceptance_sources.json") == fixtures_hash, "embedded fixtures match the source revision under test")
	var shell = load("res://main.tscn").instantiate()
	root.add_child(shell)
	check(shell.find_children("*", "Label", true, false).any(func(label): return label.text == "ITSASO  /  " + expected), "visible application footer matches package version")
	shell.queue_free()
	await process_frame
	await process_frame
	print("EXPORT_CONTRACT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
